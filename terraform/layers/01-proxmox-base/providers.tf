# =============================================================================
# Layer 01: Proxmox Base - Provider Configuration
# =============================================================================
# Downloads ISOs, cloud images, and LXC templates to all Proxmox nodes.
#
# With Proxmox clustering, the provider connects to one node's API and can
# manage resources on ALL nodes in the cluster. The proxmox_node variable
# determines which node's API credentials are read from Vault — use any
# cluster member.
#
# Normal usage (clustered, Vault is running):
#   terraform apply -var proxmox_node=lab-01
#
# Bootstrap (no Vault yet):
#   terraform apply -var use_vault=false \
#     -var-file=../../environments/lab-01.tfvars
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

  ssh {
    agent = false
  }
}
