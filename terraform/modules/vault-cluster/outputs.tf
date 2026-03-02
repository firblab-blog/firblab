# ---------------------------------------------------------
# Cluster Topology
# ---------------------------------------------------------

output "cluster_nodes" {
  description = "Map of all cluster nodes with their addresses and roles"
  value       = local.cluster_nodes
}

output "raft_peers" {
  description = "List of all Raft peer API addresses for retry_join configuration"
  value       = local.raft_peers
}

# ---------------------------------------------------------
# Proxmox Node Outputs
# ---------------------------------------------------------

output "proxmox_vm_ids" {
  description = "VM IDs for Proxmox-managed Vault nodes"
  value       = { for k, v in module.proxmox_vault_nodes : k => v.vm_id }
}

output "proxmox_node_ips" {
  description = "IPv4 addresses for Proxmox-managed Vault nodes"
  value       = { for k, v in module.proxmox_vault_nodes : k => v.ipv4_addresses }
}

output "proxmox_ssh_private_keys" {
  description = "SSH private keys for Proxmox-managed Vault nodes"
  value       = { for k, v in module.proxmox_vault_nodes : k => v.ssh_private_key }
  sensitive   = true
}

output "proxmox_ssh_public_keys" {
  description = "SSH public keys for Proxmox-managed Vault nodes"
  value       = { for k, v in module.proxmox_vault_nodes : k => v.ssh_public_key }
}
