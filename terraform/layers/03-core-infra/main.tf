# =============================================================================
# Layer 03: Core Infrastructure
# Rover CI visualization: https://github.com/im2nguyen/rover
# =============================================================================
# Deploys core CI/CD services:
#   - GitLab CE (VM)       : Source code management and CI/CD pipelines
#   - GitLab Runner (LXC)  : Executes CI/CD jobs in Docker containers
#
# All services are deployed to the Management network (10.0.10.0/24)
# untagged on vmbr0 for reachability from all networks.
#
# Wazuh Manager was removed — lab-02 only has 16 GB RAM and cannot
# support vault-2 (4GB) + GitLab (8GB) + Runner (2GB) + Wazuh (8GB).
# =============================================================================

# ---------------------------------------------------------
# GitLab CE (VM)
# ---------------------------------------------------------

module "gitlab" {
  source = "../../modules/proxmox-vm/"

  # Identity
  name        = var.gitlab_name
  description = "GitLab CE - Source code management and CI/CD"
  vm_id       = var.gitlab_vm_id
  tags        = ["gitlab", "ci", "security"]

  # Proxmox placement
  proxmox_node = var.gitlab_proxmox_node

  # Compute resources
  cpu_cores = var.gitlab_cpu_cores
  cpu_type  = "x86-64-v2-AES"
  memory_mb = var.gitlab_memory_mb

  # Storage — both disks on nvme-thin-1 (PBS restore from lab-02 migration)
  os_disk_size_gb    = var.gitlab_os_disk_size_gb
  storage_pool       = var.gitlab_storage_pool
  data_storage_pool  = var.gitlab_data_storage_pool
  snippet_storage    = var.snippet_storage

  data_disks = [
    {
      interface = "scsi1"
      size_gb   = var.gitlab_data_disk_size_gb
    }
  ]

  # Template cloning (Packer) or cloud image fallback
  clone_template_vm_id = var.clone_template_vm_id
  clone_template_node  = var.clone_template_node
  download_cloud_image = var.clone_template_vm_id > 0 ? false : var.download_cloud_image
  cloud_image_url      = var.cloud_image_url
  cloud_image_filename = var.cloud_image_filename

  # Network
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag
  ip_address     = var.gitlab_ip_address
  gateway        = var.gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH — guest agent key injection (reliable cross-node SSH access)
  additional_ssh_key = var.ssh_public_key
  proxmox_ssh_host   = local.proxmox_node_ips[var.gitlab_proxmox_node]
  proxmox_ssh_key    = pathexpand("~/.ssh/id_ed25519_${var.gitlab_proxmox_node}")

  # Startup order 2 = core services (after Vault)
  startup_order = "2"
}

# ---------------------------------------------------------
# GitLab Runner (LXC)
# ---------------------------------------------------------

module "gitlab_runner" {
  source = "../../modules/proxmox-lxc/"

  # Identity
  name        = var.gitlab_runner_name
  description = "GitLab Runner - CI/CD job executor (Docker-in-LXC)"
  vm_id       = var.gitlab_runner_vm_id
  tags        = ["gitlab-runner", "ci", "security"]

  # Proxmox placement
  proxmox_node = var.gitlab_runner_proxmox_node

  # Compute resources
  cpu_cores    = var.gitlab_runner_cpu_cores
  memory_mb    = var.gitlab_runner_memory_mb
  swap_mb      = 1024
  disk_size_gb = var.gitlab_runner_disk_size_gb
  storage_pool = var.storage_pool

  # Container configuration
  docker_enabled = true

  # Network
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag
  ip_address     = var.gitlab_runner_ip_address
  gateway        = var.gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH
  additional_ssh_key = var.ssh_public_key
}

# ---------------------------------------------------------
# Wazuh Manager (VM) — REMOVED
# ---------------------------------------------------------
# Wazuh was removed to stay within lab-02's 16 GB RAM budget.
# vault-2 (4GB) + GitLab (8GB) + Runner (2GB) = 14GB, leaving
# 2GB for Proxmox host overhead. Wazuh needed 8GB additional.
#
# To re-enable: uncomment the module below and the wazuh_*
# variables in variables.tf + outputs in outputs.tf.
# ---------------------------------------------------------
