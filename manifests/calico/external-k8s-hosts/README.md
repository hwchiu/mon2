# External Kubernetes Hosts

This path treats every node in a second Kubernetes cluster as a Calico-managed
external host instead of installing a second in-cluster Calico deployment.

## What this is for

- cluster-2 keeps its own Kubernetes control plane
- cluster-2 keeps Cilium as its CNI
- cluster-1 remains the only Calico datastore and policy control plane
- cluster-2 nodes are represented in cluster-1 as:
  - placeholder Kubernetes `Node` objects
  - Calico `Node` objects
  - Calico `HostEndpoint` objects on `eth0`

This gives you host-level policy across multiple Kubernetes clusters and VMs,
but it does **not** give cluster-2 workload identity inside cluster-1. Cluster-2
pods are still local to cluster-2 and are not onboarded as Calico workload
endpoints in cluster-1.

## Bootstrap workflow

1. Provision cluster-2 with Kubernetes and Cilium only.
2. Keep cluster-1 Calico policy-only deployment healthy.
3. Apply the shared baseline policy on cluster-1:

```bash
kubectl --context=hep-0605-0534-k3s apply -f manifests/calico/vm-experiment/20-host-baseline-allow-all.yaml
```

4. Run the onboarding script from the repo root:

```bash
./scripts/onboard-external-k8s-hosts.sh \
  --cluster1-kubeconfig /home/ubuntu/.kube/hep-0605-0534-k3s.yaml \
  --cluster2-kubeconfig /path/to/cluster2-kubeconfig.yaml \
  --cluster1-api-server https://10.70.10.10:6443 \
  --jumpbox azureuser@20.110.199.106 \
  --cluster-id cluster-2
```

## Labels added to cluster-2 HostEndpoints

- `cluster_id=<cluster-id>`
- `cluster_kind=kubernetes`
- `endpoint_role=k8s-node`
- `managed_as=external-host`
- `policy_profile=baseline`

These labels are intended to be the selector surface for later host-level
GlobalNetworkPolicy.
