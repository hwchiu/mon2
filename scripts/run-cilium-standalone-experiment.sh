#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run-cilium-standalone-experiment.sh \
    --kubeconfig /path/to/cluster.yaml \
    --jumpbox azureuser@20.110.199.106 \
    --zone1-node k3s-server-0=10.70.10.10 \
    --zone1-node k3s-agent-01=10.70.10.11 \
    --zone2-node k3s-agent-02=10.70.10.12 \
    --linux-standalone linux-hostname=10.70.20.30 \
    --windows-standalone windows-hostname=10.70.20.31 \
    [--context hep-lab-k3s] \
    [--ssh-user azureuser] \
    [--linux-workload-name linux-hostname] \
    [--port 18080]

This script mirrors the existing Calico zone experiment shape:

1. Installs a dedicated HTTP test service on the Linux targets.
2. Labels the selected cluster nodes for the Cilium host-policy slice.
3. Renders and applies the narrow Cilium manifests for TCP 18080 only.
4. Runs a small reachability matrix and prints PASS / FAIL / OBSERVE lines.

Important limitations:
  - The Linux standalone target is meaningful only if the deprecated
    external-workload attachment is healthy.
  - Windows is probed as an explicit target, but the result is observational
    unless a real Cilium standalone attachment path exists.
  - Pass at least two distinct `--zone1-node` private IPs so the zone1 allow
    case is a real cross-host probe instead of a self-probe.
EOF
}

log() {
  printf '[cilium-standalone] %s\n' "$*"
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

append_target() {
  local raw="$1"
  local __names_var="$2"
  local __ips_var="$3"
  local name="${raw%%=*}"
  local ip="${raw#*=}"

  if [[ -z "$name" || -z "$ip" || "$name" == "$raw" ]]; then
    die "target arguments must look like name=ip, got: $raw"
  fi

  eval "$__names_var+=(\"\$name\")"
  eval "$__ips_var+=(\"\$ip\")"
}

select_distinct_zone1_peer() {
  local idx
  for idx in "${!ZONE1_NODE_IPS[@]}"; do
    [[ "$idx" -eq 0 ]] && continue
    if [[ "${ZONE1_NODE_IPS[$idx]}" != "$FIRST_ZONE1_IP" ]]; then
      SECOND_ZONE1_NAME="${ZONE1_NODE_NAMES[$idx]}"
      SECOND_ZONE1_IP="${ZONE1_NODE_IPS[$idx]}"
      return 0
    fi
  done

  return 1
}

run_kubectl() {
  local cmd=(kubectl --kubeconfig "$KUBECONFIG")
  if [[ -n "$KUBE_CONTEXT" ]]; then
    cmd+=(--context "$KUBE_CONTEXT")
  fi
  "${cmd[@]}" "$@"
}

join_cidrs() {
  local ip
  for ip in "$@"; do
    printf '        - cidr: %s/32\n' "$ip"
  done
}

replace_block() {
  local file="$1"
  local start_marker="$2"
  local end_marker="$3"
  local replacement="$4"
  local tmp="${file}.tmp"

  awk \
    -v start="$start_marker" \
    -v end="$end_marker" \
    -v replacement="$replacement" '
      index($0, start) {
        print
        if (replacement != "") {
          printf "%s", replacement
          if (substr(replacement, length(replacement), 1) != "\n") {
            printf "\n"
          }
        }
        in_block = 1
        next
      }
      index($0, end) {
        in_block = 0
        print
        next
      }
      !in_block { print }
    ' "$file" >"$tmp"

  mv "$tmp" "$file"
}

render_manifest() {
  local source="$1"
  local destination="$2"

  cp "$source" "$destination"
  replace_block "$destination" "# ZONE1_NODE_CIDRS_BEGIN" "# ZONE1_NODE_CIDRS_END" "$(join_cidrs "${ZONE1_NODE_IPS[@]}")"
  replace_block "$destination" "# ZONE2_NODE_CIDRS_BEGIN" "# ZONE2_NODE_CIDRS_END" "$(join_cidrs "${ZONE2_NODE_IPS[@]}")"
}

install_test_service() {
  local name="$1"
  local ip="$2"
  local zone="$3"
  local role="$4"
  local target="${SSH_USER}@${ip}"

  log "Installing test service on ${name} (${ip}, ${zone}, ${role})"
  ssh "${SSH_OPTS[@]}" "$target" 'sudo mkdir -p /usr/local/bin /etc/systemd/system /etc/default'
  scp "${SSH_OPTS[@]}" "${WORKDIR}/lab-cilium-http.py" "$target:/tmp/lab-cilium-http.py" >/dev/null
  scp "${SSH_OPTS[@]}" "${WORKDIR}/lab-cilium-http.service" "$target:/tmp/lab-cilium-http.service" >/dev/null
  ssh "${SSH_OPTS[@]}" "$target" "cat >/tmp/lab-cilium-http.env <<EOF
LAB_ZONE=${zone}
LAB_NAME=${name}
LAB_ROLE=${role}
LAB_HTTP_PORT=${PORT}
EOF
sudo install -m 0755 /tmp/lab-cilium-http.py /usr/local/bin/lab-cilium-http.py
sudo install -m 0644 /tmp/lab-cilium-http.service /etc/systemd/system/lab-cilium-http.service
sudo install -m 0644 /tmp/lab-cilium-http.env /etc/default/lab-cilium-http
sudo systemctl daemon-reload
sudo systemctl enable --now lab-cilium-http.service
sudo systemctl is-active lab-cilium-http.service
curl --fail --silent --max-time 5 http://127.0.0.1:${PORT}/
rm -f /tmp/lab-cilium-http.py /tmp/lab-cilium-http.service /tmp/lab-cilium-http.env"
}

detect_linux_attachment_state() {
  if ! run_kubectl get crd ciliumexternalworkloads.cilium.io >/dev/null 2>&1; then
    printf 'unattached'
    return 0
  fi

  if ! run_kubectl get ciliumexternalworkload "$LINUX_WORKLOAD_NAME" >/dev/null 2>&1; then
    printf 'unattached'
    return 0
  fi

  local status_ip
  status_ip="$(run_kubectl get ciliumexternalworkload "$LINUX_WORKLOAD_NAME" -o jsonpath='{.status.ip}' 2>/dev/null || true)"
  if [[ -n "$status_ip" ]]; then
    printf 'attached'
  else
    printf 'unattached'
  fi
}

probe_from_linux() {
  local source_ip="$1"
  local destination_ip="$2"
  local target="${SSH_USER}@${source_ip}"

  ssh "${SSH_OPTS[@]}" "$target" "curl --silent --show-error --max-time 5 http://${destination_ip}:${PORT}/" 2>&1
}

run_check() {
  local source_name="$1"
  local source_ip="$2"
  local destination_name="$3"
  local destination_ip="$4"
  local expected="$5"
  local case_name="$6"
  local response_mode="$7"
  local output
  local curl_status=0
  local actual="deny"

  output="$(probe_from_linux "$source_ip" "$destination_ip")" || curl_status=$?

  if [[ "$response_mode" == "json" ]]; then
    if (( curl_status == 0 )) && [[ "$output" == *'"host"'* ]] && [[ "$output" == *"${destination_name}"* ]]; then
      actual="allow"
    fi
  else
    if (( curl_status == 0 )); then
      actual="allow"
    fi
  fi

  case "$expected" in
    allow|deny)
      if [[ "$actual" == "$expected" ]]; then
        printf 'PASS    case=%-22s source=%-20s target=%-20s expected=%-5s actual=%s\n' "$case_name" "$source_name" "$destination_name" "$expected" "$actual"
      else
        printf 'FAIL    case=%-22s source=%-20s target=%-20s expected=%-5s actual=%s\n' "$case_name" "$source_name" "$destination_name" "$expected" "$actual"
        printf '        output=%s\n' "$output"
        FAILURES=$((FAILURES + 1))
      fi
      ;;
    observe)
      printf 'OBSERVE case=%-22s source=%-20s target=%-20s expected=%-7s actual=%s\n' "$case_name" "$source_name" "$destination_name" "$expected" "$actual"
      printf '        output=%s\n' "$output"
      ;;
    *)
      die "unsupported expected status: $expected"
      ;;
  esac
}

KUBECONFIG=""
KUBE_CONTEXT=""
JUMPBOX=""
SSH_USER="azureuser"
PORT="${PORT:-18080}"
LINUX_WORKLOAD_NAME=""
declare -a ZONE1_NODE_NAMES=()
declare -a ZONE1_NODE_IPS=()
declare -a ZONE2_NODE_NAMES=()
declare -a ZONE2_NODE_IPS=()
LINUX_NAME=""
LINUX_IP=""
WINDOWS_NAME=""
WINDOWS_IP=""

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
    --jumpbox)
      JUMPBOX="$2"
      shift 2
      ;;
    --ssh-user)
      SSH_USER="$2"
      shift 2
      ;;
    --zone1-node)
      append_target "$2" ZONE1_NODE_NAMES ZONE1_NODE_IPS
      shift 2
      ;;
    --zone2-node)
      append_target "$2" ZONE2_NODE_NAMES ZONE2_NODE_IPS
      shift 2
      ;;
    --linux-standalone)
      append_target "$2" __linux_name __linux_ip
      LINUX_NAME="$__linux_name"
      LINUX_IP="$__linux_ip"
      shift 2
      ;;
    --windows-standalone)
      append_target "$2" __windows_name __windows_ip
      WINDOWS_NAME="$__windows_name"
      WINDOWS_IP="$__windows_ip"
      shift 2
      ;;
    --linux-workload-name)
      LINUX_WORKLOAD_NAME="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
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

if [[ -z "$KUBECONFIG" || -z "$JUMPBOX" || -z "$LINUX_NAME" || -z "$WINDOWS_NAME" ]]; then
  usage >&2
  exit 1
fi

if [[ "${#ZONE1_NODE_NAMES[@]}" -lt 2 || "${#ZONE2_NODE_NAMES[@]}" -eq 0 ]]; then
  die "provide at least two --zone1-node values and one --zone2-node value"
fi

if [[ -z "$LINUX_WORKLOAD_NAME" ]]; then
  LINUX_WORKLOAD_NAME="$LINUX_NAME"
fi

need_cmd kubectl
need_cmd ssh
need_cmd scp
need_cmd mktemp

if [[ ! -f "$KUBECONFIG" ]]; then
  die "kubeconfig not found: $KUBECONFIG"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST_DIR="${REPO_ROOT}/manifests/cilium/host-experiment"
WORKDIR="$(mktemp -d)"
FAILURES=0
trap 'rm -rf "$WORKDIR"' EXIT

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ProxyJump="$JUMPBOX"
)

cat >"${WORKDIR}/lab-cilium-http.py" <<'EOF'
#!/usr/bin/env python3
import http.server
import json
import os
import socket

zone = os.environ.get("LAB_ZONE", "unknown")
name = os.environ.get("LAB_NAME", socket.gethostname())
role = os.environ.get("LAB_ROLE", "unknown")
port = int(os.environ.get("LAB_HTTP_PORT", "18080"))

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps(
            {
                "host": name,
                "zone": zone,
                "role": role,
                "path": self.path,
            },
            indent=2,
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        return

server = http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler)
server.serve_forever()
EOF
chmod +x "${WORKDIR}/lab-cilium-http.py"

cat >"${WORKDIR}/lab-cilium-http.service" <<'EOF'
[Unit]
Description=Cilium standalone experiment HTTP endpoint
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/default/lab-cilium-http
ExecStart=/usr/local/bin/lab-cilium-http.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

log "Installing dedicated HTTP service on Linux targets"
for idx in "${!ZONE1_NODE_NAMES[@]}"; do
  install_test_service "${ZONE1_NODE_NAMES[$idx]}" "${ZONE1_NODE_IPS[$idx]}" "zone1" "cluster-node"
done
for idx in "${!ZONE2_NODE_NAMES[@]}"; do
  install_test_service "${ZONE2_NODE_NAMES[$idx]}" "${ZONE2_NODE_IPS[$idx]}" "zone2" "cluster-node"
done
install_test_service "$LINUX_NAME" "$LINUX_IP" "zone1" "linux-external-workload"

log "Labelling cluster nodes for the Cilium host-policy slice"
for node_name in "${ZONE1_NODE_NAMES[@]}"; do
  run_kubectl label node "$node_name" \
    lab.cilium.io/experiment=cilium-standalone \
    lab.cilium.io/host-kind=cluster-node \
    lab.cilium.io/zone=zone1 \
    --overwrite >/dev/null
done
for node_name in "${ZONE2_NODE_NAMES[@]}"; do
  run_kubectl label node "$node_name" \
    lab.cilium.io/experiment=cilium-standalone \
    lab.cilium.io/host-kind=cluster-node \
    lab.cilium.io/zone=zone2 \
    --overwrite >/dev/null
done

log "Rendering manifests with the supplied node IPs"
render_manifest "${MANIFEST_DIR}/10-zone1-allow-node-http.yaml" "${WORKDIR}/10-zone1-allow-node-http.yaml"
render_manifest "${MANIFEST_DIR}/20-zone2-deny-node-http.yaml" "${WORKDIR}/20-zone2-deny-node-http.yaml"
render_manifest "${MANIFEST_DIR}/30-linux-external-workload-http.yaml" "${WORKDIR}/30-linux-external-workload-http.yaml"

log "Applying Cilium experiment manifests"
run_kubectl apply -f "${WORKDIR}/10-zone1-allow-node-http.yaml"
run_kubectl apply -f "${WORKDIR}/20-zone2-deny-node-http.yaml"
run_kubectl apply -f "${WORKDIR}/30-linux-external-workload-http.yaml"

LINUX_ATTACHMENT_STATE="$(detect_linux_attachment_state)"
log "Linux external-workload state: ${LINUX_ATTACHMENT_STATE}"
log "Windows limitation reminder: probes to ${WINDOWS_NAME} are observational unless a real standalone Cilium path exists"

FIRST_ZONE1_NAME="${ZONE1_NODE_NAMES[0]}"
FIRST_ZONE1_IP="${ZONE1_NODE_IPS[0]}"
FIRST_ZONE2_NAME="${ZONE2_NODE_NAMES[0]}"
FIRST_ZONE2_IP="${ZONE2_NODE_IPS[0]}"
SECOND_ZONE1_NAME=""
SECOND_ZONE1_IP=""

if ! select_distinct_zone1_peer; then
  die "provide at least two distinct --zone1-node private IPs so the zone1 allow case is not a self-probe"
fi

log "Running reachability matrix on TCP ${PORT}"
run_check "$FIRST_ZONE1_NAME" "$FIRST_ZONE1_IP" "$SECOND_ZONE1_NAME" "$SECOND_ZONE1_IP" "allow" "node-zone1-allow" "json"
run_check "$FIRST_ZONE2_NAME" "$FIRST_ZONE2_IP" "$FIRST_ZONE1_NAME" "$FIRST_ZONE1_IP" "deny" "node-zone2-to-zone1-deny" "json"
run_check "$FIRST_ZONE1_NAME" "$FIRST_ZONE1_IP" "$FIRST_ZONE2_NAME" "$FIRST_ZONE2_IP" "deny" "node-zone1-to-zone2-deny" "json"

if [[ "$LINUX_ATTACHMENT_STATE" == "attached" ]]; then
  run_check "$FIRST_ZONE1_NAME" "$FIRST_ZONE1_IP" "$LINUX_NAME" "$LINUX_IP" "allow" "linux-zone1-allow" "json"
  run_check "$FIRST_ZONE2_NAME" "$FIRST_ZONE2_IP" "$LINUX_NAME" "$LINUX_IP" "deny" "linux-zone2-to-linux-deny" "json"
  run_check "$LINUX_NAME" "$LINUX_IP" "$FIRST_ZONE2_NAME" "$FIRST_ZONE2_IP" "deny" "linux-to-zone2-deny" "json"
else
  run_check "$FIRST_ZONE1_NAME" "$FIRST_ZONE1_IP" "$LINUX_NAME" "$LINUX_IP" "observe" "linux-zone1-observe" "json"
  run_check "$FIRST_ZONE2_NAME" "$FIRST_ZONE2_IP" "$LINUX_NAME" "$LINUX_IP" "observe" "linux-zone2-observe" "json"
  run_check "$LINUX_NAME" "$LINUX_IP" "$FIRST_ZONE2_NAME" "$FIRST_ZONE2_IP" "observe" "linux-to-zone2-observe" "json"
fi

run_check "$FIRST_ZONE1_NAME" "$FIRST_ZONE1_IP" "$WINDOWS_NAME" "$WINDOWS_IP" "observe" "windows-iis-observe" "http"

if (( FAILURES > 0 )); then
  log "Experiment completed with ${FAILURES} failing checks"
  exit 1
fi

log "Experiment completed without failing checks"
