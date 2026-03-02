# =============================================================================
# Layer 07-authentik-config: Variables
# =============================================================================
# All credentials are read from Vault automatically:
#   - Authentik bootstrap token from secret/services/authentik
#   - Vault provider reads VAULT_ADDR, VAULT_TOKEN, VAULT_CACERT from env
#
# Normal usage (no -var flags needed):
#   export VAULT_ADDR=https://10.0.10.10:8200
#   export VAULT_TOKEN=hvs.xxxxx
#   export VAULT_CACERT=~/.lab/tls/ca/ca.pem
#   terraform apply
# =============================================================================

# ---------------------------------------------------------
# Vault Integration
# ---------------------------------------------------------

variable "use_vault" {
  description = "Read Authentik bootstrap token from Vault (true) or use direct variable (false)"
  type        = bool
  default     = true
}

# ---------------------------------------------------------
# Authentik Connection
# ---------------------------------------------------------

variable "authentik_url" {
  description = "Authentik instance URL"
  type        = string
  default     = "http://10.0.10.16:9000"
}

variable "authentik_token" {
  description = "Authentik API token (emergency fallback when use_vault=false)"
  type        = string
  sensitive   = true
  default     = ""
}
