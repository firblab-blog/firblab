# =============================================================================
# Layer 01: Proxmox Base Configuration
# Rover CI visualization: https://github.com/im2nguyen/rover
# =============================================================================
# Manages Proxmox host-level resources: ISO downloads, cloud images, storage
# pool references, and base configuration that other layers depend on.
#
# This layer ensures each Proxmox node has:
#   - Packer ISOs (Ubuntu 24.04, Rocky Linux 9) for template builds
#   - Ubuntu cloud image as fallback for VMs not using Packer templates
#   - LXC container templates for layers that create containers
#   - Validated storage pools for downstream layer placement decisions
# =============================================================================

# ---------------------------------------------------------
# Packer ISO Downloads (per node × per ISO)
# ---------------------------------------------------------
# Downloads installer ISOs to each Proxmox node's local:iso/ storage.
# Packer references these ISOs when building hardened VM templates.
# ---------------------------------------------------------

locals {
  # Cross-product: every node gets every ISO
  node_iso_pairs = {
    for pair in flatten([
      for node_key, node in var.proxmox_nodes : [
        for iso_key, iso in var.packer_isos : {
          key       = "${node_key}-${iso_key}"
          node_name = node.name
          url       = iso.url
          filename  = iso.filename
          checksum  = iso.checksum
        }
      ]
    ]) : pair.key => pair
  }
}

resource "proxmox_virtual_environment_download_file" "packer_iso" {
  for_each = local.node_iso_pairs

  content_type        = "iso"
  datastore_id        = var.iso_storage_pool
  node_name           = each.value.node_name
  url                 = each.value.url
  file_name           = each.value.filename
  overwrite_unmanaged = true
  upload_timeout      = 3600

  # upload_timeout bumped to 60 minutes — Ubuntu 24.04 ISO is 2.6GB and
  # regularly exceeds the default 600s timeout on residential connections.
  #
  # overwrite_unmanaged = true allows Terraform to adopt files that already
  # exist on disk but aren't in state (e.g., after state was cleared during
  # cluster recovery). The provider will re-download the file to take ownership.
  # Once the file is in state, subsequent applies are no-ops unless the
  # upstream URL content changes (controlled by the 'overwrite' flag).

}

# ---------------------------------------------------------
# Cloud Image Downloads (per node — fallback)
# ---------------------------------------------------------
# Downloads the Ubuntu 24.04 Noble cloud image to each Proxmox node.
# Used by VMs that don't clone from a Packer template (e.g., vault-2
# during bootstrap before the Packer template exists).
# ---------------------------------------------------------

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  for_each = var.proxmox_nodes

  content_type        = "iso"
  datastore_id        = var.iso_storage_pool
  node_name           = each.value.name
  url                 = var.cloud_image_url
  file_name           = var.cloud_image_filename
  overwrite_unmanaged = true

  # overwrite_unmanaged = true allows Terraform to adopt files that already
  # exist on disk but aren't in state. See packer_iso resource for details.

}

# ---------------------------------------------------------
# LXC Container Templates (per node × per template)
# ---------------------------------------------------------
# Downloads LXC container templates to each Proxmox node's
# local:vztmpl/ storage. Used by layers that create LXC
# containers (e.g., Layer 03 GitLab Runner, Layer 05 Ghost).
# ---------------------------------------------------------

locals {
  node_lxc_template_pairs = {
    for pair in flatten([
      for node_key, node in var.proxmox_nodes : [
        for tmpl_key, tmpl in var.lxc_templates : {
          key       = "${node_key}-${tmpl_key}"
          node_name = node.name
          url       = tmpl.url
          filename  = tmpl.filename
        }
      ]
    ]) : pair.key => pair
  }
}

resource "proxmox_virtual_environment_download_file" "lxc_template" {
  for_each = local.node_lxc_template_pairs

  content_type        = "vztmpl"
  datastore_id        = var.iso_storage_pool
  node_name           = each.value.node_name
  url                 = each.value.url
  file_name           = each.value.filename
  overwrite_unmanaged = true

  # overwrite_unmanaged = true allows Terraform to adopt files that already
  # exist on disk but aren't in state. See packer_iso resource for details.

}

# ---------------------------------------------------------
# Storage Pool Data Sources (per node)
# ---------------------------------------------------------
# Validates that the expected storage pools exist on each node.
# Other layers can reference these outputs for placement decisions.
# ---------------------------------------------------------

data "proxmox_virtual_environment_datastores" "available" {
  for_each = var.proxmox_nodes

  node_name = each.value.name
}
