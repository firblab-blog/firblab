# =============================================================================
# Layer 07-authentik-config: Provider Configuration
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
# Emergency fallback (Vault unreachable):
#   terraform apply -var use_vault=false \
#     -var authentik_token="your-bootstrap-token"
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
# Read Authentik Bootstrap Token from Vault (KV v2)
# ---------------------------------------------------------

data "vault_kv_secret_v2" "authentik" {
  count = var.use_vault ? 1 : 0
  mount = "secret"
  name  = "services/authentik"
}

locals {
  authentik_token = var.use_vault ? data.vault_kv_secret_v2.authentik[0].data["bootstrap_token"] : var.authentik_token
}

# ---------------------------------------------------------
# Authentik Provider
# ---------------------------------------------------------

provider "authentik" {
  url   = var.authentik_url
  token = local.authentik_token
}
