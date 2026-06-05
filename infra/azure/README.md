# Azure Lab Scaffolding

The Azure lab is now provisioned with Terraform under [infra/azure/terraform](/home/ubuntu/calico/infra/azure/terraform).

## What Terraform creates

- one public jumpbox VM
- one primary k3s server VM
- a configurable number of primary k3s agent VMs
- an optional second k3s cluster on its own subnet
- a configurable number of standalone legacy VMs
- one VNet with management, primary k3s, optional secondary k3s, and legacy subnets
- NSGs that keep public SSH limited to the jumpbox

The k3s server boots with Flannel disabled and the built-in network policy controller disabled. After the k3s API is up, the server installs Cilium and waits for it to become healthy. Legacy VMs are bootstrapped with NGINX and basic troubleshooting tools.

## Files

- `terraform/versions.tf`: provider and Terraform version requirements
- `terraform/variables.tf`: input variables
- `terraform/main.tf`: Azure network, NIC, VM, and bootstrap definitions
- `terraform/outputs.tf`: IPs and helper commands
- `terraform/terraform.tfvars.example`: example input values
- `terraform/templates/*.tftpl`: cloud-init templates for the jumpbox, k3s nodes, and legacy VMs
- `../../scripts/onboard-external-k8s-hosts.sh`: post-provision onboarding for cluster-2 nodes as Calico-managed external hosts

## Usage

1. Authenticate to Azure with `az login` or another supported `azurerm` auth method.
2. Change into the Terraform directory:

```bash
cd infra/azure/terraform
```

3. Copy the example vars file and update it. Use an absolute path for `ssh_public_key_path` because Terraform's `file()` function does not expand `~`.

```bash
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
```

4. Provision the lab:

```bash
terraform init
terraform plan
terraform apply
```

5. Inspect the generated connection details:

```bash
terraform output
```

If you enable the optional second cluster, Terraform also returns:

- the second cluster server private IP
- the second cluster agent private IPs
- an SSH command for the second cluster server
- a kube-api tunnel command that binds local port `26443`

6. Tear the lab down when finished:

```bash
terraform destroy
```

## Bootstrap behavior

- The k3s server writes `/home/<admin_username>/.kube/config` for convenience.
- Bootstrap logs are written to `/var/log/bootstrap-k3s-server.log`, `/var/log/bootstrap-k3s-agent.log`, and `/var/log/bootstrap-legacy.log`.
- The configuration intentionally does not install Calico. That remains manual because the Calico-on-Cilium combination is the subject under test.
- If you enable the second cluster, it is still Cilium-only. To bring its nodes under cluster-1 Calico host policy, use `scripts/onboard-external-k8s-hosts.sh` after the cluster is healthy.

## Dependencies

- Terraform
- Azure credentials accepted by the `azurerm` provider
- an existing SSH key pair
- `ssh` to reach the jumpbox and private VMs
