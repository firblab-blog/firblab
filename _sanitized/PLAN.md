# FirbLab-OS Phase 1: Codebase Portability & Project Scaffolding

## Goal

Create the `firblab-os` GitLab project as a clean, portable fork of the `firblab` codebase — stripped of all Jordan-specific values (IPs, domains, hostnames, MAC addresses, emails, SSH keys, VM IDs, etc.) and restructured so any user can deploy the same hardened homelab stack on their own hardware by providing their own configuration.

This phase delivers:
1. The new `firblab-os` GitLab repo (mirrored to GitHub)
2. A clear separation of **framework** (reusable IaC) vs **instance config** (user-specific values)
3. Example config files (`.example`) for every environment-specific file
4. An interactive CLI setup wizard that generates those config files from user input
5. Documentation for both approaches (manual templates OR wizard)

---

## Scope: What Is "Core" vs "Optional"

### Core (Always Deployed)
These are mandatory — FirbLab-OS doesn't function without them:

| Component | Layer | Purpose |
|-----------|-------|---------|
| Network (VLAN segmentation) | TF Layer 00 | VLAN segmentation, firewall zones, switch port profiles |
| Proxmox Base | TF Layer 01 | ISOs, cloud images, LXC templates on Proxmox nodes |
| Vault (cluster or standalone) | TF Layer 02 + Ansible | Secret management (Raft HA or single-node) |
| Vault Config | TF Layer 02-config | Secret seeding (KV v2 engine) |
| CIS Hardening | Packer + Ansible | Immutable baseline (Packer) + runtime enforcement (Ansible) |
| Packer Templates | Packer | Hardened Ubuntu 24.04 + Rocky 9 VM templates |
| Reverse Proxy (Traefik) | TF Layer 05 + Ansible | TLS termination, service routing |
| GitLab CE | TF Layer 03 + Ansible | Git server, CI/CD pipelines |
| Proxmox Bootstrap | Ansible | Node hardening, cluster join, iptables |

**Provider-specific notes:**
- **Network:** Phase 1 supports `unifi` (full Terraform automation) and `manual` (user configures their own gear — FirbLab-OS documents required VLANs/subnets/firewall rules). Future: OPNsense, pfSense, MikroTik providers.
- **SSO:** Phase 1 supports `authentik` (full Terraform + Ansible automation) and `none` (no SSO, ForwardAuth disabled). Future: Authelia, TinyAuth.
- **Control node:** The FirbLab-OS control plane (the orchestrator app) runs on ANY device — RPi5, Mac, a VM, a container. It does NOT require Proxmox. Proxmox nodes are *managed targets*, not a requirement for the control node itself.

### Optional (User Chooses)
Enabled/disabled via config. Each is self-contained:

| Component | Layer | Purpose |
|-----------|-------|---------|
| SSO (Authentik) | TF Layer 05 + 07 + Ansible | Identity provider, ForwardAuth for all services |
| RKE2 Kubernetes | TF Layer 04 + Ansible | Container orchestration (ArgoCD, MetalLB, Longhorn, etc.) |
| Hetzner Cloud Gateway | TF Layer 06 | External reverse proxy, WireGuard site-to-site |
| GPU/AI Workloads | TF Layer 05 + Ansible | Ollama, Open WebUI, n8n (ROCm GPU passthrough) |
| Standalone Services | TF Layer 05 + Ansible | Ghost, Mealie, FoundryVTT, Vaultwarden, etc. |
| Archive Appliance | Ansible | Kiwix, ArchiveBox, BookStack, etc. (bare-metal) |
| PBS (Proxmox Backup) | TF Layer 05 + Ansible | Backup server with ZFS passthrough |
| Monitoring Stack | K8s (ArgoCD) | Prometheus, Grafana, Loki |
| NetBox | TF Layer 05 + Ansible | Infrastructure documentation/CMDB |

---

## Architecture: How the Separation Works

```
firblab-os/                          # The product (generic, portable)
├── terraform/
│   ├── layers/                      # All TF layers (generic)
│   ├── modules/                     # All TF modules (generic)
│   └── environments/
│       └── *.tfvars.example         # Example tfvars (no real values)
├── ansible/
│   ├── roles/                       # All roles (generic)
│   ├── playbooks/                   # All playbooks (generic)
│   └── inventory/
│       ├── hosts.yml.example        # Example inventory
│       └── group_vars/
│           ├── all.yml.example      # Example global vars
│           └── *.yml.example        # Example per-group vars
├── packer/                          # Templates (generic)
├── k8s/                             # K8s manifests (generic, domain parameterized)
├── scripts/                         # Helper scripts (generic)
├── setup/                           # NEW: Setup wizard + config generation
│   ├── wizard.py                    # Interactive CLI wizard
│   ├── templates/                   # Jinja2 templates for config generation
│   └── schema/                      # JSON Schema for validation
├── config/                          # NEW: User's instance config (gitignored)
│   ├── site.yml                     # Master config file (user fills in)
│   └── site.yml.example             # Documented example
└── docs/                            # All documentation
```

### The `config/site.yml` — Single Source of Truth for User Config

Instead of editing 15+ tfvars files and 10+ group_vars files, users fill in ONE file:

```yaml
# config/site.yml — Your homelab configuration
# Generated by: setup/wizard.py OR filled in manually from site.yml.example

# =============================================================================
# Identity
# =============================================================================
site_name: "mylab"                     # Used for naming (hostnames, S3 buckets, etc.)
domain_internal: "home.mylab.org"      # Internal DNS domain (Traefik routes)
domain_external: "mylab.org"           # External domain (ACME certs, Cloudflare)
admin_email: "admin@mylab.org"         # ACME, GitLab, Authentik admin
timezone: "America/New_York"

# =============================================================================
# Network
# =============================================================================
network:
  provider: "unifi"                    # unifi | manual
  gateway_ip: "192.168.1.1"           # Router/UDM Pro IP
  # UniFi-specific (only when provider: unifi)
  unifi:
    api_url: "https://192.168.1.1"
    # api_key stored in Vault (secret/infra/unifi)
  vlans:
    management:
      id: 10
      subnet: "10.0.10.0/24"
      gateway: "10.0.10.1"
    services:
      id: 20
      subnet: "10.0.20.0/24"
      gateway: "10.0.20.1"
    dmz:
      id: 30
      subnet: "10.0.30.0/24"
      gateway: "10.0.30.1"
    storage:
      id: 40
      subnet: "10.0.40.0/24"
      gateway: "10.0.40.1"
    security:
      id: 50
      subnet: "10.0.50.0/24"
      gateway: "10.0.50.1"
  dns_servers: ["1.1.1.1", "8.8.8.8"]
  switches: []                         # Populated by wizard or manually

# =============================================================================
# Proxmox Nodes
# =============================================================================
proxmox_nodes:
  - name: "lab-01"
    ip: "10.0.10.10"
    role: "compute"                    # compute | lightweight | storage
    ssh_key: "~/.ssh/id_ed25519_lab-01"
    nic_name: "enp1s0"                 # CRITICAL: must match actual NIC
    storage_pools:
      os: "local-lvm"
      data: "local-lvm"               # Override per-node if HDD available

# =============================================================================
# Vault Cluster
# =============================================================================
vault:
  version: "1.21.3"
  nodes:
    - name: "vault-1"
      ip: "10.0.10.20"
      type: "proxmox_vm"              # proxmox_vm | bare_metal | macos | rpi
      vlan: "management"
    - name: "vault-2"
      ip: "10.0.50.2"
      type: "proxmox_vm"
      vlan: "security"
    - name: "vault-3"
      ip: "10.0.10.21"
      type: "rpi"
      vlan: "management"
  transit_unseal:
    enabled: true
    address: "https://10.0.10.20:8210"
  ca_cert_path: "~/.{{ site_name }}/tls/ca/ca.pem"

# =============================================================================
# SSO Provider
# =============================================================================
sso:
  provider: "authentik"                # authentik | none
  # When "none": ForwardAuth disabled, services use local auth only.
  # When "authentik": Full OIDC/ForwardAuth integration.
  # Future: authelia, tinyauth

# =============================================================================
# Core Services (Always Deployed)
# =============================================================================
core_services:
  gitlab:
    ip: "10.0.10.50"
    vm_id: 3001
    node: "lab-01"
    vlan: "management"
  gitlab_runner:
    ip: "10.0.10.51"
    vm_id: 3002
    node: "lab-01"
    vlan: "management"
    type: "lxc"
  traefik:
    ip: "10.0.10.17"
    vm_id: 5033
    node: "lab-01"
    vlan: "management"
    type: "lxc"

# =============================================================================
# Optional Stacks (enable/disable)
# =============================================================================
stacks:
  authentik:
    enabled: true                      # Deployed when sso.provider == "authentik"
    ip: "10.0.10.16"
    vm_id: 5021
    node: "lab-01"
    vlan: "management"

  kubernetes:
    enabled: false
    rke2_version: "v1.32.11+rke2r3"
    server_count: 3
    agent_count: 3
    server_ip_offset: 40              # .40, .41, .42 on services VLAN
    agent_ip_offset: 50               # .50, .51, .52 on services VLAN
    vm_id_start: 4000
    node: "lab-01"
    vlan: "services"

  hetzner:
    enabled: false
    server_type: "cpx22"
    location: "nbg1"
    # Credentials in Vault (secret/infra/hetzner)

  gpu_ai:
    enabled: false
    node: "lab-01"
    ip: "10.0.20.18"
    vm_id: 5035
    vlan: "services"
    gpu_pci_ids: []                    # e.g., ["03:00.0", "03:00.1"]
    rocm_target: ""                    # e.g., "gfx1101" for RX 7800 XT

# =============================================================================
# Optional Standalone Services
# =============================================================================
services:
  ghost:
    enabled: false
    ip: "10.0.20.10"
    vm_id: 5010
    node: "lab-01"
    type: "lxc"
    vlan: "services"
  mealie:
    enabled: false
    ip: "10.0.20.13"
    vm_id: 5014
    node: "lab-01"
    type: "lxc"
    vlan: "services"
  foundryvtt:
    enabled: false
    ip: "10.0.20.12"
    vm_id: 5011
    node: "lab-01"
    type: "vm"
    vlan: "services"
  vaultwarden:
    enabled: false
    ip: "10.0.20.19"
    vm_id: 5036
    node: "lab-01"
    type: "lxc"
    vlan: "services"
  netbox:
    enabled: false
    ip: "10.0.20.14"
    vm_id: 5030
    node: "lab-01"
    type: "vm"
    vlan: "services"
  patchmon:
    enabled: false
    ip: "10.0.20.15"
    vm_id: 5032
    node: "lab-01"
    type: "vm"
    vlan: "services"
  actualbudget:
    enabled: false
    ip: "10.0.20.16"
    vm_id: 5015
    node: "lab-01"
    type: "lxc"
    vlan: "services"
  roundcube:
    enabled: false
    ip: "10.0.20.11"
    vm_id: 5013
    node: "lab-01"
    type: "lxc"
    vlan: "services"
  pbs:
    enabled: false
    ip: "10.0.10.15"
    vm_id: 5031
    node: "lab-01"
    type: "vm"
    vlan: "management"
  archive:
    enabled: false
    ip: "10.0.20.20"
    type: "bare_metal"
    vlan: "services"
  # ... more services as they're added
```

### How `site.yml` Flows Into IaC

```
config/site.yml
      │
      ▼
setup/wizard.py (or manual editing)
      │
      ├──► terraform/environments/*.tfvars      (generated)
      ├──► ansible/inventory/hosts.yml          (generated)
      ├──► ansible/inventory/group_vars/*.yml   (generated)
      ├──► k8s/ values overrides                (generated)
      └──► scripts/ .env files                  (generated)
```

The wizard reads `site.yml` and renders Jinja2 templates into the actual config files that Terraform/Ansible/K8s consume. Users never need to understand tfvars syntax or Ansible inventory format — they just fill in `site.yml`.

---

## Implementation Steps

### Step 1: Create the GitLab Project
- Create `infrastructure/firblab-os` project in GitLab (via Terraform Layer 03-gitlab-config)
- Configure GitHub mirror push
- Set up initial branch protection rules

### Step 2: Define the `config/site.yml` Schema
- Create `setup/schema/site-schema.json` (JSON Schema for validation)
- Create `config/site.yml.example` with comprehensive documentation
- Every field documented with description, type, default, constraints

### Step 3: Build the Config Generator
- Create `setup/wizard.py` — interactive CLI that:
  1. Walks user through each section of `site.yml`
  2. Validates input against the schema
  3. Offers smart defaults (e.g., auto-calculate VLAN gateways from subnets)
  4. Writes `config/site.yml`
- Create `setup/generate.py` — reads `site.yml` and renders all config files:
  - Jinja2 templates in `setup/templates/` for every generated file
  - Validates rendered output
  - Reports what was generated

### Step 4: Create Jinja2 Templates for All Config Files
Templates that read from `site.yml` and produce:

| Template | Generates | Key Values Injected |
|----------|-----------|---------------------|
| `terraform/environments/network.tfvars.j2` | `network.tfvars` | VLAN IDs, subnets, switch MACs, DNS |
| `terraform/environments/proxmox-base.tfvars.j2` | `proxmox-base.tfvars` | Node names, IPs, storage pools |
| `terraform/environments/vault-infra.tfvars.j2` | `vault-infra.tfvars` | Vault node IPs, VM IDs, VLANs |
| `terraform/environments/vault-config.tfvars.j2` | `vault-config.tfvars` | Proxmox creds, UniFi creds (user provides) |
| `terraform/environments/core-infra.tfvars.j2` | `core-infra.tfvars` | GitLab IP, Runner IP, VM IDs |
| `terraform/environments/rke2.tfvars.j2` | `rke2.tfvars` | Node counts, IP offsets, VM IDs |
| `terraform/environments/standalone.tfvars.j2` | `standalone.tfvars` | Per-service IP, VM ID, node, enabled |
| `terraform/environments/hetzner.tfvars.j2` | `hetzner.tfvars` | Server type, location, WG config |
| `terraform/environments/authentik.tfvars.j2` | `authentik.tfvars` | Authentik IP, domain |
| `ansible/inventory/hosts.yml.j2` | `hosts.yml` | All host IPs, SSH keys, groups, jump host |
| `ansible/inventory/group_vars/all.yml.j2` | `all.yml` | Domain, VLANs, Vault addr, DNS, timezone |
| `ansible/inventory/group_vars/vault_cluster.yml.j2` | `vault_cluster.yml` | Raft peers, transit unseal, version |
| `ansible/inventory/group_vars/core_infra.yml.j2` | `core_infra.yml` | GitLab URLs, Runner URL, OIDC |
| `ansible/inventory/group_vars/rke2_cluster.yml.j2` | `rke2_cluster.yml` | RKE2 version, node IPs, CIDRs |
| `ansible/inventory/group_vars/standalone_services.yml.j2` | `standalone_services.yml` | Service ports, firewall sources |
| `ansible/inventory/group_vars/traefik_proxy.yml.j2` | `traefik_proxy.yml` | Backend map, domain, Authentik URL |
| `k8s/argocd/install.yml.j2` | `install.yml` | GitLab repo URL |
| `k8s/platform/*/values.yaml.j2` | Various | Domain, Vault addr, Authentik OIDC URLs |

### Step 5: Strip the Codebase
- Copy the `firblab` repo into `firblab-os`
- Remove all `.tfvars` files (replace with `.tfvars.example`)
- Remove `ansible/inventory/hosts.yml` (replace with `.example`)
- Remove all `group_vars/*.yml` (replace with `.example`)
- Remove all `.secrets/` directories
- Remove `terraform.tfstate*` files
- Remove any `*.auto.tfvars`
- Add all generated paths to `.gitignore`
- Update all hardcoded defaults in `variables.tf` files to use empty/placeholder defaults
- Update all hardcoded defaults in Ansible `defaults/main.yml` to remove FirbLab-specific values
- Audit and update all scripts to use env vars or config file instead of hardcoded values

### Step 6: Update Terraform Variable Defaults
For every `variables.tf` across all layers, change hardcoded defaults:

```hcl
# BEFORE (firblab repo)
variable "vault_addr" {
  default = "https://10.0.10.10:8200"
}

# AFTER (firblab-os repo)
variable "vault_addr" {
  description = "Vault cluster API address"
  type        = string
  # No default — must be provided via tfvars
}
```

Variables that have genuinely universal defaults (like `storage_pool = "local-lvm"`) keep their defaults. Only environment-specific values are stripped.

### Step 7: Update Ansible Role Defaults
For every `defaults/main.yml` with FirbLab-specific values:

```yaml
# BEFORE (firblab repo)
traefik_domain: "home.example-lab.org"
traefik_authentik_url: "http://10.0.10.16:9000"

# AFTER (firblab-os repo)
traefik_domain: ""          # Set via group_vars (generated from site.yml)
traefik_authentik_url: ""   # Set via group_vars (generated from site.yml)
```

### Step 8: Documentation
- `README.md` — Project overview, quick start, architecture diagram
- `docs/GETTING-STARTED.md` — Step-by-step from zero to deployed
- `docs/ARCHITECTURE.md` — How the layers fit together
- `docs/CONFIGURATION.md` — Complete `site.yml` reference
- `docs/MANUAL-SETUP.md` — For users who want to fill in templates manually
- Update all existing docs to be generic (remove FirbLab-specific references)

### Step 9: Validate
- Run `setup/generate.py` with the example `site.yml` → verify all files render
- Run `terraform validate` on each layer with generated tfvars
- Run `ansible-inventory --list` with generated inventory
- Run `ansible-lint` on all playbooks

---

## What Does NOT Change

The following stay as-is (already generic or universally applicable):

- **Terraform modules** (`proxmox-vm`, `proxmox-lxc`, `proxmox-rke2-cluster`, etc.) — already parameterized via variables
- **Ansible roles** (task logic) — roles consume variables, the tasks themselves are generic
- **Packer template logic** — provisioning scripts are OS-generic (CIS hardening, SSH, UFW, etc.)
- **Packer variable interface** — already accepts VM ID, node, storage, ISO as variables
- **K8s Gatekeeper policies** — security constraints are universal
- **Ansible role structure** (common, hardening, rke2, vault, etc.)
- **Terraform provider configurations** — already support dual-mode (Vault + bootstrap fallback)

---

## Hardcoded Values Audit Summary

From the codebase exploration, these are the categories of values being extracted:

| Category | Count | Examples | Extracted To |
|----------|-------|----------|--------------|
| IP addresses | 50+ | 10.0.10.42, 10.0.20.220 | `site.yml` network + node + service sections |
| Hostnames | 40+ | lab-01, vault-2, gitlab | `site.yml` node + service names |
| Domains | 310+ refs | home.example-lab.org, example-lab.local | `site.yml` domain_internal/external |
| MAC addresses | 4 | 52:54:00:11:22:01 | `site.yml` network.switches |
| VLAN IDs | 5 | 10, 20, 30, 40, 50 | `site.yml` network.vlans |
| VM IDs | 30+ | 9000-9002, 4000-4005, 5010-5036 | `site.yml` per-service vm_id |
| Emails | 5 | admin@example-lab.org | `site.yml` admin_email |
| Vault config | 15+ refs | https://10.0.10.10:8200, secret/infra/* | `site.yml` vault section |
| SSH key paths | 15+ | ~/.ssh/id_ed25519_lab-* | `site.yml` per-node ssh_key |
| Storage pools | 3 | local-lvm, hdd-data-0 | `site.yml` per-node storage_pools |
| S3 buckets | 4 | firblab-vault-backups | Derived from `site.yml` site_name |
| Git repo URLs | 10+ | http://10.0.10.50/infrastructure/firblab.git | Derived from GitLab IP + site_name |

---

## File Delivery Order

To minimize risk and allow incremental validation:

1. **`config/site.yml.example`** + **`setup/schema/site-schema.json`** — Define the contract first
2. **`setup/generate.py`** + **`setup/templates/`** — Build the generator + all Jinja2 templates
3. **`setup/wizard.py`** — Build the interactive CLI
4. **Strip the codebase** — Remove hardcoded values, update defaults
5. **`.gitignore`** updates — Ensure generated files are ignored
6. **Documentation** — Getting started, architecture, config reference
7. **GitLab project creation** — Create repo, push, configure mirror
8. **Validation** — End-to-end test with example config

---

## Success Criteria

Phase 1 is complete when:

- [ ] A new user can `git clone` the firblab-os repo
- [ ] Run `python setup/wizard.py` and answer questions about their hardware
- [ ] The wizard generates a valid `config/site.yml`
- [ ] Run `python setup/generate.py` and get all tfvars, inventory, and group_vars files
- [ ] OR manually copy `.example` files and fill in values
- [ ] `terraform validate` passes on all enabled layers
- [ ] `ansible-inventory --list` shows correct host groups
- [ ] No FirbLab-specific IPs, domains, hostnames, or emails remain in the codebase
- [ ] The original `firblab` repo continues to work unchanged
