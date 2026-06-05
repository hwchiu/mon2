# Zone Isolation Experiment

This directory contains the first centralized host-firewall experiment for the
lab.

## Model

- `zone1`: `legacy-01` and all three `hep-0605-0534-k3s2` nodes
- `zone2`: `legacy-02`

The experiment is intentionally scoped to a dedicated host test service on TCP
`18080`. This avoids disrupting:

- jumpbox SSH access
- k3s and Kubernetes control-plane traffic
- Cilium datapath traffic inside either cluster

## Files

- `00-zone-hostendpoints.yaml`: adds `zone` and `experiment` labels to the five
  external-host HostEndpoints
- `10-allow-zone1-to-zone1-http.yaml`: allows zone1 to reach zone1 on TCP
  `18080`, and explicitly denies zone2 to zone1 on the same port
- `20-deny-zone1-to-zone2-http.yaml`: explicitly denies zone1 to zone2 on TCP
  `18080`

## Apply order

```bash
DATASTORE_TYPE=kubernetes KUBECONFIG=/path/to/cluster1.yaml calicoctl apply -f 00-zone-hostendpoints.yaml
DATASTORE_TYPE=kubernetes KUBECONFIG=/path/to/cluster1.yaml calicoctl apply -f 10-allow-zone1-to-zone1-http.yaml
DATASTORE_TYPE=kubernetes KUBECONFIG=/path/to/cluster1.yaml calicoctl apply -f 20-deny-zone1-to-zone2-http.yaml
```

## Expected behavior

- `zone1 -> zone1` on TCP `18080`: allowed
- `zone1 -> zone2` on TCP `18080`: denied
- `zone2 -> zone1` on TCP `18080`: denied

This experiment does not yet enforce all-port zoning. It only validates that a
single Calico control plane can drive label-based host policy across:

- standalone VMs
- a second Kubernetes cluster whose nodes are onboarded as external hosts
