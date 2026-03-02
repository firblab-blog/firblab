# ---------------------------------------------------------
# Packer ISO Outputs
# ---------------------------------------------------------

output "packer_iso_ids" {
  description = "Map of node-iso pairs to their downloaded ISO IDs (e.g., lab-02-ubuntu-24.04)"
  value = {
    for key, download in proxmox_virtual_environment_download_file.packer_iso :
    key => download.id
  }
}

output "packer_isos" {
  description = "Map of Packer ISO configurations (names, URLs, filenames)"
  value       = var.packer_isos
}

# ---------------------------------------------------------
# Cloud Image Outputs (fallback)
# ---------------------------------------------------------

output "cloud_image_ids" {
  description = "Map of node names to their downloaded Ubuntu cloud image IDs"
  value = {
    for node_key, download in proxmox_virtual_environment_download_file.ubuntu_cloud_image :
    node_key => download.id
  }
}

output "cloud_image_filename" {
  description = "Filename of the downloaded cloud image (same across all nodes)"
  value       = var.cloud_image_filename
}

# ---------------------------------------------------------
# Node Outputs
# ---------------------------------------------------------

output "node_names" {
  description = "List of Proxmox node names managed by this layer"
  value       = [for node in var.proxmox_nodes : node.name]
}

output "nodes" {
  description = "Full map of Proxmox nodes with their configuration"
  value       = var.proxmox_nodes
}

# ---------------------------------------------------------
# Storage Outputs
# ---------------------------------------------------------

output "available_datastores" {
  description = "Map of node names to their available datastore IDs"
  value = {
    for node_key, ds in data.proxmox_virtual_environment_datastores.available :
    node_key => [for d in ds.datastores : d.id]
  }
}

output "vm_storage_pool" {
  description = "Storage pool name used for VM disks"
  value       = var.vm_storage_pool
}

output "iso_storage_pool" {
  description = "Storage pool name used for ISOs and cloud images"
  value       = var.iso_storage_pool
}

output "snippet_storage_pool" {
  description = "Storage pool name used for cloud-init snippets"
  value       = var.snippet_storage_pool
}

# ---------------------------------------------------------
# Network Outputs
# ---------------------------------------------------------

output "network_bridge" {
  description = "Default network bridge on Proxmox hosts"
  value       = var.network_bridge
}
