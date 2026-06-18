output "bastion_public_ip" {
  value = azurerm_public_ip.bastion_pip.ip_address
}

output "lb_public_ip" {
  value       = azurerm_public_ip.lb_pip.ip_address
  description = "Public IP of the Load Balancer"
}

output "endpoint_url" {
  value       = "http://${azurerm_public_ip.lb_pip.ip_address}/v1/completions"
  description = "vLLM API endpoint URL"
}

output "gpu_private_ip" {
  value       = azurerm_network_interface.gpu_nic.private_ip_address
  description = "Private IP of the GPU node"
}

output "ssh_command" {
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.bastion_pip.ip_address}"
  description = "SSH command to connect to Bastion Host"
}

output "resource_group_name" {
  value       = azurerm_resource_group.ai_rg.name
  description = "Name of the Resource Group (for cleanup)"
}
