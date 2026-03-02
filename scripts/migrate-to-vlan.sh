#!/usr/bin/env bash
# =============================================================================
# Migrate Linux Host to Management VLAN
# =============================================================================
# Reconfigures a Linux host's network interface to use a static IP on the
# Management VLAN (10.0.10.0/24). Run this AFTER Layer 00 (Network) has
# created the VLANs and the host's switch port has been assigned the
# "Management Access" port profile in the UniFi UI.
#
# Supports both:
#   - Ubuntu/Debian with netplan (RPi5, Ubuntu VMs)
#     → Writes a fresh netplan YAML (flat interfaces, no bridge complexity)
#   - Proxmox/Debian with /etc/network/interfaces (lab-02)
#     → In-place sed replacement of IP/gateway/DNS only — preserves all
#       existing bridge directives (bridge-ports, bridge-stp, bridge-fd),
#       source includes, and other interface stanzas. Overwriting the
#       whole file would strip Proxmox bridge config and kill networking.
#
# This script SSHes to the host at its CURRENT IP, detects the network
# config system, updates the config with the TARGET IP, and applies it.
# The SSH session will drop when the IP changes — expected.
#
# For macOS hosts (Mac Mini M4), use scripts/migrate-macmini-vlan.sh instead.
#
# Prerequisites:
#   1. Layer 00 applied (VLANs exist on gw-01)
#   2. Switch port assigned "Management Access" profile (UniFi UI)
#   3. SSH access to host at its current IP
#
# Usage:
#   ./scripts/migrate-to-vlan.sh <current_ip> <target_ip> [user] [ssh_key] [interface]
#
# Examples:
#   ./scripts/migrate-to-vlan.sh 10.0.10.196 10.0.10.2  root  ~/.ssh/id_ed25519_lab-02  # lab-02 (Proxmox)
#   ./scripts/migrate-to-vlan.sh 10.0.4.13 10.0.10.13 admin ~/.ssh/id_ed25519_lab-rpi5  # RPi5 (Ubuntu)
# =============================================================================

set -euo pipefail

# --- Arguments ---
CURRENT_IP="${1:?Usage: $0 <current_ip> <target_ip> [user] [ssh_key] [interface]}"
TARGET_IP="${2:?Usage: $0 <current_ip> <target_ip> [user] [ssh_key] [interface]}"
SSH_USER="${3:-admin}"
SSH_KEY="${4:-}"
IFACE="${5:-}"

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

# Resolve sudo — fresh Proxmox installs don't have sudo, and root doesn't need it.
# When SSH_USER is root, all commands run without sudo prefix.
if [ "${SSH_USER}" = "root" ]; then
  SUDO=""
else
  SUDO="sudo"
fi

# All physical hosts in the lab belong on Management VLAN 10.
# VMs and LXCs on other VLANs (Services 20, DMZ 30, Storage 40,
# Security 50) get their IPs via Terraform cloud-init or Proxmox
# network config — they do not use this script.
GATEWAY="10.0.10.1"
SUBNET_MASK="24"
DNS_1="1.1.1.1"
DNS_2="8.8.8.8"

echo "============================================"
echo "  VLAN Migration (Linux)"
echo "============================================"
echo "  Current IP:  ${CURRENT_IP}"
echo "  Target IP:   ${TARGET_IP}/${SUBNET_MASK}"
echo "  Gateway:     ${GATEWAY}"
echo "  User:        ${SSH_USER}"
echo "  SSH Key:     ${SSH_KEY:-<agent/config default>}"
echo "  DNS:         ${DNS_1}, ${DNS_2}"
echo "============================================"
echo ""

# --- Preflight: verify SSH connectivity ---
echo "[1/6] Verifying SSH connectivity to ${SSH_USER}@${CURRENT_IP}..."
if ! ssh ${SSH_OPTS} -o BatchMode=yes "${SSH_USER}@${CURRENT_IP}" "echo ok" &>/dev/null; then
  echo "ERROR: Cannot SSH to ${SSH_USER}@${CURRENT_IP}"
  echo "  - Is the host reachable? Try: ping ${CURRENT_IP}"
  echo "  - Is SSH key auth configured? Try: ssh ${SSH_KEY:+-i ${SSH_KEY}} ${SSH_USER}@${CURRENT_IP}"
  exit 1
fi
echo "  SSH connection OK."

# --- Detect network interface ---
echo "[2/6] Detecting primary network interface..."
if [ -z "${IFACE}" ]; then
  IFACE=$(ssh ${SSH_OPTS} "${SSH_USER}@${CURRENT_IP}" \
    "ip -o -4 addr show | grep '${CURRENT_IP}' | awk '{print \$2}'" 2>/dev/null)
  if [ -z "${IFACE}" ]; then
    echo "ERROR: Could not detect interface for ${CURRENT_IP}."
    echo "  Specify it manually: $0 ${CURRENT_IP} ${TARGET_IP} ${SSH_USER} ${SSH_KEY:-\"\"} <interface>"
    exit 1
  fi
fi
echo "  Interface: ${IFACE}"

# --- Detect network config system ---
echo "[3/6] Detecting network configuration system..."
HAS_NETPLAN=$(ssh ${SSH_OPTS} "${SSH_USER}@${CURRENT_IP}" \
  "command -v netplan &>/dev/null && echo yes || echo no" 2>/dev/null)

if [ "${HAS_NETPLAN}" = "yes" ]; then
  NET_SYSTEM="netplan"
else
  NET_SYSTEM="interfaces"
fi
echo "  Config system: ${NET_SYSTEM}"

# --- Confirm before proceeding ---
echo ""
echo "[4/6] WARNING: This will change the host's IP address."
echo "  The SSH connection WILL drop when the IP changes."
echo "  After migration, connect with: ssh ${SSH_USER}@${TARGET_IP}"
echo ""
echo "  Before proceeding, confirm:"
echo "    1. Layer 00 has been applied (VLANs exist on gw-01)"
echo "    2. The switch port for this host is assigned the 'Management Access' profile"
echo ""
read -r -p "  Proceed? (y/N): " CONFIRM
if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
  echo "  Aborted."
  exit 0
fi

# --- Write network config ---
if [ "${NET_SYSTEM}" = "netplan" ]; then
  echo "[5/6] Writing netplan configuration..."

  NETPLAN_CONFIG="network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      addresses:
        - ${TARGET_IP}/${SUBNET_MASK}
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses:
          - ${DNS_1}
          - ${DNS_2}
      dhcp4: false
      dhcp6: false"

  ssh ${SSH_OPTS} "${SSH_USER}@${CURRENT_IP}" "
    # Backup existing netplan configs
    ${SUDO} cp -r /etc/netplan /etc/netplan.bak.\$(date +%s)

    # Remove any existing netplan configs
    ${SUDO} rm -f /etc/netplan/*.yaml /etc/netplan/*.yml

    # Write new config
    echo '${NETPLAN_CONFIG}' | ${SUDO} tee /etc/netplan/01-management-vlan.yaml > /dev/null
    ${SUDO} chmod 600 /etc/netplan/01-management-vlan.yaml

    echo 'Netplan written. Applying in 2 seconds...'
    echo 'SSH will disconnect — this is expected.'

    # Apply in background so the SSH command can return
    nohup bash -c 'sleep 2 && ${SUDO} netplan apply' &>/dev/null &
  "

  echo "  Netplan config written and apply scheduled."

else
  echo "[5/6] Updating /etc/network/interfaces configuration..."

  # --- Strategy: in-place sed replacement ---
  # /etc/network/interfaces on Proxmox hosts contains bridge directives
  # (bridge-ports, bridge-stp, bridge-fd) that are CRITICAL for vmbr0 to
  # function. Overwriting the file with a flat template strips these and
  # leaves the bridge with no physical NIC attached — total network loss.
  #
  # Instead, we:
  #   1. Backup the existing config
  #   2. Replace ONLY the IP address line(s) and gateway
  #   3. Add DNS if not already present
  # This preserves all bridge config, source includes, and other stanzas.

  ssh ${SSH_OPTS} "${SSH_USER}@${CURRENT_IP}" "
    set -euo pipefail

    # Backup existing interfaces config
    ${SUDO} cp /etc/network/interfaces /etc/network/interfaces.bak.\$(date +%s)

    # Replace the address line (handles both 'address x.x.x.x/cidr' and 'address x.x.x.x' + 'netmask')
    # Match any address line under the target interface stanza
    ${SUDO} sed -i 's|address ${CURRENT_IP}/[0-9]*|address ${TARGET_IP}/${SUBNET_MASK}|g' /etc/network/interfaces
    ${SUDO} sed -i 's|address ${CURRENT_IP}\$|address ${TARGET_IP}|g' /etc/network/interfaces

    # Update gateway if present
    if grep -q 'gateway ' /etc/network/interfaces; then
      ${SUDO} sed -i 's|gateway [0-9.]*|gateway ${GATEWAY}|g' /etc/network/interfaces
    else
      # Add gateway after the address line
      ${SUDO} sed -i '/address ${TARGET_IP}/a\\        gateway ${GATEWAY}' /etc/network/interfaces
    fi

    # Ensure DNS is configured
    if grep -q 'dns-nameservers' /etc/network/interfaces; then
      ${SUDO} sed -i 's|dns-nameservers .*|dns-nameservers ${DNS_1} ${DNS_2}|g' /etc/network/interfaces
    else
      # Add DNS after gateway line
      ${SUDO} sed -i '/gateway ${GATEWAY}/a\\        dns-nameservers ${DNS_1} ${DNS_2}' /etc/network/interfaces
    fi

    echo 'Updated /etc/network/interfaces (in-place). Verifying...'
    echo '--- Updated config ---'
    cat /etc/network/interfaces
    echo '--- End config ---'
    echo ''
    echo 'Restarting networking in 2 seconds...'
    echo 'SSH will disconnect — this is expected.'

    # Restart networking in background so the SSH command can return
    nohup bash -c 'sleep 2 && ${SUDO} systemctl restart networking' &>/dev/null &
  "

  echo "  Interfaces config updated in-place and restart scheduled."
fi

# --- Wait and verify ---
echo "[6/6] Waiting for host to come up at ${TARGET_IP}..."
echo "  (This may take 10-30 seconds)"

RETRIES=12
DELAY=5
for i in $(seq 1 ${RETRIES}); do
  sleep ${DELAY}
  if ssh ${SSH_OPTS} -o ConnectTimeout=3 -o BatchMode=yes "${SSH_USER}@${TARGET_IP}" "echo ok" &>/dev/null; then
    echo ""
    echo "============================================"
    echo "  Migration successful!"
    echo "  Host is now reachable at: ${SSH_USER}@${TARGET_IP}"
    echo "============================================"
    exit 0
  fi
  echo "  Attempt ${i}/${RETRIES} — waiting..."
done

echo ""
echo "============================================"
echo "  WARNING: Host did not come up at ${TARGET_IP}"
echo "  within $(( RETRIES * DELAY )) seconds."
echo ""
echo "  Possible causes:"
echo "    - Switch port not yet on VLAN 10"
echo "    - IP conflict on 10.0.10.0/24"
echo "    - Config syntax error"
echo ""
if [ "${NET_SYSTEM}" = "netplan" ]; then
  echo "  Recovery (netplan):"
  echo "    - Check /etc/netplan/01-management-vlan.yaml"
  echo "    - Backups are in /etc/netplan.bak.*"
  echo "    - Restore: sudo cp /etc/netplan.bak.*/*.yaml /etc/netplan/ && sudo netplan apply"
else
  echo "  Recovery (interfaces — in-place edit, backup available):"
  echo "    - Check /etc/network/interfaces (only IP/gateway/DNS were changed)"
  echo "    - Backup is at /etc/network/interfaces.bak.*"
  echo "    - Restore: sudo cp /etc/network/interfaces.bak.<timestamp> /etc/network/interfaces && sudo systemctl restart networking"
  echo "    - Or manually fix the address line and restart networking"
fi
echo "============================================"
exit 1
