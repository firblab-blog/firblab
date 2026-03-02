# =============================================================================
# Layer 08-netbox-config: NetBox DCIM/IPAM Configuration
# =============================================================================
# Manages NetBox virtual machine records, interfaces, and IP addresses for all
# Terraform-provisioned VMs (Layers 03-06). Makes Terraform the authoritative
# owner of VM lifecycle in NetBox — creating/destroying a VM in Terraform
# automatically updates NetBox.
#
# The seed script (scripts/netbox-seed.py) retains ownership of physical
# infrastructure: manufacturers, device types, devices, cables, VLANs, etc.
#
# Provider: e-breuninger/netbox v5.1.0 officially supports NetBox 4.3.0-4.4.10.
# FirbLab runs NetBox 4.5.2 — one minor version ahead. The provider emits a
# non-blocking warning but the CRUD endpoints we use are stable across 4.4→4.5.
#
# Prerequisites:
#   - NetBox running at http://10.0.20.14:8080 (deployed by Layer 05 + Ansible)
#   - API token stored in Vault at secret/services/netbox → api_token
#   - Vault env vars set (VAULT_ADDR, VAULT_TOKEN, VAULT_CACERT)
#   - Existing VM records cleaned from NetBox (seed script creates conflicts)
#
# Usage:
#   cd terraform/layers/08-netbox-config
#   terraform init
#   terraform apply                # reads API token from Vault
#
# Emergency fallback (Vault unreachable):
#   terraform apply -var use_vault=false -var netbox_api_token="your-token"
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    netbox = {
      source  = "e-breuninger/netbox"
      version = ">= 5.1.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0.0"
    }
  }
}
