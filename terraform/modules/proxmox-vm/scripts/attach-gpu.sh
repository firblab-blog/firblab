#!/usr/bin/env bash
# =============================================================================
# attach-gpu.sh — PCI GPU Passthrough to Proxmox VM
# =============================================================================
# Called by terraform_data.ai_gpu_passthrough in Layer 05.
# SSHs to the Proxmox host and uses `qm set` to attach PCI
# devices (GPU + audio function) to the VM as hostpci0, hostpci1, etc.
#
# Required environment variables (set by Terraform local-exec):
#   PROXMOX_HOST    — Proxmox node IP (e.g., 10.0.10.42)
#   PROXMOX_USER    — SSH user for Proxmox node (e.g., admin)
#   PROXMOX_SSH_KEY — SSH private key path for Proxmox node
#   VM_ID           — Proxmox VM ID (e.g., 5035)
#   PCI_DEVICES     — Pipe-separated PCI device specs. Each spec can
#                      contain commas for PCI options (e.g., "03:00.0,pcie=1|03:00.1,pcie=1")
#
# AMD RDNA 3 (Navi 32/33) GPU Reset Workaround:
#   These GPUs cannot perform a clean PCI Function-Level Reset. After a VM
#   shutdown or failed start, the GPU enters D3cold and becomes permanently
#   inaccessible (PCI config space reads as garbage). The only recovery is
#   a full PCI bus remove/rescan, which forces the kernel to re-enumerate
#   the device. This script performs that reset before every qm start.
#
# Prerequisites:
#   - IOMMU enabled on the host (intel_iommu=on iommu=pt)
#   - GPU bound to vfio-pci driver (not amdgpu/nouveau)
#   - Run proxmox-gpu-setup.yml before using this script
# =============================================================================
set -euo pipefail

# Validate required vars
for var in PROXMOX_HOST PROXMOX_USER PROXMOX_SSH_KEY VM_ID PCI_DEVICES; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Required environment variable $var is not set" >&2
    exit 1
  fi
done

# Parse PCI device list — pipe-separated, each entry is "bus:slot.func,options"
# e.g., "03:00.0,pcie=1|03:00.1,pcie=1" → two devices
IFS='|' read -ra DEVICES <<< "$PCI_DEVICES"

if [[ ${#DEVICES[@]} -eq 0 ]]; then
  echo "ERROR: PCI_DEVICES is empty" >&2
  exit 1
fi

echo "[VM ${VM_ID}] Attaching ${#DEVICES[@]} PCI device(s)..."
for i in "${!DEVICES[@]}"; do
  echo "  hostpci${i}: ${DEVICES[$i]}"
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
# Step 2: Stop VM if running (hostpci requires VM to be stopped)
# ---------------------------------------------------------------------------
if echo "$VM_STATUS" | grep -q "running"; then
  echo "[VM ${VM_ID}] Stopping VM for GPU attachment..."
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
fi

# ---------------------------------------------------------------------------
# Step 3: Attach each PCI device via qm set
# ---------------------------------------------------------------------------
for i in "${!DEVICES[@]}"; do
  DEVICE="${DEVICES[$i]}"

  echo "[VM ${VM_ID}] Attaching PCI device as hostpci${i}: ${DEVICE}..."
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "$PROXMOX_SSH" "${QM} set ${VM_ID} --hostpci${i} ${DEVICE}"
  echo "[VM ${VM_ID}] hostpci${i} attached successfully"
done

# ---------------------------------------------------------------------------
# Step 4: PCI GPU Reset — Remove/Rescan (AMD RDNA 3 workaround)
# ---------------------------------------------------------------------------
# AMD RX 7800 XT (Navi 32) cannot perform a clean PCI FLR. After any VM
# lifecycle event (start/stop/crash), the GPU may enter D3cold with corrupt
# PCI config space (PCI_INTERRUPT_PIN reads as 0 → QEMU assertion crash).
#
# The fix: remove the GPU from the PCI bus, rescan to re-enumerate from
# scratch, then rebind to vfio-pci. This forces the kernel to re-read
# the device's config space from hardware, getting a clean state.
#
# We extract just the PCI addresses (bus:slot.func) from the device specs,
# stripping off any options like pcie=1,rombar=0.
echo "[VM ${VM_ID}] Performing PCI GPU reset (remove/rescan)..."

# Build the list of PCI addresses to reset
PCI_ADDRS=()
for i in "${!DEVICES[@]}"; do
  # Extract just the PCI address (everything before the first comma)
  ADDR=$(echo "${DEVICES[$i]}" | cut -d',' -f1)
  PCI_ADDRS+=("0000:${ADDR}")
done

# Build a remote reset script as a temp file to avoid heredoc quoting hell.
# The script runs as root on the Proxmox host via sudo.
RESET_SCRIPT=$(mktemp /tmp/gpu-reset-XXXXXX.sh)
cat > "$RESET_SCRIPT" <<'RESET_EOF'
#!/usr/bin/env bash
set -e
ADDRS=("$@")

# ---------------------------------------------------------------------------
# Check if GPU reset is actually needed
# ---------------------------------------------------------------------------
# On fresh Terraform apply (GPU never used by a VM), the GPU should be in D0
# bound to vfio-pci. Doing a PCI remove/rescan in this state is unnecessary
# and dangerous — RDNA 3 GPUs can enter D3cold during removal and fail to
# re-enumerate. Only reset if the GPU is in a bad state.
# ---------------------------------------------------------------------------
echo "  Checking GPU state..."
NEEDS_RESET=false
for addr in "${ADDRS[@]}"; do
  STATE=$(cat "/sys/bus/pci/devices/${addr}/power_state" 2>/dev/null || echo "missing")
  DRIVER=$(basename "$(readlink "/sys/bus/pci/devices/${addr}/driver" 2>/dev/null)" 2>/dev/null || echo "none")
  D3COLD=$(cat "/sys/bus/pci/devices/${addr}/d3cold_allowed" 2>/dev/null || echo "unknown")
  echo "  ${addr}: driver=${DRIVER} power_state=${STATE} d3cold_allowed=${D3COLD}"

  if [ "$STATE" = "missing" ]; then
    echo "  ${addr}: device not present in sysfs — needs reset"
    NEEDS_RESET=true
  elif [ "$STATE" != "D0" ]; then
    echo "  ${addr}: not in D0 (${STATE}) — needs reset"
    NEEDS_RESET=true
  elif [ "$DRIVER" != "vfio-pci" ]; then
    echo "  ${addr}: wrong driver (${DRIVER}) — needs reset"
    NEEDS_RESET=true
  fi
done

if [ "$NEEDS_RESET" = "false" ]; then
  echo "  All GPU devices in D0 with vfio-pci — skipping PCI reset"
  echo "  GPU reset complete (no-op)"
  exit 0
fi

echo "  GPU needs PCI reset — performing remove/rescan..."

echo "  Removing PCI devices..."
for addr in "${ADDRS[@]}"; do
  if [ -e "/sys/bus/pci/devices/${addr}/remove" ]; then
    echo 1 > "/sys/bus/pci/devices/${addr}/remove"
    echo "  ${addr}: removed"
  else
    echo "  ${addr}: already removed or not present"
  fi
done

sleep 5

echo "  Rescanning PCI bus..."
echo 1 > /sys/bus/pci/rescan

# Wait for devices to re-enumerate — RDNA 3 can be slow to come back
RESCAN_OK=false
for attempt in 1 2 3; do
  sleep 5
  ALL_FOUND=true
  for addr in "${ADDRS[@]}"; do
    if [ ! -e "/sys/bus/pci/devices/${addr}" ]; then
      ALL_FOUND=false
      break
    fi
  done
  if [ "$ALL_FOUND" = "true" ]; then
    RESCAN_OK=true
    echo "  All devices found after rescan (attempt ${attempt})"
    break
  fi
  echo "  Devices not yet visible, retrying rescan (attempt ${attempt}/3)..."
  echo 1 > /sys/bus/pci/rescan
done

if [ "$RESCAN_OK" = "false" ]; then
  echo "" >&2
  echo "  ERROR: GPU devices not found after 3 rescan attempts!" >&2
  echo "  This usually means the GPU entered D3cold during removal." >&2
  echo "  Recovery requires a FULL POWER CYCLE of the Proxmox host:" >&2
  echo "    1. Shut down all VMs: qm shutdown <vmid>" >&2
  echo "    2. Power off: sudo poweroff" >&2
  echo "    3. Wait 10 seconds, then power on" >&2
  echo "" >&2
  exit 1
fi

echo "  Rebinding to vfio-pci..."
for addr in "${ADDRS[@]}"; do
  if [ -e "/sys/bus/pci/devices/${addr}" ]; then
    echo "vfio-pci" > "/sys/bus/pci/devices/${addr}/driver_override"
    if [ -e "/sys/bus/pci/devices/${addr}/driver/unbind" ]; then
      echo "${addr}" > "/sys/bus/pci/devices/${addr}/driver/unbind" 2>/dev/null || true
    fi
    echo "${addr}" > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true

    DRIVER=$(basename "$(readlink "/sys/bus/pci/devices/${addr}/driver" 2>/dev/null)" 2>/dev/null || echo "none")
    STATE=$(cat "/sys/bus/pci/devices/${addr}/power_state" 2>/dev/null || echo "unknown")
    D3COLD=$(cat "/sys/bus/pci/devices/${addr}/d3cold_allowed" 2>/dev/null || echo "unknown")
    echo "  ${addr}: driver=${DRIVER} power_state=${STATE} d3cold_allowed=${D3COLD}"
  else
    echo "  ERROR: ${addr} not found after rescan!" >&2
    exit 1
  fi
done

echo "  GPU reset complete"
RESET_EOF
chmod +x "$RESET_SCRIPT"

# Upload and execute the reset script on the Proxmox host
REMOTE_SCRIPT="/tmp/gpu-reset-$$.sh"
# shellcheck disable=SC2086
scp $SSH_OPTS "$RESET_SCRIPT" "${PROXMOX_SSH}:${REMOTE_SCRIPT}"
# shellcheck disable=SC2086
ssh $SSH_OPTS "$PROXMOX_SSH" "sudo bash ${REMOTE_SCRIPT} ${PCI_ADDRS[*]}"
# shellcheck disable=SC2086
ssh $SSH_OPTS "$PROXMOX_SSH" "rm -f ${REMOTE_SCRIPT}"
rm -f "$RESET_SCRIPT"

echo "[VM ${VM_ID}] PCI GPU reset successful"

# ---------------------------------------------------------------------------
# Step 5: Deploy hookscript for future VM start/stop cycles
# ---------------------------------------------------------------------------
# Install a Proxmox hookscript so the PCI remove/rescan happens automatically
# on every VM start — not just Terraform-managed starts. Without this, manual
# `qm start` or Proxmox auto-start after reboot would hit the same QEMU crash.
echo "[VM ${VM_ID}] Installing GPU reset hookscript..."

HOOKSCRIPT_NAME="gpu-reset-${VM_ID}.sh"

# Build the hookscript content locally, then upload it
HOOKSCRIPT_FILE=$(mktemp /tmp/gpu-hookscript-XXXXXX.sh)
cat > "$HOOKSCRIPT_FILE" <<HOOKSCRIPT_EOF
#!/usr/bin/env bash
# =============================================================================
# Proxmox Hookscript — AMD RDNA 3 GPU Reset
# =============================================================================
# Performs PCI remove/rescan before VM start to work around the AMD GPU reset
# bug. Without this, the GPU enters D3cold after any VM lifecycle event and
# QEMU crashes with: pci_irq_handler: Assertion '0 <= irq_num' failed.
#
# Installed by: terraform_data.ai_gpu_passthrough (attach-gpu.sh)
# Hookscript docs: https://pve.proxmox.com/pve-docs/chapter-qm.html#qm_hookscripts
# =============================================================================

VMID="\$1"
PHASE="\$2"

GPU_ADDRS=(${PCI_ADDRS[*]})

case "\$PHASE" in
  pre-start)
    echo "GPU hookscript: Resetting AMD GPU for VM \${VMID}..."

    # Check if reset is needed (GPU already in D0 + vfio-pci = skip)
    NEEDS_RESET=false
    for addr in "\${GPU_ADDRS[@]}"; do
      STATE=\$(cat "/sys/bus/pci/devices/\${addr}/power_state" 2>/dev/null || echo "missing")
      DRIVER=\$(basename "\$(readlink "/sys/bus/pci/devices/\${addr}/driver" 2>/dev/null)" 2>/dev/null || echo "none")
      echo "  \${addr}: driver=\${DRIVER} power_state=\${STATE}"
      if [ "\$STATE" != "D0" ] || [ "\$DRIVER" != "vfio-pci" ]; then
        NEEDS_RESET=true
      fi
    done

    if [ "\$NEEDS_RESET" = "false" ]; then
      echo "GPU hookscript: All devices in D0 with vfio-pci — skipping reset"
      exit 0
    fi

    for addr in "\${GPU_ADDRS[@]}"; do
      if [ -e "/sys/bus/pci/devices/\${addr}/remove" ]; then
        echo 1 > "/sys/bus/pci/devices/\${addr}/remove"
        echo "  \${addr}: removed"
      fi
    done

    sleep 5

    # Retry rescan up to 3 times — RDNA 3 can be slow to re-enumerate
    RESCAN_OK=false
    for attempt in 1 2 3; do
      echo 1 > /sys/bus/pci/rescan
      sleep 5
      ALL_FOUND=true
      for addr in "\${GPU_ADDRS[@]}"; do
        if [ ! -e "/sys/bus/pci/devices/\${addr}" ]; then
          ALL_FOUND=false
          break
        fi
      done
      if [ "\$ALL_FOUND" = "true" ]; then
        RESCAN_OK=true
        echo "  Devices found after rescan (attempt \${attempt})"
        break
      fi
      echo "  Rescan attempt \${attempt}/3 — devices not yet visible..."
    done

    if [ "\$RESCAN_OK" = "false" ]; then
      echo "  ERROR: GPU not found after 3 rescan attempts!" >&2
      echo "  Host power cycle required to recover GPU." >&2
      exit 1
    fi

    for addr in "\${GPU_ADDRS[@]}"; do
      if [ -e "/sys/bus/pci/devices/\${addr}" ]; then
        echo "vfio-pci" > "/sys/bus/pci/devices/\${addr}/driver_override"
        if [ -e "/sys/bus/pci/devices/\${addr}/driver/unbind" ]; then
          echo "\${addr}" > "/sys/bus/pci/devices/\${addr}/driver/unbind" 2>/dev/null || true
        fi
        echo "\${addr}" > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true

        STATE=\$(cat "/sys/bus/pci/devices/\${addr}/power_state" 2>/dev/null || echo "unknown")
        echo "  \${addr}: rebound to vfio-pci, power_state=\${STATE}"
      else
        echo "  ERROR: \${addr} not found after rescan!"
        exit 1
      fi
    done

    echo "GPU hookscript: Reset complete"
    ;;

  post-stop)
    echo "GPU hookscript: VM \${VMID} stopped, GPU will be reset on next pre-start"
    ;;

  *)
    ;;
esac

exit 0
HOOKSCRIPT_EOF
chmod +x "$HOOKSCRIPT_FILE"

# Upload hookscript to Proxmox snippets directory
# shellcheck disable=SC2086
scp $SSH_OPTS "$HOOKSCRIPT_FILE" "${PROXMOX_SSH}:/tmp/${HOOKSCRIPT_NAME}"
# shellcheck disable=SC2086
ssh $SSH_OPTS "$PROXMOX_SSH" "sudo mv /tmp/${HOOKSCRIPT_NAME} /var/lib/vz/snippets/${HOOKSCRIPT_NAME} && sudo chmod +x /var/lib/vz/snippets/${HOOKSCRIPT_NAME}"
rm -f "$HOOKSCRIPT_FILE"

# Attach hookscript to the VM
# shellcheck disable=SC2086
ssh $SSH_OPTS "$PROXMOX_SSH" "${QM} set ${VM_ID} --hookscript local:snippets/${HOOKSCRIPT_NAME}"
echo "[VM ${VM_ID}] Hookscript installed: local:snippets/${HOOKSCRIPT_NAME}"

# ---------------------------------------------------------------------------
# Step 6: Start VM
# ---------------------------------------------------------------------------
echo "[VM ${VM_ID}] Starting VM..."
# shellcheck disable=SC2086
ssh $SSH_OPTS "$PROXMOX_SSH" "${QM} start ${VM_ID}"

# ---------------------------------------------------------------------------
# Step 7: Wait for QEMU guest agent to respond (confirms VM is fully booted)
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

echo "[VM ${VM_ID}] GPU passthrough complete — ${#DEVICES[@]} PCI device(s) attached"
