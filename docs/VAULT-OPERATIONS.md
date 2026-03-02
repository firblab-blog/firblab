# Vault Operations Runbook

This is the operations guide for the HashiCorp Vault HA cluster in the firblab homelab. Use this document for routine maintenance, incident response, and disaster recovery.

---

## Table of Contents

- [Cluster Overview](#cluster-overview)
- [Common Commands](#common-commands)
- [Unsealing](#unsealing)
- [Backup Procedures](#backup-procedures)
- [Restore Procedures](#restore-procedures)
- [Secret Rotation](#secret-rotation)
- [Raft Operations](#raft-operations)
- [PKI Operations](#pki-operations)
- [Monitoring and Alerts](#monitoring-and-alerts)
- [Troubleshooting](#troubleshooting)

---

## Cluster Overview

The Vault cluster is a 3-node Raft HA deployment spread across heterogeneous hardware. All inter-node communication uses TLS. Raft consensus requires a quorum of 2 of 3 nodes to elect a leader and process requests.

| Node    | Machine                  | Address              | Role                  |
| ------- | ------------------------ | -------------------- | --------------------- |
| vault-1 | Mac Mini M4 (native macOS LaunchDaemon) | 10.0.10.10:8200   | Voter (initial leader)|
| vault-2 | lab-01 (Proxmox VM)| 10.0.50.2:8200    | Voter                 |
| vault-3 | RPi5 CM5 (bare metal)   | 10.0.10.13:8200   | Voter                 |

**Cluster port:** 8201 (Raft replication and request forwarding)
**Quorum requirement:** 2 of 3 nodes must be healthy for the cluster to operate.
**TLS:** Required on all API listeners (8200) and cluster listeners (8201).

### Network Diagram (Logical)

```
                   +-----------------+
                   |    vault-1      |
                   | 10.0.10.10   |
                   | Mac Mini M4     |
                   +--------+--------+
                            |
              +-------------+-------------+
              |                           |
     +--------+--------+        +--------+--------+
     |    vault-2      |        |    vault-3      |
     | 10.0.50.2    |        | 10.0.10.13   |
     | Proxmox VM      |        | RPi5 CM5        |
     +-----------------+        +-----------------+
```

All three nodes form a full mesh for Raft replication over port 8201.

---

## Common Commands

Set the target Vault address before running any command:

```bash
export VAULT_ADDR=https://10.0.10.10:8200
```

### Cluster Health

```bash
# Check the status of the current node (sealed/unsealed, HA mode, leader address)
vault status

# List all Raft peers and their voter status
vault operator raft list-peers

# Check Raft autopilot health (server stability, leader info, voter status)
vault operator raft autopilot state
```

### Leadership

```bash
# Force the current leader to step down (triggers a new election)
vault operator step-down
```

### Secrets

```bash
# Read a secret from the KV v2 engine
vault kv get secret/infra/proxmox/lab-02

# Write or update a secret
vault kv put secret/path key=value

# List secrets at a path
vault kv list secret/infra/proxmox/

# Delete a secret (soft delete in KV v2; recoverable)
vault kv delete secret/path

# Permanently destroy a specific version
vault kv destroy -versions=1 secret/path
```

### Audit

```bash
# Enable file-based audit logging
vault audit enable file file_path=/var/log/vault/audit.log

# List active audit devices
vault audit list

# Disable an audit device (use with caution -- Vault blocks requests if all audit devices fail)
vault audit disable file/
```

### Tokens and Auth

```bash
# Look up the current token's details
vault token lookup

# Create a short-lived token for automation
vault token create -ttl=1h -policy=my-policy

# List enabled auth methods
vault auth list
```

---

## Unsealing

### Auto-Unseal (Normal Operation)

Under normal conditions, no manual unsealing is required. The production cluster is configured with transit auto-unseal. The mechanism works as follows:

1. A lightweight "unseal vault" instance runs natively on the Mac Mini at `https://10.0.10.10:8210`.
2. Each production Vault node's configuration contains a `seal "transit"` stanza pointing to this unseal vault.
3. When a production node starts (or restarts), it contacts the unseal vault to retrieve the master key encryption key via the transit engine.
4. The node decrypts its master key and completes the unseal process automatically.

**Verify auto-unseal is working after a node restart:**

```bash
# Wait 30-60 seconds after the node starts, then check
VAULT_ADDR=https://10.0.10.10:8200 vault status
```

The output should show `Sealed: false` and `Seal Type: transit`.

### Unseal Vault Recovery

The unseal vault itself uses Shamir's Secret Sharing with a 1/1 threshold (single key). It is **not** auto-unsealed. After a full power outage or Mac Mini restart, the unseal vault must be manually unsealed before the production cluster can recover.

**Recovery procedure after a full power outage:**

```bash
# Step 1: SSH to the Mac Mini
ssh admin@10.0.10.10

# Step 2: Check the unseal vault status
VAULT_ADDR=https://127.0.0.1:8210 vault status
```

If the output shows `Sealed: true`, proceed:

```bash
# Step 3: Unseal the unseal vault
VAULT_ADDR=https://127.0.0.1:8210 vault operator unseal <unseal-key>
```

```bash
# Step 4: Wait 30-60 seconds for production nodes to auto-unseal, then verify
for addr in 10.0.10.10 10.0.50.2 10.0.10.13; do
  echo "--- $addr ---"
  VAULT_ADDR=https://$addr:8200 vault status
  echo ""
done
```

All three nodes should report `Sealed: false`. If any node remains sealed after 60 seconds, see [Troubleshooting: Node Won't Unseal](#node-wont-unseal).

### Unseal Key Storage Locations

The unseal vault's Shamir key is stored in three independent locations:

| Copy     | Location                                              | Access                     |
| -------- | ----------------------------------------------------- | -------------------------- |
| Primary  | Password manager                                      | Digital, primary retrieval |
| Physical | Printed QR code in physical safe                      | Offline backup             |
| Encrypted| age-encrypted file on RPi5 (`/backups/vault/unseal-key.age`) | Decrypted with SOPS age key |

To decrypt the age-encrypted copy:

```bash
age -d -i ~/.config/sops/age/keys.txt /backups/vault/unseal-key.age
```

---

## Backup Procedures

### Automated Backup (scripts/vault-backup.sh)

Automated backups run as a cron job or systemd timer on vault-1. The script performs the following steps in order:

```bash
# 1. Take a Raft snapshot
vault operator raft snapshot save /tmp/vault-snapshot-$(date +%Y%m%d%H%M).snap

# 2. Encrypt the snapshot with age
age -r <public-key> -o /tmp/vault-snapshot-$(date +%Y%m%d%H%M).snap.age \
  /tmp/vault-snapshot-$(date +%Y%m%d%H%M).snap

# 3. Upload encrypted snapshot to Hetzner Object Storage (S3-compatible)
aws s3 cp \
  --endpoint-url https://nbg1.your-objectstorage.com \
  /tmp/vault-snapshot-$(date +%Y%m%d%H%M).snap.age \
  s3://firblab-vault-backups/

# 4. Copy encrypted snapshot to RPi5 local storage
scp /tmp/vault-snapshot-$(date +%Y%m%d%H%M).snap.age \
  vault-backup@10.0.10.13:/backups/vault/

# 5. Remove the unencrypted snapshot from disk immediately
rm /tmp/vault-snapshot-$(date +%Y%m%d%H%M).snap
```

**Retention policy:**
- Local copies on Mac Mini: cleaned up after transfer
- RPi5: 30 days
- Hetzner Object Storage: 90 days

### Manual Backup

Take a manual backup before any risky operation (upgrades, restore, configuration changes):

```bash
export VAULT_ADDR=https://10.0.10.10:8200
vault operator raft snapshot save /tmp/vault-manual-$(date +%Y%m%d).snap
```

Verify the snapshot file is non-empty:

```bash
ls -lh /tmp/vault-manual-*.snap
```

### Backup Schedule

| Copy         | Location                    | Frequency    | Retention |
| ------------ | --------------------------- | ------------ | --------- |
| Primary      | Mac Mini (Raft storage)     | Live         | Current   |
| Local backup | RPi5                        | Every 6 hours| 30 days   |
| Off-site     | Hetzner Object Storage      | Daily        | 90 days   |

### Verifying Backups

Periodically test that backups are valid and restorable:

```bash
# List recent backups on Hetzner
aws s3 ls \
  --endpoint-url https://nbg1.your-objectstorage.com \
  s3://firblab-vault-backups/ \
  | tail -5

# List recent backups on RPi5
ssh vault-backup@10.0.10.13 'ls -lht /backups/vault/*.snap.age | head -5'
```

---

## Restore Procedures

**IMPORTANT:** Always take a fresh backup before performing a restore, in case the restore snapshot is corrupted or outdated.

### Restore from Snapshot

Use this when you have an unencrypted `.snap` file:

```bash
export VAULT_ADDR=https://10.0.10.10:8200

# Take a safety backup first
vault operator raft snapshot save /tmp/vault-pre-restore-$(date +%Y%m%d%H%M).snap

# Restore from the target snapshot
vault operator raft snapshot restore /path/to/snapshot.snap
```

After the restore completes, verify the cluster:

```bash
vault status
vault operator raft list-peers
vault kv get secret/infra/proxmox/lab-02  # Spot-check a known secret
```

### Restore from Encrypted Backup

Use this when restoring from the RPi5 or Hetzner Object Storage:

```bash
# Download from Hetzner if needed
aws s3 cp \
  --endpoint-url https://nbg1.your-objectstorage.com \
  s3://firblab-vault-backups/vault-snapshot-YYYYMMDDHHMM.snap.age \
  /tmp/

# Or copy from RPi5
scp vault-backup@10.0.10.13:/backups/vault/vault-snapshot-YYYYMMDDHHMM.snap.age /tmp/

# Decrypt the snapshot
age -d -i ~/.config/sops/age/keys.txt /tmp/vault-snapshot-YYYYMMDDHHMM.snap.age > /tmp/vault-restore.snap

# Restore
export VAULT_ADDR=https://10.0.10.10:8200
vault operator raft snapshot restore /tmp/vault-restore.snap

# Clean up the decrypted snapshot from disk
rm /tmp/vault-restore.snap
```

### Full Cluster Rebuild

Use this procedure only when all 3 nodes are lost and no running cluster exists.

```bash
# Step 1: Provision new nodes using Terraform and Ansible
cd firblab/terraform/layers/02-vault
tofu apply
cd ../../..
ansible-playbook ansible/playbooks/vault-deploy.yml

# Step 2: Initialize Vault on the first node
export VAULT_ADDR=https://10.0.10.10:8200
vault operator init -key-shares=1 -key-threshold=1
```

**Save the unseal key and root token immediately.** Store them in the password manager and update all backup locations.

```bash
# Step 3: Unseal the first node
vault operator unseal <unseal-key>

# Step 4: Join the remaining nodes to the cluster
# On vault-2 and vault-3, Vault is already configured with retry_join.
# Starting the Vault service will cause them to join automatically.
# If they don't, manually join:
VAULT_ADDR=https://10.0.50.2:8200 vault operator raft join https://10.0.10.10:8200
VAULT_ADDR=https://10.0.10.13:8200 vault operator raft join https://10.0.10.10:8200

# Step 5: Restore from the most recent snapshot
vault operator raft snapshot restore /path/to/snapshot.snap

# Step 6: Verify the cluster
vault operator raft list-peers
vault status
```

After restoring, reconfigure the transit auto-unseal by redeploying the unseal vault and updating the seal stanza on all production nodes.

---

## Secret Rotation

### Rotating Infrastructure Credentials

When rotating credentials for infrastructure services, update the secret in Vault and then re-run the relevant Terraform layer to propagate the change.

```bash
export VAULT_ADDR=https://10.0.10.10:8200

# Proxmox API token
vault kv put secret/infra/proxmox/lab-02 \
  url=https://10.0.10.2:8006 \
  token_id=terraform@pam!terraform-token \
  token_secret=<new-secret>

# Hetzner API token
vault kv put secret/infra/hetzner/api token=<new-token>

# Cloudflare API token
vault kv put secret/infra/cloudflare/api token=<new-token> zone_id=<zone-id>
```

After updating any credential, re-run the Terraform layer that consumes it:

```bash
cd firblab/terraform/layers/<relevant-layer>
tofu plan   # Verify the change is picked up
tofu apply  # Apply the change
```

### Rotating Vault's Own TLS Certificates

Vault's listener and cluster TLS certificates must be rotated before expiry. Perform a rolling restart to avoid downtime.

```bash
# Step 1: Generate new certificates (via Vault PKI or manual process)
# Place the new cert, key, and CA bundle in the Ansible role's files directory
# or update the certificate source in the playbook variables.

# Step 2: Deploy new certificates to all 3 nodes
ansible-playbook ansible/playbooks/vault-deploy.yml --tags tls

# Step 3: Rolling restart -- standbys first, then leader
# Identify the current leader
vault operator raft list-peers

# Restart standby nodes one at a time, waiting for each to rejoin
ssh admin@<standby-1-ip> 'sudo systemctl restart vault'
# Wait for the node to rejoin and unseal
vault operator raft list-peers

ssh admin@<standby-2-ip> 'sudo systemctl restart vault'
# Wait for the node to rejoin and unseal
vault operator raft list-peers

# Step down the leader (triggers election to a standby), then restart it
vault operator step-down
ssh admin@<old-leader-ip> 'sudo systemctl restart vault'
# Wait for the node to rejoin and unseal
vault operator raft list-peers
```

Verify that all nodes report healthy status and the correct certificate after the rolling restart:

```bash
for addr in 10.0.10.10 10.0.50.2 10.0.10.13; do
  echo "--- $addr ---"
  openssl s_client -connect $addr:8200 -servername $addr </dev/null 2>/dev/null \
    | openssl x509 -noout -dates -subject
  echo ""
done
```

### Rotating the Vault Root Token

The root token should not be used day-to-day. If you need a new one:

```bash
# Generate a new root token using the unseal key
vault operator generate-root -init
vault operator generate-root -nonce=<nonce> <unseal-key>
vault operator generate-root -decode=<encoded-token> -otp=<otp>

# Revoke the old root token
vault token revoke <old-root-token>
```

---

## Raft Operations

### Checking Cluster Health

```bash
# List all Raft peers with their role, address, and voter status
vault operator raft list-peers

# Get detailed autopilot state (health, stability, redundancy zones)
vault operator raft autopilot state
```

Healthy output should show 3 voters, 1 leader, and 2 followers.

### Adding a New Raft Peer

```bash
# Step 1: Provision and configure the new node with Terraform and Ansible.
# Ensure the Vault configuration includes retry_join blocks pointing to existing peers.

# Step 2: Start the Vault service on the new node.
# With retry_join configured, the node will automatically discover and join the cluster.
ssh admin@<new-node-ip> 'sudo systemctl start vault'

# Step 3: Verify the new peer appears in the peer list
vault operator raft list-peers
```

If the node does not auto-join, manually trigger the join:

```bash
VAULT_ADDR=https://<new-node-ip>:8200 vault operator raft join https://10.0.10.10:8200
```

### Removing a Raft Peer

Use this when decommissioning a node or replacing failed hardware:

```bash
# Identify the node ID from the peer list
vault operator raft list-peers

# Remove the peer
vault operator raft remove-peer <node-id>

# Verify removal
vault operator raft list-peers
```

**Warning:** Removing a peer from a 3-node cluster reduces quorum tolerance to zero. If the remaining 2 nodes cannot both stay healthy, the cluster will lose quorum. Add a replacement node before or immediately after removal.

### Forcing a Raft Recovery

Use this only as a last resort when quorum is permanently lost (2+ nodes destroyed).

1. Stop Vault on the surviving node.
2. Create a `raft/peers.json` file in the Vault data directory with only the surviving node.
3. Start Vault. It will bootstrap a single-node cluster.
4. Restore from the latest snapshot.
5. Re-add the other nodes.

Refer to the [HashiCorp documentation on Raft recovery](https://developer.hashicorp.com/vault/docs/concepts/integrated-storage#manual-recovery-using-peersjson) for the exact `peers.json` format.

---

## PKI Operations

### Issuing an Internal TLS Certificate

Use the intermediate CA to issue short-lived certificates for internal services:

```bash
vault write pki/intermediate-ca/firblab/issue/server \
  common_name="service.example-lab.local" \
  ttl="24h"
```

The output contains the certificate, private key, and CA chain. Pass these to the service configuration.

For services managed by Ansible, the playbook should retrieve the certificate at deploy time rather than storing long-lived certs on disk.

### Listing Certificates

```bash
# List all issued certificate serial numbers
vault list pki/intermediate-ca/firblab/certs

# Read a specific certificate by serial
vault read pki/intermediate-ca/firblab/cert/<serial>
```

### Revoking a Certificate

```bash
vault write pki/intermediate-ca/firblab/revoke serial_number=<serial>
```

### Rotating the Intermediate CA

Perform this before the intermediate CA certificate expires. Old leaf certificates signed by the previous intermediate will continue to validate until their own expiry, as long as the old intermediate remains in the CA chain.

```bash
# Step 1: Generate a new intermediate CSR
vault write -format=json pki/intermediate-ca/firblab/intermediate/generate/internal \
  common_name="firblab Intermediate CA v2" \
  | jq -r '.data.csr' > intermediate_v2.csr

# Step 2: Sign the CSR with the root CA
vault write -format=json pki/root-ca/root/sign-intermediate \
  csr=@intermediate_v2.csr \
  format=pem_bundle \
  ttl="43800h" \
  | jq -r '.data.certificate' > intermediate_v2_signed.pem

# Step 3: Import the signed certificate back into the intermediate CA mount
vault write pki/intermediate-ca/firblab/intermediate/set-signed \
  certificate=@intermediate_v2_signed.pem

# Step 4: Verify the new intermediate
vault read pki/intermediate-ca/firblab/cert/ca
```

### Tidying Up Expired Certificates

```bash
vault write pki/intermediate-ca/firblab/tidy \
  tidy_cert_store=true \
  tidy_revoked_certs=true \
  safety_buffer="72h"
```

---

## Monitoring and Alerts

### Key Metrics

Monitor these metrics via the Vault telemetry endpoint or a Prometheus scrape:

| Metric                              | Expected Value | Severity if Wrong |
| ----------------------------------- | -------------- | ----------------- |
| `vault.core.unsealed`               | 1              | CRITICAL          |
| `vault.raft.leader`                 | 1 (on leader)  | CRITICAL          |
| `vault.raft.peers`                  | 3              | WARNING           |
| `vault.audit.log_request_failure`   | 0              | CRITICAL          |
| `vault.expire.num_leases`           | Track trend    | WARNING (if growing unbounded) |
| `vault.runtime.alloc_bytes`         | Track trend    | WARNING (memory pressure) |
| `vault.barrier.put` / `.get`        | Track latency  | WARNING (storage slowness) |

### Alert Rules

| Condition                  | Severity | Action                                      |
| -------------------------- | -------- | ------------------------------------------- |
| Any node sealed            | CRITICAL | Gotify push notification; check unseal vault|
| Leader change              | WARNING  | Investigate; usually self-resolving         |
| Raft peer count < 3        | WARNING  | Identify missing node; restore or re-add    |
| Audit log write failure    | CRITICAL | Vault will block all requests; fix immediately |
| Lease count growing fast   | WARNING  | Check for lease leaks in applications       |

### Manual Health Check

Run this to get a quick overview of the entire cluster:

```bash
echo "=== Cluster Status ==="
for addr in 10.0.10.10 10.0.50.2 10.0.10.13; do
  echo ""
  echo "--- $addr ---"
  VAULT_ADDR=https://$addr:8200 vault status 2>&1 | grep -E 'Sealed|HA Enabled|HA Cluster|HA Mode'
done

echo ""
echo "=== Raft Peers ==="
vault operator raft list-peers

echo ""
echo "=== Unseal Vault ==="
VAULT_ADDR=https://10.0.10.10:8210 vault status 2>&1 | grep -E 'Sealed|Initialized'
```

---

## Troubleshooting

### Node Won't Unseal

**Symptoms:** `vault status` shows `Sealed: true` on one or more production nodes after a restart.

**Diagnosis and resolution:**

```bash
# Step 1: Check the unseal vault on the Mac Mini
VAULT_ADDR=https://10.0.10.10:8210 vault status
```

If the unseal vault is sealed, unseal it first (see [Unseal Vault Recovery](#unseal-vault-recovery)).

```bash
# Step 2: Verify network connectivity from the affected node to the unseal vault
ssh admin@<affected-node-ip> 'curl -sk https://10.0.10.10:8210/v1/sys/health'
```

If the connection fails, check firewall rules and ensure port 8210 is open between the affected node and the Mac Mini.

```bash
# Step 3: Check Vault logs on the affected node for transit seal errors
ssh admin@<affected-node-ip> 'journalctl -u vault -n 50 --no-pager'
```

Look for errors containing `seal`, `transit`, or `unseal`. Common issues:
- **"permission denied"**: The transit token used by the seal stanza has expired or been revoked. Re-create the token on the unseal vault.
- **"connection refused"**: The unseal vault is down or the address is wrong. Verify the `seal "transit"` stanza in the node's Vault configuration.
- **"certificate signed by unknown authority"**: TLS trust issue. Ensure the node trusts the unseal vault's CA certificate.

```bash
# Step 4: If transit auto-unseal cannot be restored quickly, use manual unseal
# This requires the recovery keys (not the unseal vault's Shamir key)
vault operator unseal -migrate <recovery-key>
```

### Split Brain / No Leader

**Symptoms:** `vault status` on all nodes shows `HA Mode: standby` with no leader, or requests return `503 Service Unavailable`.

```bash
# Step 1: Check all node statuses
for addr in 10.0.10.10 10.0.50.2 10.0.10.13; do
  echo "--- $addr ---"
  VAULT_ADDR=https://$addr:8200 vault status 2>&1
  echo ""
done
```

```bash
# Step 2: Check Raft peer list from any responsive node
vault operator raft list-peers
```

If quorum is lost (2 or more nodes are unreachable):

1. **Recover the majority first.** Bring at least 2 of 3 nodes back online.
2. Do **not** force a single-node leader election unless you are certain the other nodes are permanently destroyed.
3. Once 2 nodes are healthy, Raft will automatically elect a leader.

If all 3 nodes are running but no leader is elected:

```bash
# Step 3: Check for clock skew between nodes
echo "--- 10.0.10.10 ---"
ssh admin@10.0.10.10 'date -u'
echo "--- 10.0.50.2 ---"
ssh admin@10.0.50.2 'date -u'
echo "--- 10.0.10.13 ---"
ssh admin@10.0.10.13 'date -u'
```

Significant clock skew can prevent Raft leader election. Synchronize clocks with NTP and restart Vault on all nodes.

```bash
# Step 4: As a last resort, step down on all nodes to force a fresh election
for addr in 10.0.10.10 10.0.50.2 10.0.10.13; do
  VAULT_ADDR=https://$addr:8200 vault operator step-down 2>/dev/null
done
```

### Storage Full

**Symptoms:** Vault logs show write errors or `no space left on device`. The Raft data directory is on a dedicated 20GB disk (scsi1 on the Proxmox VM).

```bash
# Step 1: Check disk usage on the affected node
ssh admin@<node-ip> 'df -h /opt/vault/data'
```

```bash
# Step 2: Take a snapshot and verify it succeeds
vault operator raft snapshot save /tmp/vault-emergency-$(date +%Y%m%d).snap
```

```bash
# Step 3: Remove old local snapshots if any exist
ssh admin@<node-ip> 'ls -lh /tmp/vault-snapshot-* /tmp/vault-manual-*'
ssh admin@<node-ip> 'rm -f /tmp/vault-snapshot-* /tmp/vault-manual-*'
```

```bash
# Step 4: Restart Vault to trigger Raft auto-compaction
ssh admin@<node-ip> 'sudo systemctl restart vault'
```

If the disk is still critically full after compaction:

```bash
# Step 5: Expand the disk via Proxmox (for vault-2)
# In Proxmox UI or CLI, increase the scsi1 disk size
# Then on the VM:
ssh admin@10.0.50.2 'sudo growpart /dev/sdb 1 && sudo resize2fs /dev/sdb1'
```

### Audit Device Failure

**Symptoms:** All Vault API requests return errors. Vault refuses to process requests when audit logging fails.

```bash
# Step 1: Check which audit devices are enabled
vault audit list

# Step 2: Check if the audit log path is writable
ssh admin@<node-ip> 'ls -la /var/log/vault/audit.log'
ssh admin@<node-ip> 'df -h /var/log/vault/'
```

```bash
# Step 3: If the log file or directory is full or inaccessible, fix the underlying issue
# Rotate or truncate the log
ssh admin@<node-ip> 'sudo truncate -s 0 /var/log/vault/audit.log'

# Or if disk is full, free space
ssh admin@<node-ip> 'sudo journalctl --vacuum-size=100M'
```

```bash
# Step 4: If the audit device cannot be recovered, disable and re-enable it
vault audit disable file/
vault audit enable file file_path=/var/log/vault/audit.log
```

### High Lease Count

**Symptoms:** `vault.expire.num_leases` metric is growing continuously, Vault becomes slow.

```bash
# Step 1: Count current leases
vault list sys/leases/lookup/

# Step 2: Identify which auth method or secret engine is creating the most leases
vault read sys/leases/count

# Step 3: Revoke leases from a specific path if needed
vault lease revoke -prefix auth/token/
```

Investigate the application generating excessive leases. Common causes include applications that create new tokens or dynamic secrets without revoking them.

### Node Replaced or Rebuilt

If a node's hardware is replaced or the VM is rebuilt:

```bash
# Step 1: Remove the old peer from the cluster
vault operator raft remove-peer <old-node-id>

# Step 2: Deploy the new node with Terraform and Ansible
# The new node will have retry_join configured and will auto-join

# Step 3: Verify the new node joined successfully
vault operator raft list-peers
```

---

## Version Upgrade Procedure

When upgrading Vault to a new version:

```bash
# Step 1: Read the upgrade guide for the target version
# Check for breaking changes, required state migrations, and minimum upgrade paths

# Step 2: Take a backup
vault operator raft snapshot save /tmp/vault-pre-upgrade-$(date +%Y%m%d).snap

# Step 3: Upgrade standbys first, one at a time
# On each standby node:
ssh admin@<standby-ip> 'sudo apt update && sudo apt install vault=<new-version>-1'
ssh admin@<standby-ip> 'sudo systemctl restart vault'
# Wait for the node to rejoin and unseal
vault operator raft list-peers

# Step 4: Step down the leader, then upgrade it
vault operator step-down
ssh admin@<old-leader-ip> 'sudo apt update && sudo apt install vault=<new-version>-1'
ssh admin@<old-leader-ip> 'sudo systemctl restart vault'

# Step 5: Verify the cluster
vault status
vault operator raft list-peers
vault operator raft autopilot state
```

---

## Quick Reference: Power Outage Recovery Checklist

Use this checklist when recovering from a complete power outage affecting all nodes.

```
[ ] 1. Verify all machines are powered on and network is up
[ ] 2. SSH to Mac Mini: ssh admin@10.0.10.10
[ ] 3. Check unseal vault: VAULT_ADDR=https://127.0.0.1:8210 vault status
[ ] 4. Unseal the unseal vault if sealed
[ ] 5. Wait 60 seconds for production nodes to auto-unseal
[ ] 6. Verify vault-1: VAULT_ADDR=https://10.0.10.10:8200 vault status
[ ] 7. Verify vault-2: VAULT_ADDR=https://10.0.50.2:8200 vault status
[ ] 8. Verify vault-3: VAULT_ADDR=https://10.0.10.13:8200 vault status
[ ] 9. Verify Raft peers: vault operator raft list-peers
[ ] 10. Spot-check a secret: vault kv get secret/infra/proxmox/lab-02
[ ] 11. Verify dependent services are reconnecting (Terraform, apps, etc.)
```
