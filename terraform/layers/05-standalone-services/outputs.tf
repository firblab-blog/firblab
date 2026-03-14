# =============================================================================
# Layer 05: Standalone Services - Outputs
# =============================================================================

# ---------------------------------------------------------
# Ghost Outputs
# ---------------------------------------------------------

output "ghost_container_id" {
  description = "Proxmox container ID for Ghost"
  value       = module.ghost.container_id
}

output "ghost_ipv4_addresses" {
  description = "IPv4 addresses assigned to Ghost"
  value       = module.ghost.ipv4_addresses
}

output "ghost_ssh_private_key" {
  description = "SSH private key for Ghost"
  value       = module.ghost.ssh_private_key
  sensitive   = true
}

output "ghost_ssh_public_key" {
  description = "SSH public key for Ghost"
  value       = module.ghost.ssh_public_key
}

output "ghost_ssh_private_key_path" {
  description = "Path to the SSH private key for Ghost"
  value       = module.ghost.ssh_private_key_path
}

# ---------------------------------------------------------
# FoundryVTT Outputs
# ---------------------------------------------------------

output "foundryvtt_vm_id" {
  description = "Proxmox VM ID for FoundryVTT"
  value       = module.foundryvtt.vm_id
}

output "foundryvtt_ipv4_addresses" {
  description = "IPv4 addresses assigned to FoundryVTT"
  value       = module.foundryvtt.ipv4_addresses
}

output "foundryvtt_ssh_private_key" {
  description = "SSH private key for FoundryVTT"
  value       = module.foundryvtt.ssh_private_key
  sensitive   = true
}

output "foundryvtt_ssh_public_key" {
  description = "SSH public key for FoundryVTT"
  value       = module.foundryvtt.ssh_public_key
}

output "foundryvtt_ssh_private_key_path" {
  description = "Path to the SSH private key for FoundryVTT"
  value       = module.foundryvtt.ssh_private_key_path
}

# ---------------------------------------------------------
# Roundcube Outputs
# ---------------------------------------------------------

output "roundcube_container_id" {
  description = "Proxmox container ID for Roundcube"
  value       = module.roundcube.container_id
}

output "roundcube_ipv4_addresses" {
  description = "IPv4 addresses assigned to Roundcube"
  value       = module.roundcube.ipv4_addresses
}

output "roundcube_ssh_private_key" {
  description = "SSH private key for Roundcube"
  value       = module.roundcube.ssh_private_key
  sensitive   = true
}

output "roundcube_ssh_public_key" {
  description = "SSH public key for Roundcube"
  value       = module.roundcube.ssh_public_key
}

output "roundcube_ssh_private_key_path" {
  description = "Path to the SSH private key for Roundcube"
  value       = module.roundcube.ssh_private_key_path
}

# ---------------------------------------------------------
# Mealie Outputs
# ---------------------------------------------------------

output "mealie_container_id" {
  description = "Proxmox container ID for Mealie"
  value       = module.mealie.container_id
}

output "mealie_ipv4_addresses" {
  description = "IPv4 addresses assigned to Mealie"
  value       = module.mealie.ipv4_addresses
}

output "mealie_ssh_private_key" {
  description = "SSH private key for Mealie"
  value       = module.mealie.ssh_private_key
  sensitive   = true
}

output "mealie_ssh_public_key" {
  description = "SSH public key for Mealie"
  value       = module.mealie.ssh_public_key
}

output "mealie_ssh_private_key_path" {
  description = "Path to the SSH private key for Mealie"
  value       = module.mealie.ssh_private_key_path
}

# ---------------------------------------------------------
# WireGuard Outputs
# ---------------------------------------------------------

output "wireguard_container_id" {
  description = "Proxmox container ID for WireGuard"
  value       = module.wireguard.container_id
}

output "wireguard_ipv4_addresses" {
  description = "IPv4 addresses assigned to WireGuard"
  value       = module.wireguard.ipv4_addresses
}

output "wireguard_ssh_private_key" {
  description = "SSH private key for WireGuard"
  value       = module.wireguard.ssh_private_key
  sensitive   = true
}

output "wireguard_ssh_public_key" {
  description = "SSH public key for WireGuard"
  value       = module.wireguard.ssh_public_key
}

output "wireguard_ssh_private_key_path" {
  description = "Path to the SSH private key for WireGuard"
  value       = module.wireguard.ssh_private_key_path
}

# ---------------------------------------------------------
# NetBox Outputs
# ---------------------------------------------------------

output "netbox_vm_id" {
  description = "Proxmox VM ID for NetBox"
  value       = module.netbox.vm_id
}

output "netbox_ipv4_addresses" {
  description = "IPv4 addresses assigned to NetBox"
  value       = module.netbox.ipv4_addresses
}

output "netbox_ssh_private_key" {
  description = "SSH private key for NetBox"
  value       = module.netbox.ssh_private_key
  sensitive   = true
}

output "netbox_ssh_public_key" {
  description = "SSH public key for NetBox"
  value       = module.netbox.ssh_public_key
}

output "netbox_ssh_private_key_path" {
  description = "Path to the SSH private key for NetBox"
  value       = module.netbox.ssh_private_key_path
}

# ---------------------------------------------------------
# PBS Outputs
# ---------------------------------------------------------

output "pbs_vm_id" {
  description = "Proxmox VM ID for PBS"
  value       = module.pbs.vm_id
}

output "pbs_ipv4_addresses" {
  description = "IPv4 addresses assigned to PBS"
  value       = module.pbs.ipv4_addresses
}

output "pbs_ssh_private_key" {
  description = "SSH private key for PBS"
  value       = module.pbs.ssh_private_key
  sensitive   = true
}

output "pbs_ssh_public_key" {
  description = "SSH public key for PBS"
  value       = module.pbs.ssh_public_key
}

output "pbs_ssh_private_key_path" {
  description = "Path to the SSH private key for PBS"
  value       = module.pbs.ssh_private_key_path
}

# ---------------------------------------------------------
# PatchMon Outputs
# ---------------------------------------------------------

output "patchmon_vm_id" {
  description = "Proxmox VM ID for PatchMon"
  value       = module.patchmon.vm_id
}

output "patchmon_ipv4_addresses" {
  description = "IPv4 addresses assigned to PatchMon"
  value       = module.patchmon.ipv4_addresses
}

output "patchmon_ssh_private_key" {
  description = "SSH private key for PatchMon"
  value       = module.patchmon.ssh_private_key
  sensitive   = true
}

output "patchmon_ssh_public_key" {
  description = "SSH public key for PatchMon"
  value       = module.patchmon.ssh_public_key
}

output "patchmon_ssh_private_key_path" {
  description = "Path to the SSH private key for PatchMon"
  value       = module.patchmon.ssh_private_key_path
}

# ---------------------------------------------------------
# changedetection.io Outputs
# ---------------------------------------------------------

output "changedetection_container_id" {
  description = "Proxmox container ID for changedetection.io"
  value       = module.changedetection.container_id
}

output "changedetection_ipv4_addresses" {
  description = "IPv4 addresses assigned to changedetection.io"
  value       = module.changedetection.ipv4_addresses
}

output "changedetection_ssh_private_key" {
  description = "SSH private key for changedetection.io"
  value       = module.changedetection.ssh_private_key
  sensitive   = true
}

output "changedetection_ssh_public_key" {
  description = "SSH public key for changedetection.io"
  value       = module.changedetection.ssh_public_key
}

output "changedetection_ssh_private_key_path" {
  description = "Path to the SSH private key for changedetection.io"
  value       = module.changedetection.ssh_private_key_path
}

# ---------------------------------------------------------
# Actual Budget Outputs
# ---------------------------------------------------------

output "actualbudget_container_id" {
  description = "Proxmox container ID for Actual Budget"
  value       = module.actualbudget.container_id
}

output "actualbudget_ipv4_addresses" {
  description = "IPv4 addresses assigned to Actual Budget"
  value       = module.actualbudget.ipv4_addresses
}

output "actualbudget_ssh_private_key" {
  description = "SSH private key for Actual Budget"
  value       = module.actualbudget.ssh_private_key
  sensitive   = true
}

output "actualbudget_ssh_public_key" {
  description = "SSH public key for Actual Budget"
  value       = module.actualbudget.ssh_public_key
}

output "actualbudget_ssh_private_key_path" {
  description = "Path to the SSH private key for Actual Budget"
  value       = module.actualbudget.ssh_private_key_path
}

# ---------------------------------------------------------
# Backup Outputs
# ---------------------------------------------------------

output "backup_container_id" {
  description = "Proxmox container ID for Backup"
  value       = module.backup.container_id
}

output "backup_ipv4_addresses" {
  description = "IPv4 addresses assigned to Backup"
  value       = module.backup.ipv4_addresses
}

output "backup_ssh_private_key" {
  description = "SSH private key for Backup"
  value       = module.backup.ssh_private_key
  sensitive   = true
}

output "backup_ssh_public_key" {
  description = "SSH public key for Backup"
  value       = module.backup.ssh_public_key
}

output "backup_ssh_private_key_path" {
  description = "Path to the SSH private key for Backup"
  value       = module.backup.ssh_private_key_path
}

# ---------------------------------------------------------
# Uptime Kuma Internal Outputs
# ---------------------------------------------------------

output "uptime_kuma_internal_container_id" {
  description = "Proxmox container ID for internal Uptime Kuma"
  value       = module.uptime_kuma_internal.container_id
}

output "uptime_kuma_internal_ipv4_addresses" {
  description = "IPv4 addresses assigned to internal Uptime Kuma"
  value       = module.uptime_kuma_internal.ipv4_addresses
}

output "uptime_kuma_internal_ssh_private_key" {
  description = "SSH private key for internal Uptime Kuma"
  value       = module.uptime_kuma_internal.ssh_private_key
  sensitive   = true
}

output "uptime_kuma_internal_ssh_public_key" {
  description = "SSH public key for internal Uptime Kuma"
  value       = module.uptime_kuma_internal.ssh_public_key
}

output "uptime_kuma_internal_ssh_private_key_path" {
  description = "Path to the SSH private key for internal Uptime Kuma"
  value       = module.uptime_kuma_internal.ssh_private_key_path
}

# ---------------------------------------------------------
# Gotify Internal Outputs
# ---------------------------------------------------------

output "gotify_container_id" {
  description = "Proxmox container ID for internal Gotify"
  value       = module.gotify.container_id
}

output "gotify_ipv4_addresses" {
  description = "IPv4 addresses assigned to internal Gotify"
  value       = module.gotify.ipv4_addresses
}

output "gotify_ssh_private_key" {
  description = "SSH private key for internal Gotify"
  value       = module.gotify.ssh_private_key
  sensitive   = true
}

output "gotify_ssh_public_key" {
  description = "SSH public key for internal Gotify"
  value       = module.gotify.ssh_public_key
}

output "gotify_ssh_private_key_path" {
  description = "Path to the SSH private key for internal Gotify"
  value       = module.gotify.ssh_private_key_path
}

# ---------------------------------------------------------
# SonarQube Outputs
# ---------------------------------------------------------

output "sonarqube_vm_id" {
  description = "Proxmox VM ID for SonarQube"
  value       = module.sonarqube.vm_id
}

output "sonarqube_ipv4_addresses" {
  description = "IPv4 addresses assigned to SonarQube"
  value       = module.sonarqube.ipv4_addresses
}

output "sonarqube_ssh_private_key" {
  description = "SSH private key for SonarQube"
  value       = module.sonarqube.ssh_private_key
  sensitive   = true
}

output "sonarqube_ssh_public_key" {
  description = "SSH public key for SonarQube"
  value       = module.sonarqube.ssh_public_key
}

output "sonarqube_ssh_private_key_path" {
  description = "Path to the SSH private key for SonarQube"
  value       = module.sonarqube.ssh_private_key_path
}
