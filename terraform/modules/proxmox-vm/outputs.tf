output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "ipv4_addresses" {
  description = "IPv4 addresses assigned to the VM"
  value       = proxmox_virtual_environment_vm.this.ipv4_addresses
}

output "ssh_private_key" {
  description = "Generated SSH private key for VM access"
  value       = tls_private_key.vm_key.private_key_openssh
  sensitive   = true
}

output "ssh_public_key" {
  description = "Generated SSH public key"
  value       = tls_private_key.vm_key.public_key_openssh
}

output "ssh_private_key_path" {
  description = "Path to the saved SSH private key file"
  value       = local_file.vm_private_key.filename
}

output "password" {
  description = "Generated VM password"
  value       = random_password.vm_password.result
  sensitive   = true
}

output "hostname" {
  description = "VM hostname"
  value       = var.name
}

output "name" {
  description = "VM name in Proxmox"
  value       = proxmox_virtual_environment_vm.this.name
}
