# Cilium Standalone Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add repo-native infrastructure, experiment assets, and one single narrative document for a Cilium-based standalone host validation that covers k3s nodes, one Linux standalone VM, and one Windows standalone VM.

**Architecture:** Keep the current Azure VM lab as the base, add optional Cilium-specific standalone hosts without breaking the existing Calico assets, implement the cluster-node host-policy and Linux external-workload experiment assets in separate files, and consolidate the full setup story, limitations, and testing cases into one markdown file.

**Tech Stack:** Terraform (`azurerm`), Azure VM extensions, k3s, Cilium, Bash, PowerShell, Markdown

---

## File Structure

### Infrastructure

- Modify: `infra/azure/terraform/variables.tf`
  Purpose: Add opt-in variables for one Cilium Linux standalone VM and one Windows standalone VM.
- Modify: `infra/azure/terraform/main.tf`
  Purpose: Add NICs, VM resources, and Windows bootstrap extension without changing the current default lab behavior.
- Modify: `infra/azure/terraform/outputs.tf`
  Purpose: Publish IPs and helper commands for the new hosts.
- Create: `infra/azure/terraform/templates/cilium-linux-vm-cloud-init.tftpl`
  Purpose: Bootstrap a Linux standalone host with Docker and basic troubleshooting tools for the legacy Cilium external-workload path.
- Create: `infra/azure/terraform/templates/cilium-windows-bootstrap.ps1.tftpl`
  Purpose: Bootstrap Windows with OpenSSH, IIS on TCP `18080`, and a predictable test artifact.
- Modify: `infra/azure/README.md`
  Purpose: Document the new opt-in Cilium standalone host infrastructure.

### Experiment Assets

- Create: `manifests/cilium/README.md`
  Purpose: Top-level entry for Cilium-specific assets.
- Create: `manifests/cilium/host-experiment/README.md`
  Purpose: Explain the split model: cluster host policy vs Linux external workload vs Windows limitation.
- Create: `manifests/cilium/host-experiment/10-zone1-allow-node-http.yaml`
  Purpose: Allow TCP `18080` to zone-1 labeled nodes from the intended sources.
- Create: `manifests/cilium/host-experiment/20-zone2-deny-node-http.yaml`
  Purpose: Deny TCP `18080` to zone-2 labeled nodes.
- Create: `manifests/cilium/host-experiment/30-linux-external-workload-http.yaml`
  Purpose: Example endpoint policy for the attached Linux external workload.
- Create: `scripts/onboard-cilium-linux-external-workload.sh`
  Purpose: Automate the deprecated Linux external-workload registration flow as far as the older Cilium CLI supports it.
- Create: `scripts/run-cilium-standalone-experiment.sh`
  Purpose: Install the dedicated test service where needed and execute the allow/deny matrix.

### Single-File Story

- Create: `docs/cilium-standalone-host-validation.md`
  Purpose: Be the single source for the whole story: architecture, setup, limitations, test cases, expected results, result classification, and execution checklist.
- Modify: `README.md`
  Purpose: Point readers to the single-file Cilium validation document.

## Task 1: Add Opt-In Azure Infrastructure For Cilium Standalone Hosts

**Files:**
- Create: `infra/azure/terraform/templates/cilium-linux-vm-cloud-init.tftpl`
- Create: `infra/azure/terraform/templates/cilium-windows-bootstrap.ps1.tftpl`
- Modify: `infra/azure/terraform/variables.tf`
- Modify: `infra/azure/terraform/main.tf`
- Modify: `infra/azure/terraform/outputs.tf`
- Modify: `infra/azure/README.md`

- [ ] **Step 1: Add the new Terraform variables**

Add opt-in controls similar to:

```hcl
variable "cilium_linux_vm_enabled" {
  description = "Whether to provision a dedicated Linux standalone VM for the Cilium validation flow."
  type        = bool
  default     = false
}

variable "cilium_windows_vm_enabled" {
  description = "Whether to provision a dedicated Windows standalone VM for the Cilium validation flow."
  type        = bool
  default     = false
}

variable "cilium_linux_vm_size" {
  description = "Azure VM size for the standalone Linux VM used by the Cilium validation flow."
  type        = string
  default     = "Standard_B2s"
}

variable "cilium_windows_vm_size" {
  description = "Azure VM size for the standalone Windows VM used by the Cilium validation flow."
  type        = string
  default     = "Standard_B2s"
}

variable "windows_admin_username" {
  description = "Admin username for the standalone Windows VM."
  type        = string
  default     = "azureuser"
}

variable "windows_admin_password" {
  description = "Admin password for the standalone Windows VM. Required when cilium_windows_vm_enabled is true."
  type        = string
  default     = ""
  sensitive   = true
}
```

- [ ] **Step 2: Extend `main.tf` with standalone host resources**

Add:

- local names and fixed private IPs for the new Linux and Windows hosts
- network interfaces on the existing standalone/legacy subnet
- one `azurerm_linux_virtual_machine` using `cilium-linux-vm-cloud-init.tftpl`
- one `azurerm_windows_virtual_machine`
- one `azurerm_virtual_machine_extension` using `cilium-windows-bootstrap.ps1.tftpl`

Use patterns already present in `main.tf`, for example:

```hcl
resource "azurerm_network_interface" "cilium_linux_vm" {
  count               = var.cilium_linux_vm_enabled ? 1 : 0
  name                = "${local.cilium_linux_vm_name}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.legacy.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.cilium_linux_vm_private_ip
  }
}
```

For the Windows extension, keep the script idempotent and restricted to:

- installing and enabling OpenSSH Server
- installing IIS
- binding IIS to `18080`
- writing a simple lab page
- opening firewall for `18080`

- [ ] **Step 3: Add the Linux bootstrap template**

Create a cloud-init template that installs the minimum host prerequisites:

```yaml
#cloud-config
package_update: true
package_upgrade: false
packages:
  - curl
  - jq
  - netcat-openbsd
  - docker.io
  - nginx
write_files:
  - path: /usr/local/bin/bootstrap-cilium-linux.sh
    permissions: "0755"
    content: |
      #!/usr/bin/env bash
      set -euxo pipefail
      systemctl enable --now docker
      systemctl enable --now nginx
      mkdir -p /etc/lab
      printf '{\"host\":\"%s\",\"role\":\"cilium-linux-standalone\"}\n' '${vm_name}' > /var/www/html/index.html
runcmd:
  - [bash, -lc, "/usr/local/bin/bootstrap-cilium-linux.sh > /var/log/bootstrap-cilium-linux.log 2>&1"]
```

- [ ] **Step 4: Add the Windows bootstrap PowerShell template**

Create a PowerShell template that:

- enables OpenSSH server
- writes the provided SSH public key into `administrators_authorized_keys`
- installs IIS
- configures an `18080` binding
- writes a simple `index.html`

Use a structure like:

```powershell
$ErrorActionPreference = "Stop"

Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

New-Item -ItemType Directory -Force -Path "C:\ProgramData\ssh" | Out-Null
Set-Content -Path "C:\ProgramData\ssh\administrators_authorized_keys" -Value @'
${ssh_public_key}
'@

Install-WindowsFeature -Name Web-Server -IncludeManagementTools
New-Item -ItemType Directory -Force -Path "C:\inetpub\lab" | Out-Null
Set-Content -Path "C:\inetpub\lab\index.html" -Value "<html><body>${vm_name}</body></html>"
```

- [ ] **Step 5: Add outputs and usage docs**

Add outputs similar to:

```hcl
output "cilium_linux_vm_private_ip" {
  value = try(azurerm_network_interface.cilium_linux_vm[0].ip_configuration[0].private_ip_address, null)
}

output "cilium_windows_vm_private_ip" {
  value = try(azurerm_network_interface.cilium_windows_vm[0].ip_configuration[0].private_ip_address, null)
}
```

Document the new variables and outputs in `infra/azure/README.md`.

- [ ] **Step 6: Verify formatting and syntax**

Run:

```bash
terraform -chdir=infra/azure/terraform fmt
terraform -chdir=infra/azure/terraform validate
```

Expected:

- `terraform fmt` rewrites only formatting
- `terraform validate` succeeds if credentials/provider initialization are available

If `terraform validate` cannot run because the provider is not initialized in this environment, record that explicitly.

- [ ] **Step 7: Commit the infrastructure slice**

Run:

```bash
git add infra/azure/terraform infra/azure/README.md
git commit -m "feat: add cilium standalone host lab infrastructure"
```

## Task 2: Add Cilium Experiment Manifests And Automation

**Files:**
- Create: `manifests/cilium/README.md`
- Create: `manifests/cilium/host-experiment/README.md`
- Create: `manifests/cilium/host-experiment/10-zone1-allow-node-http.yaml`
- Create: `manifests/cilium/host-experiment/20-zone2-deny-node-http.yaml`
- Create: `manifests/cilium/host-experiment/30-linux-external-workload-http.yaml`
- Create: `scripts/onboard-cilium-linux-external-workload.sh`
- Create: `scripts/run-cilium-standalone-experiment.sh`

- [ ] **Step 1: Create the Cilium manifests tree**

Create a new manifest area that keeps Cilium assets separate from `manifests/calico`.

`manifests/cilium/README.md` must explain:

- cluster-node host policy is a Cilium host-firewall path
- Linux standalone onboarding uses deprecated external workloads
- Windows remains an explicit target with no assumed success path

- [ ] **Step 2: Add host-policy manifests for the dedicated test port**

Create CCNP manifests that only touch TCP `18080`.

Use the `nodeSelector` form for cluster nodes, for example:

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: cilium-zone1-allow-node-http
spec:
  nodeSelector:
    matchLabels:
      lab.cilium.io/zone: zone1
  ingress:
    - fromCIDRSet:
        - cidr: 10.70.10.0/24
        - cidr: 10.70.20.30/32
      toPorts:
        - ports:
            - port: "18080"
              protocol: TCP
```

Keep the policies narrow and document any assumptions inline.

- [ ] **Step 3: Add the Linux external workload policy example**

Create `30-linux-external-workload-http.yaml` using endpoint-style policy, not node policy.

The file must make the limitation explicit in comments and labels, for example:

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: cilium-linux-external-workload-http
spec:
  endpointSelector:
    matchLabels:
      io.kubernetes.pod.name: hep-lab-cilium-linux
  ingress:
    - fromCIDRSet:
        - cidr: 10.70.10.0/24
      toPorts:
        - ports:
            - port: "18080"
              protocol: TCP
```

- [ ] **Step 4: Add Linux external workload onboarding automation**

Create `scripts/onboard-cilium-linux-external-workload.sh` that:

- checks for `kubectl`, `cilium`, `ssh`, `scp`
- enables clustermesh external workloads on a user-specified older Cilium line
- creates the external workload registration
- generates the install script
- copies and runs it on the Linux VM through the jumpbox

Core flow:

```bash
cilium clustermesh enable --service-type NodePort --enable-external-workloads
cilium clustermesh vm create "$WORKLOAD_NAME" -n default --ipv4-alloc-cidr "$ALLOC_CIDR"
cilium clustermesh vm install "$WORKDIR/install-external-workload.sh"
scp ... "$WORKDIR/install-external-workload.sh" "$REMOTE_TARGET:/tmp/"
ssh ... "$REMOTE_TARGET" "sudo HOST_IP=$HOST_IP bash /tmp/install-external-workload.sh"
```

The script must warn that:

- the path is deprecated
- success on Linux does not imply equivalent host-firewall semantics

- [ ] **Step 5: Add the main experiment runner**

Create `scripts/run-cilium-standalone-experiment.sh` that:

- installs a dedicated test service on Linux nodes and Linux standalone VM
- assumes the Windows bootstrap already exposed IIS on `18080`
- applies the Cilium manifests
- runs a pass/fail matrix
- prints result lines suitable for the single-file report

Use the current `scripts/run-zone-isolation-experiment.sh` as the model for:

- argument parsing
- SSH through jumpbox
- dedicated service bootstrap
- pass/fail output formatting

- [ ] **Step 6: Verify script and YAML quality**

Run:

```bash
bash -n scripts/onboard-cilium-linux-external-workload.sh
bash -n scripts/run-cilium-standalone-experiment.sh
```

If `shellcheck` is available, also run:

```bash
shellcheck scripts/onboard-cilium-linux-external-workload.sh scripts/run-cilium-standalone-experiment.sh
```

Use `kubectl apply --dry-run=client` only if a cluster context is available; otherwise note that YAML syntax was checked structurally and not applied.

- [ ] **Step 7: Commit the experiment slice**

Run:

```bash
git add manifests/cilium scripts
git commit -m "feat: add cilium standalone host experiment assets"
```

## Task 3: Write The Single Story And Testing File

**Files:**
- Create: `docs/cilium-standalone-host-validation.md`
- Modify: `README.md`

- [ ] **Step 1: Create the single-file document skeleton**

The document must be the one place a reader can understand the whole flow. Use this structure:

```md
# Cilium Standalone Host Validation

## Why this exists
## Topology
## What is actually under test
## Important limitations
## Azure provisioning
## Cluster setup
## Linux standalone host attachment
## Windows standalone host attempt
## Round 1 test cases
## Expected results matrix
## Result classification
## Evidence checklist
## Rollback
```

- [ ] **Step 2: Fill in the actual story and test cases**

The content must explicitly state:

- cluster nodes use host policy
- Linux standalone uses deprecated external workloads
- Windows may end in a validated fail
- the first round only uses dedicated TCP `18080`

Include a concrete table like:

```md
| ID | Source | Destination | Port | Expected | Notes |
| --- | --- | --- | --- | --- | --- |
| C01 | zone1 node | zone1 node | 18080 | allow | cluster host policy |
| C02 | zone1 node | zone2 node | 18080 | deny | cluster host policy |
| C03 | zone1 node | linux standalone | 18080 | allow/deny per policy | deprecated external workload path |
| C04 | linux standalone | zone1 node | 18080 | allow/deny per policy | deprecated external workload path |
| C05 | zone1 node | windows standalone | 18080 | observe / unsupported if unattached | explicit Windows branch |
```

- [ ] **Step 3: Add limitation and verdict sections**

Include a verdict taxonomy identical to the spec:

```md
- Supported pass
- Supported fail
- Deprecated path pass
- Deprecated path fail
- No official standalone Windows path found
- Attempted path incompatible with Windows
- Lab/config error
- Unclear / needs more evidence
```

Make the distinction between product limitation and lab error unavoidable in the document.

- [ ] **Step 4: Link the new single-file doc from the repo root**

Update `README.md` so the Cilium document is discoverable from the top of the repo.

Add a short paragraph like:

```md
For the Cilium-based standalone host validation, see `docs/cilium-standalone-host-validation.md`.
```

- [ ] **Step 5: Verify markdown quality**

Run:

```bash
sed -n '1,260p' docs/cilium-standalone-host-validation.md
```

Check manually that:

- the file is self-contained
- the setup flow and test matrix are both present
- limitations are stated in the same document, not elsewhere

- [ ] **Step 6: Commit the documentation slice**

Run:

```bash
git add docs/cilium-standalone-host-validation.md README.md
git commit -m "docs: add cilium standalone validation story"
```

## Task 4: Integration And Final Verification

**Files:**
- Review all changes from Tasks 1-3

- [ ] **Step 1: Rebase or merge task commits if needed**

If task branches or subagent commits are isolated, integrate them into the feature branch cleanly.

- [ ] **Step 2: Run repo-level verification commands**

Run:

```bash
terraform -chdir=infra/azure/terraform fmt -check
bash -n scripts/onboard-cilium-linux-external-workload.sh
bash -n scripts/run-cilium-standalone-experiment.sh
git diff --check
```

Expected:

- no Terraform formatting drift
- shell scripts parse cleanly
- no whitespace errors

- [ ] **Step 3: Sanity-read the single-file story against the actual assets**

Verify the document references the actual paths created:

- `infra/azure/terraform/...`
- `manifests/cilium/...`
- `scripts/onboard-cilium-linux-external-workload.sh`
- `scripts/run-cilium-standalone-experiment.sh`

- [ ] **Step 4: Create the final feature commit if integration changed anything**

Run:

```bash
git add -A
git commit -m "chore: integrate cilium standalone validation assets"
```

Only do this if there are uncommitted integration edits.

- [ ] **Step 5: Merge back to `master`**

From the main checkout:

```bash
git checkout master
git merge --ff-only feat/cilium-standalone-validation
```

If `--ff-only` fails because extra commits landed on `master`, rebase the feature branch first and then merge.
