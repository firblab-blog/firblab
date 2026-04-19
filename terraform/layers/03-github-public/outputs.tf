# =============================================================================
# Layer 03-github-public: Outputs
# =============================================================================

output "firblab_github_repo_url" {
  description = "Public GitHub URL for firblab"
  value       = github_repository.firblab.html_url
}

output "project_guardrails_github_repo_url" {
  description = "Public GitHub URL for project-guardrails"
  value       = github_repository.project_guardrails.html_url
}
