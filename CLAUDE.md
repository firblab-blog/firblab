# FirbLab — Project Instructions for Claude Code

## Project Overview

FirbLab is a homelab infrastructure platform running on Proxmox, managed entirely through IaC (Terraform, Packer, Ansible) with secrets in HashiCorp Vault. The goal is a production-grade, CIS-hardened, self-healing environment.

## Architecture

### Network

Network configuration is managed by Terraform Layer 00 (`terraform/layers/00-network/`) with Ansible filling provider gaps. **No manual changes** through the UniFi UI. See `docs/NETWORK.md` for the full topology and the Terraform/Ansible boundary.

- **VLAN 1 (10.0.4.0/24):** Default/LAN — Mac workstation (admin box), gw-01
- **VLAN 10 (10.0.10.0/24):** Management — Proxmox nodes, Vault cluster, GitLab
- **VLAN 20 (10.0.20.0/24):** Services — RKE2 cluster, standalone service VMs/LXCs, MetalLB pool (.220-.250)
- **VLAN 30 (10.0.30.0/24):** DMZ — Internet-facing services, WireGuard
- **VLAN 40 (10.0.40.0/24):** Storage — TrueNAS (10.0.40.2), NFS, iSCSI
- **VLAN 50 (10.0.50.0/24):** Security — vault-2 (10.0.50.2)\n- **VLAN 60 (10.0.60.0/24):** IoT — Home Assistant (10.0.60.10)
- **Inter-VLAN routing** is handled by gw-01 (UDM Pro) with zone-based firewall policies (managed by Terraform Layer 00)

### Network IaC Rules

These rules are mandatory for ALL network changes. Derived from the Layer 00 cutover directive.

1. **All switch port profiles are managed via Terraform.** No UI configuration. Port overrides in `devices.tf`, profiles in `main.tf`.
2. **VLAN enforcement is explicit and deterministic.** Every physical device gets a port profile. No reliance on Default LAN permissiveness.
3. **Incremental cutover only.** Never mass VLAN migration. Change one port at a time, verify, then proceed.
4. **Documentation and Terraform state must remain aligned.** When you change `devices.tf`, update `docs/NETWORK.md` port tables in the same commit.
5. **No workaround mechanisms — except documented provider gaps.** No `null_resource`, no `local-exec`, no SSH hacks, no Ansible for network configuration that the Terraform provider CAN handle. For settings the provider CANNOT manage (documented in `ansible/roles/unifi-config/defaults/main.yml`), use `terraform_data` + Ansible via the `unifi-config` role. Track provider gap status — migrate back to Terraform when/if the provider adds support.
6. **Operate conservatively.** Prioritize correctness over speed. A bad port profile change can brick a node's network — requiring physical console recovery.

### Hosts

**Proxmox Cluster (Management VLAN 10):**
- **lab-01 (10.0.10.42):** Main compute (i9-12900K, 64GB RAM — RKE2 cluster 5 VMs + GitLab VM + Authentik VM + Backup LXC)
- **lab-02 (10.0.10.2):** Pilot node (Intel N100, 16GB RAM — vault-2, GitLab Runner)
- **lab-03 (10.0.10.3):** Lightweight services (Intel N100, 12GB RAM — Ghost, Roundcube, Mealie, FoundryVTT, WireGuard)
- **lab-04 (10.0.10.4):** Lightweight compute (Dell Wyse, J5005, 20GB RAM — PBS, NetBox, PatchMon, Traefik Proxy)

**Vault Cluster (Raft, 3 nodes):**
- **vault-1 (10.0.10.10):** Mac Mini M4 — primary (macOS native)
- **vault-2 (10.0.50.2):** VM on lab-02 — Security VLAN 50
- **vault-3 (10.0.10.13):** RPi5 CM5 — Management VLAN 10

**RKE2 Kubernetes Cluster (Services VLAN 20):**
- 3 server nodes (2C/4G, 10.0.20.40-42) + 2 agent nodes (4C/10G, 10.0.20.50-51), all on lab-01
- ArgoCD manages platform services via GitOps (app-of-apps pattern)
- K8s workloads: Mealie, GitLab CE (testing), Wazuh SIEM, Headlamp, Trivy

### Terraform Layers

```
terraform/layers/
  00-network/          # UniFi VLANs, firewall zones, zone policies, port profiles, switch devices
  01-proxmox-base/     # Proxmox provider setup, ISOs, cloud images, LXC templates
  02-vault-infra/      # Vault server infrastructure (VM provisioning)
  02-vault-config/     # Vault secrets, policies, mounts, auth backends (KV v2)
  03-core-infra/       # Core VMs (GitLab, Runner)
  03-gitlab-config/    # GitLab groups, projects, labels, deploy tokens, CI/CD vars
  04-rke2-cluster/     # RKE2 Kubernetes cluster (server + agent nodes)
  05-standalone-services/ # Standalone service VMs/LXCs
  06-hetzner/          # Hetzner cloud servers (gateway + honeypot)
```

### Packer Templates

```
packer/
  ubuntu-24.04/        # Hardened Ubuntu 24.04 LTS base template
  rocky-9/             # Hardened Rocky Linux 9 base template
  http/                # Shared autoinstall/kickstart configs
```

### Ansible

```
ansible/
  playbooks/           # Deployment playbooks (proxmox-bootstrap, rke2-deploy, argocd-bootstrap, etc.)
  inventory/           # hosts.yml + group_vars/ (proxmox_nodes, rke2_cluster, core_infra, etc.)
  roles/               # Reusable roles (common, hardening, rke2, vault, gitlab, etc.)
```

### Kubernetes (ArgoCD GitOps)

```
k8s/
  argocd/
    install.yml        # Root app-of-apps Application
    apps/              # ArgoCD Application manifests (wave 0/1/2)
  platform/            # Helm values + manifests (MetalLB, Traefik, cert-manager, GitLab CE, Wazuh, etc.)
  apps/                # Workload app manifests (Mealie)
```

## Current State Documentation — MANDATORY

**`docs/CURRENT-STATE.md` is the authoritative inventory of all deployed infrastructure.** This is a hard requirement:

1. **Any change to infrastructure MUST be reflected in `docs/CURRENT-STATE.md` in the same commit.** This includes: new VMs/LXCs, IP changes, VLAN changes, service deployments, Terraform applies, Ansible runs, ArgoCD app status changes, hardware additions/removals, and firewall rule changes.
2. **When updating CURRENT-STATE.md, update the "Last updated" date at the top of the file.**
3. **If a change also affects `docs/NETWORK.md`** (VLANs, IPs, switch ports, firewall rules), update both docs in the same commit.
4. **CURRENT-STATE.md documents REALITY, not plans.** Only record what is actually deployed and verified. Use ✅/⚠️/❌ status markers. Move completed items out of "Pending Work" when done.
5. **When diagnosing issues**, check CURRENT-STATE.md first for the actual deployed state. Do not rely on DEPLOYMENT.md or ARCHITECTURE.md for current IPs, VLANs, or service locations — those describe the plan, not reality.

## Naming Conventions

- **Proxmox nodes:** `lab-XX` (e.g., `lab-02`)
- **VM templates:** `tmpl-<distro>-<version>-<role>` (e.g., `tmpl-ubuntu-2404-base`)
- **Vault paths:** `secret/infra/<service>/<node>` (e.g., `secret/infra/proxmox/lab-02`)
- **API tokens:** `<user>@pam!<purpose>-token` (e.g., `terraform@pam!terraform-token`)
- **SSH keys:** `~/.ssh/id_ed25519_<hostname>` (e.g., `~/.ssh/id_ed25519_lab-02`)

## Hardening Boundary

- **Packer bakes the IMMUTABLE BASELINE (~30%):** SSH hardening, UFW, fail2ban, kernel params, disabled filesystems, secure /tmp, password quality, auditd, template cleanup.
- **Ansible enforces RUNTIME STATE (~70%):** AIDE, AppArmor, auditd rules, file permissions, USB storage, cron perms, per-host UFW rules, Wazuh enrollment.
- **LXC vs VM:** LXC containers get `common` only (no `hardening` role). VMs get `common` + `hardening`. LXC shares host kernel — sysctl, auditd, AppArmor, kernel modules are meaningless inside unprivileged containers.
- **Proxmox nodes:** Use iptables (not UFW). `proxmox_skip_ufw: true` in group_vars. Firewall rules set by `proxmox-bootstrap.yml`.

## Vault

- **Address:** `https://10.0.10.10:8200`
- **CA cert:** `~/.lab/tls/ca/ca.pem`
- **KV engine:** v2, mounted at `secret/`
- **Secret taxonomy:**
  - `secret/infra/` — Infrastructure device credentials (Proxmox, UniFi, Hetzner)
  - `secret/services/` — Application-level secrets (GitLab, Grafana)
  - `secret/compute/` — Per-host secrets (SSH keys, admin passwords)
  - `secret/k8s/` — Kubernetes-specific secrets (synced by External Secrets Operator)
- **URL format note:** Vault stores Proxmox base URLs (e.g., `https://10.0.10.2:8006`). The bpg/proxmox Terraform provider uses this directly. Packer's Telmate plugin needs `/api2/json` appended — `packer-build.sh` handles this automatically.

## Key Gotchas

1. **Packer URL format:** Telmate plugin requires `https://host:8006/api2/json`. Vault stores base URL only. `packer-build.sh` appends the path.
2. **Guest agent permissions:** Packer needs `VM.GuestAgent.Audit` privilege (PVE 9.x) on the API token to query guest agent for VM IP discovery. The old `VM.Monitor` privilege was removed in PVE 9.
3. **Proxmox boot order:** Do NOT set `boot = "c"` in Packer templates — it uses legacy format and breaks ISO boot.
4. **Plugin version:** Use `proxmox >= 1.2.3` with `boot_iso {}` block (replaces deprecated `iso_file`/`unmount_iso`).
5. **NIC names on Proxmox nodes:** `proxmox_mgmt_bridge_ports` in inventory MUST match the actual NIC name. Wrong value = permanent network loss requiring console recovery. Always verify with `ip link show` before bootstrap.
6. **fail2ban + ssh-agent:** Multiple keys in agent causes rapid auth failures → ban. Use `-i <key> -o IdentitiesOnly=yes`.
7. **Switch port profile changes:** Applying a Proxmox Trunk profile to a port hosting a critical service (e.g., Vault) will temporarily disrupt connectivity. Plan accordingly — use `use_vault=false` bootstrap fallback if needed.

## Key Documentation

- **`docs/CURRENT-STATE.md` — AUTHORITATIVE inventory of all deployed infrastructure (IPs, VMs, services, status). Update on EVERY infra change.**
- `docs/NETWORK.md` — Full network topology, VLANs, firewall rules, switch port assignments
- `docs/MACHINE-ONBOARDING.md` — Step-by-step guides for adding Proxmox nodes, VMs, LXCs, bare metal
- `docs/DEPLOYMENT.md` — Full deployment sequence for the platform (PLAN, not current state)
- `docs/DEPLOY-RKE2.md` — RKE2 cluster deployment and ArgoCD bootstrap
- `docs/VAULT-OPERATIONS.md` — Vault seal/unseal, backup, Raft operations
