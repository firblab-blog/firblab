# Machine Onboarding Guide

How to add a new machine to firblab. The architecture is designed so that adding a machine is a configuration change, not a restructure. Every machine type follows the same pattern: define it in config, provision it, configure it with Ansible, verify it works.

This guide covers every machine type the lab supports.

---

## Table of Contents

- [Proxmox Node (Bare Metal)](#proxmox-node-bare-metal)
- [Proxmox VM](#proxmox-vm)
- [Proxmox LXC Container](#proxmox-lxc-container)
- [Bare Metal / RPi](#bare-metal--rpi)
- [Hetzner Cloud Server](#hetzner-cloud-server)
- [Adding a New k3s Worker Node](#adding-a-new-k3s-worker-node)
- [Adding a New Vault Cluster Node](#adding-a-new-vault-cluster-node)
- [Post-Onboarding Checklist](#post-onboarding-checklist)
- [IP Address Planning](#ip-address-planning)

---

## Proxmox Node (Bare Metal)

A physical server running Proxmox VE that hosts VMs and LXC containers. The full
onboarding pipeline touches 4 Terraform layers, 3 Ansible playbooks, and Vault.

### Prerequisites

- Proxmox VE 9.x ISO on USB (or already installed)
- Physical access to the server
- A free port on a managed switch (switch-01 or switch-02)
- A free Management VLAN IP (10.0.10.x, below .100)
- Vault unsealed with `VAULT_TOKEN` set in environment

### Step 1: Install Proxmox VE (manual)

Install Proxmox from ISO. During install, set the management IP to an available
address on the Management VLAN (10.0.10.x). Hostname should follow the
`lab-XX` convention.

### Step 2: Assign switch port profile (Terraform Layer 00)

The new node will have **no network** until its switch port gets the "Proxmox Trunk"
profile. This is the most common gotcha — Proxmox is installed but can't reach the
network because the port is on the Default VLAN.

Edit `terraform/layers/00-network/devices.tf` and add a `port_override` block to
the appropriate switch resource:

```hcl
# In unifi_device.switch_closet or unifi_device.switch_minilab:
port_override {
  number          = <PORT_NUMBER>
  name            = "lab-XX"
  port_profile_id = unifi_port_profile.proxmox_trunk.id
}
```

Update `docs/NETWORK.md` "Physical Switch Port Assignments" table to reflect the
new port assignment.

Apply:

```bash
cd terraform/layers/00-network
terraform plan    # verify only the port override is added
terraform apply
```

Verify from workstation: `ping 10.0.10.X`

### Step 3: Generate SSH key

Each Proxmox node gets a dedicated SSH key stored at `~/.ssh/id_ed25519_lab-XX`.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_lab-XX -C "admin@lab-XX" -N ""
ssh-copy-id -i ~/.ssh/id_ed25519_lab-XX.pub root@10.0.10.X
# Test:
ssh -i ~/.ssh/id_ed25519_lab-XX -o IdentitiesOnly=yes root@10.0.10.X hostname
```

> **Note:** Use `-o IdentitiesOnly=yes` to avoid fail2ban lockouts when
> `ssh-agent` has multiple keys loaded.

### Step 4: Verify NIC name

**Critical:** The bootstrap playbook reconfigures the network bridge to use the
physical NIC specified by `proxmox_mgmt_bridge_ports` in the inventory. A wrong
value permanently kills network access — recovery requires physical console.

```bash
ssh -i ~/.ssh/id_ed25519_lab-XX -o IdentitiesOnly=yes root@10.0.10.X 'ip link show'
```

Look for the physical NIC (not `lo`, `vmbr0`, or `bond0`). Common names: `nic0`,
`eno1`, `enp1s0`. Existing nodes use `nic0` — but different hardware may differ.

### Step 5: Add to Ansible inventory

Edit `ansible/inventory/hosts.yml` and add the node to the `proxmox_nodes` group:

```yaml
proxmox_nodes:
  hosts:
    lab-XX:
      ansible_host: 10.0.10.X
      ansible_user: admin
      ansible_ssh_private_key_file: ~/.ssh/id_ed25519_lab-XX
      proxmox_node_name: lab-XX
      proxmox_mgmt_bridge_ports: <NIC_NAME>   # from Step 4
```

Group vars in `group_vars/proxmox_nodes.yml` apply automatically:
- `proxmox_skip_ufw: true` (Proxmox uses iptables, not UFW)
- `usb_storage_enabled: true` (for VM passthrough)
- `ssh_permit_root_login: "prohibit-password"` (required for cluster operations)

### Step 6: Bootstrap with Ansible

```bash
ansible-playbook ansible/playbooks/proxmox-bootstrap.yml --limit lab-XX
```

**Play 1 (as root — first and last time):**
- Disables enterprise repos, enables no-subscription community repos
- Creates `admin` user with SSH key + passwordless sudo
- Configures VLAN-aware bridge (`vmbr0`) with trunk to all VLANs
- Sets iptables firewall (SSH 22, WebUI 8006, Corosync 5405-5412, Migration 60000-60050)
- Enables `snippets` + `images` content types on local storage
- Locks root SSH to key-only (`prohibit-password`)

**Play 2 (as admin):**
- `common` role: packages, NTP, fail2ban, SSH hardening, auto-updates
- `hardening` role: CIS L1 kernel params, auditd, AIDE, AppArmor

### Step 7: Create API token + seed Vault

```bash
ansible-playbook ansible/playbooks/proxmox-api-setup.yml --limit lab-XX
```

Creates `terraform@pam` user, `TerraformProv` role, and API token on the Proxmox
node, then **automatically seeds the credentials into Vault** at
`secret/infra/proxmox/lab-XX`. No manual `vault kv put` or tfvars editing needed.

Requires: `vault` CLI on controller, `VAULT_TOKEN` set, CA cert at `vault_lookup_ca_cert`.

If the token already exists (re-run), the Vault seed is skipped — the token secret
is only available at creation time.

Verify:

```bash
vault kv get secret/infra/proxmox/lab-XX
curl -sk -H "Authorization: PVEAPIToken=terraform@pam!terraform-token=<secret>" \
  https://10.0.10.X:8006/api2/json/version | jq .
```

### Step 8: Add to Layer 01 (Proxmox Base)

Add the node to the `proxmox_nodes` variable in
`terraform/layers/01-proxmox-base/variables.tf`:

```hcl
"lab-XX" = {
  name = "lab-XX"
  ip   = "10.0.10.X"
}
```

Apply:

```bash
cd terraform/layers/01-proxmox-base
terraform apply
```

This downloads ISOs, LXC templates, and cloud images to the new node's local
storage.

### Step 9: Join the Proxmox cluster

```bash
ansible-playbook ansible/playbooks/proxmox-cluster-init.yml \
  --limit lab-01,lab-XX
```

The playbook:
- Temporarily enables root SSH for `pvecm` operations
- Sets up bidirectional root SSH key trust
- Joins the new node to the existing cluster (`pvecm add`)
- Nodes join serially (serial: 1) to prevent quorum race conditions
- Re-locks root SSH after join completes
- Verifies quorum and node membership

`lab-01` is the cluster leader (defined in `group_vars/proxmox_nodes.yml`).

### Step 10: Enroll Wazuh agent (optional)

```bash
ansible-playbook ansible/playbooks/wazuh-deploy.yml --limit lab-XX
```

### Verify

```bash
# Network connectivity
ping 10.0.10.X

# SSH access
ssh -i ~/.ssh/id_ed25519_lab-XX -o IdentitiesOnly=yes admin@10.0.10.X hostname

# Proxmox API
curl -sk -H "Authorization: PVEAPIToken=terraform@pam!terraform-token=<secret>" \
  https://10.0.10.X:8006/api2/json/version | jq .

# Vault secret
vault kv get secret/infra/proxmox/lab-XX

# Cluster membership
ssh admin@10.0.10.X sudo pvecm status
ssh admin@10.0.10.X sudo pvecm nodes

# Web UI — verify node visible at https://10.0.10.2:8006 (any cluster node)
```

### Files touched during onboarding

| File | Change |
|------|--------|
| `terraform/layers/00-network/devices.tf` | Port override for switch port |
| `docs/NETWORK.md` | Switch port assignment table |
| `ansible/inventory/hosts.yml` | Node in `proxmox_nodes` group |
| `terraform/layers/01-proxmox-base/variables.tf` | Node in `proxmox_nodes` map |

---

## Proxmox VM

A virtual machine running on a Proxmox node, fully managed by Terraform.

### Prerequisites

- A running Proxmox node with available resources
- A free static IP on the target VLAN (below .100)

### Steps

1. **Define in Terraform.** Add a new module block using `modules/proxmox-vm` in the appropriate layer:

   | Layer | Use case |
   |---|---|
   | `03-core-infra` | Infrastructure services (DNS, monitoring, etc.) |
   | `04-k3s-cluster` | Kubernetes cluster nodes |
   | `05-standalone-services` | Standalone application VMs |

   Example module block:

   ```hcl
   module "new_vm" {
     source = "../../modules/proxmox-vm"

     hostname    = "new-vm"
     target_node = "pve-01"
     cores       = 2
     memory      = 2048
     disk_size   = 20
     vlan_tag    = 20
     ip_address  = "10.0.20.X/24"
     gateway     = "10.0.20.1"
   }
   ```

2. **Choose the correct VLAN:**

   | VLAN | Subnet | Purpose |
   |---|---|---|
   | 20 (Services) | 10.0.20.0/24 | Application workloads |
   | 30 (DMZ) | 10.0.30.0/24 | Internet-facing services |
   | 50 (Security) | 10.0.50.0/24 | Security infrastructure |

3. **Assign a static IP** within the chosen VLAN's range. Use an IP below .100 to avoid the DHCP range (.100-.200).

4. **Apply Terraform:**

   ```bash
   cd terraform/layers/<layer>
   terraform plan
   terraform apply
   ```

5. **Add to Ansible inventory and configure.** Add the new VM to `ansible/inventory/hosts.yml` under the appropriate group, then run the service role:

   ```bash
   ansible-playbook ansible/playbooks/<service>.yml -l new-vm
   ```

6. **Harden:**

   ```bash
   ansible-playbook ansible/playbooks/harden.yml -l new-vm
   ```

7. **Enroll the Wazuh agent:**

   ```bash
   ansible-playbook ansible/playbooks/wazuh-deploy.yml -l new-vm
   ```

---

## Proxmox LXC Container

An unprivileged container with Docker nesting support, managed by Terraform. LXCs are lighter than VMs and suitable for single-service workloads.

### Prerequisites

- A running Proxmox node with available resources
- A free static IP on the target VLAN (below .100)

### Steps

1. **Define in Terraform.** Add a new module block using `modules/proxmox-lxc` in the appropriate layer:

   ```hcl
   module "new_lxc" {
     source = "../../modules/proxmox-lxc"

     hostname    = "new-lxc"
     target_node = "pve-01"
     cores       = 1
     memory      = 512
     disk_size   = 8
     vlan_tag    = 20
     ip_address  = "10.0.20.X/24"
     gateway     = "10.0.20.1"
   }
   ```

2. **Choose the VLAN and assign a static IP** (same VLAN table as the VM section above, same rule: stay below .100).

3. **Apply Terraform:**

   ```bash
   cd terraform/layers/<layer>
   terraform plan
   terraform apply
   ```

4. **Add to Ansible inventory and deploy the service.** Add the LXC to `ansible/inventory/hosts.yml`, then run the appropriate service role:

   ```bash
   ansible-playbook ansible/playbooks/<service>.yml -l new-lxc
   ```

5. **Harden and enroll Wazuh:**

   ```bash
   ansible-playbook ansible/playbooks/harden.yml -l new-lxc
   ansible-playbook ansible/playbooks/wazuh-deploy.yml -l new-lxc
   ```

---

## Bare Metal / RPi

A physical machine that is not running Proxmox. This covers Raspberry Pi 5 / CM5 boards, Mac Mini UTM VMs, or any other standalone hardware.

### Prerequisites

- Ubuntu 24.04 installed (ARM64 for RPi and Mac Mini, AMD64 for x86 hardware)
- Network cable connected to the appropriate VLAN port on the switch
- A free static IP on the target VLAN

### Steps

1. **Install the OS.** Flash Ubuntu 24.04 Server to the device. For RPi, use the Raspberry Pi Imager. Set a temporary password for initial SSH access.

2. **Configure the network.** Connect to the appropriate VLAN and assign a static IP. Edit `/etc/netplan/` config or set it during OS install.

3. **Add to Ansible inventory.** Edit `ansible/inventory/hosts.yml` and add the host under the appropriate group:

   ```yaml
   bare_metal:
     hosts:
       rpi-new:
         ansible_host: 10.0.20.X
   ```

4. **Bootstrap.** Set up SSH key authentication and create the admin user. If the machine can be reached from the Ansible controller:

   ```bash
   ssh-copy-id admin@10.0.20.X
   ```

   Then verify Ansible connectivity:

   ```bash
   ansible -m ping rpi-new
   ```

5. **Harden:**

   ```bash
   ansible-playbook ansible/playbooks/harden.yml -l rpi-new
   ```

6. **Deploy the service:**

   ```bash
   ansible-playbook ansible/playbooks/<service>.yml -l rpi-new
   ```

7. **Enroll the Wazuh agent:**

   ```bash
   ansible-playbook ansible/playbooks/wazuh-deploy.yml -l rpi-new
   ```

---

## Hetzner Cloud Server

A cloud VPS hosted at Hetzner, managed by Terraform. Used for services that need to be outside the homelab (public-facing, geographically distributed, or as a backup location).

### Prerequisites

- Hetzner Cloud API token configured in Terraform
- Cloudflare API token configured (for DNS)

### Steps

1. **Define in Terraform.** Add the server to `terraform/layers/06-hetzner/main.tf` using the `modules/hetzner-server` module:

   ```hcl
   module "new_hetzner" {
     source = "../../modules/hetzner-server"

     hostname    = "htz-new"
     server_type = "cx22"
     location    = "fsn1"
     image       = "ubuntu-24.04"
   }
   ```

2. **Add DNS records.** Use the `modules/cloudflare-dns` module to create the appropriate DNS entries pointing to the server's public IP:

   ```hcl
   module "new_hetzner_dns" {
     source = "../../modules/cloudflare-dns"

     zone_id = var.cloudflare_zone_id
     name    = "new-service"
     type    = "A"
     value   = module.new_hetzner.ipv4_address
   }
   ```

3. **Apply Terraform:**

   ```bash
   cd terraform/layers/06-hetzner
   terraform plan
   terraform apply
   ```

4. **Add to Ansible inventory and configure.** Add the server to `ansible/inventory/hosts.yml` under the `hetzner` group, then run hardening and the service role:

   ```bash
   ansible-playbook ansible/playbooks/harden.yml -l htz-new
   ansible-playbook ansible/playbooks/<service>.yml -l htz-new
   ```

5. **Set up WireGuard** (if the server needs access to homelab resources). Configure a WireGuard tunnel between the Hetzner server and the homelab gateway.

---

## Adding a New k3s Worker Node

Scaling the Kubernetes cluster is a config change.

### Steps

1. **Update the worker count** in `terraform/layers/04-k3s-cluster/terraform.tfvars`:

   ```hcl
   worker_count = 4  # was 3
   ```

2. **Apply Terraform** to provision the new VM:

   ```bash
   cd terraform/layers/04-k3s-cluster
   terraform plan
   terraform apply
   ```

3. **Join the node to the cluster** by running the k3s deploy playbook. Terraform outputs will include the new node's IP:

   ```bash
   ansible-playbook ansible/playbooks/k3s-deploy.yml
   ```

4. **Verify** the node joined successfully:

   ```bash
   kubectl get nodes
   ```

   The new node should appear with status `Ready` within a minute or two.

---

## Adding a New Vault Cluster Node

Adding a node to the Vault Raft cluster. For full Raft peer operations (removing nodes, disaster recovery), see `docs/VAULT-OPERATIONS.md`.

### Steps

1. **Add the node** to the `nodes` variable in `terraform/layers/02-vault/terraform.tfvars`.

2. **If this is a Proxmox VM**, also add the VM configuration to the `nodes_config` variable with cores, memory, disk, VLAN, and IP.

3. **Apply Terraform:**

   ```bash
   cd terraform/layers/02-vault
   terraform plan
   terraform apply
   ```

4. **Deploy Vault** to the new node:

   ```bash
   ansible-playbook ansible/playbooks/vault-deploy.yml -l vault-new
   ```

5. **Verify** the node joined the Raft cluster:

   ```bash
   vault operator raft list-peers
   ```

   The new node should appear as a `follower` in the peer list.

---

## Post-Onboarding Checklist

Run through this checklist for every new machine, regardless of type. Do not skip items.

- [ ] SSH key-only authentication enabled (password auth disabled)
- [ ] Host added to `ansible/inventory/hosts.yml`
- [ ] Hardening playbook applied (DevSec baseline + CIS Level 1)
- [ ] Wazuh agent enrolled and reporting to the manager
- [ ] Monitoring: `node_exporter` installed and Prometheus is scraping it
- [ ] Backup: machine included in backup schedule (if it holds state)
- [ ] Firewall: only expected ports are open (verify with a port scan from another VLAN)
- [ ] DNS: hostname is resolvable (via internal DNS or `/etc/hosts`)
- [ ] Documentation: inventory comments updated if anything non-obvious was configured

---

## IP Address Planning

Reference this table when assigning IPs to new machines.

| VLAN | Subnet | Static Range | DHCP Range | Reserved | Purpose |
|---|---|---|---|---|---|
| 10 (Management) | 10.0.10.0/24 | .2 - .99 | .100 - .200 | -- | Proxmox hosts, switches, IPMI |
| 20 (Services) | 10.0.20.0/24 | .2 - .99 | .100 - .200 | .220 - .250 (MetalLB) | Application VMs and LXCs |
| 30 (DMZ) | 10.0.30.0/24 | .2 - .99 | .100 - .200 | -- | Internet-facing services |
| 40 (Storage) | 10.0.40.0/24 | .2 - .99 | .100 - .200 | -- | NFS, iSCSI, Ceph |
| 50 (Security) | 10.0.50.0/24 | .2 - .99 | .100 - .200 | -- | Wazuh, Vault, monitoring |

Rules:

- Always assign static IPs below .100.
- The DHCP range (.100 - .200) is for temporary and test use only. Production machines must have static assignments.
- The .220 - .250 range on the Services VLAN is reserved for MetalLB (Kubernetes LoadBalancer IPs). Do not assign these manually.
- Document every IP assignment in the Ansible inventory with a comment so the next person knows what is using it.
