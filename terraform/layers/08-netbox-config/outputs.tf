# =============================================================================
# Layer 08-netbox-config: Outputs
# =============================================================================

# ---------------------------------------------------------
# Proxmox VM Records
# ---------------------------------------------------------

output "proxmox_vm_ids" {
  description = "Map of VM name to NetBox virtual machine ID (Proxmox cluster)"
  value       = { for k, v in netbox_virtual_machine.proxmox : k => v.id }
}

output "proxmox_ip_address_ids" {
  description = "Map of VM name to NetBox IP address ID (Proxmox cluster)"
  value       = { for k, v in netbox_ip_address.proxmox_primary : k => v.id }
}

# ---------------------------------------------------------
# Hetzner VM Records
# ---------------------------------------------------------

output "hetzner_vm_ids" {
  description = "Map of VM name to NetBox virtual machine ID (Hetzner cluster)"
  value       = { for k, v in netbox_virtual_machine.hetzner : k => v.id }
}

# ---------------------------------------------------------
# Foundation Resource IDs
# ---------------------------------------------------------

output "site_id" {
  description = "NetBox site ID for FirbLab"
  value       = netbox_site.firblab.id
}

output "proxmox_cluster_id" {
  description = "NetBox cluster ID for firblab-cluster (Proxmox)"
  value       = netbox_cluster.firblab.id
}

output "hetzner_cluster_id" {
  description = "NetBox cluster ID for hetzner-cloud"
  value       = netbox_cluster.hetzner.id
}

output "terraform_managed_tag_id" {
  description = "NetBox tag ID for terraform-managed"
  value       = netbox_tag.terraform_managed.id
}
