# =============================================================================
# Layer 03-github-public: Provider Configuration
# =============================================================================
# All credentials are read from Vault automatically. No tfvars or -var flags
# needed for normal operation — the Vault provider reads VAULT_ADDR,
# VAULT_TOKEN, and VAULT_CACERT from environment variables.
#
# Normal usage:
#   export VAULT_ADDR=https://10.0.10.10:8200
#   export VAULT_TOKEN=hvs.xxxxx
#   export VAULT_CACERT=~/.lab/tls/ca/ca.pem
#   terraform apply
# =============================================================================

provider "vault" {}

data "vault_kv_secret_v2" "github" {
  mount = "secret"
  name  = "services/github"
}

provider "github" {
  owner = data.vault_kv_secret_v2.github.data["github_username"]
  token = data.vault_kv_secret_v2.github.data["admin_token"]
}
