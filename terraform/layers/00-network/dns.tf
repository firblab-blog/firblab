# =============================================================================
# Internal DNS Records (home.example-lab.org)
# =============================================================================
# The gw-01 serves these to all DHCP clients via its built-in DNS forwarder.
# No external DNS server needed — records are injected directly.
#
# Architecture (3-way split):
#   K8s workloads       → K8s Traefik MetalLB VIP (10.0.20.220)
#   Standalone + mgmt   → Standalone Traefik proxy (10.0.10.17)
#   Vault               → Direct IP (own CA-signed TLS, no proxy needed)
#
# Adding a new K8s service:
#   1. Add to k8s_traefik_services below
#   2. Add IngressRoute in k8s/platform/traefik/manifests/
#   3. terraform apply
#
# Adding a new standalone/mgmt service:
#   1. Add to proxy_services below
#   2. Add backend entry in ansible/roles/traefik-standalone/defaults/main.yml
#   3. terraform apply + re-run Ansible
# =============================================================================

locals {
  # K8s Traefik LoadBalancer VIP (MetalLB services-pool 10.0.20.220-250)
  traefik_vip = "10.0.20.220"

  # K3s Traefik LoadBalancer VIP (MetalLB k3s-pool 10.0.20.200-219)
  k3s_traefik_vip = "10.0.20.200"

  # Standalone Traefik reverse proxy (LXC on Management VLAN 10)
  standalone_proxy_ip = "10.0.10.17"

  # RKE2 workloads — K8s Traefik (IngressRoute CRDs in k8s/platform/traefik/)
  k8s_traefik_services = toset([
    "headlamp",    # K8s platform (K8s dashboard)
    "longhorn",    # K8s platform (storage UI)
    "argocd",      # K8s platform (GitOps UI)
    "gitlab-test", # K8s workload (GitLab CE Helm testing instance)
    "wazuh",       # K8s workload (Wazuh SIEM dashboard)
  ])

  # K3s workloads — K3s Traefik (Ingress in k8s/k3s-platform/)
  k3s_traefik_services = toset([
    "grafana",     # Monitoring dashboards (migrated from RKE2)
  ])

  # ALL standalone + management services → standalone Traefik proxy
  # TLS termination via Let's Encrypt DNS-01. Traefik routes by Host header.
  proxy_services = toset([
    "ghost",         # Standalone LXC — blog (ForwardAuth)
    "mail",          # Roundcube LXC — webmail (ForwardAuth)
    "foundryvtt",    # Standalone VM — virtual tabletop (ForwardAuth)
    "mealie",        # Standalone LXC — recipe manager (native OIDC)
    "netbox",        # Standalone VM — DCIM/IPAM (native OIDC)
    "patchmon",      # Standalone VM — patch monitoring (native OIDC)
    "actualbudget",  # Standalone LXC — personal finance (ForwardAuth)
    "git",           # Alias for GitLab (short subdomain)
    "gitlab",        # Management VM — source control (native OIDC)
    "auth",          # Management VM — Authentik SSO/IDP
    "pbs",           # Management VM — Proxmox Backup Server (ForwardAuth)
    "vaultwarden",   # Standalone LXC — password vault (native OIDC)
    "openwebui",     # Standalone VM — AI chat UI (ForwardAuth)
    "n8n",           # Standalone VM — workflow automation (ForwardAuth)
    # Archive appliance (ZimaBlade 7700 bare-metal, Services VLAN 20)
    "archive",       # FileBrowser file manager (ForwardAuth)
    "kiwix",         # Kiwix Serve — offline Wikipedia/StackExchange/iFixit (ForwardAuth)
    "archivebox",    # ArchiveBox — web page archiving (ForwardAuth)
    "bookstack",     # BookStack — personal wiki (ForwardAuth)
    "stirlingpdf",   # Stirling PDF — PDF tools (ForwardAuth)
    "wallabag",      # Wallabag — read-it-later (ForwardAuth)
    "backrest",      # Management LXC — Backrest backup monitoring UI (ForwardAuth)
    "status",        # Management LXC — Uptime Kuma internal monitoring (ForwardAuth)
    "homeassistant", # IoT RPi5 — Home Assistant (native OIDC)
    # Hetzner gateway services — proxied via standalone Traefik to *.example-lab.org
    # Accessible from workstation; internal names keep traffic consistent with homelab DNS
    "gotify",        # Hetzner — notification server (native auth)
    "adguard",       # Hetzner — DNS-level ad blocking (native auth)
    # TrueNAS apps (Storage VLAN 40, 10.0.40.2)
    "archiver",      # Mail Archiver (native OIDC)
    "truenas",       # TrueNAS web UI (native auth)
    "immich",        # Photo management (native auth)
    "linkwarden",    # Bookmark manager (native auth)
    "paperless",     # Paperless-ngx document management (native auth)
    "plex",          # Plex Media Server (Plex account auth)
    "portracker",    # Port tracker (native auth)
    "tools",         # IT Tools developer utilities (native auth)
    "search",        # SearXNG metasearch engine (ForwardAuth)
    # Proxmox node UIs (Management VLAN 10 — self-signed certs, proxied for valid TLS)
    "pve-01",        # lab-01 (i9-12900K, main compute)
    "pve-02",        # lab-02 (N100, pilot node)
    "pve-03",        # lab-03 (N100, lightweight services)
    "pve-04",        # lab-04 (J5005, lightweight compute)
  ])

  # Direct IPs — own TLS, no proxy needed
  # Vault uses its own CA-signed TLS. Tools connect by IP, not hostname.
  direct_services = {
    "vault" = "10.0.10.10"
  }
}

# ---------------------------------------------------------
# K8s Traefik-proxied services (IngressRoute CRDs)
# ---------------------------------------------------------

resource "unifi_dns_record" "k8s_traefik_service" {
  for_each = local.k8s_traefik_services

  name    = "${each.value}.home.example-lab.org"
  type    = "A"
  record  = local.traefik_vip
  enabled = true
  ttl     = 300
}

# ---------------------------------------------------------
# K3s Traefik-proxied services (Ingress in k8s/k3s-platform/)
# ---------------------------------------------------------

resource "unifi_dns_record" "k3s_traefik_service" {
  for_each = local.k3s_traefik_services

  name    = "${each.value}.home.example-lab.org"
  type    = "A"
  record  = local.k3s_traefik_vip
  enabled = true
  ttl     = 300
}

# ---------------------------------------------------------
# Standalone proxy services (Traefik LXC on VLAN 10)
# ---------------------------------------------------------

resource "unifi_dns_record" "proxy_service" {
  for_each = local.proxy_services

  name    = "${each.value}.home.example-lab.org"
  type    = "A"
  record  = local.standalone_proxy_ip
  enabled = true
  ttl     = 300
}

# ---------------------------------------------------------
# Direct-access services (own TLS, no proxy)
# ---------------------------------------------------------

resource "unifi_dns_record" "direct_service" {
  for_each = local.direct_services

  name    = "${each.key}.home.example-lab.org"
  type    = "A"
  record  = each.value
  enabled = true
  ttl     = 300
}
