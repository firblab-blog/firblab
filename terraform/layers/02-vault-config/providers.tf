# =============================================================================
# Layer 02-vault-config: Vault Configuration - Provider
# =============================================================================
# Uses the HashiCorp Vault provider to manage Vault's internal configuration
# declaratively. Requires a running, initialized, unsealed Vault cluster.
#
# Authentication: Pass the Vault token via TF_VAR_vault_token environment
# variable or in a local .tfvars file (excluded from Git).
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0"
    }
  }
}

provider "vault" {
  address      = var.vault_addr
  token        = var.vault_token
  ca_cert_file = var.vault_ca_cert != "" ? pathexpand(var.vault_ca_cert) : null
}
