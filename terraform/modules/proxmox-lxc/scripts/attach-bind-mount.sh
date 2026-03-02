#!/usr/bin/env bash
# =============================================================================
# attach-bind-mount.sh — Bind-Mount Host Directory into LXC Container
# =============================================================================
# Called by terraform_data.backup_bind_mount in Layer 05.
# SSHs to the Proxmox host and uses `pct set` to attach a host directory
# as a bind mount inside the LXC container.
#
# Required because the bpg/proxmox Terraform provider requires root@pam auth
# for LXC bind mounts, and we authenticate with terraform@pam API tokens.
# Same pattern as attach-passthrough-disks.sh for VM disk passthrough.
#
# Required environment variables (set by Terraform local-exec):
#   PROXMOX_HOST       — Proxmox node IP (e.g., 10.0.10.42)
#   PROXMOX_USER       — SSH user for Proxmox node (e.g., admin)
#   PROXMOX_SSH_KEY    — SSH private key path for Proxmox node
#   CONTAINER_ID       — Proxmox LXC container ID (e.g., 5040)
#   HOST_PATH          — Host directory to bind-mount (e.g., /hdd-mirror-0/restic)
#   CONTAINER_PATH     — Mount point inside container (e.g., /mnt/restic)
# =============================================================================
set -euo pipefail

# Validate required vars
for var in PROXMOX_HOST PROXMOX_USER PROXMOX_SSH_KEY CONTAINER_ID HOST_PATH CONTAINER_PATH; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Required environment variable $var is not set" >&2
    exit 1
  fi
done

echo "[CT ${CONTAINER_ID}] Attaching bind mount: ${HOST_PATH} -> ${CONTAINER_PATH}"

# SSH options — use specific key with IdentitiesOnly to prevent fail2ban bans
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
SSH_OPTS="${SSH_OPTS} -i ${PROXMOX_SSH_KEY} -o IdentitiesOnly=yes"
PROXMOX_SSH="${PROXMOX_USER}@${PROXMOX_HOST}"

# pct lives in /usr/sbin which isn't in non-root PATH on Proxmox.
# admin user requires sudo to run pct commands.
PCT="sudo /usr/sbin/pct"

# ---------------------------------------------------------------------------
# Step 1: Check current container status
# ---------------------------------------------------------------------------
echo "[CT ${CONTAINER_ID}] Checking container status..."
# shellcheck disable=SC2086
CT_STATUS=$(ssh $SSH_OPTS "$PROXMOX_SSH" "${PCT} status ${CONTAINER_ID}" 2>&1)
echo "[CT ${CONTAINER_ID}] Current status: ${CT_STATUS}"

# ---------------------------------------------------------------------------
# Step 2: Check if bind mount already exists
# ---------------------------------------------------------------------------
echo "[CT ${CONTAINER_ID}] Checking if mp0 is already configured..."
# shellcheck disable=SC2086
EXISTING_MP=$(ssh $SSH_OPTS "$PROXMOX_SSH" "${PCT} config ${CONTAINER_ID}" 2>&1 | grep "^mp0:" || true)

if [[ -n "$EXISTING_MP" ]]; then
  if echo "$EXISTING_MP" | grep -q "${HOST_PATH}"; then
    echo "[CT ${CONTAINER_ID}] Bind mount already configured: ${EXISTING_MP}"
    echo "[CT ${CONTAINER_ID}] No changes needed."
    exit 0
  else
    echo "[CT ${CONTAINER_ID}] mp0 exists but with different path: ${EXISTING_MP}"
    echo "[CT ${CONTAINER_ID}] Will reconfigure..."
  fi
fi

# ---------------------------------------------------------------------------
# Step 3: Stop container if running (pct set for mount points requires stop)
# ---------------------------------------------------------------------------
CT_WAS_RUNNING=false
if echo "$CT_STATUS" | grep -q "running"; then
  echo "[CT ${CONTAINER_ID}] Stopping container for mount point configuration..."
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "$PROXMOX_SSH" "${PCT} shutdown ${CONTAINER_ID} --timeout 30" 2>&1 || true

  # Wait for container to stop
  for i in $(seq 1 20); do
    # shellcheck disable=SC2086
    STATUS=$(ssh $SSH_OPTS "$PROXMOX_SSH" "${PCT} status ${CONTAINER_ID}" 2>&1)
    if echo "$STATUS" | grep -q "stopped"; then
      echo "[CT ${CONTAINER_ID}] Container stopped (attempt ${i})"
      break
    fi
    if [[ $i -eq 20 ]]; then
      echo "[CT ${CONTAINER_ID}] Container didn't stop gracefully, forcing..."
      # shellcheck disable=SC2086
      ssh $SSH_OPTS "$PROXMOX_SSH" "${PCT} stop ${CONTAINER_ID}" 2>&1
      sleep 3
    fi
    sleep 2
  done
  CT_WAS_RUNNING=true
fi

# ---------------------------------------------------------------------------
# Step 4: Verify host path exists on Proxmox node
# ---------------------------------------------------------------------------
echo "[CT ${CONTAINER_ID}] Verifying host path ${HOST_PATH} exists..."
# shellcheck disable=SC2086
if ! ssh $SSH_OPTS "$PROXMOX_SSH" "sudo test -d ${HOST_PATH}"; then
  echo "ERROR: [CT ${CONTAINER_ID}] Host path ${HOST_PATH} does not exist on ${PROXMOX_HOST}" >&2
  # Restart container if it was running before
  if [[ "$CT_WAS_RUNNING" == "true" ]]; then
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "$PROXMOX_SSH" "${PCT} start ${CONTAINER_ID}" 2>&1 || true
  fi
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 5: Attach bind mount via pct set
# ---------------------------------------------------------------------------
echo "[CT ${CONTAINER_ID}] Attaching bind mount..."
# shellcheck disable=SC2086
ssh $SSH_OPTS "$PROXMOX_SSH" "${PCT} set ${CONTAINER_ID} -mp0 ${HOST_PATH},mp=${CONTAINER_PATH}"
echo "[CT ${CONTAINER_ID}] Bind mount configured successfully"

# ---------------------------------------------------------------------------
# Step 5.5: Fix ownership for unprivileged LXC UID mapping
# ---------------------------------------------------------------------------
# Unprivileged LXCs use UID namespace isolation. Proxmox default subuid/subgid
# mapping: container UID 0 → host UID 100000 (base offset from /etc/subuid).
# Without this chown, the bind-mounted directory appears as nobody:nogroup
# (65534:65534) inside the container, and chown from inside the container
# fails with EPERM.
#
# By chowning the host directory to 100000:100000, it appears as root:root
# inside the container. Ansible (running as root via become: true) can then
# chown to the service user (e.g., restic:restic).
#
# We read the actual mapping from the container config to avoid hardcoding.
echo "[CT ${CONTAINER_ID}] Fixing ownership for unprivileged LXC UID mapping..."
# shellcheck disable=SC2086
LXC_IDMAP=$(ssh $SSH_OPTS "$PROXMOX_SSH" "sudo grep '^lxc.idmap' /etc/pve/lxc/${CONTAINER_ID}.conf 2>/dev/null | head -1" || true)
if [[ -n "$LXC_IDMAP" ]]; then
  # Parse: lxc.idmap = u 0 100000 65536 → extract base UID (100000)
  HOST_UID_BASE=$(echo "$LXC_IDMAP" | awk '{print $5}')
  echo "[CT ${CONTAINER_ID}] Container UID mapping: container 0 → host ${HOST_UID_BASE}"
else
  # Default Proxmox unprivileged LXC mapping
  HOST_UID_BASE=100000
  echo "[CT ${CONTAINER_ID}] No explicit idmap found, using default base: ${HOST_UID_BASE}"
fi

# Chown the host directory (and contents) to the container's root UID
# shellcheck disable=SC2086
ssh $SSH_OPTS "$PROXMOX_SSH" "sudo chown -R ${HOST_UID_BASE}:${HOST_UID_BASE} ${HOST_PATH}"
echo "[CT ${CONTAINER_ID}] Host path ${HOST_PATH} chowned to ${HOST_UID_BASE}:${HOST_UID_BASE}"

# ---------------------------------------------------------------------------
# Step 6: Start container
# ---------------------------------------------------------------------------
echo "[CT ${CONTAINER_ID}] Starting container..."
# shellcheck disable=SC2086
ssh $SSH_OPTS "$PROXMOX_SSH" "${PCT} start ${CONTAINER_ID}"

# Wait for container to be running
for i in $(seq 1 30); do
  # shellcheck disable=SC2086
  STATUS=$(ssh $SSH_OPTS "$PROXMOX_SSH" "${PCT} status ${CONTAINER_ID}" 2>&1)
  if echo "$STATUS" | grep -q "running"; then
    echo "[CT ${CONTAINER_ID}] Container is running (attempt ${i})"
    break
  fi
  if [[ $i -eq 30 ]]; then
    echo "ERROR: [CT ${CONTAINER_ID}] Container did not reach running state within 60 seconds" >&2
    exit 1
  fi
  sleep 2
done

# ---------------------------------------------------------------------------
# Step 7: Verify bind mount is visible inside container
# ---------------------------------------------------------------------------
echo "[CT ${CONTAINER_ID}] Verifying bind mount inside container..."
# shellcheck disable=SC2086
if ssh $SSH_OPTS "$PROXMOX_SSH" "${PCT} exec ${CONTAINER_ID} -- test -d ${CONTAINER_PATH}"; then
  echo "[CT ${CONTAINER_ID}] Bind mount verified: ${CONTAINER_PATH} is accessible"
else
  echo "WARNING: [CT ${CONTAINER_ID}] ${CONTAINER_PATH} not visible inside container" >&2
fi

echo "[CT ${CONTAINER_ID}] Bind mount complete: ${HOST_PATH} -> ${CONTAINER_PATH}"
