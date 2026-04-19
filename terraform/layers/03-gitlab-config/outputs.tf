# =============================================================================
# Layer 03-gitlab-config: Outputs
# =============================================================================

# ---------------------------------------------------------
# Group IDs
# ---------------------------------------------------------

output "infrastructure_group_id" {
  description = "Infrastructure group ID"
  value       = gitlab_group.groups["infrastructure"].id
}

output "applications_group_id" {
  description = "Applications group ID"
  value       = gitlab_group.groups["applications"].id
}

output "personal_group_id" {
  description = "Personal group ID"
  value       = gitlab_group.groups["personal"].id
}

output "documentation_group_id" {
  description = "Documentation group ID"
  value       = gitlab_group.groups["documentation"].id
}

# ---------------------------------------------------------
# Project URLs
# ---------------------------------------------------------

output "project_urls" {
  description = "Map of project keys to their HTTP clone URLs"
  value       = { for k, v in gitlab_project.projects : k => v.http_url_to_repo }
}

output "firblab_project_url" {
  description = "firblab monorepo HTTP clone URL"
  value       = gitlab_project.projects["firblab"].http_url_to_repo
}

# ---------------------------------------------------------
# Summary
# ---------------------------------------------------------

output "group_count" {
  description = "Number of groups created"
  value       = length(gitlab_group.groups)
}

output "project_count" {
  description = "Number of projects created"
  value       = length(gitlab_project.projects)
}

output "label_count" {
  description = "Number of labels created (projects × common labels)"
  value       = length(gitlab_project_label.labels)
}

# ---------------------------------------------------------
# Deploy Tokens
# ---------------------------------------------------------

output "argocd_deploy_token_username" {
  description = "ArgoCD deploy token username (token stored in Vault at secret/services/gitlab)"
  value       = gitlab_deploy_token.argocd_readonly.username
}

# ---------------------------------------------------------
# GitLab Agent for Kubernetes
# ---------------------------------------------------------

output "cluster_agent_id" {
  description = "GitLab cluster agent ID for firblab-rke2 (token in Vault at secret/k8s/gitlab-agent)"
  value       = gitlab_cluster_agent.firblab_rke2.agent_id
}

output "cluster_agent_name" {
  description = "GitLab cluster agent name"
  value       = gitlab_cluster_agent.firblab_rke2.name
}
