# Disaster Recovery Runbook

Last updated: 2026-02-20

## Service Dependency Tree

Recovery must follow this order. Each tier depends on all tiers above it.

> **Direct-access URLs for all services:** See [SERVICE-DIRECTORY.md](SERVICE-DIRECTORY.md) for proxy URLs, direct IP:port fallbacks, and `kubectl port-forward` commands when Traefik is down.

```
Tier 0: Physical Infrastructure (power, network)
  ├── gw-01 (inter-VLAN routing)
  ├── Switches (switch-01, switch-02, switch-03)
  └── UPS (CyberPower, closet rack only)

Tier 1: Hypervisors (Proxmox nodes)
  ├── lab-01 (main compute, RKE2 cluster)
  ├── lab-02 (GitLab, vault-2, Runner)
  ├── lab-03 (Ghost, FoundryVTT, Roundcube, Mealie, WireGuard)
  └── lab-04 (Authentik, NetBox, PatchMon, PBS)

Tier 1.5: Backup Infrastructure
  ├── PBS (10.0.10.15:8007, VM 5031 on lab-04) — VM/LXC full-image backups
  └── Backup LXC (10.0.10.18, LXC 5040 on lab-01) — Restic REST server :8500 + Backrest UI :9898
      └── hdd-mirror-0 ZFS bind-mounted at /mnt/restic (append-only, htpasswd, private-repos)

Tier 2: Secrets Management (Vault)
  ├── unseal Vault (Mac Mini :8210, Shamir) ← must be unsealed FIRST
  ├── vault-1 (Mac Mini :8200, primary)
  ├── vault-2 (VM on lab-02, VLAN 50)
  └── vault-3 (RPi5 CM5, VLAN 10)

Tier 3: Core Infrastructure
  ├── GitLab (repos, CI/CD)
  └── gitlab-runner (CI pipelines)

Tier 4: Platform Services (RKE2 Kubernetes)
  ├── RKE2 server nodes (3x, VLAN 20)
  ├── RKE2 agent nodes (3x, VLAN 20)
  ├── ArgoCD (GitOps controller)
  ├── Longhorn (persistent storage)
  ├── MetalLB + Traefik (networking)
  └── cert-manager + ESO (TLS + secrets)

Tier 5: Application Services
  ├── Standalone: Ghost, FoundryVTT, Roundcube, Mealie, NetBox
  ├── K8s: SonarQube, Grafana
  └── Network: Scanopy, NUT
```

## RPO/RTO Targets

| Service | RPO | RTO | Backup Method | Off-site |
|---------|-----|-----|---------------|----------|
| Vault secrets | 6 hours | 30 min | Raft snapshot + age + S3 | Hetzner S3 (30d) + RPi5 (30d) |
| GitLab (repos+DB) | 24 hours | 1 hour | gitlab-backup (Sun=full, Mon-Sat=incremental) + age + S3 | Hetzner S3 (30d) |
| Ghost blog | 24 hours | 15 min | **Dual:** Restic (01:00, hdd-mirror-0) + tar+age+S3 (03:30) | Hetzner S3 (30d) |
| Vaultwarden | 24 hours | 15 min | **Dual:** Restic (01:10, hdd-mirror-0) + tar+age+S3 (04:15) | Hetzner S3 (30d) |
| Mealie recipes | 24 hours | 15 min | **Dual:** Restic (01:20, hdd-mirror-0) + tar+age+S3 (04:00) | Hetzner S3 (30d) |
| Actual Budget | 24 hours | 15 min | **Dual:** Restic (01:30, hdd-mirror-0) + tar+age+S3 (04:30) | Hetzner S3 (30d) |
| FoundryVTT | 24 hours | 15 min | **Dual:** Restic (01:40, hdd-mirror-0) + tar+age+S3 (05:00) | Hetzner S3 (30d) |
| Roundcube | 24 hours | 15 min | **Dual:** Restic (01:50, pg_dump, hdd-mirror-0) + tar+age+S3 (05:15) | Hetzner S3 (30d) |
| Authentik (SSO) | 24 hours | 15 min | **Dual:** Restic (02:00, pg_dump, hdd-mirror-0) + tar+age+S3 (04:45) | Hetzner S3 (30d) |
| PatchMon | 24 hours | 15 min | **Dual:** Restic (02:10, pg_dump, hdd-mirror-0) + tar+age+S3 (03:30) | Hetzner S3 (30d) |
| Longhorn PVCs | 6 hours | 30 min | Local snapshots (6h, retain 12) | Local only (3-day window) |
| Proxmox VMs | 24 hours | 1 hour | PBS (daily, dedup, incremental) | PBS on lab-04 (keep-daily=7, weekly=4, monthly=3) |
| Terraform state | Per-apply | 15 min | CI post-apply + age + S3 | Hetzner S3 (age-encrypted) |
| Proxmox config | N/A | 2 hours | Proxmox cluster replication + docs | N/A |

**Restic retention:** 7 daily / 4 weekly / 3 monthly (local hdd-mirror-0). Weekly integrity check (Sundays).

**S3 cost strategy:** Only small, high-value, irreplaceable data goes to Hetzner S3 (~10-20 GB total). Bulk infrastructure backups (vzdump, Longhorn PVCs) stay local to avoid exceeding the 1TB flat-rate tier.

**S3 retention:** All backup buckets have server-side lifecycle policies (30-day expiration) managed via Terraform Layer 06 inline `lifecycle_rule` blocks. Script-based cleanup has been removed — Hetzner enforces expiration server-side.

## Power Topology

### UPS-Protected (Closet Rack)

CyberPower CP1500PFCLCDa — 1000W real power, ~38 min runtime at 21% load.

| Device | Switch Port | Role |
|--------|------------|------|
| lab-01 | Closet Port 1 | Main compute (RKE2 cluster) |
| TrueNAS | Closet Port 2 | Storage |
| lab-04 | Closet Port 3 | Lightweight compute (NetBox) |
| lab-08 | Closet Port 4 | NUT server + Scanopy |
| Closet switch | Port 5 (uplink) | switch-01 |

### Wall Power (Minilab) — NO UPS

| Device | Switch Port | Role |
|--------|------------|------|
| lab-03 | Minilab Port 1 | Lightweight services |
| JetKVM | Minilab Port 2 | KVM-over-IP |
| Mac Mini (vault-1) | Minilab Port 3 | Vault primary |
| lab-02 | Minilab Port 4 | GitLab, vault-2 |
| RPi5 (vault-3) | Minilab Port 5 | Vault standby |

## Shutdown Sequence (Power Outage)

### Coordinated UPS Shutdown (NUT)

When UPS battery hits LOWBATT (~10%):

1. **NUT master (lab-08)** detects LOWBATT → signals FSD to all secondary clients
2. **Secondary clients shut down first:**
   - lab-01 (RKE2 VMs drain, then Proxmox shuts down)
   - lab-04 (NetBox VM shuts down, then Proxmox)
3. **Master waits HOSTSYNC (15s)** for secondaries to disconnect
4. **Master (lab-08) shuts down** — NUT, Scanopy stop gracefully
5. **UPS cuts power** after FINALDELAY (5s)

### Minilab (Wall Power Loss)

Minilab devices hard-stop immediately on house power loss. This is acceptable because:
- **vault-1**: Raft replication across 3 nodes. vault-2 (lab-02) or vault-3 (RPi5) survive if they have power.
- **vault-3**: Same — Raft replication protects data.
- **lab-02** (GitLab): Daily backup to S3. RTO: restore from backup.
- **lab-03** (services): Docker volumes backed up daily to S3. RTO: restore from backup.

## Disaster Scenarios

### Scenario 1: Brief Power Outage (< 30 min)

**Impact:** UPS absorbs the outage. No shutdown occurs.

**Recovery:** None needed. Verify all services are operational after power returns.

### Scenario 2: Extended Power Outage (> 38 min)

**Impact:** UPS exhausted → NUT coordinated shutdown of closet rack. Minilab hard-stops.

**Recovery:**
1. Power returns → gw-01 boots first (auto)
2. Proxmox nodes boot (may need manual start via BIOS/IPMI)
3. VMs auto-start via Proxmox on-boot setting
4. Unseal Vault:
   ```bash
   # On Mac Mini (vault-1):
   # Unseal vault first (port 8210):
   vault operator unseal -address=https://127.0.0.1:8210

   # Primary cluster auto-unseals via transit
   # Verify: vault status -address=https://10.0.10.10:8200
   ```
5. Verify services: GitLab, ArgoCD, all standalone services
6. Check NUT: `upsc ups@10.0.4.20` — verify UPS is back on line power

### Scenario 3: Single Proxmox Node Failure

**Impact:** VMs on that node are down.

**Recovery:**
- If lab-01 (RKE2): K8s cluster degrades but survives (3 servers, need 2 for quorum). Agent workloads reschedule.
- If lab-02 (GitLab): Restore GitLab VM from PBS backup or rebuild from Terraform + Ansible.
- If lab-03 (services): Restore LXCs/VMs from PBS or rebuild from Terraform + Docker volume backups.
- If lab-04 (NetBox + PBS): Restore from PBS (if PBS survived) or rebuild from Terraform. PBS is a single point of failure on this node — rebuild via Packer template + `pbs-deploy.yml` + `proxmox-pbs-register.yml`.

### Scenario 4: Vault Cluster Failure

**Impact:** No new secrets can be read. Services with cached tokens continue working.

**Recovery (partial — 1 node):**
1. If 2+ nodes are healthy, Raft quorum is maintained — no action needed.
2. If leader fails, automatic leader election occurs.

**Recovery (total — all 3 nodes):**
1. Rebuild vault-1 (Mac Mini) — re-deploy via `ansible-playbook vault-deploy.yml`
2. Unseal the unseal Vault instance
3. Restore Raft snapshot:
   ```bash
   vault operator raft snapshot restore /path/to/vault-snapshot-YYYYMMDDHHMMSS.snap
   ```
4. Unseal primary vault → Raft leader election → cluster healthy
5. Rebuild vault-2 and vault-3, join to Raft cluster

### Scenario 5: GitLab Data Loss

**Backup strategy:** Weekly full backup (Sunday) + daily incremental backups (Mon–Sat).
Incremental backups are **independently restorable** — you do NOT need to apply a chain
of incrementals on top of a full backup. Use the timestamp of whichever backup you want
to restore (full or incremental), the restore command is the same.

**Recovery:**
1. Rebuild GitLab VM from Terraform Layer 03 + Ansible `gitlab-deploy.yml`
2. Restore from S3:
   ```bash
   # Download and decrypt
   aws s3 cp --endpoint-url https://<endpoint> \
     s3://firblab-gitlab-backups/<latest>_gitlab_backup.tar.age .
   aws s3 cp --endpoint-url https://<endpoint> \
     s3://firblab-gitlab-backups/gitlab-config-backup-<latest>.tar.age .

   age -d -i <age-private-key> -o backup.tar backup.tar.age
   age -d -i <age-private-key> -o config.tar config.tar.age

   # Restore config (MUST be done before application restore)
   tar xf config.tar -C /
   gitlab-ctl reconfigure

   # Restore application backup (works for both full and incremental)
   cp backup.tar /var/opt/gitlab/backups/
   gitlab-backup restore BACKUP=<timestamp>
   gitlab-ctl restart
   ```

### Scenario 6: Longhorn PVC Data Loss

**Recovery:**
1. In Longhorn UI or CLI, restore volume from latest S3 backup
2. Or restore from local snapshot (faster, if available)
3. Restart affected workload pod

### Scenario 7: Service Data Loss (Standalone Services)

**Preferred method: Restic restore from hdd-mirror-0 (fastest)**

```bash
# Set Restic credentials (from Vault: secret/backup/restic)
export RESTIC_REPOSITORY="rest:http://<node>:<htpasswd_pass>@10.0.10.18:8500/<node>/"
export RESTIC_PASSWORD="<repo_password>"

# List available snapshots
restic snapshots --tag <service>

# Restore latest snapshot to a temp directory (verify first!)
restic restore latest --tag <service> --target /tmp/restore-test
ls /tmp/restore-test/opt/<service>/

# Actual restore (after verification):
docker compose -f /opt/<service>/docker-compose.yml down
restic restore latest --tag <service> --target /
docker compose -f /opt/<service>/docker-compose.yml up -d

# For PostgreSQL services (Authentik, Roundcube, PatchMon):
# The pg_dump file is included in the snapshot
cat /tmp/restore-test/opt/<service>/<service>-dump.sql | \
  docker exec -i <db-container> psql -U <user> <dbname>
```

**Node-to-credential mapping:**
- lab-03 services (ghost, vaultwarden, mealie, actualbudget, foundryvtt, roundcube): user=lab-03
- lab-04 services (authentik, patchmon): user=lab-04

**Fallback method: S3 tar+age restore (if hdd-mirror-0 unavailable)**

1. Download encrypted backup from S3:
   ```bash
   aws s3 cp --endpoint-url https://<endpoint> \
     s3://firblab-service-backups/<hostname>/<service>-<timestamp>.tar.age .
   age -d -i <age-private-key> -o backup.tar backup.tar.age
   ```
2. Stop service: `docker compose -f /opt/<service>/docker-compose.yml down`
3. Restore data: `tar xf backup.tar -C /`
4. Start service: `docker compose -f /opt/<service>/docker-compose.yml up -d`

### Scenario 8: PBS Failure

**Impact:** No new VM/LXC backups. Existing data on PBS data disk may be lost if disk fails.

**Recovery:**
1. Rebuild PBS VM from Terraform Layer 05:
   ```bash
   cd terraform/layers/05-standalone-services && terraform apply
   ```
2. Configure PBS:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/pbs-deploy.yml
   ```
3. Re-register PBS on all PVE nodes:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/proxmox-pbs-register.yml
   ```
4. Verify backups resume: PBS UI at `https://10.0.10.15:8007`

**Note:** PBS is a single point of failure for VM/LXC full-image backups. Application-level backups have dual pipelines: Restic (local, hdd-mirror-0 on lab-01) + tar+age (off-site, Hetzner S3). A service can be restored from either pipeline independently.

## Backup Verification

### Monthly Checks
- [ ] Vault: Verify S3 backup exists and is recent (`aws s3 ls s3://firblab-vault-backups/`)
- [ ] Vault: Verify RPi5 local backup exists (`ssh vault-backup@10.0.10.13 ls /backups/vault/`)
- [ ] GitLab: Verify S3 backup exists (`aws s3 ls s3://firblab-gitlab-backups/`)
- [ ] Longhorn: Verify local snapshots exist (Longhorn UI → Volumes → each volume)
- [ ] Docker volumes: Verify S3 backups exist (`aws s3 ls s3://firblab-service-backups/`)
- [ ] PBS: Verify backups exist for all nodes (PBS UI at `https://10.0.10.15:8007`)
- [ ] Restic: Visual check via Backrest UI (SSH tunnel: `ssh -L 9898:127.0.0.1:9898 root@10.0.10.18`, then open `http://localhost:9898`)
- [ ] Restic: Verify snapshots exist for all services (CLI):
  ```bash
  export RESTIC_PASSWORD="<repo_password>"
  for node in lab-03 lab-04; do
    restic -r "rest:http://${node}:<pass>@10.0.10.18:8500/${node}/" snapshots
  done
  ```
- [ ] Restic: Verify integrity (automatic weekly, but manual check):
  ```bash
  restic -r "rest:http://lab-03:<pass>@10.0.10.18:8500/lab-03/" check
  ```

### Quarterly Restore Drill
- [ ] Restore a Vault snapshot to a test instance
- [ ] Restore a GitLab backup to a test VM
- [ ] Restore a Longhorn PVC from S3 backup
- [ ] Restore a service from Restic (fastest path):
  ```bash
  restic -r "rest:http://lab-03:<pass>@10.0.10.18:8500/lab-03/" \
    restore latest --tag ghost --target /tmp/ghost-restore-test
  ls /tmp/ghost-restore-test/opt/ghost/data/   # Verify files exist
  rm -rf /tmp/ghost-restore-test
  ```
- [ ] Restore a service from S3 tar+age (fallback path)

## Encryption Keys

All backups are encrypted with age. The age keypair is stored in:
- **Vault:** `secret/backup/age-key` (public_key + private_key)
- **Password manager:** Backup copy of the private key

**CRITICAL:** Without the age private key, encrypted backups are unrecoverable. Ensure the private key exists in at least 2 independent locations.

## S3 Buckets

| Bucket | Contents | Retention |
|--------|----------|-----------|
| `firblab-vault-backups` | Vault Raft snapshots (age-encrypted) | 90 days |
| `firblab-gitlab-backups` | GitLab application + config backups | 30 days |
| `firblab-longhorn-backups` | Longhorn PVC backups | 7 daily |
| `firblab-service-backups` | Docker volume backups (by hostname) | 30 days |
| `firblab-proxmox-backups` | **Unused** (replaced by PBS, kept for potential future re-enable) | — |
| `firblab-tfstate-backups` | Terraform state files (by layer) | Per-apply |

## NUT Configuration

| Host | Mode | Role | Action on LOWBATT |
|------|------|------|-------------------|
| lab-08 | netserver (primary) | Master | Signals FSD, shuts down last |
| lab-01 | netclient (secondary) | Slave | Shuts down on FSD signal |
| lab-04 | netclient (secondary) | Slave | Shuts down on FSD signal |

**NUT Server:** `10.0.4.20:3493`
**UPS Name:** `ups`
**Secrets:** `vault kv get -mount=secret services/nut`
