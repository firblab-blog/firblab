# =============================================================================
# WAR Platform (VM) — lab-01, Services VLAN 20
# =============================================================================
# Multi-agent adjudication, critique, and synthesis platform.
# Deploys four custom-built services (dashboard, recall-service,
# guardrail-service, war-service) + PostgreSQL via Docker Compose.
#
# Images are built by the WAR GitLab CI pipeline and published to the
# GitLab Container Registry. The pipeline updates war_*_image vars in
# ansible/roles/war/defaults/main.yml and triggers deploy:war in firblab CI.
#
# Placed on lab-01 (i9-12900K, 64GB RAM) — the primary compute node.
# All other Layer 05 services default to lab-03; WAR gets its own
# war_proxmox_node variable (same pattern as netbox_proxmox_node).
# =============================================================================

module "war" {
  source = "../../modules/proxmox-vm/"
  count  = var.war_enabled ? 1 : 0

  # Identity
  name        = var.war_name
  description = "WAR Platform - Multi-agent adjudication, critique, and synthesis"
  vm_id       = var.war_vm_id
  tags        = ["war", "ai", "services"]

  # Proxmox placement — lab-01 (NOT the shared default lab-03)
  proxmox_node = var.war_proxmox_node

  # Compute resources — multi-service stack with Postgres
  cpu_cores = var.war_cpu_cores
  cpu_type  = "x86-64-v2-AES"
  memory_mb = var.war_memory_mb

  # Storage — clone from hardened Packer template
  clone_template_vm_id = var.clone_template_vm_id
  clone_template_node  = var.clone_template_node
  os_disk_size_gb      = var.war_os_disk_size_gb
  storage_pool         = var.storage_pool
  snippet_storage      = var.snippet_storage

  # Network — Services VLAN 20
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag
  ip_address     = var.war_ip_address
  gateway        = var.gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH — guest-agent injection must target the node hosting this VM
  additional_ssh_key = var.ssh_public_key
  proxmox_ssh_host   = local.proxmox_node_ips[var.war_proxmox_node]
  proxmox_ssh_key    = pathexpand("~/.ssh/id_ed25519_${var.war_proxmox_node}")
}
