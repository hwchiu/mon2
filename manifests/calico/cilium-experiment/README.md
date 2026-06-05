# Calico On Cilium Experiment

This overlay is intentionally narrow and experimental.

It starts from the official Calico `calico-policy-only.yaml` manifest and applies local patches to reduce blast radius on the existing k3s plus Cilium cluster:

- removes the `install-cni` init container so Calico does not write a new CNI config
- removes the host CNI directory mounts from `calico-node`
- limits `calico-node` to a single worker node for the first pass
- narrows `calico-kube-controllers` to the `node` controller

Apply with:

```bash
kubectl --context=hep-0605-0534-k3s apply -k manifests/calico/cilium-experiment
```

After the Calico agents are healthy, add a safe baseline policy and the first
HostEndpoint with:

```bash
kubectl --context=hep-0605-0534-k3s apply -f manifests/calico/cilium-experiment/10-host-baseline-allow-all.yaml
kubectl --context=hep-0605-0534-k3s apply -f manifests/calico/cilium-experiment/20-agent-01-hostendpoint.yaml
```

The baseline policy keeps `host_protected == "true"` endpoints in allow-all mode
until narrower host firewall rules are ready.

There is also a disposable validation policy for the first protected worker:

```bash
kubectl --context=hep-0605-0534-k3s apply -f manifests/calico/cilium-experiment/30-agent-01-deny-test-port-18081.yaml
kubectl --context=hep-0605-0534-k3s delete -f manifests/calico/cilium-experiment/30-agent-01-deny-test-port-18081.yaml
```

It denies TCP `18081` on `hep-0605-0534-k3s-agent-01` and is intended only for a
short verification run against a temporary listener.

Delete with:

```bash
kubectl --context=hep-0605-0534-k3s delete -k manifests/calico/cilium-experiment
```
