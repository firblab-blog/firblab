# =============================================================================
# Layer 03: Core Infrastructure - Outputs
# =============================================================================

# ---------------------------------------------------------
# GitLab CE Outputs
# ---------------------------------------------------------

output "gitlab_vm_id" {
  description = "Proxmox VM ID for GitLab CE"
  value       = module.gitlab.vm_id
}

output "gitlab_ipv4_addresses" {
  description = "IPv4 addresses assigned to GitLab CE"
  value       = module.gitlab.ipv4_addresses
}

output "gitlab_ssh_private_key" {
  description = "SSH private key for GitLab CE"
  value       = module.gitlab.ssh_private_key
  sensitive   = true
}

output "gitlab_ssh_public_key" {
  description = "SSH public key for GitLab CE"
  value       = module.gitlab.ssh_public_key
}

output "gitlab_ssh_private_key_path" {
  description = "Path to the SSH private key for GitLab CE"
  value       = module.gitlab.ssh_private_key_path
}

# ---------------------------------------------------------
# GitLab Runner Outputs
# ---------------------------------------------------------

output "gitlab_runner_container_id" {
  description = "Proxmox container ID for GitLab Runner"
  value       = module.gitlab_runner.container_id
}

output "gitlab_runner_ipv4_addresses" {
  description = "IPv4 addresses assigned to GitLab Runner"
  value       = module.gitlab_runner.ipv4_addresses
}

output "gitlab_runner_ssh_private_key" {
  description = "SSH private key for GitLab Runner"
  value       = module.gitlab_runner.ssh_private_key
  sensitive   = true
}

output "gitlab_runner_ssh_public_key" {
  description = "SSH public key for GitLab Runner"
  value       = module.gitlab_runner.ssh_public_key
}

output "gitlab_runner_ssh_private_key_path" {
  description = "Path to the SSH private key for GitLab Runner"
  value       = module.gitlab_runner.ssh_private_key_path
}

# ---------------------------------------------------------
# Wazuh Manager Outputs — REMOVED
# ---------------------------------------------------------
# Wazuh was removed to stay within lab-02's 16 GB RAM budget.
