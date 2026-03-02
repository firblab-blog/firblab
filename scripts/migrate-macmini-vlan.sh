#!/usr/bin/env bash
# =============================================================================
# Migrate Mac Mini M4 to Management VLAN (macOS)
# =============================================================================
# Reconfigures the Mac Mini M4's Ethernet interface to use a static IP on
# the Management VLAN (10.0.10.0/24). Run this from your MacBook Pro
# AFTER Layer 00 (Network) has created the VLANs and the Mac Mini's switch
# port has been assigned the "Management Access" port profile in the UniFi UI.
#
# This script SSHes to the Mac Mini at its CURRENT IP and uses macOS
# `networksetup` to set a static IP. The SSH session will drop when the
# IP changes — this is expected.
#
# After migration, the Mac Mini host will be at 10.0.10.10. The UTM VM
# (vault-1) will be created separately at 10.0.10.11 using
# scripts/setup-macmini-vm.sh.
#
# For Linux hosts (lab-02, RPi5), use scripts/migrate-to-vlan.sh instead.
#
# Prerequisites:
#   1. Layer 00 applied (VLANs exist on gw-01)
#   2. Mac Mini switch port assigned "Management Access" profile (UniFi UI)
#   3. SSH access to Mac Mini at its current IP (Remote Login enabled in
#      System Settings > General > Sharing)
#
# Usage:
#   ./scripts/migrate-macmini-vlan.sh <current_ip> <target_ip> [user] [ssh_key]
#
# Examples:
#   ./scripts/migrate-macmini-vlan.sh 10.0.4.28 10.0.10.10 admin ~/.ssh/id_ed25519_lab-macmini
#   ./scripts/migrate-macmini-vlan.sh 10.0.4.28 10.0.10.10  # defaults: admin, auto-detect key
# =============================================================================

set -euo pipefail

# --- Arguments ---
CURRENT_IP="${1:?Usage: $0 <current_ip> <target_ip> [user] [ssh_key]}"
TARGET_IP="${2:?Usage: $0 <current_ip> <target_ip> [user] [ssh_key]}"
SSH_USER="${3:-admin}"
SSH_KEY="${4:-}"

# --- Build SSH options ---
# If a key is specified, use it. Otherwise let SSH agent / ~/.ssh/config handle it.
SSH_OPTS="-o ConnectTimeout=5"
if [ -n "${SSH_KEY}" ]; then
  if [ ! -f "${SSH_KEY}" ]; then
    echo "ERROR: SSH key not found: ${SSH_KEY}"
    exit 1
  fi
  SSH_OPTS="${SSH_OPTS} -i ${SSH_KEY}"
fi

# All physical hosts in the lab belong on Management VLAN 10.
GATEWAY="10.0.10.1"
SUBNET="255.255.255.0"
DNS_1="1.1.1.1"
DNS_2="8.8.8.8"

echo "============================================"
echo "  VLAN Migration (macOS — Mac Mini M4)"
echo "============================================"
echo "  Current IP:  ${CURRENT_IP}"
echo "  Target IP:   ${TARGET_IP}"
echo "  Subnet:      ${SUBNET}"
echo "  Gateway:     ${GATEWAY}"
echo "  User:        ${SSH_USER}"
echo "  SSH Key:     ${SSH_KEY:-<agent/config default>}"
echo "  DNS:         ${DNS_1}, ${DNS_2}"
echo "============================================"
echo ""

# --- Preflight: verify SSH connectivity ---
echo "[1/5] Verifying SSH connectivity to ${SSH_USER}@${CURRENT_IP}..."
if ! ssh ${SSH_OPTS} -o BatchMode=yes "${SSH_USER}@${CURRENT_IP}" "echo ok" &>/dev/null; then
  echo "ERROR: Cannot SSH to ${SSH_USER}@${CURRENT_IP}"
  echo "  - Is the host reachable? Try: ping ${CURRENT_IP}"
  echo "  - Is Remote Login enabled? System Settings > General > Sharing > Remote Login"
  echo "  - Is SSH key auth configured? Try: ssh ${SSH_KEY:+-i ${SSH_KEY}} ${SSH_USER}@${CURRENT_IP}"
  exit 1
fi
echo "  SSH connection OK."

# --- Detect Ethernet service name ---
echo "[2/5] Detecting macOS Ethernet network service..."
NET_SERVICE=$(ssh ${SSH_OPTS} "${SSH_USER}@${CURRENT_IP}" \
  "networksetup -listallnetworkservices | grep -i -E 'ethernet|thunderbolt|usb.*lan' | head -1" 2>/dev/null)

if [ -z "${NET_SERVICE}" ]; then
  echo "ERROR: Could not detect Ethernet network service on Mac Mini."
  echo "  Available services:"
  ssh ${SSH_OPTS} "${SSH_USER}@${CURRENT_IP}" \
    "networksetup -listallnetworkservices" 2>/dev/null || true
  echo ""
  echo "  Manually set the IP on the Mac Mini:"
  echo "    sudo networksetup -setmanual \"<service_name>\" ${TARGET_IP} ${SUBNET} ${GATEWAY}"
  echo "    sudo networksetup -setdnsservers \"<service_name>\" ${DNS_1} ${DNS_2}"
  exit 1
fi
echo "  Network service: ${NET_SERVICE}"

# --- Show current config ---
echo ""
echo "  Current configuration:"
ssh ${SSH_OPTS} "${SSH_USER}@${CURRENT_IP}" \
  "networksetup -getinfo '${NET_SERVICE}'" 2>/dev/null || true
echo ""

# --- Confirm before proceeding ---
echo "[3/5] WARNING: This will change the Mac Mini's IP address."
echo "  The SSH connection WILL drop when the IP changes."
echo "  After migration, connect with: ssh ${SSH_USER}@${TARGET_IP}"
echo ""
echo "  Before proceeding, confirm:"
echo "    1. Layer 00 has been applied (VLANs exist on gw-01)"
echo "    2. The Mac Mini's switch port is assigned the 'Management Access' profile"
echo ""
read -r -p "  Proceed? (y/N): " CONFIRM
if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
  echo "  Aborted."
  exit 0
fi

# --- Apply network configuration ---
echo "[4/5] Applying static IP configuration..."

# networksetup takes effect immediately — the connection will drop
ssh ${SSH_OPTS} "${SSH_USER}@${CURRENT_IP}" "
  echo 'Setting static IP: ${TARGET_IP}...'
  echo 'SSH will disconnect — this is expected.'

  # Apply in background so the SSH command can return
  nohup bash -c '
    sleep 2
    sudo networksetup -setmanual \"${NET_SERVICE}\" ${TARGET_IP} ${SUBNET} ${GATEWAY}
    sudo networksetup -setdnsservers \"${NET_SERVICE}\" ${DNS_1} ${DNS_2}
  ' &>/dev/null &
"

echo "  Static IP configuration scheduled."

# --- Wait and verify ---
echo "[5/5] Waiting for Mac Mini to come up at ${TARGET_IP}..."
echo "  (This may take 10-30 seconds)"

RETRIES=12
DELAY=5
for i in $(seq 1 ${RETRIES}); do
  sleep ${DELAY}
  if ssh ${SSH_OPTS} -o ConnectTimeout=3 -o BatchMode=yes "${SSH_USER}@${TARGET_IP}" "echo ok" &>/dev/null; then
    echo ""
    echo "============================================"
    echo "  Migration successful!"
    echo "  Mac Mini is now reachable at: ${SSH_USER}@${TARGET_IP}"
    echo ""
    echo "  Next step: Create the UTM VM for vault-1:"
    echo "    ./scripts/setup-macmini-vm.sh"
    echo "============================================"
    exit 0
  fi
  echo "  Attempt ${i}/${RETRIES} — waiting..."
done

echo ""
echo "============================================"
echo "  WARNING: Mac Mini did not come up at ${TARGET_IP}"
echo "  within $(( RETRIES * DELAY )) seconds."
echo ""
echo "  Possible causes:"
echo "    - Switch port not yet on VLAN 10"
echo "    - IP conflict on 10.0.10.0/24"
echo "    - networksetup command failed"
echo ""
echo "  Recovery (physical/Screen Sharing access):"
echo "    - Open System Settings > Network > Ethernet"
echo "    - Set IP manually to ${TARGET_IP}"
echo "    - Or revert: sudo networksetup -setdhcp '${NET_SERVICE}'"
echo "============================================"
exit 1
