# =============================================================================
# Layer 03: Core Infrastructure — SSH Key Storage in Vault
# =============================================================================
# Writes Terraform-generated SSH private keys to Vault at secret/compute/<host>.
# These keys are consumed by CI/CD pipeline deploy jobs that run Ansible
# playbooks against target hosts.
#
# Path format: secret/compute/<hostname> → { ssh_private_key: "..." }
# Consumer: scripts/ci-setup-ssh.sh (reads via Vault API in CI before_script)
# Policy: gitlab-ci (Layer 02-vault-config grants secret/data/compute/* read)
# =============================================================================

resource "vault_kv_secret_v2" "gitlab_ssh" {
  mount = "secret"
  name  = "compute/gitlab"

  data_json = jsonencode({
    ssh_private_key = module.gitlab.ssh_private_key
  })
}

resource "vault_kv_secret_v2" "gitlab_runner_ssh" {
  mount = "secret"
  name  = "compute/gitlab-runner"

  data_json = jsonencode({
    ssh_private_key = module.gitlab_runner.ssh_private_key
  })
}
