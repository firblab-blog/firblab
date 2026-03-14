# =============================================================================
# SonarQube CE (VM) — lab-01, Services VLAN 20
# =============================================================================
# Static code analysis platform with GitLab ALM integration.
# Runs SonarQube CE LTS + PostgreSQL via Docker Compose.
#
# Placed on lab-01 (i9-12900K, 64GB RAM) — SonarQube requires 4-6GB for
# the JVM (web + CE processes) and Elasticsearch. Other Layer 05 services
# default to lab-03; SonarQube gets lab-01 (same pattern as WAR).
#
# GitLab integration (managed by Terraform Layer 03):
#   - OAuth app: sonarqube.home.example-lab.org/oauth2/callback/gitlab
#   - ALM token: posts quality gate decoration to GitLab MRs
#   - CI variable: SONAR_HOST_URL, SONAR_TOKEN (after sonarqube_ci_ready=true)
#
# Secrets: secret/services/sonarqube (seeded by Layer 03)
# =============================================================================

module "sonarqube" {
  source = "../../modules/proxmox-vm/"

  # Identity
  name        = var.sonarqube_name
  description = "SonarQube CE — static code analysis, GitLab ALM integration"
  vm_id       = var.sonarqube_vm_id
  tags        = ["sonarqube", "analysis", "services"]

  # Proxmox placement — lab-01 (NOT the shared default lab-03)
  proxmox_node = var.sonarqube_proxmox_node

  # Compute resources — JVM (web + CE) + Elasticsearch requires 4-6GB RAM
  cpu_cores = var.sonarqube_cpu_cores
  cpu_type  = "x86-64-v2-AES"
  memory_mb = var.sonarqube_memory_mb

  # Storage — clone from hardened Packer template
  clone_template_vm_id = var.clone_template_vm_id
  clone_template_node  = var.clone_template_node
  os_disk_size_gb      = var.sonarqube_os_disk_size_gb
  storage_pool         = var.storage_pool
  snippet_storage      = var.snippet_storage

  # Network — Services VLAN 20
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag
  ip_address     = var.sonarqube_ip_address
  gateway        = var.gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH — guest-agent injection must target the node hosting this VM
  additional_ssh_key = var.ssh_public_key
  proxmox_ssh_host   = local.proxmox_node_ips[var.sonarqube_proxmox_node]
  proxmox_ssh_key    = pathexpand("~/.ssh/id_ed25519_${var.sonarqube_proxmox_node}")
}
