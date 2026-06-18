# Cilium Host Experiment

This directory mirrors the repo's current zone-isolation testing style while
making the Cilium split explicit:

- cluster nodes use `nodeSelector` host policy
- the Linux standalone VM uses deprecated external-workload endpoint policy
- Windows stays an explicit target, but not a repo-native attached host in this
  manifest set

## Apply order

1. Ensure Cilium host firewall prerequisites are already enabled on the
   cluster.
2. Label the participating cluster nodes with:
   - `lab.cilium.io/experiment=cilium-standalone`
   - `lab.cilium.io/host-kind=cluster-node`
   - `lab.cilium.io/zone=zone1|zone2`
3. If you want Linux standalone enforcement, run
   `scripts/onboard-cilium-linux-external-workload.sh` first. That script
   creates a `CiliumExternalWorkload` identity labeled as:
   - `lab.cilium.io/experiment=cilium-standalone`
   - `lab.cilium.io/host-kind=linux-external-workload`
   - `lab.cilium.io/zone=zone1`
4. Apply the manifests in order:
   - `10-zone1-allow-node-http.yaml`
   - `20-zone2-deny-node-http.yaml`
   - `30-linux-external-workload-http.yaml`

The repo copies below carry example CIDR values for the current lab. The runner
script renders temporary copies so the `fromCIDRSet` and `toCIDRSet` blocks
match the node IPs you pass in.

## Expected behavior

- `zone1 node -> zone1 node` on TCP `18080`: allowed
- `zone2 node -> zone1 node` on TCP `18080`: denied
- `zone1 node -> zone2 node` on TCP `18080`: denied
- `zone1 node -> Linux standalone` on TCP `18080`: allowed if the deprecated
  external-workload attachment is healthy; otherwise treat as observation only
- `zone2 node -> Linux standalone` on TCP `18080`: denied if the deprecated
  external-workload attachment is healthy
- `Linux standalone -> zone2 node` on TCP `18080`: denied if the deprecated
  external-workload attachment is healthy
- Windows on TCP `18080`: observation target only until a viable standalone
  Cilium attachment path is proven in this repo

## Limitations

- The cluster-node manifests keep `enableDefaultDeny` disabled so this round
  only touches TCP `18080` instead of implicitly locking down unrelated host
  traffic.
- `30-linux-external-workload-http.yaml` is endpoint policy for a deprecated
  onboarding path. A pass here is a lab result, not proof of parity with node
  host firewall.
- The Linux onboarding helper expects an older `cilium` CLI that still exposes
  `cilium clustermesh vm create/install/status`.
- Windows is intentionally not hidden behind a fallback Windows Firewall
  translation. If Windows cannot attach to Cilium meaningfully, the correct
  outcome is a documented unsupported result.
