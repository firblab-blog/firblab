#!/usr/bin/env bash
# =============================================================================
# attach-passthrough-disks.sh — Physical Disk Passthrough to Proxmox VM
# =============================================================================
# Called by terraform_data.pbs_disk_passthrough in Layer 05.
# SSHs to the Proxmox host and uses `qm set` to attach physical disks
# directly to the VM as scsi1, scsi2, etc.
#
# Required environment variables (set by Terraform local-exec):
#   PROXMOX_HOST    — Proxmox node IP (e.g., 10.0.10.4)
#   PROXMOX_USER    — SSH user for Proxmox node (e.g., admin)
#   PROXMOX_SSH_KEY — SSH private key path for Proxmox node
#   VM_ID           — Proxmox VM ID (e.g., 5031)
#   DISK_LIST       — Comma-separated /dev/disk/by-id/ paths
#                      (e.g., "ata-WDC_WD161...,ata-ST16000...")
# =============================================================================
set -euo pipefail

# Validate required vars
for var in PROXMOX_HOST PROXMOX_USER PROXMOX_SSH_KEY VM_ID DISK_LIST; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Required environment variable $var is not set" >&2
    exit 1
  fi
done

# Parse disk list
IFS=',' read -ra DISKS <<< "$DISK_LIST"
if [[ ${#DISKS[@]} -eq 0 ]]; then
  echo "ERROR: DISK_LIST is empty" >&2
  exit 1
fi

echo "[VM ${VM_ID}] Attaching ${#DISKS[@]} passthrough disk(s)..."
for i in "${!DISKS[@]}"; do
  echo "  scsi$((i + 1)): /dev/disk/by-id/${DISKS[$i]}"
done

# SSH options — use specific key with IdentitiesOnly to prevent fail2ban bans
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
SSH_OPTS="${SSH_OPTS} -i ${PROXMOX_SSH_KEY} -o IdentitiesOnly=yes"
PROXMOX_SSH="${PROXMOX_USER}@${PROXMOX_HOST}"

# qm lives in /usr/sbin which isn't in non-root PATH on Proxmox.
# admin user requires sudo to run qm commands.
QM="sudo /usr/sbin/qm"

# ---------------------------------------------------------------------------
# Step 1: Check current VM status
# ---------------------------------------------------------------------------
echo "[VM ${VM_ID}] Checking VM status..."
# shellcheck disable=SC2086
VM_STATUS=$(ssh $SSH_OPTS "$PROXMOX_SSH" "${QM} status ${VM_ID}" 2>&1)
echo "[VM ${VM_ID}] Current status: ${VM_STATUS}"

# ---------------------------------------------------------------------------
# Step 2: Stop VM if running (qm set for passthrough requires VM to be stopped)
# ---------------------------------------------------------------------------
VM_WAS_RUNNING=false
if echo "$VM_STATUS" | grep -q "running"; then
  echo "[VM ${VM_ID}] Stopping VM for disk attachment..."
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "$PROXMOX_SSH" "${QM} shutdown ${VM_ID} --timeout 60" 2>&1 || true

  # Wait for VM to actually stop
  for i in $(seq 1 30); do
    # shellcheck disable=SC2086
    STATUS=$(ssh $SSH_OPTS "$PROXMOX_SSH" "${QM} status ${VM_ID}" 2>&1)
    if echo "$STATUS" | grep -q "stopped"; then
      echo "[VM ${VM_ID}] VM stopped (attempt ${i})"
      break
    fi
    if [[ $i -eq 30 ]]; then
      echo "[VM ${VM_ID}] VM didn't stop gracefully, forcing..."
      # shellcheck disable=SC2086
      ssh $SSH_OPTS "$PROXMOX_SSH" "${QM} stop ${VM_ID}" 2>&1
      sleep 3
    fi
    sleep 2
  done
  VM_WAS_RUNNING=true
fi

# ---------------------------------------------------------------------------
# Step 3: Attach each disk via qm set
# ---------------------------------------------------------------------------
for i in "${!DISKS[@]}"; do
  SCSI_INDEX=$((i + 1))  # scsi0 is OS disk, passthrough starts at scsi1
  DISK_PATH="/dev/disk/by-id/${DISKS[$i]}"

  echo "[VM ${VM_ID}] Attaching ${DISK_PATH} as scsi${SCSI_INDEX}..."
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "$PROXMOX_SSH" "${QM} set ${VM_ID} --scsi${SCSI_INDEX} ${DISK_PATH}"
  echo "[VM ${VM_ID}] scsi${SCSI_INDEX} attached successfully"
done

# ---------------------------------------------------------------------------
# Step 4: Start VM
# ---------------------------------------------------------------------------
echo "[VM ${VM_ID}] Starting VM..."
# shellcheck disable=SC2086
ssh $SSH_OPTS "$PROXMOX_SSH" "${QM} start ${VM_ID}"

# ---------------------------------------------------------------------------
# Step 5: Wait for QEMU guest agent to respond (confirms VM is fully booted)
# ---------------------------------------------------------------------------
echo "[VM ${VM_ID}] Waiting for QEMU guest agent..."
AGENT_READY=false
for i in $(seq 1 60); do
  # shellcheck disable=SC2086
  if ssh $SSH_OPTS "$PROXMOX_SSH" "${QM} guest cmd ${VM_ID} ping" >/dev/null 2>&1; then
    echo "[VM ${VM_ID}] Guest agent responding (attempt ${i})"
    AGENT_READY=true
    break
  fi
  sleep 2
done

if [[ "$AGENT_READY" != "true" ]]; then
  echo "ERROR: [VM ${VM_ID}] Guest agent not responding after 120s" >&2
  exit 1
fi

echo "[VM ${VM_ID}] Disk passthrough complete — ${#DISKS[@]} disk(s) attached"
