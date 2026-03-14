# =============================================================================
# Layer 04: RKE2 Cluster — SSH Key Storage in Vault
# =============================================================================
# Writes Terraform-generated SSH private keys to Vault at secret/compute/<host>.
# These keys are consumed by CI/CD pipeline deploy jobs that run Ansible
# playbooks against target hosts.
#
# Path format: secret/compute/<hostname> → { ssh_private_key: "..." }
# Consumer: scripts/ci-setup-ssh.sh (reads via Vault API in CI before_script)
# Policy: gitlab-ci (Layer 02-vault-config grants secret/data/compute/* read)
#
# Note: The RKE2 cluster module outputs SSH keys as maps keyed by node name
# (e.g., "rke2-server-1"). We iterate over both server and agent maps.
# =============================================================================

resource "vault_kv_secret_v2" "rke2_server_ssh" {
  for_each = var.rke2_enabled ? module.rke2_cluster[0].server_ssh_keys : {}

  mount = "secret"
  name  = "compute/${each.key}"

  data_json = jsonencode({
    ssh_private_key = each.value
  })
}

resource "vault_kv_secret_v2" "rke2_agent_ssh" {
  for_each = var.rke2_enabled ? module.rke2_cluster[0].agent_ssh_keys : {}

  mount = "secret"
  name  = "compute/${each.key}"

  data_json = jsonencode({
    ssh_private_key = each.value
  })
}
