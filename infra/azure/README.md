# Azure Lab Scaffolding

The Azure lab is provisioned with Terraform under `infra/azure/terraform`.

## What Terraform creates

- one public jumpbox VM
- one primary k3s server VM
- a configurable number of primary k3s agent VMs
- an optional second k3s cluster on its own subnet
- a configurable number of standalone legacy VMs
- optional dedicated Cilium standalone VMs: one Linux host and one Windows host, both on the existing legacy subnet
- one VNet with management, primary k3s, optional secondary k3s, and legacy subnets
- NSGs that keep public SSH limited to the jumpbox

The k3s server boots with Flannel disabled and the built-in network policy controller disabled. After the k3s API is up, the server installs Cilium and waits for it to become healthy. Legacy VMs are bootstrapped with NGINX and basic troubleshooting tools.

The dedicated Cilium Linux standalone VM is opt-in and installs Docker, curl, jq, `netcat-openbsd`, and NGINX, then writes a simple test artifact that is also served through NGINX. The dedicated Cilium Windows standalone VM is also opt-in and uses a Custom Script Extension to enable OpenSSH, install IIS, bind HTTP on TCP `18080`, write a simple test page, and open firewall access for `18080`.

Default lab behavior is unchanged unless you explicitly enable the new Cilium standalone VM booleans.

## Files

- `terraform/versions.tf`: provider and Terraform version requirements
- `terraform/variables.tf`: input variables
- `terraform/main.tf`: Azure network, NIC, VM, and bootstrap definitions
- `terraform/outputs.tf`: IPs and helper commands
- `terraform/terraform.tfvars.example`: example input values
- `terraform/terraform.cilium-standalone.tfvars.example`: pinned example for the deprecated Cilium standalone-host validation flow
- `terraform/templates/*.tftpl`: cloud-init templates for the jumpbox, k3s nodes, legacy VMs, and the optional Cilium standalone VMs
- `../../scripts/onboard-external-k8s-hosts.sh`: post-provision onboarding for cluster-2 nodes as Calico-managed external hosts

## Usage

1. Authenticate to Azure with `az login` or another supported `azurerm` auth method.
2. Change into the Terraform directory:

```bash
cd infra/azure/terraform
```

3. Copy the example vars file that matches the validation track and update it. Use an absolute path for `ssh_public_key_path` because Terraform's `file()` function does not expand `~`.

```bash
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
```

For the standalone Cilium validation round described in
`docs/cilium-standalone-host-validation.md`, start from the pinned example
instead:

```bash
cp terraform.cilium-standalone.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
```

That dedicated example:

- pins `k3s_version`, `cilium_version`, and `cilium_cli_version` to the older combination required by the deprecated Linux external-workload flow
- enables the dedicated Linux and Windows standalone VMs
- sets `legacy_vm_count = 0` so the lab shape matches the round-1 document more closely
- gives `scripts/onboard-cilium-linux-external-workload.sh` a repo-local `cilium_cli_version` source so the deprecated Linux onboarding helper can download the pinned old CLI by default

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

If you enable the dedicated Cilium standalone hosts, Terraform also returns:

- the dedicated Linux standalone VM private IP
- the dedicated Windows standalone VM private IP
- an SSH command for the Linux standalone VM through the jumpbox
- an SSH command for the Windows standalone VM through the jumpbox after OpenSSH finishes bootstrapping
- a jumpbox tunnel command that forwards local port `18080` to the Windows IIS listener

6. Tear the lab down when finished:

```bash
terraform destroy
```

## Opt-In Cilium Standalone Hosts

Enable one or both of these booleans in `terraform.tfvars`:

```hcl
cilium_linux_vm_enabled   = true
cilium_windows_vm_enabled = true
windows_admin_password    = "SetARealAzurePassword123!"
```

Relevant variables:

- `cilium_linux_vm_enabled`: creates the dedicated Linux standalone VM on the legacy subnet
- `cilium_linux_vm_size`: overrides the Linux VM size
- `cilium_windows_vm_enabled`: creates the dedicated Windows standalone VM on the legacy subnet
- `cilium_windows_vm_size`: overrides the Windows VM size
- `cilium_cli_version`: optionally pins the `cilium` CLI release tag downloaded during k3s server bootstrap
- `windows_admin_username`: admin username for the Windows VM
- `windows_admin_password`: required when the Windows VM is enabled and must satisfy Azure Windows password requirements

The Windows bootstrap reuses the public key loaded from `ssh_public_key_path` and writes it into `C:\ProgramData\ssh\administrators_authorized_keys` so the jumpbox can reach the VM over OpenSSH once the Custom Script Extension completes.

## Bootstrap behavior

- The k3s server writes `/home/<admin_username>/.kube/config` for convenience.
- When `cilium_cli_version` is set, the k3s server downloads that exact `cilium` CLI release tag instead of the current stable CLI.
- Bootstrap logs are written to `/var/log/bootstrap-k3s-server.log`, `/var/log/bootstrap-k3s-agent.log`, `/var/log/bootstrap-legacy.log`, and `/var/log/bootstrap-cilium-linux.log` when the dedicated Linux standalone VM is enabled.
- The Windows bootstrap is logged by the Azure Custom Script Extension under `C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\`.
- The configuration intentionally does not install Calico. That remains manual because the Calico-on-Cilium combination is the subject under test.
- If you enable the second cluster, it is still Cilium-only. To bring its nodes under cluster-1 Calico host policy, use `scripts/onboard-external-k8s-hosts.sh` after the cluster is healthy.

## Dependencies

- Terraform
- Azure credentials accepted by the `azurerm` provider
- an existing SSH key pair
- `ssh` to reach the jumpbox and private VMs
