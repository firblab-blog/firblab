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
# Node Definitions
# ---------------------------------------------------------
# IP offsets are configurable via server_ip_offset / agent_ip_offset.
# Default: servers at .40, .41, .42 — agents at .50, .51, .52
# ---------------------------------------------------------

locals {
  # VLAN prefix derived from gateway (e.g., 10.0.20.1 → 10.0.20)
  vlan_prefix = join(".", slice(split(".", var.gateway), 0, 3))

  # Build a map of server (control plane) nodes
  server_nodes = {
    for i in range(var.master_count) : "${var.cluster_name}-server-${i + 1}" => {
      name       = "${var.cluster_name}-server-${i + 1}"
      vm_id      = var.vm_id_start + i
      role       = "server"
      ip_address = "${local.vlan_prefix}.${var.server_ip_offset + i}/24"
    }
  }

  # Build a map of agent (worker) nodes
  agent_nodes = {
    for i in range(var.worker_count) : "${var.cluster_name}-agent-${i + 1}" => {
      name       = "${var.cluster_name}-agent-${i + 1}"
      vm_id      = var.vm_id_start + var.master_count + i
      role       = "agent"
      ip_address = "${local.vlan_prefix}.${var.agent_ip_offset + i}/24"
    }
  }
}

# ---------------------------------------------------------
# Server (Control Plane) Nodes
# ---------------------------------------------------------

module "servers" {
  source   = "../proxmox-vm"
  for_each = local.server_nodes

  name         = each.value.name
  vm_id        = each.value.vm_id
  proxmox_node = var.proxmox_node
  description  = "RKE2 server node for cluster ${var.cluster_name}"

  tags = ["rke2", "server", "cluster-${var.cluster_name}"]

  # Compute resources
  cpu_cores = var.master_cpu_cores
  memory_mb = var.master_memory_mb

  # Storage
  os_disk_size_gb   = var.master_os_disk_size_gb
  storage_pool      = var.storage_pool
  data_storage_pool = var.data_storage_pool
  snippet_storage   = var.snippet_storage

  # Longhorn data disk
  data_disks = [
    {
      interface = "scsi1"
      size_gb   = var.data_disk_size_gb
    }
  ]

  # Template cloning (Packer) or cloud image fallback
  clone_template_vm_id = var.clone_template_vm_id
  clone_template_node  = var.clone_template_node
  download_cloud_image = var.clone_template_vm_id > 0 ? false : var.download_cloud_image
  cloud_image_url      = var.cloud_image_url
  cloud_image_filename = var.cloud_image_filename

  # Network — static IPs on Services VLAN
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag
  ip_address     = each.value.ip_address
  gateway        = var.gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH
  additional_ssh_key = var.ssh_public_key

  # Guest agent key injection (belt + suspenders for cloud-init failures)
  proxmox_ssh_host = var.proxmox_ssh_host
  proxmox_ssh_user = var.proxmox_ssh_user
  proxmox_ssh_key  = var.proxmox_ssh_key
}

# ---------------------------------------------------------
# Agent (Worker) Nodes
# ---------------------------------------------------------

module "agents" {
  source   = "../proxmox-vm"
  for_each = local.agent_nodes

  name         = each.value.name
  vm_id        = each.value.vm_id
  proxmox_node = var.proxmox_node
  description  = "RKE2 agent node for cluster ${var.cluster_name}"

  tags = ["rke2", "agent", "cluster-${var.cluster_name}"]

  # Compute resources
  cpu_cores = var.worker_cpu_cores
  memory_mb = var.worker_memory_mb

  # Storage
  os_disk_size_gb   = var.worker_os_disk_size_gb
  storage_pool      = var.storage_pool
  data_storage_pool = var.data_storage_pool
  snippet_storage   = var.snippet_storage

  # Longhorn data disk
  data_disks = [
    {
      interface = "scsi1"
      size_gb   = var.data_disk_size_gb
    }
  ]

  # Template cloning (Packer) or cloud image fallback
  clone_template_vm_id = var.clone_template_vm_id
  clone_template_node  = var.clone_template_node
  download_cloud_image = var.clone_template_vm_id > 0 ? false : var.download_cloud_image
  cloud_image_url      = var.cloud_image_url
  cloud_image_filename = var.cloud_image_filename

  # Network — static IPs on Services VLAN
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag
  ip_address     = each.value.ip_address
  gateway        = var.gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH
  additional_ssh_key = var.ssh_public_key

  # Guest agent key injection (belt + suspenders for cloud-init failures)
  proxmox_ssh_host = var.proxmox_ssh_host
  proxmox_ssh_user = var.proxmox_ssh_user
  proxmox_ssh_key  = var.proxmox_ssh_key
}
