# =============================================================================
# Layer 02-vault-config: Vault Configuration - Variables
# =============================================================================

# ---------------------------------------------------------
# Vault Connection
# ---------------------------------------------------------

variable "vault_addr" {
  description = "Vault API address (e.g., https://10.0.10.10:8200)"
  type        = string
  default     = "https://10.0.10.10:8200"
}

variable "vault_token" {
  description = "Vault token with admin/root privileges for initial configuration"
  type        = string
  sensitive   = true
}

variable "vault_ca_cert" {
  description = "Path to Vault TLS CA certificate (empty = use VAULT_CACERT env var)"
  type        = string
  default     = "~/.lab/tls/ca/ca.pem"
}

# ---------------------------------------------------------
# Secrets to Seed
# ---------------------------------------------------------

variable "proxmox_nodes" {
  description = "Map of Proxmox node names to their API credentials for seeding into Vault KV"
  type = map(object({
    api_url      = string
    token_id     = string
    token_secret = string
  }))
  default = {}
}

variable "unifi_credentials" {
  description = "UniFi controller credentials and infrastructure metadata for seeding into Vault at secret/infra/unifi"
  type = object({
    api_url = string
    api_key = string
    # Infrastructure metadata — not secrets, but centralized in Vault
    # so Layer 00 has a single source of truth for all UniFi values.
    default_lan_network_id = optional(string, "")
    switch_closet_mac      = optional(string, "")
    switch_minilab_mac     = optional(string, "")
    switch_rackmate_mac    = optional(string, "")
    switch_pro_xg8_mac     = optional(string, "")
    # WiFi passphrases
    iot_wlan_passphrase = optional(string, "")
  })
  sensitive = true
  default   = null
}

variable "hetzner_credentials" {
  description = "Hetzner Cloud credentials and deploy config for seeding into Vault at secret/infra/hetzner"
  type = object({
    hcloud_token   = string
    ssh_public_key = string
    mgmt_cidr      = string
    home_cidr      = string
    domain_name    = string
    # Hetzner Object Storage (S3-compatible) — credentials for WireGuard peer config bucket
    # Generated manually in Hetzner Cloud Console (no API for credential creation).
    # The bucket itself is a Terraform resource in Layer 06.
    s3_access_key = optional(string, "")
    s3_secret_key = optional(string, "")
    s3_endpoint   = optional(string, "")
  })
  sensitive = true
  default   = null
}

variable "cloudflare_credentials" {
  description = "Cloudflare credentials + Migadu DNS verification for seeding into Vault at secret/infra/cloudflare"
  type = object({
    api_token = string
    # Migadu domain ownership verification TXT value (from Migadu admin panel →
    # DNS Setup Instructions → "Verification TXT Record"). Single value like
    # "hosted-email-verify=rlghkpicy". Stored in Vault so Layer 06-hetzner can
    # create the DNS record without manual tfvars.
    migadu_verification = optional(string, "")
  })
  sensitive = true
  default   = null
}

# ---------------------------------------------------------
# Service Credentials
# ---------------------------------------------------------

variable "gitlab_credentials" {
  description = "GitLab admin credentials for seeding into Vault at secret/services/gitlab/admin"
  type = object({
    personal_access_token = string
    root_password         = string
  })
  sensitive = true
  default   = null
}

variable "gitlab_runner_token" {
  description = "GitLab Runner glrt- authentication token for seeding into Vault at secret/services/gitlab/runner"
  type        = string
  sensitive   = true
  default     = null
}

# ---------------------------------------------------------
# Admin Token Settings
# ---------------------------------------------------------

variable "admin_token_ttl" {
  description = "TTL for the admin token (renewable)"
  type        = string
  default     = "768h" # 32 days
}
