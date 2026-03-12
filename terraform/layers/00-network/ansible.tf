# =============================================================================
# Layer 00: Ansible Integration for Provider Gaps
# =============================================================================
# The filipowm/unifi Terraform provider (v1.0.0) cannot manage certain UniFi
# settings due to missing attributes or provider bugs. Rather than configuring
# these through the UI (violating IaC principles), we delegate to an Ansible
# role that calls the UniFi REST API directly.
#
# This file contains terraform_data resources that trigger the Ansible playbook
# when configuration values change. The Ansible role is idempotent — it reads
# current state from the API and only writes when values differ.
#
# What this manages (provider gap inventory):
#   - STP bridge priority per switch device
#   - IPv6 disable on Default LAN (provider deserialization bug blocks import)
#   - (Future) DNS content filters (provider Read bug)
#   - (Future) Ad blocking per network (provider Read bug)
#
# The Ansible playbook reads the UniFi API key from Vault automatically.
# For bootstrap (no Vault), pass -var unifi_api_key="<key>" and it will
# be forwarded to Ansible via extra-vars.
#
# See: ansible/roles/unifi-config/defaults/main.yml for full gap inventory.
# =============================================================================

# ---------------------------------------------------------
# STP Priority Configuration
# ---------------------------------------------------------
# Sets Spanning Tree Protocol bridge priority per switch.
# The unifi_device resource has no stp_priority attribute —
# the go-unifi SDK has the field but the provider never wired it.
#
# Priority values are multiples of 4096, range 0-61440.
# Lower = higher priority = more likely to become root bridge.
# gw-01 (UCG-Fiber) manages its own priority — not set here.
# ---------------------------------------------------------

resource "terraform_data" "unifi_stp_config" {
  count = length(var.switch_stp_priorities) > 0 ? 1 : 0

  # Trigger re-run when priorities change
  input = var.switch_stp_priorities

  provisioner "local-exec" {
    command     = <<-EOT
      ansible-playbook \
        ansible/playbooks/unifi-config.yml \
        -e '${jsonencode({
          unifi_api_key        = local.unifi_api_key
          unifi_stp_priorities = var.switch_stp_priorities
          unifi_manage_ipv6    = false
        })}'
    EOT
    working_dir = "${path.module}/../../.."
  }
}

# ---------------------------------------------------------
# IPv6 Disable Configuration
# ---------------------------------------------------------
# Disables IPv6 on the Default LAN (VLAN 1), which the Terraform provider
# cannot manage due to a deserialization bug on the Default network's IPsec
# fields. Without this, Windows clients on VLAN 1 receive IPv6 addresses
# from the UCG-Fiber and experience ~5-second Happy Eyeballs timeouts when
# connecting to IPv4-only homelab services.
#
# TF-managed VLANs (10/20/30/40/50/60) use ipv6_interface_type = "none"
# in main.tf directly — only unmanageable networks belong here.
# ---------------------------------------------------------

resource "terraform_data" "unifi_network_config" {
  count = length(var.ipv6_disable_networks) > 0 ? 1 : 0

  # Trigger re-run when the list of networks to target changes
  input = var.ipv6_disable_networks

  provisioner "local-exec" {
    command     = <<-EOT
      ansible-playbook \
        ansible/playbooks/unifi-config.yml \
        -e '${jsonencode({
          unifi_api_key                = local.unifi_api_key
          unifi_manage_stp             = false
          unifi_manage_ipv6            = true
          unifi_ipv6_disable_networks  = var.ipv6_disable_networks
        })}'
    EOT
    working_dir = "${path.module}/../../.."
  }
}
