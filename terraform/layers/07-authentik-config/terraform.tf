# =============================================================================
# Layer 07-authentik-config: Authentik SSO/IDP Configuration
# =============================================================================
# Manages Authentik OIDC applications, ForwardAuth providers, groups, and
# the embedded proxy outpost. Writes OIDC client credentials back to Vault
# for consumption by K8s External Secrets Operator and Ansible roles.
#
# Prerequisites:
#   - Authentik running at http://10.0.10.16:9000 (deployed by Layer 05 + Ansible)
#   - Bootstrap token stored in Vault at secret/services/authentik → bootstrap_token
#   - Vault env vars set (VAULT_ADDR, VAULT_TOKEN, VAULT_CACERT)
#
# Usage:
#   cd terraform/layers/07-authentik-config
#   terraform init
#   terraform apply                # reads bootstrap_token from Vault
#
# Emergency fallback (Vault unreachable):
#   terraform apply -var use_vault=false -var authentik_token="your-api-token"
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = ">= 2025.12.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0.0"
    }
  }
}
