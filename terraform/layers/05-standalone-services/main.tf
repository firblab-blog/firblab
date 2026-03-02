# =============================================================================
# Layer 05: Standalone Services
# Rover CI visualization: https://github.com/im2nguyen/rover
# =============================================================================
# Deploys standalone application services that run outside the RKE2 cluster.
# Each service gets its own VM or LXC container on the Services VLAN (20),
# except WireGuard which lives on the DMZ VLAN (30) and management-plane
# services (PBS, Authentik) which live on the Management VLAN (10).
#
#   - Ghost (LXC)       : Blog platform (Docker-in-LXC)          — lab-03
#   - FoundryVTT (VM)   : Virtual tabletop for gaming             — lab-03
#   - Roundcube (LXC)   : Webmail client (Docker-in-LXC)         — lab-03
#   - Mealie (LXC)      : Recipe manager (Docker-in-LXC)         — lab-03
#   - Actual Budget (LXC): Personal finance (Docker-in-LXC)      — lab-03
#   - WireGuard (LXC)   : Site-to-site VPN gateway (DMZ VLAN 30) — lab-03
#   - NetBox (VM)        : DCIM/IPAM infrastructure mapping       — lab-04
#   - PBS (VM)           : Proxmox Backup Server (Mgmt VLAN 10)   — lab-04
#   - PatchMon (VM)      : Linux patch monitoring (Docker-in-VM)  — lab-04
#   - Authentik (VM)     : SSO/IDP identity provider (Mgmt VLAN 10) — lab-04
#   - Vaultwarden (LXC)  : Password manager backup vault (Docker-in-LXC) — lab-03
#   - Archive (VM)        : Offline archive hub with TrueNAS NFS        — lab-04
#   - AI GPU (VM)          : GPU-accelerated AI/ML workloads (Ollama)    — lab-01
#   - Traefik Proxy (LXC): Reverse proxy for standalone services (Mgmt VLAN 10) — lab-04
# =============================================================================

# ---------------------------------------------------------
# Ghost (LXC)
# ---------------------------------------------------------

module "ghost" {
  source = "../../modules/proxmox-lxc/"

  # Identity
  name        = var.ghost_name
  description = "Ghost - Blog and publishing platform"
  vm_id       = var.ghost_vm_id
  tags        = ["ghost", "blog", "services"]

  # Proxmox placement
  proxmox_node = var.proxmox_node

  # Compute resources
  cpu_cores    = var.ghost_cpu_cores
  memory_mb    = var.ghost_memory_mb
  disk_size_gb = var.ghost_disk_size_gb
  storage_pool = var.storage_pool

  # Container configuration
  docker_enabled = true

  # Network
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag
  ip_address     = var.ghost_ip_address
  gateway        = var.gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH
  additional_ssh_key = var.ssh_public_key
}

# ---------------------------------------------------------
# FoundryVTT (VM)
# ---------------------------------------------------------

module "foundryvtt" {
  source = "../../modules/proxmox-vm/"

  # Identity
  name        = var.foundryvtt_name
  description = "FoundryVTT - Virtual tabletop for gaming"
  vm_id       = var.foundryvtt_vm_id
  tags        = ["foundryvtt", "gaming", "services"]

  # Proxmox placement
  proxmox_node = var.proxmox_node

  # Compute resources
  cpu_cores = var.foundryvtt_cpu_cores
  cpu_type  = "x86-64-v2-AES"
  memory_mb = var.foundryvtt_memory_mb

  # Storage — clone from hardened Packer template, data disk for game assets
  clone_template_vm_id = var.clone_template_vm_id
  clone_template_node  = var.clone_template_node
  os_disk_size_gb      = var.foundryvtt_os_disk_size_gb
  storage_pool         = var.storage_pool
  data_storage_pool    = var.data_storage_pool
  snippet_storage      = var.snippet_storage

  data_disks = [
    {
      interface = "scsi1"
      size_gb   = var.foundryvtt_data_disk_size_gb
    }
  ]

  # Network
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag
  ip_address     = var.foundryvtt_ip_address
  gateway        = var.gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH — guest-agent injection must target the node hosting this VM
  additional_ssh_key = var.ssh_public_key
  proxmox_ssh_host   = local.proxmox_node_ips[var.proxmox_node]
  proxmox_ssh_key    = pathexpand("~/.ssh/id_ed25519_${var.proxmox_node}")
}

# ---------------------------------------------------------
# Roundcube (LXC)
# ---------------------------------------------------------

module "roundcube" {
  source = "../../modules/proxmox-lxc/"

  # Identity
  name        = var.roundcube_name
  description = "Roundcube - Webmail client"
  vm_id       = var.roundcube_vm_id
  tags        = ["roundcube", "email", "services"]

  # Proxmox placement
  proxmox_node = var.proxmox_node

  # Compute resources
  cpu_cores    = var.roundcube_cpu_cores
  memory_mb    = var.roundcube_memory_mb
  disk_size_gb = var.roundcube_disk_size_gb
  storage_pool = var.storage_pool

  # Container configuration
  docker_enabled = true

  # Network
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag
  ip_address     = var.roundcube_ip_address
  gateway        = var.gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH
  additional_ssh_key = var.ssh_public_key
}

# ---------------------------------------------------------
# Mealie (LXC)
# ---------------------------------------------------------

module "mealie" {
  source = "../../modules/proxmox-lxc/"

  # Identity
  name        = var.mealie_name
  description = "Mealie - Recipe manager"
  vm_id       = var.mealie_vm_id
  tags        = ["mealie", "recipes", "services"]

  # Proxmox placement
  proxmox_node = var.proxmox_node

  # Compute resources
  cpu_cores    = var.mealie_cpu_cores
  memory_mb    = var.mealie_memory_mb
  disk_size_gb = var.mealie_disk_size_gb
  storage_pool = var.storage_pool

  # Container configuration
  docker_enabled = true

  # Network
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag
  ip_address     = var.mealie_ip_address
  gateway        = var.gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH
  additional_ssh_key = var.ssh_public_key
}

# ---------------------------------------------------------
# WireGuard (LXC) — DMZ VLAN 30
# ---------------------------------------------------------
# Site-to-site VPN gateway that terminates the WireGuard tunnel
# from the Hetzner gateway server. Lives on DMZ VLAN 30, NOT
# the default Services VLAN 20. Forwards tunnel traffic to
# homelab services via NAT/masquerade.
#
# No Docker needed — runs native WireGuard (wireguard-tools).
# ---------------------------------------------------------

module "wireguard" {
  source = "../../modules/proxmox-lxc/"

  # Identity
  name        = var.wireguard_name
  description = "WireGuard - Site-to-site VPN gateway to Hetzner"
  vm_id       = var.wireguard_vm_id
  tags        = ["wireguard", "vpn", "dmz"]

  # Proxmox placement
  proxmox_node = var.proxmox_node

  # Compute resources — minimal (WireGuard is very lightweight)
  cpu_cores    = var.wireguard_cpu_cores
  memory_mb    = var.wireguard_memory_mb
  disk_size_gb = var.wireguard_disk_size_gb
  storage_pool = var.storage_pool

  # Container configuration — no Docker needed
  docker_enabled = false

  # Network — DMZ VLAN 30, NOT the layer default (Services VLAN 20)
  network_bridge = var.network_bridge
  vlan_tag       = var.wireguard_vlan_tag
  ip_address     = var.wireguard_ip_address
  gateway        = var.wireguard_gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH
  additional_ssh_key = var.ssh_public_key
}

# ---------------------------------------------------------
# NetBox (VM) — lab-04
# ---------------------------------------------------------
# DCIM + IPAM infrastructure mapping platform. Provides a
# live, API-queryable inventory of all hardware, VMs, IPs,
# VLANs, and cabling. Replaces/augments CURRENT-STATE.md.
#
# Deployed as a full VM (not LXC) to get CIS L1 hardening.
# Lives on lab-04 (20GB RAM, idle node) — has its own
# proxmox_node variable since all other services default to
# lab-03.
# ---------------------------------------------------------

module "netbox" {
  source = "../../modules/proxmox-vm/"

  # Identity
  name        = var.netbox_name
  description = "NetBox - DCIM/IPAM infrastructure mapping"
  vm_id       = var.netbox_vm_id
  tags        = ["netbox", "dcim", "services"]

  # Proxmox placement — lab-04 (NOT the shared default lab-03)
  proxmox_node = var.netbox_proxmox_node

  # Compute resources
  cpu_cores = var.netbox_cpu_cores
  cpu_type  = "x86-64-v2-AES"
  memory_mb = var.netbox_memory_mb

  # Storage — clone from hardened Packer template, no data disk needed
  clone_template_vm_id = var.clone_template_vm_id
  clone_template_node  = var.clone_template_node
  os_disk_size_gb      = var.netbox_os_disk_size_gb
  storage_pool         = var.storage_pool
  snippet_storage      = var.snippet_storage

  # Network — Services VLAN 20
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag
  ip_address     = var.netbox_ip_address
  gateway        = var.gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH — guest-agent injection must target the node hosting this VM
  additional_ssh_key = var.ssh_public_key
  proxmox_ssh_host   = local.proxmox_node_ips[var.netbox_proxmox_node]
  proxmox_ssh_key    = pathexpand("~/.ssh/id_ed25519_${var.netbox_proxmox_node}")
}

# ---------------------------------------------------------
# Proxmox Backup Server (VM) — lab-04
# ---------------------------------------------------------
# Centralized backup server with content-addressable dedup.
# Replaces per-node vzdump cron scripts. All 4 PVE nodes
# back up to this PBS instance via the PBS API (port 8007).
#
# Deployed as a full VM on lab-04 (Management VLAN 10)
# for direct access from all Proxmox nodes without inter-VLAN
# routing. Uses PBS Packer template (not Ubuntu — PBS has its
# own Debian-based installer).
#
# Disk architecture:
#   - OS disk (32 GB): SSD on local-lvm — fast boot, responsive UI
#   - Data disks: Two physical HDDs passed through from lab-04
#     to the VM via qm set (scsi1 + scsi2). PBS creates a ZFS
#     mirror internally (~14.6 TB usable). Data survives VM
#     rebuilds — zpool import recovers the pool.
#
# Retention: keep-daily=7, keep-weekly=4, keep-monthly=3.
# ---------------------------------------------------------

module "pbs" {
  source = "../../modules/proxmox-vm/"

  # Identity
  name        = var.pbs_name
  description = "Proxmox Backup Server - Centralized dedup backups"
  vm_id       = var.pbs_vm_id
  tags        = ["pbs", "backup", "infra"]

  # Proxmox placement — lab-04 (same node as NetBox)
  proxmox_node = var.pbs_proxmox_node

  # Compute resources
  cpu_cores = var.pbs_cpu_cores
  cpu_type  = "x86-64-v2-AES"
  memory_mb = var.pbs_memory_mb

  # Storage — clone from PBS Packer template (9002, NOT Ubuntu 9000)
  # OS disk only — data disks are physical HDDs passed through separately
  # by terraform_data.pbs_disk_passthrough below (bpg/proxmox doesn't
  # support raw device passthrough natively).
  clone_template_vm_id = var.pbs_template_vm_id
  clone_template_node  = var.clone_template_node
  os_disk_size_gb      = var.pbs_os_disk_size_gb
  storage_pool         = var.storage_pool
  snippet_storage      = var.snippet_storage

  # Network — Management VLAN 10 (untagged on vmbr0)
  # All Proxmox nodes are on VLAN 10 — no inter-VLAN routing needed
  network_bridge = var.network_bridge
  vlan_tag       = null
  ip_address     = var.pbs_ip_address
  gateway        = var.pbs_gateway
  domain_name    = var.domain_name
  dns_servers    = ["10.0.10.1"]

  # SSH — guest-agent injection is CRITICAL for PBS (no cloud-init at all)
  # PBS uses root (no admin user exists). vm_ssh_user overrides the inject target
  # without touching cloud-init's user_account (which can't be hotplugged).
  vm_ssh_user        = "root"
  additional_ssh_key = var.ssh_public_key
  proxmox_ssh_host   = local.proxmox_node_ips[var.pbs_proxmox_node]
  proxmox_ssh_key    = pathexpand("~/.ssh/id_ed25519_${var.pbs_proxmox_node}")
}

# ---------------------------------------------------------
# PBS HDD Passthrough (Physical Disk → VM)
# ---------------------------------------------------------
# Attaches physical HDDs from lab-04 to the PBS VM as
# scsi1 and scsi2. The bpg/proxmox Terraform provider does
# NOT support raw device passthrough — only LVM/ZFS/directory
# storage pools. So we use the same local-exec pattern as
# inject-ssh-keys.sh: SSH to the Proxmox node, run qm set.
#
# The script stops the VM, attaches disks, restarts it, and
# waits for the guest agent. Disks use /dev/disk/by-id/ paths
# for stable identification across reboots.
#
# To discover disk-by-id paths on lab-04:
#   ssh admin@10.0.10.4 'ls -la /dev/disk/by-id/ | grep ata- | grep -v part'
# ---------------------------------------------------------

resource "terraform_data" "pbs_disk_passthrough" {
  count = length(var.pbs_passthrough_disks) > 0 ? 1 : 0

  # Re-run if VM is recreated or disk list changes
  triggers_replace = [
    module.pbs.vm_id,
    join(",", var.pbs_passthrough_disks),
  ]

  depends_on = [module.pbs]

  provisioner "local-exec" {
    command     = "${path.module}/../../modules/proxmox-vm/scripts/attach-passthrough-disks.sh"
    interpreter = ["bash", "-c"]

    environment = {
      PROXMOX_HOST    = local.proxmox_node_ips[var.pbs_proxmox_node]
      PROXMOX_USER    = "admin"
      PROXMOX_SSH_KEY = pathexpand("~/.ssh/id_ed25519_${var.pbs_proxmox_node}")
      VM_ID           = module.pbs.vm_id
      DISK_LIST       = join(",", var.pbs_passthrough_disks)
    }
  }
}

# ---------------------------------------------------------
# Authentik (VM) — lab-04, Management VLAN 10
# ---------------------------------------------------------
# Centralized SSO/IDP (OIDC, SAML, LDAP, SCIM) for all
# homelab services. Runs as a CIS-hardened VM (not LXC) —
# highest-value target that holds credentials and issues
# tokens for every service.
#
# Docker Compose: PostgreSQL + server + worker containers
# (only officially supported non-K8s deployment method).
# Direct HTTP access on port 9000 — no Traefik proxy.
# DNS resolves auth.home.example-lab.org → 10.0.10.16.
# ---------------------------------------------------------

module "authentik" {
  source = "../../modules/proxmox-vm/"

  # Identity
  name        = var.authentik_name
  description = "Authentik - Identity Provider (SSO/OIDC/SAML)"
  vm_id       = var.authentik_vm_id
  tags        = ["authentik", "sso", "infra"]

  # Proxmox placement — lab-01 (migrated from lab-04, PBS-restored)
  proxmox_node = var.authentik_proxmox_node

  # Compute resources
  cpu_cores = var.authentik_cpu_cores
  cpu_type  = "x86-64-v2-AES"
  memory_mb = var.authentik_memory_mb

  # Storage — PBS-restored to nvme-thin-1 on lab-01
  clone_template_vm_id = var.clone_template_vm_id
  clone_template_node  = var.clone_template_node
  os_disk_size_gb      = var.authentik_os_disk_size_gb
  storage_pool         = var.authentik_storage_pool
  snippet_storage      = var.snippet_storage

  # Network — Management VLAN 10 (untagged on vmbr0, like PBS)
  network_bridge = var.network_bridge
  vlan_tag       = null
  ip_address     = var.authentik_ip_address
  gateway        = var.authentik_gateway
  domain_name    = var.domain_name
  dns_servers    = ["10.0.10.1"]

  # SSH — guest-agent injection must target the node hosting this VM
  additional_ssh_key = var.ssh_public_key
  proxmox_ssh_host   = local.proxmox_node_ips[var.authentik_proxmox_node]
  proxmox_ssh_key    = pathexpand("~/.ssh/id_ed25519_${var.authentik_proxmox_node}")
}

# ---------------------------------------------------------
# PatchMon (VM) — lab-04, Services VLAN 20
# ---------------------------------------------------------
# Enterprise-grade Linux patch monitoring platform. Lightweight
# agents on all Linux hosts report outbound-only to this server.
# Provides fleet visibility: packages, compliance, Docker, SSH.
#
# Docker Compose: PostgreSQL 17 + Redis 7 + backend + frontend.
# Deployed as a CIS-hardened VM (sensitive infra monitoring).
# OIDC with Authentik for SSO (both on lab-04).
# ---------------------------------------------------------

module "patchmon" {
  source = "../../modules/proxmox-vm/"

  # Identity
  name        = var.patchmon_name
  description = "PatchMon - Linux patch monitoring and fleet management"
  vm_id       = var.patchmon_vm_id
  tags        = ["patchmon", "monitoring", "services"]

  # Proxmox placement — lab-04
  proxmox_node = var.patchmon_proxmox_node

  # Compute resources
  cpu_cores = var.patchmon_cpu_cores
  cpu_type  = "x86-64-v2-AES"
  memory_mb = var.patchmon_memory_mb

  # Storage — clone from hardened Packer template
  clone_template_vm_id = var.clone_template_vm_id
  clone_template_node  = var.clone_template_node
  os_disk_size_gb      = var.patchmon_os_disk_size_gb
  storage_pool         = var.storage_pool
  snippet_storage      = var.snippet_storage

  # Network — Services VLAN 20
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag
  ip_address     = var.patchmon_ip_address
  gateway        = var.gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH — guest-agent injection must target the node hosting this VM
  additional_ssh_key = var.ssh_public_key
  proxmox_ssh_host   = local.proxmox_node_ips[var.patchmon_proxmox_node]
  proxmox_ssh_key    = pathexpand("~/.ssh/id_ed25519_${var.patchmon_proxmox_node}")
}

# ---------------------------------------------------------
# Actual Budget (LXC) — lab-03, Services VLAN 20
# ---------------------------------------------------------
# Local-first personal finance app with envelope budgeting.
# Ultra-lightweight: single container, SQLite backend, no
# external database. Data syncs across devices via built-in
# sync server.
#
# Deployed as an LXC (Docker-in-LXC) — same pattern as
# Ghost, Mealie, Roundcube.
# ---------------------------------------------------------

module "actualbudget" {
  source = "../../modules/proxmox-lxc/"

  # Identity
  name        = var.actualbudget_name
  description = "Actual Budget - Personal finance and envelope budgeting"
  vm_id       = var.actualbudget_vm_id
  tags        = ["actualbudget", "finance", "services"]

  # Proxmox placement
  proxmox_node = var.proxmox_node

  # Compute resources
  cpu_cores    = var.actualbudget_cpu_cores
  memory_mb    = var.actualbudget_memory_mb
  disk_size_gb = var.actualbudget_disk_size_gb
  storage_pool = var.storage_pool

  # Container configuration
  docker_enabled = true

  # Network
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag
  ip_address     = var.actualbudget_ip_address
  gateway        = var.gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH
  additional_ssh_key = var.ssh_public_key
}

# ---------------------------------------------------------
# Traefik Reverse Proxy (LXC) — lab-04, Management VLAN 10
# ---------------------------------------------------------
# Standalone Traefik v3 reverse proxy for ALL non-K8s services.
# TLS termination via Let's Encrypt DNS-01 (Cloudflare). Routes
# traffic to both management (VLAN 10) and services (VLAN 20)
# backends. ForwardAuth via Authentik for services without native
# OIDC support.
#
# Deployed as an LXC with Docker (same pattern as Ghost, Mealie).
# Lives on Management VLAN 10 for direct L2 access to management
# services (GitLab, Authentik, PBS) without inter-VLAN routing
# on the backend path. Reaches VLAN 20 services via gw-01
# routing (zone policy already allows VLAN 10 → VLAN 20).
#
# Architecture split:
#   K8s Traefik (10.0.20.220) → K8s workloads only
#   This proxy (10.0.10.17)   → ALL standalone + mgmt services
# ---------------------------------------------------------

module "traefik_proxy" {
  source = "../../modules/proxmox-lxc/"

  # Identity
  name        = var.traefik_proxy_name
  description = "Traefik - Reverse proxy for standalone and management services"
  vm_id       = var.traefik_proxy_vm_id
  tags        = ["traefik", "proxy", "infra"]

  # Proxmox placement — lab-04 (same node as Authentik, PBS, NetBox)
  proxmox_node = var.traefik_proxy_proxmox_node

  # Compute resources — lightweight (Traefik is very efficient)
  cpu_cores    = var.traefik_proxy_cpu_cores
  memory_mb    = var.traefik_proxy_memory_mb
  disk_size_gb = var.traefik_proxy_disk_size_gb
  storage_pool = var.storage_pool

  # Container configuration
  docker_enabled = true

  # Network — Management VLAN 10 (untagged on vmbr0, like PBS + Authentik)
  network_bridge = var.network_bridge
  vlan_tag       = null
  ip_address     = var.traefik_proxy_ip_address
  gateway        = var.traefik_proxy_gateway
  domain_name    = var.domain_name
  dns_servers    = ["10.0.10.1"]

  # SSH
  additional_ssh_key = var.ssh_public_key
}

# ---------------------------------------------------------
# Vaultwarden (LXC) — lab-03, Services VLAN 20
# ---------------------------------------------------------
# Self-hosted password vault (Bitwarden-compatible). Serves as
# a backup mirror for 1Password data. Single container, SQLite
# backend, extremely lightweight. Authentik OIDC SSO with master
# password fallback (SSO_ONLY=false).
#
# Deployed as an LXC (Docker-in-LXC) — same pattern as
# Ghost, Mealie, Actual Budget.
# ---------------------------------------------------------

module "vaultwarden" {
  source = "../../modules/proxmox-lxc/"

  # Identity
  name        = var.vaultwarden_name
  description = "Vaultwarden - Self-hosted password manager (1Password backup)"
  vm_id       = var.vaultwarden_vm_id
  tags        = ["vaultwarden", "security", "services"]

  # Proxmox placement
  proxmox_node = var.proxmox_node

  # Compute resources
  cpu_cores    = var.vaultwarden_cpu_cores
  memory_mb    = var.vaultwarden_memory_mb
  disk_size_gb = var.vaultwarden_disk_size_gb
  storage_pool = var.storage_pool

  # Container configuration
  docker_enabled = true

  # Network
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag
  ip_address     = var.vaultwarden_ip_address
  gateway        = var.gateway
  domain_name    = var.domain_name
  dns_servers    = var.dns_servers

  # SSH
  additional_ssh_key = var.ssh_public_key
}

# ---------------------------------------------------------
# Archive — REMOVED from Proxmox
# ---------------------------------------------------------
# Archive hub is moving to a dedicated ZimaBlade 7700 device
# (bare metal, not a Proxmox VM). Ansible role + playbook
# retained for reuse on the new hardware.
# VM 5034 on lab-04 destroyed via terraform apply.
# ---------------------------------------------------------

# ---------------------------------------------------------
# AI GPU (VM) — REMOVED 2026-02-25
# ---------------------------------------------------------
# VM 5035 destroyed — intermittent fan runaway (GPU/case fans
# hitting 100% under load). Ansible roles retained in
# ansible/roles/ai-gpu/ and ansible/roles/proxmox-gpu/ for
# future reuse. lab-01 IOMMU/VFIO host config left in place.
# ---------------------------------------------------------

# ---------------------------------------------------------
# Backup (LXC) — lab-01, Management VLAN 10
# ---------------------------------------------------------
# Centralized Restic REST server + Backrest monitoring UI.
# Stores backup data on hdd-mirror-0 (ZFS mirror, ~3.6TB)
# via host bind mount. No Docker needed — both rest-server
# and Backrest are standalone Go binaries as systemd units.
#
# Bind mount (mp0) is added via terraform_data below because
# the bpg/proxmox provider requires root@pam for bind mounts
# and we authenticate with terraform@pam API tokens.
# Same pattern as PBS disk passthrough.
# ---------------------------------------------------------

module "backup" {
  source = "../../modules/proxmox-lxc/"

  # Identity
  name        = var.backup_name
  description = "Backup - Restic REST server + Backrest monitoring UI"
  vm_id       = var.backup_vm_id
  tags        = ["backup", "restic", "infra"]

  # Proxmox placement — lab-01 (where hdd-mirror-0 lives)
  proxmox_node = var.backup_proxmox_node

  # Compute resources — lightweight (Go binaries, no DB)
  cpu_cores    = var.backup_cpu_cores
  memory_mb    = var.backup_memory_mb
  disk_size_gb = var.backup_disk_size_gb
  storage_pool = var.storage_pool

  # Container configuration — NO Docker needed
  docker_enabled = false

  # Network — Management VLAN 10 (untagged on vmbr0, like PBS + Authentik)
  network_bridge = var.network_bridge
  vlan_tag       = null
  ip_address     = var.backup_ip_address
  gateway        = var.backup_gateway
  domain_name    = var.domain_name
  dns_servers    = ["10.0.10.1"]

  # SSH
  additional_ssh_key = var.ssh_public_key

  # Startup — backup infra should start early (after storage, before services)
  startup_order = "2"
}

# ---------------------------------------------------------
# Backup LXC Bind Mount (Host ZFS → Container)
# ---------------------------------------------------------
# Attaches /hdd-mirror-0/restic from lab-01 into the
# backup LXC as /mnt/restic. Uses the same local-exec pattern
# as PBS disk passthrough because bpg/proxmox requires root@pam
# for bind mounts and we use API token auth.
#
# pct set <vmid> -mp0 <host_path>,mp=<container_path>
# ---------------------------------------------------------

resource "terraform_data" "backup_bind_mount" {
  # Re-run if LXC is recreated or mount paths change
  triggers_replace = [
    module.backup.container_id,
    var.backup_host_mount_path,
    var.backup_container_mount_path,
  ]

  depends_on = [module.backup]

  provisioner "local-exec" {
    command     = "${path.module}/../../modules/proxmox-lxc/scripts/attach-bind-mount.sh"
    interpreter = ["bash", "-c"]

    environment = {
      PROXMOX_HOST    = local.proxmox_node_ips[var.backup_proxmox_node]
      PROXMOX_USER    = "admin"
      PROXMOX_SSH_KEY = pathexpand("~/.ssh/id_ed25519_${var.backup_proxmox_node}")
      CONTAINER_ID    = module.backup.container_id
      HOST_PATH       = var.backup_host_mount_path
      CONTAINER_PATH  = var.backup_container_mount_path
    }
  }
}

# ---------------------------------------------------------
# Uptime Kuma Internal (LXC) — lab-03, Management VLAN 10
# ---------------------------------------------------------
# Internal homelab monitoring. Lives on Management VLAN 10 for
# direct access to Vault, Proxmox, and all homelab VLANs.
# Port 3001 — Traefik proxies as status.home.example-lab.org.
# Paired with the public Uptime Kuma on the Hetzner gateway
# which monitors public-facing *.example-lab.org services only.
# ---------------------------------------------------------

module "uptime_kuma_internal" {
  source = "../../modules/proxmox-lxc/"

  # Identity
  name        = var.uptime_kuma_internal_name
  description = "Uptime Kuma (Internal) - Homelab service health monitoring"
  vm_id       = var.uptime_kuma_internal_vm_id
  tags        = ["uptime-kuma", "monitoring", "infra"]

  # Proxmox placement — lab-03 (most headroom: 44% memory)
  proxmox_node = var.proxmox_node

  # Compute resources — lightweight (Node.js, SQLite, no external DB)
  cpu_cores    = var.uptime_kuma_internal_cpu_cores
  memory_mb    = var.uptime_kuma_internal_memory_mb
  disk_size_gb = var.uptime_kuma_internal_disk_size_gb
  storage_pool = var.storage_pool

  # Container configuration
  docker_enabled = true

  # Network — Management VLAN 10 (untagged on vmbr0, like Traefik proxy + backup)
  network_bridge = var.network_bridge
  vlan_tag       = null
  ip_address     = var.uptime_kuma_internal_ip_address
  gateway        = var.uptime_kuma_internal_gateway
  domain_name    = var.domain_name
  # Override layer-wide DNS: must resolve *.home.example-lab.org (UDM Pro serves
  # this zone on all VLAN interfaces; use the Management VLAN 10 gateway).
  dns_servers    = ["10.0.10.1"]

  # SSH
  additional_ssh_key = var.ssh_public_key

  # Startup — monitoring should come up after core services
  startup_order = "3"
}
