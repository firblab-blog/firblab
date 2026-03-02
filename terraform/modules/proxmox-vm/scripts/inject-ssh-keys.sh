#!/usr/bin/env bash
# =============================================================================
# inject-ssh-keys.sh — QEMU Guest Agent SSH Key Injection
# =============================================================================
# Called by terraform_data.ssh_key_injection in the proxmox-vm module.
# SSHs to the Proxmox host and uses `qm guest exec` to write authorized_keys
# directly inside the VM, bypassing cloud-init entirely.
#
# Required environment variables (set by Terraform local-exec):
#   PROXMOX_HOST  — Proxmox node IP (e.g., 10.0.10.42)
#   PROXMOX_USER  — SSH user for Proxmox node (e.g., admin)
#   VM_ID         — Proxmox VM ID (e.g., 4000)
#   VM_USER       — Username inside the VM (e.g., admin)
#   SSH_PUB_KEY   — Primary SSH public key (Terraform-generated)
#   EXTRA_KEY     — Optional additional SSH public key (operator's personal key)
# =============================================================================
set -euo pipefail

# Validate required vars
for var in PROXMOX_HOST PROXMOX_USER VM_ID VM_USER SSH_PUB_KEY; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Required environment variable $var is not set" >&2
    exit 1
  fi
done

# Build the authorized_keys content
AUTHORIZED_KEYS="$SSH_PUB_KEY"
if [[ -n "${EXTRA_KEY:-}" ]]; then
  AUTHORIZED_KEYS="${AUTHORIZED_KEYS}
${EXTRA_KEY}"
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
# Use specific key with IdentitiesOnly to prevent fail2ban bans from
# ssh-agent offering too many keys before the right one is tried.
if [[ -n "${PROXMOX_SSH_KEY:-}" ]]; then
  SSH_OPTS="${SSH_OPTS} -i ${PROXMOX_SSH_KEY} -o IdentitiesOnly=yes"
fi
PROXMOX_SSH="${PROXMOX_USER}@${PROXMOX_HOST}"

# qm lives in /usr/sbin which isn't in non-root PATH on Proxmox.
# admin user requires sudo to run qm commands.
QM="sudo /usr/sbin/qm"

# ---------------------------------------------------------------------------
# Step 1: Wait for QEMU guest agent to respond
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

# Extra settle time — guest agent may respond before filesystem is fully ready
sleep 3

# ---------------------------------------------------------------------------
# Step 2: Inject SSH keys via guest agent
# ---------------------------------------------------------------------------
echo "[VM ${VM_ID}] Injecting SSH keys for user '${VM_USER}'..."

# Write authorized_keys using qm guest exec.
# qm guest exec runs commands as root inside the VM.
# We use a single bash -c command to avoid multiple round-trips.
# shellcheck disable=SC2086
ssh $SSH_OPTS "$PROXMOX_SSH" "${QM} guest exec ${VM_ID} -- bash -c 'HOME_DIR=\$(getent passwd ${VM_USER} | cut -d: -f6); mkdir -p \${HOME_DIR}/.ssh; chmod 700 \${HOME_DIR}/.ssh; cat > \${HOME_DIR}/.ssh/authorized_keys << KEYS
${AUTHORIZED_KEYS}
KEYS
chmod 600 \${HOME_DIR}/.ssh/authorized_keys; chown -R ${VM_USER}:${VM_USER} \${HOME_DIR}/.ssh'"

echo "[VM ${VM_ID}] SSH keys injected successfully for user '${VM_USER}'"
