#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  onboard-cilium-linux-external-workload.sh \
    --kubeconfig /path/to/cluster.yaml \
    --jumpbox azureuser@20.110.199.106 \
    --linux-target linux-hostname=10.70.20.30 \
    [--context hep-lab-k3s] \
    [--cilium-namespace kube-system] \
    [--ssh-user azureuser] \
    [--workload-name linux-hostname] \
    [--workload-namespace default] \
    [--ipv4-alloc-cidr 10.192.1.0/30] \
    [--labels lab.cilium.io/experiment=cilium-standalone,lab.cilium.io/host-kind=linux-external-workload,lab.cilium.io/zone=zone1] \
    [--service-type LoadBalancer] \
    [--vm-config key=value] \
    [--retries 4] \
    [--skip-clustermesh-enable]

This script automates as much of the deprecated Cilium external-workload path
as the older `cilium clustermesh vm ...` CLI supports:

1. Verifies the legacy `vm` subcommands are available.
2. Optionally runs `cilium clustermesh enable --enable-external-workloads`.
3. Creates or reuses the Linux `CiliumExternalWorkload`.
4. Generates the install script with `cilium clustermesh vm install`.
5. Copies the generated script to the Linux VM through the jumpbox.
6. Runs the install script on the Linux VM and prints resulting status.

Important limitations:
  - This is the deprecated external-workload path, not a supported replacement
    for Kubernetes node host firewall.
  - The target VM hostname must match the external workload name.
  - The script expects an older Cilium CLI that still exposes
    `cilium clustermesh vm create/install/status`.
EOF
}

log() {
  printf '[onboard-cilium-linux-external-workload] %s\n' "$*"
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "missing required command: $1"
  fi
}

parse_target() {
  local raw="$1"
  local __name_var="$2"
  local __ip_var="$3"
  local name="${raw%%=*}"
  local ip="${raw#*=}"

  if [[ -z "$name" || -z "$ip" || "$name" == "$raw" ]]; then
    die "target arguments must look like name=ip, got: $raw"
  fi

  printf -v "$__name_var" '%s' "$name"
  printf -v "$__ip_var" '%s' "$ip"
}

run_kubectl() {
  local cmd=(kubectl --kubeconfig "$KUBECONFIG")
  if [[ -n "$KUBE_CONTEXT" ]]; then
    cmd+=(--context "$KUBE_CONTEXT")
  fi
  "${cmd[@]}" "$@"
}

run_cilium() {
  local cmd=(cilium --namespace "$CILIUM_NAMESPACE")
  if [[ -n "$KUBE_CONTEXT" ]]; then
    cmd+=(--context "$KUBE_CONTEXT")
  fi
  KUBECONFIG="$KUBECONFIG" "${cmd[@]}" "$@"
}

render_vm_config_args() {
  local item
  for item in "${VM_CONFIGS[@]}"; do
    printf '%s\0%s\0' '--config' "$item"
  done
}

render_label_args() {
  local item
  local labels_csv="$1"
  IFS=',' read -r -a label_items <<<"$labels_csv"
  for item in "${label_items[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ -n "$item" ]] || continue
    printf '%s\0' "$item"
  done
}

KUBECONFIG=""
KUBE_CONTEXT=""
CILIUM_NAMESPACE="kube-system"
JUMPBOX=""
SSH_USER="azureuser"
LINUX_TARGET=""
LINUX_NAME=""
LINUX_IP=""
WORKLOAD_NAME=""
WORKLOAD_NAMESPACE="default"
IPV4_ALLOC_CIDR="10.192.1.0/30"
WORKLOAD_LABELS="lab.cilium.io/experiment=cilium-standalone,lab.cilium.io/host-kind=linux-external-workload,lab.cilium.io/zone=zone1"
SERVICE_TYPE="LoadBalancer"
SKIP_CLUSTERMESH_ENABLE=0
RETRIES=4
declare -a VM_CONFIGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kubeconfig)
      KUBECONFIG="$2"
      shift 2
      ;;
    --context)
      KUBE_CONTEXT="$2"
      shift 2
      ;;
    --cilium-namespace)
      CILIUM_NAMESPACE="$2"
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
    --linux-target)
      LINUX_TARGET="$2"
      shift 2
      ;;
    --workload-name)
      WORKLOAD_NAME="$2"
      shift 2
      ;;
    --workload-namespace)
      WORKLOAD_NAMESPACE="$2"
      shift 2
      ;;
    --ipv4-alloc-cidr)
      IPV4_ALLOC_CIDR="$2"
      shift 2
      ;;
    --labels)
      WORKLOAD_LABELS="$2"
      shift 2
      ;;
    --service-type)
      SERVICE_TYPE="$2"
      shift 2
      ;;
    --vm-config)
      VM_CONFIGS+=("$2")
      shift 2
      ;;
    --retries)
      RETRIES="$2"
      shift 2
      ;;
    --skip-clustermesh-enable)
      SKIP_CLUSTERMESH_ENABLE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [[ -z "$KUBECONFIG" || -z "$JUMPBOX" || -z "$LINUX_TARGET" ]]; then
  usage >&2
  exit 1
fi

need_cmd kubectl
need_cmd cilium
need_cmd ssh
need_cmd scp
need_cmd mktemp

if [[ ! -f "$KUBECONFIG" ]]; then
  die "kubeconfig not found: $KUBECONFIG"
fi

parse_target "$LINUX_TARGET" LINUX_NAME LINUX_IP

if [[ -z "$WORKLOAD_NAME" ]]; then
  WORKLOAD_NAME="$LINUX_NAME"
fi

if ! run_cilium clustermesh vm --help >/dev/null 2>&1; then
  die "the installed cilium CLI does not expose 'cilium clustermesh vm'; use an older CLI line for the deprecated external-workload flow"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKDIR="$(mktemp -d)"
INSTALL_SCRIPT="${WORKDIR}/install-external-workload.sh"
trap 'rm -rf "$WORKDIR"' EXIT

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ProxyJump="$JUMPBOX"
)

REMOTE_TARGET="${SSH_USER}@${LINUX_IP}"

log "Deprecated-path reminder: this script drives Linux external workloads only; it is not equivalent to node host firewall"
log "Checking remote hostname"
REMOTE_HOSTNAME="$(ssh "${SSH_OPTS[@]}" "$REMOTE_TARGET" 'hostname -s' 2>/dev/null || true)"
if [[ "$REMOTE_HOSTNAME" != "$WORKLOAD_NAME" ]]; then
  die "remote hostname mismatch: expected '$WORKLOAD_NAME', got '${REMOTE_HOSTNAME:-<empty>}'"
fi

log "Ensuring Docker is present on ${WORKLOAD_NAME}"
ssh "${SSH_OPTS[@]}" "$REMOTE_TARGET" 'if ! command -v docker >/dev/null 2>&1; then sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io; fi; sudo systemctl enable --now docker'

if (( SKIP_CLUSTERMESH_ENABLE == 0 )); then
  log "Enabling clustermesh external workloads on the cluster"
  run_cilium clustermesh enable --service-type "$SERVICE_TYPE" --enable-external-workloads
else
  log "Skipping clustermesh enable step"
fi

log "Waiting for clustermesh status"
run_cilium clustermesh status --wait

if run_kubectl get ciliumexternalworkload "$WORKLOAD_NAME" >/dev/null 2>&1; then
  log "Reusing existing CiliumExternalWorkload ${WORKLOAD_NAME}"
  mapfile -d '' -t LABEL_ARGS < <(render_label_args "$WORKLOAD_LABELS")
  if [[ "${#LABEL_ARGS[@]}" -gt 0 ]]; then
    run_kubectl label ciliumexternalworkload "$WORKLOAD_NAME" --overwrite "${LABEL_ARGS[@]}"
  fi
else
  log "Creating CiliumExternalWorkload ${WORKLOAD_NAME}"
  CREATE_CMD=(
    clustermesh vm create "$WORKLOAD_NAME"
    -n "$WORKLOAD_NAMESPACE"
    --ipv4-alloc-cidr "$IPV4_ALLOC_CIDR"
    --labels "$WORKLOAD_LABELS"
  )
  run_cilium "${CREATE_CMD[@]}"
fi

log "Current external workload status"
run_cilium clustermesh vm status "$WORKLOAD_NAME" || true

log "Generating install script"
INSTALL_CMD=(clustermesh vm install "$INSTALL_SCRIPT" --wait --retries "$RETRIES")
while IFS= read -r -d '' arg; do
  INSTALL_CMD+=("$arg")
done < <(render_vm_config_args)
run_cilium "${INSTALL_CMD[@]}"

log "Copying install script to ${REMOTE_TARGET} through the jumpbox"
scp "${SSH_OPTS[@]}" "$INSTALL_SCRIPT" "${REMOTE_TARGET}:/tmp/install-external-workload.sh" >/dev/null

log "Running install script on ${WORKLOAD_NAME}"
ssh "${SSH_OPTS[@]}" "$REMOTE_TARGET" "sudo HOST_IP=${LINUX_IP} bash /tmp/install-external-workload.sh"

log "Checking remote Cilium agent status"
ssh "${SSH_OPTS[@]}" "$REMOTE_TARGET" 'sudo cilium-dbg status --brief'

log "Checking updated external workload status"
run_cilium clustermesh vm status "$WORKLOAD_NAME"

CEW_IP="$(run_kubectl get ciliumexternalworkload "$WORKLOAD_NAME" -o jsonpath='{.status.ip}' 2>/dev/null || true)"
if [[ -n "$CEW_IP" ]]; then
  log "External workload registered with status IP ${CEW_IP}"
else
  log "External workload exists but does not yet report a status IP"
fi

log "Completed deprecated Linux external-workload onboarding for ${WORKLOAD_NAME}"
