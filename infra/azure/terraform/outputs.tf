output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "jumpbox_public_ip" {
  value = azurerm_public_ip.jumpbox.ip_address
}

output "jumpbox_private_ip" {
  value = azurerm_network_interface.jumpbox.ip_configuration[0].private_ip_address
}

output "k3s_server_private_ip" {
  value = azurerm_network_interface.k3s_server.ip_configuration[0].private_ip_address
}

output "k3s_agent_private_ips" {
  value = {
    for name, nic in azurerm_network_interface.k3s_agents :
    name => nic.ip_configuration[0].private_ip_address
  }
}

output "legacy_private_ips" {
  value = {
    for name, nic in azurerm_network_interface.legacy :
    name => nic.ip_configuration[0].private_ip_address
  }
}

output "ssh_jumpbox_command" {
  value = "ssh ${var.admin_username}@${azurerm_public_ip.jumpbox.ip_address}"
}

output "ssh_k3s_server_via_jumpbox_command" {
  value = "ssh -J ${var.admin_username}@${azurerm_public_ip.jumpbox.ip_address} ${var.admin_username}@${azurerm_network_interface.k3s_server.ip_configuration[0].private_ip_address}"
}

output "ssh_kubeapi_tunnel_command" {
  value = "ssh -N -L 6443:${azurerm_network_interface.k3s_server.ip_configuration[0].private_ip_address}:6443 ${var.admin_username}@${azurerm_public_ip.jumpbox.ip_address}"
}

output "k3s_bootstrap_notes" {
  value = <<-EOT
  Fetch /etc/rancher/k3s/k3s.yaml through the jumpbox and keep an SSH tunnel open to local port 6443 when using kubectl from your workstation.
  Bootstrap logs:
  - /var/log/bootstrap-k3s-server.log
  - /var/log/bootstrap-k3s-agent.log
  - /var/log/bootstrap-legacy.log
  EOT
}
