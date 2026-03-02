# =============================================================================
# Layer 03: Core Infrastructure - Provider Configuration
# =============================================================================
# Deploys GitLab CE and GitLab Runner on the Management VLAN (untagged on vmbr0).
# GitLab and Runner can be on different Proxmox nodes via per-service
# variables (gitlab_proxmox_node, gitlab_runner_proxmox_node).
#
# With Proxmox clustering, the provider connects to one node's API but can
# manage VMs on ANY node in the cluster. The proxmox_node variable determines
# which node's API credentials are read from Vault.
#
# Normal usage (Vault is running):
#   terraform apply -var proxmox_node=lab-01
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

  # Node IP lookup for SSH key injection (same pattern as Layer 05)
  proxmox_node_ips = {
    "lab-01" = "10.0.10.42"
    "lab-02" = "10.0.10.2"
    "lab-03" = "10.0.10.3"
    "lab-04" = "10.0.10.4"
  }
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
  # Operator must load the node key first: ssh-add ~/.ssh/id_ed25519_lab-*
  ssh {
    agent    = true
    username = "admin"
  }
}
