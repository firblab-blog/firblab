# =============================================================================
# Layer 04: RKE2 Cluster
# Rover CI visualization: https://github.com/im2nguyen/rover
# =============================================================================
# Deploys a DISA STIG-hardened RKE2 Kubernetes cluster on Proxmox VMs using
# the proxmox-rke2-cluster module.
#
# Topology:
#   - 3 server nodes (2 CPU / 4GB RAM each) for HA control plane
#   - 3 agent nodes  (4 CPU / 8GB RAM each) for workloads
#   - All nodes on Services VLAN 20 with static IPs
#   - VM IDs starting at 4000
#   - Cloned from Packer-built Ubuntu 24.04 template (VM 9000)
# =============================================================================

module "rke2_cluster" {
  source = "../../modules/proxmox-rke2-cluster/"
  count  = var.rke2_enabled ? 1 : 0

  # Proxmox placement
  proxmox_node = var.proxmox_node

  # Cluster identity
  cluster_name = var.cluster_name
  vm_id_start  = var.vm_id_start

  # Server node configuration
  master_count           = var.master_count
  master_cpu_cores       = var.master_cpu_cores
  master_memory_mb       = var.master_memory_mb
  master_os_disk_size_gb = var.master_os_disk_size_gb

  # Agent node configuration
  worker_count           = var.worker_count
  worker_cpu_cores       = var.worker_cpu_cores
  worker_memory_mb       = var.worker_memory_mb
  worker_os_disk_size_gb = var.worker_os_disk_size_gb

  # IP address offsets (avoid collision with Layer 05 standalone services)
  server_ip_offset = var.server_ip_offset
  agent_ip_offset  = var.agent_ip_offset

  # RKE2 version
  rke2_version = var.rke2_version

  # Template cloning (Packer-built Ubuntu 24.04)
  clone_template_vm_id = var.clone_template_vm_id
  clone_template_node  = var.clone_template_node

  # Cloud image (fallback when not cloning)
  download_cloud_image = var.download_cloud_image
  cloud_image_url      = var.cloud_image_url
  cloud_image_filename = var.cloud_image_filename

  # Storage
  storage_pool      = var.storage_pool
  data_storage_pool = var.data_storage_pool
  snippet_storage   = var.snippet_storage
  data_disk_size_gb = var.data_disk_size_gb

  # Network (Services VLAN 20)
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag
  gateway        = var.gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH
  ssh_public_key = var.ssh_public_key

  # Guest agent key injection — derives Proxmox host IP from Vault API URL
  proxmox_ssh_host = local.proxmox_ssh_host
  proxmox_ssh_key  = pathexpand("~/.ssh/id_ed25519_${var.proxmox_node}")
}
