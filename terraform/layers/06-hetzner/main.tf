# =============================================================================
# Layer 06: Hetzner Cloud Infrastructure
# Rover CI visualization: https://github.com/im2nguyen/rover
# =============================================================================
# Deploys FirbLab's Hetzner Cloud infrastructure:
#
# 1. Gateway Server (lab-gateway, cpx22)
#    Docker with 8 services: Traefik, WireGuard, CrowdSec, Fail2ban,
#    Watchtower, AdGuard Home, Gotify, Uptime Kuma.
#    Homelab services (Ghost, Mealie, FoundryVTT) exposed via WireGuard tunnel.
#
# 2. Honeypot Server (lab-honeypot, cpx22)
#    Dedicated cybersecurity/deception server. Docker with Cowrie (SSH/Telnet),
#    OpenCanary (FTP/MySQL/RDP/VNC/Redis), Dionaea (SMB/SIP/HTTP malware
#    capture), Endlessh (SSH tarpit), and Grafana Alloy (log shipping to Loki).
#    WireGuard client tunnels logs back through the gateway to homelab Loki.
#
# Also manages:
#   - Cloudflare DNS records for all public-facing services
#   - Hetzner Object Storage buckets (backups, WireGuard peer configs)
#
# Prerequisites:
#   - Vault secrets seeded: secret/infra/hetzner, secret/infra/cloudflare
#   - Cloudflare zone for domain_name must exist
#   - SSH public key available
#
# Usage (all vars from Vault — zero flags needed):
#   cd terraform/layers/06-hetzner
#   terraform init
#   terraform apply
# =============================================================================

# ---------------------------------------------------------
# Password Generation
# ---------------------------------------------------------
# Generated at plan time, injected into cloud-init template.
# Passwords persist in Terraform state — store state securely.
# ---------------------------------------------------------

resource "random_password" "gotify" {
  length  = 32
  special = false
}

resource "random_password" "traefik_dashboard" {
  length  = 32
  special = false
}

resource "random_password" "adguard" {
  length  = 32
  special = false
}

# ---------------------------------------------------------
# Hetzner Object Storage — WireGuard Peer Config Bucket
# ---------------------------------------------------------
# S3-compatible bucket for distributing WireGuard peer configs
# to the homelab before the tunnel is established (Vault is
# unreachable until the tunnel is up — S3 breaks the chicken-
# and-egg). Cloud-init uploads peer configs here after
# generating them; the Ansible wireguard-deploy playbook
# downloads them on the homelab side.
# ---------------------------------------------------------

resource "aws_s3_bucket" "wireguard_peers" {
  bucket        = var.s3_bucket
  force_destroy = true
}

# ---------------------------------------------------------
# Hetzner Object Storage — Backup Buckets
# ---------------------------------------------------------
# Off-site backup storage for the 3-2-1 backup strategy.
# All backups are age-encrypted before upload.
# See docs/DISASTER-RECOVERY.md for retention and RPO targets.
# ---------------------------------------------------------

resource "aws_s3_bucket" "vault_backups" {
  bucket = "example-lab-vault-backups"

  # Server-side 30-day expiration — replaces script-based cleanup.
  # Uses inline lifecycle_rule for Hetzner S3-compatible API compatibility.
  lifecycle_rule {
    id      = "expire-after-30-days"
    enabled = true
    prefix  = ""

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket" "gitlab_backups" {
  bucket = "example-lab-gitlab-backups"

  lifecycle_rule {
    id      = "expire-after-30-days"
    enabled = true
    prefix  = ""

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket" "longhorn_backups" {
  bucket = "example-lab-longhorn-backups"

  lifecycle_rule {
    id      = "expire-after-30-days"
    enabled = true
    prefix  = ""

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket" "service_backups" {
  bucket = "example-lab-service-backups"

  lifecycle_rule {
    id      = "expire-after-30-days"
    enabled = true
    prefix  = ""

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket" "proxmox_backups" {
  bucket = "example-lab-proxmox-backups"

  lifecycle_rule {
    id      = "expire-after-30-days"
    enabled = true
    prefix  = ""

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket" "tfstate_backups" {
  bucket = "example-lab-tfstate-backups"
}

check "honeypot_requires_gateway" {
  assert {
    condition     = !var.honeypot_enabled || var.gateway_enabled
    error_message = "The Hetzner honeypot depends on the gateway for WireGuard peer distribution and log shipping. Set gateway_enabled=true when honeypot_enabled=true."
  }
}

locals {
  gateway_records = var.gateway_enabled ? [
    {
      name    = "@"
      type    = "A"
      content = module.server[0].server_ip
      comment = "FirbLab gateway server"
    },
    {
      name    = "blog"
      type    = "CNAME"
      content = local.domain_name
      comment = "Ghost blog (via WireGuard tunnel)"
    },
    {
      name    = "food"
      type    = "CNAME"
      content = local.domain_name
      comment = "Mealie recipe manager (via WireGuard tunnel)"
    },
    {
      name    = "foundryvtt"
      type    = "CNAME"
      content = local.domain_name
      comment = "FoundryVTT virtual tabletop (via WireGuard tunnel)"
    },
    {
      name    = "traefik"
      type    = "CNAME"
      content = local.domain_name
      comment = "Traefik reverse proxy dashboard"
    },
    {
      name    = "adguard"
      type    = "CNAME"
      content = local.domain_name
      comment = "AdGuard Home DNS admin"
    },
    {
      name    = "status"
      type    = "CNAME"
      content = local.domain_name
      comment = "Uptime Kuma monitoring"
    },
    {
      name    = "gotify"
      type    = "CNAME"
      content = local.domain_name
      comment = "Gotify push notifications"
    },
  ] : []

  honeypot_records = var.honeypot_enabled ? [
    {
      name    = "honeypot"
      type    = "A"
      content = module.honeypot_server[0].server_ip
      comment = "FirbLab honeypot server (Cowrie, OpenCanary, Dionaea)"
    },
  ] : []
}

moved {
  from = module.server
  to   = module.server[0]
}

moved {
  from = module.honeypot_server
  to   = module.honeypot_server[0]
}

# ---------------------------------------------------------
# Hetzner Cloud Server
# ---------------------------------------------------------

module "server" {
  count  = var.gateway_enabled ? 1 : 0
  source = "../../modules/hetzner-server/"

  # Server identity
  name        = var.server_name
  server_type = var.server_type
  location    = var.location
  image       = var.image

  # SSH
  create_ssh_key = true
  ssh_public_key = local.ssh_public_key

  # Labels
  labels = {
    environment = "production"
    managed_by  = "terraform"
    role        = "gateway"
  }

  # Cloud-init bootstrap — full Docker/WireGuard/Traefik deployment
  cloud_init_template = "${path.module}/files/user-data.sh.tpl"
  cloud_init_vars = {
    domain_name            = local.domain_name
    wireguard_port         = tostring(var.wireguard_port)
    wireguard_network      = var.wireguard_network
    wireguard_peers        = tostring(var.wireguard_peers)
    letsencrypt_email      = var.letsencrypt_email
    docker_network         = var.docker_network
    traefik_dashboard_hash = bcrypt(random_password.traefik_dashboard.result)
    gotify_password        = random_password.gotify.result
    adguard_password       = bcrypt(random_password.adguard.result)
    # Homelab service backends (routed via WireGuard tunnel to Services VLAN 20)
    ghost_backend      = var.ghost_backend
    mealie_backend     = var.mealie_backend
    foundryvtt_backend = var.foundryvtt_backend
    # Hetzner Object Storage — WireGuard peer config distribution
    s3_access_key = local.s3_access_key
    s3_secret_key = local.s3_secret_key
    s3_endpoint   = local.s3_endpoint
    s3_bucket     = aws_s3_bucket.wireguard_peers.id
    # WireGuard homelab peer routing
    homelab_peer_name = var.homelab_peer_name
    homelab_subnets   = var.homelab_subnets
  }

  # Firewall rules
  firewall_rules = [
    # Real SSH — moved to port 2222, restricted to WireGuard tunnel + home network
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "2222"
      source_ips = [local.mgmt_cidr, local.home_cidr]
    },
    # HTTP — public (Traefik, Let's Encrypt ACME challenge)
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "80"
      source_ips = ["0.0.0.0/0", "::/0"]
    },
    # HTTPS — public (Traefik reverse proxy)
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "443"
      source_ips = ["0.0.0.0/0", "::/0"]
    },
    # WireGuard UDP — public
    {
      direction  = "in"
      protocol   = "udp"
      port       = tostring(var.wireguard_port)
      source_ips = ["0.0.0.0/0", "::/0"]
    },
    # DNS (AdGuard Home) — restricted to mgmt CIDR
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "53"
      source_ips = [local.mgmt_cidr]
    },
    {
      direction  = "in"
      protocol   = "udp"
      port       = "53"
      source_ips = [local.mgmt_cidr]
    },
    # AdGuard admin UI — restricted
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "3000"
      source_ips = [local.mgmt_cidr]
    },
    # Uptime Kuma — restricted
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "3001"
      source_ips = [local.mgmt_cidr]
    },
    # Gotify — restricted
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "8080"
      source_ips = [local.mgmt_cidr]
    },
    # Traefik dashboard — restricted
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "8888"
      source_ips = [local.mgmt_cidr]
    },
  ]
}

# ---------------------------------------------------------
# Hetzner Cloud Server — Honeypot
# ---------------------------------------------------------
# Dedicated cybersecurity/deception server. Runs Cowrie,
# OpenCanary, Dionaea, Endlessh, and Grafana Alloy. Services
# deployed by Ansible (honeypot-deploy.yml); cloud-init only
# installs Docker and moves SSH to port 2222.
#
# WireGuard client on this server connects to the gateway's
# WireGuard server, allowing Alloy to push logs through the
# tunnel to the homelab Loki instance.
# ---------------------------------------------------------

module "honeypot_server" {
  count  = var.honeypot_enabled ? 1 : 0
  source = "../../modules/hetzner-server/"

  # Server identity
  name        = var.honeypot_server_name
  server_type = var.honeypot_server_type
  location    = var.location
  image       = var.image

  # SSH — reuse gateway's key (Hetzner enforces uniqueness on key material)
  create_ssh_key = !var.gateway_enabled
  ssh_key_id     = var.gateway_enabled ? module.server[0].ssh_key_id : null
  ssh_public_key = var.gateway_enabled ? "" : local.ssh_public_key

  # Labels
  labels = {
    environment = "production"
    managed_by  = "terraform"
    role        = "honeypot"
  }

  # Cloud-init bootstrap — Docker, SSH port migration, WireGuard client
  cloud_init_template = "${path.module}/files/honeypot-user-data.sh.tpl"
  cloud_init_vars = {
    ssh_port       = "2222"
    docker_network = var.docker_network
    # WireGuard client — downloads peer config from gateway's S3 bucket
    s3_access_key         = local.s3_access_key
    s3_secret_key         = local.s3_secret_key
    s3_endpoint           = local.s3_endpoint
    s3_bucket             = aws_s3_bucket.wireguard_peers.id
    wireguard_peer        = var.honeypot_wireguard_peer
    wireguard_allowed_ips = "${var.wireguard_network}, ${var.homelab_subnets}"
  }

  # Firewall rules — honeypot ports are PUBLIC (that's the point)
  firewall_rules = [
    # Real SSH — restricted to WireGuard tunnel + home network
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "2222"
      source_ips = [local.mgmt_cidr, local.home_cidr]
    },
    # WireGuard client — needs to reach gateway
    {
      direction  = "in"
      protocol   = "udp"
      port       = tostring(var.wireguard_port)
      source_ips = ["0.0.0.0/0", "::/0"]
    },
    # --- Honeypot ports — ALL PUBLIC ---
    # FTP (OpenCanary)
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "21"
      source_ips = ["0.0.0.0/0", "::/0"]
    },
    # SSH (Cowrie interactive honeypot)
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "22"
      source_ips = ["0.0.0.0/0", "::/0"]
    },
    # Telnet (Cowrie)
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "23"
      source_ips = ["0.0.0.0/0", "::/0"]
    },
    # SMB (Dionaea malware capture)
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "445"
      source_ips = ["0.0.0.0/0", "::/0"]
    },
    # MySQL (OpenCanary)
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "3306"
      source_ips = ["0.0.0.0/0", "::/0"]
    },
    # RDP (OpenCanary)
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "3389"
      source_ips = ["0.0.0.0/0", "::/0"]
    },
    # SIP (Dionaea)
    {
      direction  = "in"
      protocol   = "udp"
      port       = "5060"
      source_ips = ["0.0.0.0/0", "::/0"]
    },
    # VNC (OpenCanary)
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "5900"
      source_ips = ["0.0.0.0/0", "::/0"]
    },
    # Redis (OpenCanary)
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "6379"
      source_ips = ["0.0.0.0/0", "::/0"]
    },
    # HTTP (Dionaea)
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "8080"
      source_ips = ["0.0.0.0/0", "::/0"]
    },
    # HTTPS (Dionaea)
    {
      direction  = "in"
      protocol   = "tcp"
      port       = "8443"
      source_ips = ["0.0.0.0/0", "::/0"]
    },
  ]
}

# ---------------------------------------------------------
# Cloudflare DNS
# ---------------------------------------------------------

module "dns" {
  source = "../../modules/cloudflare-dns/"

  domain_name = local.domain_name

  records = concat(
    [
      # NOTE: No wildcard CNAME — explicit records ONLY.
      # A wildcard *.example-lab.org catches *.home.example-lab.org queries on public DNS,
      # which overrides the UCG-Fiber's internal DNS records when clients race
      # between local and upstream resolvers. This caused Firefox to connect to
      # the Hetzner Traefik (which has no routes for internal services) instead
      # of the standalone Traefik proxy (10.0.10.17).
      #
      # Explicit service records for Hetzner-proxied services
    ],
    local.gateway_records,
    [
      # ---------------------------------------------------------
      # Migadu Email DNS Records
      # ---------------------------------------------------------
      # MX, SPF, DKIM, DMARC for example-lab.org email via Migadu.
      # All email records MUST have proxied = false (Cloudflare
      # proxy breaks email — MX/TXT/CNAME need direct DNS).
      #
      # DKIM CNAME targets: Copy exact values from Migadu admin
      # panel → DNS settings before terraform apply.
      # ---------------------------------------------------------

      # MX records — route inbound email to Migadu
      {
        name     = "@"
        type     = "MX"
        content  = "aspmx1.migadu.com"
        priority = 10
        proxied  = false
        comment  = "Migadu MX primary"
      },
      {
        name     = "@"
        type     = "MX"
        content  = "aspmx2.migadu.com"
        priority = 20
        proxied  = false
        comment  = "Migadu MX secondary"
      },

      # Wildcard MX — catch-all for subdomains (Migadu recommendation)
      {
        name     = "*"
        type     = "MX"
        content  = "aspmx1.migadu.com"
        priority = 10
        proxied  = false
        comment  = "Migadu wildcard MX primary"
      },
      {
        name     = "*"
        type     = "MX"
        content  = "aspmx2.migadu.com"
        priority = 20
        proxied  = false
        comment  = "Migadu wildcard MX secondary"
      },

      # SPF — authorize Migadu to send on behalf of example-lab.org
      {
        name    = "@"
        type    = "TXT"
        content = "v=spf1 include:spf.migadu.com -all"
        proxied = false
        comment = "Migadu SPF"
      },

      # DKIM — Migadu signing keys (verify exact targets in Migadu admin panel)
      {
        name    = "key1._domainkey"
        type    = "CNAME"
        content = "key1.example-lab.org._domainkey.migadu.com"
        proxied = false
        comment = "Migadu DKIM key1"
      },
      {
        name    = "key2._domainkey"
        type    = "CNAME"
        content = "key2.example-lab.org._domainkey.migadu.com"
        proxied = false
        comment = "Migadu DKIM key2"
      },
      {
        name    = "key3._domainkey"
        type    = "CNAME"
        content = "key3.example-lab.org._domainkey.migadu.com"
        proxied = false
        comment = "Migadu DKIM key3"
      },

      # DMARC — policy for handling SPF/DKIM failures
      {
        name    = "_dmarc"
        type    = "TXT"
        content = "v=DMARC1; p=quarantine; rua=mailto:postmaster@example-lab.org"
        proxied = false
        comment = "DMARC policy"
      },

      # Migadu domain ownership verification TXT record
      # Value from Migadu admin panel → DNS Setup → "Verification TXT Record"
      {
        name    = "@"
        type    = "TXT"
        content = local.migadu_verification
        proxied = false
        comment = "Migadu domain ownership verification"
      },

      # Thunderbird/Outlook auto-discovery CNAMEs
      {
        name    = "autoconfig"
        type    = "CNAME"
        content = "autoconfig.migadu.com"
        proxied = false
        comment = "Thunderbird autoconfig via Migadu"
      },
      {
        name    = "autodiscover"
        type    = "CNAME"
        content = "autodiscover.migadu.com"
        proxied = false
        comment = "Outlook autodiscover via Migadu"
      },

      # ---------------------------------------------------------
      # SRV records — MANUALLY MANAGED in Cloudflare
      # ---------------------------------------------------------
      # Cloudflare provider v5 cannot create SRV records — the API
      # requires structured data fields (weight, port, target) but
      # cloudflare_dns_record only supports the content string field.
      # Create these 4 records manually in the Cloudflare dashboard:
      #
      #   _autodiscover._tcp  SRV  0 1 443  autodiscover.migadu.com
      #   _imaps._tcp         SRV  0 1 993  imap.migadu.com
      #   _pop3s._tcp         SRV  0 1 995  pop.migadu.com
      #   _submissions._tcp   SRV  0 1 465  smtp.migadu.com
      # ---------------------------------------------------------
    ],
    local.honeypot_records,
  )
}
