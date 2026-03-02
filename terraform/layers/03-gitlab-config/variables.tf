# =============================================================================
# Layer 03-gitlab-config: GitLab Configuration - Variables
# =============================================================================
# All credentials are read from Vault automatically:
#   - GitLab PAT from secret/services/gitlab/admin
#   - AppRole role_id + secret_id from secret/services/gitlab/approle
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
  description = "Read GitLab PAT from Vault (true) or use direct variable (false)"
  type        = bool
  default     = true
}

# ---------------------------------------------------------
# GitLab Connection
# ---------------------------------------------------------

variable "gitlab_base_url" {
  description = "GitLab instance URL"
  type        = string
  default     = "http://10.0.10.50"
}

variable "gitlab_token" {
  description = "GitLab Personal Access Token (emergency fallback when use_vault=false)"
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------
# Instance-Level CI/CD Variables (Vault)
# ---------------------------------------------------------
# These are set as GitLab instance-level CI/CD variables so
# ALL projects inherit Vault access automatically.
# ---------------------------------------------------------

variable "vault_addr" {
  description = "Vault API address for CI/CD pipelines"
  type        = string
  default     = "https://10.0.10.10:8200"
}

variable "vault_cacert_path" {
  description = "Local path to Vault CA certificate PEM file (read at plan time)"
  type        = string
  default     = "~/.lab/tls/ca/ca.pem"
}

variable "vault_cacert_env_override" {
  description = "Alternate CA cert file path (CI sets this via TF_VAR_vault_cacert_env_override to the VAULT_CACERT file-type variable path)"
  type        = string
  default     = ""
}

variable "vault_approle_role_id" {
  description = "AppRole role_id override (emergency fallback when use_vault=false; normally read from Vault)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_approle_secret_id" {
  description = "AppRole secret_id override (emergency fallback when use_vault=false; normally read from Vault)"
  type        = string
  sensitive   = true
  default     = ""
}
