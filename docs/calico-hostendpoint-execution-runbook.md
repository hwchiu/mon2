# Execution Runbook

This runbook turns the validation plan into a repeatable sequence.

## 1. Provision the Azure VM lab

```bash
cd infra/azure/terraform
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

terraform init
terraform plan
terraform apply
terraform output
```

Use an absolute path for `ssh_public_key_path`.

After Terraform finishes, return to the repo root before applying manifests:

```bash
cd /home/ubuntu/mon2
```

## 2. Verify bootstrap and reachability

Use the Terraform outputs for the exact IPs and helper commands.

From your workstation:

```bash
ssh <admin-username>@<jumpbox-public-ip>
```

From your workstation to the k3s server through the jumpbox:

```bash
ssh -J <admin-username>@<jumpbox-public-ip> <admin-username>@<k3s-server-private-ip>
```

To use the repo manifests from your workstation, fetch the kubeconfig and keep an SSH tunnel open in a second terminal:

```bash
ssh -J <admin-username>@<jumpbox-public-ip> <admin-username>@<k3s-server-private-ip> \
  'sudo cat /etc/rancher/k3s/k3s.yaml' > /tmp/hep-lab-k3s.yaml

ssh -N -L 6443:<k3s-server-private-ip>:6443 <admin-username>@<jumpbox-public-ip>
```

Then from your workstation:

```bash
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl get nodes -o wide
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl get pods -A -o wide
```

If you prefer to inspect the server directly:

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
cilium status
```

If the cluster is not healthy, inspect:

```bash
sudo journalctl -u k3s --no-pager
sudo cat /var/log/bootstrap-k3s-server.log
sudo cat /var/log/bootstrap-k3s-agent.log
```

## 3. Deploy workload probes

From your workstation:

```bash
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl apply -f manifests/k8s/test-workloads.yaml
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl -n hep-lab get pods -o wide
```

Confirm the labeled and blocked client pods are running before you proceed.

## 4. Validate the standalone VM baseline

Install Calico Felix on the legacy VMs in policy-only mode using the Kubernetes datastore from the k3s cluster. Use the current Tigera non-cluster-host instructions as the source of truth for the exact package names and service configuration.

Minimum host-side settings to capture during the test:

- `FELIX_DATASTORETYPE=kubernetes`
- `KUBECONFIG=<path to kubeconfig with access to the k3s-backed datastore>`
- `CALICO_NODENAME=<stable hostname>`
- `CALICO_NETWORKING_BACKEND=none`

After Felix is healthy on the legacy VMs:

```bash
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl apply -f manifests/calico/00-host-baseline-allow.template.yaml
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl apply -f manifests/calico/vm-hostendpoint.template.yaml
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl apply -f manifests/calico/10-allow-labelled-workload-to-legacy.yaml
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl apply -f manifests/calico/90-default-deny-host-ingress.yaml
```

Replace placeholders before applying.

## 5. Attempt the k3s plus Cilium experiment

This step is intentionally manual because the coexistence path is the subject under test.

Rules for the attempt:

- Do not replace the active Cilium CNI configuration.
- Do not let Calico own the k3s CNI directories.
- Record the exact manifests, Helm values, and daemonset changes used.
- Start with one node selector before widening HostEndpoint coverage.

If you reach a healthy Calico control plane:

```bash
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl apply -f manifests/calico/20-enable-auto-hostendpoints.yaml
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl get hostendpoints -A -o wide
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl apply -f manifests/calico/00-host-baseline-allow.template.yaml
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl apply -f manifests/calico/90-default-deny-host-ingress.yaml
```

## 6. Smoke tests

From the labeled pod:

```bash
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl -n hep-lab exec deploy/access-client -- curl -sS --max-time 5 http://<legacy-vm-a-ip>
```

From the blocked pod:

```bash
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl -n hep-lab exec deploy/blocked-client -- curl -sS --max-time 5 http://<legacy-vm-a-ip>
```

From the jumpbox:

```bash
nc -vz <legacy-vm-a-ip> 22
nc -vz <legacy-vm-a-ip> 80
```

From the k3s server:

```bash
kubectl get nodes -o wide
cilium status
```

## 7. Rollback

Use these first if management access or node health starts to degrade:

```bash
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl delete -f manifests/calico/90-default-deny-host-ingress.yaml --ignore-not-found
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl apply -f manifests/calico/99-disable-auto-hostendpoints.yaml
```

Then confirm:

```bash
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl get hostendpoints -A -o wide
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl get pods -A
KUBECONFIG=/tmp/hep-lab-k3s.yaml kubectl get nodes
```

And on the k3s server:

```bash
cilium status
```
