# Calico HostEndpoint Azure Validation Lab

This repository provisions an Azure VM lab with Terraform to test whether Calico HostEndpoints can provide one label-driven host firewall across:

- k3s nodes that use Cilium as the Kubernetes CNI
- standalone Azure Linux VMs

Start with [docs/calico-hostendpoint-azure-validation-plan.md](/home/ubuntu/calico/docs/calico-hostendpoint-azure-validation-plan.md), then use [infra/azure](/home/ubuntu/calico/infra/azure/README.md) for provisioning and [manifests/calico](/home/ubuntu/calico/manifests/calico/README.md) for policy examples.

For execution steps, use [docs/calico-hostendpoint-execution-runbook.md](/home/ubuntu/calico/docs/calico-hostendpoint-execution-runbook.md).
