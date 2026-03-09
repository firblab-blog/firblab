# =============================================================================
# Layer 05: Standalone Services — SSH Key Storage in Vault
# =============================================================================
# Writes Terraform-generated SSH private keys to Vault at secret/compute/<host>.
# These keys are consumed by CI/CD pipeline deploy jobs that run Ansible
# playbooks against target hosts.
#
# Path format: secret/compute/<hostname> → { ssh_private_key: "..." }
# Consumer: scripts/ci-setup-ssh.sh (reads via Vault API in CI before_script)
# Policy: gitlab-ci (Layer 02-vault-config grants secret/data/compute/* read)
# =============================================================================

resource "vault_kv_secret_v2" "ghost_ssh" {
  mount = "secret"
  name  = "compute/ghost"

  data_json = jsonencode({
    ssh_private_key = module.ghost.ssh_private_key
  })
}

resource "vault_kv_secret_v2" "foundryvtt_ssh" {
  mount = "secret"
  name  = "compute/foundryvtt"

  data_json = jsonencode({
    ssh_private_key = module.foundryvtt.ssh_private_key
  })
}

resource "vault_kv_secret_v2" "roundcube_ssh" {
  mount = "secret"
  name  = "compute/roundcube"

  data_json = jsonencode({
    ssh_private_key = module.roundcube.ssh_private_key
  })
}

resource "vault_kv_secret_v2" "mealie_ssh" {
  mount = "secret"
  name  = "compute/mealie"

  data_json = jsonencode({
    ssh_private_key = module.mealie.ssh_private_key
  })
}

resource "vault_kv_secret_v2" "wireguard_ssh" {
  mount = "secret"
  name  = "compute/wireguard"

  data_json = jsonencode({
    ssh_private_key = module.wireguard.ssh_private_key
  })
}

resource "vault_kv_secret_v2" "netbox_ssh" {
  mount = "secret"
  name  = "compute/netbox"

  data_json = jsonencode({
    ssh_private_key = module.netbox.ssh_private_key
  })
}

resource "vault_kv_secret_v2" "pbs_ssh" {
  mount = "secret"
  name  = "compute/pbs"

  data_json = jsonencode({
    ssh_private_key = module.pbs.ssh_private_key
  })
}

resource "vault_kv_secret_v2" "authentik_ssh" {
  mount = "secret"
  name  = "compute/authentik"

  data_json = jsonencode({
    ssh_private_key = module.authentik.ssh_private_key
  })
}

resource "vault_kv_secret_v2" "patchmon_ssh" {
  mount = "secret"
  name  = "compute/patchmon"

  data_json = jsonencode({
    ssh_private_key = module.patchmon.ssh_private_key
  })
}

resource "vault_kv_secret_v2" "actualbudget_ssh" {
  mount = "secret"
  name  = "compute/actualbudget"

  data_json = jsonencode({
    ssh_private_key = module.actualbudget.ssh_private_key
  })
}

resource "vault_kv_secret_v2" "traefik_proxy_ssh" {
  mount = "secret"
  name  = "compute/traefik-proxy"

  data_json = jsonencode({
    ssh_private_key = module.traefik_proxy.ssh_private_key
  })
}

resource "vault_kv_secret_v2" "vaultwarden_ssh" {
  mount = "secret"
  name  = "compute/vaultwarden"

  data_json = jsonencode({
    ssh_private_key = module.vaultwarden.ssh_private_key
  })
}


resource "vault_kv_secret_v2" "backup_ssh" {
  mount = "secret"
  name  = "compute/backup"

  data_json = jsonencode({
    ssh_private_key = module.backup.ssh_private_key
  })
}

resource "vault_kv_secret_v2" "war_ssh" {
  mount = "secret"
  name  = "compute/war"

  data_json = jsonencode({
    ssh_private_key = module.war.ssh_private_key
  })
}
