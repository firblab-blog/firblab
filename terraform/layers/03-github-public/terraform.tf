# =============================================================================
# Layer 03-github-public: Public GitHub Repository Management
# =============================================================================
# Manages public GitHub repositories and branch protections that correspond to
# firblab-managed public surfaces.
#
# This layer is intentionally separate from 03-gitlab-config so GitHub API
# rate limits do not block day-to-day GitLab configuration changes.
#
# Prerequisites:
#   - GitHub credentials stored in Vault at secret/services/github
#   - Vault env vars set (VAULT_ADDR, VAULT_TOKEN, VAULT_CACERT)
#
# Usage:
#   cd terraform/layers/03-github-public
#   terraform init
#   terraform apply
#
# State migration from 03-gitlab-config:
#   1. Import or move existing GitHub resources into this layer's state
#   2. Remove GitHub resources from the old 03-gitlab-config state
#   3. Apply this layer first, then apply 03-gitlab-config
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0.0"
    }
    github = {
      source  = "integrations/github"
      version = ">= 6.6.0"
    }
  }
}
