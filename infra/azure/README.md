# Azure Lab Scaffolding

The Azure lab is now provisioned with Terraform under [infra/azure/terraform](/home/ubuntu/calico/infra/azure/terraform).

## What Terraform creates

- one public jumpbox VM
- one k3s server VM
- a configurable number of k3s agent VMs
- a configurable number of standalone legacy VMs
- one VNet with management, k3s, and legacy subnets
- NSGs that keep public SSH limited to the jumpbox

The k3s server boots with Flannel disabled and the built-in network policy controller disabled. After the k3s API is up, the server installs Cilium and waits for it to become healthy. Legacy VMs are bootstrapped with NGINX and basic troubleshooting tools.

## Files

- `terraform/versions.tf`: provider and Terraform version requirements
- `terraform/variables.tf`: input variables
- `terraform/main.tf`: Azure network, NIC, VM, and bootstrap definitions
- `terraform/outputs.tf`: IPs and helper commands
- `terraform/terraform.tfvars.example`: example input values
- `terraform/templates/*.tftpl`: cloud-init templates for the jumpbox, k3s nodes, and legacy VMs

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

6. Tear the lab down when finished:

```bash
terraform destroy
```

## Bootstrap behavior

- The k3s server writes `/home/<admin_username>/.kube/config` for convenience.
- Bootstrap logs are written to `/var/log/bootstrap-k3s-server.log`, `/var/log/bootstrap-k3s-agent.log`, and `/var/log/bootstrap-legacy.log`.
- The configuration intentionally does not install Calico. That remains manual because the Calico-on-Cilium combination is the subject under test.

## Dependencies

- Terraform
- Azure credentials accepted by the `azurerm` provider
- an existing SSH key pair
- `ssh` to reach the jumpbox and private VMs
