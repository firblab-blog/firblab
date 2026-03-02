# =============================================================================
# Layer 02-vault-infra: Vault VM Infrastructure
# Rover CI visualization: https://github.com/im2nguyen/rover
# =============================================================================
# Provisions the Proxmox VM for vault-2. This layer handles ONLY the VM
# infrastructure — Vault software configuration is managed by Layer
# 02-vault-config (secrets engines, policies, KV seeding) and Ansible
# (binary installation, Raft clustering, TLS).
#
# Terraform-managed:
#   vault-2: Proxmox VM on lab-02 (Security VLAN 50) - 10.0.50.2
#
# Ansible-managed (not in this layer):
#   vault-1: Mac Mini M4 (macOS native, ARM64)            - 10.0.10.10
#   vault-3: RPi5 CM5 (Ubuntu 24.04 ARM64 bare metal)     - 10.0.10.13
#
# After Terraform provisions vault-2, run the Ansible vault role against all
# three nodes to install and configure Vault with Raft integrated storage.
# =============================================================================

# ---------------------------------------------------------
# Locals
# ---------------------------------------------------------

locals {
  vault_nodes = {
    "vault-1" = {
      address      = var.vault_node_1_address
      api_addr     = "https://${var.vault_node_1_address}:${var.vault_api_port}"
      cluster_addr = "https://${var.vault_node_1_address}:${var.vault_cluster_port}"
      managed_by   = "ansible"
      description  = "Mac Mini M4 (macOS native, ARM64)"
    }
    "vault-2" = {
      address      = var.vault_node_2_address
      api_addr     = "https://${var.vault_node_2_address}:${var.vault_api_port}"
      cluster_addr = "https://${var.vault_node_2_address}:${var.vault_cluster_port}"
      managed_by   = "terraform"
      description  = "Proxmox VM on lab-02 (Security VLAN 50)"
    }
    "vault-3" = {
      address      = var.vault_node_3_address
      api_addr     = "https://${var.vault_node_3_address}:${var.vault_api_port}"
      cluster_addr = "https://${var.vault_node_3_address}:${var.vault_cluster_port}"
      managed_by   = "ansible"
      description  = "RPi5 CM5 (Ubuntu 24.04 ARM64 bare metal)"
    }
  }
}

# ---------------------------------------------------------
# Vault Node 2 (Proxmox VM)
# ---------------------------------------------------------

module "vault_2" {
  source = "../../modules/proxmox-vm/"

  # Identity
  name        = var.vault_vm_name
  description = var.vault_vm_description
  vm_id       = var.vault_vm_id
  tags        = ["vault", "ha", "security"]

  # Proxmox placement
  proxmox_node = var.proxmox_node

  # Compute resources
  cpu_cores = var.vault_cpu_cores
  cpu_type  = "x86-64-v2-AES"
  memory_mb = var.vault_memory_mb

  # Clone from hardened Packer template (Rocky 9 = 9001, Ubuntu 24.04 = 9000)
  clone_template_vm_id = var.vault_template_vm_id
  clone_template_node  = var.vault_template_node

  # Storage
  os_disk_size_gb = var.vault_os_disk_size_gb
  storage_pool    = var.vault_storage_pool
  snippet_storage = var.vault_snippet_storage

  data_disks = [
    {
      interface = "scsi1"
      size_gb   = var.vault_data_disk_size_gb
    }
  ]

  # Cloud-init (vault-specific prep: user, data disk, sysctl)
  cloud_init_template = "${path.module}/files/vault-user-data.yaml"
  vm_username         = var.vault_vm_username

  # Network
  network_bridge = var.vault_network_bridge
  vlan_tag       = var.vault_vlan_tag
  ip_address     = var.vault_ip_address
  gateway        = var.vault_gateway
  domain_name    = var.vault_domain_name
  dns_servers    = var.vault_dns_servers

  # SSH
  additional_ssh_key = var.ssh_public_key

  # Startup order 1 = critical infrastructure (starts early, stops late)
  startup_order      = "1"
  startup_up_delay   = "120"
  startup_down_delay = "60"
}
