###############################################
# GitHub Repository: example-lab-blog/firblab
###############################################
# Manages security and merge settings on the public GitHub
# mirror of firblab-public. The repo was created manually
# and imported into Terraform state.
#
# NOTE: security_and_analysis may cause 422 errors on some
# user-owned public repos (provider bug #2190). If apply
# fails on this block, remove it and enable secret scanning
# via gh api instead.
#
# Fine-grained PAT permissions required (admin_token):
#   Administration: Read & Write
#   Contents: Read
#   Metadata: Read (implicit)
###############################################

resource "github_repository" "firblab" {
  name        = "firblab"
  description = "FirbLab — production-grade homelab infrastructure platform. Terraform, Ansible, Packer, Vault, RKE2 Kubernetes, and ArgoCD GitOps."
  visibility  = "public"

  has_issues      = true
  has_wiki        = false
  has_projects    = false
  has_downloads   = true
  has_discussions = false

  delete_branch_on_merge      = true
  web_commit_signoff_required = true
  vulnerability_alerts        = true

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_repository" "project_guardrails" {
  name        = "project-guardrails"
  description = "Portable repo-local guardrails for projects that want a reviewable operating baseline, not just lint rules."
  visibility  = "public"

  has_issues      = true
  has_wiki        = false
  has_projects    = false
  has_downloads   = true
  has_discussions = false

  delete_branch_on_merge      = true
  web_commit_signoff_required = true
  vulnerability_alerts        = true

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

###############################################
# GitHub Branch Protection: main
###############################################
# Protects main from force pushes and deletion. Direct
# pushes are still allowed because GitLab-driven public
# mirrors push directly to main in this workflow.
###############################################

resource "github_branch_protection" "firblab_main" {
  repository_id = github_repository.firblab.node_id
  pattern       = "main"

  allows_force_pushes = false
  allows_deletions    = false
  enforce_admins      = false
}

resource "github_branch_protection" "project_guardrails_main" {
  repository_id = github_repository.project_guardrails.node_id
  pattern       = "main"

  allows_force_pushes = false
  allows_deletions    = false
  enforce_admins      = false
}
