# =============================================================================
# Layer 03-gitlab-config: GitLab CE Resource Bootstrap
# Rover CI visualization: https://github.com/im2nguyen/rover
# =============================================================================
# Creates the organizational structure for a clean, consolidated GitLab:
#   - Instance-level application settings (sign-in, auth, security)
#   - 4 top-level groups (Infrastructure, Applications, Personal, Documentation)
#   - 13 projects across those groups
#   - Standard labels on all projects
#   - Branch protection on infrastructure projects
#   - Instance-level CI/CD variables (Vault AppRole for all pipelines)
#
# This replaces the old lab-01 GitLab which had 18+ projects in a messy
# hierarchy. The new structure consolidates all per-node repos (lab-01,
# lab-02, firblab-05, firblab-macmini, firblab-rpi5, firblab-aws,
# lab-hetzner, firblab-win) into a single "firblab" monorepo.
#
# NOTE: The GitLab provider requires a PAT with 'api' scope. This is read
#       from Vault at secret/services/gitlab/admin (see providers.tf).
# =============================================================================

###############################################
# Locals - Configuration Data
###############################################

locals {
  # ---------------------------------------------------------------------------
  # Groups — flat hierarchy, 4 top-level groups
  # ---------------------------------------------------------------------------
  groups = {
    infrastructure = {
      name             = "Infrastructure"
      path             = "infrastructure"
      description      = "Infrastructure, automation, and platform engineering"
      visibility_level = "private"
    }
    applications = {
      name             = "Applications"
      path             = "applications"
      description      = "Application development projects"
      visibility_level = "private"
    }
    personal = {
      name             = "Personal"
      path             = "personal"
      description      = "Personal projects and hobby content"
      visibility_level = "private"
    }
    documentation = {
      name             = "Documentation"
      path             = "documentation"
      description      = "Documentation, guides, and knowledge base"
      visibility_level = "private"
    }
  }

  # ---------------------------------------------------------------------------
  # Projects
  # ---------------------------------------------------------------------------
  # Each project specifies its group, merge settings, and feature toggles.
  # Optional keys default to false/disabled if not set.
  # ---------------------------------------------------------------------------
  projects = {
    # --- Infrastructure ---
    firblab = {
      name                                         = "firblab"
      path                                         = "firblab"
      description                                  = "Homelab monorepo — Terraform, Ansible, Packer, and documentation for the entire firblab infrastructure"
      group_key                                    = "infrastructure"
      visibility_level                             = "private"
      wiki_enabled                                 = true
      container_registry_enabled                   = true
      only_allow_merge_if_pipeline_succeeds        = true
      only_allow_merge_if_all_discussions_resolved = true
      remove_source_branch_after_merge             = true
    }
    firblab_os = {
      name                                         = "firblab-os"
      path                                         = "firblab-os"
      description                                  = "FirbLab OS — portable, GitOps-native homelab infrastructure control plane. Deploy a hardened, Vault-first homelab stack on your own hardware."
      group_key                                    = "infrastructure"
      visibility_level                             = "private"
      wiki_enabled                                 = true
      container_registry_enabled                   = true
      only_allow_merge_if_pipeline_succeeds        = true
      only_allow_merge_if_all_discussions_resolved = true
      remove_source_branch_after_merge             = true
    }
    firblab_public = {
      name                                         = "firblab-public"
      path                                         = "firblab-public"
      description                                  = "FirbLab — production-grade homelab infrastructure platform. Sanitized public portfolio showcasing Terraform, Ansible, Packer, Vault, RKE2 Kubernetes, and ArgoCD GitOps."
      group_key                                    = "infrastructure"
      visibility_level                             = "private"
      wiki_enabled                                 = false
      container_registry_enabled                   = false
      only_allow_merge_if_pipeline_succeeds        = false
      only_allow_merge_if_all_discussions_resolved = false
      remove_source_branch_after_merge             = true
      initialize_with_readme                       = false
    }
    ci_templates = {
      name                                  = "ci-templates"
      path                                  = "ci-templates"
      description                           = "Reusable CI/CD pipeline templates and components"
      group_key                             = "infrastructure"
      visibility_level                      = "private"
      only_allow_merge_if_pipeline_succeeds = true
      remove_source_branch_after_merge      = true
    }
    cybersecurity = {
      name                                         = "cybersecurity"
      path                                         = "cybersecurity"
      description                                  = "Security infrastructure — Wazuh SIEM, Suricata IDS/IPS, MISP threat intel, security monitoring"
      group_key                                    = "infrastructure"
      visibility_level                             = "private"
      wiki_enabled                                 = true
      container_registry_enabled                   = true
      only_allow_merge_if_pipeline_succeeds        = true
      only_allow_merge_if_all_discussions_resolved = true
      remove_source_branch_after_merge             = true
    }
    security_policies = {
      name             = "security-policies"
      path             = "security-policies"
      description      = "Security policies, SAST/DAST configurations, and compliance rules"
      group_key        = "infrastructure"
      visibility_level = "private"
    }
    homeassistant = {
      name                             = "homeassistant"
      path                             = "homeassistant"
      description                      = "Home Assistant configuration, automations, packages, and integrations — synced to HAOS via Git Pull add-on"
      group_key                        = "infrastructure"
      visibility_level                 = "private"
      wiki_enabled                     = true
      remove_source_branch_after_merge = true
    }

    # --- Applications ---
    tavkit = {
      name                             = "tavkit"
      path                             = "tavkit"
      description                      = "DM's Essential Toolkit — multi-tool workspace with persistent tavs, kits, and AI generators for D&D 5e (Godot)"
      group_key                        = "applications"
      visibility_level                 = "private"
      wiki_enabled                     = true
      container_registry_enabled       = true
      remove_source_branch_after_merge = true
    }
    um_actually = {
      name                             = "um-actually"
      path                             = "um-actually"
      description                      = "Um, Actually — multiplayer trivia game (web app with Docker deployment)"
      group_key                        = "applications"
      visibility_level                 = "private"
      wiki_enabled                     = true
      container_registry_enabled       = true
      remove_source_branch_after_merge = true
    }
    pforte = {
      name                             = "pforte"
      path                             = "pforte"
      description                      = "Pforte — unified game library management across Steam, Xbox, and PlayStation"
      group_key                        = "applications"
      visibility_level                 = "private"
      wiki_enabled                     = true
      container_registry_enabled       = true
      remove_source_branch_after_merge = true
    }
    iron_cohort_game = {
      name                             = "iron-cohort-game"
      path                             = "iron-cohort-game"
      description                      = "Iron Cohort — tactical RPG game built in Godot Engine"
      group_key                        = "applications"
      visibility_level                 = "private"
      wiki_enabled                     = true
      remove_source_branch_after_merge = true
    }

    # --- Personal ---
    dnd_campaign = {
      name             = "dnd-campaign"
      path             = "dnd-campaign"
      description      = "D&D campaign notes, NPCs, world-building, and session logs"
      group_key        = "personal"
      visibility_level = "private"
      wiki_enabled     = true
    }
    iron_cohort = {
      name             = "iron-cohort"
      path             = "iron-cohort"
      description      = "The Iron Cohort — D&D 5e Eberron campaign public content"
      group_key        = "personal"
      visibility_level = "private"
      wiki_enabled     = true
    }
    stls = {
      name             = "stls"
      path             = "stls"
      description      = "3D printing STL files, designs, and print configurations"
      group_key        = "personal"
      visibility_level = "private"
      wiki_enabled     = true
    }

    # --- Documentation ---
    infrastructure_docs = {
      name             = "infrastructure-docs"
      path             = "infrastructure-docs"
      description      = "Infrastructure documentation, runbooks, and operational procedures"
      group_key        = "documentation"
      visibility_level = "private"
      wiki_enabled     = true
    }
    dnd_docs = {
      name             = "dnd-docs"
      path             = "dnd-docs"
      description      = "D&D documentation, world-building guides, and campaign resources"
      group_key        = "documentation"
      visibility_level = "private"
      wiki_enabled     = true
    }
  }

  # ---------------------------------------------------------------------------
  # Branch Protection — infrastructure projects get maintainer-level protection
  # ---------------------------------------------------------------------------
  branch_protections = {
    firblab           = { push = "maintainer", merge = "maintainer", allow_force_push = false }
    firblab_os        = { push = "maintainer", merge = "maintainer", allow_force_push = false }
    firblab_public    = { push = "maintainer", merge = "maintainer", allow_force_push = false }
    ci_templates      = { push = "maintainer", merge = "maintainer", allow_force_push = false }
    cybersecurity     = { push = "maintainer", merge = "maintainer", allow_force_push = false }
    security_policies = { push = "maintainer", merge = "maintainer", allow_force_push = false }
  }

  # ---------------------------------------------------------------------------
  # Standard Labels — applied to all projects
  # ---------------------------------------------------------------------------
  # Uses the setproduct pattern to create a cross-product of projects × labels.
  # ---------------------------------------------------------------------------
  common_labels = {
    "bug"                = "#D73A4A"
    "enhancement"        = "#A2EEEF"
    "documentation"      = "#0075CA"
    "security"           = "#E4E669"
    "tech-debt"          = "#D876E3"
    "priority::critical" = "#FF0000"
    "priority::high"     = "#FF9900"
    "priority::medium"   = "#FFCC00"
    "priority::low"      = "#00CC00"
    "type::terraform"    = "#7B42BC"
    "type::ansible"      = "#EE0000"
    "type::docker"       = "#2496ED"
    "type::kubernetes"   = "#326CE5"
    "status::wip"        = "#808080"
    "status::review"     = "#0066CC"
    "status::done"       = "#00AA00"
  }

  # Build cross-product: each project × each label
  project_labels = {
    for pair in setproduct(keys(local.projects), keys(local.common_labels)) :
    "${pair[0]}/${pair[1]}" => {
      project_key = pair[0]
      label_name  = pair[1]
      label_color = local.common_labels[pair[1]]
    }
  }
}

###############################################
# Groups
###############################################

resource "gitlab_group" "groups" {
  for_each = local.groups

  name                   = each.value.name
  path                   = each.value.path
  description            = each.value.description
  visibility_level       = each.value.visibility_level
  request_access_enabled = true
}

###############################################
# Projects
###############################################

resource "gitlab_project" "projects" {
  for_each = local.projects

  name             = each.value.name
  path             = each.value.path
  description      = each.value.description
  namespace_id     = gitlab_group.groups[each.value.group_key].id
  visibility_level = each.value.visibility_level

  # Initialize with a README and set main as default branch
  initialize_with_readme = lookup(each.value, "initialize_with_readme", true)
  default_branch         = "main"

  # CI/CD
  ci_config_path      = ".gitlab-ci.yml"
  auto_devops_enabled = false

  # Merge settings
  only_allow_merge_if_pipeline_succeeds            = lookup(each.value, "only_allow_merge_if_pipeline_succeeds", false)
  only_allow_merge_if_all_discussions_are_resolved = lookup(each.value, "only_allow_merge_if_all_discussions_resolved", false)
  remove_source_branch_after_merge                 = lookup(each.value, "remove_source_branch_after_merge", false)

  # Feature toggles
  issues_access_level         = "enabled"
  merge_requests_access_level = "enabled"
  wiki_access_level           = lookup(each.value, "wiki_enabled", false) ? "enabled" : "disabled"
  snippets_access_level       = "enabled"

  container_registry_access_level = lookup(each.value, "container_registry_enabled", false) ? "enabled" : "disabled"

  depends_on = [gitlab_group.groups]
}

###############################################
# Branch Protection
###############################################

resource "gitlab_branch_protection" "main" {
  for_each = local.branch_protections

  project            = gitlab_project.projects[each.key].id
  branch             = "main"
  push_access_level  = each.value.push
  merge_access_level = each.value.merge
  allow_force_push   = each.value.allow_force_push

  depends_on = [gitlab_project.projects]
}

###############################################
# Project Labels
###############################################

resource "gitlab_project_label" "labels" {
  for_each = local.project_labels

  project     = gitlab_project.projects[each.value.project_key].id
  name        = each.value.label_name
  color       = each.value.label_color
  description = "Managed by Terraform"

  depends_on = [gitlab_project.projects]
}

###############################################
# Instance-Level CI/CD Variables
###############################################
# Vault connection variables set at the instance level so ALL
# projects inherit them automatically. Pipelines use AppRole
# (role_id + secret_id) to authenticate and obtain a short-lived
# VAULT_TOKEN at job start.
#
# Pipeline usage:
#   export VAULT_TOKEN=$(vault write -field=token \
#     auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")
###############################################

resource "gitlab_instance_variable" "vault_addr" {
  key       = "VAULT_ADDR"
  value     = var.vault_addr
  protected = false
  masked    = false
}

resource "gitlab_instance_variable" "vault_cacert" {
  key           = "VAULT_CACERT"
  value         = local.vault_cacert_content
  protected     = false
  masked        = false
  variable_type = "file"
}

resource "gitlab_instance_variable" "vault_role_id" {
  count     = local.vault_approle_role_id != "" ? 1 : 0
  key       = "VAULT_ROLE_ID"
  value     = local.vault_approle_role_id
  protected = false
  masked    = true
}

resource "gitlab_instance_variable" "vault_secret_id" {
  count     = local.vault_approle_secret_id != "" ? 1 : 0
  key       = "VAULT_SECRET_ID"
  value     = local.vault_approle_secret_id
  protected = false
  masked    = true
}

###############################################
# Instance-Level CI/CD Variables — Terraform State Backup
###############################################
# S3 backup bucket + endpoint for post-apply tfstate uploads.
# The .terraform-apply template in ci-templates/terraform-ci.yml
# checks these vars and uploads tfstate after each successful apply.
###############################################

resource "gitlab_instance_variable" "tfstate_backup_bucket" {
  key       = "TFSTATE_BACKUP_BUCKET"
  value     = "firblab-tfstate-backups"
  protected = false
  masked    = false
}

resource "gitlab_instance_variable" "tfstate_s3_endpoint" {
  key       = "TFSTATE_S3_ENDPOINT"
  value     = "nbg1.your-objectstorage.com"
  protected = false
  masked    = false
}

###############################################
# Deploy Token: ArgoCD Read-Only Access
###############################################
# Creates a project-scoped deploy token on the firblab monorepo
# with read_repository scope. ArgoCD uses this to clone the repo
# for GitOps sync. The token is written to Vault so the
# argocd-bootstrap.yml Ansible playbook can retrieve it at runtime.
#
# Vault path: secret/services/gitlab
# Keys: argocd_deploy_username, argocd_deploy_token
###############################################

resource "gitlab_deploy_token" "argocd_readonly" {
  project  = gitlab_project.projects["firblab"].id
  name     = "argocd-readonly"
  username = "argocd-readonly"
  scopes   = ["read_repository"]

  depends_on = [gitlab_project.projects]
}

resource "vault_kv_secret_v2" "gitlab_argocd_token" {
  mount = "secret"
  name  = "services/gitlab"

  data_json = jsonencode({
    argocd_deploy_username = gitlab_deploy_token.argocd_readonly.username
    argocd_deploy_token    = gitlab_deploy_token.argocd_readonly.token
  })

  depends_on = [gitlab_deploy_token.argocd_readonly]
}

###############################################
# Project Access Token: ArgoCD Image Updater
###############################################
# Creates a project-scoped access token on the firblab monorepo with
# read_repository + write_repository scopes. ArgoCD Image Updater uses
# this for Git write-back — committing image tag updates directly to
# the repo so ArgoCD can sync them.
#
# Deploy tokens do NOT support write_repository — project access tokens
# are required for Git push operations.
#
# Separate from the ArgoCD read-only deploy token (least privilege).
# Vault path: secret/services/gitlab/image-updater
###############################################

resource "gitlab_project_access_token" "image_updater" {
  project      = gitlab_project.projects["firblab"].id
  name         = "argocd-image-updater"
  scopes       = ["read_repository", "write_repository"]
  access_level = "maintainer"
  expires_at   = "2027-02-15"

  depends_on = [gitlab_project.projects]
}

resource "vault_kv_secret_v2" "gitlab_image_updater" {
  mount = "secret"
  name  = "services/gitlab/image-updater"

  data_json = jsonencode({
    username = "argocd-image-updater"
    token    = gitlab_project_access_token.image_updater.token
  })

  depends_on = [gitlab_project_access_token.image_updater]
}

###############################################
# Pipeline Schedule: Renovate Bot
###############################################
# Weekly scheduled pipeline (Monday 5:00 AM ET) that triggers the
# renovate:update-check job via RENOVATE_RUN variable gate.
# Renovate scans for outdated Helm charts, Terraform providers,
# Ansible collections, and CI base images.
###############################################

resource "gitlab_pipeline_schedule" "renovate" {
  project     = gitlab_project.projects["firblab"].id
  description = "Renovate Bot — weekly dependency update scan"
  ref         = "refs/heads/main"
  cron        = "0 5 * * 1"
  active      = true

  depends_on = [gitlab_project.projects]
}

resource "gitlab_pipeline_schedule_variable" "renovate_run" {
  project              = gitlab_project.projects["firblab"].id
  pipeline_schedule_id = gitlab_pipeline_schedule.renovate.pipeline_schedule_id
  key                  = "RENOVATE_RUN"
  value                = "true"
}

###############################################
# Project Access Token: Wiki Push
###############################################
# Creates a project-scoped access token for CI to push rendered
# documentation and D2 diagrams to the GitLab project wiki.
# The wiki is a separate Git repo (firblab.wiki.git) but shares
# the same project-level access tokens.
#
# Token is stored in Vault and injected as a masked CI/CD variable.
# Vault path: secret/services/gitlab/wiki-push
###############################################

resource "gitlab_project_access_token" "wiki_push" {
  project      = gitlab_project.projects["firblab"].id
  name         = "ci-wiki-push"
  scopes       = ["read_repository", "write_repository"]
  access_level = "developer"
  expires_at   = "2027-02-15"

  depends_on = [gitlab_project.projects]
}

resource "vault_kv_secret_v2" "gitlab_wiki_push" {
  mount = "secret"
  name  = "services/gitlab/wiki-push"

  data_json = jsonencode({
    username = "ci-wiki-push"
    token    = gitlab_project_access_token.wiki_push.token
  })

  depends_on = [gitlab_project_access_token.wiki_push]
}

# Inject the wiki push token as a masked project-level CI/CD variable.
# Protected = true ensures it's only available on protected branches (main).
resource "gitlab_project_variable" "wiki_push_token" {
  project   = gitlab_project.projects["firblab"].id
  key       = "WIKI_PUSH_TOKEN"
  value     = gitlab_project_access_token.wiki_push.token
  protected = true
  masked    = true

  depends_on = [gitlab_project_access_token.wiki_push]
}

###############################################
# GitLab Agent for Kubernetes: firblab-rke2
###############################################
# Registers a cluster agent on the firblab monorepo so the RKE2
# cluster can connect back to GitLab for CI/CD pipeline access,
# GitOps sync, and workload observability.
#
# The agent runs in-cluster (deployed by ArgoCD) and maintains
# an outbound WebSocket tunnel to GitLab's KAS service — no
# inbound firewall rules needed on the cluster side.
#
# Agent config: .gitlab/agents/firblab-rke2/config.yaml
# Vault path:   secret/k8s/gitlab-agent (consumed by ESO)
# K8s namespace: gitlab-agent
###############################################

resource "gitlab_cluster_agent" "firblab_rke2" {
  project = gitlab_project.projects["firblab"].id
  name    = "firblab-rke2"

  depends_on = [gitlab_project.projects]
}

resource "gitlab_cluster_agent_token" "firblab_rke2" {
  project     = gitlab_project.projects["firblab"].id
  agent_id    = gitlab_cluster_agent.firblab_rke2.agent_id
  name        = "firblab-rke2-token"
  description = "Agent token for RKE2 cluster — managed by Terraform, consumed by ESO"

  depends_on = [gitlab_cluster_agent.firblab_rke2]
}

# Write the agent token to Vault at secret/k8s/gitlab-agent so the
# External Secrets Operator can sync it into the gitlab-agent namespace.
resource "vault_kv_secret_v2" "gitlab_agent_token" {
  mount = "secret"
  name  = "k8s/gitlab-agent"

  data_json = jsonencode({
    token = gitlab_cluster_agent_token.firblab_rke2.token
  })

  depends_on = [gitlab_cluster_agent_token.firblab_rke2]
}

###############################################
# Deploy Token: Home Assistant Git Pull
###############################################
# Read-only deploy token for the Home Assistant config repo.
# The HAOS Git Pull add-on uses HTTPS + token auth to pull
# configuration from GitLab into /config/ on the RPi.
#
# Vault path: secret/services/gitlab/homeassistant
# Keys: deploy_username, deploy_token, repo_url
###############################################

resource "gitlab_deploy_token" "homeassistant_gitpull" {
  project  = gitlab_project.projects["homeassistant"].id
  name     = "ha-gitpull-readonly"
  username = "ha-gitpull"
  scopes   = ["read_repository"]

  depends_on = [gitlab_project.projects]
}

resource "vault_kv_secret_v2" "gitlab_homeassistant" {
  mount = "secret"
  name  = "services/gitlab/homeassistant"

  data_json = jsonencode({
    deploy_username = gitlab_deploy_token.homeassistant_gitpull.username
    deploy_token    = gitlab_deploy_token.homeassistant_gitpull.token
    repo_url        = "https://${gitlab_deploy_token.homeassistant_gitpull.username}:${gitlab_deploy_token.homeassistant_gitpull.token}@gitlab.home.example-lab.org/infrastructure/homeassistant.git"
  })

  depends_on = [gitlab_deploy_token.homeassistant_gitpull]
}

###############################################
# Project Access Token: Home Assistant Config Push
###############################################
# Write-capable token for syncing HA config from the firblab repo's
# homeassistant/ directory to the infrastructure/homeassistant GitLab repo.
# Used by scripts/ha-config-sync.sh (reads token from Vault).
#
# Vault path: secret/services/gitlab/homeassistant-push
# Keys: username, token, repo_url
###############################################

resource "gitlab_project_access_token" "homeassistant_push" {
  project      = gitlab_project.projects["homeassistant"].id
  name         = "ha-config-push"
  scopes       = ["read_repository", "write_repository"]
  access_level = "maintainer"
  expires_at   = "2027-03-01"

  depends_on = [gitlab_project.projects]
}

resource "vault_kv_secret_v2" "gitlab_homeassistant_push" {
  mount = "secret"
  name  = "services/gitlab/homeassistant-push"

  data_json = jsonencode({
    username = "ha-config-push"
    token    = gitlab_project_access_token.homeassistant_push.token
    repo_url = "https://ha-config-push:${gitlab_project_access_token.homeassistant_push.token}@gitlab.home.example-lab.org/infrastructure/homeassistant.git"
  })

  depends_on = [gitlab_project_access_token.homeassistant_push]
}

###############################################
# Instance-Level Application Settings
###############################################
# Codifies sign-in, authentication, and security settings that would
# otherwise require manual configuration via Admin > Settings > General.
# OmniAuth provider config (Authentik OIDC) is in gitlab.rb (Ansible),
# but the instance-level toggles for how sign-in behaves are here.
#
# Reference: https://docs.gitlab.com/ee/api/settings.html
###############################################

###############################################
# GitHub Push Mirror — firblab-public
#
# Pushes firblab-public to a public GitHub repo (example-lab-blog/firblab).
# Vault path: secret/services/github
# Keys: mirror_token (fine-grained PAT, Contents RW), github_username
###############################################

data "vault_kv_secret_v2" "github" {
  mount = "secret"
  name  = "services/github"
}

resource "gitlab_project_mirror" "firblab_public_to_github" {
  project                 = gitlab_project.projects["firblab_public"].id
  url                     = "https://${data.vault_kv_secret_v2.github.data["github_username"]}:${data.vault_kv_secret_v2.github.data["mirror_token"]}@github.com/${data.vault_kv_secret_v2.github.data["github_username"]}/firblab.git"
  enabled                 = true
  keep_divergent_refs     = false
  only_protected_branches = false
}

###############################################
# GitHub Repository: example-lab-blog/firblab
###############################################
# Manages security and merge settings on the public GitHub
# mirror of firblab-public. The repo was created manually —
# imported into Terraform state via the import block below.
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

import {
  to = github_repository.firblab
  id = "firblab"
}

resource "github_repository" "firblab" {
  name        = "firblab"
  description = "FirbLab — production-grade homelab infrastructure platform. Terraform, Ansible, Packer, Vault, RKE2 Kubernetes, and ArgoCD GitOps."
  visibility  = "public"

  # Features
  has_issues      = true
  has_wiki        = false
  has_projects    = false
  has_downloads   = true
  has_discussions = false

  # Merge behavior
  delete_branch_on_merge = true

  # Commit signing
  web_commit_signoff_required = true

  # Dependabot vulnerability alerts
  vulnerability_alerts = true

  # Secret scanning + push protection (free for public repos)
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
# pushes ARE allowed — the GitLab CI mirror pushes directly
# to main (no PRs, no status checks in this workflow).
###############################################

resource "github_branch_protection" "firblab_main" {
  repository_id = github_repository.firblab.node_id
  pattern       = "main"

  # Block destructive operations
  allows_force_pushes = false
  allows_deletions    = false

  # Do NOT enforce for admins — mirror token needs to push
  enforce_admins = false
}

###############################################
# Project Access Token: CI Sanitize Push
###############################################
# Write-capable token for the CI sanitize job to push sanitized
# content from firblab → firblab-public. The token is stored as a
# masked CI/CD variable on the firblab project (source repo).
#
# Vault path: secret/services/gitlab/sanitize-push
###############################################

resource "gitlab_project_access_token" "sanitize_push" {
  project      = gitlab_project.projects["firblab_public"].id
  name         = "ci-sanitize-push"
  scopes       = ["read_repository", "write_repository"]
  access_level = "maintainer"
  expires_at   = "2027-03-01"

  depends_on = [gitlab_project.projects]
}

resource "vault_kv_secret_v2" "gitlab_sanitize_push" {
  mount = "secret"
  name  = "services/gitlab/sanitize-push"

  data_json = jsonencode({
    username = "ci-sanitize-push"
    token    = gitlab_project_access_token.sanitize_push.token
  })

  depends_on = [gitlab_project_access_token.sanitize_push]
}

# Inject the sanitize push token as a masked project-level CI/CD variable
# on the firblab project (where the CI job runs).
resource "gitlab_project_variable" "sanitize_push_token" {
  project   = gitlab_project.projects["firblab"].id
  key       = "SANITIZE_PUSH_TOKEN"
  value     = gitlab_project_access_token.sanitize_push.token
  protected = true
  masked    = true

  depends_on = [gitlab_project_access_token.sanitize_push]
}

resource "gitlab_application_settings" "this" {
  # --- Sign-in & Registration ---
  signup_enabled                           = false # No open registration — users via OIDC or admin-created
  password_authentication_enabled_for_web  = true  # Allow local login (root, service accounts, emergency access)
  password_authentication_enabled_for_git  = true  # Deploy tokens + PATs use password auth for Git over HTTPS
  require_admin_approval_after_user_signup = true  # Safety net if signup is ever re-enabled

  # --- OAuth / Authentik SSO ---
  # Empty list = all configured OAuth sources are enabled for sign-in.
  # To disable a source, add its name here (e.g., ["openid_connect"]).
  disabled_oauth_sign_in_sources = []

  # --- Security Hardening ---
  after_sign_out_path = "https://auth.home.example-lab.org/application/o/gitlab/end-session/"
}
