# =============================================================================
# Layer 07-authentik-config: Outputs
# =============================================================================

# ---------------------------------------------------------
# Provider Summary
# ---------------------------------------------------------

output "oauth2_provider_count" {
  description = "Number of OIDC providers created"
  value       = length(authentik_provider_oauth2.oauth2)
}

output "proxy_provider_count" {
  description = "Number of ForwardAuth proxy providers created"
  value       = length(authentik_provider_proxy.proxy)
}

output "application_count" {
  description = "Total number of Authentik applications"
  value       = length(authentik_application.oauth2) + length(authentik_application.proxy) + length(authentik_application.bookmark)
}

output "bookmark_app_count" {
  description = "Number of bookmark applications (no SSO)"
  value       = length(authentik_application.bookmark)
}

# ---------------------------------------------------------
# Vault Paths Written
# ---------------------------------------------------------

output "vault_oidc_paths" {
  description = "Vault KV paths where OIDC credentials were written"
  value       = { for k, v in vault_kv_secret_v2.oidc_credentials : k => "secret/${v.name}" }
}

# ---------------------------------------------------------
# Client IDs (non-sensitive, useful for downstream config)
# ---------------------------------------------------------

output "oauth2_client_ids" {
  description = "Map of service name to OIDC client_id"
  value       = { for k, v in authentik_provider_oauth2.oauth2 : k => v.client_id }
}

# ---------------------------------------------------------
# Outpost
# ---------------------------------------------------------

output "outpost_name" {
  description = "Name of the ForwardAuth outpost"
  value       = data.authentik_outpost.embedded.name
}
