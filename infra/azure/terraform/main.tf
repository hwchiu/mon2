locals {
  common_tags = merge(
    {
      workload   = "calico-hostendpoint-lab"
      managed_by = "terraform"
    },
    var.tags,
  )

  ssh_public_key = trimspace(file(var.ssh_public_key_path))

  jumpbox_name          = "${var.name_prefix}-jumpbox"
  k3s_server_name       = "${var.name_prefix}-k3s-server-0"
  jumpbox_private_ip    = cidrhost(var.management_subnet_cidr, 10)
  k3s_server_private_ip = cidrhost(var.cluster_subnet_cidr, 10)

  k3s_agent_private_ips = [
    for idx in range(var.k3s_agent_count) : cidrhost(var.cluster_subnet_cidr, 11 + idx)
  ]

  legacy_private_ips = [
    for idx in range(var.legacy_vm_count) : cidrhost(var.legacy_subnet_cidr, 20 + idx)
  ]

  k3s_agents = {
    for idx, ip in local.k3s_agent_private_ips :
    format("%s-k3s-agent-%02d", var.name_prefix, idx + 1) => ip
  }

  legacy_vms = {
    for idx, ip in local.legacy_private_ips :
    format("%s-legacy-%02d", var.name_prefix, idx + 1) => ip
  }
}

resource "random_password" "k3s_token" {
  length  = 40
  special = false
}

resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "lab" {
  name                = var.vnet_name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [var.vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "management" {
  name                 = var.management_subnet_name
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.management_subnet_cidr]
}

resource "azurerm_subnet" "cluster" {
  name                 = var.cluster_subnet_name
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.cluster_subnet_cidr]
}

resource "azurerm_subnet" "legacy" {
  name                 = var.legacy_subnet_name
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.legacy_subnet_cidr]
}

resource "azurerm_network_security_group" "management" {
  name                = "${var.name_prefix}-mgmt-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.common_tags
}

resource "azurerm_network_security_rule" "management_ssh" {
  name                        = "allow-admin-ssh"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = var.admin_cidr
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.management.name
}

resource "azurerm_network_security_group" "workload" {
  name                = "${var.name_prefix}-workload-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.common_tags
}

resource "azurerm_subnet_network_security_group_association" "management" {
  subnet_id                 = azurerm_subnet.management.id
  network_security_group_id = azurerm_network_security_group.management.id
}

resource "azurerm_subnet_network_security_group_association" "cluster" {
  subnet_id                 = azurerm_subnet.cluster.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

resource "azurerm_subnet_network_security_group_association" "legacy" {
  subnet_id                 = azurerm_subnet.legacy.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

resource "azurerm_public_ip" "jumpbox" {
  name                = "${local.jumpbox_name}-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = merge(local.common_tags, { role = "jumpbox" })
}

resource "azurerm_network_interface" "jumpbox" {
  name                = "${local.jumpbox_name}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = merge(local.common_tags, { role = "jumpbox" })

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.management.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.jumpbox_private_ip
    public_ip_address_id          = azurerm_public_ip.jumpbox.id
  }
}

resource "azurerm_network_interface" "k3s_server" {
  name                = "${local.k3s_server_name}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = merge(local.common_tags, { role = "k3s-server" })

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.cluster.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.k3s_server_private_ip
  }
}

resource "azurerm_network_interface" "k3s_agents" {
  for_each            = local.k3s_agents
  name                = "${each.key}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = merge(local.common_tags, { role = "k3s-agent" })

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.cluster.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value
  }
}

resource "azurerm_network_interface" "legacy" {
  for_each            = local.legacy_vms
  name                = "${each.key}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = merge(local.common_tags, { role = "legacy-vm" })

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.legacy.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value
  }
}

resource "azurerm_linux_virtual_machine" "jumpbox" {
  name                = local.jumpbox_name
  computer_name       = local.jumpbox_name
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  size                = var.jumpbox_vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.jumpbox.id,
  ]
  disable_password_authentication = true
  custom_data                     = base64encode(templatefile("${path.module}/templates/jumpbox-cloud-init.tftpl", {}))
  tags                            = merge(local.common_tags, { role = "jumpbox" })

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

resource "azurerm_linux_virtual_machine" "k3s_server" {
  name                = local.k3s_server_name
  computer_name       = local.k3s_server_name
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  size                = var.k3s_vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.k3s_server.id,
  ]
  disable_password_authentication = true
  custom_data = base64encode(templatefile("${path.module}/templates/k3s-server-cloud-init.tftpl", {
    admin_username      = var.admin_username
    cilium_version      = var.cilium_version
    cluster_cidr        = var.cluster_cidr
    expected_node_count = var.k3s_agent_count + 1
    k3s_token           = random_password.k3s_token.result
    k3s_version         = var.k3s_version
    server_private_ip   = local.k3s_server_private_ip
    service_cidr        = var.service_cidr
  }))
  tags = merge(local.common_tags, { role = "k3s-server" })

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

resource "azurerm_linux_virtual_machine" "k3s_agents" {
  for_each            = local.k3s_agents
  name                = each.key
  computer_name       = each.key
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  size                = var.k3s_vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.k3s_agents[each.key].id,
  ]
  disable_password_authentication = true
  custom_data = base64encode(templatefile("${path.module}/templates/k3s-agent-cloud-init.tftpl", {
    k3s_token         = random_password.k3s_token.result
    k3s_version       = var.k3s_version
    node_private_ip   = each.value
    server_private_ip = local.k3s_server_private_ip
  }))
  tags = merge(local.common_tags, { role = "k3s-agent" })

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

resource "azurerm_linux_virtual_machine" "legacy" {
  for_each            = local.legacy_vms
  name                = each.key
  computer_name       = each.key
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  size                = var.legacy_vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.legacy[each.key].id,
  ]
  disable_password_authentication = true
  custom_data = base64encode(templatefile("${path.module}/templates/legacy-vm-cloud-init.tftpl", {
    vm_name = each.key
  }))
  tags = merge(local.common_tags, { role = "legacy-vm" })

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}
