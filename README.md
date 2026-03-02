# firblab

Production-grade homelab infrastructure managed entirely through code. Single source of truth for all machines, networks, and services.

Built on Proxmox VE, Hetzner Cloud, and UniFi networking with security-first design principles.

## Hardware

| Machine | Hardware | Role |
|---|---|---|
| **lab-01** | i9-12900K, 64 GB RAM | Main compute — RKE2 cluster (6 VMs), Proxmox node |
| **lab-02** | Intel N100, 16 GB RAM | Pilot node — GitLab, GitLab Runner, vault-2 |
| **lab-03** | Intel N100, 12 GB RAM | Lightweight services — Ghost, Roundcube, Mealie, FoundryVTT, WireGuard |
| **lab-04** | Dell Wyse J5005, 20 GB RAM | Lightweight compute — NetBox |
| **lab-08** | RPi4, 8 GB RAM | Scanopy network scanner + NUT UPS server (bare metal) |
| **vault-1** | Mac Mini M4, 24 GB RAM | Vault primary (native macOS LaunchDaemon), always-on anchor |
| **vault-3** | RPi5 CM5, 16 GB RAM | Vault standby (Ubuntu 24.04 ARM64, bare metal) |
| **TrueNAS** | i5-9500, 16 GB RAM | NFS, Plex, ZFS storage |
| **Hetzner VPS** | cpx22 (Nuremberg) | Public gateway — Traefik, WireGuard, AdGuard, monitoring |
| **gw-01** | Ubiquiti UDM Pro | VLAN routing, firewall, DHCP |

## Architecture

- **Network:** 6 VLANs managed via Terraform (Default, Management, Services, DMZ, Storage, Security)
- **Compute:** Proxmox VE cluster (4 nodes) running RKE2 Kubernetes + standalone VMs/LXCs
- **Secrets:** HashiCorp Vault 3-node HA Raft cluster (Mac Mini + Proxmox VM + RPi5)
- **Cloud:** Hetzner VPS for public-facing services with WireGuard site-to-site tunnel
- **GitOps:** GitLab CI/CD for Terraform + Ansible, ArgoCD for Kubernetes workloads
- **Security:** CIS L1 hardening (Packer baseline + Ansible runtime), Vault PKI, TLS everywhere
- **Monitoring:** Prometheus + Grafana + Loki (RKE2), Uptime Kuma, Gotify notifications
- **Backups:** Automated 3-2-1 strategy — Vault (6h), GitLab (daily), Longhorn PVCs (6h snap + daily S3), Proxmox vzdump (daily + weekly S3), Docker volumes (daily), tfstate (per-apply). All encrypted with age, off-site to Hetzner S3.
- **UPS:** CyberPower on closet rack, NUT server + clients for coordinated shutdown

## Terraform Layers

Infrastructure is deployed in ordered layers, each with independent state:

| Layer | Purpose | Target |
|---|---|---|
| `00-network` | UniFi VLANs, firewall zones, zone policies, port profiles, switch devices | gw-01 |
| `01-proxmox-base` | Storage pools, cloud images, Packer templates | Proxmox hosts |
| `02-vault-infra` | Vault VM provisioning (vault-2 on lab-02) | Proxmox |
| `02-vault-config` | Vault KV, PKI, policies, AppRole, secrets | Vault |
| `03-core-infra` | GitLab CE VM + Runner LXC | lab-02 |
| `03-gitlab-config` | GitLab groups, projects, CI/CD variables, deploy tokens | GitLab |
| `04-rke2-cluster` | RKE2 server + agent VMs (3+3) | lab-01 |
| `05-standalone-services` | Ghost, FoundryVTT, Roundcube, Mealie, WireGuard, NetBox | lab-03, lab-04 |
| `06-hetzner` | Hetzner VPS, Cloudflare DNS, S3 backup buckets | Hetzner Cloud |

## Quick Start

### Prerequisites

- Proxmox VE 8.x on at least one node
- UniFi UDM Pro (gw-01) with API access
- Mac Mini M4 (for Vault primary, native macOS)
- Hetzner Cloud account + Cloudflare account (for DNS)
- Tools: `terraform` >= 1.9, `ansible` >= 2.15, `packer` >= 1.11, `kubectl`, `vault`, `age`

### 1. Clone and Configure

```bash
git clone <repo-url>
cd firblab

# Copy and fill in environment-specific variables
for f in terraform/environments/*.tfvars.example; do
  cp "$f" "${f%.example}"
done
# Edit each .tfvars file with your actual values
```

### 2. Bootstrap (Layers 00-03)

The first 4 layers must be deployed manually since GitLab doesn't exist yet. See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for the full bootstrap sequence.

```bash
# Layer 00: Network (UniFi VLANs + firewall rules)
cd terraform/layers/00-network
terraform init && terraform apply

# Layer 01: Proxmox base (storage, templates)
ansible-playbook ansible/playbooks/proxmox-bootstrap.yml -l lab-02
cd terraform/layers/01-proxmox-base
terraform init && terraform apply

# Layer 02: Vault HA cluster
cd terraform/layers/02-vault-infra && terraform init && terraform apply
ansible-playbook ansible/playbooks/vault-deploy.yml
cd terraform/layers/02-vault-config && terraform init && terraform apply

# Layer 03: Core infrastructure (GitLab + Runner)
cd terraform/layers/03-core-infra && terraform init && terraform apply
ansible-playbook ansible/playbooks/gitlab-deploy.yml
cd terraform/layers/03-gitlab-config && terraform init && terraform apply
# Push repo to GitLab — CI/CD manages layers 04-06 from here
```

### 3. GitOps (Layers 04-06)

After GitLab is running, subsequent layers are deployed via CI/CD pipelines triggered by merge requests.

## Directory Structure

```
ansible.cfg           Ansible config (inventory + role paths, run from repo root)
terraform/
  modules/            Shared reusable modules (proxmox-vm, proxmox-lxc, hetzner-server, etc.)
  layers/             Deployment layers 00-06 (applied in order)
  environments/       Per-machine .tfvars.example files
ansible/
  playbooks/          26 deployment and hardening playbooks
  roles/              23 roles (common, hardening, vault, docker, gitlab, rke2, backup, nut, etc.)
  inventory/          Static inventory + group_vars
k8s/
  argocd/             ArgoCD bootstrap + app-of-apps (18 Applications, 3 sync waves)
  apps/               Application manifests (Mealie, SonarQube, Headlamp)
  platform/           Cluster services (MetalLB, cert-manager, Longhorn, Traefik, monitoring)
  policies/           Gatekeeper constraint templates and constraints
packer/               Hardened Ubuntu 24.04 + Rocky Linux 9 VM templates
ci-templates/         Shared GitLab CI/CD pipeline templates (Terraform, Ansible, D2, Rover)
scripts/              Bootstrap, backup, and utility scripts
docs/                 Architecture, operations, DR, and runbook documentation
```

## Portability

This repo is designed to be publicly hostable. All secrets are managed via Vault or kept out of Git by `.gitignore`. `.tfvars` files use committed `.tfvars.example` templates with placeholder values. Anyone with similar hardware can clone, fill in their values, and deploy.

## Security

- Zero plaintext secrets in repo — all managed via HashiCorp Vault
- CIS Ubuntu 24.04 Level 1 hardening on all hosts (Packer baseline + Ansible runtime)
- VLAN segmentation with zone-based firewall policies (27 policies, 6 zones)
- TLS everywhere: Vault PKI for internal certs, Let's Encrypt for public
- Automated encrypted backups to Hetzner S3 (age encryption, 3-2-1 strategy)
- NUT UPS monitoring with coordinated shutdown on power events
- CrowdSec on internet-facing hosts
- Trivy Operator + OPA/Gatekeeper for Kubernetes security

## Documentation

| Document | Description |
|---|---|
| [CURRENT-STATE.md](docs/CURRENT-STATE.md) | **Authoritative inventory** of all deployed infrastructure |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Architecture design and decisions |
| [NETWORK.md](docs/NETWORK.md) | VLAN layout, firewall rules, WireGuard, reverse proxy |
| [SECURITY.md](docs/SECURITY.md) | Vault cluster, hardening, PKI, secrets management |
| [DISASTER-RECOVERY.md](docs/DISASTER-RECOVERY.md) | DR runbook, restore procedures, RPO/RTO targets |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | Complete bootstrap sequence |
| [VAULT-OPERATIONS.md](docs/VAULT-OPERATIONS.md) | Vault unseal, backup, restore, rotation |
| [MACHINE-ONBOARDING.md](docs/MACHINE-ONBOARDING.md) | How to add a new machine to the lab |

## License

MIT
