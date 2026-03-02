# ---------------------------------------------------------
# Server Node Outputs
# ---------------------------------------------------------

output "server_ips" {
  description = "IPv4 addresses for each server node"
  value       = { for k, v in module.servers : k => v.ipv4_addresses }
}

output "server_vm_ids" {
  description = "Proxmox VM IDs for each server node"
  value       = { for k, v in module.servers : k => v.vm_id }
}

output "server_ssh_keys" {
  description = "SSH private keys for server node access"
  value       = { for k, v in module.servers : k => v.ssh_private_key }
  sensitive   = true
}

output "server_ssh_key_paths" {
  description = "Paths to saved SSH private key files for server nodes"
  value       = { for k, v in module.servers : k => v.ssh_private_key_path }
}

# ---------------------------------------------------------
# Agent Node Outputs
# ---------------------------------------------------------

output "agent_ips" {
  description = "IPv4 addresses for each agent node"
  value       = { for k, v in module.agents : k => v.ipv4_addresses }
}

output "agent_vm_ids" {
  description = "Proxmox VM IDs for each agent node"
  value       = { for k, v in module.agents : k => v.vm_id }
}

output "agent_ssh_keys" {
  description = "SSH private keys for agent node access"
  value       = { for k, v in module.agents : k => v.ssh_private_key }
  sensitive   = true
}

output "agent_ssh_key_paths" {
  description = "Paths to saved SSH private key files for agent nodes"
  value       = { for k, v in module.agents : k => v.ssh_private_key_path }
}

# ---------------------------------------------------------
# Legacy Aliases (consumed by layer 04 outputs)
# ---------------------------------------------------------

output "master_ips" {
  description = "IPv4 addresses for server nodes (alias for server_ips)"
  value       = { for k, v in module.servers : k => v.ipv4_addresses }
}

output "master_vm_ids" {
  description = "Proxmox VM IDs for server nodes (alias for server_vm_ids)"
  value       = { for k, v in module.servers : k => v.vm_id }
}

output "worker_ips" {
  description = "IPv4 addresses for agent nodes (alias for agent_ips)"
  value       = { for k, v in module.agents : k => v.ipv4_addresses }
}

output "worker_vm_ids" {
  description = "Proxmox VM IDs for agent nodes (alias for agent_vm_ids)"
  value       = { for k, v in module.agents : k => v.vm_id }
}

# ---------------------------------------------------------
# Cluster Summary
# ---------------------------------------------------------

output "cluster_name" {
  description = "Name of the RKE2 cluster"
  value       = var.cluster_name
}

output "node_count" {
  description = "Total number of nodes in the cluster"
  value       = var.master_count + var.worker_count
}
