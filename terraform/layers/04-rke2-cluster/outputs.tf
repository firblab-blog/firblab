# =============================================================================
# Layer 04: RKE2 Cluster - Outputs
# =============================================================================

# ---------------------------------------------------------
# Server Node Outputs
# ---------------------------------------------------------

output "server_ips" {
  description = "IPv4 addresses of the RKE2 server (control plane) nodes"
  value       = module.rke2_cluster.server_ips
}

output "server_vm_ids" {
  description = "Proxmox VM IDs of the RKE2 server nodes"
  value       = module.rke2_cluster.server_vm_ids
}

output "server_ssh_key_paths" {
  description = "Paths to SSH private key files for server nodes"
  value       = module.rke2_cluster.server_ssh_key_paths
}

# ---------------------------------------------------------
# Agent Node Outputs
# ---------------------------------------------------------

output "agent_ips" {
  description = "IPv4 addresses of the RKE2 agent (worker) nodes"
  value       = module.rke2_cluster.agent_ips
}

output "agent_vm_ids" {
  description = "Proxmox VM IDs of the RKE2 agent nodes"
  value       = module.rke2_cluster.agent_vm_ids
}

output "agent_ssh_key_paths" {
  description = "Paths to SSH private key files for agent nodes"
  value       = module.rke2_cluster.agent_ssh_key_paths
}

# ---------------------------------------------------------
# Cluster Information
# ---------------------------------------------------------

output "cluster_name" {
  description = "RKE2 cluster name"
  value       = var.cluster_name
}

output "cluster_summary" {
  description = "RKE2 cluster configuration summary"
  value = {
    cluster_name = var.cluster_name
    rke2_version = var.rke2_version
    master_count = var.master_count
    worker_count = var.worker_count
    vlan_tag     = var.vlan_tag
    vm_id_start  = var.vm_id_start
  }
}
