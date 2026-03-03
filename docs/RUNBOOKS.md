# Operational Runbooks

This document is the grab-and-go reference for incident response, routine maintenance, and monitoring alert triage. Every section contains exact commands. When something is on fire, start here.

For architecture context, see [ARCHITECTURE.md](ARCHITECTURE.md). For network details, see [NETWORK.md](NETWORK.md). For Vault-specific deep dives, see [VAULT-OPERATIONS.md](VAULT-OPERATIONS.md).

---

## Table of Contents

- [Incident Response](#incident-response)
  - [Power Outage Recovery](#power-outage-recovery)
  - [Single Node Failure](#single-node-failure)
  - [Network Outage (WireGuard Tunnel Down)](#network-outage-wireguard-tunnel-down)
  - [Vault Sealed Alert (CRITICAL)](#vault-sealed-alert-critical)
  - [GitLab Down](#gitlab-down)
  - [k3s Cluster Issues](#k3s-cluster-issues)
- [Proxmox Node Replacement (Hardware Swap)](#proxmox-node-replacement-hardware-swap)
- [Routine Maintenance](#routine-maintenance)
  - [Updating Ubuntu Packages (All Hosts)](#updating-ubuntu-packages-all-hosts)
  - [Upgrading Vault Version](#upgrading-vault-version)
  - [Upgrading k3s](#upgrading-k3s)
  - [Certificate Renewal](#certificate-renewal)
  - [Proxmox Host Updates](#proxmox-host-updates)
  - [Backup Verification](#backup-verification)
  - [Log Review](#log-review)
- [Monitoring Alert Reference](#monitoring-alert-reference)
- [Service Restart Commands Quick Reference](#service-restart-commands-quick-reference)

---

## Incident Response

### Power Outage Recovery

Full lab power loss. Everything is down. Follow this sequence exactly -- order matters because services have interdependencies.

**Prerequisites:** Power has stabilized and UPS is no longer on battery.

**Recovery sequence:**

1. **Wait for power to stabilize.** Do not rush. Give it 2-3 minutes after power returns.

2. **gw-01 comes up automatically.** Network routing, VLAN segmentation, DHCP, and firewall rules restore on boot. Verify by checking for network connectivity from any wired device.

3. **Proxmox hosts boot automatically.** Startup delay is configured in BIOS ("restore on AC power loss"). Give nodes 3-5 minutes to fully POST and start the Proxmox hypervisor.

4. **SSH to the Mac Mini VM (unseal vault host):**
   ```bash
   ssh admin@10.0.10.11
   ```

5. **Unseal the unseal vault:**
   ```bash
   VAULT_ADDR=https://127.0.0.1:8210 vault operator unseal <key>
   ```
   You need a single unseal key. This is the Transit unseal vault that auto-unseals the production cluster.

6. **Wait 30-60 seconds** for the production Vault nodes to auto-unseal via Transit. They will reach out to the unseal vault and unseal themselves automatically.

7. **Verify the Vault cluster is healthy.** Check all 3 nodes:
   ```bash
   for addr in 10.0.10.11 10.0.50.2 10.0.10.13; do
     echo "--- $addr ---"
     VAULT_ADDR=https://$addr:8200 vault status 2>&1 | grep -E 'Sealed|HA Mode|Version'
   done
   ```
   Expected: all nodes report `Sealed: false`. One node should show `HA Mode: active`, the other two `HA Mode: standby`.

8. **VMs and LXCs start automatically** based on Proxmox startup order configuration. Vault VMs have the highest priority (lowest start order number), followed by core infrastructure, then application services. Allow 5-10 minutes for everything to come up.

9. **Verify services are responding:**
   ```bash
   # Check key services from a management host
   curl -sk https://10.0.10.11:8200/v1/sys/health   # Vault primary
   curl -s http://<gitlab-ip>/users/sign_in | head -5    # GitLab
   kubectl get nodes                                      # k3s cluster
   kubectl get pods -A | grep -v Running                  # Any unhealthy pods
   ```

10. **Check Wazuh dashboard for alerts during downtime.** Log into the Wazuh web UI and review any alerts that fired during the power event. Filter by the outage time window. Most will be expected (service unavailable, agent disconnected) but look for anything anomalous.

**Estimated total recovery time:** 10-15 minutes from power restoration to all services healthy.

---

### Single Node Failure

One Proxmox node is down. The others are still running.

**Vault impact:**
- 2 of 3 nodes maintain Raft quorum. No action needed.
- Reads and writes continue normally against the active node.
- Verify quorum: `vault operator raft list-peers`

**Service impact:**
- VMs/LXCs hosted on the failed node are unavailable until the node recovers.
- No automatic migration -- services remain down on that node until it comes back.

**k3s impact (if applicable):**
- **Worker node failure:** Pods reschedule to remaining workers automatically (after the default `node-monitor-grace-period` of 40 seconds + `pod-eviction-timeout` of 5 minutes).
  ```bash
  kubectl get nodes                          # Identify NotReady node
  kubectl get pods -A -o wide | grep <node>  # See affected pods
  ```
- **Master node failure:** Remaining masters maintain etcd quorum (3-node cluster tolerates 1 failure). Control plane continues to function.
  ```bash
  kubectl get nodes
  kubectl get cs   # Component status
  ```

**Recovery:** When the node comes back online, VMs/LXCs auto-start per Proxmox config. Verify via the Proxmox web UI or:
```bash
pvesh get /nodes/<node-name>/qemu --output-format json | jq '.[].name'
pvesh get /nodes/<node-name>/lxc --output-format json | jq '.[].name'
```

---

### Network Outage (WireGuard Tunnel Down)

**Symptoms:** Public-facing services (Ghost blog, any HTTPS endpoints) are unreachable from the internet. Hetzner reverse proxy cannot route traffic to the homelab. Uptime Kuma fires tunnel-down alerts.

**Step 1 -- Check the Hetzner side:**
```bash
ssh root@<hetzner-ip>
wg show
```
Look for: `latest handshake` timestamp. If it is more than 2-3 minutes old, the tunnel is stale.

Check if the WireGuard interface is even up:
```bash
ip a show wg0
```

**Step 2 -- Check the homelab side:**
```bash
ssh admin@<dmz-wireguard-lxc-ip>
wg show
```
Same checks: verify the interface exists and the last handshake is recent.

**Step 3 -- Restart WireGuard on whichever side looks broken (or both):**
```bash
systemctl restart wg-quick@wg0
```

**Step 4 -- If the tunnel comes up but drops again, check for firewall drift:**
```bash
cd ~/repos/firblab/terraform/layers/00-network
terraform plan
```
If there is drift in the gw-01 firewall rules (port forwarding, WireGuard allow rules), apply to restore:
```bash
terraform apply
```

**Step 5 -- Verify end-to-end:**
```bash
# From outside the homelab (Hetzner or a remote machine)
curl -v https://yourdomain.com

# From inside the homelab, test tunnel connectivity
ping -c 3 <hetzner-wg-ip>
```

---

### Vault Sealed Alert (CRITICAL)

This is the highest-priority alert. A sealed Vault node cannot serve secrets, and if quorum is lost, the entire cluster goes read-only (and then down).

**Step 1 -- Identify which node(s) are sealed:**
```bash
for addr in 10.0.10.11 10.0.50.2 10.0.10.13; do
  echo "--- $addr ---"
  VAULT_ADDR=https://$addr:8200 vault status 2>&1 | grep Sealed
done
```

**Step 2 -- If only one node is sealed:**
- It should auto-unseal via Transit within a minute. Wait and re-check.
- If it does not auto-unseal, check if the unseal vault is reachable from that node:
  ```bash
  # From the sealed node
  curl -sk https://10.0.10.11:8210/v1/sys/health
  ```
- Check the Vault service logs on the sealed node:
  ```bash
  journalctl -u vault -f
  ```
- Restart the Vault service if logs show a recoverable error:
  ```bash
  systemctl restart vault
  ```

**Step 3 -- If the unseal vault itself is down:**
```bash
ssh admin@10.0.10.11
systemctl status vault-unseal
# If down, start it:
systemctl start vault-unseal
# Then unseal it:
VAULT_ADDR=https://127.0.0.1:8210 vault operator unseal <key>
```
Once the unseal vault is back, production nodes should auto-unseal within 30-60 seconds.

**Step 4 -- If a node crashed and cannot restart:**
```bash
# Check Vault logs
journalctl -u vault --no-pager -n 100

# Check disk space (Raft storage)
df -h /opt/vault/data

# Check Raft integrity
VAULT_ADDR=https://<active-node>:8200 vault operator raft list-peers
```
If a node is permanently lost from the Raft cluster, remove it:
```bash
VAULT_ADDR=https://<active-node>:8200 vault operator raft remove-peer <node-id>
```
Then reprovision via Ansible and rejoin.

**Step 5 -- If all 3 nodes are sealed (power outage scenario):**
Follow the [Power Outage Recovery](#power-outage-recovery) procedure above. The unseal vault must come up first.

**Step 6 -- Verify cluster health after recovery:**
```bash
VAULT_ADDR=https://10.0.10.11:8200 vault operator raft list-peers
VAULT_ADDR=https://10.0.10.11:8200 vault status
```
Confirm 3 peers, 1 leader, 2 followers, all unsealed.

---

### GitLab Down

**Impact:** CI/CD pipelines paused. Git push/pull unavailable. Running services are unaffected (they do not depend on GitLab at runtime).

**Step 1 -- SSH to the GitLab VM:**
```bash
ssh admin@<gitlab-ip>
```

**Step 2 -- Check GitLab component status:**
```bash
sudo gitlab-ctl status
```
All components should show `run`. If any show `down`, note which ones.

**Step 3 -- Restart GitLab:**
```bash
sudo gitlab-ctl restart
```
This gracefully restarts all components. Wait 2-3 minutes for full startup.

**Step 4 -- Check logs if restart does not resolve:**
```bash
# Tail all logs
sudo gitlab-ctl tail

# Or target specific components
sudo gitlab-ctl tail postgresql
sudo gitlab-ctl tail puma
sudo gitlab-ctl tail sidekiq
```

**Step 5 -- If the VM itself is down:**
- Check Proxmox web UI for the VM status.
- Start the VM manually from Proxmox UI or CLI:
  ```bash
  # From the Proxmox host
  qm start <vmid>
  ```
- Once the VM boots, GitLab services should auto-start. Verify with `gitlab-ctl status`.

**Step 6 -- If GitLab is up but slow or erroring:**
```bash
# Check resource usage
free -h
df -h
top -bn1 | head -20

# Check PostgreSQL
sudo gitlab-psql -c "SELECT pg_is_in_recovery();"
```

---

### k3s Cluster Issues

#### Pods Stuck in Pending

Pods in `Pending` state means the scheduler cannot place them.

**Step 1 -- Check node resources:**
```bash
kubectl describe nodes | grep -A5 "Allocated resources"
```
If CPU or memory requests exceed capacity, you need to free up resources or add a node.

**Step 2 -- Check PersistentVolume availability:**
```bash
kubectl get pv
kubectl get pvc -A | grep -v Bound
```
Unbound PVCs mean storage is unavailable. Check the storage provisioner.

**Step 3 -- Check events for the specific pod:**
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```
Events will tell you exactly why scheduling failed (insufficient resources, node affinity mismatch, taints, etc.).

#### Node NotReady

**Step 1 -- Identify the problem node:**
```bash
kubectl get nodes
```

**Step 2 -- SSH to the node and check kubelet:**
```bash
# On a server (master) node:
systemctl status k3s

# On an agent (worker) node:
systemctl status k3s-agent
```

**Step 3 -- Check logs:**
```bash
# Server node:
journalctl -u k3s -f

# Agent node:
journalctl -u k3s-agent -f
```
Common causes: certificate expiry, disk pressure, memory pressure, kubelet crash loop.

**Step 4 -- Restart k3s:**
```bash
# Server:
systemctl restart k3s

# Agent:
systemctl restart k3s-agent
```

**Step 5 -- If restart does not fix it, drain and rejoin:**
```bash
# From a working node with kubectl access
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <node-name>

# Then re-run the k3s deploy playbook to rejoin the node
ansible-playbook ansible/playbooks/k3s-deploy.yml -l <node-name>
```

#### ArgoCD Out of Sync

**Step 1 -- Check application status:**
```bash
argocd app list
# Or via kubectl:
kubectl get applications -n argocd
```

**Step 2 -- Inspect the diff:**
```bash
argocd app diff <app-name>
```

**Step 3 -- Manual sync if the diff looks correct:**
```bash
argocd app sync <app-name>
```

**Step 4 -- If sync fails, check for root cause:**
```bash
argocd app get <app-name>
# Check events:
kubectl describe application <app-name> -n argocd
```

**Common causes:**
- **Secret not available:** Check External Secrets Operator logs:
  ```bash
  kubectl logs -n external-secrets deploy/external-secrets -f
  kubectl get externalsecrets -A
  ```
- **Image pull failure:** Check pod events for `ImagePullBackOff`.
- **Resource conflict:** Another controller or manual edit is fighting ArgoCD. Check for `OutOfSync` annotations.

---

## Proxmox Node Replacement (Hardware Swap)

A Proxmox node has permanently failed and must be replaced with new hardware. This procedure slots the replacement in with zero data loss -- everything is rebuilt from IaC (Terraform, Packer, Ansible). The only things not in code are Vault secrets (stored on the surviving Vault cluster) and git repos (stored on your local workstation).

**When to use this:** Hardware failure, planned decommission, or upgrading to new hardware. The old node is unreachable and will not come back.

**Time estimate:** 2-3 hours of command execution after Proxmox is installed.

**Prerequisites:**
- Replacement hardware with Proxmox VE installed
- Vault cluster healthy (at least 2 of 3 nodes up -- the failed node may host vault-2)
- Local workstation has all repos, SSH keys, and CLI tools
- Switch port configured as trunk for all VLANs

### Naming Convention

When replacing a node, the new machine gets its own name (e.g., `lab-02` replaces `lab-09`). Do NOT reuse the old name -- it creates confusion in logs, Vault secrets, and Ansible history.

### Phase 0: Assess Impact

Before touching anything, identify what was running on the dead node:

```bash
# What Terraform layers targeted this node?
grep -r "proxmox_node.*lab-XX" terraform/layers/*/variables.tf

# What VMs/LXCs were deployed on it?
grep -r "lab-XX" terraform/layers/*/terraform.tfstate 2>/dev/null | head -20

# What Ansible inventory references it?
grep -r "lab-XX\|192.168.XX.XX" ansible/inventory/

# Is vault-2 affected? (vault-2 runs on Proxmox)
vault operator raft list-peers
```

Document the list of affected services. Common scenarios:

| Dead Node Role | Affected Services |
|---|---|
| Pilot/staging (lab-09) | Layer 01 resources, Packer templates, vault-2 VM |
| Main compute (lab-01) | Layer 03 services (GitLab, Wazuh, Runner), Layer 04 (k3s), Layer 05 (standalone) |

### Phase 1: Prepare Replacement Hardware

**1.1 Install Proxmox VE**

Install Proxmox on the replacement hardware. Assign a static IP on Management VLAN 10 during installation.

```
Example: lab-02 at 10.0.10.2
```

**1.2 Generate SSH Key**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_lab-NEW -C "lab-NEW"
ssh-copy-id -i ~/.ssh/id_ed25519_lab-NEW.pub root@<new-ip>
```

**1.3 Network Migration (if needed)**

If the new node starts on a different subnet (DHCP), migrate it to Management VLAN 10:

```bash
./scripts/migrate-to-vlan.sh <old-ip> <target-ip> root ~/.ssh/id_ed25519_lab-NEW
```

Verify connectivity:

```bash
ssh -i ~/.ssh/id_ed25519_lab-NEW root@<target-ip> 'hostname && pvesh get /version'
```

**1.4 Clean Up Existing VMs (if repurposing an existing Proxmox node)**

If the replacement hardware already has Proxmox with existing VMs/LXCs, destroy them first:

```bash
# SSH to the node and list everything
ssh root@<new-ip>
qm list            # VMs
pct list            # LXCs

# Stop and destroy each one
qm stop <vmid> && qm destroy <vmid>
pct stop <ctid> && pct destroy <ctid>
```

Verify storage pools match expectations:

```bash
pvesm status
```

If the pool names differ from what Terraform expects (e.g., `vmdata` instead of `local-lvm`), note this -- you'll update the tfvars accordingly.

### Phase 2: Update Code References

All references to the old node must be updated. This is a search-and-replace across the codebase.

**2.1 Terraform Variable Defaults**

Update the default `proxmox_node` in each layer that targeted the old node:

```bash
# Files to check:
# terraform/layers/01-proxmox-base/variables.tf
# terraform/layers/02-vault-infra/variables.tf
# (Layer 03+ default to lab-01 -- only update if they targeted the dead node)
```

Change `default = "firblab-OLD"` to `default = "lab-NEW"` in each file.

**2.2 Terraform Environment Files**

Create a new tfvars file for the replacement node:

```bash
cp terraform/environments/firblab-OLD.tfvars terraform/environments/lab-NEW.tfvars
cp terraform/environments/firblab-OLD.tfvars.example terraform/environments/lab-NEW.tfvars.example
```

Edit `lab-NEW.tfvars`:
- Update `proxmox_api_url` to the new IP
- Update `proxmox_nodes` map (node name and IP)
- Update `ssh_public_key` to the new node's key
- Update storage pool names if different on the new hardware

**2.3 Delete Stale Terraform State**

The old node's resources are gone. State files referencing destroyed infrastructure must be removed:

```bash
# Delete state for layers that targeted the dead node
rm -f terraform/layers/01-proxmox-base/terraform.tfstate*
rm -f terraform/layers/02-vault-infra/terraform.tfstate*
rm -f terraform/layers/03-core-infra/terraform.tfstate*
rm -f terraform/layers/03-gitlab-config/terraform.tfstate*
```

These layers will be re-applied fresh against the new node.

**2.4 Ansible Inventory**

Update `ansible/inventory/hosts.yml` -- replace the old node entry:

```yaml
proxmox_nodes:
  hosts:
    lab-NEW:
      ansible_host: <new-ip>
      ansible_user: admin
      ansible_ssh_private_key_file: ~/.ssh/id_ed25519_lab-NEW
      proxmox_node_name: lab-NEW
```

**2.5 Packer Template Defaults**

Update default `proxmox_node` in Packer templates (or just pass it as an argument):

```bash
# packer/ubuntu-24.04/ubuntu-24.04-base.pkr.hcl
# packer/rocky-9/rocky-9-base.pkr.hcl
```

**2.6 Scripts**

Update default node in `scripts/packer-build.sh`:

```bash
NODE="${1:-lab-NEW}"
```

### Phase 3: Bootstrap the New Node

**3.1 Ansible Bootstrap**

```bash
ansible-playbook ansible/playbooks/proxmox-bootstrap.yml -l lab-NEW
```

This creates the admin user, deploys SSH keys, configures VLAN-aware bridging, and hardens SSH.

**3.2 Enable Snippets Storage**

Verify (or enable) the `snippets` content type on the `local` storage:

```bash
ssh admin@<new-ip> 'sudo pvesm set local --content images,iso,vztmpl,backup,snippets'
```

**3.3 Create Terraform API Token**

```bash
ansible-playbook ansible/playbooks/proxmox-api-setup.yml --limit lab-NEW
```

Save the token output.

**3.4 Store Credentials in Vault**

```bash
vault kv put secret/infra/proxmox/lab-NEW \
  url="https://<new-ip>:8006" \
  token_id="terraform@pam!terraform-token" \
  token_secret="<token-from-step-3.3>"
```

### Phase 4: Rebuild Infrastructure Layers

Execute the layers in order. Each step depends on the previous one.

**4.1 Layer 01: Proxmox Base (ISOs, cloud images, templates)**

```bash
ssh-add ~/.ssh/id_ed25519_lab-NEW

cd terraform/layers/01-proxmox-base
terraform init
terraform apply -var-file=../../environments/lab-NEW.tfvars
```

**4.2 Packer Templates**

```bash
./scripts/packer-build.sh lab-NEW ubuntu-24.04
./scripts/packer-build.sh lab-NEW rocky-9
```

Verify templates exist as VM 9000 and 9001 in the Proxmox UI.

**4.3 Layer 02-vault-infra: Rebuild vault-2 (if affected)**

Only needed if the dead node hosted vault-2:

```bash
cd terraform/layers/02-vault-infra
terraform init
terraform apply -var proxmox_node=lab-NEW
```

Then deploy Vault and rejoin the Raft cluster:

```bash
ansible-playbook ansible/playbooks/vault-deploy.yml --limit vault-2

# Rejoin Raft (vault-1 on Mac Mini is still leader)
ssh admin@10.0.50.2 'VAULT_ADDR=https://127.0.0.1:8200 vault operator raft join https://10.0.10.10:8200'

# Verify
vault operator raft list-peers
```

**4.4 Layer 03-core-infra: GitLab, Runner, Wazuh**

```bash
cd terraform/layers/03-core-infra
terraform init
terraform apply -var proxmox_node=lab-NEW
```

Then configure via Ansible:

```bash
ansible-playbook ansible/playbooks/gitlab-deploy.yml
```

**4.5 Generate GitLab PAT and Store in Vault**

```bash
bash scripts/generate-gitlab-token.sh <gitlab-ip>

vault kv put secret/services/gitlab/admin \
  personal_access_token="glpat-xxxx" \
  root_password="xxxx"
```

**4.6 Layer 03-gitlab-config: Restore GitLab Configuration**

```bash
cd terraform/layers/03-gitlab-config
terraform init
terraform apply
```

This recreates all groups, projects, labels, and branch protections.

**4.7 Push Repos**

```bash
export GITLAB_TOKEN=$(vault kv get -field=personal_access_token secret/services/gitlab/admin)
bash scripts/push-repos-to-gitlab.sh
```

**4.8 Re-apply Branch Protections**

```bash
cd terraform/layers/03-gitlab-config
terraform apply
```

### Phase 5: Verify

```bash
# Proxmox node is healthy
ssh admin@<new-ip> 'pvesh get /version && pvesm status'

# Vault cluster has 3 peers (if vault-2 was rebuilt)
vault operator raft list-peers

# GitLab is accessible
curl -s -o /dev/null -w "%{http_code}" http://<gitlab-ip>/

# All repos are present
curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "http://<gitlab-ip>/api/v4/projects?per_page=100" | jq '.[].path_with_namespace'

# Branch protections are in place
cd terraform/layers/03-gitlab-config
terraform plan    # Should show "No changes"
```

### Phase 6: Update Documentation

After the replacement is verified:

- Update `docs/DEPLOYMENT.md` hardware table
- Update `docs/ARCHITECTURE.md` if node roles changed
- Update `README.md` hardware references
- Commit all code changes

### Reference: Files to Update for Node Replacement

| Category | Files | What to Change |
|---|---|---|
| Terraform defaults | `terraform/layers/01-proxmox-base/variables.tf` | `proxmox_node` default |
| | `terraform/layers/02-vault-infra/variables.tf` | `proxmox_node` default |
| Terraform envs | `terraform/environments/lab-NEW.tfvars` | Create from old, update IPs/keys/pools |
| | `terraform/environments/lab-NEW.tfvars.example` | Create from old, update examples |
| Terraform state | `terraform/layers/01-proxmox-base/terraform.tfstate*` | Delete (rebuild from scratch) |
| | `terraform/layers/02-vault-infra/terraform.tfstate*` | Delete (rebuild from scratch) |
| | `terraform/layers/03-core-infra/terraform.tfstate*` | Delete (rebuild from scratch) |
| | `terraform/layers/03-gitlab-config/terraform.tfstate*` | Delete (rebuild from scratch) |
| Ansible | `ansible/inventory/hosts.yml` | Replace old node entry |
| Packer | `packer/ubuntu-24.04/ubuntu-24.04-base.pkr.hcl` | `proxmox_node` default (optional) |
| | `packer/rocky-9/rocky-9-base.pkr.hcl` | `proxmox_node` default (optional) |
| Scripts | `scripts/packer-build.sh` | Default node (optional) |
| Vault | `secret/infra/proxmox/lab-NEW` | Store new node credentials |
| Docs | `docs/DEPLOYMENT.md`, `README.md` | Update hardware table, phase references |

---

## Routine Maintenance

### Updating Ubuntu Packages (All Hosts)

Run the hardening/update playbook against all managed hosts:
```bash
ansible-playbook ansible/playbooks/harden.yml --tags updates -l all
```

For a specific host only:
```bash
ansible-playbook ansible/playbooks/harden.yml --tags updates -l lab-01
```

After updates, check if any hosts require a reboot:
```bash
ansible all -m shell -a "[ -f /var/run/reboot-required ] && echo REBOOT_NEEDED || echo OK"
```

If reboots are needed, schedule them during a maintenance window and reboot one node at a time.

---

### Upgrading Vault Version

This is a rolling upgrade. Standbys first, then the leader.

**Step 1 -- Update the version variable:**

Edit `terraform/layers/02-vault/variables.tf` and change `vault_version` to the target version.

**Step 2 -- Upgrade standby nodes first:**
```bash
ansible-playbook ansible/playbooks/vault-deploy.yml -l vault_standbys --tags upgrade
```
After each standby comes back, verify it rejoined the cluster:
```bash
VAULT_ADDR=https://<standby-addr>:8200 vault status
```

**Step 3 -- Step down the current leader:**
```bash
VAULT_ADDR=https://<leader-addr>:8200 vault operator step-down
```
One of the upgraded standbys will become the new leader.

**Step 4 -- Upgrade the old leader (now a standby):**
```bash
ansible-playbook ansible/playbooks/vault-deploy.yml -l vault_leader --tags upgrade
```

**Step 5 -- Verify the entire cluster:**
```bash
for addr in 10.0.10.11 10.0.50.2 10.0.10.13; do
  echo "--- $addr ---"
  VAULT_ADDR=https://$addr:8200 vault status 2>&1 | grep -E 'Version|Sealed|HA Mode'
done
```
All nodes should report the new version, `Sealed: false`, and proper HA roles.

---

### Upgrading k3s

**Step 1 -- Update `k3s_version`** in the relevant Terraform or Ansible variable file.

**Step 2 -- Run the k3s deploy playbook (handles rolling upgrade):**
```bash
ansible-playbook ansible/playbooks/k3s-deploy.yml
```
The playbook upgrades masters first (one at a time), then workers.

**Step 3 -- Verify:**
```bash
kubectl get nodes
```
All nodes should show the new version and `Ready` status.

```bash
kubectl get pods -A | grep -v Running | grep -v Completed
```
No pods should be in a crash or error state.

---

### Certificate Renewal

**Public certificates (Let's Encrypt via Traefik):**
- Fully automatic. Traefik handles ACME challenge and renewal.
- No action needed unless Traefik itself is down.
- Verify: `curl -vI https://yourdomain.com 2>&1 | grep "expire date"`

**Internal certificates (Vault PKI via cert-manager):**
- cert-manager watches certificate resources and auto-renews before expiry.
- Monitor cert-manager logs if renewal alerts fire:
  ```bash
  kubectl logs -n cert-manager deploy/cert-manager -f
  kubectl get certificates -A
  kubectl get certificaterequests -A
  ```

**Vault cluster TLS certificates:**
- If using manually provisioned certs, renew via the Ansible vault-deploy playbook:
  ```bash
  ansible-playbook ansible/playbooks/vault-deploy.yml --tags tls
  ```
- This regenerates certs and restarts Vault nodes in a rolling fashion.

---

### Proxmox Host Updates

**Important:** Do one node at a time. Ensure all critical VMs on the node can tolerate a brief downtime, or live-migrate them to another node first.

```bash
# SSH to the Proxmox host
ssh root@<proxmox-host-ip>

# Update packages
apt update && apt dist-upgrade -y

# Check if a reboot is required (kernel update)
[ -f /var/run/reboot-required ] && echo "REBOOT NEEDED" || echo "No reboot needed"

# If reboot needed:
reboot
```

After reboot, verify the node rejoined the Proxmox cluster:
```bash
pvecm status
```

Verify all VMs/LXCs on that node started correctly:
```bash
qm list
pct list
```

---

### Backup Verification

Monthly procedure to confirm Vault backups are valid and restorable.

**Step 1 -- Download the latest Vault snapshot from Hetzner S3:**
```bash
# Use your S3 CLI tool / rclone / aws-cli with the Hetzner endpoint
aws s3 cp s3://<bucket>/vault-snapshots/latest.snap.age ./snapshot.snap.age \
  --endpoint-url https://<hetzner-s3-endpoint>
```

**Step 2 -- Decrypt the snapshot:**
```bash
age -d -i <age-key-file> snapshot.snap.age > snapshot.snap
```

**Step 3 -- Spin up a temporary test Vault instance:**
```bash
vault server -dev -dev-listen-address=127.0.0.1:8299 &
export VAULT_ADDR=http://127.0.0.1:8299
```

**Step 4 -- Restore the snapshot:**
```bash
vault operator raft snapshot restore snapshot.snap
```

**Step 5 -- Verify secrets are accessible:**
```bash
vault kv list secret/
vault kv get secret/<some-known-key>
```

**Step 6 -- Tear down the test instance:**
```bash
kill %1   # Stop the background Vault process
rm -f snapshot.snap snapshot.snap.age
```

Log the verification result and date.

---

### Proxmox VM/LXC Restore Test

Semi-annual procedure to verify Proxmox backup integrity.

**Step 1 -- Identify a recent vzdump backup:**
```bash
ssh root@<proxmox-host> ls -lt /var/lib/vz/dump/ | head -5
```

**Step 2 -- Restore to a temporary VMID (use a high VMID to avoid conflicts):**
```bash
# For a VM backup:
qmrestore /var/lib/vz/dump/vzdump-qemu-<vmid>-<date>.vma.zst 9999

# For an LXC backup:
pct restore 9999 /var/lib/vz/dump/vzdump-lxc-<ctid>-<date>.tar.zst
```

**Step 3 -- Start the test VM/LXC and verify:**
```bash
qm start 9999   # or: pct start 9999
# SSH in and verify the service is functional
```

**Step 4 -- Clean up:**
```bash
qm stop 9999 && qm destroy 9999   # or: pct stop 9999 && pct destroy 9999
```

Log the verification result and date.

---

### GitLab Restore Test

Semi-annual procedure to verify GitLab backup integrity.

**Step 1 -- Copy the latest GitLab backup to a test LXC:**
```bash
scp admin@gitlab:/var/opt/gitlab/backups/*_gitlab_backup.tar admin@test-lxc:/tmp/
```

**Step 2 -- On the test LXC, install GitLab and restore:**
```bash
# Install the same GitLab version as production
sudo gitlab-backup restore BACKUP=<timestamp>
sudo gitlab-ctl reconfigure
```

**Step 3 -- Verify:**
- Log in to the test GitLab web UI.
- Confirm repos, CI/CD config, and user accounts are present.

**Step 4 -- Tear down the test LXC.**

Log the verification result and date.

---

### Log Review

Weekly review checklist.

**Wazuh dashboard:**
- Log into the Wazuh web UI.
- Review alerts from the past 7 days. Filter by severity (level 7+).
- Investigate any new rule triggers. Tune false positives if needed.
- Confirm all agents are connected: Agents > check for any disconnected.

**Vault audit log:**
- Look for unusual access patterns: unexpected auth methods, failed login attempts, access to sensitive paths.
  ```bash
  # On a Vault node
  journalctl -u vault --since "7 days ago" | grep "auth/" | head -50
  ```

**GitLab:**
- Check for failed pipelines: GitLab UI > CI/CD > Pipelines.
- Review user activity: Admin Area > Monitoring > Audit Events.

**Proxmox:**
- Check VM/LXC resource utilization trends via the Proxmox web UI (Datacenter > Summary).
- Look for VMs consistently near CPU or memory limits.
- Check storage pool usage:
  ```bash
  pvesm status
  ```

---

## Monitoring Alert Reference

| Alert | Severity | Source | Action |
|---|---|---|---|
| Vault node sealed | CRITICAL | Prometheus | Unseal immediately -- see [Vault Sealed Alert](#vault-sealed-alert-critical) |
| Vault leader change | WARNING | Prometheus | Investigate cause; usually benign (rolling upgrade, step-down). Verify new leader is healthy |
| Raft peer count < 3 | WARNING | Prometheus | Check the missing node. SSH to it, check `systemctl status vault`. Rejoin if needed |
| Host disk > 85% | WARNING | node_exporter | Identify large files: `du -sh /* \| sort -rh \| head -10`. Clean up logs, old images, snapshots |
| Host disk > 95% | CRITICAL | node_exporter | Immediate cleanup. Check `/var/log`, Docker images, Vault snapshots. Free space before services fail |
| k3s node NotReady | WARNING | kube-state-metrics | See [Node NotReady](#node-notready) procedure above |
| ArgoCD app degraded | WARNING | ArgoCD | See [ArgoCD Out of Sync](#argocd-out-of-sync) procedure above |
| Wazuh agent disconnected | WARNING | Wazuh Manager | SSH to the host, restart the agent: `systemctl restart wazuh-agent` |
| WireGuard tunnel down | CRITICAL | Uptime Kuma | See [Network Outage](#network-outage-wireguard-tunnel-down) procedure above |
| SSL cert expiring (<7d) | WARNING | Uptime Kuma / cert-manager | Check auto-renewal. For Traefik certs: restart Traefik. For cert-manager: check cert-manager logs |
| GitLab Runner offline | WARNING | GitLab | SSH to the runner host, restart: `gitlab-runner restart`. Check logs: `journalctl -u gitlab-runner -f` |
| Backup job failed | WARNING | Cron / systemd timer | Check the timer: `systemctl status vault-backup.timer`. Check logs: `journalctl -u vault-backup.service --since today` |

---

## Service Restart Commands Quick Reference

Quick-reference table. SSH to the listed node, then run the command.

| Service | Node | Restart Command |
|---|---|---|
| Vault | vault-1 / vault-2 / vault-3 | `systemctl restart vault` |
| Unseal Vault | vault-1 (Mac Mini VM) | `systemctl restart vault-unseal` |
| GitLab | GitLab VM | `sudo gitlab-ctl restart` |
| Wazuh Manager | Wazuh VM | `systemctl restart wazuh-manager` |
| Wazuh Agent | Any managed host | `systemctl restart wazuh-agent` |
| k3s server | k3s master node(s) | `systemctl restart k3s` |
| k3s agent | k3s worker node(s) | `systemctl restart k3s-agent` |
| Ghost | Ghost LXC | `cd /opt/ghost && docker compose restart` |
| Plex | Plex VM | `systemctl restart plexmediaserver` |
| FoundryVTT | FoundryVTT VM | `systemctl restart foundryvtt` |
| Traefik (Hetzner) | Hetzner VPS | `cd /opt/traefik && docker compose restart` |
| WireGuard | Hetzner VPS or DMZ LXC | `systemctl restart wg-quick@wg0` |
| ArgoCD | k3s cluster (via kubectl) | `kubectl rollout restart deploy/argocd-server -n argocd` |
| External Secrets | k3s cluster (via kubectl) | `kubectl rollout restart deploy/external-secrets -n external-secrets` |
| cert-manager | k3s cluster (via kubectl) | `kubectl rollout restart deploy/cert-manager -n cert-manager` |
