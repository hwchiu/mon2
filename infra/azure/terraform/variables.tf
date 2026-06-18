variable "subscription_id" {
  description = "Azure subscription ID. Leave empty to use the active Azure CLI context."
  type        = string
  default     = ""
}

variable "location" {
  description = "Azure region for all lab resources."
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Resource group for the lab."
  type        = string
  default     = "rg-calico-hep-lab"
}

variable "name_prefix" {
  description = "Prefix used for Azure resource names."
  type        = string
  default     = "hep-lab"
}

variable "tags" {
  description = "Additional tags applied to all Azure resources."
  type        = map(string)
  default     = {}
}

variable "vnet_name" {
  description = "Virtual network name."
  type        = string
  default     = "vnet-calico-hep-lab"
}

variable "vnet_cidr" {
  description = "Address space for the Azure VNet."
  type        = string
  default     = "10.70.0.0/16"
}

variable "management_subnet_name" {
  description = "Subnet name for the jumpbox."
  type        = string
  default     = "snet-mgmt"
}

variable "management_subnet_cidr" {
  description = "CIDR for the jumpbox subnet."
  type        = string
  default     = "10.70.0.0/24"
}

variable "cluster_subnet_name" {
  description = "Subnet name for k3s nodes."
  type        = string
  default     = "snet-k3s"
}

variable "cluster_subnet_cidr" {
  description = "CIDR for the k3s node subnet."
  type        = string
  default     = "10.70.10.0/24"
}

variable "legacy_subnet_name" {
  description = "Subnet name for standalone legacy VMs."
  type        = string
  default     = "snet-legacy"
}

variable "legacy_subnet_cidr" {
  description = "CIDR for the standalone VM subnet."
  type        = string
  default     = "10.70.20.0/24"
}

variable "cluster2_subnet_name" {
  description = "Subnet name for the optional second k3s cluster."
  type        = string
  default     = "snet-k3s-2"
}

variable "cluster2_subnet_cidr" {
  description = "CIDR for the optional second k3s cluster."
  type        = string
  default     = "10.70.30.0/24"
}

variable "admin_cidr" {
  description = "Source CIDR allowed to SSH to the jumpbox."
  type        = string
}

variable "admin_username" {
  description = "Admin username for all Linux VMs."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Absolute path to the SSH public key that will be installed on all VMs."
  type        = string
}

variable "jumpbox_vm_size" {
  description = "Azure VM size for the jumpbox."
  type        = string
  default     = "Standard_B2s"
}

variable "k3s_vm_size" {
  description = "Azure VM size for the k3s server and agents."
  type        = string
  default     = "Standard_B2s"
}

variable "legacy_vm_size" {
  description = "Azure VM size for legacy standalone VMs."
  type        = string
  default     = "Standard_B2s"
}

variable "cilium_linux_vm_enabled" {
  description = "Whether to provision a dedicated Linux standalone VM for the Cilium validation flow."
  type        = bool
  default     = false
}

variable "cilium_linux_vm_size" {
  description = "Azure VM size for the dedicated Linux standalone VM used by the Cilium validation flow."
  type        = string
  default     = "Standard_B2s"
}

variable "cilium_windows_vm_enabled" {
  description = "Whether to provision a dedicated Windows standalone VM for the Cilium validation flow."
  type        = bool
  default     = false
}

variable "cilium_windows_vm_size" {
  description = "Azure VM size for the dedicated Windows standalone VM used by the Cilium validation flow."
  type        = string
  default     = "Standard_B2s"
}

variable "windows_admin_username" {
  description = "Admin username for the dedicated Windows standalone VM."
  type        = string
  default     = "azureuser"
}

variable "windows_admin_password" {
  description = "Admin password for the dedicated Windows standalone VM. Required when cilium_windows_vm_enabled is true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cluster2_enabled" {
  description = "Whether to provision the optional second k3s cluster."
  type        = bool
  default     = false
}

variable "cluster2_vm_size" {
  description = "Azure VM size for the second k3s cluster."
  type        = string
  default     = "Standard_B2s"
}

variable "k3s_agent_count" {
  description = "Number of k3s agent nodes."
  type        = number
  default     = 2
}

variable "legacy_vm_count" {
  description = "Number of standalone legacy VMs."
  type        = number
  default     = 2
}

variable "cluster2_agent_count" {
  description = "Number of agent nodes in the optional second k3s cluster."
  type        = number
  default     = 2
}

variable "k3s_version" {
  description = "Pinned k3s version such as v1.33.1+k3s1. Leave empty to install the installer default."
  type        = string
  default     = ""
}

variable "cilium_version" {
  description = "Pinned Cilium version installed by the Cilium CLI."
  type        = string
  default     = "1.19.4"
}

variable "cilium_cli_version" {
  description = "Optional pinned cilium-cli release tag such as v0.16.24. Leave empty to download the current stable cilium-cli release."
  type        = string
  default     = ""
}

variable "cluster_cidr" {
  description = "Pod CIDR passed to k3s and Cilium."
  type        = string
  default     = "10.42.0.0/16"
}

variable "service_cidr" {
  description = "Service CIDR passed to k3s."
  type        = string
  default     = "10.43.0.0/16"
}

variable "cluster2_cluster_cidr" {
  description = "Pod CIDR passed to the second k3s cluster and its Cilium install."
  type        = string
  default     = "10.52.0.0/16"
}

variable "cluster2_service_cidr" {
  description = "Service CIDR passed to the second k3s cluster."
  type        = string
  default     = "10.53.0.0/16"
}
