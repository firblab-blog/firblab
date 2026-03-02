# =============================================================================
# Layer 06: Hetzner - Write Server IPs to Vault
# =============================================================================
# After provisioning Hetzner servers, write their public IPs back to Vault
# so Ansible can look them up dynamically via the community.hashi_vault
# collection — no manual IP copy-paste into inventory.
#
# Vault path: secret/infra/hetzner/server_ips
#
# Ansible consumption:
#   ansible/inventory/host_vars/lab-honeypot.yml uses:
#     lookup('community.hashi_vault.vault_kv2_get', 'infra/hetzner/server_ips')
#
# Only active when use_vault=true (skipped during bootstrap without Vault).
# =============================================================================

resource "vault_kv_secret_v2" "hetzner_server_ips" {
  count = var.use_vault ? 1 : 0

  mount = "secret"
  name  = "infra/hetzner/server_ips"

  data_json = jsonencode({
    gateway_ip  = module.server.server_ip
    honeypot_ip = module.honeypot_server.server_ip
  })
}

# =============================================================================
# Gateway Service Credentials
# =============================================================================
# Stores gateway service passwords so ansible/playbooks/gateway-deploy.yml can
# read them from Vault rather than relying on Terraform state or cloud-init
# template variables.
#
# Ansible consumption:
#   ansible/playbooks/gateway-deploy.yml reads:
#     infra/hetzner/credentials → gateway_gotify_password, gateway_traefik_dashboard_hash,
#                                  gateway_adguard_password_hash
#
# bcrypt note: Terraform's bcrypt() recalculates on every apply (random salt), so
# terraform plan always shows a diff on this resource. This is pre-existing behavior —
# the same bcrypt() calls already exist in cloud_init_vars (main.tf). The pattern:
#   1. terraform apply → new bcrypt hashes written to Vault
#   2. gateway-deploy.yml deploys new (still valid) hashes → brief service restart
#   3. Subsequent gateway-deploy.yml runs → Vault unchanged → no restart
# =============================================================================
resource "vault_kv_secret_v2" "hetzner_credentials" {
  count = var.use_vault ? 1 : 0

  mount = "secret"
  name  = "infra/hetzner/credentials"

  data_json = jsonencode({
    # Plain-text passwords (Gotify uses env var, not bcrypt)
    gotify_password        = random_password.gotify.result
    traefik_dashboard_pass = random_password.traefik_dashboard.result
    adguard_password       = random_password.adguard.result
    # Pre-computed bcrypt hashes — Ansible reads directly, no Jinja2 hash recomputation
    # This keeps gateway configs stable between playbook runs (no spurious restarts)
    traefik_dashboard_hash = bcrypt(random_password.traefik_dashboard.result)
    adguard_password_hash  = bcrypt(random_password.adguard.result)
  })
}
