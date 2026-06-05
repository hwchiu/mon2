#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  onboard-external-k8s-hosts.sh \
    --cluster1-kubeconfig /path/to/cluster1.yaml \
    --cluster2-kubeconfig /path/to/cluster2.yaml \
    --cluster1-api-server https://10.70.10.10:6443 \
    --jumpbox azureuser@20.110.199.106 \
    [--ssh-user azureuser] \
    [--cluster-id cluster-2] \
    [--calicoctl-bin /path/to/calicoctl]

This script treats every node in cluster-2 as a Calico-managed external host.
It does not install Calico inside cluster-2 as a Kubernetes CNI or operator.
Instead, it:

1. Lists cluster-2 nodes and their internal IPs.
2. Creates placeholder Kubernetes Nodes in cluster-1 for the external hosts.
3. Creates matching Calico Node and HostEndpoint resources in cluster-1.
4. Installs Felix-only calico-node on each cluster-2 node.

Requirements:
  - kubectl, jq, ssh, scp, curl
  - cluster-1 must already have Calico policy-only running
  - cluster-1 kubeconfig can reach the Calico datastore
  - cluster-2 kubeconfig can list nodes
  - cluster-2 nodes must be reachable over SSH through the jumpbox
EOF
}

log() {
  printf '[onboard-external-k8s-hosts] %s\n' "$*"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

CLUSTER1_KUBECONFIG=""
CLUSTER2_KUBECONFIG=""
CLUSTER1_API_SERVER=""
JUMPBOX=""
SSH_USER="azureuser"
CLUSTER_ID="cluster-2"
CALICOCTL_BIN="${CALICOCTL_BIN:-/tmp/calicoctl-linux-amd64}"
CALICO_VERSION="${CALICO_VERSION:-3.32.0}"
POLICY_PROFILE="${POLICY_PROFILE:-baseline}"
HOST_INTERFACE="${HOST_INTERFACE:-eth0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster1-kubeconfig)
      CLUSTER1_KUBECONFIG="$2"
      shift 2
      ;;
    --cluster2-kubeconfig)
      CLUSTER2_KUBECONFIG="$2"
      shift 2
      ;;
    --cluster1-api-server)
      CLUSTER1_API_SERVER="$2"
      shift 2
      ;;
    --jumpbox)
      JUMPBOX="$2"
      shift 2
      ;;
    --ssh-user)
      SSH_USER="$2"
      shift 2
      ;;
    --cluster-id)
      CLUSTER_ID="$2"
      shift 2
      ;;
    --calicoctl-bin)
      CALICOCTL_BIN="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$CLUSTER1_KUBECONFIG" || -z "$CLUSTER2_KUBECONFIG" || -z "$CLUSTER1_API_SERVER" || -z "$JUMPBOX" ]]; then
  usage >&2
  exit 1
fi

need_cmd kubectl
need_cmd jq
need_cmd ssh
need_cmd scp
need_cmd curl

if [[ ! -f "$CLUSTER1_KUBECONFIG" ]]; then
  printf 'cluster-1 kubeconfig not found: %s\n' "$CLUSTER1_KUBECONFIG" >&2
  exit 1
fi

if [[ ! -f "$CLUSTER2_KUBECONFIG" ]]; then
  printf 'cluster-2 kubeconfig not found: %s\n' "$CLUSTER2_KUBECONFIG" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VM_RBAC_MANIFEST="${REPO_ROOT}/manifests/calico/vm-experiment/00-vm-agent-rbac.yaml"
BASELINE_MANIFEST="${REPO_ROOT}/manifests/calico/vm-experiment/20-host-baseline-allow-all.yaml"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ProxyJump="$JUMPBOX"
)

log "Applying cluster-1 RBAC and baseline allow profile"
kubectl --kubeconfig "$CLUSTER1_KUBECONFIG" apply -f "$VM_RBAC_MANIFEST" >/dev/null
kubectl --kubeconfig "$CLUSTER1_KUBECONFIG" apply -f "$BASELINE_MANIFEST" >/dev/null

log "Waiting for cluster-1 service account token"
for _ in $(seq 1 60); do
  TOKEN_B64="$(kubectl --kubeconfig "$CLUSTER1_KUBECONFIG" -n kube-system get secret calico-vm-agent-token -o jsonpath='{.data.token}' 2>/dev/null || true)"
  CA_B64="$(kubectl --kubeconfig "$CLUSTER1_KUBECONFIG" -n kube-system get secret calico-vm-agent-token -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)"
  if [[ -n "$TOKEN_B64" && -n "$CA_B64" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "${TOKEN_B64:-}" || -z "${CA_B64:-}" ]]; then
  printf 'cluster-1 calico-vm-agent-token is not ready\n' >&2
  exit 1
fi

TOKEN="$(printf '%s' "$TOKEN_B64" | base64 -d)"

cat >"$WORKDIR/cluster1-datastore.kubeconfig" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CA_B64}
    server: ${CLUSTER1_API_SERVER}
  name: cluster1-calico-datastore
contexts:
- context:
    cluster: cluster1-calico-datastore
    namespace: kube-system
    user: calico-vm-agent
  name: calico-vm-agent
current-context: calico-vm-agent
users:
- name: calico-vm-agent
  user:
    token: ${TOKEN}
EOF

if [[ ! -x "$CALICOCTL_BIN" ]]; then
  log "Downloading calicoctl ${CALICO_VERSION}"
  curl -fsSL -o "$CALICOCTL_BIN" "https://github.com/projectcalico/calico/releases/download/v${CALICO_VERSION}/calicoctl-linux-amd64"
  chmod +x "$CALICOCTL_BIN"
fi

CALICO_NODE_POD="$(kubectl --kubeconfig "$CLUSTER1_KUBECONFIG" -n kube-system get pods -l k8s-app=calico-node -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "$CALICO_NODE_POD" ]]; then
  printf 'unable to find a running calico-node pod on cluster-1\n' >&2
  exit 1
fi

log "Extracting calico-node binary from ${CALICO_NODE_POD}"
kubectl --kubeconfig "$CLUSTER1_KUBECONFIG" -n kube-system exec "$CALICO_NODE_POD" -- cat /bin/calico-node >"$WORKDIR/calico-node"
chmod +x "$WORKDIR/calico-node"

cat >"$WORKDIR/calico-node.service" <<'EOF'
[Unit]
Description=Calico Felix agent
After=syslog.target network.target

[Service]
User=root
EnvironmentFile=/etc/calico/calico.env
ExecStartPre=/usr/bin/mkdir -p /var/run/calico
ExecStart=/usr/local/bin/calico-node -felix
KillMode=process
Restart=on-failure
LimitNOFILE=32000

[Install]
WantedBy=multi-user.target
EOF

cat >"$WORKDIR/install-calico-node.sh" <<'EOF'
#!/usr/bin/env bash
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ipset conntrack libpcap0.8

if [[ ! -e /usr/lib/x86_64-linux-gnu/libpcap.so.1 ]] && [[ -e /usr/lib/x86_64-linux-gnu/libpcap.so.1.10.1 ]]; then
  ln -s /usr/lib/x86_64-linux-gnu/libpcap.so.1.10.1 /usr/lib/x86_64-linux-gnu/libpcap.so.1
fi

install -d -m 0755 /etc/calico /usr/local/bin
install -m 0755 "$SCRIPT_DIR/calico-node" /usr/local/bin/calico-node
install -m 0644 "$SCRIPT_DIR/calico-node.service" /etc/systemd/system/calico-node.service
install -m 0600 "$SCRIPT_DIR/calico.env" /etc/calico/calico.env
install -m 0600 "$SCRIPT_DIR/kubeconfig" /etc/calico/kubeconfig

systemctl daemon-reload
systemctl enable --now calico-node
systemctl is-active calico-node
EOF
chmod +x "$WORKDIR/install-calico-node.sh"

NODE_JSON="$WORKDIR/cluster2-nodes.json"
kubectl --kubeconfig "$CLUSTER2_KUBECONFIG" get nodes -o json >"$NODE_JSON"

mapfile -t NODE_ROWS < <(jq -r '.items[] | [.metadata.name, (.status.addresses[] | select(.type == "InternalIP") | .address)] | @tsv' "$NODE_JSON")

if [[ "${#NODE_ROWS[@]}" -eq 0 ]]; then
  printf 'cluster-2 returned zero nodes\n' >&2
  exit 1
fi

log "Found ${#NODE_ROWS[@]} cluster-2 nodes"

for row in "${NODE_ROWS[@]}"; do
  NODE_NAME="${row%%$'\t'*}"
  NODE_IP="${row#*$'\t'}"
  REMOTE_TARGET="${SSH_USER}@${NODE_IP}"

  if [[ -z "$NODE_NAME" || -z "$NODE_IP" ]]; then
    printf 'invalid node row: %s\n' "$row" >&2
    exit 1
  fi

  log "Registering ${NODE_NAME} (${NODE_IP}) in cluster-1"

  cat >"$WORKDIR/${NODE_NAME}-placeholder.yaml" <<EOF
apiVersion: v1
kind: Node
metadata:
  name: ${NODE_NAME}
  labels:
    kubernetes.io/hostname: ${NODE_NAME}
    lab.calico.io/non-cluster-host: "true"
    lab.calico.io/external-k8s-cluster: "${CLUSTER_ID}"
spec:
  unschedulable: true
  taints:
    - key: lab.calico.io/non-cluster-host
      value: "true"
      effect: NoSchedule
EOF
  kubectl --kubeconfig "$CLUSTER1_KUBECONFIG" apply -f "$WORKDIR/${NODE_NAME}-placeholder.yaml" >/dev/null

  cat >"$WORKDIR/${NODE_NAME}-calico.yaml" <<EOF
apiVersion: projectcalico.org/v3
kind: Node
metadata:
  name: ${NODE_NAME}
---
apiVersion: projectcalico.org/v3
kind: HostEndpoint
metadata:
  name: ${NODE_NAME}-${HOST_INTERFACE}
  labels:
    cluster_id: "${CLUSTER_ID}"
    cluster_kind: "kubernetes"
    endpoint_role: "k8s-node"
    host_name: "${NODE_NAME}"
    managed_as: "external-host"
    policy_profile: "${POLICY_PROFILE}"
spec:
  node: ${NODE_NAME}
  interfaceName: ${HOST_INTERFACE}
  expectedIPs:
    - ${NODE_IP}
EOF
  DATASTORE_TYPE=kubernetes KUBECONFIG="$CLUSTER1_KUBECONFIG" "$CALICOCTL_BIN" apply -f "$WORKDIR/${NODE_NAME}-calico.yaml" >/dev/null

  cat >"$WORKDIR/${NODE_NAME}-calico.env" <<EOF
FELIX_DATASTORETYPE=kubernetes
KUBECONFIG=/etc/calico/kubeconfig
CALICO_NODENAME=${NODE_NAME}
CALICO_IP=${NODE_IP}
NO_DEFAULT_POOLS=true
CALICO_NETWORKING_BACKEND=none
FELIX_HEALTHENABLED=true
FELIX_LOGSEVERITYSCREEN=Info
FELIX_XDPENABLED=false
EOF

  log "Installing Felix on ${NODE_NAME}"
  ssh "${SSH_OPTS[@]}" "$REMOTE_TARGET" 'mkdir -p "$HOME/onboard-calico"'
  scp "${SSH_OPTS[@]}" "$WORKDIR/calico-node" "$REMOTE_TARGET:~/onboard-calico/calico-node" >/dev/null
  scp "${SSH_OPTS[@]}" "$WORKDIR/calico-node.service" "$REMOTE_TARGET:~/onboard-calico/calico-node.service" >/dev/null
  scp "${SSH_OPTS[@]}" "$WORKDIR/install-calico-node.sh" "$REMOTE_TARGET:~/onboard-calico/install-calico-node.sh" >/dev/null
  scp "${SSH_OPTS[@]}" "$WORKDIR/cluster1-datastore.kubeconfig" "$REMOTE_TARGET:~/onboard-calico/kubeconfig" >/dev/null
  scp "${SSH_OPTS[@]}" "$WORKDIR/${NODE_NAME}-calico.env" "$REMOTE_TARGET:~/onboard-calico/calico.env" >/dev/null
  ssh "${SSH_OPTS[@]}" "$REMOTE_TARGET" 'chmod +x "$HOME/onboard-calico/install-calico-node.sh" && sudo "$HOME/onboard-calico/install-calico-node.sh"'
done

log "Cluster-1 external host inventory"
DATASTORE_TYPE=kubernetes KUBECONFIG="$CLUSTER1_KUBECONFIG" "$CALICOCTL_BIN" get nodes -o wide
kubectl --kubeconfig "$CLUSTER1_KUBECONFIG" get hostendpoints.crd.projectcalico.org -o wide

log "Cluster-2 node readiness"
kubectl --kubeconfig "$CLUSTER2_KUBECONFIG" get nodes -o wide
