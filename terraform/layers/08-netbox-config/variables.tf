# =============================================================================
# Layer 08-netbox-config: Variables
# =============================================================================
# All credentials are read from Vault automatically:
#   - NetBox API token from secret/services/netbox -> api_token
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
  description = "Read NetBox API token from Vault (true) or use direct variable (false)"
  type        = bool
  default     = true
}

# ---------------------------------------------------------
# NetBox Connection
# ---------------------------------------------------------

variable "netbox_url" {
  description = "NetBox instance URL"
  type        = string
  default     = "http://10.0.20.14:8080"
}

variable "netbox_api_token" {
  description = "NetBox API token (emergency fallback when use_vault=false)"
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------
# Hetzner Gateway
# ---------------------------------------------------------

variable "hetzner_gateway_ip" {
  description = "Public IPv4 address of the Hetzner gateway (from Layer 06 terraform output server_ip). Empty = skip IP assignment."
  type        = string
  default     = "203.0.113.10"
}
