# =============================================================================
# Layer 02-vault-config: Vault Configuration
# Rover CI visualization: https://github.com/im2nguyen/rover
# =============================================================================
# Manages Vault's internal configuration: secrets engines, auth methods,
# policies, audit logging, and seed data. Requires a running, initialized
# Vault cluster (deployed by Layer 02-vault-infra + Ansible).
#
# This layer is the source of truth for:
#   - KV v2 secrets engine at secret/
#   - PKI secrets engines (pki/ root CA, pki_int/ intermediate CA)
#   - Vault policies (admin, terraform, packer, gitlab-ci, k8s-external-secrets, cert-manager, backup)
#   - Auth backends (AppRole for GitLab CI, Kubernetes for k3s workloads)
#   - Audit file logging
#   - Admin token (replaces root token for day-to-day use)
#   - Seed secrets (Proxmox, UniFi, Hetzner, Cloudflare → secret/infra/)
#   - Seed secrets (GitLab → secret/services/gitlab/)
#
# Secret taxonomy (KV v2 at secret/):
#   infra/       Infrastructure device credentials (Proxmox, UniFi, Hetzner, etc.)
#   compute/     Per-host secrets (SSH keys, admin passwords)
#   services/    Application-level secrets (GitLab, Ghost, Plex, etc.)
#   k8s/         Kubernetes-specific secrets (synced by External Secrets Operator)
#   backup/      Backup & DR credentials (age key, S3 creds)
#   tls/         Non-PKI static certificates (bootstrap certs)
#   personal/    Personal credentials (licenses, DNS registrar)
#
# Prerequisites:
#   - Vault cluster initialized and unsealed
#   - Valid Vault token with root or admin privileges
#
# Usage:
#   cd terraform/layers/02-vault-config
#   terraform init
#   terraform apply -var-file=../../environments/vault-config.tfvars
# =============================================================================

# ---------------------------------------------------------
# KV v2 Secrets Engine
# ---------------------------------------------------------

resource "vault_mount" "kv" {
  path        = "secret"
  type        = "kv-v2"
  description = "Key-Value secrets engine for infrastructure credentials"
}

# ---------------------------------------------------------
# PKI Secrets Engine — Root CA
# ---------------------------------------------------------
# Root CA with 10-year TTL. Only used to sign the intermediate.
# In production, the root would be offline — but for a homelab
# Vault-managed root is acceptable.
#
# Adapted from homelab/terraform/vault/pki.tf (proven pattern).
# ---------------------------------------------------------

resource "vault_mount" "pki" {
  path                  = "pki"
  type                  = "pki"
  description           = "Root PKI CA — signs intermediate only"
  max_lease_ttl_seconds = 315360000 # 10 years
}

resource "vault_pki_secret_backend_config_urls" "root" {
  backend                 = vault_mount.pki.path
  issuing_certificates    = ["${var.vault_addr}/v1/pki/ca"]
  crl_distribution_points = ["${var.vault_addr}/v1/pki/crl"]
}

resource "vault_pki_secret_backend_root_cert" "root" {
  backend     = vault_mount.pki.path
  type        = "internal"
  common_name = "firblab Root CA"
  ttl         = "87600h" # 10 years
  key_bits    = 4096
}

# ---------------------------------------------------------
# PKI Secrets Engine — Intermediate CA
# ---------------------------------------------------------
# Short-lived certs (24h default, 90d max) for all internal
# services. cert-manager and Terraform issue certs via the
# "firblab" role on this intermediate.
#
# Policies already grant access:
#   admin     → pki/*, pki_int/* (full CRUD)
#   terraform → pki_int/issue/firblab (issue only)
#   gitlab_ci → pki_int/issue/firblab (issue only)
# ---------------------------------------------------------

resource "vault_mount" "pki_int" {
  path                  = "pki_int"
  type                  = "pki"
  description           = "Intermediate PKI CA — issues service certs"
  max_lease_ttl_seconds = 157788000 # 5 years
}

resource "vault_pki_secret_backend_intermediate_cert_request" "intermediate" {
  backend     = vault_mount.pki_int.path
  type        = "internal"
  common_name = "firblab Intermediate CA"
  key_bits    = 4096
}

resource "vault_pki_secret_backend_root_sign_intermediate" "root" {
  backend     = vault_mount.pki.path
  csr         = vault_pki_secret_backend_intermediate_cert_request.intermediate.csr
  common_name = "firblab Intermediate CA"
  ttl         = "43800h" # 5 years
}

resource "vault_pki_secret_backend_intermediate_set_signed" "intermediate" {
  backend     = vault_mount.pki_int.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.root.certificate
}

resource "vault_pki_secret_backend_config_urls" "intermediate" {
  backend                 = vault_mount.pki_int.path
  issuing_certificates    = ["${var.vault_addr}/v1/pki_int/ca"]
  crl_distribution_points = ["${var.vault_addr}/v1/pki_int/crl"]
}

# ---------------------------------------------------------
# PKI Roles — Certificate Issuance
# ---------------------------------------------------------
# The "firblab" role is the primary issuance endpoint for all
# internal TLS certificates. Used by:
#   - cert-manager (k8s ClusterIssuer → pki_int/sign/firblab)
#   - Terraform (pki_int/issue/firblab for infra certs)
#   - GitLab CI (pki_int/issue/firblab for deployed services)
# ---------------------------------------------------------

resource "vault_pki_secret_backend_role" "firblab" {
  backend            = vault_mount.pki_int.path
  name               = "firblab"
  ttl                = "86400"   # 24 hours default
  max_ttl            = "7776000" # 90 days max
  generate_lease     = true
  allowed_domains    = ["example-lab.local", "localhost"]
  allow_subdomains   = true
  allow_ip_sans      = true
  allow_glob_domains = true
  server_flag        = true
  client_flag        = true
}

# ---------------------------------------------------------
# Audit Logging
# ---------------------------------------------------------

resource "vault_audit" "file" {
  type = "file"

  options = {
    file_path = "/var/log/vault/audit.log"
  }
}

# ---------------------------------------------------------
# Policies
# ---------------------------------------------------------

resource "vault_policy" "admin" {
  name = "admin"

  policy = <<-EOT
    # Full access to KV secrets (all taxonomy paths)
    path "secret/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # Manage auth methods and policies
    path "auth/*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
    path "sys/auth/*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
    path "sys/policies/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # PKI operations
    path "pki/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
    path "pki_int/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # Vault status and health
    path "sys/health" {
      capabilities = ["read"]
    }
    path "sys/leader" {
      capabilities = ["read"]
    }

    # Raft cluster management
    path "sys/storage/raft/*" {
      capabilities = ["read", "list"]
    }

    # Audit device management
    path "sys/audit*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }

    # Mount management (list + CRUD)
    path "sys/mounts" {
      capabilities = ["read", "list"]
    }
    path "sys/mounts/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # Token management (self and children)
    path "auth/token/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
  EOT
}

resource "vault_policy" "terraform" {
  name = "terraform"

  policy = <<-EOT
    # Read infrastructure device credentials
    path "secret/data/infra/*" {
      capabilities = ["read", "list"]
    }
    path "secret/metadata/infra/*" {
      capabilities = ["list"]
    }

    # Read per-host compute secrets (SSH keys for provisioning)
    path "secret/data/compute/*" {
      capabilities = ["read", "list"]
    }
    path "secret/metadata/compute/*" {
      capabilities = ["list"]
    }

    # Read service credentials (GitLab PAT for Layer 03-gitlab-config)
    path "secret/data/services/*" {
      capabilities = ["read", "list"]
    }
    path "secret/metadata/services/*" {
      capabilities = ["list"]
    }

    # List top-level metadata for discovery
    path "secret/metadata" {
      capabilities = ["list"]
    }

    # Issue TLS certificates for infrastructure
    path "pki_int/issue/firblab" {
      capabilities = ["create", "update"]
    }
  EOT
}

resource "vault_policy" "packer" {
  name = "packer"

  policy = <<-EOT
    # Read Proxmox API credentials for Packer template builds
    path "secret/data/infra/proxmox/*" {
      capabilities = ["read"]
    }
    path "secret/metadata/infra/proxmox/*" {
      capabilities = ["list"]
    }
  EOT
}

resource "vault_policy" "gitlab_ci" {
  name = "gitlab-ci"

  policy = <<-EOT
    # Read infrastructure credentials for CI/CD provisioning
    path "secret/data/infra/*" {
      capabilities = ["read", "list"]
    }
    path "secret/metadata/infra/*" {
      capabilities = ["list"]
    }

    # Read service secrets for deployment
    path "secret/data/services/*" {
      capabilities = ["read", "list"]
    }
    path "secret/metadata/services/*" {
      capabilities = ["list"]
    }

    # Read k8s secrets for cluster deployments
    path "secret/data/k8s/*" {
      capabilities = ["read", "list"]
    }
    path "secret/metadata/k8s/*" {
      capabilities = ["list"]
    }

    # Read compute secrets (SSH keys) for CI/CD Ansible deployments
    path "secret/data/compute/*" {
      capabilities = ["read"]
    }
    path "secret/metadata/compute/*" {
      capabilities = ["list"]
    }

    # Read backup secrets (age key, restic creds) for deploy playbooks
    path "secret/data/backup/*" {
      capabilities = ["read"]
    }
    path "secret/metadata/backup/*" {
      capabilities = ["list"]
    }

    # List top-level metadata for discovery
    path "secret/metadata" {
      capabilities = ["list"]
    }

    # Issue TLS certificates for deployed services
    path "pki_int/issue/firblab" {
      capabilities = ["create", "update"]
    }

    # Create child tokens (required by the Terraform Vault provider)
    path "auth/token/create" {
      capabilities = ["update"]
    }
  EOT
}

resource "vault_policy" "k8s_external_secrets" {
  name = "k8s-external-secrets"

  policy = <<-EOT
    # Read k8s-specific secrets (synced by External Secrets Operator)
    path "secret/data/k8s/*" {
      capabilities = ["read", "list"]
    }
    path "secret/metadata/k8s/*" {
      capabilities = ["list"]
    }

    # Read service secrets that k8s workloads consume
    path "secret/data/services/*" {
      capabilities = ["read", "list"]
    }
    path "secret/metadata/services/*" {
      capabilities = ["list"]
    }

    # Cloudflare API token — consumed by cert-manager for DNS-01 challenges
    path "secret/data/infra/cloudflare" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_policy" "cert_manager" {
  name = "cert-manager"

  policy = <<-EOT
    # Issue certificates via intermediate CA
    path "pki_int/issue/firblab" {
      capabilities = ["create", "update"]
    }
    path "pki_int/sign/firblab" {
      capabilities = ["create", "update"]
    }
  EOT
}

resource "vault_policy" "backup" {
  name = "backup"

  policy = <<-EOT
    # Read backup credentials (age key, S3 creds)
    path "secret/data/backup/*" {
      capabilities = ["read", "list"]
    }
    path "secret/metadata/backup/*" {
      capabilities = ["list"]
    }

    # Raft snapshot for backup operations
    path "sys/storage/raft/snapshot" {
      capabilities = ["read"]
    }
  EOT
}

# Alias for the backup policy — the vault-backup-setup.yml playbook
# creates tokens with -policy=vault-backup (descriptive name for cron tokens).
resource "vault_policy" "vault_backup" {
  name   = "vault-backup"
  policy = vault_policy.backup.policy
}

# ---------------------------------------------------------
# AppRole Auth Backend (for GitLab CI/CD)
# ---------------------------------------------------------
# Enables AppRole authentication method. GitLab CI pipelines
# use role_id + secret_id (stored as instance-level CI/CD
# variables in GitLab) to obtain short-lived tokens with the
# gitlab-ci policy attached.
#
# Flow: pipeline starts → exchanges role_id+secret_id for
# a 1-hour VAULT_TOKEN → uses token for terraform/ansible →
# token expires automatically.
# ---------------------------------------------------------

resource "vault_auth_backend" "approle" {
  type = "approle"
}

resource "vault_approle_auth_backend_role" "gitlab_ci" {
  backend        = vault_auth_backend.approle.path
  role_name      = "gitlab-ci"
  token_policies = ["gitlab-ci"]
  token_ttl      = 3600  # 1 hour
  token_max_ttl  = 14400 # 4 hours
}

# Extract role_id for output (consumed by Layer 03-gitlab-config)
data "vault_approle_auth_backend_role_id" "gitlab_ci" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.gitlab_ci.role_name
}

# Generate a secret_id for GitLab CI (consumed by Layer 03-gitlab-config)
resource "vault_approle_auth_backend_role_secret_id" "gitlab_ci" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.gitlab_ci.role_name
}

# Write AppRole credentials to Vault KV so Layer 03-gitlab-config can
# read them automatically via data source — no manual -var flags needed.
# Path: secret/services/gitlab/approle (alongside services/gitlab/admin).
resource "vault_kv_secret_v2" "gitlab_ci_approle" {
  mount = vault_mount.kv.path
  name  = "services/gitlab/approle"
  data_json = jsonencode({
    role_id   = data.vault_approle_auth_backend_role_id.gitlab_ci.role_id
    secret_id = vault_approle_auth_backend_role_secret_id.gitlab_ci.secret_id
  })
}

# ---------------------------------------------------------
# Kubernetes Auth Backend (for RKE2 workloads)
# ---------------------------------------------------------
# Enables the Kubernetes auth method. Roles are created here
# so policies are ready before the cluster exists.
#
# The backend configuration (k8s API host, CA cert, token
# reviewer JWT) is set by the Ansible playbook AFTER the
# RKE2 cluster deploys:
#   ansible-playbook ansible/playbooks/vault-k8s-auth.yml
#
# This configures:
#   kubernetes_host = "https://10.0.20.40:6443"
#   kubernetes_ca_cert = <from RKE2 server-ca.crt>
#   token_reviewer_jwt = <from vault-auth SA token>
# ---------------------------------------------------------

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

# Role for External Secrets Operator — syncs Vault secrets → k8s
resource "vault_kubernetes_auth_backend_role" "external_secrets" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "external-secrets"
  bound_service_account_names      = ["external-secrets"]
  bound_service_account_namespaces = ["external-secrets"]
  token_policies                   = ["k8s-external-secrets"]
  token_ttl                        = 3600 # 1 hour
}

# Role for cert-manager — issues TLS certificates via Vault PKI
resource "vault_kubernetes_auth_backend_role" "cert_manager" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "cert-manager"
  bound_service_account_names      = ["cert-manager"]
  bound_service_account_namespaces = ["cert-manager"]
  token_policies                   = ["cert-manager"]
  token_ttl                        = 3600 # 1 hour
}

# ---------------------------------------------------------
# K3s Kubernetes Auth Backend (auth/kubernetes-k3s/)
# ---------------------------------------------------------
# Separate auth backend for the K3s RPi5 cluster. The RKE2
# backend above is at auth/kubernetes/. K3s uses a different
# API endpoint (https://10.0.20.60:6443) and CA cert.
#
# Backend configuration (k8s API host, CA cert, token
# reviewer JWT) is set by the Ansible playbook:
#   ansible-playbook ansible/playbooks/k3s-vault-k8s-auth.yml
# ---------------------------------------------------------

resource "vault_auth_backend" "kubernetes_k3s" {
  type        = "kubernetes"
  path        = "kubernetes-k3s"
  description = "K3s RPi5 cluster auth (Services VLAN 20)"
}

resource "vault_kubernetes_auth_backend_role" "k3s_external_secrets" {
  backend                          = vault_auth_backend.kubernetes_k3s.path
  role_name                        = "external-secrets"
  bound_service_account_names      = ["external-secrets"]
  bound_service_account_namespaces = ["external-secrets"]
  token_policies                   = ["k8s-external-secrets"]
  token_ttl                        = 3600 # 1 hour
}

resource "vault_kubernetes_auth_backend_role" "k3s_cert_manager" {
  backend                          = vault_auth_backend.kubernetes_k3s.path
  role_name                        = "cert-manager"
  bound_service_account_names      = ["cert-manager"]
  bound_service_account_namespaces = ["cert-manager"]
  token_policies                   = ["cert-manager"]
  token_ttl                        = 3600 # 1 hour
}

# ---------------------------------------------------------
# Kubernetes Service Secrets (secret/k8s/*)
# ---------------------------------------------------------
# Auto-generated credentials for K8s workloads. External
# Secrets Operator syncs these to K8s Secrets. Operators
# retrieve passwords via: vault kv get secret/k8s/<service>
#
# Policy: k8s-external-secrets has read access to secret/k8s/*
# ---------------------------------------------------------

# Grafana admin credentials
resource "random_password" "grafana_admin" {
  length  = 32
  special = false # Avoid special chars that may break Grafana env vars
}

resource "vault_kv_secret_v2" "grafana" {
  mount = vault_mount.kv.path
  name  = "k8s/grafana"
  data_json = jsonencode({
    username = "admin"
    password = random_password.grafana_admin.result
  })
}

# Longhorn UI basic-auth credentials
resource "random_password" "longhorn_admin" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "longhorn" {
  mount = vault_mount.kv.path
  name  = "k8s/longhorn"
  data_json = jsonencode({
    username = "admin"
    password = random_password.longhorn_admin.result
  })
}

# Roundcube webmail credentials (DES key + PostgreSQL)
resource "random_password" "roundcube_des_key" {
  length  = 24
  special = false # Roundcube internal session/encryption key — 24 chars required
}

resource "random_password" "roundcube_db" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "roundcube" {
  mount = vault_mount.kv.path
  name  = "services/roundcube"
  data_json = jsonencode({
    des_key     = random_password.roundcube_des_key.result
    db_username = "roundcube"
    db_password = random_password.roundcube_db.result
  })
}

# ---------------------------------------------------------
# Admin Token
# ---------------------------------------------------------
# Long-lived, renewable token for day-to-day admin operations.
# Replaces the root token — root should be revoked after this
# token is created and verified.
# ---------------------------------------------------------

resource "vault_token" "admin" {
  display_name = "firblab-admin"
  policies     = ["admin"]
  ttl          = var.admin_token_ttl
  renewable    = true
  no_parent    = true

  metadata = {
    purpose    = "Day-to-day admin operations"
    created_by = "terraform/layers/02-vault-config"
  }
}

# ---------------------------------------------------------
# Seed Secrets: Proxmox API Credentials
# ---------------------------------------------------------
# Seeded at secret/infra/proxmox/<node-name> following the
# taxonomy: infra/ = infrastructure device credentials.
#
# After Vault is operational, other Terraform layers read these
# via data "vault_kv_secret_v2" in their providers.tf, and
# Packer reads them via the packer-build.sh script.
# ---------------------------------------------------------

resource "vault_kv_secret_v2" "proxmox" {
  for_each = var.proxmox_nodes

  mount = vault_mount.kv.path
  name  = "infra/proxmox/${each.key}"

  data_json = jsonencode({
    url          = each.value.api_url
    token_id     = each.value.token_id
    token_secret = each.value.token_secret
  })
}

# ---------------------------------------------------------
# Seed Secrets: UniFi Controller Credentials
# ---------------------------------------------------------
# Seeded at secret/infra/unifi — consumed by Layer 00-network.
# ---------------------------------------------------------

resource "vault_kv_secret_v2" "unifi" {
  count = var.unifi_credentials != null ? 1 : 0

  mount = vault_mount.kv.path
  name  = "infra/unifi"

  data_json = jsonencode({
    api_url                = var.unifi_credentials.api_url
    api_key                = var.unifi_credentials.api_key
    default_lan_network_id = var.unifi_credentials.default_lan_network_id
    switch_closet_mac      = var.unifi_credentials.switch_closet_mac
    switch_minilab_mac     = var.unifi_credentials.switch_minilab_mac
    switch_rackmate_mac    = var.unifi_credentials.switch_rackmate_mac
    switch_pro_xg8_mac     = var.unifi_credentials.switch_pro_xg8_mac
    iot_wlan_passphrase    = var.unifi_credentials.iot_wlan_passphrase
  })
}

# ---------------------------------------------------------
# Seed Secrets: Hetzner Cloud Credentials
# ---------------------------------------------------------
# Seeded at secret/infra/hetzner — consumed by Layer 06-hetzner.
# ---------------------------------------------------------

resource "vault_kv_secret_v2" "hetzner" {
  count = var.hetzner_credentials != null ? 1 : 0

  mount = vault_mount.kv.path
  name  = "infra/hetzner"

  data_json = jsonencode({
    hcloud_token   = var.hetzner_credentials.hcloud_token
    ssh_public_key = var.hetzner_credentials.ssh_public_key
    mgmt_cidr      = var.hetzner_credentials.mgmt_cidr
    home_cidr      = var.hetzner_credentials.home_cidr
    domain_name    = var.hetzner_credentials.domain_name
    s3_access_key  = var.hetzner_credentials.s3_access_key
    s3_secret_key  = var.hetzner_credentials.s3_secret_key
    s3_endpoint    = var.hetzner_credentials.s3_endpoint
  })
}

# ---------------------------------------------------------
# Seed Secrets: Cloudflare Credentials
# ---------------------------------------------------------
# Seeded at secret/infra/cloudflare — consumed by Layer 06-hetzner.
# ---------------------------------------------------------

resource "vault_kv_secret_v2" "cloudflare" {
  count = var.cloudflare_credentials != null ? 1 : 0

  mount = vault_mount.kv.path
  name  = "infra/cloudflare"

  data_json = jsonencode({
    api_token           = var.cloudflare_credentials.api_token
    migadu_verification = var.cloudflare_credentials.migadu_verification
  })
}

# ---------------------------------------------------------
# Seed Secrets: GitLab Admin Credentials
# ---------------------------------------------------------
# Seeded at secret/services/gitlab/admin — consumed by
# Layer 03-gitlab-config (GitLab provider authentication).
#
# The PAT is generated by scripts/generate-gitlab-token.sh
# and stored here for Terraform to consume. This closes the
# bootstrap loop: GitLab runs → PAT generated → stored in
# Vault → Terraform reads it to manage GitLab resources.
# ---------------------------------------------------------

resource "vault_kv_secret_v2" "gitlab" {
  count = var.gitlab_credentials != null ? 1 : 0

  mount = vault_mount.kv.path
  name  = "services/gitlab/admin"

  data_json = jsonencode({
    personal_access_token = var.gitlab_credentials.personal_access_token
    root_password         = var.gitlab_credentials.root_password
  })
}

# ---------------------------------------------------------
# Seed Secrets: GitLab Runner Authentication Token
# ---------------------------------------------------------
# Seeded at secret/services/gitlab/runner — consumed by
# the gitlab-runner-deploy.yml Ansible playbook via the
# community.hashi_vault lookup plugin.
#
# The glrt- token is generated in the GitLab UI when
# creating a new instance runner (Admin > CI/CD > Runners).
# ---------------------------------------------------------

resource "vault_kv_secret_v2" "gitlab_runner" {
  count = var.gitlab_runner_token != null ? 1 : 0

  mount = vault_mount.kv.path
  name  = "services/gitlab/runner"

  data_json = jsonencode({
    token = var.gitlab_runner_token
  })
}

# ---------------------------------------------------------
# Authentik SSO/IDP Credentials (secret/services/authentik)
# ---------------------------------------------------------
# Auto-generated secrets for Authentik deployment. Read by the
# authentik-deploy.yml Ansible playbook via the vault CLI.
#
# Fields:
#   secret_key          — Cookie signing key (never change after first install)
#   postgresql_password — Bundled PostgreSQL auth
#   bootstrap_password  — Initial akadmin user password (first startup only)
#   bootstrap_token     — Initial API token (first startup only)
# ---------------------------------------------------------

resource "random_password" "authentik_secret_key" {
  length  = 64
  special = false
}

resource "random_password" "authentik_db" {
  length  = 32
  special = false
}

resource "random_password" "authentik_bootstrap" {
  length  = 32
  special = false
}

resource "random_id" "authentik_bootstrap_token" {
  byte_length = 32
}

resource "vault_kv_secret_v2" "authentik" {
  mount = vault_mount.kv.path
  name  = "services/authentik"
  data_json = jsonencode({
    secret_key          = random_password.authentik_secret_key.result
    postgresql_password = random_password.authentik_db.result
    bootstrap_password  = random_password.authentik_bootstrap.result
    bootstrap_token     = random_id.authentik_bootstrap_token.hex
  })
}

# ---------------------------------------------------------
# PatchMon — Linux Patch Monitoring Platform
# ---------------------------------------------------------
# Docker Compose stack: PostgreSQL 17 + Redis 7 + backend + frontend.
# Secrets pre-seeded here so Ansible can read them from Vault at deploy.
#
# Fields:
#   postgres_password — PostgreSQL auth for patchmon_user
#   redis_password    — Redis requirepass
#   jwt_secret        — JWT signing key for API auth
# ---------------------------------------------------------

resource "random_password" "patchmon_db" {
  length  = 32
  special = false
}

resource "random_password" "patchmon_redis" {
  length  = 32
  special = false
}

resource "random_password" "patchmon_jwt" {
  length  = 64
  special = false
}

resource "vault_kv_secret_v2" "patchmon" {
  mount = vault_mount.kv.path
  name  = "services/patchmon"
  data_json = jsonencode({
    postgres_password = random_password.patchmon_db.result
    redis_password    = random_password.patchmon_redis.result
    jwt_secret        = random_password.patchmon_jwt.result
  })
}

# ---------------------------------------------------------
# Vaultwarden — Self-hosted Password Manager
# ---------------------------------------------------------
# Bitwarden-compatible password vault serving as a backup
# mirror for 1Password. Single container, SQLite backend.
#
# Fields:
#   admin_token — Vaultwarden admin panel login token
# ---------------------------------------------------------

resource "random_password" "vaultwarden_admin_token" {
  length  = 48
  special = false
}

# Master passwords for Vaultwarden user accounts.
# Users are invited via the admin API (playbook post_task), then complete
# registration in the web vault using these passwords. Store in Vault so
# they're retrievable if needed, but users should change them after first login.
resource "random_password" "vaultwarden_admin_master" {
  length  = 32
  special = true
}

resource "random_password" "vaultwarden_user_master" {
  length  = 32
  special = true
}

resource "vault_kv_secret_v2" "vaultwarden" {
  mount = vault_mount.kv.path
  name  = "services/vaultwarden"
  data_json = jsonencode({
    admin_token          = random_password.vaultwarden_admin_token.result
    admin_email         = "admin@example-lab.org"
    admin_master_password = random_password.vaultwarden_admin_master.result
    user_email         = "user@example-lab.org"
    user_master_password = random_password.vaultwarden_user_master.result
  })
}

# ---------------------------------------------------------
# Open WebUI — AI Chat Interface
# ---------------------------------------------------------
# Open WebUI creates its admin account on first sign-up or first
# OIDC login. No env-var admin seeding — the first user becomes admin.
# We pre-seed a secret_key for JWT signing (WEBUI_SECRET_KEY) so it
# survives container recreation.
# ---------------------------------------------------------

resource "random_password" "openwebui_secret_key" {
  length  = 48
  special = false
}

resource "vault_kv_secret_v2" "openwebui" {
  mount = vault_mount.kv.path
  name  = "services/openwebui"
  data_json = jsonencode({
    secret_key = random_password.openwebui_secret_key.result
  })
}

# ---------------------------------------------------------
# n8n — Workflow Automation
# ---------------------------------------------------------
# n8n uses a file-based encryption key for credentials stored
# in its SQLite/Postgres DB. Without a stable key, credentials
# become unreadable after container recreation.
# ---------------------------------------------------------

resource "random_password" "n8n_encryption_key" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "n8n" {
  mount = vault_mount.kv.path
  name  = "services/n8n"
  data_json = jsonencode({
    encryption_key = random_password.n8n_encryption_key.result
  })
}

# ---------------------------------------------------------
# Archive Appliance — Prepper Knowledge Base (ZimaBlade 7700)
# ---------------------------------------------------------
# Dedicated bare-metal archive appliance running Kiwix, ArchiveBox,
# BookStack, Stirling PDF, Wallabag, and FileBrowser.
#
# Fields:
#   bookstack_app_key          — Laravel APP_KEY (base64-encoded 32 bytes)
#   bookstack_db_password      — BookStack MariaDB user password
#   bookstack_db_root_password — BookStack MariaDB root password
#   wallabag_db_password       — Wallabag MariaDB user password
#   wallabag_db_root_password  — Wallabag MariaDB root password
# ---------------------------------------------------------

# BookStack APP_KEY — Laravel requires "base64:<32-random-bytes-b64>"
# random_id produces cryptographically random bytes with base64 output.
resource "random_id" "archive_bookstack_app_key" {
  byte_length = 32
}

resource "random_password" "archive_bookstack_db" {
  length  = 32
  special = false
}

resource "random_password" "archive_bookstack_db_root" {
  length  = 32
  special = false
}

resource "random_password" "archive_wallabag_db" {
  length  = 32
  special = false
}

resource "random_password" "archive_wallabag_db_root" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "archive" {
  mount = vault_mount.kv.path
  name  = "services/archive"
  data_json = jsonencode({
    bookstack_app_key          = "base64:${random_id.archive_bookstack_app_key.b64_std}"
    bookstack_db_password      = random_password.archive_bookstack_db.result
    bookstack_db_root_password = random_password.archive_bookstack_db_root.result
    wallabag_db_password       = random_password.archive_wallabag_db.result
    wallabag_db_root_password  = random_password.archive_wallabag_db_root.result
  })
}

# ---------------------------------------------------------
# GitLab CE on Kubernetes (Testing Instance)
# ---------------------------------------------------------
# Auto-generated root password for the GitLab CE Helm chart
# deployed on the RKE2 cluster. External Secrets Operator syncs
# this to the gitlab namespace as the initial-root-password secret.
#
# Path: secret/k8s/gitlab
# ---------------------------------------------------------

resource "random_password" "gitlab_k8s_root" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "gitlab_k8s" {
  mount = vault_mount.kv.path
  name  = "k8s/gitlab"
  data_json = jsonencode({
    root_password = random_password.gitlab_k8s_root.result
  })
}

# ---------------------------------------------------------
# Wazuh SIEM on Kubernetes
# ---------------------------------------------------------
# Credentials for Wazuh Manager and agent enrollment.
# External Secrets Operator syncs these to the wazuh namespace.
#
# Fields:
#   api_password              — Wazuh Manager REST API admin password
#   agent_enrollment_password — authd password for agent registration (port 1515)
#
# Path: secret/k8s/wazuh
# ---------------------------------------------------------

resource "random_password" "wazuh_api" {
  length  = 32
  special = false
}

resource "random_password" "wazuh_enrollment" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "wazuh" {
  mount = vault_mount.kv.path
  name  = "k8s/wazuh"
  data_json = jsonencode({
    api_password              = random_password.wazuh_api.result
    agent_enrollment_password = random_password.wazuh_enrollment.result
  })
}

# ---------------------------------------------------------
# Home Assistant — HAOS RPi5 (IoT VLAN 60)
# ---------------------------------------------------------
# Long-lived access token for external integrations:
#   - Prometheus → HA REST API scraping
#   - n8n / automation webhooks
#
# Note: This is a placeholder. After HAOS first boot, generate
# the actual long-lived token via HA UI (Profile → Long-Lived
# Access Tokens) and update this secret manually in Vault:
#   vault kv put secret/services/homeassistant api_token=<token>
# ---------------------------------------------------------

resource "vault_kv_secret_v2" "homeassistant" {
  mount = vault_mount.kv.path
  name  = "services/homeassistant"
  data_json = jsonencode({
    api_token = "placeholder-generate-from-ha-ui"
    host      = "10.0.60.10"
    port      = "8123"
  })
}
