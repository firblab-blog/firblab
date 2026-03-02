terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.81.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4"
    }
  }
}

# ---------------------------------------------------------
# Locals
# ---------------------------------------------------------

locals {
  # Build the full cluster node map with computed addresses
  cluster_nodes = {
    for node in var.nodes : node.node_id => {
      node_id      = node.node_id
      address      = node.address
      api_addr     = "https://${node.address}:${var.api_port}"
      cluster_addr = "https://${node.address}:${var.cluster_port}"
      node_type    = node.node_type
      managed_by   = node.node_type == "proxmox-vm" ? "terraform" : "ansible"
      description  = node.description
    }
  }

  # Filter to only Proxmox-managed nodes (the ones Terraform provisions)
  proxmox_nodes = {
    for k, v in local.cluster_nodes : k => v if v.node_type == "proxmox-vm"
  }

  # All peer addresses for Raft retry_join configuration
  raft_peers = [for node in local.cluster_nodes : node.api_addr]
}

# ---------------------------------------------------------
# Proxmox Vault Nodes
# ---------------------------------------------------------
# Only nodes with node_type = "proxmox-vm" are provisioned here.
# Bare-metal and RPi nodes are provisioned by Ansible.

module "proxmox_vault_nodes" {
  source   = "../proxmox-vm/"
  for_each = local.proxmox_nodes

  # Identity
  name        = each.value.node_id
  description = each.value.description
  vm_id       = var.nodes_config[each.key].vm_id
  tags        = ["vault", "ha", "security"]

  # Proxmox placement
  proxmox_node = var.nodes_config[each.key].proxmox_node

  # Compute resources
  cpu_cores = var.cpu_cores
  cpu_type  = "x86-64-v2-AES"
  memory_mb = var.memory_mb

  # Storage
  os_disk_size_gb = var.os_disk_size_gb
  storage_pool    = var.nodes_config[each.key].storage_pool
  snippet_storage = var.nodes_config[each.key].snippet_storage

  data_disks = [
    {
      interface = "scsi1"
      size_gb   = var.data_disk_size_gb
    }
  ]

  # Cloud image
  download_cloud_image = var.download_cloud_image
  cloud_image_url      = var.cloud_image_url
  cloud_image_filename = var.cloud_image_filename

  # Cloud-init
  cloud_init_template = var.cloud_init_template
  cloud_init_vars = {
    vault_version = var.vault_version
  }
  vm_username = var.vm_username

  # Network
  network_bridge = var.nodes_config[each.key].network_bridge
  vlan_tag       = var.nodes_config[each.key].vlan_tag
  ip_address     = "${each.value.address}/${var.nodes_config[each.key].subnet_mask}"
  gateway        = var.nodes_config[each.key].gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH
  additional_ssh_key = var.ssh_public_key

  # Critical infrastructure starts early
  startup_order      = "1"
  startup_up_delay   = "120"
  startup_down_delay = "60"
}
