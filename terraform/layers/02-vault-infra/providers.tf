# =============================================================================
# Layer 02-vault-infra: Vault VM Infrastructure - Provider Configuration
# =============================================================================
# Provisions the Proxmox VM for vault-2. Vault software configuration is
# managed separately by Layer 02-vault-config and Ansible.
#
# Dual-mode authentication: reads Proxmox API credentials from Vault by
# default. Falls back to direct variables for bootstrap (before Vault exists).
#
# Cluster topology:
#   vault-1: Mac Mini M4 (macOS native, ARM64)            - 10.0.10.10
#   vault-2: Proxmox VM on lab-02 (VLAN 50)           - 10.0.50.2
#   vault-3: RPi5 CM5 (Ubuntu 24.04 ARM64 bare metal)     - 10.0.10.13
#
# Terraform only manages vault-2 (Proxmox VM). The Mac Mini and RPi nodes
# are provisioned via Ansible since they are not Proxmox-managed resources.
#
# Normal usage (Vault is running):
#   terraform apply
#
# Bootstrap (no Vault yet):
#   terraform apply -var use_vault=false \
#     -var-file=../../environments/lab-02.tfvars
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.81.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0.0"
    }
  }
}

# ---------------------------------------------------------
# Vault Provider
# ---------------------------------------------------------

provider "vault" {
  address      = var.vault_addr
  token        = var.vault_token
  ca_cert_file = var.vault_ca_cert != "" ? pathexpand(var.vault_ca_cert) : null
}

# ---------------------------------------------------------
# Read Proxmox Credentials from Vault (KV v2)
# ---------------------------------------------------------

data "vault_kv_secret_v2" "proxmox" {
  count = var.use_vault ? 1 : 0
  mount = "secret"
  name  = "infra/proxmox/${var.proxmox_node}"
}

locals {
  proxmox_api_url = var.use_vault ? data.vault_kv_secret_v2.proxmox[0].data["url"] : var.proxmox_api_url
  proxmox_api_token = var.use_vault ? (
    "${data.vault_kv_secret_v2.proxmox[0].data["token_id"]}=${data.vault_kv_secret_v2.proxmox[0].data["token_secret"]}"
  ) : var.proxmox_api_token
}

# ---------------------------------------------------------
# Proxmox Provider
# ---------------------------------------------------------

provider "proxmox" {
  endpoint  = local.proxmox_api_url
  api_token = local.proxmox_api_token
  insecure  = true # Self-signed Proxmox cert

  # SSH is required by the bpg/proxmox provider to upload cloud-init snippets
  # (the Proxmox API doesn't support snippet uploads — SFTP is used instead).
  # Uses ssh-agent with the lab-02 key: ssh-add ~/.ssh/id_ed25519_lab-02
  ssh {
    agent    = true
    username = "admin"
  }
}
