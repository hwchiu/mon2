# Cilium Manifest Set

This tree keeps the Cilium validation assets separate from the existing
`manifests/calico` flow.

## Split model

These assets intentionally use three different Cilium shapes because the lab
does not have one clean, uniform standalone-host primitive in Cilium:

- Kubernetes cluster nodes use `CiliumClusterwideNetworkPolicy` with
  `nodeSelector`, so the experiment exercises Cilium host policy on real
  cluster nodes.
- The standalone Linux VM uses the deprecated external-workload path. Its
  policy is endpoint-style and should not be read as equivalent to node host
  firewall semantics.
- The standalone Windows VM remains an explicit validation target, but there is
  no repo-native standalone Cilium attachment asset here. Windows is therefore
  an observation branch that may fail or stay unsupported.

## Scope

- Every manifest in this tree is intentionally scoped to TCP `18080`.
- The host experiment uses `enableDefaultDeny.ingress=false` and
  `enableDefaultDeny.egress=false` where needed so the round stays out of SSH,
  kube-apiserver, and other non-test host traffic.
- The runner rewrites the example CIDR blocks in the host experiment manifests
  so the applied policy matches the node IPs you pass at execution time.
- The runner expects two distinct `zone1` node IPs and one `zone2` node so the
  allow case is measured between distinct cluster hosts.

## Assets

- `host-experiment/10-zone1-allow-node-http.yaml`: cluster-node host policy for
  the `zone1` allow case plus the `zone2 -> zone1` deny case on TCP `18080`
- `host-experiment/20-zone2-deny-node-http.yaml`: cluster-node host policy for
  the `zone1 -> zone2` deny case on TCP `18080`
- `host-experiment/30-linux-external-workload-http.yaml`: deprecated Linux
  external-workload policy, written as endpoint policy rather than node host
  policy
- `scripts/onboard-cilium-linux-external-workload.sh`: helper for the older
  `cilium clustermesh vm ...` onboarding path; by default it resolves the
  pinned old `cilium` CLI release tag from the repo's Terraform vars
- `scripts/run-cilium-standalone-experiment.sh`: installs the dedicated Linux
  test service, applies the manifests, and prints the reachability matrix
