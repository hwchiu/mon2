#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run-zone-isolation-experiment.sh \
    --cluster1-kubeconfig /path/to/cluster1.yaml \
    --jumpbox azureuser@20.110.199.106 \
    [--calicoctl-bin /path/to/calicoctl] \
    [--port 18080]

This script:
1. Installs a dedicated HTTP test service on the five external hosts.
2. Applies the zone-isolation HostEndpoint labels and Calico policy.
3. Executes a small reachability matrix and prints pass/fail.
EOF
}

log() {
  printf '[zone-isolation] %s\n' "$*"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

CLUSTER1_KUBECONFIG=""
JUMPBOX=""
CALICOCTL_BIN="${CALICOCTL_BIN:-/tmp/calicoctl-linux-amd64}"
PORT="${PORT:-18080}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster1-kubeconfig)
      CLUSTER1_KUBECONFIG="$2"
      shift 2
      ;;
    --jumpbox)
      JUMPBOX="$2"
      shift 2
      ;;
    --calicoctl-bin)
      CALICOCTL_BIN="$2"
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
      printf 'unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$CLUSTER1_KUBECONFIG" || -z "$JUMPBOX" ]]; then
  usage >&2
  exit 1
fi

need_cmd ssh
need_cmd scp
need_cmd mktemp

if [[ ! -f "$CLUSTER1_KUBECONFIG" ]]; then
  printf 'cluster-1 kubeconfig not found: %s\n' "$CLUSTER1_KUBECONFIG" >&2
  exit 1
fi

if [[ ! -x "$CALICOCTL_BIN" ]]; then
  printf 'calicoctl not found or not executable: %s\n' "$CALICOCTL_BIN" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST_DIR="${REPO_ROOT}/manifests/calico/zone-experiment"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ProxyJump="$JUMPBOX"
)

HOSTS=(
  "hep-0605-0534-legacy-01|10.70.20.20|zone1"
  "hep-0605-0534-legacy-02|10.70.20.21|zone2"
  "hep-0605-0534-k3s2-server-0|10.70.30.10|zone1"
  "hep-0605-0534-k3s2-agent-01|10.70.30.11|zone1"
  "hep-0605-0534-k3s2-agent-02|10.70.30.12|zone1"
)

cat >"${WORKDIR}/lab-zone-http.py" <<'EOF'
#!/usr/bin/env python3
import http.server
import json
import os
import socket

zone = os.environ.get("LAB_ZONE", "unknown")
name = os.environ.get("LAB_NAME", socket.gethostname())
port = int(os.environ.get("LAB_ZONE_PORT", "18080"))

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps(
            {
                "host": name,
                "zone": zone,
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
chmod +x "${WORKDIR}/lab-zone-http.py"

cat >"${WORKDIR}/lab-zone-http.service" <<'EOF'
[Unit]
Description=Zone isolation lab HTTP endpoint
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/default/lab-zone-http
ExecStart=/usr/local/bin/lab-zone-http.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

install_test_service() {
  local name="$1"
  local ip="$2"
  local zone="$3"
  local target="azureuser@${ip}"

  log "Installing test service on ${name} (${ip}, ${zone})"
  ssh "${SSH_OPTS[@]}" "$target" 'sudo mkdir -p /usr/local/bin /etc/systemd/system /etc/default'
  scp "${SSH_OPTS[@]}" "${WORKDIR}/lab-zone-http.py" "$target:/tmp/lab-zone-http.py" >/dev/null
  scp "${SSH_OPTS[@]}" "${WORKDIR}/lab-zone-http.service" "$target:/tmp/lab-zone-http.service" >/dev/null
  ssh "${SSH_OPTS[@]}" "$target" "cat >/tmp/lab-zone-http.env <<EOF
LAB_ZONE=${zone}
LAB_NAME=${name}
LAB_ZONE_PORT=${PORT}
EOF
sudo install -m 0755 /tmp/lab-zone-http.py /usr/local/bin/lab-zone-http.py
sudo install -m 0644 /tmp/lab-zone-http.service /etc/systemd/system/lab-zone-http.service
sudo install -m 0644 /tmp/lab-zone-http.env /etc/default/lab-zone-http
sudo systemctl daemon-reload
sudo systemctl enable --now lab-zone-http.service
sudo systemctl is-active lab-zone-http.service
curl --fail --silent --max-time 5 http://127.0.0.1:${PORT}/
rm -f /tmp/lab-zone-http.py /tmp/lab-zone-http.service /tmp/lab-zone-http.env"
}

for host_row in "${HOSTS[@]}"; do
  IFS='|' read -r host_name host_ip host_zone <<<"$host_row"
  install_test_service "$host_name" "$host_ip" "$host_zone"
done

log "Applying zone HostEndpoint labels and policy"
DATASTORE_TYPE=kubernetes KUBECONFIG="$CLUSTER1_KUBECONFIG" "$CALICOCTL_BIN" apply -f "${MANIFEST_DIR}/00-zone-hostendpoints.yaml"
DATASTORE_TYPE=kubernetes KUBECONFIG="$CLUSTER1_KUBECONFIG" "$CALICOCTL_BIN" apply -f "${MANIFEST_DIR}/10-allow-zone1-to-zone1-http.yaml"
DATASTORE_TYPE=kubernetes KUBECONFIG="$CLUSTER1_KUBECONFIG" "$CALICOCTL_BIN" apply -f "${MANIFEST_DIR}/20-deny-zone1-to-zone2-http.yaml"

run_check() {
  local source_name="$1"
  local source_ip="$2"
  local destination_name="$3"
  local destination_ip="$4"
  local expected="$5"
  local target="azureuser@${source_ip}"
  local output
  local status="deny"

  output="$(ssh "${SSH_OPTS[@]}" "$target" "curl --silent --show-error --max-time 5 http://${destination_ip}:${PORT}/" 2>&1 || true)"
  if [[ "$output" == *'"host"'* && "$output" == *"${destination_name}"* ]]; then
    status="allow"
  fi

  if [[ "$status" == "$expected" ]]; then
    printf 'PASS  %-26s -> %-26s expected=%-5s actual=%s\n' "$source_name" "$destination_name" "$expected" "$status"
  else
    printf 'FAIL  %-26s -> %-26s expected=%-5s actual=%s\n' "$source_name" "$destination_name" "$expected" "$status"
    printf '      output: %s\n' "$output"
    return 1
  fi
}

log "Running connectivity matrix on TCP ${PORT}"
run_check "hep-0605-0534-legacy-01" "10.70.20.20" "hep-0605-0534-k3s2-server-0" "10.70.30.10" "allow"
run_check "hep-0605-0534-k3s2-server-0" "10.70.30.10" "hep-0605-0534-legacy-01" "10.70.20.20" "allow"
run_check "hep-0605-0534-k3s2-agent-01" "10.70.30.11" "hep-0605-0534-k3s2-agent-02" "10.70.30.12" "allow"
run_check "hep-0605-0534-legacy-01" "10.70.20.20" "hep-0605-0534-legacy-02" "10.70.20.21" "deny"
run_check "hep-0605-0534-k3s2-server-0" "10.70.30.10" "hep-0605-0534-legacy-02" "10.70.20.21" "deny"
run_check "hep-0605-0534-legacy-02" "10.70.20.21" "hep-0605-0534-legacy-01" "10.70.20.20" "deny"
run_check "hep-0605-0534-legacy-02" "10.70.20.21" "hep-0605-0534-k3s2-server-0" "10.70.30.10" "deny"

log "Zone experiment completed"
