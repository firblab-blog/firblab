output "container_id" {
  description = "Proxmox container ID"
  value       = proxmox_virtual_environment_container.this.vm_id
}

output "ipv4_addresses" {
  description = "IPv4 addresses assigned to the container"
  value       = proxmox_virtual_environment_container.this.initialization[0].ip_config[0].ipv4[0].address
}

output "ssh_private_key" {
  description = "Generated SSH private key for container access"
  value       = tls_private_key.container_key.private_key_openssh
  sensitive   = true
}

output "ssh_public_key" {
  description = "Generated SSH public key"
  value       = tls_private_key.container_key.public_key_openssh
}

output "ssh_private_key_path" {
  description = "Path to the saved SSH private key file"
  value       = local_file.container_private_key.filename
}

output "password" {
  description = "Generated container password"
  value       = random_password.container_password.result
  sensitive   = true
}

output "hostname" {
  description = "Container hostname"
  value       = var.name
}
