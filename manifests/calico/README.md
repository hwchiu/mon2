# Calico Manifest Set

These manifests are templates and examples for the host-endpoint validation flow.
They are written for the CRD-backed `crd.projectcalico.org/v1` API that is
available through `kubectl` on the current k3s plus Cilium lab cluster.

## Apply order

1. Replace placeholders in `00-host-baseline-allow.template.yaml`.
2. Create HostEndpoint objects from `vm-hostendpoint.template.yaml` for each legacy VM.
3. Apply `10-allow-labelled-workload-to-legacy.yaml`.
4. Apply `90-default-deny-host-ingress.yaml`.
5. Deploy the workload pods from [manifests/k8s/test-workloads.yaml](/home/ubuntu/calico/manifests/k8s/test-workloads.yaml).
6. On Kubernetes clusters, enable or disable node auto HostEndpoints with `20-enable-auto-hostendpoints.yaml` and `99-disable-auto-hostendpoints.yaml`.

## Notes

- Apply the baseline allow policy before creating restrictive HostEndpoints.
- The `node:` value in a VM HostEndpoint must match the hostname Felix uses on that VM.
- `expectedIPs` is required when other endpoints use selectors to match the VM.
- On the k3s cluster, enable automatic node HostEndpoints only after the experimental Calico footprint is healthy.
- On the Cilium-backed k3s nodes, start with one node or a narrow selector and keep rollback ready.
- If auto HostEndpoints are enabled on the k3s cluster, be ready to disable them immediately with `99-disable-auto-hostendpoints.yaml`.
