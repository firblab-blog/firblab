#!/bin/bash
# =============================================================================
# UniFi Auto-Discovery + Vault Seed Script
# =============================================================================
# Queries the UniFi controller API to discover infrastructure metadata
# (switch MACs, Default LAN network ID) and seeds them into Vault.
#
# Eliminates manual MAC tracking — the controller is the source of truth
# for hardware identifiers, Vault is the source of truth for Terraform.
#
# Prerequisites:
#   - UniFi controller with API key (UCG-Fiber or UDM Pro)
#   - jq installed
#   - For --seed mode: vault CLI authenticated (VAULT_TOKEN + VAULT_ADDR set)
#
# Usage:
#   # Discover only (prints -var flags for bootstrap)
#   ./scripts/seed-unifi-to-vault.sh --discover \
#     --host 10.0.4.1 --api-key "<key>"
#
#   # Seed into Vault (after controller + Vault are both up)
#   ./scripts/seed-unifi-to-vault.sh --seed \
#     --host 10.0.4.1 --api-key "<key>"
#
# What it discovers:
#   - switch_closet_mac      (device named "switch-01")
#   - switch_minilab_mac     (device named "switch-02")
#   - switch_rackmate_mac    (device named "switch-03")
#   - switch_pro_xg8_mac     (device named "switch-04")
#   - default_lan_network_id (network named "Default")
#
# What it seeds into Vault (--seed mode):
#   secret/infra/unifi → all of the above + api_url + api_key
# =============================================================================

set -euo pipefail

# --- Argument parsing ---
MODE=""
HOST="10.0.4.1"
API_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --discover) MODE="discover"; shift ;;
    --seed)     MODE="seed"; shift ;;
    --host)     HOST="$2"; shift 2 ;;
    --api-key)  API_KEY="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [ -z "$MODE" ]; then
  echo "Usage: $0 --discover|--seed --host <host> --api-key <key>"
  exit 1
fi

if [ -z "$API_KEY" ]; then
  echo "ERROR: --api-key is required"
  exit 1
fi

BASE_URL="https://${HOST}/proxy/network/api/s/default"

# --- Discover devices ---
echo "Querying ${HOST} for adopted devices..." >&2
DEVICES=$(curl -sk -H "X-API-KEY:${API_KEY}" "${BASE_URL}/rest/device" 2>/dev/null)

get_mac() {
  local name="$1"
  echo "$DEVICES" | jq -r ".data[] | select(.name==\"${name}\") | .mac // empty"
}

CLOSET_MAC=$(get_mac "switch-01")
MINILAB_MAC=$(get_mac "switch-02")
RACKMATE_MAC=$(get_mac "switch-03")
PRO_XG8_MAC=$(get_mac "switch-04")

# --- Discover Default LAN network ID ---
echo "Querying ${HOST} for Default LAN network ID..." >&2
NETWORKS=$(curl -sk -H "X-API-KEY:${API_KEY}" "${BASE_URL}/rest/networkconf" 2>/dev/null)
DEFAULT_LAN_ID=$(echo "$NETWORKS" | jq -r '.data[] | select(.name=="Default") | ._id // empty')

# --- Validate ---
echo "" >&2
echo "Discovered values:" >&2
echo "  switch_closet_mac      = ${CLOSET_MAC:-NOT FOUND}" >&2
echo "  switch_minilab_mac     = ${MINILAB_MAC:-NOT FOUND}" >&2
echo "  switch_rackmate_mac    = ${RACKMATE_MAC:-NOT FOUND}" >&2
echo "  switch_pro_xg8_mac     = ${PRO_XG8_MAC:-(not adopted yet)}" >&2
echo "  default_lan_network_id = ${DEFAULT_LAN_ID:-NOT FOUND}" >&2
echo "" >&2

# Fail if required values missing
if [ -z "$CLOSET_MAC" ] || [ -z "$MINILAB_MAC" ] || [ -z "$RACKMATE_MAC" ] || [ -z "$DEFAULT_LAN_ID" ]; then
  echo "ERROR: Required values missing. Are all switches adopted?" >&2
  exit 1
fi

if [ "$MODE" = "discover" ]; then
  # Output as Terraform -var flags (for copy-paste into bootstrap command)
  echo "# Terraform -var flags for bootstrap (use_vault=false):"
  echo "-var switch_closet_mac=\"${CLOSET_MAC}\""
  echo "-var switch_minilab_mac=\"${MINILAB_MAC}\""
  echo "-var switch_rackmate_mac=\"${RACKMATE_MAC}\""
  [ -n "$PRO_XG8_MAC" ] && echo "-var switch_pro_xg8_mac=\"${PRO_XG8_MAC}\""
  echo "-var default_lan_network_id=\"${DEFAULT_LAN_ID}\""

elif [ "$MODE" = "seed" ]; then
  # Verify Vault is reachable
  if ! vault status >/dev/null 2>&1; then
    echo "ERROR: Vault is not reachable. Set VAULT_ADDR + VAULT_TOKEN." >&2
    exit 1
  fi

  echo "Seeding secret/infra/unifi in Vault..." >&2

  # Build the JSON payload
  PAYLOAD=$(jq -n \
    --arg api_url "https://${HOST}" \
    --arg api_key "$API_KEY" \
    --arg default_lan_network_id "$DEFAULT_LAN_ID" \
    --arg switch_closet_mac "$CLOSET_MAC" \
    --arg switch_minilab_mac "$MINILAB_MAC" \
    --arg switch_rackmate_mac "$RACKMATE_MAC" \
    --arg switch_pro_xg8_mac "${PRO_XG8_MAC:-}" \
    '{
      api_url: $api_url,
      api_key: $api_key,
      default_lan_network_id: $default_lan_network_id,
      switch_closet_mac: $switch_closet_mac,
      switch_minilab_mac: $switch_minilab_mac,
      switch_rackmate_mac: $switch_rackmate_mac,
      switch_pro_xg8_mac: $switch_pro_xg8_mac
    }')

  vault kv put secret/infra/unifi - <<< "$PAYLOAD"

  echo "Vault secret/infra/unifi seeded successfully." >&2
  echo "" >&2
  echo "Verify: vault kv get secret/infra/unifi" >&2
fi
