# Azure Host Validation Lab

This repository provisions an Azure VM lab with Terraform for two related
validation tracks:

- existing Calico HostEndpoint assets for label-driven host policy across
  Cilium-backed k3s nodes, standalone Linux VMs, and onboarded external hosts
- the Cilium standalone host validation document for cluster-node host policy,
  Linux deprecated external workloads, and the Windows standalone attempt

Start with
[docs/calico-hostendpoint-azure-validation-plan.md](docs/calico-hostendpoint-azure-validation-plan.md)
for the Calico validation track and
[docs/cilium-standalone-host-validation.md](docs/cilium-standalone-host-validation.md)
for the Cilium standalone validation track.

Use [infra/azure/README.md](infra/azure/README.md) for provisioning,
[manifests/calico/README.md](manifests/calico/README.md) for the Calico policy
assets, and
[docs/calico-hostendpoint-execution-runbook.md](docs/calico-hostendpoint-execution-runbook.md)
for the Calico execution sequence.
