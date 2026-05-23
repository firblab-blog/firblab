# drive_audit

Read-only Ansible role that surveys every physical drive in the homelab and emits Markdown + JSON reports covering what's actually on the hardware, what's actually being used, and whether it's healthy.

Built because the docs lie, the IaC describes intent, and only the running kernel knows what's really happening.

## What it collects

Per host (dispatched by OS):

**Linux** (Proxmox nodes, RPis, ZimaBlade, generic Debian/Ubuntu)
- `lsblk -J` block-device tree (model, serial, WWN, transport, rotational, mount, fstype)
- SMART data per physical disk:
  - SATA/SAS: `smartctl -ja` (full attribute table)
  - NVMe: `smartctl -ja -d nvme` **+** `nvme smart-log -o json` (catches fields smartctl misses)
- LVM: `pvs`/`vgs`/`lvs --reportformat json` — full PV/VG/LV/thin-pool topology
- ZFS (if present): `zpool list`, `zpool status`, `zfs list` with key properties (`recordsize`, `compression`, `atime`, `sync`, `dedup`)
- Mounts: `findmnt -J --real`
- Host TRIM hygiene:
  - `/etc/lvm/lvm.conf` `issue_discards` setting
  - `fstrim.timer` enabled/active state
  - `smartd.service` / `smartmontools.service` state
  - active `/etc/smartd.conf` lines

**Proxmox-only extras** (auto-added on `proxmox_nodes` hosts):
- `pveversion`, `pvesm status`
- Every VM (`qm config <vmid>`) and LXC (`pct config <vmid>`)
- Lets you cross-reference which guest disks live on which physical pool

**macOS** (Mac Mini)
- `system_profiler` SPHardware / SPNVMe / SPStorage JSON
- `diskutil list -plist` + `diskutil apfs list -plist`
- `fdesetup status` (FileVault)
- `smartctl` per disk if Homebrew smartmontools is installed

**TrueNAS**
- `midclt call disk.query` (canonical disk inventory)
- `midclt call pool.query`
- `midclt call smart.test.query` / `smart.test.results`
- `midclt call pool.scrub.query`
- `midclt call sharing.nfs.query`
- ZFS pool/dataset state via `zpool`/`zfs`

## Outputs

```
reports/drive-audit/
  <RUN_ID>/
    AGGREGATE.md            # cross-host roll-up + risk flags
    lab-01.md           # per-host pretty report
    lab-01.json         # per-host raw collected data
    lab-02.md
    ...
  latest -> <RUN_ID>        # symlink to most recent run
```

Reports are written to `$PWD/reports/drive-audit/` — run from the repo root so they land in `<repo>/reports/drive-audit/`. Add `reports/` to `.gitignore` (these contain serials).

## Usage

```bash
# Read-only audit of every physical host (safest first run)
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/drive-audit.yml

# Install missing diagnostics (smartmontools, nvme-cli) first
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/drive-audit.yml \
  -e audit_install_tools=true

# Just one host
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/drive-audit.yml \
  --limit lab-02

# Label a run (useful before/after changes)
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/drive-audit.yml \
  -e audit_run_id=pre-nvme-swap-2026-05
```

## Inventory targeting

Plays against the meta group `homelab_hardware` which fans out to: `proxmox_nodes`, `macmini`, `rpi`, `k3s_cluster`, `truenas`, `archive_appliance`. Excludes guest VMs/LXCs (their backing storage is captured on the host) and cloud hosts (Hetzner).

To add new hardware: just include the host's group as a child of `homelab_hardware` in `ansible/inventory/hosts.yml`.

## Variables

| Var | Default | Notes |
|-----|---------|-------|
| `audit_install_tools` | `false` | Install smartmontools / nvme-cli / zfsutils-linux if missing |
| `audit_output_root` | `$PWD/reports/drive-audit` | Where reports land |
| `audit_run_id` | UTC timestamp | Override to label runs |
| `audit_render_aggregate` | `true` | Render `AGGREGATE.md` after per-host runs |
| `audit_capture_configs` | `true` | Include active lvm.conf / smartd.conf snippets in JSON |
| `audit_command_timeout` | `60` | Per-command timeout (seconds) |

## Risk flags surfaced in AGGREGATE.md

The aggregate report automatically calls out:

- **High unsafe-shutdown ratio (>10% of power cycles)** — PLP / power-stability concern, especially relevant for drives holding Vault Raft, etcd, or Postgres WAL.
- **Wear > 80%** — NVMe `percentage_used` past the warning line.
- **Any media errors** — drive returning bad data.
- **Reallocated sectors on SATA** — silent disk degradation.
- **`issue_discards = 0`** on LVM — TRIM may not reach physical SSD/NVMe through LVM-thin.
- **`smartd` not running** — no proactive monitoring.
- **`smartctl` missing** — drive health is invisible.

## What it deliberately does NOT do

- Mutate any drive, pool, or config (read-only by design — even `audit_install_tools=true` only installs probe utilities)
- Run SMART self-tests (`smartctl -t short/long`) — those take real time and are better scheduled
- Touch the filesystem beyond reads
- Modify Proxmox / TrueNAS configuration

## How it's wired

- Lives in `firblab` (legacy repo) at `ansible/roles/drive_audit/`
- Symlinked into `firblab-v2/ansible/roles/drive_audit` and `firblab-v2/ansible/playbooks/drive-audit.yml` so the same role works from either repo
- Canonical hardware inventory is in `firblab/ansible/inventory/hosts.yml` — run from that repo root for now

## Troubleshooting

**`smartctl: command not found`** — re-run with `-e audit_install_tools=true`, or apt-install manually.

**`midclt: command not found` on TrueNAS** — confirms the host isn't actually TrueNAS Scale; rerun without the `truenas` group membership or switch dispatch.

**Permission denied on `/dev/...`** — your inventory user lacks sudo. The role uses `become: true` for all reads; check sudoers.

**Aggregate task fails with "audited_hosts is undefined"** — every per-host run failed (typically SSH or auth). Check the host run output.

**Reports under `~/Library/...` instead of repo `reports/`** — `audit_output_root` defaults to `$PWD/reports/drive-audit`, so run from the repo root, or override with `-e audit_output_root=...`.
