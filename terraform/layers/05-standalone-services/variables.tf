# =============================================================================
# Layer 05: Standalone Services - Variables
# =============================================================================

# ---------------------------------------------------------
# Vault Connection (source of truth for secrets)
# ---------------------------------------------------------

variable "use_vault" {
  description = "Read Proxmox credentials from Vault (set false for bootstrap before Vault exists)"
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
# Proxmox Connection
# ---------------------------------------------------------

variable "proxmox_node" {
  description = "Proxmox node name — used for Vault secret lookup and resource targeting"
  type        = string
  default     = "lab-03"
}

variable "proxmox_api_url" {
  description = "Proxmox API URL — only used when use_vault=false (bootstrap)"
  type        = string
  default     = ""
}

variable "proxmox_api_token" {
  description = "Proxmox API token (format: user@realm!token=secret) — only used when use_vault=false (bootstrap)"
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------
# SSH
# ---------------------------------------------------------

variable "ssh_public_key" {
  description = "Additional SSH public key to authorize on all services"
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# Shared Infrastructure Settings
# ---------------------------------------------------------

variable "storage_pool" {
  description = "Proxmox storage pool for OS disks (NVMe recommended)"
  type        = string
  default     = "local-lvm"
}

variable "clone_template_vm_id" {
  description = "Proxmox VM ID of the Packer-built template to clone (e.g., 9000 for tmpl-ubuntu-2404-base)"
  type        = number
  default     = 9000
}

variable "clone_template_node" {
  description = "Proxmox node where the Packer template lives. Enables cross-node cloning."
  type        = string
  default     = "lab-01"
}

variable "data_storage_pool" {
  description = "Proxmox storage pool for data disks — game assets, etc. (defaults to storage_pool on single-disk nodes)"
  type        = string
  default     = "local-lvm"
}

variable "snippet_storage" {
  description = "Proxmox storage for cloud-init snippets"
  type        = string
  default     = "local"
}

# ---------------------------------------------------------
# Network Settings (Services VLAN 20)
# ---------------------------------------------------------

variable "network_bridge" {
  description = "Network bridge for all services"
  type        = string
  default     = "vmbr0"
}

variable "vlan_tag" {
  description = "VLAN tag for all services (Services VLAN)"
  type        = number
  default     = 20
}

variable "gateway" {
  description = "Network gateway for the Services VLAN"
  type        = string
  default     = "10.0.20.1"
}

variable "domain_name" {
  description = "DNS domain name"
  type        = string
  default     = "example-lab.local"
}

variable "dns_servers" {
  description = "DNS server addresses — default is UDM Pro Services VLAN 20 gateway"
  type        = list(string)
  default     = ["10.0.20.1"]
}

# ---------------------------------------------------------
# Ghost (LXC)
# ---------------------------------------------------------

variable "ghost_vm_id" {
  description = "Proxmox VM ID for Ghost container"
  type        = number
  default     = 5010
}

variable "ghost_name" {
  description = "Hostname for Ghost container"
  type        = string
  default     = "ghost"
}

variable "ghost_cpu_cores" {
  description = "Number of CPU cores for Ghost"
  type        = number
  default     = 1
}

variable "ghost_memory_mb" {
  description = "Memory in MB for Ghost"
  type        = number
  default     = 1024
}

variable "ghost_disk_size_gb" {
  description = "Disk size in GB for Ghost"
  type        = number
  default     = 20
}

variable "ghost_ip_address" {
  description = "Static IP address for Ghost in CIDR notation"
  type        = string
  default     = "10.0.20.10/24"
}

# ---------------------------------------------------------
# FoundryVTT (VM)
# ---------------------------------------------------------

variable "foundryvtt_vm_id" {
  description = "Proxmox VM ID for FoundryVTT"
  type        = number
  default     = 5011
}

variable "foundryvtt_name" {
  description = "Hostname for FoundryVTT VM"
  type        = string
  default     = "foundryvtt"
}

variable "foundryvtt_cpu_cores" {
  description = "Number of CPU cores for FoundryVTT"
  type        = number
  default     = 2
}

variable "foundryvtt_memory_mb" {
  description = "Memory in MB for FoundryVTT"
  type        = number
  default     = 2048
}

variable "foundryvtt_os_disk_size_gb" {
  description = "OS disk size in GB for FoundryVTT"
  type        = number
  default     = 40
}

variable "foundryvtt_data_disk_size_gb" {
  description = "Data disk size in GB for FoundryVTT (game assets, worlds)"
  type        = number
  default     = 30
}

variable "foundryvtt_ip_address" {
  description = "Static IP address for FoundryVTT in CIDR notation"
  type        = string
  default     = "10.0.20.12/24"
}

# ---------------------------------------------------------
# Roundcube (LXC)
# ---------------------------------------------------------

variable "roundcube_vm_id" {
  description = "Proxmox VM ID for Roundcube container"
  type        = number
  default     = 5013
}

variable "roundcube_name" {
  description = "Hostname for Roundcube container"
  type        = string
  default     = "roundcube"
}

variable "roundcube_cpu_cores" {
  description = "Number of CPU cores for Roundcube"
  type        = number
  default     = 1
}

variable "roundcube_memory_mb" {
  description = "Memory in MB for Roundcube (PostgreSQL + Roundcube)"
  type        = number
  default     = 1024
}

variable "roundcube_disk_size_gb" {
  description = "Disk size in GB for Roundcube"
  type        = number
  default     = 10
}

variable "roundcube_ip_address" {
  description = "Static IP address for Roundcube in CIDR notation"
  type        = string
  default     = "10.0.20.11/24"
}

# ---------------------------------------------------------
# Mealie (LXC)
# ---------------------------------------------------------

variable "mealie_vm_id" {
  description = "Proxmox VM ID for Mealie container"
  type        = number
  default     = 5014
}

variable "mealie_name" {
  description = "Hostname for Mealie container"
  type        = string
  default     = "mealie"
}

variable "mealie_cpu_cores" {
  description = "Number of CPU cores for Mealie"
  type        = number
  default     = 1
}

variable "mealie_memory_mb" {
  description = "Memory in MB for Mealie"
  type        = number
  default     = 1024
}

variable "mealie_disk_size_gb" {
  description = "Disk size in GB for Mealie"
  type        = number
  default     = 10
}

variable "mealie_ip_address" {
  description = "Static IP address for Mealie in CIDR notation"
  type        = string
  default     = "10.0.20.13/24"
}

# ---------------------------------------------------------
# WireGuard (LXC) — DMZ VLAN 30
# ---------------------------------------------------------
# WireGuard gateway that terminates the site-to-site tunnel
# from Hetzner. Lives on the DMZ VLAN (30), NOT the default
# Services VLAN (20). NAT/masquerades traffic toward VLAN 20
# so service hosts see source IP 10.0.30.2.
# ---------------------------------------------------------

variable "wireguard_vm_id" {
  description = "Proxmox VM ID for WireGuard container"
  type        = number
  default     = 5020
}

variable "wireguard_name" {
  description = "Hostname for WireGuard container"
  type        = string
  default     = "wireguard"
}

variable "wireguard_cpu_cores" {
  description = "Number of CPU cores for WireGuard"
  type        = number
  default     = 1
}

variable "wireguard_memory_mb" {
  description = "Memory in MB for WireGuard"
  type        = number
  default     = 256
}

variable "wireguard_disk_size_gb" {
  description = "Disk size in GB for WireGuard"
  type        = number
  default     = 4
}

variable "wireguard_ip_address" {
  description = "Static IP address for WireGuard on DMZ VLAN 30 in CIDR notation"
  type        = string
  default     = "10.0.30.2/24"
}

variable "wireguard_gateway" {
  description = "Gateway for the DMZ VLAN"
  type        = string
  default     = "10.0.30.1"
}

variable "wireguard_vlan_tag" {
  description = "VLAN tag for WireGuard (DMZ VLAN)"
  type        = number
  default     = 30
}

# ---------------------------------------------------------
# NetBox (VM) — lab-04
# ---------------------------------------------------------
# DCIM + IPAM infrastructure mapping platform. Runs as a
# full VM (not LXC) to get CIS hardening. Deployed on
# lab-04 (idle node, 20GB RAM) to avoid impacting
# existing workloads on lab-03.
# ---------------------------------------------------------

variable "netbox_vm_id" {
  description = "Proxmox VM ID for NetBox"
  type        = number
  default     = 5030
}

variable "netbox_name" {
  description = "Hostname for NetBox VM"
  type        = string
  default     = "netbox"
}

variable "netbox_proxmox_node" {
  description = "Proxmox node for NetBox VM placement (separate from shared proxmox_node since NetBox lives on lab-04)"
  type        = string
  default     = "lab-04"
}

variable "netbox_cpu_cores" {
  description = "Number of CPU cores for NetBox"
  type        = number
  default     = 2
}

variable "netbox_memory_mb" {
  description = "Memory in MB for NetBox"
  type        = number
  default     = 4096
}

variable "netbox_os_disk_size_gb" {
  description = "OS disk size in GB for NetBox"
  type        = number
  default     = 40
}

variable "netbox_ip_address" {
  description = "Static IP address for NetBox in CIDR notation"
  type        = string
  default     = "10.0.20.14/24"
}

# ---------------------------------------------------------
# Proxmox Backup Server (VM) — lab-04, Management VLAN 10
# ---------------------------------------------------------
# Centralized backup server with content-addressable dedup.
# Replaces per-node vzdump cron scripts. Lives on Management
# VLAN 10 for direct access from all Proxmox nodes. Uses its
# own Packer template (PBS ISO, VM ID 9002) — NOT Ubuntu.
# ---------------------------------------------------------

variable "pbs_vm_id" {
  description = "Proxmox VM ID for PBS"
  type        = number
  default     = 5031
}

variable "pbs_name" {
  description = "Hostname for PBS VM"
  type        = string
  default     = "pbs"
}

variable "pbs_proxmox_node" {
  description = "Proxmox node for PBS VM placement"
  type        = string
  default     = "lab-04"
}

variable "pbs_template_vm_id" {
  description = "Proxmox VM ID of the PBS Packer template (9002, separate from Ubuntu 9000)"
  type        = number
  default     = 9002
}

variable "pbs_cpu_cores" {
  description = "Number of CPU cores for PBS"
  type        = number
  default     = 2
}

variable "pbs_memory_mb" {
  description = "Memory in MB for PBS"
  type        = number
  default     = 4096
}

variable "pbs_os_disk_size_gb" {
  description = "OS disk size in GB for PBS"
  type        = number
  default     = 32
}

variable "pbs_passthrough_disks" {
  description = "Physical disk /dev/disk/by-id/ names to passthrough to PBS VM for ZFS mirror (stable serial-based IDs from lab-04)"
  type        = list(string)
  default = [
    "ata-ST18000NM000J-2TV103_ZR5E1GJ7", # /dev/sdb — 18TB Seagate (16.4T usable)
    "ata-ST16000NM000J-2TW103_ZR5EXLL9", # /dev/sdc — 16TB Seagate (14.6T usable)
  ]
}

variable "pbs_ip_address" {
  description = "Static IP address for PBS on Management VLAN 10 in CIDR notation"
  type        = string
  default     = "10.0.10.15/24"
}

variable "pbs_gateway" {
  description = "Gateway for PBS on Management VLAN 10"
  type        = string
  default     = "10.0.10.1"
}

# ---------------------------------------------------------
# Authentik (VM) — lab-04, Management VLAN 10
# ---------------------------------------------------------
# SSO/IDP — CIS-hardened VM with Docker Compose.
# Holds credentials and issues tokens for all services.
# ---------------------------------------------------------

variable "authentik_vm_id" {
  description = "Proxmox VM ID for Authentik"
  type        = number
  default     = 5021
}

variable "authentik_name" {
  description = "Hostname for Authentik VM"
  type        = string
  default     = "authentik"
}

variable "authentik_proxmox_node" {
  description = "Proxmox node for Authentik VM placement"
  type        = string
  default     = "lab-01"
}

variable "authentik_cpu_cores" {
  description = "Number of CPU cores for Authentik"
  type        = number
  default     = 2
}

variable "authentik_memory_mb" {
  description = "Memory in MB for Authentik"
  type        = number
  default     = 4096
}

variable "authentik_os_disk_size_gb" {
  description = "OS disk size in GB for Authentik (must be >= Packer template base disk)"
  type        = number
  default     = 40
}

variable "authentik_storage_pool" {
  description = "Storage pool for Authentik OS disk. Restored from PBS to nvme-thin-1 on lab-01."
  type        = string
  default     = "nvme-thin-1"
}

variable "authentik_ip_address" {
  description = "Static IP address for Authentik on Management VLAN 10 in CIDR notation"
  type        = string
  default     = "10.0.10.16/24"
}

variable "authentik_gateway" {
  description = "Gateway for Authentik on Management VLAN 10"
  type        = string
  default     = "10.0.10.1"
}

# ---------------------------------------------------------
# PatchMon (VM) — lab-04, Services VLAN 20
# ---------------------------------------------------------
# Linux fleet patch monitoring. Docker Compose stack
# (PostgreSQL + Redis + backend + frontend). CIS-hardened
# VM on lab-04 alongside NetBox and Authentik.
# ---------------------------------------------------------

variable "patchmon_vm_id" {
  description = "Proxmox VM ID for PatchMon"
  type        = number
  default     = 5032
}

variable "patchmon_name" {
  description = "Hostname for PatchMon VM"
  type        = string
  default     = "patchmon"
}

variable "patchmon_proxmox_node" {
  description = "Proxmox node for PatchMon VM placement"
  type        = string
  default     = "lab-04"
}

variable "patchmon_cpu_cores" {
  description = "Number of CPU cores for PatchMon"
  type        = number
  default     = 2
}

variable "patchmon_memory_mb" {
  description = "Memory in MB for PatchMon"
  type        = number
  default     = 2048
}

variable "patchmon_os_disk_size_gb" {
  description = "OS disk size in GB for PatchMon (must be >= Packer template base disk)"
  type        = number
  default     = 40
}

variable "patchmon_ip_address" {
  description = "Static IP address for PatchMon in CIDR notation"
  type        = string
  default     = "10.0.20.15/24"
}

# ---------------------------------------------------------
# changedetection.io (LXC) — lab-03, Services VLAN 20
# ---------------------------------------------------------
# Web page change monitoring and alerting. Watches GovDeals
# and other auction sites for homelab hardware listings.
# Playwright browser sidecar for JavaScript rendering.
# ---------------------------------------------------------

variable "changedetection_vm_id" {
  description = "Proxmox VM ID for changedetection.io container"
  type        = number
  default     = 5016
}

variable "changedetection_name" {
  description = "Hostname for changedetection.io container"
  type        = string
  default     = "changedetection"
}

variable "changedetection_cpu_cores" {
  description = "Number of CPU cores for changedetection.io"
  type        = number
  default     = 1
}

variable "changedetection_memory_mb" {
  description = "Memory in MB for changedetection.io (2GB for Playwright browser sidecar)"
  type        = number
  default     = 2048
}

variable "changedetection_disk_size_gb" {
  description = "Disk size in GB for changedetection.io"
  type        = number
  default     = 8
}

variable "changedetection_ip_address" {
  description = "Static IP address for changedetection.io in CIDR notation"
  type        = string
  default     = "10.0.20.17/24"
}

# ---------------------------------------------------------
# Actual Budget (LXC) — lab-03, Services VLAN 20
# ---------------------------------------------------------
# Local-first personal finance app. Minimal resource needs:
# single container, SQLite, no external DB.
# ---------------------------------------------------------

variable "actualbudget_vm_id" {
  description = "Proxmox VM ID for Actual Budget container"
  type        = number
  default     = 5015
}

variable "actualbudget_name" {
  description = "Hostname for Actual Budget container"
  type        = string
  default     = "actualbudget"
}

variable "actualbudget_cpu_cores" {
  description = "Number of CPU cores for Actual Budget"
  type        = number
  default     = 1
}

variable "actualbudget_memory_mb" {
  description = "Memory in MB for Actual Budget"
  type        = number
  default     = 512
}

variable "actualbudget_disk_size_gb" {
  description = "Disk size in GB for Actual Budget"
  type        = number
  default     = 10
}

variable "actualbudget_ip_address" {
  description = "Static IP address for Actual Budget in CIDR notation"
  type        = string
  default     = "10.0.20.16/24"
}

# ---------------------------------------------------------
# Traefik Reverse Proxy (LXC) — lab-04, Management VLAN 10
# ---------------------------------------------------------
# Standalone Traefik v3 reverse proxy for all non-K8s services.
# TLS termination via Let's Encrypt DNS-01 (Cloudflare).
# Lightweight LXC — Traefik is very resource-efficient.
# ---------------------------------------------------------

variable "traefik_proxy_vm_id" {
  description = "Proxmox VM ID for Traefik proxy container"
  type        = number
  default     = 5033
}

variable "traefik_proxy_name" {
  description = "Hostname for Traefik proxy container"
  type        = string
  default     = "traefik-proxy"
}

variable "traefik_proxy_proxmox_node" {
  description = "Proxmox node for Traefik proxy placement"
  type        = string
  default     = "lab-04"
}

variable "traefik_proxy_cpu_cores" {
  description = "Number of CPU cores for Traefik proxy"
  type        = number
  default     = 1
}

variable "traefik_proxy_memory_mb" {
  description = "Memory in MB for Traefik proxy"
  type        = number
  default     = 512
}

variable "traefik_proxy_disk_size_gb" {
  description = "Disk size in GB for Traefik proxy"
  type        = number
  default     = 10
}

variable "traefik_proxy_ip_address" {
  description = "Static IP address for Traefik proxy on Management VLAN 10 in CIDR notation"
  type        = string
  default     = "10.0.10.17/24"
}

variable "traefik_proxy_gateway" {
  description = "Gateway for Traefik proxy on Management VLAN 10"
  type        = string
  default     = "10.0.10.1"
}

# ---------------------------------------------------------
# Vaultwarden (LXC) — lab-03, Services VLAN 20
# ---------------------------------------------------------
# Self-hosted password vault (Bitwarden-compatible). Backup
# mirror for 1Password. Minimal resource needs: single
# container, SQLite, no external DB.
# ---------------------------------------------------------

variable "vaultwarden_vm_id" {
  description = "Proxmox VM ID for Vaultwarden container"
  type        = number
  default     = 5036
}

variable "vaultwarden_name" {
  description = "Hostname for Vaultwarden container"
  type        = string
  default     = "vaultwarden"
}

variable "vaultwarden_cpu_cores" {
  description = "Number of CPU cores for Vaultwarden"
  type        = number
  default     = 1
}

variable "vaultwarden_memory_mb" {
  description = "Memory in MB for Vaultwarden"
  type        = number
  default     = 512
}

variable "vaultwarden_disk_size_gb" {
  description = "Disk size in GB for Vaultwarden"
  type        = number
  default     = 4
}

variable "vaultwarden_ip_address" {
  description = "Static IP address for Vaultwarden in CIDR notation"
  type        = string
  default     = "10.0.20.19/24"
}

# ---------------------------------------------------------
# Archive — REMOVED (migrating to dedicated ZimaBlade 7700)
# ---------------------------------------------------------


# ---------------------------------------------------------
# Backup (LXC) — lab-01, Management VLAN 10
# ---------------------------------------------------------
# Restic REST server + Backrest monitoring UI. Centralized
# backup target for all service hosts. Bind-mounts
# /hdd-mirror-0/restic from lab-01's host ZFS mirror.
# No Docker needed — both services are standalone Go binaries
# running as systemd units.
# ---------------------------------------------------------

variable "backup_vm_id" {
  description = "Proxmox VM ID for backup LXC container"
  type        = number
  default     = 5040
}

variable "backup_name" {
  description = "Hostname for backup LXC container"
  type        = string
  default     = "backup"
}

variable "backup_proxmox_node" {
  description = "Proxmox node for backup LXC placement (must host hdd-mirror-0)"
  type        = string
  default     = "lab-01"
}

variable "backup_cpu_cores" {
  description = "Number of CPU cores for backup LXC"
  type        = number
  default     = 2
}

variable "backup_memory_mb" {
  description = "Memory in MB for backup LXC"
  type        = number
  default     = 1024
}

variable "backup_disk_size_gb" {
  description = "Root disk size in GB for backup LXC"
  type        = number
  default     = 8
}

variable "backup_ip_address" {
  description = "Static IP address for backup LXC on Management VLAN 10 in CIDR notation"
  type        = string
  default     = "10.0.10.18/24"
}

variable "backup_gateway" {
  description = "Gateway for backup LXC on Management VLAN 10"
  type        = string
  default     = "10.0.10.1"
}

variable "backup_host_mount_path" {
  description = "Host path to bind-mount into the backup LXC (hdd-mirror-0 restic data)"
  type        = string
  default     = "/hdd-mirror-0/restic"
}

variable "backup_container_mount_path" {
  description = "Mount path inside the backup LXC container"
  type        = string
  default     = "/mnt/restic"
}

# ---------------------------------------------------------
# Uptime Kuma Internal (LXC) — lab-03, Management VLAN 10
# ---------------------------------------------------------
# Internal homelab monitoring instance. Monitors Vault, Proxmox,
# and all *.home.example-lab.org services. Lives on Management VLAN 10
# so it can reach all VLANs directly — no WireGuard tunnel needed.
# Paired with the public Uptime Kuma on the Hetzner gateway which
# monitors public-facing *.example-lab.org services.
# ---------------------------------------------------------

variable "uptime_kuma_internal_vm_id" {
  description = "Proxmox VM ID for internal Uptime Kuma container"
  type        = number
  default     = 5041
}

variable "uptime_kuma_internal_name" {
  description = "Hostname for internal Uptime Kuma container"
  type        = string
  default     = "uptime-kuma-internal"
}

variable "uptime_kuma_internal_cpu_cores" {
  description = "Number of CPU cores for internal Uptime Kuma"
  type        = number
  default     = 1
}

variable "uptime_kuma_internal_memory_mb" {
  description = "Memory in MB for internal Uptime Kuma"
  type        = number
  default     = 512
}

variable "uptime_kuma_internal_disk_size_gb" {
  description = "Disk size in GB for internal Uptime Kuma"
  type        = number
  default     = 8
}

variable "uptime_kuma_internal_ip_address" {
  description = "Static IP address for internal Uptime Kuma on Management VLAN 10 in CIDR notation"
  type        = string
  default     = "10.0.10.19/24"
}

variable "uptime_kuma_internal_gateway" {
  description = "Gateway for internal Uptime Kuma on Management VLAN 10"
  type        = string
  default     = "10.0.10.1"
}

# ---------------------------------------------------------
# Gotify Internal (LXC) — lab-03, Management VLAN 10
# ---------------------------------------------------------
# Internal push notification server. Receives alerts from all homelab
# services: uptime-kuma-internal, changedetection listing watcher, etc.
# Paired with the Hetzner Gotify (external alerts: Alertmanager, etc.).
# Accessible at https://gotify.home.example-lab.org via Traefik standalone.
# ---------------------------------------------------------

variable "gotify_vm_id" {
  description = "Proxmox VM ID for internal Gotify container"
  type        = number
  default     = 5042
}

variable "gotify_name" {
  description = "Hostname for internal Gotify container"
  type        = string
  default     = "gotify"
}

variable "gotify_cpu_cores" {
  description = "Number of CPU cores for internal Gotify (single Go binary, very lightweight)"
  type        = number
  default     = 1
}

variable "gotify_memory_mb" {
  description = "Memory in MB for internal Gotify (SQLite + Go binary)"
  type        = number
  default     = 256
}

variable "gotify_disk_size_gb" {
  description = "Disk size in GB for internal Gotify"
  type        = number
  default     = 4
}

variable "gotify_ip_address" {
  description = "Static IP address for internal Gotify on Management VLAN 10 in CIDR notation"
  type        = string
  default     = "10.0.10.20/24"
}

variable "gotify_gateway" {
  description = "Gateway for internal Gotify on Management VLAN 10"
  type        = string
  default     = "10.0.10.1"
}

# ---------------------------------------------------------
# FreshRSS (LXC) — lab-03, Services VLAN 20
# ---------------------------------------------------------
# Self-hosted RSS feed aggregator. Lightweight LXC with Docker
# Compose. Native OIDC via Authentik — each user gets their own
# feed collection. Port 80.
# ---------------------------------------------------------

variable "freshrss_vm_id" {
  description = "Proxmox VM ID for FreshRSS container"
  type        = number
  default     = 5043
}

variable "freshrss_name" {
  description = "Hostname for FreshRSS container"
  type        = string
  default     = "freshrss"
}

variable "freshrss_cpu_cores" {
  description = "Number of CPU cores for FreshRSS"
  type        = number
  default     = 1
}

variable "freshrss_memory_mb" {
  description = "Memory in MB for FreshRSS"
  type        = number
  default     = 512
}

variable "freshrss_disk_size_gb" {
  description = "Disk size in GB for FreshRSS"
  type        = number
  default     = 8
}

variable "freshrss_ip_address" {
  description = "Static IP address for FreshRSS in CIDR notation"
  type        = string
  default     = "10.0.20.21/24"
}

# ---------------------------------------------------------
# WAR Platform (VM) — lab-01
# ---------------------------------------------------------

variable "war_vm_id" {
  description = "Proxmox VM ID for WAR platform"
  type        = number
  default     = 5044
}

variable "war_name" {
  description = "Hostname for WAR platform VM"
  type        = string
  default     = "war"
}

variable "war_proxmox_node" {
  description = "Proxmox node for WAR VM placement (lab-01 — primary compute, separate from shared default lab-03)"
  type        = string
  default     = "lab-01"
}

variable "war_cpu_cores" {
  description = "Number of CPU cores for WAR platform"
  type        = number
  default     = 4
}

variable "war_memory_mb" {
  description = "Memory in MB for WAR platform (4 app services + Postgres)"
  type        = number
  default     = 8192
}

variable "war_os_disk_size_gb" {
  description = "OS disk size in GB for WAR platform"
  type        = number
  default     = 40
}

variable "war_ip_address" {
  description = "Static IP address for WAR platform in CIDR notation"
  type        = string
  default     = "10.0.20.22/24"
}
