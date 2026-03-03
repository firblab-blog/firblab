# Deployment Guide

Complete bootstrap sequence for deploying the firblab infrastructure from scratch. This is the primary reference for bringing up the entire stack on bare hardware.

## Overview

The bootstrap must be done manually since GitLab does not exist yet. The order ensures each step only depends on previous steps. Vault is deployed as early as possible (Phase 2) so that all subsequent layers can read secrets from it. After Phase 4 (GitLab is live), CI/CD manages all subsequent layers.

```
Phase 0  Prerequisites (manual)         -- bare hardware ready
Phase 1  Network (Layer 00)             -- VLANs and firewall on gw-01
Phase 2  Vault Cluster (Layers 01+02)   -- lab-02 bootstrap + secrets infrastructure
Phase 3  (Skipped — single-node setup, lab-02 serves both roles)
Phase 4  Core Infra (Layer 03)          -- GitLab + Runner on lab-02
  --- CI/CD takes over from here ---
Phase 5  k3s Cluster (Layer 04)         -- Kubernetes workloads
Phase 6  Standalone Services (Layer 05) -- Ghost, FoundryVTT, Plex, Roundcube
Phase 7  Hetzner (Layer 06)             -- public gateway, DNS, email
Phase 8  Validation and Hardening       -- security scans, backup tests
```

Phases 0 through 4 are executed from your local workstation. Phases 5 through 7 are driven by GitLab CI/CD pipelines triggered by merge requests. Phase 8 is a manual validation pass.

---

## Prerequisites

### Hardware

| Machine | Hardware | Role |
|---|---|---|
| **lab-02** | Intel N100, 16GB RAM, Proxmox 9.x | Compute node (Vault standby, GitLab, Wazuh, services) |
| **lab-03** | Intel N100, 12GB RAM, Proxmox 9.x | Lightweight services node (Ghost, Mealie, Roundcube) |
| **lab-macmini** | Mac Mini M4, 16GB+ RAM | Vault primary (native macOS LaunchDaemon), always-on anchor |
| **lab-rpi** | RPi5 CM5, 16GB RAM | Vault standby, backup agent |
| **Hetzner VPS** | cpx21 (3 vCPU, 4GB RAM) | Public gateway (Traefik, WireGuard, email) |
| **gw-01** | Ubiquiti UDM Pro | VLAN routing, firewall, DHCP |

> **Note:** lab-09 was the original pilot/staging node. It was decommissioned due to hardware failure and replaced by lab-02. See [RUNBOOKS.md — Proxmox Node Replacement](RUNBOOKS.md#proxmox-node-replacement-hardware-swap) for the replacement procedure.

### Accounts

- Hetzner Cloud account with API token
- Cloudflare account with API token and zone ID for your domain
- gw-01 (UniFi UDM Pro) with local API access (Settings > Control Plane > API)

### Tools

Install these on your local workstation before starting:

| Tool | Minimum Version | Purpose |
|---|---|---|
| `terraform` | >= 1.9 | Infrastructure provisioning |
| `ansible` | >= 2.15 | Configuration management |
| `packer` | >= 1.11 | VM template building |
| `kubectl` | latest | Kubernetes cluster management |
| `sops` | latest | Secret file encryption |
| `age` | latest | Encryption backend for SOPS |
| `vault` | latest | HashiCorp Vault CLI |
| `jq` | latest | JSON processing (used by scripts) |

Verify all tools are installed:

```bash
terraform version && ansible --version && packer version && \
kubectl version --client && sops --version && age --version && \
vault version && jq --version
```

---

## Initial Setup

### 1. Clone the Repository

```bash
git clone https://github.com/your-username/firblab.git
cd firblab
```

### 2. Generate SOPS Age Key

SOPS + age lets you commit encrypted copies of sensitive files (tfvars, tfstate) to Git. Without it, these files stay local-only via `.gitignore`. You do not need SOPS to deploy -- it is only needed for portable encrypted backups in Git.

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

Record the public key printed to stdout. You will need it in the next step.

### 3. Configure SOPS

Edit `.sops.yaml` at the repo root and replace the placeholder age public key with your own:

```yaml
creation_rules:
  - path_regex: '\.tfvars$'
    age: 'age1your-public-key-here'
  - path_regex: '\.tfstate$'
    age: 'age1your-public-key-here'
  - path_regex: 'vault\.yml$'
    age: 'age1your-public-key-here'
  - path_regex: '\.env$'
    age: 'age1your-public-key-here'
```

**How SOPS fits into the workflow:**

- `.gitignore` excludes `*.tfvars` and `*.tfstate` (plaintext never enters Git)
- `.gitignore` allows `*.sops.*` files through (encrypted copies are safe to commit)
- To commit an encrypted backup of a sensitive file:

```bash
# Encrypt and commit
sops --encrypt terraform/environments/network.tfvars \
  > terraform/environments/network.sops.tfvars
git add terraform/environments/network.sops.tfvars

# On another machine, decrypt
sops --decrypt terraform/environments/network.sops.tfvars \
  > terraform/environments/network.tfvars
```

SOPS encryption is optional during initial bootstrap. You can wire it in later once the infrastructure is running.

### 4. Prepare Variable Files

Every Terraform layer uses `.tfvars` files for environment-specific values. Committed `.tfvars.example` files contain placeholder values.

```bash
for f in terraform/environments/*.tfvars.example; do
  cp "$f" "${f%.example}"
done
```

Edit each `.tfvars` file and fill in your actual values (Proxmox IPs, API tokens, SSH keys, network ranges, etc.). These files are excluded from Git by `.gitignore`.

---

## Phase 0: Prerequisites (Manual)

These steps are performed by hand before any automation runs.

### 0.1 Install Proxmox on lab-02

Download the Proxmox VE 9.x ISO and install it on the compute node (Intel N100, 16GB RAM). Use the default settings. Assign a static IP on the management network (`10.0.10.2`).

### 0.2 Verify lab-02 Network Access

Confirm you can reach the node from your workstation:

```bash
ssh root@10.0.10.2
pvesh get /version
```

The Proxmox web UI should also be accessible at `https://10.0.10.2:8006`.

### 0.3 Prepare Mac Mini M4 for Native Vault

Vault runs directly on macOS as a LaunchDaemon on the Mac Mini M4 at `10.0.10.10`. There is no UTM VM -- Ansible deploys the Vault binary and a `launchd` plist that starts Vault at boot. This eliminates the VM overhead and simplifies the always-on anchor node.

Ensure the Mac Mini has:

- macOS 15+ (Sequoia or later) with Remote Login (SSH) enabled
- A static IP of `10.0.10.10/24` on the Management VLAN (10)
- The `admin` user account with your SSH public key in `~/.ssh/authorized_keys`

```bash
# From workstation, verify connectivity
ssh admin@10.0.10.10 'sw_vers'
```

### 0.4 Install Ubuntu on RPi5 CM5

Flash Ubuntu 24.04 LTS ARM64 (server) to the RPi5 CM5 storage. Assign a static IP on Management VLAN (e.g., `10.0.10.13`). Enable SSH.

```bash
ssh ubuntu@10.0.10.13
```

### 0.5 Generate Age Key for SOPS

If you have not already done so in Initial Setup:

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

Store the age secret key in at least two additional secure locations:

1. Password manager (e.g., 1Password, Bitwarden)
2. Printed QR code in a physical safe

The age key is needed to decrypt any SOPS-encrypted files (tfvars, tfstate, vault.yml) if you choose to commit encrypted copies to Git. Once Vault is running, also store a copy at `secret/backup/age-key`.

### 0.6 Create UniFi API Credentials

On the gw-01 web UI:

1. Navigate to **Settings > Control Plane > API**
2. Create a local-only admin account or note the existing credentials
3. Record the username, password, and controller URL (e.g., `https://10.0.4.1`)

Add these to `terraform/environments/network.tfvars`:

```hcl
unifi_username = "terraform"
unifi_password = "your-password"
unifi_api_url  = "https://10.0.4.1"
unifi_api_key  = "your-api-key"  # If set, username/password are ignored
```

---

## Phase 1: Network (Layer 00)

**What this does:** Declares all VLANs, firewall zones, firewall policies, port profiles, and DHCP ranges on gw-01 (UDM Pro) as Terraform-managed resources. After this phase, the network fabric is ready for all subsequent infrastructure.

**VLAN layout created:**

| VLAN ID | Name | Subnet | Purpose |
|---|---|---|---|
| 1 | Default/LAN | 10.0.4.0/24 | gw-01 default network, workstation |
| 10 | Management | 10.0.10.0/24 | Proxmox hosts, gw-01, Mac Mini, RPi, SSH |
| 20 | Services | 10.0.20.0/24 | k3s cluster, standalone app VMs/LXCs |
| 30 | DMZ | 10.0.30.0/24 | WireGuard endpoint, internet-facing services |
| 40 | Storage | 10.0.40.0/24 | NFS, Longhorn replication, backup traffic |
| 50 | Security | 10.0.50.0/24 | Vault, Wazuh, GitLab (isolated sensitive infra) |

### 1.1 Apply Network Configuration

```bash
cd terraform/layers/00-network
terraform init
terraform plan -var-file=../../environments/network.tfvars
terraform apply -var-file=../../environments/network.tfvars
```

Review the plan output carefully. This modifies your live network configuration. Run from a **wired connection** -- applying WiFi changes over WiFi will drop your session.

**Resources created:**

- 5 VLANs (10, 20, 30, 40, 50)
- Firewall zones and inter-VLAN policies
- Port profiles for trunk and access ports
- DHCP ranges per VLAN

### 1.2 Verify

From a host on the Management VLAN:

```bash
# Confirm VLANs are routable where expected
ping -c 3 10.0.10.1   # Management gateway
ping -c 3 10.0.20.1   # Services gateway
ping -c 3 10.0.50.1   # Security gateway

# Confirm firewall blocks are in place
# From a Services VLAN host, DMZ should be unreachable
ping -c 3 10.0.30.1   # Should fail from Services VLAN

# Verify no Terraform drift
terraform plan -var-file=../../environments/network.tfvars  # Should show "No changes"
```

Check the UniFi UI to confirm VLANs appear under **Settings > Networks** and firewall rules appear under **Settings > Firewall & Security**.

### 1.3 Migrate Hosts to Management VLAN

Now that VLAN 10 (Management) exists, move all physical hosts from the old network (`10.0.4.x`) to VLAN 10 (`10.0.10.0/24`).

**Step 1: Assign switch ports.** In the UniFi UI, navigate to **Devices > Switch > Ports** and assign the "Management Access" port profile (created by Layer 00) to the switch ports for:

- lab-02 (Proxmox pilot node)
- Mac Mini M4 (Vault primary host)
- RPi5 CM5 (Vault standby)

**Step 2: Re-IP existing hosts.** Each physical host is currently on the old network (`10.0.4.x`) and needs a static IP on VLAN 10 (`10.0.10.0/24`). Two scripts handle this — one for Linux hosts, one for macOS. Each host has a dedicated SSH key (`~/.ssh/id_ed25519_lab-*`):

```bash
# Migrate Mac Mini M4 (macOS — uses networksetup)
# User: admin, Key: id_ed25519_lab-macmini
./scripts/migrate-macmini-vlan.sh 10.0.4.28 10.0.10.10 admin ~/.ssh/id_ed25519_lab-macmini

# Migrate lab-02 (Proxmox — auto-detects netplan vs /etc/network/interfaces)
./scripts/migrate-to-vlan.sh <current-ip> 10.0.10.2 root ~/.ssh/id_ed25519_lab-02

# Migrate RPi5 (Ubuntu — uses netplan)
./scripts/migrate-to-vlan.sh <current-ip> 10.0.10.13 admin ~/.ssh/id_ed25519_lab-rpi5
```

Each script SSHes to the host at its current IP, applies the new static IP config, and waits for the host to come up at the new address. The SSH session will drop when the IP changes -- this is expected.

> **Note:** Replace `<current-ip>` with the actual current IPs of your hosts. The Mac Mini is at `10.0.4.28`. For Linux hosts, if the network interface name isn't auto-detected, pass it as the 5th argument: `./scripts/migrate-to-vlan.sh <ip> 10.0.10.2 root ~/.ssh/id_ed25519_lab-02 eth0`

**Step 3: Verify.** Confirm all hosts are reachable at their new IPs:

```bash
# Mac Mini M4 (macOS host)
ssh -i ~/.ssh/id_ed25519_lab-macmini admin@10.0.10.10 'hostname'

# Proxmox pilot
ssh -i ~/.ssh/id_ed25519_lab-02 root@10.0.10.2 'hostname'

# RPi5
ssh -i ~/.ssh/id_ed25519_lab-rpi5 admin@10.0.10.13 'hostname'

# Management gateway
ping -c 3 10.0.10.1
```

---

## Phase 2: Vault Cluster (Layers 01 + 02 -- THE PILOT)

**What this does:** Gets the central secrets infrastructure live as early as possible. First bootstraps lab-02 as the Proxmox compute node (Layer 01), then deploys the 3-node HashiCorp Vault HA cluster (Layer 02) across three physically separate machines. This is the most critical phase -- Vault becomes the central secrets store for all subsequent infrastructure.

### 2.1 Bootstrap Proxmox Compute Node (lab-02)

lab-02 must be configured before Vault because it hosts the vault-2 VM. It also serves as the main compute node for all subsequent workloads (GitLab, Wazuh, k3s, standalone services).

```bash
ansible-playbook ansible/playbooks/proxmox-bootstrap.yml -l lab-02
```

**What the playbook does:**

- Creates a non-root admin user with sudo
- Deploys your SSH public key and disables password authentication
- Configures VLAN-aware bridge (`vmbr0`) with trunk to all VLANs
- Hardens SSH (disables root login, sets key-only auth)
- Installs required packages (qemu-guest-agent, cloud-init utilities)

```bash
# Bootstrap mode (Vault doesn't exist yet, pass creds directly)
cd terraform/layers/01-proxmox-base
terraform init
terraform apply -var use_vault=false -var-file=../../environments/lab-02.tfvars
```

**Resources created:**

- Storage pools (local-lvm, NFS mounts if applicable)
- Ubuntu 24.04 cloud image downloads
- Packer VM/LXC templates built from the cloud images

#### Create Proxmox API Token for Terraform

After bootstrapping the Proxmox node, create an API token that Terraform will use for all subsequent provisioning. This token will be seeded into Vault so that Terraform layers can authenticate without local credentials.

```bash
# Create Proxmox API token for Terraform
ansible-playbook ansible/playbooks/proxmox-api-setup.yml --limit lab-02
```

The playbook output includes the API token ID and secret. **Save this output** -- you will need the token secret to seed into Vault in Phase 2.5.5. The token secret is only displayed once and cannot be retrieved later.

**Verify:**

```bash
# Proxmox API is accessible via token
curl -s -k -H "Authorization: PVEAPIToken=terraform@pam!terraform-token=<token>" \
  https://10.0.10.2:8006/api2/json/version | jq .

# Storage pools are visible
pvesh get /storage --output-format json | jq '.[].storage'

# VM templates exist
qm list | grep template

# No Terraform drift (bootstrap mode — Vault not yet available)
cd terraform/layers/01-proxmox-base
terraform plan -var use_vault=false -var-file=../../environments/lab-02.tfvars
```

### 2.2 Configure Vault on Mac Mini

vault-1 runs natively on the Mac Mini M4 at `10.0.10.10`, deployed by Ansible. No VM creation is needed -- Vault runs directly on macOS as a LaunchDaemon. The `vault-deploy.yml` playbook handles installing the Vault binary, creating the data directories, deploying TLS certificates, and installing the `com.hashicorp.vault` LaunchDaemon plist.

```bash
ansible-playbook ansible/playbooks/vault-deploy.yml --limit vault-1
```

Verify the Mac Mini is reachable and ready:

```bash
ssh admin@10.0.10.10 'sw_vers && vault version'
```

### 2.3 Harden Mac Mini and RPi5

**Vault node topology:**

| Node | Machine | OS | Address |
|---|---|---|---|
| vault-1 | Mac Mini M4 (native macOS) | macOS 15+ ARM64 | 10.0.10.10:8200 |
| vault-2 | lab-02 (Proxmox VM) | Ubuntu 24.04 AMD64 | 10.0.50.2:8200 |
| vault-3 | RPi5 CM5 (bare metal) | Ubuntu 24.04 ARM64 | 10.0.10.13:8200 |

```bash
ansible-playbook ansible/playbooks/harden.yml -l macmini,rpi
```

Applies the full hardening baseline to both hosts before Vault is installed:

- DevSec OS + SSH hardening
- CIS Ubuntu 24.04 Level 1 benchmarks
- fail2ban, auditd, AIDE, automatic security updates

### 2.4 Provision Vault Infrastructure

```bash
cd terraform/layers/02-vault-infra
terraform init
terraform apply
```

**Resources created:**

- Vault VM on lab-02 (Proxmox)
- Network configuration for Mac Mini and RPi5 Vault nodes
- TLS certificates for Vault cluster communication (bootstrap certs)

### 2.5 Deploy Vault

```bash
ansible-playbook ansible/playbooks/vault-deploy.yml
```

**What the playbook does:**

1. Installs Vault binary on all 3 nodes
2. Deploys Vault server configuration with Raft storage and TLS
3. Deploys the unseal vault on the Mac Mini (separate process, port 8210)
4. Initializes the Vault cluster on vault-1
5. Configures transit auto-unseal (production cluster uses the unseal vault's transit engine)
6. Joins vault-2 and vault-3 to the Raft cluster

After this step, Vault is running but empty.

### 2.5.5 Configure Vault (Layer 02-vault-config)

After Vault is initialized and unsealed, apply the Vault configuration layer to set up
secrets engines, policies, audit logging, and seed infrastructure credentials:

```bash
cd terraform/layers/02-vault-config
terraform init
terraform apply -var-file=terraform.tfvars
```

This layer creates:
- KV v2 secrets engine at `secret/`
- Vault policies (admin, terraform, gitlab-ci)
- File audit logging
- Admin token (replaces root token for daily use)
- Proxmox API credentials seeded at `secret/infra/proxmox/<node>`

Save the admin token output to `~/.vault-token`:
```bash
terraform output -raw admin_token > ~/.vault-token
chmod 600 ~/.vault-token
```

### 2.6 Seed Vault with Remaining Secrets

Most secrets are now seeded automatically by Layer 02-vault-config (Phase 2.5.5), including the KV v2 secrets engine, Vault policies, audit logging, and Proxmox API credentials. The following secrets still require manual seeding until their respective Terraform providers are integrated:

```bash
export VAULT_ADDR="https://10.0.10.10:8200"
export VAULT_TOKEN="$(cat ~/.vault-token)"
export VAULT_CACERT="/path/to/vault-ca.pem"

# Hetzner Cloud API
vault kv put secret/infra/hetzner/api \
  token="your-hetzner-api-token"

# Cloudflare API
vault kv put secret/infra/cloudflare/api \
  token="your-cloudflare-api-token" \
  zone_id="your-cloudflare-zone-id"

# UniFi controller credentials
vault kv put secret/infra/unifi/udm-pro \
  username="terraform" \
  password="your-unifi-password" \
  url="https://10.0.4.1"
```

### 2.7 Enable PKI Secrets Engine

Create the internal certificate authority hierarchy:

```bash
# Enable root CA (long TTL, offline after issuing intermediate)
vault secrets enable -path=pki pki
vault secrets tune -max-lease-ttl=87600h pki
vault write -field=certificate pki/root/generate/internal \
  common_name="firblab Root CA" \
  issuer_name="root-ca" \
  ttl=87600h > root-ca.pem

# Enable intermediate CA (issues short-lived certs)
vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=43800h pki_int

# Generate intermediate CSR, sign with root, import
vault write -format=json pki_int/intermediate/generate/internal \
  common_name="firblab Intermediate CA" \
  issuer_name="intermediate-ca" | jq -r '.data.csr' > intermediate.csr

vault write -format=json pki/root/sign-intermediate \
  csr=@intermediate.csr \
  format=pem_bundle \
  ttl=43800h | jq -r '.data.certificate' > intermediate-signed.pem

vault write pki_int/intermediate/set-signed \
  certificate=@intermediate-signed.pem

# Create a role for issuing certs
vault write pki_int/roles/firblab \
  allowed_domains="example-lab.local,mgmt.example-lab.local" \
  allow_subdomains=true \
  max_ttl=720h
```

### 2.8 Enable Audit Logging

```bash
vault audit enable file file_path=/var/log/vault/audit.log
```

Verify the audit device is active:

```bash
vault audit list
```

### 2.9 Set Up Backup Cron

Deploy the backup script and cron job:

```bash
ansible-playbook ansible/playbooks/vault-backup.yml
```

Or manually install:

```bash
# On vault-1 (Mac Mini)
sudo cp scripts/vault-backup.sh /usr/local/bin/vault-backup.sh
sudo chmod +x /usr/local/bin/vault-backup.sh

# Add to crontab (runs every 6 hours)
echo "0 */6 * * * /usr/local/bin/vault-backup.sh" | sudo tee /etc/cron.d/vault-backup
```

The backup script performs:

1. `vault operator raft snapshot save` to create a point-in-time snapshot
2. Encrypts the snapshot with age
3. Copies to RPi5 via SCP (local backup)
4. Uploads to Hetzner Object Storage (off-site backup)
5. Cleans up snapshots older than 30 days locally, 90 days on S3

### 2.10 Verify

```bash
# Check cluster health on all nodes
for addr in 10.0.10.10 10.0.50.2 10.0.10.13; do
  echo "--- vault at $addr ---"
  VAULT_ADDR="https://$addr:8200" vault status
done

# Verify secrets are readable
vault kv get secret/infra/proxmox/lab-02

# Verify Raft cluster membership
vault operator raft list-peers

# Test auto-unseal (restart one standby node)
ssh ubuntu@10.0.10.13 'sudo systemctl restart vault'
sleep 10
VAULT_ADDR="https://10.0.10.13:8200" vault status
# Sealed should be false -- auto-unseal via transit worked

# Verify PKI
vault read pki_int/roles/firblab

# Verify audit logging
vault audit list
```

**AT THIS POINT:** Vault is live and serving secrets. lab-02 is proven as a working Proxmox node and will also serve as the main compute node for all services (GitLab, Wazuh, k3s, standalone services).

> **Note:** In the original two-node design, Phase 3 rebuilt a separate lab-01 as the main compute node. With the single-node lab-02 setup, lab-02 serves both roles (Vault standby + compute). Phase 3 is skipped -- proceed directly to Phase 3.5 (Packer templates) and Phase 4 (Core Infra) targeting lab-02.

---

## Phase 3.5: Build Packer VM Templates

**What this does:** Builds hardened VM templates on Proxmox using Packer with credentials sourced from Vault. These templates bake in CIS Level 1 baseline hardening (SSH, firewall, kernel params, filesystem restrictions, password quality, auditd) so every VM starts secure. Downstream Terraform layers clone from these templates instead of raw cloud images.

### 3.5.1 Prerequisites

- Vault running and accessible with admin token
- Packer >= 1.11 installed locally
- Proxmox API token for Packer (`packer@pam!packer-token` with `PVEVMAdmin` role)

ISOs are downloaded automatically by Layer 01 (`terraform apply` downloads Ubuntu 24.04 and Rocky Linux 9 ISOs to every Proxmox node's `local:iso/` storage). No manual ISO uploads needed.

### 3.5.2 Apply Packer Vault Policy and Download ISOs

The `packer` Vault policy was added in Phase 3 (Layer 02-vault-config). ISOs are managed by Layer 01. Apply both if needed:

```bash
# Apply packer policy to Vault
cd /Users/admin/repos/firblab/terraform/layers/02-vault-config
terraform apply -var-file=../../environments/vault-config.tfvars

# Download ISOs to Proxmox (automated)
cd /Users/admin/repos/firblab/terraform/layers/01-proxmox-base
terraform apply -var proxmox_node=lab-02
```

### 3.5.3 Build Ubuntu 24.04 Template (VM ID 9000)

```bash
# Ensure Vault environment is configured
export VAULT_ADDR="https://10.0.10.10:8200"
export VAULT_TOKEN="$(cat ~/.vault-token)"
export VAULT_CACERT="$HOME/.lab/tls/ca/ca.pem"

# Build the hardened Ubuntu template
./scripts/packer-build.sh lab-02
```

This creates `tmpl-ubuntu-2404-base` (VM ID 9000) with:
- SSH hardening (no root login, no password auth, Protocol 2, MaxAuthTries 3)
- UFW firewall (deny incoming, allow SSH only)
- fail2ban, auditd, unattended-upgrades
- Kernel security parameters (ASLR, reverse-path filtering, SYN cookies)
- Disabled unused filesystems (cramfs, freevxfs, jffs2, hfs, hfsplus, squashfs, udf)
- Secure /tmp and shared memory mounts
- Password quality (minlen 12, digit/upper/lower/special required)
- Cloud-init ready for Terraform provisioning

### 3.5.4 Build Rocky Linux 9 Template (VM ID 9001)

```bash
./scripts/packer-build.sh lab-02 rocky-9
```

This creates `tmpl-rocky-9-base` (VM ID 9001) with equivalent hardening adapted for the RedHat ecosystem (firewalld, SELinux enforcing, dnf-automatic, EPEL).

### 3.5.5 Verify Templates

Check that both templates appear in the Proxmox UI as templates:
- VM 9000: `tmpl-ubuntu-2404-base`
- VM 9001: `tmpl-rocky-9-base`

---

## Phase 4: Core Infra (Layer 03, on lab-02)

**What this does:** Deploys GitLab CE and a GitLab Runner on lab-02. After this phase, GitLab CI/CD is operational and manages all subsequent infrastructure layers. This is the handoff point from manual bootstrap to automated pipelines.

**RAM budget (lab-02 has 16 GB):**

| Service | RAM | Type |
|---|---|---|
| vault-2 | 4 GB | VM (deployed in Phase 2) |
| GitLab CE | 8 GB | VM |
| GitLab Runner | 2 GB | LXC (Docker nesting) |
| Proxmox host | ~2 GB | Overhead |
| **Total** | **~16 GB** | |

> **Note:** Wazuh Manager was removed from Layer 03 — lab-02 cannot support vault-2 (4GB) + GitLab (8GB) + Runner (2GB) + Wazuh (8GB) = 24GB on 16GB hardware. Wazuh can be re-enabled on a separate node if needed.

### 4.1 Provision Core Infrastructure VMs

**Prerequisites:**
- Phase 2 complete (Vault operational, Proxmox API token in Vault)
- Phase 3.5 complete (Packer template ID 9000 built on lab-02)
- `VAULT_ADDR`, `VAULT_TOKEN`, `VAULT_CACERT` exported
- SSH agent loaded with Proxmox host key: `ssh-add ~/.ssh/id_ed25519_lab-02`

```bash
cd terraform/layers/03-core-infra
terraform init
terraform plan    # Review — should create GitLab VM + Runner LXC
terraform apply
```

> **CRITICAL:** The `clone_template_vm_id` variable defaults to `9000` (Packer template). **Never** change this to `0` or omit it after initial deployment — switching from clone mode to cloud-image mode forces Terraform to **destroy and recreate** the VM, which is a data-loss event.

**Resources created on lab-02:**

| Resource | Type | IP | Network |
|---|---|---|---|
| GitLab CE | VM (8GB, 4 CPU) | 10.0.10.50 | Management (untagged on vmbr0) |
| GitLab Runner | LXC (2GB, 2 CPU) | 10.0.10.51 | Management (untagged on vmbr0) |

Terraform reads Proxmox credentials from Vault via the Vault provider (`data "vault_kv_secret_v2"`). Cloud-init snippets require SSH to the Proxmox host (provider `ssh { agent = true }` block).

### 4.2 Extract SSH Keys

Terraform generates per-host SSH keys. Extract them for Ansible access:

```bash
# GitLab VM
terraform output -raw gitlab_ssh_private_key > ~/.ssh/id_ed25519_gitlab
chmod 600 ~/.ssh/id_ed25519_gitlab
ssh-keygen -y -f ~/.ssh/id_ed25519_gitlab > ~/.ssh/id_ed25519_gitlab.pub

# GitLab Runner LXC
terraform output -raw gitlab_runner_ssh_private_key > ~/.ssh/id_ed25519_gitlab-runner
chmod 600 ~/.ssh/id_ed25519_gitlab-runner
ssh-keygen -y -f ~/.ssh/id_ed25519_gitlab-runner > ~/.ssh/id_ed25519_gitlab-runner.pub
```

> **macOS note:** OpenSSH 10.x requires the `.pub` file alongside the private key. Without it, `ssh` silently skips the key and falls through to password auth.

**Verify SSH to GitLab VM:**

```bash
ssh-keygen -R 10.0.10.50    # Clear stale known_hosts if rebuilding
ssh -i ~/.ssh/id_ed25519_gitlab admin@10.0.10.50 hostname
```

### 4.3 Bootstrap GitLab Runner LXC

The Proxmox LXC provider injects SSH keys to **root only** (no username field). Run the LXC bootstrap playbook to create the `admin` user:

```bash
cd ~/repos/firblab
ansible-playbook ansible/playbooks/lxc-bootstrap.yml --limit gitlab-runner -e "ansible_user=root"
```

**Verify:**

```bash
ssh -i ~/.ssh/id_ed25519_gitlab-runner admin@10.0.10.51 hostname
# Should return: gitlab-runner
```

### 4.4 Deploy GitLab CE

```bash
ansible-playbook ansible/playbooks/gitlab-deploy.yml --limit gitlab
```

**What the playbook does:**

- Installs GitLab CE (Omnibus package, current version)
- Formats and mounts the data disk at `/mnt/gitlab-data`
- Configures `gitlab.rb` (external URL, git data storage using `gitaly['configuration']` syntax)
- Runs `gitlab-ctl reconfigure`
- Waits for health check (`http://127.0.0.1/-/health` — localhost only in GitLab 18.x)
- Verifies external reachability (root URL returns 302 → `/users/sign_in`)

**Verification:**

```bash
# From your workstation
curl -s -o /dev/null -w "%{http_code}" http://10.0.10.50
# Should return 302

# Get the initial root password (on the GitLab VM)
ssh -i ~/.ssh/id_ed25519_gitlab admin@10.0.10.50 'sudo cat /etc/gitlab/initial_root_password'
```

Log in at `http://10.0.10.50` with user `root` and the initial password.

> **GitLab 18.x notes:**
> - Health endpoints (`/-/health`, `/-/readiness`, `/-/liveness`) return 404 from external IPs — they only respond on `127.0.0.1`.
> - Git data storage uses `gitaly['configuration']` syntax (the `git_data_dirs()` method was removed in 18.0).

### 4.5 Create and Register GitLab Runner

#### 4.5.1 Create the Runner in GitLab UI

1. Log into GitLab at `http://10.0.10.50`
2. Navigate to **Admin > CI/CD > Runners > New instance runner**
3. Set tags: `docker,linux,firblab`
4. Leave other options at defaults (not paused, not protected, no timeout)
5. Click **Create runner**
6. Copy the `glrt-` authentication token from the next page

> **GitLab 18.x runner registration:** With `glrt-` tokens, tags, description, locked, and run-untagged are configured **server-side** in the GitLab UI — NOT via `gitlab-runner register` CLI flags. The register command only accepts `--url`, `--token`, `--executor`, and executor-specific options.

#### 4.5.2 Store the Runner Token in Vault

```bash
export VAULT_ADDR=https://10.0.10.10:8200
export VAULT_CACERT=~/.lab/tls/ca/ca.pem
# Use your admin token (from Phase 2)
vault kv put secret/services/gitlab/runner token=glrt-YOUR_TOKEN_HERE

# Verify
vault kv get -field=token secret/services/gitlab/runner
```

The Ansible playbook reads this token automatically via `vault kv get` (pipe lookup on the controller). No `-e gitlab_runner_token=...` needed on the command line.

> **Vault path taxonomy:** `secret/services/gitlab/runner` follows the established pattern: `services/` = application-level secrets, `gitlab/` = GitLab service, `runner` = runner-specific credential. Parallel to `secret/services/gitlab/admin` (PAT + root password).

#### 4.5.3 Deploy the Runner

```bash
# Ensure Vault env vars are set (the playbook reads the token from Vault)
export VAULT_ADDR=https://10.0.10.10:8200
export VAULT_TOKEN=hvs.YOUR_ADMIN_TOKEN
export VAULT_CACERT=~/.lab/tls/ca/ca.pem

cd ~/repos/firblab
ansible-playbook ansible/playbooks/gitlab-runner-deploy.yml --limit gitlab-runner
```

**What the playbook does:**

1. Retrieves `glrt-` token from Vault (`vault kv get -mount=secret -field=token services/gitlab/runner`)
2. Applies common role (packages, NTP, fail2ban, SSH hardening, UFW firewall)
3. Installs Docker CE (official apt repo)
4. Installs GitLab Runner (official apt repo)
5. Templates `config.toml` (concurrent jobs, check interval)
6. Registers runner with GitLab (`gitlab-runner register --non-interactive`)
7. Verifies service status and registration

> **dpkg lock contention:** The common role enables `unattended-upgrades`, which can immediately grab the dpkg lock on a fresh system. The role includes a "Wait for apt/dpkg lock" task that polls until the lock is free (up to 5 minutes) before any package operations.

> **Hardening is intentionally omitted** for LXC containers. LXC shares the host kernel — most CIS controls (sysctl, kernel modules, AppArmor, auditd) either fail or are meaningless inside an unprivileged container. Hardening is applied at the Proxmox host level.

**Verification:**

```bash
# SSH to the runner LXC and check
ssh -i ~/.ssh/id_ed25519_gitlab-runner admin@10.0.10.51

sudo gitlab-runner status
# Should show: gitlab-runner: Service is running

sudo gitlab-runner list
# Should show the registered runner with the GitLab URL

sudo docker info --format '{{.ServerVersion}}'
# Should show the installed Docker version
```

Also verify in the GitLab UI: **Admin > CI/CD > Runners** — the runner should show as online with a green dot.

### 4.6 Configure CI/CD Variables and Push Repository

CI/CD variables are managed at the **instance level** via Terraform — every project inherits Vault access automatically. Pipelines authenticate to Vault using **AppRole** (short-lived tokens, automatic rotation).

#### 4.6.1 Create AppRole for GitLab CI (Layer 02-vault-config)

The AppRole auth backend, role, and `gitlab-ci` policy are managed in Layer 02-vault-config. If you haven't applied this layer since the AppRole resources were added:

```bash
cd terraform/layers/02-vault-config
terraform init
terraform apply -var-file=../../environments/vault-config.tfvars
```

This creates:
- AppRole auth backend at `auth/approle`
- `gitlab-ci` role with 1-hour token TTL and the `gitlab-ci` policy
- A `secret_id` for the role

Extract the credentials:

```bash
ROLE_ID=$(terraform output -raw gitlab_ci_approle_role_id)
SECRET_ID=$(terraform output -raw gitlab_ci_approle_secret_id)
```

#### 4.6.2 Set Instance-Level CI/CD Variables (Layer 03-gitlab-config)

```bash
cd terraform/layers/03-gitlab-config
terraform apply \
  -var "vault_approle_role_id=$ROLE_ID" \
  -var "vault_approle_secret_id=$SECRET_ID"
```

This creates 4 instance-level CI/CD variables (visible under **Admin > Settings > CI/CD > Variables**):

| Variable | Type | Protected | Masked | Source |
|---|---|---|---|---|
| `VAULT_ADDR` | env_var | No | No | Default: `https://10.0.10.10:8200` |
| `VAULT_CACERT` | file | No | No | Read from `~/.lab/tls/ca/ca.pem` |
| `VAULT_ROLE_ID` | env_var | No | Yes | Layer 02-vault-config output |
| `VAULT_SECRET_ID` | env_var | No | Yes | Layer 02-vault-config output |

All variables are unprotected (available on all branches) so MR pipelines can run `terraform plan`.

#### 4.6.3 Pipeline Vault Login Pattern

Plan/apply/deploy jobs exchange AppRole credentials for a short-lived `VAULT_TOKEN` in their `before_script`. The CI Docker images don't include the `vault` CLI, so we hit the Vault API directly with `wget` (Alpine) or `curl` (Debian):

**Terraform template** (`ci-templates/terraform-ci.yml`) — Alpine-based image, uses `wget`:

```yaml
# Inlined in .terraform-plan, .terraform-apply, .terraform-destroy before_script
- apk add --no-cache -q jq
- |
  VAULT_TOKEN=$(wget -qO- \
    --ca-certificate "$VAULT_CACERT" \
    --header "Content-Type: application/json" \
    --post-data "{\"role_id\":\"$VAULT_ROLE_ID\",\"secret_id\":\"$VAULT_SECRET_ID\"}" \
    "$VAULT_ADDR/v1/auth/approle/login" \
    | jq -r '.auth.client_token')
- export VAULT_TOKEN
```

**Ansible template** (`ci-templates/ansible-ci.yml`) — Debian-based image, uses `curl`:

```yaml
# Inlined in .ansible-deploy before_script
- apt-get update -qq && apt-get install -yqq jq > /dev/null 2>&1
- |
  VAULT_TOKEN=$(curl -sf \
    --cacert "$VAULT_CACERT" \
    -X POST -H "Content-Type: application/json" \
    -d "{\"role_id\":\"$VAULT_ROLE_ID\",\"secret_id\":\"$VAULT_SECRET_ID\"}" \
    "$VAULT_ADDR/v1/auth/approle/login" \
    | jq -r '.auth.client_token')
- export VAULT_TOKEN
```

The token has a 1-hour TTL (4-hour max) and the `gitlab-ci` policy. Validate and scan jobs don't need Vault access — they use `terraform init -backend=false`.

A `vault:test-approle` job in `.gitlab-ci.yml` runs on every MR to verify the full auth chain (login + policy access).

#### 4.6.4 Push Repository

```bash
# Add GitLab as a remote (repos were pushed by scripts/push-repos-to-gitlab.sh)
# If not already pushed:
git remote add gitlab http://10.0.10.50/infrastructure/firblab.git
git push gitlab main
```

### 4.7 Verify

```bash
# GitLab web UI is accessible
curl -s -o /dev/null -w "%{http_code}" http://10.0.10.50
# Should return 302

# GitLab Runner is registered and online
ssh -i ~/.ssh/id_ed25519_gitlab-runner admin@10.0.10.51 'sudo gitlab-runner list'

# Runner token is in Vault
vault kv get -field=token secret/services/gitlab/runner
# Should return glrt-...

# CI pipeline runs successfully
git checkout -b test/ci-validation
git commit --allow-empty -m "test: verify CI pipeline"
git push gitlab test/ci-validation
# Check GitLab UI > CI/CD > Pipelines — job should execute on the runner
```

### 4.8 Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Terraform destroys GitLab VM on apply | `clone_template_vm_id` changed (e.g., 9000 → 0) | **Never** change this after initial deployment. Set default to `9000` in `variables.tf`. |
| SSH to Runner LXC asks for password | LXC provider only injects keys to root | Run `lxc-bootstrap.yml` (Step 4.3) |
| Ansible "No inventory was parsed" | Running from wrong directory | Run from repo root (`~/repos/firblab/`), not from `ansible/` |
| Docker role fails with dpkg lock | `unattended-upgrades` holding the lock | Wait 2 minutes and re-run. The dpkg lock wait task handles this automatically. |
| `gitlab-runner register` rejects `--tag-list` | GitLab 18.x: tags are server-side with `glrt-` tokens | Tags are set in the GitLab UI, not via CLI |
| GitLab health check returns 404 | GitLab 18.x: health endpoints are localhost-only | Use `http://127.0.0.1/-/health` from the remote host |
| `hvac` Python library crashes Ansible | Homebrew Python incompatibility | Playbook uses `vault` CLI pipe lookup — just ensure `VAULT_ADDR`/`VAULT_TOKEN`/`VAULT_CACERT` are set |

**FROM HERE:** GitLab CI/CD manages all subsequent layers (Phases 5-7). Merge requests to `main` that modify a layer's files trigger the corresponding pipeline (plan on MR, apply on merge).

---

## Phase 5: k3s Cluster (Layer 04, via GitLab CI/CD)

**What this does:** Provisions a k3s Kubernetes cluster on lab-02 and installs platform services (ArgoCD, cert-manager, MetalLB, Longhorn, monitoring, External Secrets Operator). Application workloads (Mealie, SonarQube) are deployed via ArgoCD.

### 5.1 Trigger Pipeline for Layer 04

Create a merge request that includes the Layer 04 Terraform configuration:

```bash
git checkout -b deploy/k3s-cluster
# Ensure terraform/layers/04-k3s-cluster/ files are committed
git push gitlab deploy/k3s-cluster
```

The GitLab pipeline will:

1. Run `terraform validate` and `tfsec` scan
2. Run `terraform plan` and post the plan as an MR comment
3. On merge to `main`, run `terraform apply` (manual gate)

**Resources created on lab-02:**

- 3 k3s master VMs (2 CPU, 4 GB RAM each, Services VLAN 20)
- 2 k3s worker VMs (4 CPU, 8 GB RAM each, Services VLAN 20)

### 5.2 Deploy k3s

The pipeline triggers the Ansible playbook after Terraform apply:

```bash
ansible-playbook ansible/playbooks/k3s-deploy.yml
```

This installs k3s on all master and worker nodes and produces a kubeconfig file.

### 5.3 Install Platform Services

Install the cluster platform stack via ArgoCD bootstrap:

```bash
# Get kubeconfig from the k3s deployment
export KUBECONFIG=/path/to/k3s-kubeconfig.yaml

# Bootstrap ArgoCD
kubectl apply -f k8s/argocd/install.yml

# ArgoCD then syncs all platform services from the repo:
# - cert-manager (TLS via Vault PKI issuer)
# - MetalLB (LoadBalancer IPs: 10.0.20.220-250)
# - Longhorn (persistent storage with snapshots)
# - External Secrets Operator (Vault -> k8s Secrets sync)
# - Prometheus + Grafana + Loki (monitoring stack)
```

### 5.4 Deploy Applications via ArgoCD

ArgoCD watches `k8s/workloads/` and automatically deploys:

- **Mealie** -- recipe manager (from `k8s/workloads/mealie/`)
- **SonarQube** -- code quality analysis (from `k8s/workloads/sonarqube/`)

ArgoCD Application manifests are in `k8s/argocd/apps/`.

### 5.5 Verify

```bash
# All nodes are Ready
kubectl get nodes
# NAME          STATUS   ROLES                  AGE   VERSION
# k3s-master-1  Ready    control-plane,master   ...   v1.xx
# k3s-master-2  Ready    control-plane,master   ...   v1.xx
# k3s-master-3  Ready    control-plane,master   ...   v1.xx
# k3s-worker-1  Ready    <none>                 ...   v1.xx
# k3s-worker-2  Ready    <none>                 ...   v1.xx

# ArgoCD UI is accessible
kubectl -n argocd get svc argocd-server
# Access via port-forward or MetalLB IP

# All ArgoCD apps are synced
kubectl -n argocd get applications
# Should show Synced / Healthy for all apps

# Mealie is accessible
curl -s -o /dev/null -w "%{http_code}" http://mealie.services.example-lab.local

# SonarQube is accessible
curl -s -o /dev/null -w "%{http_code}" http://sonarqube.services.example-lab.local

# Longhorn dashboard shows healthy volumes
kubectl -n longhorn-system get volumes

# Monitoring stack is collecting data
kubectl -n monitoring get pods
```

---

## Phase 6: Standalone Services (Layer 05, via GitLab CI/CD)

**What this does:** Deploys standalone services that run as individual VMs or LXCs on lab-02 (not in the k3s cluster). These services have specific resource or runtime requirements that make bare VM/LXC deployment more appropriate than Kubernetes.

### 6.1 Trigger Pipeline for Layer 05

```bash
git checkout -b deploy/standalone-services
# Ensure terraform/layers/05-standalone-services/ files are committed
git push gitlab deploy/standalone-services
```

The pipeline provisions and configures:

| Service | Runtime | VLAN | Notes |
|---|---|---|---|
| **Ghost** | LXC (Docker Compose) | 20 (Services) | Blog, exposed via Hetzner Traefik |
| **FoundryVTT** | VM | 20 (Services) | VTT platform, WebSocket/WebRTC |
| **Plex** | VM | 20 (Services) | Media server, potential GPU passthrough |
| **Roundcube** | LXC | 20 (Services) | Webmail client (Migadu IMAP/SMTP) |

Each service is provisioned by Terraform (infrastructure) and configured by Ansible (application deployment):

```bash
# Terraform creates the VMs/LXCs
# Pipeline runs:
cd terraform/layers/05-standalone-services
terraform apply

# Ansible configures the services
# Pipeline triggers:
ansible-playbook ansible/playbooks/service-deploy.yml -l standalone_services
```

### 6.2 Restore Migrated Data

If you backed up data in Phase 3.1, restore it now:

```bash
# Ghost content
scp backups/ghost-export.json admin@ghost-lxc:/tmp/
ssh admin@ghost-lxc 'docker exec ghost-app ghost import /tmp/ghost-export.json'

# Plex library
scp backups/plex-backup.tar.gz admin@plex-vm:/tmp/
ssh admin@plex-vm 'sudo tar xzf /tmp/plex-backup.tar.gz -C /'

# FoundryVTT worlds
scp backups/foundry-backup.tar.gz admin@foundry-vm:/tmp/
ssh admin@foundry-vm 'sudo tar xzf /tmp/foundry-backup.tar.gz -C /opt/foundryvtt/'
```

### 6.3 Verify

```bash
# Ghost blog is accessible and content is intact
curl -s -o /dev/null -w "%{http_code}" https://ghost.services.example-lab.local
# Verify a known post exists via the Ghost API

# FoundryVTT loads a world
curl -s -o /dev/null -w "%{http_code}" https://foundry.services.example-lab.local

# Plex finds the media library
curl -s -o /dev/null -w "%{http_code}" http://plex.services.example-lab.local:32400/web

# Roundcube webmail is accessible
curl -s -o /dev/null -w "%{http_code}" https://mail.services.example-lab.local
```

---

## Phase 7: Hetzner (Layer 06, via GitLab CI/CD)

**What this does:** Deploys the public-facing Hetzner VPS that serves as the internet gateway for the entire homelab. Configures WireGuard site-to-site tunnel, Traefik reverse proxy, Cloudflare DNS, and email infrastructure. After this phase, your services are accessible from the public internet.

### 7.1 Deploy Hetzner Server

```bash
git checkout -b deploy/hetzner
# Ensure terraform/layers/06-hetzner/ files are committed
git push gitlab deploy/hetzner
```

The pipeline provisions:

- Hetzner cpx21 VPS (3 vCPU, 4 GB RAM)
- Cloud-init bootstraps the server with Docker, WireGuard, and base packages
- Hetzner firewall rules (SSH, HTTP, HTTPS, WireGuard UDP)

### 7.2 Configure WireGuard Site-to-Site Tunnel

The Ansible playbook (triggered by the pipeline) configures WireGuard on both endpoints:

```
Hetzner VPS (public IP) <-- WireGuard tunnel (10.8.0.0/24) --> DMZ VLAN (30) on lab-02
```

The tunnel allows Traefik on Hetzner to route traffic to homelab services on the Services VLAN (20) via the DMZ VLAN (30).

### 7.3 Configure Traefik Routing

Traefik v3 on the Hetzner VPS handles all public-facing domains:

- Automatic HTTPS via Let's Encrypt ACME
- Routes to homelab services through the WireGuard tunnel
- Rate limiting and security headers

### 7.4 Configure Cloudflare DNS Records

Terraform manages Cloudflare DNS records for all public-facing services:

```hcl
# Example records created:
# blog.yourdomain.com    -> Hetzner VPS IP (proxied)
# foundry.yourdomain.com -> Hetzner VPS IP (proxied)
# mail.yourdomain.com    -> Hetzner VPS IP (not proxied, for email)
```

### 7.5 Verify

```bash
# Public domains resolve correctly
dig +short blog.yourdomain.com
dig +short foundry.yourdomain.com

# HTTPS is valid (Let's Encrypt cert)
curl -s -o /dev/null -w "%{http_code}" https://blog.yourdomain.com
# Should return 200

# WireGuard tunnel is active
ssh admin@hetzner-vps 'sudo wg show'
# Should show active peer with recent handshake

# AdGuard Home DNS filtering
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000
# Should return 200 (AdGuard admin UI)

# Traefik dashboard (if enabled)
curl -s https://traefik.yourdomain.com/api/rawdata | jq '.routers | keys'
```

---

## Phase 8: Validation and Hardening

**What this does:** A comprehensive validation pass across the entire stack. Run these checks after all phases are complete to confirm the infrastructure meets security and operational requirements.

### 8.1 Terraform Security Scan

```bash
# Scan all layers for misconfigurations
cd terraform/
for layer in layers/0*; do
  echo "=== Scanning $layer ==="
  tfsec "$layer"
done
```

**Target:** 0 critical or high severity findings.

### 8.2 Container and Image Security Scan

```bash
# Scan Kubernetes manifests
trivy config k8s/

# Scan running container images in k3s
trivy k8s --report summary
```

**Target:** 0 critical findings.

### 8.3 CIS Benchmark Audit

Run the CIS Ubuntu 24.04 Level 1 benchmark on every host:

```bash
ansible-playbook ansible/playbooks/harden.yml -l all --check --diff
```

Any drift from the hardened baseline will appear in the diff output.

For a formal CIS audit, use the CIS-CAT tool or Wazuh's SCA (Security Configuration Assessment) module, which runs CIS checks automatically.

**Target:** Level 1 pass on all hosts.

### 8.4 Wazuh Agent Status

Verify all agents are reporting to the Wazuh Manager:

```bash
# Via Wazuh API
curl -s -k -u admin:admin \
  "https://wazuh.security.example-lab.local:55000/agents?pretty" | \
  jq '.data.affected_items[] | {name, status, lastKeepAlive}'
```

**Target:** All agents in `active` status, no critical alerts in the dashboard.

### 8.5 VLAN Isolation Port Scan

From a host on each VLAN, scan the other VLANs to confirm only expected ports are open:

```bash
# From Services VLAN (20), scan Security VLAN (50)
nmap -Pn -p 8200,80,443,1514,1515 10.0.50.0/24
# Only Vault (8200), GitLab (80/443), Wazuh agent ports (1514/1515) should be open

# From Services VLAN (20), scan DMZ VLAN (30)
nmap -Pn 10.0.30.0/24
# Should show no open ports (Services -> DMZ is blocked)

# From Default VLAN (1), scan any lab VLAN
nmap -Pn 10.0.10.0/24
# Should show no open ports (Default -> Lab is blocked)
```

**Target:** Only expected ports open; all firewall policies enforced.

### 8.6 SSH Key-Only Authentication

Verify password authentication is disabled on every host:

```bash
for host in 10.0.10.2 10.0.10.2 10.0.10.10 10.0.10.13; do
  echo "--- $host ---"
  ssh -o PasswordAuthentication=yes -o BatchMode=yes admin@$host 'echo ok' 2>&1 || echo "PASS: password auth rejected"
done
```

**Target:** Every host rejects password-based SSH login.

### 8.7 Vault Audit Log Review

```bash
# Check that audit log is being written
vault audit list

# Review recent entries (on vault-1)
ssh admin@10.0.10.10 'sudo tail -20 /var/log/vault/audit.log' | jq .

# Confirm root token has been revoked (or create a plan to revoke it)
vault token lookup
# If still using the root token, revoke it and use AppRole/admin tokens instead:
# vault token revoke <root-token>
```

### 8.8 Backup Restore Test

Validate that Vault snapshots can be restored to a fresh node:

```bash
# On a test node (e.g., a temporary VM on lab-02)
# 1. Install Vault
# 2. Start with a fresh Raft storage directory
# 3. Restore from snapshot

vault operator raft snapshot restore -force /path/to/latest-snapshot.snap

# Verify data is intact
vault kv get secret/infra/proxmox/lab-02
```

**Target:** Snapshot restores successfully and all secrets are readable.

---

## State Management

Terraform state management evolves across two phases during the bootstrap.

### Phase 1: Bootstrap (Layers 00-02)

All state is stored locally. Plaintext state files are excluded from Git by `.gitignore`. To back up state in Git, encrypt with SOPS first:

```bash
# After each apply, optionally encrypt and commit state
sops --encrypt terraform/layers/00-network/terraform.tfstate \
  > terraform/layers/00-network/terraform.tfstate.sops.json
git add terraform/layers/00-network/terraform.tfstate.sops.json

# To restore on another machine
sops --decrypt terraform/layers/00-network/terraform.tfstate.sops.json \
  > terraform/layers/00-network/terraform.tfstate
```

This approach has zero external dependencies -- the foundational layers that create the remote state infrastructure cannot depend on that infrastructure existing. SOPS encryption of state files is optional; without it, state stays local-only.

### Phase 2: Post-Vault, Post-Hetzner (Layers 03-08) — NOT YET IMPLEMENTED

> **Current status (2026-02-20):** All layers still use local state (Phase 1). CI plan jobs fail against empty state and are configured with `allow_failure: true`. CI apply jobs are manual-gated and unused. When this phase is implemented, remove `allow_failure: true` from `.terraform-plan` in `ci-templates/terraform-ci.yml`.

After Vault and Hetzner are live, migrate layers 03-08 to Hetzner Object Storage (S3-compatible backend):

```hcl
# terraform/layers/03-core-infra/backend.tf
terraform {
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
}
```

To migrate an existing local state to the S3 backend:

```bash
cd terraform/layers/03-core-infra
# Add the backend "s3" block to backend.tf
terraform init -migrate-state
```

**Layers 00-02 stay local + Git permanently.** Foundational layers should not depend on remote state they create. If the Hetzner S3 bucket is down, you can still manage network, Proxmox, and Vault.

GitLab CI serialization (one pipeline at a time per layer) prevents concurrent state modifications, so DynamoDB locking is not needed.

**Fallback:** If S3 becomes unavailable, revert to local + Git by removing the `backend "s3"` block and running `terraform init -migrate-state`.

---

## Per-Layer Verification Checklist

Use this as a quick reference to verify each layer after deployment or when troubleshooting.

### Layer 00: Network

- [ ] `terraform plan -var-file=../../environments/network.tfvars` in `00-network/` shows no changes
- [ ] All 5 VLANs visible in UniFi UI under Settings > Networks
- [ ] Ping between VLANs from Management host succeeds where expected
- [ ] Firewall blocks between restricted VLANs confirmed (Services cannot reach DMZ, Default cannot reach Lab)
- [ ] DHCP ranges are correct for each VLAN
- [ ] Port profiles assigned to switch ports match Terraform state

### Layer 01: Proxmox Base

- [ ] Proxmox API accessible via token on each node
- [ ] Storage pools visible in Proxmox UI (local-lvm, NFS if configured)
- [ ] Cloud-init Ubuntu 24.04 template available
- [ ] VLAN-aware bridge (`vmbr0`) configured on each node
- [ ] SSH key-only access, root login disabled
- [ ] `terraform plan` shows no drift

### Layer 02: Vault

- [ ] `vault status` returns healthy on all 3 nodes
- [ ] `vault operator raft list-peers` shows 3 voters
- [ ] `vault kv get secret/infra/proxmox/lab-02` returns expected data
- [ ] Auto-unseal works (restart a standby, verify it unseals without intervention)
- [ ] PKI intermediate CA can issue certificates
- [ ] Audit log is being written (`/var/log/vault/audit.log`)
- [ ] Backup cron is running (`crontab -l` on vault-1)
- [ ] Backup snapshot exists on RPi5 and Hetzner S3

### Layer 03: Core Infra

- [ ] GitLab web UI is accessible and login works
- [ ] GitLab Runner is registered and online (Admin > Runners)
- [ ] CI pipeline triggers on push and completes successfully
- [ ] CI/CD variables (VAULT_ADDR, VAULT_TOKEN) are configured
- [ ] Wazuh Manager dashboard is accessible
- [ ] All Wazuh agents are in `active` status
- [ ] No critical Wazuh alerts on the dashboard

### Layer 04: k3s Cluster

- [ ] `kubectl get nodes` shows all masters and workers in Ready state
- [ ] ArgoCD UI is accessible, all apps show Synced/Healthy
- [ ] MetalLB is assigning LoadBalancer IPs in the 10.0.20.220-250 range
- [ ] Longhorn dashboard shows healthy storage volumes
- [ ] cert-manager can issue certificates from Vault PKI
- [ ] External Secrets Operator is syncing secrets from Vault
- [ ] Prometheus is scraping metrics, Grafana dashboards are populated
- [ ] Mealie and SonarQube are accessible via their ingress URLs

### Layer 05: Standalone Services

- [ ] Ghost blog is accessible, test post can be published
- [ ] FoundryVTT loads the game world, WebSocket connections work
- [ ] Plex finds the media library, streams playback successfully
- [ ] Roundcube webmail is accessible, can compose and read email
- [ ] All services are enrolled as Wazuh agents

### Layer 06: Hetzner

- [ ] Public domains resolve to the Hetzner VPS IP via Cloudflare DNS
- [ ] HTTPS certificates are valid (Let's Encrypt) on all public domains
- [ ] WireGuard tunnel is active (`wg show` on Hetzner shows recent handshake)
- [ ] Traefik routes traffic through the tunnel to homelab services
- [ ] AdGuard Home DNS filtering is active on the VPS
- [ ] Hetzner firewall allows only SSH, HTTP, HTTPS, and WireGuard UDP
- [ ] CrowdSec is installed and active on the Hetzner VPS

---

## Troubleshooting

### Vault Cluster Issues

**Vault is sealed after reboot:**

The unseal vault on the Mac Mini uses Shamir 1/1. After a power outage:

1. SSH to the Mac Mini: `ssh admin@10.0.10.10`
2. Unseal the unseal vault: `VAULT_ADDR=https://127.0.0.1:8210 vault operator unseal`
3. Enter the single unseal key (from your password manager)
4. The production Vault cluster should auto-unseal within 30 seconds
5. Verify: `vault status` on all 3 nodes

**Raft cluster lost quorum (2+ nodes down):**

```bash
# On the surviving node, force a single-node recovery
vault operator raft join -leader-ca-cert=@/etc/vault.d/tls/ca.pem https://<surviving-node>:8200
```

See `docs/VAULT-OPERATIONS.md` for the full disaster recovery procedure.

### Terraform State Issues

**State file is locked or corrupted:**

```bash
# For local state (layers 00-02), inspect directly
cat terraform.tfstate | jq .

# If state was SOPS-encrypted in Git, decrypt first
sops --decrypt terraform.tfstate.sops.json | jq .

# For S3 state (layers 03-06), download and inspect
aws s3 cp --endpoint-url https://region1.your-objectstorage.com \
  s3://firblab-tfstate/layers/03-core-infra/terraform.tfstate .
```

**State drift after manual changes:**

```bash
terraform plan  # Review what Terraform wants to change
terraform apply # Let Terraform reconcile, or:
terraform import <resource> <id>  # Import manually-created resources
```

### Network Connectivity Issues

**Cannot reach a VLAN:**

1. Check UniFi UI for VLAN configuration
2. Verify trunk port profile on the switch port
3. Verify Proxmox bridge has VLAN awareness enabled
4. Check zone policies: `terraform state show unifi_firewall_zone_policy.<name>`

### Packer Build Fails with "500 no such file '/version'"

This error means the Packer Proxmox plugin is hitting the wrong API path. The Telmate `proxmox-api-go` library (used by the Packer plugin) appends `/version` directly to the `proxmox_url` value. If the URL is missing `/api2/json`, Packer hits `https://host:8006/version` instead of `https://host:8006/api2/json/version`.

**The fix is already built into `packer-build.sh`** — it automatically appends `/api2/json` to the base URL stored in Vault. If you see this error, check:

1. The Vault secret at `secret/infra/proxmox/<node>` has a `url` field (e.g., `https://10.0.10.2:8006`)
2. The `packer-build.sh` script is being used (not manual `packer build`)
3. If running Packer manually, ensure `proxmox_url` includes `/api2/json`:
   ```
   proxmox_url = "https://10.0.10.2:8006/api2/json"
   ```

**Note:** The bpg/proxmox Terraform provider (used by Layer 01) accepts the base URL without `/api2/json`. Only the Packer Proxmox plugin requires the full path. The Vault secret stores the base URL to remain compatible with both consumers.

### GitLab CI/CD Pipeline Failures

**Runner is offline:**

```bash
ssh admin@gitlab-runner-lxc 'sudo gitlab-runner status'
ssh admin@gitlab-runner-lxc 'sudo gitlab-runner verify'
```

**Pipeline cannot reach Vault:**

1. Verify `VAULT_ADDR` CI/CD variable is set correctly
2. Verify the GitLab Runner can reach the Security VLAN (50)
3. Check the AppRole token has not expired

---

## Quick Reference: Full Command Sequence

For experienced operators who want the condensed command list without explanations:

```bash
# Phase 0: Manual hardware setup (not scriptable)

# Phase 1: Network
cd terraform/layers/00-network && terraform init && terraform apply -var-file=../../environments/network.tfvars

# Phase 1 cont: Migrate hosts to VLAN 10
# Assign "Management Access" port profile to switch ports in UniFi UI, then:
./scripts/migrate-macmini-vlan.sh 10.0.4.28 10.0.10.10 admin ~/.ssh/id_ed25519_lab-macmini  # Mac Mini M4
./scripts/migrate-to-vlan.sh <old-ip> 10.0.10.2 root ~/.ssh/id_ed25519_lab-02                 # lab-02
./scripts/migrate-to-vlan.sh <old-ip> 10.0.10.13 admin ~/.ssh/id_ed25519_lab-rpi5              # RPi5

# Phase 2: Vault (includes Proxmox pilot bootstrap for vault-2 VM)
ansible-playbook ansible/playbooks/proxmox-bootstrap.yml -l lab-02
cd terraform/layers/01-proxmox-base && terraform init && terraform apply -var use_vault=false -var-file=../../environments/lab-02.tfvars
ansible-playbook ansible/playbooks/proxmox-api-setup.yml --limit lab-02
ansible-playbook ansible/playbooks/harden.yml -l macmini,rpi
cd terraform/layers/02-vault-infra && terraform init && terraform apply -var use_vault=false -var-file=../../environments/lab-02.tfvars
ansible-playbook ansible/playbooks/vault-deploy.yml
cd terraform/layers/02-vault-config && terraform init && terraform apply -var-file=../../environments/vault-config.tfvars
terraform output -raw admin_token > ~/.vault-token && chmod 600 ~/.vault-token
export VAULT_ADDR="https://10.0.10.10:8200"
export VAULT_TOKEN="$(cat ~/.vault-token)"
vault kv put secret/infra/hetzner/api token=...
vault kv put secret/infra/cloudflare/api token=... zone_id=...
vault kv put secret/infra/unifi/udm-pro username=... password=... url=...
# PKI setup, audit logging, backup cron (see Phase 2.7-2.9)

# Phase 3: Skipped (single-node setup — lab-02 already bootstrapped in Phase 2)

# Phase 4: Core Infra (on lab-02)
cd terraform/layers/03-core-infra && terraform init && terraform apply
terraform output -raw gitlab_ssh_private_key > ~/.ssh/id_ed25519_gitlab && chmod 600 ~/.ssh/id_ed25519_gitlab
ssh-keygen -y -f ~/.ssh/id_ed25519_gitlab > ~/.ssh/id_ed25519_gitlab.pub
terraform output -raw gitlab_runner_ssh_private_key > ~/.ssh/id_ed25519_gitlab-runner && chmod 600 ~/.ssh/id_ed25519_gitlab-runner
ssh-keygen -y -f ~/.ssh/id_ed25519_gitlab-runner > ~/.ssh/id_ed25519_gitlab-runner.pub
ansible-playbook ansible/playbooks/lxc-bootstrap.yml --limit gitlab-runner -e "ansible_user=root"
ansible-playbook ansible/playbooks/gitlab-deploy.yml --limit gitlab
# Create runner in GitLab UI (Admin > CI/CD > Runners), copy glrt- token
vault kv put secret/services/gitlab/runner token=glrt-YOUR_TOKEN
ansible-playbook ansible/playbooks/gitlab-runner-deploy.yml --limit gitlab-runner
# Generate PAT, store in Vault, apply gitlab-config
bash scripts/generate-gitlab-token.sh 10.0.10.50
vault kv put secret/services/gitlab/admin personal_access_token=glpat-XXX root_password=XXX
cd terraform/layers/03-gitlab-config && terraform init && terraform apply
# AppRole for CI/CD (from Layer 02-vault-config)
cd terraform/layers/02-vault-config && terraform apply -var-file=../../environments/vault-config.tfvars
ROLE_ID=$(terraform output -raw gitlab_ci_approle_role_id)
SECRET_ID=$(terraform output -raw gitlab_ci_approle_secret_id)
cd ../03-gitlab-config && terraform apply -var "vault_approle_role_id=$ROLE_ID" -var "vault_approle_secret_id=$SECRET_ID"
# Push repos
export GITLAB_TOKEN=$(vault kv get -field=personal_access_token secret/services/gitlab/admin)
bash scripts/push-repos-to-gitlab.sh

# Phases 5-7: Via GitLab CI/CD (merge requests trigger pipelines)

# Phase 8: Validation
tfsec terraform/layers/
trivy config k8s/
ansible-playbook ansible/playbooks/harden.yml -l all --check --diff
# Wazuh agent check, port scans, SSH verification, Vault audit review, backup test
```
