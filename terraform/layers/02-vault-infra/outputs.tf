# =============================================================================
# Layer 02-vault-infra: Vault VM Infrastructure - Outputs
# =============================================================================

# ---------------------------------------------------------
# Vault VM (vault-2) Details
# ---------------------------------------------------------

output "vault_2_vm_id" {
  description = "Proxmox VM ID for vault-2"
  value       = module.vault_2.vm_id
}

output "vault_2_ip_address" {
  description = "IP address of vault-2"
  value       = var.vault_ip_address
}

output "vault_2_ipv4_addresses" {
  description = "All IPv4 addresses assigned to vault-2 by Proxmox"
  value       = module.vault_2.ipv4_addresses
}

output "vault_2_ssh_private_key_path" {
  description = "Path to the SSH private key for vault-2"
  value       = module.vault_2.ssh_private_key_path
}

output "vault_2_ssh_private_key" {
  description = "SSH private key for vault-2"
  value       = module.vault_2.ssh_private_key
  sensitive   = true
}

output "vault_2_ssh_public_key" {
  description = "SSH public key for vault-2"
  value       = module.vault_2.ssh_public_key
}

output "vault_2_password" {
  description = "Generated password for vault-2"
  value       = module.vault_2.password
  sensitive   = true
}

# ---------------------------------------------------------
# Vault API Addresses (all nodes)
# ---------------------------------------------------------

output "vault_api_addresses" {
  description = "Vault API addresses for all cluster nodes"
  value = {
    "vault-1" = "https://${var.vault_node_1_address}:${var.vault_api_port}"
    "vault-2" = "https://${var.vault_node_2_address}:${var.vault_api_port}"
    "vault-3" = "https://${var.vault_node_3_address}:${var.vault_api_port}"
  }
}

# ---------------------------------------------------------
# Cluster Configuration Summary
# ---------------------------------------------------------

output "cluster_summary" {
  description = "Vault HA cluster configuration summary"
  value = {
    cluster_name  = "vault-ha"
    vault_version = var.vault_version
    storage       = "raft"
    node_count    = 3
    nodes = {
      "vault-1" = {
        address     = var.vault_node_1_address
        api_addr    = "https://${var.vault_node_1_address}:${var.vault_api_port}"
        platform    = "Mac Mini M4 (UTM VM)"
        managed_by  = "ansible"
      }
      "vault-2" = {
        address     = var.vault_node_2_address
        api_addr    = "https://${var.vault_node_2_address}:${var.vault_api_port}"
        platform    = "Proxmox VM (lab-02)"
        managed_by  = "terraform"
      }
      "vault-3" = {
        address     = var.vault_node_3_address
        api_addr    = "https://${var.vault_node_3_address}:${var.vault_api_port}"
        platform    = "RPi5 CM5 (bare metal)"
        managed_by  = "ansible"
      }
    }
    raft_peers = [
      "${var.vault_node_1_address}:${var.vault_cluster_port}",
      "${var.vault_node_2_address}:${var.vault_cluster_port}",
      "${var.vault_node_3_address}:${var.vault_cluster_port}",
    ]
  }
}
