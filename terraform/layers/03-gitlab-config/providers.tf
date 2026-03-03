# =============================================================================
# Layer 03-gitlab-config: Provider Configuration
# =============================================================================
# All credentials are read from Vault automatically. No tfvars or -var flags
# needed for normal operation — the Vault provider reads VAULT_ADDR,
# VAULT_TOKEN, and VAULT_CACERT from environment variables.
#
# Normal usage (everything from Vault + env vars):
#   export VAULT_ADDR=https://10.0.10.10:8200
#   export VAULT_TOKEN=hvs.xxxxx
#   export VAULT_CACERT=~/.lab/tls/ca/ca.pem
#   terraform apply
#
# Emergency fallback (Vault unreachable — GitLab only, GitHub requires Vault):
#   terraform apply -var use_vault=false \
#     -var gitlab_token="glpat-xxxx"
# =============================================================================

# ---------------------------------------------------------
# Vault Provider
# ---------------------------------------------------------
# The hashicorp/vault provider natively reads from environment:
#   VAULT_ADDR    → API address
#   VAULT_TOKEN   → Authentication token
#   VAULT_CACERT  → CA certificate path
# No explicit configuration needed when env vars are set.
# ---------------------------------------------------------

provider "vault" {}

# ---------------------------------------------------------
# Read GitLab Credentials from Vault (KV v2)
# ---------------------------------------------------------

data "vault_kv_secret_v2" "gitlab" {
  count = var.use_vault ? 1 : 0
  mount = "secret"
  name  = "services/gitlab/admin"
}

data "vault_kv_secret_v2" "gitlab_approle" {
  count = var.use_vault ? 1 : 0
  mount = "secret"
  name  = "services/gitlab/approle"
}

locals {
  gitlab_token            = var.use_vault ? data.vault_kv_secret_v2.gitlab[0].data["personal_access_token"] : var.gitlab_token
  vault_approle_role_id   = var.use_vault ? data.vault_kv_secret_v2.gitlab_approle[0].data["role_id"] : var.vault_approle_role_id
  vault_approle_secret_id = var.use_vault ? data.vault_kv_secret_v2.gitlab_approle[0].data["secret_id"] : var.vault_approle_secret_id

  # Read CA cert content for the gitlab_instance_variable.vault_cacert resource.
  # Local dev: read from vault_cacert_path (~/.lab/tls/ca/ca.pem).
  # CI: the file doesn't exist at that path inside the Docker container, but
  # VAULT_CACERT env var points to the GitLab file-type variable's temp file.
  _vault_cacert_local_path = pathexpand(var.vault_cacert_path)
  _vault_cacert_env_path   = coalesce(var.vault_cacert_env_override, "/dev/null")
  vault_cacert_content = (
    fileexists(local._vault_cacert_local_path)
    ? file(local._vault_cacert_local_path)
    : fileexists(local._vault_cacert_env_path)
    ? file(local._vault_cacert_env_path)
    : ""
  )
}

# ---------------------------------------------------------
# GitLab Provider
# ---------------------------------------------------------

provider "gitlab" {
  base_url = var.gitlab_base_url
  token    = local.gitlab_token
}

# ---------------------------------------------------------
# GitHub Provider
# ---------------------------------------------------------
# Manages the public example-lab-blog/firblab GitHub repository
# (security settings, branch protection). Authenticates with
# a fine-grained PAT stored in Vault at secret/services/github
# (key: admin_token, Administration RW + Contents Read).
#
# Separate from mirror_token (Contents RW only) used by the
# GitLab push mirror — least privilege separation.
#
# NOTE: Always requires Vault (no use_vault=false fallback).
# The data.vault_kv_secret_v2.github data source in main.tf
# has no count guard — the mirror already requires it.
# ---------------------------------------------------------

provider "github" {
  owner = data.vault_kv_secret_v2.github.data["github_username"]
  token = data.vault_kv_secret_v2.github.data["admin_token"]
}
