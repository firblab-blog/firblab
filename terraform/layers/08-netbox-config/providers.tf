# =============================================================================
# Layer 08-netbox-config: Provider Configuration
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
#     -var netbox_api_token="your-api-token"
# =============================================================================

# ---------------------------------------------------------
# Vault Provider
# ---------------------------------------------------------
# The hashicorp/vault provider natively reads from environment:
#   VAULT_ADDR    -> API address
#   VAULT_TOKEN   -> Authentication token
#   VAULT_CACERT  -> CA certificate path
# No explicit configuration needed when env vars are set.
# ---------------------------------------------------------

provider "vault" {}

# ---------------------------------------------------------
# Read NetBox API Token from Vault (KV v2)
# ---------------------------------------------------------

data "vault_kv_secret_v2" "netbox" {
  count = var.use_vault ? 1 : 0
  mount = "secret"
  name  = "services/netbox"
}

locals {
  netbox_api_token = var.use_vault ? data.vault_kv_secret_v2.netbox[0].data["api_token"] : var.netbox_api_token
}

# ---------------------------------------------------------
# NetBox Provider
# ---------------------------------------------------------

provider "netbox" {
  server_url = var.netbox_url
  api_token  = local.netbox_api_token
}
