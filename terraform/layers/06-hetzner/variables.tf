# =============================================================================
# Layer 06: Hetzner - Variables
# =============================================================================

# ---------------------------------------------------------
# Vault Connection (source of truth for secrets)
# ---------------------------------------------------------

variable "use_vault" {
  description = "Read Hetzner/Cloudflare credentials from Vault (set false for bootstrap)"
  type        = bool
  default     = true
}

variable "vault_addr" {
  description = "Vault API address"
  type        = string
  default     = "https://10.0.10.10:8200"
}

variable "vault_token" {
  description = "Vault authentication token (reads from VAULT_TOKEN env var or ~/.vault-token)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_ca_cert" {
  description = "Path to Vault TLS CA certificate (empty = use VAULT_CACERT env var)"
  type        = string
  default     = "~/.lab/tls/ca/ca.pem"
}

# ---------------------------------------------------------
# Hetzner Cloud Connection
# ---------------------------------------------------------

variable "hcloud_token" {
  description = "Hetzner Cloud API token — only used when use_vault=false (bootstrap)"
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------
# Gateway Server Configuration
# ---------------------------------------------------------

variable "server_name" {
  description = "Name for the Hetzner gateway server"
  type        = string
  default     = "lab-gateway"
}

variable "server_type" {
  description = "Hetzner server type for gateway (e.g., cpx22, cpx32)"
  type        = string
  default     = "cpx22"
}

# ---------------------------------------------------------
# Honeypot Server Configuration
# ---------------------------------------------------------

variable "honeypot_server_name" {
  description = "Name for the Hetzner honeypot server"
  type        = string
  default     = "lab-honeypot"
}

variable "honeypot_server_type" {
  description = "Hetzner server type for honeypot (e.g., cpx22, cpx32)"
  type        = string
  default     = "cpx22"
}

variable "honeypot_wireguard_peer" {
  description = "WireGuard peer name to download from S3 for the honeypot client (e.g., peer2)"
  type        = string
  default     = "peer2"
}

# ---------------------------------------------------------
# Shared Server Configuration
# ---------------------------------------------------------

variable "location" {
  description = "Hetzner datacenter location (e.g., fsn1, nbg1, hel1)"
  type        = string
  default     = "nbg1"
}

variable "image" {
  description = "Server OS image"
  type        = string
  default     = "ubuntu-24.04"
}

# ---------------------------------------------------------
# SSH
# ---------------------------------------------------------

variable "ssh_public_key" {
  description = "SSH public key — only used when use_vault=false (bootstrap). Normally read from Vault."
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# Network / Firewall
# ---------------------------------------------------------

variable "mgmt_cidr" {
  description = "Management CIDR — only used when use_vault=false (bootstrap). Normally read from Vault."
  type        = string
  default     = ""
}

variable "home_cidr" {
  description = "Home network public IP CIDR for SSH access — only used when use_vault=false (bootstrap). Normally read from Vault."
  type        = string
  default     = ""
}

variable "wireguard_port" {
  description = "WireGuard UDP port for VPN tunnel"
  type        = number
  default     = 51820
}

variable "wireguard_network" {
  description = "WireGuard tunnel CIDR (e.g., 10.8.0.0/24)"
  type        = string
  default     = "10.8.0.0/24"
}

variable "wireguard_peers" {
  description = "Number of WireGuard peer key pairs to pre-generate"
  type        = number
  default     = 20
}

# ---------------------------------------------------------
# Docker
# ---------------------------------------------------------

variable "docker_network" {
  description = "Docker bridge network CIDR for the services network"
  type        = string
  default     = "172.18.0.0/24"
}

# ---------------------------------------------------------
# Services
# ---------------------------------------------------------

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate notifications"
  type        = string
  default     = "admin@example-lab.org"
}

# ---------------------------------------------------------
# Homelab Service Backends (routed via WireGuard tunnel)
# ---------------------------------------------------------

variable "ghost_backend" {
  description = "Ghost blog backend address (IP:port on Services VLAN, reached via WireGuard)"
  type        = string
  default     = "10.0.20.10:2368"
}

variable "mealie_backend" {
  description = "Mealie recipe manager backend address (IP:port on Services VLAN, reached via WireGuard)"
  type        = string
  default     = "10.0.20.13:9000"
}

variable "foundryvtt_backend" {
  description = "FoundryVTT virtual tabletop backend address (IP:port on Services VLAN, reached via WireGuard)"
  type        = string
  default     = "10.0.20.12:30000"
}

# ---------------------------------------------------------
# Hetzner Object Storage (S3-compatible)
# ---------------------------------------------------------
# Used to distribute WireGuard peer configs to the homelab
# before the tunnel is established (Vault is unreachable).

variable "s3_access_key" {
  description = "Hetzner S3 access key — only used when use_vault=false (bootstrap)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "s3_secret_key" {
  description = "Hetzner S3 secret key — only used when use_vault=false (bootstrap)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "s3_endpoint" {
  description = "Hetzner S3 endpoint (e.g., nbg1.your-objectstorage.com) — only used when use_vault=false"
  type        = string
  default     = ""
}

variable "s3_bucket" {
  description = "Hetzner S3 bucket name for WireGuard peer configs (managed by Terraform)"
  type        = string
  default     = "firblab-wireguard"
}

# ---------------------------------------------------------
# WireGuard Homelab Peer Configuration
# ---------------------------------------------------------

variable "homelab_peer_name" {
  description = "WireGuard peer name designated as the homelab gateway (receives subnet routes on server side)"
  type        = string
  default     = "peer1"
}

variable "homelab_subnets" {
  description = "Comma-separated homelab subnets to route through the WireGuard tunnel to the homelab peer"
  type        = string
  default     = "10.0.20.0/24, 10.0.30.0/24"
}

# ---------------------------------------------------------
# Cloudflare DNS
# ---------------------------------------------------------

variable "cloudflare_api_token" {
  description = "Cloudflare API token — only used when use_vault=false (bootstrap)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "domain_name" {
  description = "Primary domain name — only used when use_vault=false (bootstrap). Normally read from Vault."
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# Migadu Email Verification (bootstrap fallback only)
# ---------------------------------------------------------
# Normally read from Vault (secret/infra/cloudflare). Only
# used when use_vault=false. Value from Migadu admin panel.

variable "migadu_verification" {
  description = "Migadu domain ownership verification TXT value (e.g. 'hosted-email-verify=xxx') — only used when use_vault=false"
  type        = string
  default     = ""
}
