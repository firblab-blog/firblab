# =============================================================================
# Layer 02-vault-config: Vault Configuration - Outputs
# =============================================================================

output "admin_token" {
  description = "Admin token for day-to-day Vault operations — save to ~/.vault-token"
  value       = vault_token.admin.client_token
  sensitive   = true
}

output "policies" {
  description = "Vault policies created by this layer"
  value = [
    vault_policy.admin.name,
    vault_policy.terraform.name,
    vault_policy.gitlab_ci.name,
    vault_policy.k8s_external_secrets.name,
    vault_policy.cert_manager.name,
    vault_policy.backup.name,
  ]
}

# ---------------------------------------------------------
# PKI Root CA Certificate
# ---------------------------------------------------------
# Distribute this CA cert to hosts and k8s clusters so they
# trust certificates issued by the intermediate CA.
# ---------------------------------------------------------

output "pki_root_ca_pem" {
  description = "Root CA certificate PEM — distribute to hosts/k8s for trust"
  value       = vault_pki_secret_backend_root_cert.root.certificate
  sensitive   = false # CA cert is public by definition
}

output "seeded_secrets" {
  description = "Vault KV paths seeded with infrastructure credentials"
  value       = [for k, v in vault_kv_secret_v2.proxmox : "secret/infra/proxmox/${k}"]
}

output "kv_mount_path" {
  description = "Path of the KV v2 secrets engine"
  value       = vault_mount.kv.path
}

# ---------------------------------------------------------
# GitLab CI AppRole Credentials
# ---------------------------------------------------------
# These are also written to Vault KV at secret/services/gitlab/approle
# by the vault_kv_secret_v2.gitlab_ci_approle resource. Layer 03 reads
# them from Vault automatically — no manual -var flags needed.
#
# Outputs kept for backward compatibility and debugging:
#   terraform output -raw gitlab_ci_approle_role_id
# ---------------------------------------------------------

# ---------------------------------------------------------
# Kubernetes Service Secret Paths
# ---------------------------------------------------------
# Generated credentials for K8s workloads. Retrieve with:
#   vault kv get secret/k8s/grafana
#   vault kv get secret/k8s/longhorn
#   vault kv get secret/services/sonarqube
# ---------------------------------------------------------

output "k8s_secret_paths" {
  description = "Vault KV paths for K8s service credentials (synced by ESO)"
  value = [
    "secret/k8s/grafana",
    "secret/k8s/longhorn",
    "secret/services/sonarqube",
  ]
}

output "gitlab_ci_approle_role_id" {
  description = "AppRole role_id for GitLab CI — set as VAULT_ROLE_ID instance variable"
  value       = data.vault_approle_auth_backend_role_id.gitlab_ci.role_id
  sensitive   = true
}

output "gitlab_ci_approle_secret_id" {
  description = "AppRole secret_id for GitLab CI — set as VAULT_SECRET_ID instance variable"
  value       = vault_approle_auth_backend_role_secret_id.gitlab_ci.secret_id
  sensitive   = true
}
