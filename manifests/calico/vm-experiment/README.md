# Standalone VM Experiment

This directory contains the cluster-side objects used for the standalone VM
Felix experiment.

## Apply order

1. Apply `00-vm-agent-rbac.yaml`.
2. Wait for the service-account token secret to be populated.
3. Create the placeholder Kubernetes `Node` object for the standalone VM:

```bash
kubectl --context=hep-0605-0534-k3s apply -f manifests/calico/vm-experiment/05-legacy-01-k8s-node.yaml
```

4. Create the Calico `Node` object with `calicoctl`:

```bash
DATASTORE_TYPE=kubernetes \
KUBECONFIG=/home/ubuntu/.kube/hep-0605-0534-k3s.yaml \
/tmp/calicoctl-linux-amd64 apply -f manifests/calico/vm-experiment/10-legacy-01-node.yaml
```

5. Apply `20-host-baseline-allow-all.yaml`.
6. Apply `30-legacy-01-hostendpoint.yaml`.
7. Use `40-legacy-01-deny-http.yaml` only as a temporary validation rule.

## Runtime notes

- The standalone VM uses `calico-node -felix` only; it is not joined to k3s as a
  worker.
- In this lab, a placeholder Kubernetes `Node` object is required so the Calico
  `Node` object can exist when using the Kubernetes datastore.
- The Felix environment on the VM uses `CALICO_NETWORKING_BACKEND=none` and
  `FELIX_XDPENABLED=false`.
- On Ubuntu 22.04 in this lab, the extracted `calico-node` binary also required
  a compatibility symlink for `libpcap.so.1`.
