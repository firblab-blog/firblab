# =============================================================================
# Layer 03-gitlab-config: GitLab CE + GitHub Configuration
# =============================================================================
# Manages GitLab organizational structure: groups, projects, labels, branch
# protections, and CI/CD variables. Also manages the public GitHub mirror
# repo (example-lab-blog/firblab) security settings and branch protection.
#
# Prerequisites:
#   - GitLab CE running at http://10.0.10.50
#   - PAT stored in Vault at secret/services/gitlab/admin
#   - GitHub fine-grained PAT stored in Vault at secret/services/github
#   - Vault env vars set (VAULT_ADDR, VAULT_TOKEN, VAULT_CACERT)
#
# Usage:
#   cd terraform/layers/03-gitlab-config
#   terraform init
#   terraform apply                # reads PAT from Vault, no tfvars needed
#
# Emergency fallback (Vault unreachable — GitLab only, GitHub requires Vault):
#   terraform apply -var use_vault=false -var gitlab_token="glpat-xxxx"
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = ">= 17.8.0"
    }
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
