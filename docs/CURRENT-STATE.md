# FirbLab Current State Inventory

Last updated: 2026-03-03 (GitHub public repo security hardened via Terraform — branch protection, Dependabot, settings)

This document is the **source of truth** for what is actually deployed and running in the homelab. It reflects real Terraform state, Ansible inventory, and verified infrastructure — not aspirational plans.

For the planned architecture and deployment sequence, see [DEPLOYMENT.md](DEPLOYMENT.md) and [ARCHITECTURE.md](ARCHITECTURE.md).
For proxy URLs, direct-access IPs, and emergency fallback commands, see [SERVICE-DIRECTORY.md](SERVICE-DIRECTORY.md) (auto-generated from IaC).

---

## Table of Contents

- [Physical Hardware](#physical-hardware)
- [Network Infrastructure](#network-infrastructure)
- [Vault Cluster](#vault-cluster)
- [Core Infrastructure](#core-infrastructure)
- [RKE2 Kubernetes Cluster](#rke2-kubernetes-cluster)
- [Standalone Services](#standalone-services)
- [DMZ Services](#dmz-services)
- [Hetzner Gateway](#hetzner-gateway)
- [Terraform Layer Status](#terraform-layer-status)
- [Ansible Automation Coverage](#ansible-automation-coverage)
- [Known Issues and Gaps](#known-issues-and-gaps)
- [Pending Work](#pending-work)

---

## Physical Hardware

### Proxmox Cluster Nodes

| Node | Hardware | RAM | IP | VLAN | Switch Port | Port Profile | Role |
|------|----------|-----|-----|------|-------------|-------------|------|
| lab-01 | i9-12900K, 64 GB + Mellanox CX4121C (dual SFP28) | 64 GB | 10.0.10.42 | 10 (Mgmt) | Pro XG 8 SFP+ 1 (port 9) | Proxmox Trunk | Main compute — RKE2 cluster (6 VMs). 10G via Mellanox CX4121C SFP28 Port 1 (DAC to switch-04 SFP+ 1). Mellanox Port 2: 10G point-to-point DAC to TrueNAS (vmbr1, 10.10.10.1/30). |
| lab-02 | Intel N100 | 16 GB | 10.0.10.2 | 10 (Mgmt) | Minilab Port 4 | Proxmox Trunk | Pilot — Runner, vault-2 (GitLab moved to lab-01 2026-03-01) |
| lab-03 | Intel N100 | 12 GB | 10.0.10.3 | 10 (Mgmt) | Minilab Port 1 | Proxmox Trunk | Lightweight services — Ghost, Roundcube, Mealie, WireGuard |
| lab-04 | Dell Wyse J5005 | 20 GB | 10.0.10.4 | 10 (Mgmt) | Closet Port 3 | Proxmox Trunk | Lightweight compute — NetBox, PBS |

### Bare-Metal / Special Purpose

| Device | Hardware | IP | VLAN | Switch Port | Port Profile | Role |
|--------|----------|-----|------|-------------|-------------|------|
| vault-1 / Mac Mini | Apple M4 | 10.0.10.10 | 10 (Mgmt) | Minilab Port 3 | Management Access | Vault primary (macOS native LaunchDaemon) |
| vault-3 / RPi5 CM5 | RPi5 CM5, 16 GB | 10.0.10.13 | 10 (Mgmt) | Minilab Port 5 | Management Access | Vault standby (Ubuntu 24.04 ARM64) |
| lab-08 / RPi4 | RPi4, 8 GB | 10.0.4.20 | 1 (Default) | Closet Port 4 | Scanner Trunk | Scanopy network scanner + NUT UPS server (Raspberry Pi OS Lite ARM64, NVMe boot via USB enclosure). VLAN sub-interfaces: .90 on VLANs 10/20/30/40/50. |
| lab-10 / TrueNAS | i5-9500, 16 GB (Dell OptiPlex 3070) + Mellanox CX4121C (dual SFP28) | 10.0.40.2 + 10.10.10.2 | 40 (Storage) + PtP | Closet Port 2 (1GbE) + PtP DAC | Storage Access | NFS/SMB, Plex, Immich, Paperless-NGX, Linkwarden, PostgreSQL, ZFS backups, Mail Archiver (port 30315), IT Tools (port 30063), SearXNG (port 30053). Pools: media (~12 TB mirror), backups (~8 TB mirror). Mellanox Port 2: 10G point-to-point DAC to lab-01 (10.10.10.2/30). Mellanox Port 1: idle (no SFP+ ports available on nearby switches). Ansible-managed via arensb.truenas collection. |
| JetKVM | KVM-over-IP | (DHCP) | 10 (Mgmt) | Minilab Port 2 | Management Access | Remote console for Mac Mini |
| lab-09 / ZimaBlade | ZimaBlade 7700 (E3950, 16 GB), MAC 52:54:00:11:22:09 | 10.0.20.20 | 20 (Services) | Rackmate Port 4 | Services Access | Prepper archive appliance: Kiwix, ArchiveBox, BookStack, Stirling PDF, Wallabag, FileBrowser. 2TB USB SSD + PS4 HDD. |
| k3s-server-1 / RPi5 | Raspberry Pi 5 8GB, NVMe boot | 10.0.20.60 | 20 (Services) | Rackmate Port 1 | Services Access | K3s cluster server node (Ubuntu 24.04 ARM64). HA etcd quorum member. |
| k3s-server-2 / RPi5 | Raspberry Pi 5 8GB, NVMe boot | 10.0.20.61 | 20 (Services) | Rackmate Port 2 | Services Access | K3s cluster server node (Ubuntu 24.04 ARM64). HA etcd quorum member. |
| k3s-server-3 / RPi5 | Raspberry Pi 5 4GB, NVMe boot | 10.0.20.62 | 20 (Services) | Rackmate Port 3 | Services Access | K3s cluster server node (Ubuntu 24.04 ARM64). HA etcd quorum member. |
| gw-01 | Ubiquiti UCG-Fiber | 10.0.4.1 | 1 (Default) | — | — | Core router, firewall, DHCP for all VLANs. 2x SFP+ 10G, 4x 2.5G, 1x 10GBase-T. |

### Network Switches

| Switch | Model | MAC | Uplink | Location |
|--------|-------|-----|--------|----------|
| switch-01 | USW Flex 2.5G 5-port | 52:54:00:11:22:01 | Port 5 → gw-01 2.5G Port 1 | Closet |
| switch-02 | USW Flex 2.5G 8 (10 physical ports) | 52:54:00:11:22:02 | Port 9 → gw-01 2.5G Port 2 | Minilab desk |
| switch-03 | USW Flex 2.5G 5-port | 52:54:00:11:22:03 | Port 5 → gw-01 2.5G Port 3 | Rackmate |
| switch-04 | USW Pro XG 8 PoE | 52:54:00:11:22:04 | SFP+ 1 → gw-01 SFP+ 1 (10G DAC) | Closet |

---

## Network Infrastructure

**Managed by:** Terraform Layer 00 (`terraform/layers/00-network/`)
**Status:** ✅ Deployed and active

### VLANs

| VLAN | Name | Subnet | Gateway | DHCP Range | Status |
|------|------|--------|---------|------------|--------|
| 1 | Default/LAN | 10.0.4.0/24 | 10.0.4.1 | .100-.254 | ✅ Active |
| 10 | Management | 10.0.10.0/24 | 10.0.10.1 | .100-.200 | ✅ Active |
| 20 | Services | 10.0.20.0/24 | 10.0.20.1 | .100-.200 | ✅ Active |
| 30 | DMZ | 10.0.30.0/24 | 10.0.30.1 | .100-.200 | ✅ Active |
| 40 | Storage | 10.0.40.0/24 | 10.0.40.1 | .100-.200 | ✅ Active (no hosts assigned yet) |
| 50 | Security | 10.0.50.0/24 | 10.0.50.1 | .100-.200 | ✅ Active |
| 60 | IoT | 10.0.60.0/24 | 10.0.60.1 | .100-.200 | ✅ Active |

### Firewall Zones (7)

Management, Services, DMZ, Storage, Security, LAN, IoT — all deployed via Terraform.

### Zone Policies (37 total)

See [NETWORK.md](NETWORK.md) for the full policy matrix. Key policies:

- Management → all VLANs: ALLOW (admin control plane)
- LAN → all VLANs: ALLOW (workstation admin access)
- DMZ → Services: ALLOW (port-filtered: 80, 443, 2368, 8888, 9000, 30000)
- Services → DMZ: ALLOW (return traffic — zone policies are stateless)
- DMZ ↔ Management: ALLOW (bidirectional, for SSH/Ansible)
- Services → Storage: ALLOW (NFS 2049/111, iSCSI 3260)
- Services → Security: ALLOW (Vault 8200, GitLab 22/80/443, Wazuh 1514/1515)
- Management ↔ IoT: ALLOW (admin access, Traefik proxy, Authentik OIDC)
- LAN ↔ IoT: ALLOW (workstation access to HA dashboard)
- Services ↔ IoT: ALLOW (Prometheus scraping, return traffic)
- DMZ → IoT: BLOCK
- IoT → DMZ: BLOCK
- IoT → Storage: BLOCK
- IoT → Security: BLOCK
- DMZ → Storage: BLOCK
- DMZ → Security: BLOCK

### Port Profiles (6)

| Profile | Native VLAN | Tagged VLANs | Assigned To |
|---------|-------------|--------------|-------------|
| Proxmox Trunk | 10 | 20, 30, 40, 50 | lab-01, -02, -03, -04 |
| Management Access | 10 | None | Mac Mini, RPi5 CM5, JetKVM |
| Services Access | 20 | None | lab-09 (ZimaBlade) |
| Storage Access | 40 | None | TrueNAS |
| Scanner Trunk | 1 (Default LAN) | 10, 20, 30, 40, 50 | lab-08 (Scanopy scanner) |
| IoT Access | 60 | None | lab-11 / CM4 8GB (Home Assistant) |

### Point-to-Point Storage Link (10G, non-switched)

Dedicated 10 Gbps DAC link for NFS/iSCSI storage traffic between lab-01 and TrueNAS. Bypasses switch fabric entirely.

| Endpoint | Interface | Bridge | IP | Peer | MTU |
|----------|-----------|--------|-----|------|-----|
| lab-01 | Mellanox CX4121C Port 2 | vmbr1 (non-VLAN-aware) | 10.10.10.1/30 | TrueNAS | 9000 |
| TrueNAS | Mellanox CX4121C Port 2 | — | 10.10.10.2/30 | lab-01 | 9000 |

**IaC:** `proxmox_storage_bridge_ports` / `proxmox_storage_ip` in `host_vars/lab-01.yml`, template `proxmox-interfaces.j2`. TrueNAS side configured via `playbooks/truenas-storage-link.yml`.
**NFS Storage:** `truenas-10g` registered on lab-01 via Terraform Layer 01 (`storage.tf`) — NFS mount at `10.10.10.2:/mnt/backups/lab-01` over 10G DAC. Content types: backup, iso, vztmpl, snippets. NFS export ACL includes `10.10.10.0/30` (Ansible: `truenas` role defaults).
**Note:** Uses `10.10.10.0/30` (not a VLAN 40 subset) because TrueNAS middleware rejects overlapping networks across interfaces.

### Internal DNS (`*.home.example-lab.org`)

**Managed by:** Terraform Layer 00 (`dns.tf`) — `unifi_dns_record` resources
**Status:** ✅ Applied 2026-02-15

All internal services are accessible via `<service>.home.example-lab.org`. The gw-01's built-in DNS forwarder serves these records to all DHCP clients — no separate DNS server needed.

**3-way DNS split:**
- **RKE2 K8s workloads** → RKE2 Traefik MetalLB VIP (`10.0.20.220`) — Headlamp, Longhorn, ArgoCD, GitLab-test, Wazuh Dashboard
- **K3s workloads** → K3s Traefik MetalLB VIP (`10.0.20.200`) — Grafana (monitoring stack)
- **Standalone + management services** → Standalone Traefik proxy (`10.0.10.17`) — Ghost, Roundcube, FoundryVTT, Mealie, NetBox, PatchMon, Actual Budget, Vaultwarden, Open WebUI, n8n, GitLab, Authentik, PBS, TrueNAS, Immich, Linkwarden, Paperless, Plex, Portracker, Mail Archiver, IT Tools, SearXNG, Proxmox UIs (pve-01–04)
- **Direct access** → own IPs (Vault only — own CA-signed TLS, tools connect by IP)

**TLS Certificate Issuers:**
- `letsencrypt-dns` ClusterIssuer — Let's Encrypt DNS-01 via Cloudflare API (user-facing `*.home.example-lab.org`)
- `vault-issuer` ClusterIssuer — Vault PKI (M2M TLS, retained for ESO/cert-manager internal use)

**Note:** Domain migrated from `.example-lab.local` to `.home.example-lab.org`. The `.local` TLD is reserved for mDNS (RFC 6762) and caused 5-second lookup delays on macOS.

### WiFi Networks

**Managed by:** Terraform Layer 00 (`wifi.tf`)
**Status:** ✅ Applied

| SSID | VLAN | Security | Bands | L2 Isolation | Notes |
|------|------|----------|-------|-------------|-------|
| Fellowship of the Ping | 60 (IoT) | WPA2/WPA3 transitional | 2.4 + 5 GHz | Yes | IoT devices, passphrase in Vault |

**AP:** U7 Pro (10.0.4.133, switch-04 Port 2, 2.5 GbE uplink, PoE++)

### CyberSecure / IDS/IPS

**Managed by:** Terraform Layer 00 (`security.tf`) + manual UI for provider-bugged features
**Status:** ✅ All active features configured (Terraform + manual UI)

| Feature | Status | Details |
|---------|--------|---------|
| Intrusion Prevention (IPS) | ✅ Applied | Active blocking on all 7 VLANs (Terraform) |
| Deep Packet Inspection | ✅ Applied | App identification + fingerprinting (Terraform) |
| Torrent Blocking | ✅ Applied | Site-wide (Terraform) |
| SSL Inspection | ✅ Applied | Off — TLS managed at app layer (Terraform) |
| Ad Blocking | ✅ Configured | IoT (VLAN 60) + Default LAN (VLAN 1) via UI (provider bug) |
| Region Blocking | ✅ Configured | RU, CN, KP, IR + additional countries via UI (no provider resource) |
| DNS Content Filter | — | Not configured (skipped for now) |
| Encrypted DNS | — | Not configured |
| Per-App Blocking | — | Not configured |

---

## Vault Cluster

**Managed by:** Terraform Layers 02-vault-infra + 02-vault-config, Ansible vault-deploy.yml
**Status:** ✅ Deployed and operational (3-node Raft, auto-unseal working)

### Nodes

| Node | IP | VLAN | Platform | OS | Role | Managed By |
|------|-----|------|----------|-----|------|-----------|
| vault-1 | 10.0.10.10 | 10 (Mgmt) | Mac Mini M4 | macOS 15+ | Primary (leader) | Ansible (LaunchDaemon) |
| vault-2 | 10.0.50.2 | 50 (Security) | Proxmox VM (lab-02), ID 2001 | Rocky Linux 9 | Standby | Terraform + Ansible |
| vault-3 | 10.0.10.13 | 10 (Mgmt) | RPi5 CM5 bare metal | Ubuntu 24.04 ARM64 | Standby | Ansible |

### Vault Configuration

| Setting | Value |
|---------|-------|
| Version | 1.21.3 |
| Storage | Integrated Raft |
| API Port | 8200 |
| Cluster Port | 8201 |
| TLS | Enabled (min TLS 1.2) |
| UI | Enabled |
| Audit | File (/var/log/vault/audit.log) |
| Seal | Transit auto-unseal via unseal Vault (Mac Mini port 8210) |

### Secrets Engines & Auth

| Engine/Backend | Path | Purpose |
|----------------|------|---------|
| KV v2 | secret/ | All infrastructure and service secrets |
| PKI Root CA | pki/ | Root CA (10-year TTL) |
| PKI Intermediate | pki_int/ | Issues certs for services (24h default, 90d max) |
| AppRole | auth/approle | GitLab CI/CD (role: gitlab-ci, 1h TTL) |
| Kubernetes (RKE2) | auth/kubernetes | RKE2 ESO + cert-manager (roles: external-secrets, cert-manager) |
| Kubernetes (K3s) | auth/kubernetes-k3s | K3s ESO + cert-manager (roles: k3s-external-secrets, k3s-cert-manager) |

### Secret Taxonomy (seeded by Layer 02-vault-config)

```
secret/
├── infra/proxmox/{lab-01,lab-02,lab-03,lab-04}/
├── infra/unifi/
├── infra/hetzner/
├── infra/cloudflare/
├── services/gitlab/admin
├── services/gitlab/runner
├── services/gitlab/approle
├── services/gitlab/image-updater  # username, token (deploy token for ArgoCD Image Updater Git write-back)
├── services/wireguard/peer1
├── services/sonarqube          # REMOVED — SonarQube deleted from RKE2 cluster
├── services/netbox             # db_password, secret_key, superuser_password, api_token, redis passwords (Ansible-generated)
├── services/authentik          # secret_key, postgresql_password, bootstrap_password, bootstrap_token (Terraform random_password)
├── services/gitlab/oidc        # client_id, client_secret (Layer 07 — Authentik OIDC for GitLab CE)
├── services/vault/oidc         # client_id, client_secret (Layer 07 — Authentik OIDC for Vault UI)
├── services/proxmox/oidc       # client_id, client_secret (Layer 07 — Authentik OIDC for Proxmox VE)
├── services/netbox/oidc        # client_id, client_secret (Layer 07 — Authentik OIDC for NetBox)
├── services/mealie/oidc        # client_id, client_secret (Layer 07 — Authentik OIDC for Mealie)
├── services/patchmon           # postgres_password, redis_password, jwt_secret (Layer 02); admin_email, admin_password, enrollment_token_key, enrollment_token_secret (Ansible onboarding via /api/v1/auth/login + /api/v1/auto-enrollment/tokens)
├── services/patchmon/oidc      # client_id, client_secret (Layer 07 — Authentik OIDC for PatchMon)
├── services/vaultwarden        # admin_token (Layer 02 — Terraform random_password)
├── services/vaultwarden/oidc   # client_id, client_secret (Layer 07 — Authentik OIDC for Vaultwarden)
├── services/openwebui          # secret_key (Layer 02 — Terraform random_password, JWT signing)
├── services/openwebui/oidc     # client_id, client_secret (Layer 07 — Authentik OIDC for Open WebUI)
├── services/n8n                # encryption_key (Layer 02 — Terraform random_password), admin_email, admin_password (manual — owner account setup)
├── services/scanopy            # db_password, admin_email, admin_password, daemon_network_id, daemon_api_key (Ansible-generated)
├── services/nut                # monitor_password, admin_password (Ansible-generated)
├── backup/age-key              # public_key (age encryption for all backup automation)
├── backup/vault                # token (Vault backup token for raft snapshot)
├── backup/restic               # repo_password, firblab02_pass, firblab03_pass, firblab04_pass (Restic REST server htpasswd + repo encryption)
├── k8s/grafana                 # username, password (Terraform random_password, synced by ESO)
├── k8s/grafana-oidc            # client_id, client_secret (Layer 07 — Authentik OIDC for Grafana, synced by ESO)
├── k8s/argocd-oidc             # client_id, client_secret (Layer 07 — Authentik OIDC for ArgoCD, synced by ESO)
├── k8s/headlamp-oidc           # client_id, client_secret (Layer 07 — Authentik OIDC for Headlamp, synced by ESO)
├── k8s/longhorn                # username, password (Terraform random_password, synced by ESO)
├── k8s/longhorn-s3             # s3_access_key, s3_secret_key, s3_endpoint (Longhorn S3 backup, synced by ESO)
├── k8s/gitlab                  # root_password (Terraform random_password, synced by ESO — GitLab CE Helm testing instance)
└── k8s/wazuh                   # api_password, agent_enrollment_password (Terraform random_password, synced by ESO)
```

---

## Core Infrastructure

**Managed by:** Terraform Layers 03 + 05, Ansible gitlab-deploy.yml + authentik-deploy.yml
**Status:** ✅ Deployed and operational

### Services

| Service | Type | VM ID | IP | VLAN | Proxmox Node | CPU | RAM | Disk |
|---------|------|-------|-----|------|-------------|-----|-----|------|
| GitLab CE | VM | 3001 | 10.0.10.50 | 10 (Mgmt, untagged) | lab-01 | 4 | 8 GB | 80 GB OS + 50 GB data (both on nvme-thin-1). PBS-restored from lab-02 2026-03-01. |
| GitLab Runner | LXC | 3002 | 10.0.10.51 | 10 (Mgmt, untagged) | lab-02 | 2 | 4 GB | 40 GB |
| Authentik | VM | 5021 | 10.0.10.16 | 10 (Mgmt, untagged) | lab-01 | 2 | 4 GB | 40 GB (nvme-thin-1). PBS-restored from lab-04 backup, fresh DB + Layer 07 re-applied 2026-03-01. |

### Authentik SSO Configuration (Layer 07-authentik-config)

**Status:** ✅ Applied 2026-03-01 — fresh DB + full Layer 07 re-apply. 12 OIDC providers, 5 ForwardAuth proxies, 11 bookmark apps, 2 groups, embedded outpost. All OIDC client_secrets regenerated and written to Vault. Downstream services re-credentialed via deploy playbooks (GitLab, Actual Budget, PatchMon, Vaultwarden, Open WebUI) and ExternalSecrets (ArgoCD, Grafana).

| Provider Type | Service | Client ID | Vault Path | SSO Wired | Status |
|--------------|---------|-----------|------------|-----------|--------|
| OIDC | Grafana | grafana | `k8s/grafana-oidc` | ✅ | ✅ Working — Grafana on K3s with OIDC via Authentik |
| OIDC | ArgoCD | argocd | `k8s/argocd-oidc` | ✅ | ⚠️ ESO force-synced with fresh creds 2026-03-01 — `invalid_client` may be resolved, needs verification |
| OIDC | Headlamp | headlamp | `k8s/headlamp-oidc` | ✅ | ⏳ ESO synced, pending ArgoCD sync of Headlamp OIDC values |
| OIDC | GitLab | gitlab | `services/gitlab/oidc` | ✅ | ✅ Working — OmniAuth OIDC login confirmed 2026-03-01 after Authentik fresh DB + re-credential |
| OIDC | Vault | vault | `services/vault/oidc` | ❌ | Deferred |
| OIDC | Proxmox | proxmox | `services/proxmox/oidc` | ❌ | Deferred |
| OIDC | NetBox | netbox | `services/netbox/oidc` | ❌ | Deferred |
| OIDC | Mealie | mealie | `services/mealie/oidc` | ❌ | Deferred |
| OIDC | PatchMon | patchmon | `services/patchmon/oidc` | ✅ | ✅ Re-credentialed 2026-03-01 via `patchmon-deploy.yml --tags configure` |
| ForwardAuth | Longhorn | — | — | ✅ | ⏳ Pending git push + ArgoCD sync |
| ForwardAuth | Ghost | — | — | ✅ | Via standalone Traefik proxy |
| ForwardAuth | Roundcube | — | — | ✅ | Via standalone Traefik proxy |
| ForwardAuth | FoundryVTT | — | — | ✅ | Via standalone Traefik proxy |
| ForwardAuth | Actual Budget | — | — | ✅ | Via standalone Traefik proxy |
| Bookmark | PBS | — | — | — | Dashboard link (`https://10.0.10.15:8007`) |
| Bookmark | Plex | — | — | — | Dashboard link (`https://10.0.40.2:32400`) |
| Bookmark | Home Assistant | — | — | — | ~~Dashboard link (`http://10.0.4.194:30103`)~~ — **migrated to ForwardAuth on HAOS RPi5** → see row below |
| ForwardAuth | Home Assistant | — | — | ✅ | ✅ ForwardAuth via standalone Traefik — admin-only access (`https://homeassistant.home.example-lab.org`) |
| Bookmark | Scanopy | — | — | — | Dashboard link (`http://10.0.4.20:60072`) |
| Bookmark | TrueNAS | — | — | — | Dashboard link (`https://10.0.40.2`) |
| Bookmark | JetKVM | — | — | — | Dashboard link (`http://10.0.10.112`) |
| OIDC | Vaultwarden | vaultwarden | `services/vaultwarden/oidc` | ✅ | ✅ Native OIDC working — SSO login via Authentik (email_verified override required) |
| OIDC | Open WebUI | openwebui | `services/openwebui/oidc` | ✅ | ✅ Native OIDC working — SSO login via Authentik |
| ForwardAuth | n8n | — | — | ✅ | ✅ ForwardAuth via standalone Traefik — admin-only access |
| OIDC | Mail Archiver | mailarchiver | `services/mailarchiver/oidc` | ✅ | Native OIDC via Authentik — admin-only. TrueNAS app on port 30315 (`https://archiver.home.example-lab.org`) |
| Bookmark | IT Tools | — | — | — | Dashboard link (`https://tools.home.example-lab.org`) — TrueNAS app port 30063 |
| ForwardAuth | SearXNG | — | — | ✅ | ForwardAuth via standalone Traefik (`https://search.home.example-lab.org`) — TrueNAS app port 30053 |
| Bookmark | Traefik (Hetzner) | — | — | — | Dashboard link (`http://10.8.0.1:8888`) — admin only |
| Bookmark | AdGuard Home | — | — | — | Dashboard link (`http://10.8.0.1:3000`) — admin only |
| Bookmark | Gotify | — | — | — | Dashboard link (`http://10.8.0.1:8080`) — admin only |
| Bookmark | Uptime Kuma | — | — | — | Dashboard link (`http://10.8.0.1:3001`) — admin only |

**Groups:** `authentik-admins` (admin access), `authentik-users` (default group for all)

**Note:** SonarQube CE 26.x dropped OIDC support — no SSO integration possible. Removed from Layer 07.

**Note:** GitLab is on **Management VLAN 10** (untagged on vmbr0), NOT Security VLAN 50 as some older docs suggest. The Terraform code (`vlan_tag = null`) is authoritative.

### GitLab Configuration (Layer 03-gitlab-config)

- 4 top-level groups: Infrastructure, Applications, Personal, Documentation
- 13+ projects across groups
- Branch protection on infrastructure projects
- CI/CD variables: Vault AppRole (role_id, secret_id) at instance level
- External URL: `https://gitlab.home.example-lab.org` (TLS terminated by standalone Traefik, internal backend `http://10.0.10.50:80`)
- **SSO:** ✅ OIDC configured (OmniAuth `openid_connect` via Authentik), applied 2026-03-01 via `gitlab-deploy.yml`
- **KAS (Kubernetes Agent Server):** ✅ Deployed (`gitlab_kas_enabled: true`), external URL `wss://gitlab.home.example-lab.org/-/kubernetes-agent/`, nginx SSL disabled (TLS terminated by standalone Traefik)
- **Cluster Agent:** ✅ `firblab-rke2` registered by Terraform Layer 03, token in Vault (`secret/k8s/gitlab-agent`). Agent deployed by ArgoCD (wave 0) via ESO token sync. Config at `.gitlab/agents/firblab-rke2/config.yaml`. Helm values corrected: `podSecurityContext` (pod-level) + `securityContext` (container-level) + `seccompProfile: RuntimeDefault` for PodSecurity `restricted` compliance
- **Renovate Bot:** Scheduled pipeline (Monday 5:00 AM) scans for outdated Helm charts, Terraform providers, Ansible collections, CI base images → creates MRs
- **ArgoCD Image Updater deploy token:** `argocd-image-updater` with `read_repository` + `write_repository` scopes, stored in Vault (`secret/services/gitlab/image-updater`)
- **GitHub Public Mirror:** `example-lab-blog/firblab` (public portfolio repo). GitLab push mirror from `firblab-public` project. Mirror token in Vault (`secret/services/github`, key: `mirror_token`, Contents RW). Admin token for Terraform repo management (`admin_token`, Administration RW). Security settings managed by Terraform Layer 03: branch protection (no force push/deletion), Dependabot alerts, Projects disabled, auto-delete branches, commit signoff required. Secret scanning + push protection enabled by default (GitHub platform-level for public repos).

### Wazuh SIEM

**Status:** ✅ Deployed 2026-03-01 — Manager + Indexer + Dashboard on RKE2 K8s cluster. Agent enrollment via MetalLB VIP 10.0.20.221:1514/1515. Dashboard at `wazuh.home.example-lab.org` via Traefik ingress.

- **K8s components:** Wazuh Manager (StatefulSet), Wazuh Indexer (StatefulSet, OpenSearch, security plugin disabled), Wazuh Dashboard (Deployment). All v4.14.3.
- **Vault secrets:** `secret/k8s/wazuh` (api_password + agent_enrollment_password), synced to K8s via ESO.
- **Config fixes applied:** PodSecurity `enforce: privileged` (indexer needs privileged init for vm.max_map_count), `DISABLE_SECURITY_PLUGIN=true` env var (image entrypoint overwrites opensearch.yml), removed legacy `wazuh.api.*` dashboard keys (4.14.x), removed invalid `<api>` ossec.conf block (4.14.x).
- **Agent fleet:** 33 hosts enrolled (all Proxmox nodes, RKE2, K3s, standalone services, Hetzner, DMZ, archive). vault-1 skipped (macOS). gitlab-runner failed (LXC connectivity — follow up separately).

---

## RKE2 Kubernetes Cluster

**Managed by:** Terraform Layer 04-rke2-cluster, Ansible rke2-deploy.yml + argocd-bootstrap.yml
**Status:** ✅ Deployed, all workload apps healthy. Gatekeeper OutOfSync (CRD annotation drift, cosmetic).

### Cluster Nodes

| Node | Role | VM ID | IP | Proxmox Node | CPU | RAM | OS Disk | Data Disk |
|------|------|-------|-----|-------------|-----|-----|---------|-----------|
| rke2-server-1 | Server (init) | 4000 | 10.0.20.40 | lab-01 | 2 | 5 GB | 50 GB | 100 GB |
| rke2-server-2 | Server | 4001 | 10.0.20.41 | lab-01 | 2 | 5 GB | 50 GB | 100 GB |
| rke2-server-3 | Server | 4002 | 10.0.20.42 | lab-01 | 2 | 5 GB | 50 GB | 100 GB |
| rke2-agent-1 | Agent | 4003 | 10.0.20.50 | lab-01 | 4 | 10 GB | 50 GB | 100 GB |
| rke2-agent-2 | Agent | 4004 | 10.0.20.51 | lab-01 | 4 | 10 GB | 50 GB | 100 GB |

**Total cluster resources:** 14 CPU cores, 35 GB RAM, 250 GB OS, 500 GB Longhorn data (3+2 topology, applied 2026-03-01)
**Storage pools:** OS disks on `local-lvm` (1TB NVMe boot drive), Longhorn data disks on `nvme-thin-1` (2TB Samsung 990 EVO Plus) — ✅ Applied 2026-03-01

### RKE2 Configuration

| Setting | Value |
|---------|-------|
| Version | v1.32.11+rke2r3 |
| CNI | Canal (Calico + Flannel) |
| Security Profile | CIS (DISA STIG + CIS Kubernetes Benchmark) |
| Cluster CIDR | 10.42.0.0/16 |
| Service CIDR | 10.43.0.0/16 |
| Cluster DNS | 10.43.0.10 |
| API Server | https://10.0.20.40:6443 |
| Registration | https://10.0.20.40:9345 |
| Disabled Components | rke2-ingress-nginx (replaced by Traefik), rke2-metrics-server |
| CoreDNS Custom Zones | `home.example-lab.org` → 10.0.20.1 + 1.1.1.1 (300s cache, HelmChartConfig via Ansible) |

### ArgoCD Applications (19 total, 3 sync waves)

| Wave | App | Namespace | PSA Level | Status | Notes |
|------|-----|-----------|-----------|--------|-------|
| 0 | kured | kured | privileged | ✅ Synced/Healthy | Safe node reboots: cordons+drains before rebooting, prevents copyutil emptyDir failures |
| 0 | traefik | traefik | baseline | ✅ Synced/Healthy | Chart v35, `allowCrossNamespace`, namespace-qualified middleware |
| 0 | metallb | metallb-system | privileged | ✅ Synced/Healthy | Working |
| 0 | cert-manager | cert-manager | restricted | ✅ Synced/Healthy | Working |
| 0 | external-secrets | external-secrets | restricted | ✅ Synced/Healthy | ServerSideApply enabled for large CRDs |
| — | ~~gatekeeper~~ | ~~gatekeeper-system~~ | — | ❌ Removed 2026-03-01 | Pruned by ArgoCD (app manifest deleted) |
| 0 | longhorn | longhorn-system | privileged | ✅ Synced/Healthy | `ignoreDifferences` on default-setting ConfigMap to prevent delete loop |
| — | ~~monitoring-prometheus~~ | ~~monitoring~~ | — | ❌ Removed | Migrated to K3s RPi5 cluster (Helm-only, no ArgoCD) |
| — | ~~monitoring-loki~~ | ~~monitoring~~ | — | ❌ Removed | Migrated to K3s RPi5 cluster (Helm-only, no ArgoCD) |
| 0 | trivy-operator | trivy-system | baseline | ✅ Synced/Healthy | Working |
| 0 | gitlab-agent | gitlab-agent | restricted | ✅ Synced/Healthy | GitLab Agent for K8s — KAS WebSocket tunnel, CI/CD cluster access |
| 0 | argocd-image-updater | argocd | baseline | ✅ Synced/Healthy | Git write-back mode, watches Mealie registries |
| 1 | metallb-config | metallb-system | — | ✅ Synced/Healthy | Working |
| 1 | cert-manager-config | cert-manager | — | ✅ Synced/Healthy | Working |
| 1 | external-secrets-config | external-secrets | — | ✅ Synced/Healthy | ClusterSecretStore vault-backend Valid/Ready |
| 1 | traefik-config | traefik | — | ✅ Synced/Healthy | Working |
| 1 | argocd-config | argocd | — | ✅ Synced/Healthy | OIDC ConfigMap, cmd-params-cm, IngressRoute (TLS via cert-manager) |
| 1 | longhorn-config | longhorn-system | — | ✅ Synced/Healthy | Working |
| — | ~~gatekeeper-policies~~ | ~~gatekeeper-system~~ | — | ❌ Removed 2026-03-01 | Pruned with gatekeeper |
| — | ~~monitoring-dashboards~~ | ~~monitoring~~ | — | ❌ Removed | Migrated to K3s RPi5 cluster (dashboard ConfigMaps applied by Ansible) |
| 2 | mealie | mealie | restricted | ✅ Synced/Healthy | v3.10.2, `strategy: Recreate` for RWO PVC |
| — | ~~sonarqube~~ | ~~sonarqube~~ | — | ❌ Removed 2026-03-01 | Pruned by ArgoCD (app manifest deleted) |
| 2 | headlamp | headlamp | restricted | ✅ Synced/Healthy | K8s web UI, read-only RBAC, SA token in Vault. ⏳ OIDC configured (pending sync) |
| 2 | gitlab | gitlab | restricted | ⚠️ Unknown/Healthy | GitLab CE Helm chart (~4Gi RAM, testing instance on RKE2) |
| 2 | wazuh | wazuh | privileged | ✅ Synced/Healthy | Wazuh SIEM — Manager + Indexer + Dashboard (v4.14.3). MetalLB VIP 10.0.20.221. |

**Resolved cascading failures:**
- ✅ PSA labels applied to all ArgoCD Application manifests → pods can schedule
- ✅ Longhorn pre-upgrade hook deadlock fixed (`preUpgradeChecker.jobEnabled: false`) → 40+ pods running, StorageClass created
- ✅ Longhorn ArgoCD delete loop fixed (`ignoreDifferences` on `longhorn-default-setting` ConfigMap) → prevents Helm pre-delete hook from firing
- ✅ External-secrets + Gatekeeper CRD sync fixed (`ServerSideApply=true`) → CRDs no longer exceed 256KB annotation limit
- ✅ ClusterSecretStore updated from v1beta1 → v1 API (ESO 0.20.x removed v1beta1)
- ✅ Grafana admin credentials pipeline: Terraform `random_password` → Vault KV → ESO ExternalSecret → K8s Secret → Grafana running (migrated to K3s)
- ✅ Grafana OIDC: `generic_oauth` via Authentik — working on K3s RPi5 cluster
- ✅ SonarQube DB credentials seeded in Vault via Terraform
- ✅ Traefik `redirectTo` → `redirections` syntax fix deployed
- ✅ SonarQube upgraded: `10-community` → `26.1.0.118079-community` (2026 LTS), GID fix (1000 → 0), postgres `16.11-alpine`
- ✅ Mealie upgraded: `v2.6.0` → `v3.10.2`, added `strategy: Recreate` for RWO PVC compatibility
- ✅ Longhorn ArgoCD Application stuck deletion cleared (removed finalizers, root app-of-apps recreated it)

- ✅ K8s Traefik 404 on all websecure routes — middleware namespace fix (`traefik-default-headers@kubernetescrd`) + `allowCrossNamespace: true`
- ✅ ArgoCD 500 Internal Server Error — IngressRoute fixed: `port: 80` (HTTP), removed `scheme: https`
- ✅ ArgoCD infinite redirect loop — `argocd-cmd-params-cm` with `server.insecure: "true"` (Traefik terminates TLS)
- ✅ DHCP DNS resolving to Hetzner instead of internal — gw-01 gateways set as primary DNS per VLAN
- ✅ cert-manager certificates all READY=False — Vault ESO policy fixed, Cloudflare API token synced, all 6 certs issued

**Remaining issues:**
- ArgoCD OIDC `invalid_client` — ESO force-synced with fresh creds 2026-03-01 after Authentik DB rebuild. May be resolved — needs verification.
- GitLab CE Helm chart (gitlab ArgoCD app) — Unknown health status, needs investigation

## K3s Kubernetes Cluster (RPi5 Bare-Metal)

**Managed by:** Ansible k3s-rpi-nvme-setup.yml + k3s-deploy.yml + k3s-platform-deploy.yml + k3s-monitoring-deploy.yml, Terraform Layers 00 (switch ports) + 02 (Vault K8s auth)
**Status:** ✅ Deployed — 3-node HA cluster running K3s v1.32.11+k3s1 on Ubuntu 24.04 ARM64, NVMe boot, CIS-hardened. Full monitoring stack (Prometheus, Grafana, Loki, Alertmanager) deployed.

### Cluster Nodes

| Node | Role | Hardware | IP | Switch Port | RAM | Storage |
|------|------|----------|-----|-------------|-----|---------|
| k3s-server-1 | Server (init) | Raspberry Pi 5 | 10.0.20.60 | Rackmate Port 1 | 8 GB | NVMe |
| k3s-server-2 | Server | Raspberry Pi 5 | 10.0.20.61 | Rackmate Port 2 | 8 GB | NVMe |
| k3s-server-3 | Server | Raspberry Pi 5 | 10.0.20.62 | Rackmate Port 3 | 4 GB | NVMe |

All 3 servers run workloads (server taints removed). No dedicated agents.

### K3s Configuration

| Setting | Value |
|---------|-------|
| Version | v1.32.11+k3s1 |
| CNI | Flannel (VXLAN) |
| Security | CIS-hardened (protect-kernel-defaults, secrets-encryption, audit policy) |
| Pod CIDR | 10.44.0.0/16 (non-overlapping with RKE2's 10.42.0.0/16) |
| Service CIDR | 10.45.0.0/16 (non-overlapping with RKE2's 10.43.0.0/16) |
| Cluster DNS | 10.45.0.10 |
| API Server | https://10.0.20.60:6443 |
| Disabled Components | traefik, metrics-server |
| CoreDNS Custom Zones | `home.example-lab.org` → 10.0.20.1 + 1.1.1.1 (300s cache) |
| Storage | local-path-provisioner (K3s default, NVMe-backed) |
| Purpose | Dedicated monitoring cluster (Prometheus, Grafana, Loki, Alertmanager) |

### Platform Services (Helm-only, no ArgoCD)

Deployed via `ansible-playbook k3s-platform-deploy.yml` and `k3s-monitoring-deploy.yml`. All Helm values in `k8s/k3s-platform/`.

| Component | Namespace | Replicas | VIP / Port | Status |
|-----------|-----------|----------|-----------|--------|
| MetalLB | metallb-system | speaker DaemonSet (3) | Pool: 10.0.20.200–219 | ✅ Running |
| Traefik | traefik | 1 | 10.0.20.200 (LB) | ✅ Running |
| cert-manager | cert-manager | 1 | — | ✅ Running |
| External Secrets Operator | external-secrets | 1 | — | ✅ Running |
| Prometheus | monitoring | 1 | — | ✅ Running (14d retention, 20Gi local-path) |
| Grafana | monitoring | 1 | grafana.home.example-lab.org → 10.0.20.200 | ✅ Running (OIDC via Authentik) |
| Alertmanager | monitoring | 1 | — | ✅ Running (Gotify webhook via WireGuard) |
| Loki | monitoring | 1 | 10.0.20.201 (LB) | ✅ Running (10Gi local-path) |
| Promtail | monitoring | DaemonSet (3) | — | ✅ Running |
| kube-state-metrics | monitoring | 1 | — | ✅ Running |

**Note:** nodeExporter DaemonSet is disabled on K3s — bare-metal nodes already run Ansible-managed node_exporter (port 9100 conflict). Heavy workloads (Prometheus, Grafana, Loki) pinned to `example-lab.org/ram-tier: standard` nodes (8GB).

### Deployment Checklist

- [x] Phase 0: NVMe setup — `k3s-rpi-nvme-setup.yml` (dual-path: SD flash or NVMe reconfig, cloud-init, EEPROM)
- [x] Phase 1: `terraform apply` Layer 00 (Services Access port profiles on Rackmate ports 1-3)
- [x] Phase 2: `k3s-deploy.yml` (common + hardening + K3s prereqs + CIS configs + cluster-init + join)
- [x] Phase 3: Verify cluster health — all 3 nodes Ready, CoreDNS running, secrets-encryption enabled
- [x] Phase 4: Vault K8s auth — `terraform apply` Layer 02 (kubernetes-k3s auth backend) + `k3s-vault-k8s-auth.yml`
- [x] Phase 5: Platform prerequisites — `k3s-platform-deploy.yml` (MetalLB, cert-manager, ESO, Traefik)
- [x] Phase 6: Monitoring stack — `k3s-monitoring-deploy.yml` (kube-prometheus-stack + loki-stack)
- [x] Phase 7: DNS cutover — `terraform apply` Layer 00 (grafana → K3s Traefik VIP 10.0.20.200)
- [x] Phase 8: Loki endpoint update — gateway + honeypot Alloy configs pointed to 10.0.20.201:3100
- [x] Phase 9: RKE2 monitoring decommission — removed ArgoCD apps, manifests, ExternalSecrets, NetworkPolicies

### Access

```bash
# Direct access (kubectx)
kubectx k3s-rpi5
kubectl get nodes

# Tunnel access (via Proxmox jump host)
ssh -L 6443:10.0.20.60:6443 -i ~/.ssh/id_ed25519_lab-01 -o IdentitiesOnly=yes admin@10.0.10.42 -N &
KUBECONFIG=~/.kube/k3s-config-tunnel kubectl get nodes
```

---

## Standalone Services

**Managed by:** Terraform Layer 05-standalone-services, Ansible deploy playbooks
**Status:** ✅ Deployed (all containers/VMs provisioned and running)

| Service | Type | VM ID | IP | VLAN | Proxmox Node | CPU | RAM | Disk | Port | Verified |
|---------|------|-------|-----|------|-------------|-----|-----|------|------|----------|
| Ghost | LXC | 5010 | 10.0.20.10 | 20 (Services) | lab-03 | 1 | 1 GB | 20 GB | 2368 | ✅ Through tunnel |
| Roundcube | LXC | 5013 | 10.0.20.11 | 20 (Services) | lab-03 | 1 | 1024 MB | 10 GB | 8080 | ❌ Not deployed |
| FoundryVTT | VM | 5011 | 10.0.20.12 | 20 (Services) | lab-03 | 2 | 4 GB | 40 GB + 30 GB data | 30000 | ❌ Not tested |
| Mealie | LXC | 5014 | 10.0.20.13 | 20 (Services) | lab-03 | 1 | 1 GB | 10 GB | 9000 | ❌ Not tested |
| NetBox | VM | 5030 | 10.0.20.14 | 20 (Services) | lab-04 | 2 | 4 GB | 40 GB | 8080 | ✅ Deployed + seeded |
| PatchMon | VM | 5032 | 10.0.20.15 | 20 (Services) | lab-04 | 2 | 2 GB | 40 GB | 3000 | ✅ Deployed (v1.4.0), admin + enrollment token configured, 26 agents enrolled |
| Actual Budget | LXC | 5015 | 10.0.20.16 | 20 (Services) | lab-03 | 1 | 512 MB | 10 GB | 5006 | ⚠️ IaC ready, not yet applied |
| PBS | VM | 5031 | 10.0.10.15 | 10 (Mgmt) | lab-04 | 2 | 4 GB | 32 GB SSD + ZFS mirror ~14.6 TB (HDD passthrough) | 8007 | ✅ Deployed |
| Archive (lab-09) | Bare-metal | — | 10.0.20.20 | 20 (Services) | ZimaBlade 7700 (switch-03 Port 4) | 4 cores | 16 GB | 32 GB eMMC + 2 TB USB SSD + ~1 TB PS4 HDD | 8080-8087 | ✅ 6 services deployed (~417 GB ZIM, Authentik SSO, daily S3 backup, monthly ZIM auto-sync); ⏳ TileServer GL (8086) + Calibre-Web (8087) coded, pending `archive-deploy.yml` + Traefik/Authentik re-apply |
| Vaultwarden | LXC | 5036 | 10.0.20.19 | 20 (Services) | lab-03 | 1 | 512 MB | 4 GB | 8000 | ✅ Deployed (Argon2 admin token, OIDC SSO, 1Password import complete) |
| Backup (Restic + Backrest) | LXC | 5040 | 10.0.10.18 | 10 (Mgmt) | lab-01 | 2 | 1 GB | 8 GB + bind-mount hdd-mirror-0 ZFS | 8500/9898 | ⚠️ IaC ready, not yet applied |
| Traefik Proxy | LXC | 5033 | 10.0.10.17 | 10 (Mgmt) | lab-04 | 1 | 512 MB | 10 GB | 80/443 | ✅ Deployed, all 10 backends proxied with valid TLS |
| Home Assistant | Bare-metal (RPi CM4 8GB) | — | 10.0.60.10 | 60 (IoT) | switch-02 Port 8 (lab-11) | 4 | 8 GB | NVMe via USB | 8123 | ✅ Deployed — CM4 8GB Lite (CM4108000), NVMe SSD via USB enclosure, HAOS 17.1. Config restored from GitLab via Git Pull add-on. Monitoring integrations: Proxmox VE (4 nodes), UniFi, Uptime Kuma, System Monitor, Vault REST sensors, Mushroom Cards dashboard. Traefik proxy UFW updated for VLAN 60. Proxmox iptables updated for VLAN 60 on port 8006. |

**Note:** FoundryVTT is deployed on **lab-03** per Terraform state (`proxmox_node = "lab-03"`). NetBox is on **lab-04** (first VM on the Dell Wyse node).

**Traefik Proxy:** Standalone Traefik v3 reverse proxy for ALL non-K8s services. TLS termination via Let's Encrypt DNS-01 (Cloudflare). ForwardAuth via Authentik for services without native OIDC. Lives on Management VLAN 10 for direct L2 access to management backends. RKE2 workloads stay on RKE2 Traefik (10.0.20.220). K3s monitoring (Grafana) on K3s Traefik (10.0.20.200).

### Bare-Metal Services (lab-08)

**Managed by:** Ansible lab-08-bootstrap.yml + lab-08-deploy.yml
**Status:** ✅ Deployed and operational

| Service | Platform | IP | Port | Secrets | Status |
|---------|----------|-----|------|---------|--------|
| Scanopy | Docker Compose (server + daemon + PostgreSQL) | 10.0.4.20 | 60072 (Web UI + API), 60073 (daemon) | `secret/services/scanopy` | ✅ Web UI live, admin onboarded, registration disabled |
| NUT | Native packages (nut-server, nut-client) | 10.0.4.20 | 3493 (upsd) | `secret/services/nut` | ✅ CyberPower CP1500PFCLCDa detected, battery 100%, OL |

**Scanopy details:**
- Version: v0.14.5 (Community), Docker images `ghcr.io/scanopy/scanopy/{server,daemon}`
- Daemon runs in host network mode with privileged access for ARP/L2/L3 scanning
- **Multi-VLAN scanning:** Switch port uses Scanner Trunk (native VLAN 1, tagged 10/20/30/40/50). 802.1Q sub-interfaces (eth0.10 through eth0.50, all at .90) give daemon L2 presence on every VLAN for full ARP/MAC discovery.
- Admin account auto-created via API onboarding (credentials in Vault)
- Daemon provisioned via `POST /api/v1/daemons/provision` — API key + network_id in Vault and injected as env vars
- Daemon mode: DaemonPoll (daemon polls server; no inbound connections needed)
- `SCANOPY_INTEGRATED_DAEMON_URL` intentionally NOT set — it triggers ServerPoll auto-registration
- Ansible role includes idempotent mode fix: detects ServerPoll daemons, deletes, restarts daemon to re-register as DaemonPoll
- Open registration disabled after initial setup
- **NetBox integration:** `scripts/scanopy-netbox-sync.py` syncs discovered hosts/IPs/MACs to NetBox (47 hosts, 22 matched, 20 new IPs created on first run). **Automated:** daily cron at 05:00 on lab-08 (credentials from Vault, deployed via Ansible Scanopy role).

**PatchMon details (10.0.20.15:3000):**
- Version: v1.4.0 (Docker Compose: PostgreSQL + Redis + backend + frontend)
- Admin: Created via web UI (v1.4.0 has no programmatic setup API), credentials in Vault
- Enrollment: Auto-enrollment token created via `POST /api/v1/auto-enrollment/tokens`, stored in Vault
- **Agent fleet:** 26 of 29 Linux hosts enrolled via `patchmon-agent-deploy.yml` (serial: 5)
  - Agent binary: `/usr/local/bin/patchmon-agent`, config: `/etc/patchmon/config.yml`, creds: `/etc/patchmon/credentials.yml`
  - Cron: 60-minute reporting interval, outbound-only to PatchMon on port 3000
  - Expected failures (3): hetzner (no Vault connectivity), vault-2 (SSH unreachable during run), wireguard (SSH unreachable during run)
- **SSO:** OIDC via Authentik configured (Layer 07), pending ansible run to apply

**NUT details:**
- UPS: CyberPower PR1500LCDRT2U (USB VID:PID 0764:0601)
- Driver: usbhid-ups v2.8.1
- **Server (lab-08):** Netserver mode, upsmon primary, HOSTSYNC 15s for coordinated shutdown
- **Clients (lab-01, lab-04):** Netclient mode, upsmon secondary, monitor `ups@10.0.4.20`
- Coordinated shutdown: UPS LOWBATT → server signals FSD → clients shut down first → server shuts down last
- Remote query: `upsc ups@10.0.4.20`

---

## DMZ Services

**Managed by:** Terraform Layer 05-standalone-services, Ansible wireguard-deploy.yml
**Status:** ✅ Deployed and verified

| Service | Type | VM ID | IP | VLAN | Proxmox Node | CPU | RAM | Disk |
|---------|------|-------|-----|------|-------------|-----|-----|------|
| WireGuard | LXC | 5020 | 10.0.30.2 | 30 (DMZ) | lab-03 | 1 | 256 MB | 4 GB |

### WireGuard Tunnel

| Parameter | Hetzner (Server) | Homelab (Client) |
|-----------|-----------------|-----------------|
| Tunnel IP | 10.8.0.1/24 | 10.8.0.2/32 |
| Listen Port | 51820 (public) | — (outbound initiation) |
| NAT/Masquerade | — | Yes (eth0, source → 10.0.30.2) |
| PresharedKey | Required | Required |
| Managed by | Terraform Layer 06 | Ansible wireguard-deploy.yml |

---

## Hetzner Gateway

**Managed by:** Terraform Layer 06-hetzner + Ansible `gateway-deploy.yml` (`hetzner-gateway` role)
**Status:** ✅ Deployed and operational | ✅ Ansible-managed (gateway-deploy.yml run 2026-02-25)

| Setting | Value |
|---------|-------|
| Server Name | lab-gateway |
| Hetzner Server ID | 120966457 |
| Public IPv4 | 203.0.113.10 |
| Server Type | cpx22 (configurable) |
| Location | Nuremberg |
| OS | Ubuntu 24.04 |
| SSH | Port 2222, key `~/.ssh/id_ed25519_lab-hetzner` |
| WireGuard IP | 10.8.0.1 |
| Backup | ✅ Deployed — `backup` role, S3 bucket `firblab-service-backups`, age-encrypted, daily 04:30 |
| Monitoring | ✅ Deployed — node_exporter (10.8.0.1:9100 WireGuard only), Prometheus scrape configured |
| Log shipping | ✅ Deployed — Grafana Alloy → Loki (10.0.20.201:3100, K3s MetalLB VIP) via WireGuard tunnel |

### Hetzner Honeypot Server

**Managed by:** Terraform Layer 06-hetzner + Ansible `honeypot-deploy.yml`
**Status:** ✅ Deployed 2026-02-24

| Setting | Value |
|---------|-------|
| Server Name | lab-honeypot |
| Public IPv4 | 203.0.113.11 |
| DNS | honeypot.example-lab.org |
| Server Type | cpx22 (4 vCPU, 8 GB RAM) |
| Location | Nuremberg |
| OS | Ubuntu 24.04 |
| Real SSH | Port 2222 (WG + home network only) |
| WireGuard | Client tunnel to gateway (peer2) → homelab Loki |

#### Docker Services on Honeypot

| Service | Port | Access | Status |
|---------|------|--------|--------|
| Cowrie | 22 (SSH), 23 (Telnet) | Public | ✅ Running |
| OpenCanary | 3389 (RDP), 5900 (VNC), 6379 (Redis) | Public | ✅ Running |
| Dionaea | 445 (SMB), 5060 (SIP), 8080 (HTTP), 8443 (HTTPS) | Public | ✅ Running |
| Endlessh | 2223 (SSH tarpit) | Public | ✅ Running |
| Grafana Alloy | — (outbound to Loki) | Local | ✅ Running |

### Docker Services on Hetzner Gateway

Fully managed by `ansible/roles/hetzner-gateway/` — all configs are Jinja2 templates.
To add/change a Traefik route: edit `templates/traefik-services.yml.j2`, run `gateway-deploy.yml --tags traefik`.

| Service | Port | Access | Status |
|---------|------|--------|--------|
| Traefik v3 | 80, 443 (public) + 8888 (metrics/dashboard) | Public + WireGuard | ✅ Working |
| WireGuard | 51820/UDP | Public | ✅ Working |
| AdGuard Home | 53 + 3000 (admin) | WireGuard only | ✅ Running |
| CrowdSec | — (w/ Traefik bouncer plugin) | Local | ✅ Running |
| Fail2ban | — | Local | ✅ Running |
| Watchtower | — (monitor-only, versions pinned) | Local | ✅ Running |
| Gotify | 8080 | WireGuard only | ✅ Running |
| Uptime Kuma | 3001 | WireGuard only | ✅ Running |
| node_exporter | 9100 (10.8.0.1 WireGuard interface only) | Prometheus via WireGuard | ✅ Running |
| Grafana Alloy | — (outbound to Loki) | Local | ✅ Running |

### Cloudflare DNS Records

| Record | Type | Target |
|--------|------|--------|
| *.example-lab.org | CNAME | example-lab.org |
| example-lab.org | A | 203.0.113.10 |
| blog.example-lab.org | CNAME | example-lab.org |
| food.example-lab.org | CNAME | example-lab.org |
| foundryvtt.example-lab.org | CNAME | example-lab.org |
| traefik.example-lab.org | CNAME | example-lab.org |
| adguard.example-lab.org | CNAME | example-lab.org |
| status.example-lab.org | CNAME | example-lab.org |
| gotify.example-lab.org | CNAME | example-lab.org |

### Hetzner Firewall Rules

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 2222 | TCP | WireGuard (10.8.0.0/24) + Home (108.31.230.122) | SSH |
| 80 | TCP | 0.0.0.0/0 | HTTP (redirect to HTTPS) |
| 443 | TCP | 0.0.0.0/0 | HTTPS (Traefik) |
| 51820 | UDP | 0.0.0.0/0 | WireGuard |
| 53 | TCP/UDP | WireGuard only | DNS (AdGuard) |
| 3000 | TCP | WireGuard only | AdGuard admin |
| 3001 | TCP | WireGuard only | Uptime Kuma |
| 8080 | TCP | WireGuard only | Gotify |
| 8888 | TCP | WireGuard only | Traefik dashboard |

---

## Terraform Layer Status

| Layer | Path | Resources | State | Status |
|-------|------|-----------|-------|--------|
| 00-network | `terraform/layers/00-network/` | VLANs, zones, policies, profiles, devices | ✅ tfstate present | ✅ Deployed |
| 01-proxmox-base | `terraform/layers/01-proxmox-base/` | ISOs, cloud images, LXC templates | ✅ tfstate present | ✅ Deployed |
| 02-vault-infra | `terraform/layers/02-vault-infra/` | vault-2 VM | ✅ tfstate present | ✅ Deployed |
| 02-vault-config | `terraform/layers/02-vault-config/` | KV, PKI, policies, AppRole, secrets | ✅ tfstate present | ✅ Deployed |
| 03-core-infra | `terraform/layers/03-core-infra/` | GitLab VM, Runner LXC | ✅ tfstate present | ✅ Deployed |
| 03-gitlab-config | `terraform/layers/03-gitlab-config/` | Groups, projects, labels, CI/CD vars, GitHub repo security | ✅ tfstate present | ✅ Deployed (GitHub provider added for public repo management) |
| 04-rke2-cluster | `terraform/layers/04-rke2-cluster/` | 3 server + 3 agent VMs | ✅ tfstate present | ✅ Deployed, all workloads healthy |
| 05-standalone-services | `terraform/layers/05-standalone-services/` | Ghost, FoundryVTT, Roundcube, Mealie, WireGuard, NetBox, PBS, Authentik, PatchMon, Actual Budget, Traefik Proxy, AI GPU, Vaultwarden | ✅ tfstate present | ✅ Authentik PBS-restored + `authentik_storage_pool` added (nvme-thin-1). AI GPU + Vaultwarden applied. |
| 06-hetzner | `terraform/layers/06-hetzner/` | Hetzner VPS (gateway + honeypot), Cloudflare DNS, 7 S3 buckets (WireGuard + 6 backup), 30-day lifecycle expiration on 5 backup buckets, Vault IP + credentials writeback | ✅ tfstate present | ✅ Applied (gateway + honeypot IPs + credentials in Vault at `secret/infra/hetzner/server_ips` + `secret/infra/hetzner/credentials`) |
| 07-authentik-config | `terraform/layers/07-authentik-config/` | 12 OIDC providers, 11 ForwardAuth proxies, 11 bookmark apps, 2 groups, embedded outpost, Vault OIDC secrets | ✅ tfstate present | ✅ Fresh apply 2026-03-01 (134 resources created from clean state after Authentik DB wipe) |
| 08-netbox-config | `terraform/layers/08-netbox-config/` | Site, 2 cluster types, 2 clusters, 21 Proxmox VMs + 1 Hetzner VM, interfaces, IPs, primary IP assignments, `terraform-managed` tag | ✅ tfstate present | ✅ Deployed (94 resources: 93 created + 1 imported site) |

### Terraform Modules

| Module | Path | Used By |
|--------|------|---------|
| proxmox-vm | `terraform/modules/proxmox-vm/` | Layers 02, 03, 04, 05 |
| proxmox-lxc | `terraform/modules/proxmox-lxc/` | Layers 03, 05 |
| proxmox-rke2-cluster | `terraform/modules/proxmox-rke2-cluster/` | Layer 04 |
| vault-cluster | `terraform/modules/vault-cluster/` | Layer 02 |
| hetzner-server | `terraform/modules/hetzner-server/` | Layer 06 |
| cloudflare-dns | `terraform/modules/cloudflare-dns/` | Layer 06 |

### Packer Templates

| Template | Path | VM ID | Node | OS |
|----------|------|-------|------|----|
| Ubuntu 24.04 Base | `packer/ubuntu-24.04/` | 9000 | lab-01 (+ cross-node clone) | Ubuntu 24.04 LTS |
| Rocky Linux 9 Base | `packer/rocky-9/` | 9001 | lab-01 (+ cross-node clone) | Rocky Linux 9 |
| PBS Base | `packer/pbs/` | 9002 | lab-01 (+ cross-node clone) | Proxmox Backup Server 4.x (Debian 13) |

---

## Ansible Automation Coverage

### Playbooks

| Playbook | Target | Roles | Status |
|----------|--------|-------|--------|
| proxmox-bootstrap.yml | proxmox_nodes | (inline tasks: interfaces, admin user, iptables, cluster) | ✅ Run on all 4 nodes |
| vault-deploy.yml | vault_cluster | common, vault, vault-unseal | ✅ Run |
| harden.yml | linux_vms | common, hardening | ⚠️ Partially run |
| gitlab-deploy.yml | gitlab | common, docker, gitlab | ✅ Run |
| gitlab-runner-deploy.yml | gitlab-runner | common, docker, gitlab-runner | ✅ Run |
| rke2-deploy.yml | rke2_cluster | common, rke2 | ✅ Run |
| argocd-bootstrap.yml | rke2-server-1 | (inline: install ArgoCD, root app) | ✅ Run |
| vault-k8s-auth.yml | rke2-server-1 | (inline: configure Vault K8s auth) | ⚠️ Status unknown |
| ghost-deploy.yml | ghost | common, docker, ghost, backup, restic-backup | ✅ Run |
| roundcube-deploy.yml | roundcube | common, docker, roundcube, backup, restic-backup | ❌ Not run |
| foundryvtt-deploy.yml | foundryvtt | common, hardening, foundryvtt, backup, restic-backup | ✅ Run |
| mealie-deploy.yml | mealie | common, docker, mealie, backup, restic-backup | ✅ Run |
| netbox-deploy.yml | netbox | common, hardening, docker, netbox | ✅ Run |
| authentik-deploy.yml | authentik | common, hardening, docker, authentik, backup, restic-backup | ✅ Run |
| lab-08-bootstrap.yml | lab-08 | (inline: admin user, NetworkManager static IP, common, hardening) | ✅ Run |
| lab-08-deploy.yml | lab-08 | common, hardening, docker, scanopy, nut | ✅ Run |
| wireguard-deploy.yml | wireguard | common, wireguard | ✅ Run |
| nut-client-deploy.yml | ups_clients | common, nut (netclient) | ✅ Run (lab-01, lab-04) |
| vault-backup-setup.yml | vault-1 | (inline: age/aws install, LaunchDaemon cron) | ✅ Run |
| pbs-deploy.yml | pbs | pbs | ✅ Run |
| proxmox-pbs-register.yml | proxmox_nodes | (inline: register PBS storage, create backup jobs, remove vzdump crons) | ✅ Run |
| proxmox-backup-setup.yml | proxmox_nodes | (inline: cleanup only — removes legacy vzdump crons, replaced by PBS) | ✅ Run (all 4 nodes) |
| macos-bootstrap.yml | macos_hosts | macos-launchd, (pf firewall) | ✅ Run |
| honeypot-deploy.yml | lab-honeypot | honeypot | ✅ Run (5 containers: Cowrie, OpenCanary, Dionaea, Endlessh, Grafana Alloy → Loki via WireGuard) |
| gateway-deploy.yml | lab-hetzner | hetzner-gateway, backup | ✅ Run (10 containers: Traefik, WireGuard, AdGuard, Gotify, Uptime Kuma, CrowdSec, Fail2ban, Watchtower, node_exporter, Grafana Alloy) |
| patchmon-deploy.yml | patchmon | common, hardening, docker, patchmon, backup, restic-backup | ✅ Run (onboarding: admin login + enrollment token + Vault store) |
| patchmon-agent-deploy.yml | patchmon_agent_targets | patchmon-agent | ✅ Run (26 of 29 hosts enrolled — 3 expected skips: hetzner, vault-2, wireguard) |
| vaultwarden-deploy.yml | vaultwarden | common, docker, vaultwarden, backup, restic-backup | ✅ Run (Argon2 admin token, user invites, 1Password import) |
| archive-deploy.yml | archive | common, hardening, docker, archive, backup | ✅ Run (6 services deployed, ~417 GB ZIM content, daily S3 backup, monthly ZIM auto-sync cron); ⏳ Re-run to deploy TileServer GL + Calibre-Web |
| proxmox-gpu-setup.yml | lab-01 | proxmox-gpu | ✅ Run (IOMMU + VFIO + d3cold workarounds applied, host power-cycled) |
| ai-gpu-deploy.yml | ai_gpu | common, hardening, docker, ai-gpu | ✅ Run (Ollama ROCm + Open WebUI OIDC + n8n, admin creds in Vault) |
| restic-server-deploy.yml | lab-01 | restic-server | ❌ Not run (pending hdd-mirror-0 ZFS pool creation) |
| actualbudget-deploy.yml | actualbudget | common, docker, actualbudget, backup, restic-backup | ✅ Run |
| truenas-probe.yml | truenas | (inline: midclt queries, sanitized YAML report) | ✅ Run (state probe) |
| truenas-deploy.yml | truenas | truenas | ✅ Run (services, NFS/SMB security fixes, snapshots, SMART tests, scrubs) |
| truenas-migrate-vlan.yml | localhost | (inline: midclt via SSH) | ⏳ Pending run |

### Roles

| Role | Purpose | Applied To |
|------|---------|-----------|
| common | Packages, NTP, fail2ban, SSH hardening, UFW | All Linux hosts |
| hardening | CIS L1: kernel params, audit, AIDE, AppArmor/SELinux | VMs only (not LXCs) |
| docker | Docker CE, compose, user config | Ghost, Roundcube, Mealie, FoundryVTT, NetBox, Authentik, Runner |
| vault | Vault binary, config, TLS, systemd/LaunchDaemon | vault-1, vault-2, vault-3 |
| vault-unseal | Unseal Vault instance (port 8210) | vault-1 (Mac Mini) |
| gitlab | GitLab CE Omnibus install + config | gitlab |
| gitlab-runner | Runner registration + Docker executor | gitlab-runner |
| rke2 | RKE2 install, CIS hardening, server/agent | rke2_cluster |
| ghost | Ghost Docker Compose deployment | ghost |
| roundcube | Roundcube Docker Compose deployment (PostgreSQL + webmail) | roundcube |
| foundryvtt | FoundryVTT Docker Compose deployment | foundryvtt |
| mealie | Mealie Docker Compose deployment | mealie |
| netbox | NetBox Docker Compose deployment (DCIM/IPAM) | netbox |
| authentik | Authentik Docker Compose deployment (SSO/IDP: PostgreSQL + server + worker) | authentik |
| scanopy | Scanopy network scanner (Docker Compose: server + daemon + PostgreSQL, automated onboarding, NetBox sync cron) | lab-08 |
| nut | NUT UPS monitoring (netserver mode on lab-08, netclient mode on UPS-powered hosts) | lab-08, lab-01, lab-04 |
| wireguard | WireGuard native install + config | wireguard |
| pbs | Proxmox Backup Server configuration (ZFS mirror, datastore, users, retention, Vault creds) | pbs |
| backup | Service backup (stop, tar, age encrypt, S3 upload; supports pre_commands for pg_dump/mysqldump, extra_paths, systemd services) | lab-08, ghost, mealie, vaultwarden, actualbudget, patchmon, authentik, foundryvtt, roundcube |
| restic-server | Restic REST server (append-only, private repos, htpasswd auth, systemd, iptables) | lab-01 |
| restic-backup | Restic backup client (per-service scripts, cron, repo init, retention pruning, weekly integrity check) | ghost, vaultwarden, mealie, actualbudget, foundryvtt, roundcube, authentik, patchmon |
| macos-launchd | macOS LaunchDaemon management | vault-1 |
| macos-homebrew | Homebrew package management for macOS | vault-1 |
| macos-ssh | SSH hardening for macOS | vault-1 |
| macos-pf | macOS pf firewall configuration | vault-1 |
| proxmox-disks | Proxmox disk management | Proxmox VMs with data disks |
| wazuh-agent | Wazuh agent enrollment | ✅ 33 hosts enrolled 2026-03-01 |
| honeypot | Cowrie + OpenCanary + Dionaea + Endlessh + Grafana Alloy honeypot deployment | lab-honeypot (dedicated Hetzner server) |
| hetzner-gateway | Full gateway stack (10 Docker services: Traefik, WireGuard, AdGuard, Gotify, Uptime Kuma, CrowdSec, Fail2ban, Watchtower, node_exporter, Alloy) + Docker daemon log rotation + logrotate | lab-hetzner |
| patchmon | PatchMon server Docker Compose deployment (PostgreSQL + Redis + backend + frontend); post_tasks: admin login via /api/v1/auth/login + enrollment token creation | patchmon |
| patchmon-agent | PatchMon agent install via auto-enrollment (deps + curl enrollment script, idempotent) | patchmon_agent_targets (all Linux hosts) |
| vaultwarden | Vaultwarden Docker Compose deployment (password vault with Authentik OIDC SSO) | vaultwarden |
| archive | Prepper archive appliance (Docker Compose: Kiwix, ArchiveBox, BookStack, Stirling PDF, Wallabag, FileBrowser, TileServer GL, Calibre-Web + ZIM auto-sync + map-download + disk setup + logrotate + NFS) | archive (ZimaBlade 7700) |
| proxmox-gpu | Proxmox host GPU passthrough prep (IOMMU, VFIO, driver blacklist) | lab-01 |
| ai-gpu | AI GPU guest VM (ROCm drivers + Ollama/Open WebUI/n8n Docker Compose) | ai-gpu |
| truenas | TrueNAS SCALE appliance config (services, NFS/SMB shares, snapshots, SMART tests, scrubs) via arensb.truenas collection | truenas |
| plex | Plex Docker deployment | **Orphaned — no playbook uses it** |

### SSH Access Patterns

| Target | SSH User | Key | Jump Host |
|--------|----------|-----|-----------|
| Proxmox nodes | admin | `~/.ssh/id_ed25519_lab-{01,02,03,04}` | Direct |
| Vault nodes | admin (Linux), admin (macOS) | Per-host keys | Direct |
| lab-08 | admin | `~/.ssh/id_ed25519_lab-08` | Direct (VLAN 1) |
| Core infra | admin | `~/.ssh/id_ed25519_{gitlab,gitlab-runner}`, Terraform `.secrets/authentik_ssh_key` | Direct |
| RKE2 nodes | admin | Terraform-generated `.secrets/` | Via lab-01 jump |
| Standalone services | root (LXC), admin (VM) | Terraform-generated `.secrets/` | Via lab-01 jump (VLAN 20) |
| DMZ services | root | Terraform-generated `.secrets/` | Via lab-01 jump |
| TrueNAS | truenas_admin | `~/.ssh/truenas_admin` (port 2222) | Direct (VLAN 40) |
| Hetzner | root | `~/.ssh/id_ed25519_lab-hetzner` (port 2222) | Direct |

---

## Known Issues and Gaps

### Critical

1. **RKE2 workstation access** — ✅ **FIXED.** Root cause was stale `lan_network: 192.168.1.0/24` in Ansible (actual subnet is `10.0.4.0/24`). UFW rules updated on all 6 nodes.

2. **ArgoCD apps blocked by PodSecurity** — ✅ **FIXED.** PSA labels added to all ArgoCD Application manifests. Pushed to GitLab, ArgoCD auto-synced.

3. **External-secrets crash-looping** — ✅ **FIXED.** Multiple issues resolved: ServerSideApply for large CRDs (256KB annotation limit), ClusterSecretStore API v1beta1→v1. ESO running and healthy.

4. **Longhorn not deploying** — ✅ **FIXED.** Pre-upgrade hook deadlock (Job references ServiceAccount not yet created). Disabled with `preUpgradeChecker.jobEnabled: false`. 40+ pods running, StorageClass created, PVCs bound.

5. **Traefik template error** — ✅ **FIXED.** Chart v34 removed `redirectTo` syntax. Values updated to `redirections.entryPoint` format. Traefik Synced/Healthy.

6. **SonarQube deployment failures** — ✅ **FIXED.** Image updated to `26.1.0.118079-community` (2026 LTS). GID fixed (1000 → 0). Postgres `16.11-alpine` with init container for volume permissions. Running and healthy.

### Documentation Mismatches (Fixed in this doc)

3. **NETWORK.md Security VLAN table** — ✅ **FIXED.** Corrected to show only vault-2 and scanner sub-interface. Note added clarifying GitLab is on VLAN 10 and Wazuh Manager is not deployed.

4. **NETWORK.md TrueNAS IP** — ✅ **RESOLVED 2026-02-23.** TrueNAS migrated to `10.0.40.2` on Storage VLAN 40. NETWORK.md and CURRENT-STATE.md now aligned.

5. **FoundryVTT host** — Some docs say lab-04. **Reality:** Terraform state shows `proxmox_node = "lab-03"` for all Layer 05 services. lab-04 hosts no VMs.

### Pending Configurations

5b. **TrueNAS media pool "unhealthy"** — ✅ **Expected behavior.** Pool ONLINE but `healthy: false` because it's a single-disk vdev (no redundancy). Not a real issue — ZFS reports unhealthy for any pool without fault tolerance.

6. **TrueNAS VLAN 40 migration** — ✅ **RESOLVED 2026-02-23.** IaC written: `truenas-migrate-vlan.yml` playbook + Terraform port profile update. Pending: run playbook + `terraform apply` Layer 00 to cut over.

7. **AllowTcpForwarding on lab-03** — Already in `proxmox_nodes.yml` group_vars (`ssh_allow_tcp_forwarding: yes`), but needs playbook run to apply to the host if not yet done.

8. **Alertmanager Gotify token** — ✅ **WIRED.** ESO ExternalSecret syncs `secret/k8s/alertmanager` → `alertmanager-config` Secret. Token stored in Vault, Alertmanager consuming via `configSecret`. Webhook targets Gotify at `http://10.8.0.1:8080` via WireGuard tunnel.

9. **Longhorn S3 backup** — ⚠️ **DISABLED** (2026-02-15). S3 backup target removed to control Hetzner costs (PVCs total 110+ Gi). Local 6-hourly snapshots (retain 12, 3-day window) remain active.

10. **Vault Kubernetes auth** — ✅ **APPLIED 2026-02-16.** ESO `k8s-external-secrets` policy includes `secret/data/infra/cloudflare` read access. All 6 K8s Let's Encrypt certificates READY=True. ArgoCD OIDC ExternalSecret synced.

### Orphaned Code

11. **`ansible/roles/plex/`** — Full role with no playbook. Plex runs as TrueNAS app (not Ansible-managed).

12. **`ansible/roles/wazuh-agent/`** — ✅ **RESOLVED 2026-03-01.** Fleet deployed via `wazuh-agent-deploy.yml`. 33 hosts enrolled.

---

## Pending Work

### Immediate (unblock remaining apps)

- [x] Diagnose RKE2 workstation access — **fixed: stale `lan_network` subnet**
- [x] Fix ArgoCD PSA labels — **fixed: 8 Application manifests updated, pushed, synced**
- [x] Fix external-secrets — **fixed: ServerSideApply + v1 API + CRD sync**
- [x] Fix Longhorn — **fixed: pre-upgrade hook disabled, 40+ pods running**
- [x] Seed Grafana admin credentials in Vault — **fixed: Terraform random_password → Vault → ESO → K8s Secret**
- [x] Seed SonarQube DB credentials in Vault — **fixed: Terraform random_password → Vault → ESO → K8s Secret**
- [x] Push Traefik `redirections` syntax fix — **fixed: traefik-config + longhorn-config now Synced/Healthy**
- [x] Push SonarQube image tag + postgres permissions fix — **fixed: 26.1.0.118079-community, GID 0, running**
- [x] Fix Mealie RWO PVC deadlock — **fixed: `strategy: Recreate`, upgraded to v3.10.2**
- [x] Fix Longhorn ArgoCD delete loop — **fixed: `ignoreDifferences` + finalizer removal**
- [x] Resolve gatekeeper/gatekeeper-policies OutOfSync — **removed** (Gatekeeper + policies deleted from RKE2 cluster)
- [x] Fix DHCP DNS for internal resolution — **applied 2026-02-16**:
  - [x] `terraform apply` Layer 02 (ESO policy for `secret/data/infra/cloudflare`)
  - [x] ESO synced: all ExternalSecrets `SecretSynced`
  - [x] All 6 K8s Let's Encrypt certificates READY=True
  - [x] `terraform apply` Layer 00 (DHCP DNS: gw-01 gateway first per VLAN)
  - [x] Manual: UniFi UI > Default LAN > DHCP DNS → `10.0.4.1`
  - [x] Mac DHCP lease renewed, DNS resolving correctly via gw-01
  - [x] `nslookup argocd.home.example-lab.org` → `10.0.20.220` ✅

### New Services (IaC ready 2026-02-16)

- [x] ~~Deploy Home Assistant on RPi 5 4GB~~ — **deployed 2026-02-19, decommed 2026-03-01** (RPi 5 removed)
- [x] Redeploy Home Assistant on CM4 8GB (lab-11) — **deployed 2026-03-01**
  - [x] Layer 00: IoT VLAN 60, zone policies, IoT Access port profile, DNS record (all still in place)
  - [x] Layer 00: Port override updated — switch-02 port 8 (was switch-03 port 2)
  - [x] Layer 02: Vault secret `services/homeassistant` (host/port unchanged, api_token needs regeneration)
  - [x] Layer 03: GitLab repo `infrastructure/homeassistant` + deploy token (still in place)
  - [x] Layer 07: ForwardAuth proxy provider + admin-only policy (still in place)
  - [x] Traefik: Backend `homeassistant` → `http://10.0.60.10:8123` (still in place)
  - [x] `terraform apply` Layer 00 (port override for switch-02 port 8)
  - [x] Flash HAOS to NVMe SSD via USB enclosure (CM4 EEPROM updated for USB boot via raspi-config)
  - [x] First boot, configure static IP 10.0.60.10 via HAOS network settings
  - [x] Restore config from GitLab repo via Git Pull add-on (direct clone to /config/)
  - [x] SSH + Terminal add-ons configured
  - [x] Traefik proxy UFW updated: added `iot_network` to `traefik_proxy_firewall_sources`
  - [x] Proxmox iptables updated: added `iot_network` to port 8006 allow rules
  - [x] Proxmox HA API token: `homeassistant@pam!ha-readonly-token` (PVEAuditor, read-only)
  - [x] HA monitoring integrations: Proxmox VE, UniFi, Uptime Kuma, System Monitor, Vault REST sensors
  - [x] Mushroom Cards dashboard (HACS)
  - [ ] Generate new HA long-lived access token, update in Vault: `secret/services/homeassistant`
  - [ ] Verify: `https://homeassistant.home.example-lab.org` through Traefik + Authentik ForwardAuth

- [x] Deploy Vaultwarden — **deployed 2026-02-17** (Argon2 admin token, admin + user user invites, 1Password data imported)
- [x] ~~Deploy Archive VM~~ — **Cancelled** (migrating to dedicated ZimaBlade 7700). VM 5034 removed from Terraform.
- [x] Deploy Archive Appliance (ZimaBlade 7700) — **deployed 2026-02-17**:
  - Ubuntu 24.04 on eMMC, 2TB USB SSD + PS4 HDD formatted/mounted by Ansible
  - Bootstrap: `archive-bootstrap.yml` (3-play: diagnostic → setup+static IP → hardening)
  - Deploy: `archive-deploy.yml` (common → hardening → docker → archive → backup)
  - Terraform: Layer 00 (DNS + switch port), Layer 02 (Vault secrets + APP_KEY), Layer 07 (6 ForwardAuth providers)
  - Traefik: 6 backends via `traefik-proxy-deploy.yml`, HTTPS + Authentik ForwardAuth
  - ZIM content: ~417 GB downloaded (Wikipedia, StackOverflow, Gutenberg, iFixit, + 8 more)
  - Automation: monthly ZIM auto-sync cron (discovers latest versions, downloads deltas, restarts Kiwix), daily S3 backup (age-encrypted to Hetzner), PatchMon agent enrolled
  - Services running: FileBrowser (8080), Kiwix (8081), ArchiveBox (8082), BookStack (8083), Stirling PDF (8084), Wallabag (8085)
  - Services coded (pending deploy): TileServer GL (8086, offline maps via OpenFreeMap), Calibre-Web (8087, ebook library)
- [x] Deploy AI GPU VM — **deployed 2026-02-17**:
  1. ~~`ansible-playbook proxmox-gpu-setup.yml`~~ — ✅ Done (IOMMU + VFIO + d3cold, host power-cycled)
  2. ~~`terraform apply` Layer 05~~ — ✅ Done (VM 5035 running, GPU passthrough + hookscript verified)
  3. ~~Add DNS + Traefik config~~ — ✅ Done (openwebui + n8n)
  4. ~~`terraform apply` Layer 00 (DNS records)~~ — ✅ Applied
  5. ~~`ansible-playbook traefik-standalone-deploy.yml`~~ — ✅ Applied (Traefik backends for openwebui + n8n)
  6. ~~`ansible-playbook ai-gpu-deploy.yml`~~ — ✅ Applied (ROCm + Ollama + Open WebUI + n8n)
  7. Open WebUI SSO via Authentik OIDC ✅, n8n behind ForwardAuth ✅, n8n admin creds in Vault ✅
- [x] Apply Authentik Hetzner bookmarks — **applied** (`terraform apply` Layer 07, 4 bookmark apps + Vaultwarden OIDC)
- [x] Add Vaultwarden + AI GPU + Archive to standalone Traefik proxy config — **deployed 2026-02-17** (6 archive backends applied via `traefik-proxy-deploy.yml`; vaultwarden, openwebui, n8n DNS + backends coded, pending `terraform apply` Layer 00 + Traefik redeploy).

### Disk Performance & TRIM Optimization (2026-02-20)

- [x] Audit all VM disk flags — **all VMs had discard=ignore, ssd=0, iothread=0** (bpg/proxmox provider overrides Packer template settings on clone)
- [x] Terraform module fix — added `disk_discard`, `disk_ssd`, `disk_iothread` variables to `proxmox-vm` module
- [x] Packer template fix — added `io_thread = true` to all 3 templates (ubuntu-24.04, rocky-9, pbs)
- [x] Ansible remediation — `proxmox-disk-remediate.yml` ran `qm set` on all VMs across all 4 nodes (discard=on, ssd=1, iothread=1)
- [x] fstrim.timer — deployed to all Linux VMs via common role (26 hosts, 7 LXC/macOS correctly skipped)
- [x] Terraform layers 04 + 05 applied — disk attributes aligned in state (in-place update, no destroy/recreate)
- [x] fstab nofail fix — `proxmox-fstab-nofail.yml` remediated all nodes; `proxmox-disks` role defaults updated to include nofail
- [x] All 4 Proxmox nodes successfully rebooted:
  - lab-01: Clean (no HDD fstab entries)
  - lab-02: Required `pvesm add dir hdd-data-0` re-registration after reboot (storage config lost) — hdd-data-0 (USB) since decommissioned; GitLab data disk migrated to local-lvm
  - lab-03: Clean (WireGuard LXC startup delay caused brief Ghost/blog.example-lab.org outage — resolved automatically)
  - lab-04: Hit emergency mode (fstab nofail was missing for HDD mounts — fixed at console, then codified)
- [x] Vault cluster verified healthy post-reboot (3/3 nodes, transit auto-unseal worked for vault-2)
- [ ] **lab-01: Move Longhorn data disks from local-lvm → nvme-thin-1 (2TB NVMe)** — IaC ready (`data_storage_pool` var threaded through Layer 04 → proxmox-rke2-cluster → proxmox-vm). Apply with `terraform apply -var 'data_storage_pool=nvme-thin-1'` in Layer 04. Check `terraform plan` first — if bpg/proxmox does in-place disk move, apply directly; if destroy/recreate, use `-target` rolling approach (drain node, apply, verify Longhorn replicas, next node).
- [x] **lab-01: 2x 3.6TB HDDs → hdd-mirror-0 ZFS mirror** — ✅ ZFS pool created (ONLINE), Proxmox storage registered as `dir` storage (hdd-mirror-0-dir) for file-based content (backup,iso,vztmpl,snippets).
- [x] **Deploy Backup LXC (Restic REST server + Backrest UI)** — ✅ **Deployed.** LXC 5040 on lab-01, bind-mounts hdd-mirror-0/restic → /mnt/restic. REST server on 0.0.0.0:8500 (append-only, htpasswd, private-repos). Backrest v1.11.2 on 127.0.0.1:9898 (read-only monitoring, SSH tunnel access only). ⚠️ **Backups have stopped running in recent days — needs investigation.**
- [ ] **Deploy Restic backups to all 8 services** — Re-run each service deploy playbook with `--tags restic-backup` after REST server is live on new IP (10.0.10.18:8500). All 8 playbooks updated to use `{{ restic_server_ip }}:{{ restic_server_port }}` from group_vars/all.yml. After verification, decommission old rest-server on lab-01 (`systemctl stop/disable restic-rest-server`, remove binary/config/iptables rules).

### Short-term

- [x] Apply Layer 00 DNS records (`terraform apply` — adds `unifi_dns_record` resources for `*.home.example-lab.org`) — **applied 2026-02-15**
- [x] Push K8s domain migration to GitLab (ArgoCD syncs new hostnames + Let's Encrypt issuer + IngressRoutes) — **pushed 2026-02-15**
- [x] Verify internal DNS resolution + HTTPS from workstation (`dig mealie.home.example-lab.org`, `curl https://mealie.home.example-lab.org`) — **verified 2026-02-15**
- [x] Deploy Authentik VM on lab-04 (`terraform apply` Layer 02 + Layer 05 + `ansible-playbook authentik-deploy.yml`) — **deployed 2026-02-15**
- [x] Apply Terraform Layer 07-authentik-config — **applied 2026-02-16** (8 OIDC providers, 4 ForwardAuth proxies, 2 groups, embedded outpost, Vault OIDC secrets)
- [ ] Wire K8s + GitLab SSO (Grafana, ArgoCD, Headlamp, Longhorn, GitLab OIDC) — **partially deployed 2026-02-16**:
  - [x] Push K8s changes to GitLab → ArgoCD synced (ExternalSecrets, ArgoCD config + IngressRoute + cmd-params-cm)
  - [x] ArgoCD UI accessible at `https://argocd.home.example-lab.org` (basic auth working)
  - [ ] ArgoCD OIDC: ESO force-synced with fresh creds 2026-03-01 after Authentik DB rebuild — may be resolved, needs verification
  - [x] GitLab OIDC: ✅ Confirmed working 2026-03-01 — re-credentialed after Authentik fresh DB + Layer 07 re-apply
  - [x] Groups scope: not needed — Authentik's built-in `profile` scope already includes `groups` claim
  - [x] Grafana OIDC: ✅ Working on K3s RPi5 cluster (migrated from RKE2)
  - [ ] Headlamp OIDC: ESO synced, pending ArgoCD sync of Headlamp values
  - [ ] Verify SSO login for all services
- [ ] Wire standalone services SSO (NetBox, Mealie, Ghost, Roundcube, FoundryVTT — deferred to future session)
- [ ] Wire infrastructure SSO (Vault UI, Proxmox VE — deferred to future session)
- [x] Deploy standalone Traefik reverse proxy — **deployed 2026-02-16**:
  - [x] LXC created (VM 5033, 10.0.10.17)
  - [x] ForwardAuth providers applied in Layer 07
  - [x] Traefik deployed via `ansible-playbook traefik-proxy-deploy.yml`
  - [x] DNS records applied (Layer 00) — 11 services → 10.0.10.17
  - [x] All 10 backends proxied with valid Let's Encrypt TLS certificates
  - [x] Verified: GitLab, Mealie, Authentik accessible via `*.home.example-lab.org`
- [ ] Deploy Renovate Bot + ArgoCD Image Updater (`terraform apply` Layer 03 → push to GitLab → ArgoCD syncs image updater → trigger manual Renovate run)
- [x] Deploy NetBox VM on lab-04 (`terraform apply` Layer 05 + `ansible-playbook netbox-deploy.yml`) — **deployed 2026-02-14**
- [x] Run `scripts/netbox-seed.py` to populate NetBox with infrastructure data — **seeded 2026-02-14**
- [x] Bootstrap lab-08 — **deployed 2026-02-15** (NetworkManager static IP, CIS L1 hardening, ARM64 auditd compat)
- [x] Deploy Scanopy + NUT on lab-08 — **deployed 2026-02-15** (Web UI live, admin onboarded, NUT monitoring CyberPower UPS)
- [x] Verify NUT remote access: `upsc ups@10.0.4.20` — **verified: battery 100%, OL, 26% load**
- [x] Fix Scanopy daemon provisioning — **fixed 2026-02-15** (automated via `/api/v1/daemons/provision`, API key + network_id in Vault)
- [x] Fix Scanopy daemon mode (ServerPoll → DaemonPoll) — **fixed 2026-02-15** (idempotent mode fix: detect/delete ServerPoll, restart daemon, removed INTEGRATED_DAEMON_URL)
- [x] Deploy Headlamp K8s dashboard on RKE2 — **deployed 2026-02-15** (read-only RBAC, agent-node affinity, SA token in Vault)
- [x] Add Rover TF plan visualization to CI pipeline — **deployed 2026-02-15** (9 layers, `visualize` stage between plan/apply). **Updated 2026-02-20:** Rover jobs switched to `needs: optional: true` so they proceed even when plan produces no artifacts.
- [x] Add D2 diagram-as-code rendering to CI pipeline — **deployed 2026-02-15** (3 architecture diagrams, SVG artifacts). Note: SVGs are CI artifacts only (30-day expiry), not committed to repo. Download from pipeline job artifacts page. **Updated 2026-02-20:** Wiki publish job renders SVGs inline (`![]()`), not as download links.
- [x] Fix CI pipeline layer naming bugs — **fixed 2026-02-15** (02-vault split, 03-gitlab-config added, 04-k3s→rke2 renamed)
- [x] Trigger first multi-VLAN network scan via Scanopy UI — **executed** (VLAN sub-interfaces configured, scans run)
- [x] Longhorn auth — **replaced 2026-02-16**: basic-auth middleware swapped for Authentik ForwardAuth (pending git push + ArgoCD sync)
- [ ] Test Roundcube, FoundryVTT, and Mealie through WireGuard tunnel
- [x] Fix NETWORK.md documentation mismatches — **fixed 2026-02-15** (k3s→RKE2, lab-04 role, Plex references, MetalLB config path)
- [ ] Run `harden.yml` on any hosts that haven't received it
- [ ] Apply AllowTcpForwarding to lab-03 if not yet done

### Infrastructure Restructuring (IaC Ready 2026-03-01)

All code changes committed. Deployment sequence below. Jordan runs all apply commands.

**Phase 1 — Remove SonarQube + Gatekeeper (code done):**
- [x] Delete K8s manifests: `k8s/argocd/apps/sonarqube.yml`, `k8s/argocd/apps/gatekeeper*.yml`, `k8s/workloads/sonarqube/`, `k8s/platform/gatekeeper/`
- [x] Remove `"sonarqube"` from DNS Layer 00, remove Vault secrets from Layer 02
- [ ] `terraform apply` Layer 00 (DNS cleanup)
- [ ] `terraform state rm` sonarqube resources in Layer 02, then `terraform apply`
- [ ] Git push → ArgoCD auto-prunes SonarQube + Gatekeeper namespaces

**Phase 2 — Drain + remove RKE2 agent-3 (code done):**
- [x] `worker_count` 3→2 in Layer 04 variables, agent-3 removed from Ansible inventory
- [ ] `kubectl drain rke2-agent-3 --ignore-daemonsets --delete-emptydir-data --timeout=300s`
- [ ] Wait for Longhorn volumes healthy, `kubectl delete node rke2-agent-3`
- [ ] `terraform apply` Layer 04 (destroys VM 4005)

**Phase 3 — Downsize RKE2 servers 4C/6G→2C/4G (code done):**
- [x] `master_cpu_cores` 4→2, `master_memory_mb` 6144→4096 in Layer 04 variables
- [ ] Rolling `terraform apply -target` per server (maintain etcd quorum 2/3)

**Phase 4 — Downsize FoundryVTT 4G→2G:** ✅ **Applied 2026-03-01**
- [x] `foundryvtt_memory_mb` 4096→2048 in Layer 05 variables
- [x] `terraform apply` Layer 05

**Phase 5 — Layer 03 per-service node variables:** ✅ **Applied 2026-03-01**
- [x] Added `gitlab_proxmox_node`, `gitlab_data_storage_pool`, `gitlab_storage_pool`, `gitlab_runner_proxmox_node` to Layer 03
- [x] Wired into module calls + added SSH key injection
- [x] `proxmox_node_ips` local in providers.tf

**Phase 6 — Move Authentik to lab-01:** ✅ **Deployed 2026-03-01**
- [x] `authentik_proxmox_node` lab-04→lab-01, `authentik_memory_mb` 2048→4096 in Layer 05
- [x] Backup: `docker exec authentik-db pg_dump` (container name was `authentik-db`, not `authentik-postgresql`)
- [x] `terraform apply` Layer 05 (destroyed on lab-04, created on lab-01)
- [x] `ansible-playbook authentik-deploy.yml`
- [x] `terraform apply` Layer 07 (recreated all OIDC providers)
- [x] **PBS restore + fresh DB rebuild (2026-03-01):** OIDC client_secret mismatch after initial migration. Destroyed VM, PBS-restored from `pbs-backup:backup/vm/5021/2026-03-01T06:00:02Z` to nvme-thin-1, wiped Postgres bind mount (`/opt/authentik/postgres`), fresh Layer 07 apply. Added `authentik_storage_pool` variable (same pattern as GitLab). All OIDC services re-credentialed: GitLab, Actual Budget, PatchMon, Vaultwarden, Open WebUI (deploy playbooks), ArgoCD + Grafana (ESO force-sync). GitLab OIDC login confirmed working.

**Phase 7 — Move GitLab VM to lab-01:** ✅ **Deployed 2026-03-01 (PBS restore)**
- [x] `gitlab_proxmox_node` lab-02→lab-01, storage pools updated to `nvme-thin-1`
- [x] Layer 03 applied (destroyed on lab-02, created on lab-01)
- [x] Fresh VM was inadequate — PBS-restored from `pbs-backup:backup/vm/3001/2026-03-01T06:00:03Z` via `qmrestore` to `nvme-thin-1` (53GB in 47s at 1GB/s)
- [x] `ansible-playbook gitlab-deploy.yml` — applied letsencrypt disable + GPG key refresh
- [x] Terraform state reconciled: `state rm` + `import lab-01/3001`
- [x] All 15 GitLab services healthy, git push/pull working

**Phase 8 — Deploy GitLab CE Helm on RKE2:** ✅ **ArgoCD synced 2026-03-01**
- [x] Vault secrets `k8s/gitlab` in Layer 02, DNS `gitlab-test` in Layer 00
- [x] ArgoCD Application `k8s/argocd/apps/gitlab.yml`, Helm values, ESO ExternalSecret
- [x] `terraform apply` Layer 00 (DNS) + Layer 02 (Vault secrets)
- [x] Git push → ArgoCD synced GitLab CE chart (testing instance, health Unknown)

**Phase 9 — Deploy Wazuh on RKE2:** ✅ **Deployed 2026-03-01**
- [x] Vault secrets `k8s/wazuh` in Layer 02, DNS `wazuh` in Layer 00
- [x] ArgoCD Application + K8s manifests (Manager StatefulSet, Indexer StatefulSet, Dashboard Deployment)
- [x] MetalLB LoadBalancer service on 10.0.20.221 (agent enrollment 1514/1515)
- [x] Git push → ArgoCD synced Wazuh (Manager + Indexer + Dashboard all 1/1 Running)
- [x] Config fixes: PodSecurity enforce=privileged, DISABLE_SECURITY_PLUGIN, removed legacy config keys

**Phase 10 — Deploy Wazuh agents:** ✅ **Fleet deployed 2026-03-01**
- [x] `wazuh_enabled: true`, `wazuh_manager_ip: 10.0.20.221` in group_vars
- [x] `wazuh-agent-deploy.yml` playbook created (targets all Linux hosts, reads enrollment password from Vault)
- [x] `ansible-playbook wazuh-agent-deploy.yml` — 33 hosts enrolled, vault-1 skipped (macOS), gitlab-runner failed (LXC connectivity)

**Target final state:**

| Node | Workloads | Allocated |
|------|-----------|-----------|
| lab-01 (24T/64G) | RKE2 3+2 (14C/32G) + GitLab VM (4C/8G) + Authentik VM (2C/4G) + Backup LXC (2C/1G) | 22C / 45G |
| lab-02 (4T/16G) | vault-2 (2C/2G) + GitLab Runner LXC (2C/4G) | 4C / 6G |
| lab-03 (4T/12G) | FoundryVTT (2C/2G downsized) + 7 LXCs (4.8G) | 9C / 6.8G |
| lab-04 (4T/20G) | PBS + NetBox + PatchMon + Traefik Proxy (Authentik removed) | 7C / 10.5G |

### Medium-term

- [x] Deploy NUT clients on UPS-powered hosts — **deployed 2026-02-15** (lab-01 + lab-04, coordinated shutdown with lab-08 NUT server)
- [x] Enable multi-VLAN scanning for Scanopy — Scanner Trunk port profile + 802.1Q sub-interfaces on lab-08 (VLANs 10/20/30/40/50 at .90)
- [x] Deploy Vault backup automation — **deployed 2026-02-15** (6-hourly Raft snapshots, age-encrypted, S3 + RPi5 copy, macOS LaunchDaemon)
- [x] Deploy GitLab backup automation — **deployed 2026-02-15** (daily gitlab-backup + age + S3 upload, secrets.json included). **Updated 2026-02-18:** incremental backups (Sun=full, Mon-Sat=incremental), upload verification, logrotate, `gitlab_backup_enabled` committed to `host_vars/gitlab.yml`
- [x] Deploy Longhorn snapshots — **deployed 2026-02-15** (6h local snapshots, retain 12). S3 backup disabled 2026-02-15 (cost control).
- [x] Deploy Docker volume backup on lab-08 — **deployed 2026-02-15** (backup role: stop containers, tar, age encrypt, S3 upload, restart)
- [x] Deploy Ghost + Mealie S3 backup — **deployed 2026-02-15** (backup role with bind-mount paths, daily age-encrypted uploads to firblab-service-backups)
- [x] Deploy Proxmox vzdump backup — **deployed 2026-02-15** → **replaced by PBS 2026-02-15** (vzdump crons retired, PBS on lab-04 manages all backups centrally with dedup)
- [x] Deploy PBS (Proxmox Backup Server) — **deployed 2026-02-15** (PBS 4.1.2/Debian 13, VM 5031 on lab-04, ZFS mirror ~14.6 TB HDD passthrough, registered on all 4 PVE nodes, backup jobs at 01:00 daily, credentials in Vault)
- [x] Deploy CI/CD tfstate backup — **deployed 2026-02-15** (terraform-apply template: age-encrypted tfstate upload to S3 per-apply)
- [x] Trim S3 backup strategy — **2026-02-15** (removed vzdump S3 + Longhorn S3, added Ghost/Mealie S3, Vault retention 90d→30d, tfstate now age-encrypted). **Updated 2026-02-18:** server-side S3 lifecycle policies (30-day expiration) applied to all 5 backup buckets, script-based S3 cleanup removed from all backup scripts
- [x] Create S3 backup buckets — **deployed 2026-02-15** (Layer 06: firblab-vault-backups, firblab-gitlab-backups, firblab-longhorn-backups, firblab-service-backups, firblab-proxmox-backups, firblab-tfstate-backups). **Updated 2026-02-18:** inline lifecycle_rule (30-day expiration) added to 5 backup buckets in Terraform; tfstate-backups intentionally excluded (no auto-expiry on state backups)
- [x] Write Disaster Recovery runbook — **deployed 2026-02-15** (docs/DISASTER-RECOVERY.md: service dependency tree, RPO/RTO targets, restore procedures, power outage scenarios)
- [x] Wire Scanopy discovery data into NetBox — **deployed 2026-02-16** (`scripts/scanopy-netbox-sync.py`: 47 hosts from Scanopy, 54 interfaces, 22 matched existing NetBox objects, 20 new IPs created, 5 skipped)
- [x] Configure Proxmox auto-import plugin in NetBox — **attempted 2026-02-16** (plugin incompatible with NetBox 4.5.2, gracefully skipped with warning. Manual VM inventory via netbox-seed.py instead.)
- [x] Add interfaces and cables to NetBox seed script — **coded 2026-02-16** (`netbox-seed.py`: device interfaces, VM interfaces, IP→interface assignments, 9 physical cables, primary IP assignment). Enables netbox-topology-views rendering. Pending: re-run `netbox-seed.py`.
- [x] NetBox → D2 diagram generator — **coded 2026-02-16** (`scripts/netbox-to-d2.py`: queries NetBox API for devices, VMs, VLANs, IPs, cables → generates `docs/diagrams/network-topology.d2`). CI triggers on `.d2` file changes. Pending: deploy NetBox, seed, run generator.
- [x] PatchMon onboarding + agent fleet deployment — **deployed 2026-02-16**: enrollment token created via onboarding, stored in Vault. 26 of 29 Linux hosts enrolled (hetzner/vault-2/wireguard expected failures).
- [x] TrueNAS IaC deployment — **deployed 2026-02-23**: `ansible-playbook truenas-deploy.yml` (security fixes: NFS network restrictions, SMB guest access disable; protection: daily snapshots, SMART tests, scrubs). Vault secret pending: generate API key in TrueNAS UI, seed manually via `vault kv put secret/infra/truenas api_url=... api_key=... hostname=... ip=...`.
- [x] Migrate TrueNAS to VLAN 40 — **IaC ready 2026-02-23**: `truenas-migrate-vlan.yml` playbook (midclt network reconfig via SSH) + Terraform Layer 00 port profile update. Pending: run playbook + `terraform apply` to execute cutover.
- [x] Deploy Wazuh Manager on RKE2 K8s cluster — **deployed 2026-03-01** (Manager + Indexer + Dashboard on RKE2, MetalLB VIP 10.0.20.221)
- [x] Deploy Hetzner gateway full Ansible stack — **deployed 2026-02-25**: `gateway-deploy.yml` run, all 10 containers running. `terraform apply` Layer 06 applied (Vault credentials seeded). Prometheus scrape targets configured (`additionalScrapeConfigs`). Note: verify WireGuard route `ip route show | grep 10.8.0` on RKE2 node for Prometheus pull to work.
- [x] Set up real Alertmanager → Gotify webhook — **wired**: ESO ExternalSecret syncs Vault token → `alertmanager-config` K8s Secret → Alertmanager `configSecret`
- [x] Longhorn ExternalSecret for auth — **superseded 2026-02-16**: replaced basic-auth with Authentik ForwardAuth middleware
- [x] Deploy honeypot deception system on Hetzner — **deployed 2026-02-16, removed 2026-02-16**: Honeypot removed from gateway to lock down attack surface. Ansible role + Grafana dashboard retained for reuse on dedicated honeypot server.
- [x] Wire Promtail → Loki pipeline — **IaC ready 2026-02-16**: Loki NodePort 31100 in values.yaml, port 31100 added to Layer 00 `homelab_service_ports`. Pending: `terraform apply` Layer 00, git push → ArgoCD sync.
- [x] Build Grafana "Honeypot SOC" dashboard — **IaC ready 2026-02-16**: ConfigMap in `k8s/platform/monitoring/dashboards/`, ArgoCD app `monitoring-dashboards`. Retained for dedicated honeypot server.
- [x] Deploy dedicated Hetzner honeypot server — **deployed 2026-02-24**: cpx22 Nuremberg (203.0.113.11), 5 containers (Cowrie, OpenCanary, Dionaea, Endlessh, Grafana Alloy). WireGuard client tunnel to gateway for log shipping to Loki. Terraform writes IP to Vault; Ansible resolves at deploy time.
- [x] Automate Scanopy → NetBox sync — **coded 2026-02-18** (daily cron at 05:00 on lab-08, Vault creds baked into env file by Ansible Scanopy role). Pending: `ansible-playbook lab-08-deploy.yml --tags scanopy,netbox-sync`
- [x] NetBox Terraform provider (Layer 08) — **deployed 2026-02-18** (e-breuninger/netbox v5.1.0, 94 resources: 21 Proxmox VMs + Hetzner gateway + interfaces + IPs + primary IPs + foundation. Seed script trimmed to physical infra + vault-2 only.)

### Future

- [x] Deploy Rover TF plan visualization in CI pipeline — **deployed 2026-02-15**
- [x] Deploy D2 diagram-as-code pipeline — **deployed 2026-02-15**
- [ ] Add TrueNAS NFS as PBS secondary datastore (VLAN 40 migration IaC ready — pending cutover execution)
- [ ] NetBox as Ansible dynamic inventory source (replace static hosts.yml)
- [ ] Auto-generate D2 diagrams on schedule via NetBox → D2 pipeline (CI scheduled job + netbox-to-d2.py)
- [x] Expose NetBox via Traefik reverse proxy — **included in standalone Traefik proxy (IaC 2026-02-16)**, `netbox.home.example-lab.org`
- [ ] Tighten LAN → all ALLOW policies after port profiles fully enforced
- [x] Enable Wazuh agents on all hosts — **deployed 2026-03-01** (33 hosts enrolled via `wazuh-agent-deploy.yml`, gitlab-runner pending)
- [ ] Plex GPU passthrough evaluation
- [ ] Remote state backend (Hetzner S3) for Terraform layers 03+ — **blocker for CI plan/apply.** All layers currently use local backend (tfstate on workstation, not in Git). CI plan jobs run against empty state → provider API errors. Workaround (2026-02-20): `allow_failure: true` on plan template. When S3 backend is implemented, remove `allow_failure` from `.terraform-plan` in `ci-templates/terraform-ci.yml`.
