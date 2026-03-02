# =============================================================================
# Layer 06: Hetzner - Provider Configuration
# =============================================================================
# Deploys the firblab external gateway on Hetzner Cloud with Cloudflare DNS.
# The gateway runs Docker, Traefik, WireGuard, and public-facing services.
#
# Dual-mode authentication: reads Hetzner and Cloudflare credentials from
# Vault by default. Falls back to direct variables for bootstrap.
#
# Normal usage (Vault is running — zero -var flags needed):
#   terraform apply
#
# Bootstrap (no Vault yet):
#   terraform apply -var use_vault=false \
#     -var hcloud_token="..." -var cloudflare_api_token="..." \
#     -var ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" \
#     -var mgmt_cidr="10.8.0.0/24" -var domain_name="example-lab.org"
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.45"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ---------------------------------------------------------
# Vault Provider
# ---------------------------------------------------------

provider "vault" {
  address      = var.vault_addr
  token        = var.vault_token
  ca_cert_file = var.vault_ca_cert != "" ? pathexpand(var.vault_ca_cert) : null
}

# ---------------------------------------------------------
# Read Credentials from Vault (KV v2)
# ---------------------------------------------------------

data "vault_kv_secret_v2" "hetzner" {
  count = var.use_vault ? 1 : 0
  mount = "secret"
  name  = "infra/hetzner"
}

data "vault_kv_secret_v2" "cloudflare" {
  count = var.use_vault ? 1 : 0
  mount = "secret"
  name  = "infra/cloudflare"
}

locals {
  hcloud_token         = var.use_vault ? data.vault_kv_secret_v2.hetzner[0].data["hcloud_token"] : var.hcloud_token
  cloudflare_api_token = var.use_vault ? data.vault_kv_secret_v2.cloudflare[0].data["api_token"] : var.cloudflare_api_token
  ssh_public_key       = var.use_vault ? data.vault_kv_secret_v2.hetzner[0].data["ssh_public_key"] : var.ssh_public_key
  mgmt_cidr            = var.use_vault ? data.vault_kv_secret_v2.hetzner[0].data["mgmt_cidr"] : var.mgmt_cidr
  home_cidr            = var.use_vault ? data.vault_kv_secret_v2.hetzner[0].data["home_cidr"] : var.home_cidr
  # nonsensitive() — domain name is public info, but Vault data source taints it as sensitive
  domain_name = nonsensitive(var.use_vault ? data.vault_kv_secret_v2.hetzner[0].data["domain_name"] : var.domain_name)
  # Hetzner Object Storage (S3-compatible) — for WireGuard peer config distribution
  # Credentials come from Vault; bucket name is a Terraform variable (the bucket is a managed resource)
  s3_access_key = var.use_vault ? data.vault_kv_secret_v2.hetzner[0].data["s3_access_key"] : var.s3_access_key
  s3_secret_key = var.use_vault ? data.vault_kv_secret_v2.hetzner[0].data["s3_secret_key"] : var.s3_secret_key
  s3_endpoint   = var.use_vault ? data.vault_kv_secret_v2.hetzner[0].data["s3_endpoint"] : var.s3_endpoint
  # Migadu domain ownership verification TXT value — stored in secret/infra/cloudflare alongside the API token.
  # nonsensitive() — this is a public DNS TXT record, but Vault taints it as sensitive.
  migadu_verification = var.use_vault ? nonsensitive(data.vault_kv_secret_v2.cloudflare[0].data["migadu_verification"]) : var.migadu_verification
}

# ---------------------------------------------------------
# Hetzner Cloud Provider
# ---------------------------------------------------------

provider "hcloud" {
  token = local.hcloud_token
}

# ---------------------------------------------------------
# Cloudflare Provider
# ---------------------------------------------------------

provider "cloudflare" {
  api_token = local.cloudflare_api_token
}

# ---------------------------------------------------------
# Hetzner Object Storage (S3-compatible via AWS provider)
# ---------------------------------------------------------
# The hcloud provider has no Object Storage resources (as of
# v1.60.0, Jan 2026). Hetzner exposes a standard S3 API
# (Ceph-backed), so we use the AWS provider with a custom
# endpoint to manage buckets.
#
# NOTE: S3 access/secret keys must be generated manually in
# the Hetzner Cloud Console (no public API for credential
# generation) and stored in Vault at secret/infra/hetzner.
# ---------------------------------------------------------

provider "aws" {
  access_key = local.s3_access_key
  secret_key = local.s3_secret_key
  region     = var.location

  # Hetzner S3 is Ceph-backed — skip AWS-specific validation
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  skip_region_validation      = true

  endpoints {
    s3 = "https://${local.s3_endpoint}"
  }
}
