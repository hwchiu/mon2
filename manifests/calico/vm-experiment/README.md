# Standalone VM Experiment

This directory contains the cluster-side objects used for the standalone VM
Felix experiment.

## Apply order

1. Apply `00-vm-agent-rbac.yaml`.
2. Wait for the service-account token secret to be populated.
3. Create the placeholder Kubernetes `Node` objects for the standalone VMs:

```bash
kubectl --context=hep-0605-0534-k3s apply \
  -f manifests/calico/vm-experiment/05-legacy-01-k8s-node.yaml \
  -f manifests/calico/vm-experiment/06-legacy-02-k8s-node.yaml
```

4. Create the Calico `Node` objects with `calicoctl`:

```bash
DATASTORE_TYPE=kubernetes \
KUBECONFIG=/home/ubuntu/.kube/hep-0605-0534-k3s.yaml \
/tmp/calicoctl-linux-amd64 apply \
  -f manifests/calico/vm-experiment/10-legacy-01-node.yaml \
  -f manifests/calico/vm-experiment/11-legacy-02-node.yaml
```

5. Apply the baseline profile for `legacy-01`:

```bash
kubectl --context=hep-0605-0534-k3s apply \
  -f manifests/calico/vm-experiment/20-host-baseline-allow-all.yaml \
  -f manifests/calico/vm-experiment/30-legacy-01-hostendpoint.yaml
```

6. Apply the restricted profile for `legacy-02`:

```bash
kubectl --context=hep-0605-0534-k3s apply \
  -f manifests/calico/vm-experiment/22-protected-vm-egress-allow.yaml \
  -f manifests/calico/vm-experiment/23-allow-jumpbox-ssh-to-protected-vms.yaml \
  -f manifests/calico/vm-experiment/24-allow-labelled-workload-to-legacy-api.yaml \
  -f manifests/calico/vm-experiment/25-allow-legacy-web-to-legacy-api.yaml \
  -f manifests/calico/vm-experiment/26-default-deny-protected-vm-ingress.yaml \
  -f manifests/calico/vm-experiment/35-legacy-02-hostendpoint.yaml
```

7. Use `40-legacy-01-deny-http.yaml` only as a temporary validation rule.

## Runtime notes

- The standalone VM uses `calico-node -felix` only; it is not joined to k3s as a
  worker.
- In this lab, a placeholder Kubernetes `Node` object is required so the Calico
  `Node` object can exist when using the Kubernetes datastore.
- The placeholder `Node` objects intentionally do not carry the standard
  `kubernetes.io/os=linux` label. If that label is present, Linux DaemonSets
  such as `cilium` and `cilium-envoy` will count the fake nodes in their
  desired replica count.
- The Felix environment on the VM uses `CALICO_NETWORKING_BACKEND=none` and
  `FELIX_XDPENABLED=false`.
- On Ubuntu 22.04 in this lab, the extracted `calico-node` binary also required
  a compatibility symlink for `libpcap.so.1`.
- `legacy-01` uses `policy_profile=baseline` and remains broadly allowed so it
  can be used as a known-good source VM.
- `legacy-02` uses `policy_profile=restricted`, allowing only jumpbox SSH and
  HTTP from the `legacy-web` VM.
- The workload-to-VM selector test is intentionally kept in the manifest set,
  but in this k3s + Cilium topology the standalone VM sees the source as the
  node IP (`10.70.10.12` / `10.70.10.10`) rather than the pod IP, so the pod
  label selector does not distinguish `access-client` from `blocked-client` at
  the VM HostEndpoint boundary.
