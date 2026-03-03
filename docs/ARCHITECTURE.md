# firblab: Architecture & Design

> **Note:** This document was written as the original architecture plan for the FirbLab rebuild. It describes the intended design and serves as a reference for architectural decisions. For the **actual deployed state** (what is running today, with real IPs and statuses), see [CURRENT-STATE.md](CURRENT-STATE.md). Some sections below reflect the original plan and may differ from reality (e.g., Wazuh is not deployed, vault-2 is on lab-02 not lab-01, RKE2 replaced k3s).

## Overview

Single consolidated repository at `~/repos/firblab/` managing all machines, networks, and services via IaC/GitOps. Replaces the scattered lab-01 through lab-05, lab-hetzner, firblab-aws, etc. with one source of truth.

**Core principles:** Cybersecurity-first, everything-as-code, GitOps-driven, minimal maintenance, portable, and designed for seamless iteration when adding new machines/services.

**Portability:** This repo is designed to be publicly hostable. All secrets are managed via Vault or encrypted with SOPS/age — never plaintext in the repo. `.tfvars` files use `.tfvars.example` templates with placeholder values. Anyone with similar hardware (Proxmox + Hetzner + UniFi) can clone this repo, fill in their own values, and deploy a complete secure homelab.

---

## Hardware Inventory

| Machine | Hardware | Role | Network |
|---|---|---|---|
| **lab-01** | i9-12900K, 64 GB RAM | Main compute — RKE2 cluster (6 VMs) | All VLANs (trunk) |
| **lab-02** | Intel N100, 16 GB RAM | Pilot node — GitLab, Runner, vault-2 | All VLANs (trunk) |
| **lab-03** | Intel N100, 12 GB RAM | Lightweight services — Ghost, Roundcube, Mealie, FoundryVTT, WireGuard | All VLANs (trunk) |
| **lab-04** | Dell Wyse J5005, 20 GB RAM | Lightweight compute — NetBox | All VLANs (trunk) |
| **lab-08** | RPi4, 8 GB RAM | Scanopy network scanner + NUT UPS server | Default LAN (Scanner Trunk) |
| **vault-1** | Mac Mini M4, 24 GB RAM | Vault primary (native macOS LaunchDaemon) | Management VLAN (10) |
| **vault-3** | RPi5 CM5, 16 GB RAM | Vault standby (Ubuntu 24.04 ARM64) | Management VLAN (10) |
| **TrueNAS** | i5-9500, 16 GB RAM | NFS, Plex, ZFS storage | Default LAN (pending VLAN 40) |
| **Hetzner VPS** | cpx22 (Nuremberg) | Public gateway — Traefik, WireGuard, AdGuard, monitoring | Cloud |
| **gw-01** | UniFi UDM Pro | VLAN routing, firewall, DHCP | All VLANs |

**Expansion:** Adding a machine is a config change, not a restructure — new entries in Terraform layer configs + Ansible inventory.

---

## 1. Repository Structure

**Path:** `~/repos/firblab/`

```
firblab/
├── terraform/
│   ├── modules/                        # Shared reusable modules
│   │   ├── proxmox-lxc/                # Unprivileged LXC with Docker nesting
│   │   ├── proxmox-vm/                 # Cloud-init VM (Ubuntu 24.04)
│   │   ├── proxmox-rke2-cluster/       # RKE2 master + worker provisioning
│   │   ├── hetzner-server/             # Hetzner VPS with cloud-init
│   │   ├── cloudflare-dns/             # DNS record management
│   │   └── vault-cluster/              # Vault node provisioning (cross-platform)
│   │
│   ├── layers/                         # Deployment layers (applied in order)
│   │   ├── 00-network/                 # UniFi VLANs, firewall rules, port profiles
│   │   ├── 01-proxmox-base/            # Proxmox host bridging, storage, templates
│   │   ├── 02-vault-infra/              # Vault VM provisioning (vault-2 on lab-02)
│   │   ├── 02-vault-config/            # Vault KV, PKI, policies, AppRole, secrets
│   │   ├── 03-core-infra/             # GitLab VM + Runner LXC (on lab-02)
│   │   ├── 03-gitlab-config/          # GitLab groups, projects, CI/CD vars, deploy tokens, K8s agent
│   │   ├── 04-rke2-cluster/            # RKE2 masters + workers (on lab-01)
│   │   ├── 05-standalone-services/    # Ghost, FoundryVTT, Roundcube, Mealie, WireGuard, NetBox
│   │   └── 06-hetzner/               # Hetzner server + all cloud services
│   │
│   ├── environments/
│   │   ├── lab-01.tfvars         # Per-node variable values (gitignored; optionally SOPS encrypted)
│   │   ├── lab-02.tfvars         # Pilot node variable values
│   │   ├── macmini.tfvars             # Mac Mini variable values
│   │   ├── rpi.tfvars                 # RPi5 variable values
│   │   └── hetzner.tfvars            # Hetzner variable values
│   │
│   └── backend.tf.example             # Backend config template (local → Hetzner S3)
│
├── ansible/
│   ├── playbooks/
│   │   ├── site.yml                    # Full site deployment orchestrator
│   │   ├── harden.yml                  # DevSec + CIS hardening (all hosts)
│   │   ├── proxmox-bootstrap.yml       # Bootstrap fresh Proxmox node (admin user, SSH, networking)
│   │   ├── vault-deploy.yml            # Vault cluster install, init, unseal setup
│   │   ├── vault-backup-setup.yml      # Vault 3-2-1 backup automation (macOS LaunchDaemon)
│   │   ├── rke2-deploy.yml             # RKE2 cluster bootstrap
│   │   ├── argocd-bootstrap.yml        # ArgoCD install + app-of-apps
│   │   ├── gitlab-deploy.yml          # GitLab CE + Runner setup
│   │   ├── ghost-deploy.yml           # Ghost blog deployment
│   │   ├── foundryvtt-deploy.yml      # FoundryVTT deployment
│   │   ├── roundcube-deploy.yml       # Roundcube deployment
│   │   ├── mealie-deploy.yml          # Mealie recipe manager deployment
│   │   ├── netbox-deploy.yml          # NetBox DCIM/IPAM deployment
│   │   ├── wireguard-deploy.yml       # WireGuard VPN deployment
│   │   ├── lab-08-deploy.yml      # Scanopy + NUT server deployment
│   │   ├── nut-client-deploy.yml      # NUT client on UPS-powered hosts
│   │   ├── proxmox-backup-setup.yml   # vzdump backup cron on all Proxmox nodes
│   │   └── macos-bootstrap.yml        # macOS host setup (vault-1)
│   │
│   ├── roles/
│   │   ├── common/                    # Base: updates, SSH hardening, fail2ban, chrony
│   │   ├── docker/                    # Docker CE install + daemon config
│   │   ├── hardening/                 # DevSec + CIS benchmark application
│   │   ├── wazuh-agent/              # Wazuh agent enrollment (reuse existing module)
│   │   ├── vault/                    # Vault server install + config (Linux + native macOS)
│   │   ├── vault-unseal/             # Transit auto-unseal Vault setup
│   │   ├── gitlab/                   # GitLab CE + Runner
│   │   ├── ghost/                    # Ghost blog Docker Compose
│   │   ├── foundryvtt/              # FoundryVTT application
│   │   ├── roundcube/              # Roundcube webmail + PostgreSQL
│   │   ├── mealie/                 # Mealie recipe manager
│   │   ├── netbox/                 # NetBox DCIM/IPAM
│   │   ├── scanopy/               # Scanopy network scanner
│   │   ├── nut/                    # NUT UPS monitoring (server + client)
│   │   ├── wireguard/             # WireGuard VPN
│   │   └── backup/                # Generic Docker volume backup
│   │
│   ├── inventory/
│   │   ├── hosts.yml                  # Static inventory (all machines)
│   │   └── group_vars/
│   │       ├── all.yml                # Global vars (DNS, domain, NTP)
│   │       ├── proxmox_nodes.yml      # Proxmox host group vars
│   │       ├── vault_cluster.yml      # Vault HA cluster vars
│   │       ├── rke2_cluster.yml        # RKE2 cluster config
│   │       └── macmini.yml            # Mac Mini-specific vars
│   │
│   └── ansible.cfg
│
├── k8s/                               # Kubernetes manifests for RKE2 workloads
│   ├── argocd/                        # ArgoCD bootstrap + app-of-apps
│   │   ├── install.yml
│   │   └── apps/
│   │       ├── mealie.yml
│   │       └── sonarqube.yml
│   │
│   ├── apps/                          # Application Helm charts / Kustomize
│   │   ├── mealie/
│   │   │   ├── kustomization.yaml
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   └── ingress.yaml
│   │   └── sonarqube/
│   │       ├── kustomization.yaml
│   │       └── values.yaml
│   │
│   └── platform/                      # Cluster-wide platform services
│       ├── metallb/
│       ├── cert-manager/
│       ├── traefik/
│       ├── longhorn/
│       ├── external-secrets/          # Vault → k8s Secrets sync
│       ├── gatekeeper/               # OPA/Gatekeeper policy enforcement
│       ├── trivy-operator/           # Vulnerability scanning
│       └── monitoring/               # Prometheus + Grafana + Loki
│
├── packer/                            # VM/LXC template images
│   ├── ubuntu-24.04-base.pkr.hcl     # Hardened Ubuntu template
│   └── credentials.pkr.hcl
│
├── ci-templates/                      # Shared GitLab CI templates (reuse existing)
│   ├── terraform-ci.yml
│   ├── ansible-ci.yml
│   └── kubernetes-ci.yml
│
├── scripts/
│   ├── bootstrap.sh                   # One-time initial deployment orchestrator
│   ├── vault-backup.sh               # Vault 3-2-1 backup cron script
│   ├── rotate-secrets.sh             # Vault secret rotation helper
│   └── setup-macmini-vault.sh        # Native macOS Vault setup on Mac Mini
│
├── docs/
│   ├── ARCHITECTURE.md
│   ├── NETWORK.md
│   ├── SECURITY.md
│   ├── DEPLOYMENT.md
│   ├── VAULT-OPERATIONS.md           # Vault unseal, backup, restore, rotation
│   ├── MACHINE-ONBOARDING.md         # How to add a new machine to the lab
│   └── RUNBOOKS.md
│
├── .gitlab-ci.yml
├── .gitignore                         # Excludes tfstate, tfvars, ssh keys, .terraform/
├── .sops.yaml                         # SOPS encryption config (age key)
├── .pre-commit-config.yaml
├── .editorconfig                      # Consistent formatting across editors
└── README.md                          # Quick start for anyone cloning the repo
```

### Portability: .tfvars.example Pattern

Every `*.tfvars` file has a committed `*.tfvars.example` counterpart with placeholder values:

```hcl
# terraform/environments/lab-01.tfvars.example
proxmox_api_url    = "https://10.0.10.2:8006"
proxmox_node       = "lab-01"
proxmox_token_id   = "terraform@pam!terraform-token"
proxmox_token_secret = "CHANGE_ME"
ssh_public_key     = "ssh-ed25519 AAAA... your-key"
network_bridge     = "vmbr0"
```

**`.gitignore` contents:**
```
# Terraform
*.tfstate
*.tfstate.backup
.terraform/
*.tfvars
!*.tfvars.example
crash.log
override.tf

# Secrets
.secrets/
*_ssh_key
*_ssh_key.pub
*.age
*.enc

# SOPS encrypted (committed intentionally — these are safe)
!*.sops.*

# Packer
packer_cache/

# Vault
*.snap

# OS
.DS_Store
*.swp
```

### Key Reusable Code from Existing Projects

| Existing File | Reuse In | Notes |
|---|---|---|
| `lab-01/mealie/main.tf` | `modules/proxmox-lxc/` | Extract LXC pattern into module |
| `lab-01/vault/main.tf` | `modules/proxmox-vm/` | Extract VM pattern into module |
| `lab-01/ansible/roles/docker/` | `ansible/roles/docker/` | Direct reuse |
| `lab-01/ansible/roles/common/` | `ansible/roles/common/` | Reuse + enhance |
| `lab-01/ansible/roles/mealie/` | `k8s/workloads/mealie/` | Convert to k8s manifest |
| `lab-01/ansible/roles/ghost/` | `ansible/roles/ghost/` | Direct reuse |
| `lab-01/ansible/roles/vault/` | `ansible/roles/vault/` | Direct reuse |
| `lab-01/ansible/roles/foundryvtt/` | `ansible/roles/foundryvtt/` | Direct reuse |
| `lab-01/ansible/roles/plex/` | `ansible/roles/plex/` | Direct reuse |
| `lab-01/cybersecurity/wazuh-agents/` | `ansible/roles/wazuh-agent/` | Reuse module |
| `lab-01/packer/` | `packer/` | Reuse hardened templates |
| `lab-01/prox-k3s/` | `modules/proxmox-rke2-cluster/` | Extract into module |
| `lab-01/ansible/site.yml` | `ansible/playbooks/rke2-deploy.yml` | Reuse as RKE2 playbook |
| `lab-01/ansible/group_vars/k3s_cluster.yml` | `ansible/inventory/group_vars/rke2_cluster.yml` | Migrate to RKE2 config |
| `lab-hetzner/terraform/*.tf` | `terraform/layers/06-hetzner/` | Reuse with refinement |
| `lab-hetzner/files/` | `terraform/layers/06-hetzner/files/` | Reuse templates |
| `lab-hetzner/ansible/` | `ansible/playbooks/harden.yml` | Reuse hardening playbooks |
| `ci-templates/*.yml` | `ci-templates/` | Direct reuse |

---

## 2. Terraform Architecture

### Shared Modules

**`modules/proxmox-lxc/`** — Standardized unprivileged LXC container:
- Inputs: `name`, `vm_id`, `proxmox_node`, `cpu`, `memory`, `disk`, `vlan_tag`, `template`, `ssh_keys`, `features`, `startup_order`
- Always: unprivileged=true, nesting=true (Docker), keyctl=false, fuse=false
- Generates ED25519 SSH key per container
- Outputs: `container_id`, `ipv4_address`, `ssh_private_key`, `ssh_public_key`
- Source pattern: `lab-01/mealie/main.tf` (lines 14-109)

**`modules/proxmox-vm/`** — Cloud-init Ubuntu VM:
- Inputs: `name`, `vm_id`, `proxmox_node`, `cpu`, `memory`, `disks[]`, `vlan_tag`, `cloud_init_template`, `ssh_keys`, `startup_order`
- Always: QEMU agent enabled, scsi controller, cloud-init drive
- Generates ED25519 SSH key per VM
- Outputs: `vm_id`, `ipv4_address`, `ssh_private_key`, `ssh_public_key`
- Source pattern: `lab-01/vault/main.tf` (lines 31-80)

**`modules/proxmox-rke2-cluster/`** — RKE2 cluster provisioning (the only DISA STIG-certified Kubernetes distribution):
- Inputs: `master_count`, `worker_count`, `cpu`, `memory`, `proxmox_node`, `vlan_tag`, `rke2_version`
- Uses `proxmox-vm` module internally for each node
- Outputs: `master_ips`, `worker_ips`, `kubeconfig`
- Source pattern: `lab-01/prox-k3s/main.tf`

**`modules/hetzner-server/`** — Hetzner VPS:
- Inputs: `server_type`, `location`, `image`, `cloud_init`, `firewall_rules[]`, `ssh_keys`
- Outputs: `server_ip`, `server_id`
- Source: `lab-hetzner/terraform/hcloud-server.tf`

**`modules/cloudflare-dns/`** — DNS records:
- Inputs: `zone_id`, `records[]` (name, type, value, proxied)
- Source: `lab-hetzner/terraform/cloudflare.tf`

**`modules/vault-cluster/`** — Vault node provisioning:
- Inputs: `node_name`, `node_type` (proxmox-vm | bare-metal | rpi), `vault_version`, `raft_peers[]`, `vlan_tag`
- Handles cross-platform (macOS Linux VM, Proxmox VM, RPi bare-metal)
- Outputs: `node_ip`, `api_addr`, `cluster_addr`

### Layer Architecture

Each layer has its own Terraform state, applied in order:

| Layer | Purpose | State | Targets |
|---|---|---|---|
| `00-network` | UniFi VLANs, firewall zones, port profiles, DHCP | Local (Git) | gw-01 |
| `01-proxmox-base` | Proxmox host networking, storage pools, Packer templates | Local (Git) | All Proxmox nodes |
| `02-vault-infra` | Vault VM provisioning (vault-2 on lab-02) | Local (Git) | Proxmox |
| `02-vault-config` | Vault KV, PKI, policies, AppRole, secrets | Local (Git) | Vault |
| `03-core-infra` | GitLab VM + Runner LXC | Local → S3 | lab-02 |
| `03-gitlab-config` | GitLab groups, projects, CI/CD vars, deploy tokens | Local → S3 | GitLab |
| `04-rke2-cluster` | RKE2 masters + workers | Local → S3 | lab-01 |
| `05-standalone-services` | Ghost, FoundryVTT, Roundcube, Mealie, WireGuard, NetBox | Local → S3 | lab-03, lab-04 |
| `06-hetzner` | Hetzner server + all cloud services | Local → S3 | Hetzner Cloud |

### State Management Strategy

**Phase 1 (Bootstrap — CURRENT):** All state local. `.gitignore` keeps plaintext state/tfvars out of Git.
- Optionally encrypt with SOPS/age and commit as `*.sops.*` files for Git-based backup
- `.sops.yaml` defines encryption rules for `*.tfvars`, `*.tfstate`, `vault.yml`, and `*.env`
- age key generated once, stored securely (printed QR, password manager, NOT in repo)
- Simple, reliable, zero external dependencies
- **CI impact:** Plan jobs run against empty state (no tfstate in CI). Configured with `allow_failure: true` so visualize/publish stages proceed. Applies are manual-gated and not used until Phase 2.

**Phase 2 (Post-Vault, Post-Hetzner):** Migrate layers 03-06 to Hetzner Object Storage:
```hcl
backend "s3" {
  bucket                      = "firblab-tfstate"
  key                         = "layers/03-core-infra/terraform.tfstate"
  endpoints                   = { s3 = "https://region1.your-objectstorage.com" }
  region                      = "nbg1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  use_path_style              = true
}
```
- Layers 00-02 stay local+Git (foundational layers should not depend on remote state they create)
- GitLab CI serialization prevents concurrent applies (no DynamoDB locking needed)
- **Fallback:** Revert to local+Git by switching backend config

### Eliminating null_resource Provisioners

Current fragile pattern: `null_resource` → `sleep 60` → `remote-exec` → `PermitRootLogin yes`

New pattern:
1. **Terraform** creates infrastructure only (VMs, LXCs, networks, DNS)
2. **Cloud-init** handles first-boot: packages, users, SSH keys, Docker install
3. **Ansible** runs after Terraform to deploy and configure applications
4. **Zero Terraform provisioners** for app setup

---

## 3. Network Architecture

### Layer 00: UniFi IaC Management

**Provider:** `filipowm/unifi` v1.0.0 (Terraform Registry)
- Actively maintained fork with UniFi OS 6.x-9.x support (UDM/UDM-Pro/UCG compatible)
- Supports: `unifi_network` (VLANs), `unifi_firewall_zone`, `unifi_firewall_zone_policy`, `unifi_firewall_group`, `unifi_port_profile`, `unifi_port_forward`, `unifi_wlan`, `unifi_user` (DHCP reservations), `unifi_static_route`, `unifi_site`
- API key authentication (recommended for controllers v9.0.108+), or username/password
- Must run from wired connection (WiFi reconfiguration will drop connection)

**Managed Resources:**
```hcl
terraform {
  required_providers {
    unifi = {
      source  = "filipowm/unifi"
      version = "~> 1.0.0"
    }
  }
}

provider "unifi" {
  api_url        = var.unifi_api_url   # https://<gw-01-IP>
  allow_insecure = true                # Self-signed cert on gw-01
  api_key        = var.unifi_api_key   # Recommended for controllers v9.0.108+
}

# VLANs, firewall zones, zone policies, port profiles, DHCP ranges
# Uses Zone-Based Firewall (UniFi OS 9.x) — no manual UI changes after bootstrap
```

### VLAN Layout

| VLAN ID | Name | Subnet | Gateway | DHCP Range | Purpose |
|---|---|---|---|---|---|
| 1 | Default/LAN | 10.0.4.0/24 | 10.0.4.1 | .100-.254 | gw-01 default network, workstation |
| 10 | Management | 10.0.10.0/24 | 10.0.10.1 | .100-.200 | Proxmox hosts, gw-01, Mac Mini, RPi, SSH |
| 20 | Services | 10.0.20.0/24 | 10.0.20.1 | .100-.200 | RKE2 cluster, standalone app VMs/LXCs |
| 30 | DMZ | 10.0.30.0/24 | 10.0.30.1 | .100-.200 | WireGuard endpoint, internet-facing services |
| 40 | Storage | 10.0.40.0/24 | 10.0.40.1 | .100-.200 | NFS, Longhorn replication, backup traffic |
| 50 | Security | 10.0.50.0/24 | 10.0.50.1 | .100-.200 | Vault cluster node (vault-2). Isolated sensitive infrastructure. |

### Inter-VLAN Firewall Rules (Managed by Terraform)

| Source | Destination | Allowed | Blocked |
|---|---|---|---|
| Management (10) | All VLANs | Full access | — |
| Services (20) | Storage (40) | NFS (2049), iSCSI (3260) | Everything else |
| Services (20) | Security (50) | Vault API (8200), GitLab (80/443), Wazuh agent (1514/1515) | Everything else |
| Services (20) | DMZ (30) | Blocked | All |
| DMZ (30) | Services (20) | HTTP/HTTPS to specific IPs (reverse proxy backends) | Everything else |
| DMZ (30) | Management (10) | Blocked | All |
| DMZ (30) | Storage (40) | Blocked | All |
| Storage (40) | Any | Blocked (accept only) | All outbound |
| Security (50) | Internet | Updates only (apt, docker) | Everything else |
| Default (1) | Lab VLANs | Blocked | All |

### Proxmox Network Config

All four Proxmox hosts (lab-01 through lab-04) use VLAN-aware bridging:
```
auto vmbr0
iface vmbr0 inet static
    address 10.0.10.X/24        # .2 for lab-02
    gateway 10.0.10.1           # gw-01
    bridge-ports <physical-nic>
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
```

Managed via `ansible/playbooks/proxmox-bootstrap.yml` (SSH to Proxmox host, template the interfaces file, restart networking).

### WireGuard Architecture

```
                    Internet
                       │
                ┌──────┴──────┐
                │  Hetzner VPS │  (Traefik, AdGuard, Gotify, Uptime Kuma)
                │  WireGuard   │
                └──────┬──────┘
                       │ Site-to-site tunnel (10.8.0.0/24)
                       │
              ┌────────┴────────┐
              │  DMZ VLAN (30)  │  WireGuard endpoint LXC
              │  lab-03    │
              └────────┬────────┘
                       │ Routes to Services VLAN
              ┌────────┴────────┐
              │ Services (20)   │  Ghost, FoundryVTT, RKE2, etc.
              └─────────────────┘

Client VPN: WireGuard on Hetzner (20 peers) → routes to homelab via tunnel
Roundcube: Direct to Migadu (no WireGuard needed)
```

### Reverse Proxy Strategy

- **External (Hetzner):** Traefik v3 handles all public-facing domains. Routes to homelab services via WireGuard tunnel
- **Internal (RKE2):** Traefik in RKE2 cluster for cluster service routing, MetalLB L2 IP on Services VLAN
- **DNS:** AdGuard on Hetzner for external; CoreDNS in RKE2 for cluster; optionally AdGuard on Proxmox for internal LAN

---

## 4. Security Architecture

### Vault HA Cluster (3-Node Raft)

**Topology:**

| Node | Machine | OS | Role | Address |
|---|---|---|---|---|
| vault-1 | Mac Mini M4 | macOS (native) | Voter (initial leader) | 10.0.10.10:8200 |
| vault-2 | lab-02 (Proxmox VM, ID 2001) | Rocky Linux 9 AMD64 | Voter | 10.0.50.2:8200 |
| vault-3 | RPi5 CM5 | Ubuntu 24.04 ARM64 (bare metal) | Voter | 10.0.10.13:8200 |

**Quorum:** 2 of 3 nodes required. Tolerates 1 node failure.

**Mac Mini Setup:**
- Vault runs natively on macOS (launchd service)
- Mac Mini on Management VLAN (10) at 10.0.10.10
- FileVault full-disk encryption enabled (encrypts Vault data at rest)
- macOS pf firewall restricts access to Vault ports only

**Vault Configuration (all nodes):**
```hcl
ui            = true
disable_mlock = true   # Recommended for Raft storage

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-1"
  retry_join { leader_api_addr = "https://10.0.10.10:8200" }
  retry_join { leader_api_addr = "https://10.0.50.2:8200" }
  retry_join { leader_api_addr = "https://10.0.10.13:8200" }
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/etc/vault.d/tls/vault-cert.pem"
  tls_key_file  = "/etc/vault.d/tls/vault-key.pem"
}

# Transit auto-unseal (pointing to unseal vault on same Mac Mini)
seal "transit" {
  address    = "https://127.0.0.1:8210"
  token      = "<unseal-vault-token>"
  key_name   = "autounseal"
  mount_path = "transit/"
}
```

**Auto-Unseal Strategy:**
- Lightweight "unseal vault" runs as a separate process on the Mac Mini (port 8210)
- Uses Shamir 1/1 key (one key, one unseal command after reboot)
- After power outage: manually unseal the one small unseal vault → production cluster auto-unseals
- Unseal key stored in: (1) password manager, (2) printed QR in physical safe, (3) encrypted on RPi

**Vault 3-2-1 Backup:**

| Copy | Location | Medium | Method | Frequency |
|---|---|---|---|---|
| **Primary** | Mac Mini (Vault leader) | SSD (VM disk) | Raft integrated storage | Live |
| **Local backup** | RPi5 or lab-02 | SD/SSD | `vault operator raft snapshot save` → SCP | Every 6 hours |
| **Off-site backup** | Hetzner Object Storage | S3 cloud | Encrypted snapshot upload via cron | Daily |

Backup script (`scripts/vault-backup.sh`):
1. `vault operator raft snapshot save /tmp/vault-snapshot-$(date +%Y%m%d%H%M).snap`
2. Encrypt with age: `age -r <public-key> -o snapshot.snap.age snapshot.snap`
3. Upload to Hetzner S3: `aws s3 cp --endpoint-url https://region1.your-objectstorage.com snapshot.snap.age s3://example-lab-vault-backups/`
4. SCP to RPi5: `scp snapshot.snap.age vault-backup@10.0.10.13:/backups/vault/`
5. Clean up snapshots older than 30 days locally, 90 days on S3
6. Runs as cron job on vault-1 (or Ansible-deployed systemd timer)

**Restore procedure documented in `docs/VAULT-OPERATIONS.md`.**

### Terraform Integration with Vault

```hcl
provider "vault" {
  address = "https://10.0.10.10:8200"
  # Bootstrap: use token from env var VAULT_TOKEN
  # Post-bootstrap: use AppRole auth
}

data "vault_generic_secret" "proxmox_node" {
  path = "secret/infra/proxmox/${var.proxmox_node}"
}

provider "proxmox" {
  endpoint  = data.vault_generic_secret.proxmox_node.data["url"]
  api_token = "${data.vault_generic_secret.proxmox_node.data["token_id"]}=${data.vault_generic_secret.proxmox_node.data["token_secret"]}"
}
```

### Secrets Hierarchy in Vault

For the authoritative, up-to-date secrets hierarchy, see [SECURITY.md](SECURITY.md) Section 2.1. Summary of top-level paths:

```
secret/
├── infra/          # Infrastructure: proxmox/{01-04}, unifi, hetzner, cloudflare
├── compute/        # Per-host: SSH keys, admin passwords
├── services/       # Apps: gitlab, ghost, foundryvtt, mealie, sonarqube, netbox, scanopy, nut, wireguard
├── k8s/            # Kubernetes: grafana, longhorn, longhorn-s3, headlamp (synced by ESO)
└── backup/         # DR: age-key, vault (backup token)

pki/                # Root CA + intermediate CA
transit/            # Auto-unseal key (on unseal Vault instance, port 8210)
```

### Hardening Baseline (All Hosts)

Applied via `ansible/playbooks/harden.yml`:
1. **DevSec OS Hardening** (reuse from lab-hetzner)
2. **DevSec SSH Hardening** (reuse from lab-hetzner)
3. **CIS Ubuntu 24.04 Level 1** (reuse from lab-hetzner)
4. **fail2ban** on all hosts
5. **Wazuh agent** on all hosts (SIEM/EDR enrollment)
6. **CrowdSec agent** on internet-facing hosts (Hetzner, DMZ)
7. **Automatic security updates** (unattended-upgrades)
8. **auditd** with CIS audit rules
9. **AIDE** file integrity monitoring

**macOS-specific hardening** (`ansible/playbooks/harden-macos.yml`):
- FileVault full-disk encryption enabled
- macOS firewall (pf) configured for Vault ports only
- Automatic updates enabled
- Remote login (SSH) restricted to admin user
- Screen lock after idle

### Certificate Management

| Scope | Method | Tool |
|---|---|---|
| Public-facing (Hetzner) | ACME / Let's Encrypt | Traefik auto-provisioning |
| Public-facing (homelab via Hetzner) | ACME / Let's Encrypt | Traefik on Hetzner |
| Internal RKE2 ingress | Vault PKI intermediate CA | cert-manager with Vault issuer |
| Service-to-service (internal) | Vault PKI (short-lived, 24h TTL) | Vault Agent / CSI driver |
| Vault cluster TLS | Vault PKI or manually generated (bootstrap) | Ansible |
| Proxmox API | Vault PKI intermediate CA | Ansible |

---

## 5. Service Deployment Strategy

### Service Placement Matrix

| Service | Runtime | Machine | VLAN | Why |
|---|---|---|---|---|
| **Vault (primary)** | Native macOS | Mac Mini M4 | 10 (Mgmt) | Always-on, power-efficient, physically isolated |
| **Vault (standby)** | Proxmox VM | lab-02 | 50 (Security) | Raft HA voter, separate from main compute |
| **Vault (standby)** | Bare metal | RPi5 CM5 | 10 (Mgmt) | Raft HA voter, separate failure domain |
| **Unseal Vault** | Native macOS | Mac Mini M4 | 10 (Mgmt) | Transit seal provider, lightweight |
| **GitLab CE** | Proxmox VM | lab-02 | 10 (Mgmt) | Resource-intensive (~8GB RAM), source of truth |
| **GitLab Runner** | Proxmox LXC | lab-02 | 10 (Mgmt) | Runs CI jobs, Docker nesting |
| **Ghost** | Proxmox LXC | lab-03 | 20 (Services) | Blog, Docker-in-LXC, exposed via Hetzner Traefik |
| **FoundryVTT** | Proxmox VM | lab-03 | 20 (Services) | WebSocket/WebRTC needs VM, persistent world data |
| **Roundcube** | Proxmox LXC | lab-03 | 20 (Services) | Webmail client (Migadu IMAP/SMTP) |
| **Mealie** | Proxmox LXC | lab-03 | 20 (Services) | Recipe manager |
| **WireGuard** | Proxmox LXC | lab-03 | 30 (DMZ) | Site-to-site tunnel to Hetzner |
| **NetBox** | Proxmox VM | lab-04 | 20 (Services) | DCIM/IPAM infrastructure inventory |
| **Scanopy** | Docker Compose | lab-08 | 1 (Default) | Network scanner (multi-VLAN via 802.1Q) |
| **NUT** | Native packages | lab-08 | 1 (Default) | UPS monitoring + coordinated shutdown |
| **Mealie** | RKE2 pod | lab-01 | 20 (Services) | Stateless-ish, auto-healing, easy updates |
| **SonarQube** | RKE2 pod | lab-01 | 20 (Services) | Helm chart available, k8s resource mgmt |
| **Hetzner stack** | Docker Compose | Hetzner VPS | Cloud | Traefik, WireGuard, AdGuard, Gotify, Uptime Kuma, CrowdSec |

### RKE2 Cluster Sizing (on lab-01)

- **3 server nodes**: 2 CPU, 4GB RAM each — Services VLAN (20)
- **3 agent nodes**: 4 CPU, 8GB RAM each — Services VLAN (20)
- **CNI:** Canal (RKE2 default, Calico + Flannel)
- **Storage:** Longhorn (PVs with snapshots)
- **Ingress:** Traefik (custom Helm install)
- **LoadBalancer:** MetalLB L2 (range: 10.0.20.220-250)

### RKE2 Platform Services (via ArgoCD)

1. **ArgoCD** — GitOps controller, watches `k8s/` in GitLab
2. **cert-manager** — TLS via Vault PKI issuer
3. **MetalLB** — LoadBalancer IPs
4. **Longhorn** — Persistent storage with snapshots
5. **External Secrets Operator** — Syncs Vault → k8s Secrets
6. **Prometheus + Grafana** — Metrics and dashboards
7. **Loki** — Log aggregation
8. **OPA/Gatekeeper** — Policy enforcement
9. **Trivy Operator** — Vulnerability scanning

---

## 6. GitOps Pipeline

### Bootstrap Sequence (Detailed)

The bootstrap must be done manually since GitLab doesn't exist yet. The order is designed so each step only depends on previous steps.

```
PHASE 0: PREREQUISITES (manual)
  0.1  Install Proxmox on lab-02 (manual ISO install)
  0.2  Ensure lab-02 is accessible on local network with root user
  0.3  Install Vault on Mac Mini M4 (native macOS, launchd service)
  0.4  Install Ubuntu 24.04 on RPi5 CM5 (ARM64)
  0.5  Generate age key for SOPS encryption (store securely)
  0.6  Create API key on gw-01 (Settings > Control Plane > API)

PHASE 1: NETWORK (Layer 00)
  1.1  cd terraform/layers/00-network && terraform init && terraform apply
       → Creates VLANs, firewall zones, firewall policies, port profiles on gw-01
  1.2  Verify: ping between VLANs from management host, verify blocks where expected
  1.3  Migrate hosts to VLAN 10:
       → Assign "Management Access" port profile to switch ports (UniFi UI)
       → ./scripts/migrate-macmini-vlan.sh 10.0.4.28 10.0.10.10 admin ~/.ssh/id_ed25519_lab-macmini  (Mac Mini M4)
       → ./scripts/migrate-to-vlan.sh <old-ip> 10.0.10.2 root ~/.ssh/id_ed25519_lab-02              (lab-02)
       → ./scripts/migrate-to-vlan.sh <old-ip> 10.0.10.13 admin ~/.ssh/id_ed25519_lab-rpi5           (RPi5)
       → ./scripts/setup-macmini-vault.sh                              (Mac Mini native Vault — install and configure)

PHASE 2: VAULT CLUSTER (Layers 01 + 02 — THE PILOT)
  2.1  ansible-playbook ansible/playbooks/proxmox-bootstrap.yml -l lab-02
       → Bootstrap Proxmox pilot node (needed for vault-2 VM)
  2.2  cd terraform/layers/01-proxmox-base && terraform apply -var-file=environments/lab-02.tfvars
       → Configures storage pools, downloads cloud images, creates Packer templates
  2.3  ansible-playbook ansible/playbooks/harden.yml -l macmini,rpi
       → Harden Mac Mini VM and RPi5
  2.4  cd terraform/layers/02-vault && terraform apply
       → Creates Vault VM on lab-02 (Proxmox node)
       → Configures Mac Mini VM and RPi5 for Vault
  2.5  ansible-playbook ansible/playbooks/vault-deploy.yml
       → Installs Vault on all 3 nodes
       → Deploys unseal vault on Mac Mini
       → Initializes cluster, unseals, configures auto-unseal
  2.6  Seed Vault with initial secrets:
       vault kv put secret/infra/proxmox/lab-02 url=... token_id=... token_secret=...
       vault kv put secret/infra/hetzner/api token=...
       vault kv put secret/infra/cloudflare/api token=... zone_id=...
       vault kv put secret/infra/unifi/udm-pro username=... password=... url=...
  2.7  Enable PKI secrets engine, create root CA + intermediate CA
  2.8  Enable audit logging
  2.9  Setup backup cron (vault-backup.sh)
  2.10 Verify: vault status (all 3 nodes), vault kv get secret/infra/proxmox/lab-02

  *** AT THIS POINT: Vault is live and serving secrets. ***
  *** lab-02 is proven. You can now rebuild lab-01. ***

PHASE 3: REBUILD lab-01
  3.1  Migrate any critical data from lab-01 (Ghost posts, service data, etc.)
  3.2  Wipe and reinstall Proxmox on lab-01
  3.3  ansible-playbook ansible/playbooks/proxmox-bootstrap.yml -l lab-01
  3.4  terraform apply for Layer 01 with lab-01.tfvars
  3.5  Verify: lab-01 Proxmox API accessible, storage pools configured

PHASE 4: CORE INFRA (Layer 03, on lab-02)
  4.1  cd terraform/layers/03-core-infra && terraform apply
       → Creates GitLab VM, GitLab Runner LXC
  4.2  ansible-playbook ansible/playbooks/harden.yml -l core_infra
  4.3  ansible-playbook ansible/playbooks/gitlab-deploy.yml
  4.4  cd terraform/layers/03-gitlab-config && terraform apply
  4.5  Push repo to GitLab, configure CI/CD variables (VAULT_ADDR, VAULT_TOKEN)
  4.6  Verify: GitLab web UI, Runner registered, CI pipeline runs

  *** FROM HERE: GitLab CI/CD manages all subsequent layers ***

PHASE 5: RKE2 CLUSTER (Layer 04, via GitLab CI/CD)
  5.1  Merge Layer 04 terraform → GitLab pipeline runs plan/apply
  5.2  ansible-playbook ansible/playbooks/rke2-deploy.yml (triggered by pipeline)
  5.3  Install ArgoCD, cert-manager, MetalLB, Longhorn, monitoring, ESO, Gatekeeper, Trivy Operator
  5.4  Deploy Mealie to RKE2 via ArgoCD
  5.5  Deploy SonarQube to RKE2 via ArgoCD
  5.6  Verify: kubectl get nodes, ArgoCD UI, Mealie accessible

PHASE 6: STANDALONE SERVICES (Layer 05, via GitLab CI/CD)
  6.1  Deploy Ghost LXC (lab-03)
  6.2  Deploy FoundryVTT VM (lab-03)
  6.3  Deploy Roundcube LXC (lab-03)
  6.4  Deploy Mealie LXC (lab-03)
  6.5  Deploy WireGuard LXC (lab-03)
  6.6  Deploy NetBox VM (lab-04)
  6.7  Deploy Scanopy + NUT server (lab-08)
  6.8  Verify: each service web UI accessible

PHASE 7: HETZNER (Layer 06, via GitLab CI/CD)
  7.1  Deploy/update Hetzner server
  7.2  Configure WireGuard site-to-site tunnel to DMZ VLAN
  7.3  Configure Traefik routing to homelab services via tunnel
  7.4  Configure Cloudflare DNS records
  7.5  Verify: public domains resolve, HTTPS, AdGuard filtering, Gotify notifications

PHASE 8: VALIDATION & HARDENING
  8.1  Full tfsec scan: 0 critical/high findings
  8.2  Full trivy scan: 0 critical findings
  8.3  CIS benchmark report: Level 1 pass on all hosts
  8.4  (When deployed) Wazuh: all agents reporting, no critical alerts
  8.5  Port scan from each VLAN: only expected ports open
  8.6  SSH key-only auth verified on all hosts
  8.7  Vault audit log review
  8.8  Backup restore test (Vault snapshot → fresh node)
```

### GitLab CI/CD Pipeline

```yaml
# .gitlab-ci.yml
stages:
  - validate
  - scan
  - plan
  - apply
  - configure

include:
  - local: ci-templates/terraform-ci.yml
  - local: ci-templates/ansible-ci.yml
  - local: ci-templates/kubernetes-ci.yml

# Per-layer jobs triggered by path changes
# Example for Layer 04:
terraform:04-rke2:plan:
  extends: .terraform-plan
  variables:
    TF_ROOT: terraform/layers/04-rke2-cluster
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes:
        - terraform/layers/04-rke2-cluster/**/*
        - terraform/modules/**/*

terraform:04-rke2:apply:
  extends: .terraform-apply
  variables:
    TF_ROOT: terraform/layers/04-rke2-cluster
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      changes:
        - terraform/layers/04-rke2-cluster/**/*
        - terraform/modules/**/*
      when: manual  # Manual gate for safety
```

### ArgoCD for RKE2

- Watches `k8s/workloads/` and `k8s/platform/` directories in GitLab
- App-of-apps pattern: single root Application manages all sub-apps
- Auto-sync with self-heal enabled
- Secrets via External Secrets Operator → Vault
- Notifications via Gotify webhook

---

## 7. Monitoring & Observability

### Stack

| Component | Location | Purpose |
|---|---|---|
| **Prometheus** | RKE2 cluster | Metrics from all services + node exporters |
| **Grafana** | RKE2 cluster | Dashboards (pre-built: node, k8s, Docker, Vault) |
| **Loki** | RKE2 cluster | Log aggregation from all hosts |
| **Alertmanager** | RKE2 cluster | Alert routing and deduplication |
| **Uptime Kuma** | Hetzner | Synthetic monitoring, public endpoint checks |
| **Gotify** | Hetzner | Push notifications (alert destination) |
| **Wazuh Manager** | *(Not deployed — RAM constraint)* | SIEM, EDR, file integrity, log analysis |
| **Wazuh Agents** | *(Disabled globally)* | Endpoint telemetry → Wazuh Manager |
| **CrowdSec** | Hetzner + DMZ | Collaborative threat intelligence |
| **node_exporter** | All hosts | System metrics → Prometheus |

### Alert Flow

```
Service metric    → Prometheus → Alertmanager → Gotify push notification
Security event    → Wazuh Agent → Wazuh Manager → Email + Gotify alert
Uptime check fail → Uptime Kuma → Gotify push notification
Container update  → Watchtower (Hetzner) → Gotify notification
ArgoCD sync fail  → ArgoCD notification → Gotify webhook
Vault seal event  → Vault telemetry → Prometheus → Alertmanager → Gotify (CRITICAL)
```

---

## 8. Backup Strategy

> **Status:** Fully deployed as of 2026-02-15. See [DISASTER-RECOVERY.md](DISASTER-RECOVERY.md) for restore procedures.

### Full Backup Matrix

| Target | Method | Frequency | RPO | Off-site |
|---|---|---|---|---|
| **Vault Raft** | `vault operator raft snapshot save` + age encrypt | Every 6 hours | 6h | Hetzner S3 + RPi5 |
| **GitLab (repos + DB)** | `gitlab-backup create` + age + S3 upload | Daily | 24h | Hetzner S3 |
| **Longhorn PVCs** | RecurringJob snapshots + S3 backup | 6h snap, daily S3 | 6h | Hetzner S3 |
| **Docker volumes (lab-08)** | tar + age + S3 upload | Daily | 24h | Hetzner S3 |
| **Proxmox VMs/LXCs** | vzdump (daily local) + weekly S3 (age-encrypted) | Daily + weekly S3 | 24h | Hetzner S3 |
| **Terraform state** | CI pipeline uploads per-apply to S3 | Per-apply | 0 | Hetzner S3 |
| **UniFi config** | gw-01 auto-backup + Terraform state | Weekly + on change | — | gw-01 + Git |

### S3 Backup Buckets (Hetzner Object Storage)

| Bucket | Purpose | Managed By |
|---|---|---|
| example-lab-vault-backups | Vault Raft snapshots | vault-backup-setup.yml (LaunchDaemon) |
| example-lab-gitlab-backups | GitLab backups + secrets.json | gitlab role (cron) |
| example-lab-longhorn-backups | Longhorn PVC backups | Longhorn RecurringJob (ArgoCD) |
| example-lab-service-backups | Docker volume backups | backup role (cron) |
| example-lab-proxmox-backups | vzdump snapshots | proxmox-backup-setup.yml (cron) |
| example-lab-tfstate-backups | Terraform state files | CI pipeline (per-apply) |

---

## 9. Verification Plan

### Per-Layer Verification

- **Layer 00 (Network):** `terraform plan` shows no drift; ping test between VLANs; firewall rules block cross-VLAN where expected; port scan confirms DHCP ranges correct
- **Layer 01 (Proxmox):** Proxmox API accessible via token; storage pools listed in UI; Packer templates available
- **Layer 02 (Vault):** `vault status` on all 3 nodes shows healthy; `vault kv get` returns test secret; auto-unseal test (restart vault-2, verify it auto-unseals); backup snapshot created and downloadable
- **Layer 03 (Core Infra):** GitLab web UI login; CI pipeline runs `terraform validate`; Runner appears in GitLab Admin; GitLab config layer creates projects and CI/CD vars
- **Layer 04 (RKE2):** `kubectl get nodes` all Ready; ArgoCD UI shows apps synced; Mealie and SonarQube accessible; Longhorn dashboard shows healthy volumes
- **Layer 05 (Services):** Ghost publishes test post; FoundryVTT loads a world; Mealie accessible; NetBox UI loads; Roundcube sends test email
- **Layer 06 (Hetzner):** Public domains resolve; HTTPS valid cert; WireGuard tunnel passes traffic; AdGuard blocking ads; Gotify notifications; Uptime Kuma checks passing

### Security Verification Checklist

- [ ] `tfsec` scan: 0 critical/high findings across all layers
- [ ] `trivy config` scan: 0 critical findings
- [ ] `ansible-lint` passes on all playbooks
- [ ] CIS Ubuntu 24.04 Level 1 benchmark: pass on all hosts
- [ ] Wazuh: all agents reporting, no critical alerts, file integrity baseline set
- [ ] Vault: audit log enabled, all policies least-privilege, root token revoked
- [ ] SSH: key-only auth verified on all hosts (`ssh -o PasswordAuthentication=no`)
- [ ] VLAN isolation: port scan from each VLAN confirms only expected ports open
- [ ] TLS: no plaintext HTTP on any internal service
- [ ] Secrets: no plaintext secrets in Git (`git log -p | grep -i password` returns nothing)
- [ ] Backup: Vault restore test on fresh node succeeds
- [ ] UniFi: no manual config changes exist outside Terraform state

---

## 10. Files to Create First (Implementation Order)

1. Initialize repo at `~/repos/firblab/` with `.gitignore`, `.sops.yaml`, `.pre-commit-config.yaml`, `.editorconfig`
   - Copy this plan to `docs/ARCHITECTURE.md` as the living architecture document
2. `terraform/modules/proxmox-lxc/` (main.tf, variables.tf, outputs.tf) — from `lab-01/mealie/main.tf`
3. `terraform/modules/proxmox-vm/` (main.tf, variables.tf, outputs.tf) — from `lab-01/vault/main.tf`
4. `terraform/layers/00-network/` (main.tf, variables.tf, providers.tf, outputs.tf) — UniFi provider config
5. `terraform/layers/01-proxmox-base/` — Proxmox storage/template config
6. `terraform/layers/02-vault/` — Vault HA cluster across 3 machines
7. `ansible/playbooks/proxmox-bootstrap.yml` — Bootstrap fresh Proxmox node
8. `ansible/playbooks/harden.yml` — from `lab-hetzner/ansible/`
9. `ansible/playbooks/vault-deploy.yml` — Vault cluster setup
10. `ansible/roles/common/` — from `lab-01/ansible/roles/common/`
11. `ansible/roles/docker/` — from `lab-01/ansible/roles/docker/`
12. `ansible/roles/vault/` — from `lab-01/ansible/roles/vault/`
13. `ansible/inventory/hosts.yml` — all machines
14. `scripts/vault-backup.sh` — 3-2-1 backup automation
15. `scripts/setup-macmini-vault.sh` — Native macOS Vault setup guide/script
16. `ci-templates/` — from existing `ci-templates/`
17. `packer/ubuntu-24.04-base.pkr.hcl` — from `lab-01/packer/`
18. `.gitlab-ci.yml` — root pipeline
