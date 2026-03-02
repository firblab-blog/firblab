#!/bin/bash
# =============================================================================
# UDM Pro Settings Export — Pre-Migration Dump
# =============================================================================
# Exports ALL UDM Pro settings via the UniFi REST API to a single JSON file.
# Run this BEFORE decommissioning or migrating to a new gateway.
#
# Captures everything Terraform does NOT manage:
#   - WAN configuration, IDS/IPS, auto-updates, site settings
#   - DHCP reservations, DNS servers, WiFi SSIDs
#   - All network configs, device info, routing rules
#
# Usage:
#   export UDM_API_KEY="<your-api-key>"
#   ./scripts/udm-pro-export.sh [host] [output_dir]
#
# Output: udm-pro-export-<timestamp>.json in the specified directory
# =============================================================================

set -euo pipefail

UDM_HOST="${1:-10.0.4.1}"
OUTPUT_DIR="${2:-.}"
API_KEY="${UDM_API_KEY:-}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
EXPORT_FILE="${OUTPUT_DIR}/udm-pro-export-${TIMESTAMP}.json"

if [ -z "$API_KEY" ]; then
  echo "ERROR: UDM_API_KEY environment variable not set"
  echo "Usage: UDM_API_KEY=<key> $0 [host] [output_dir]"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

BASE_URL="https://${UDM_HOST}/proxy/network/api/s/default"
CURL="curl -sk -H X-API-KEY:${API_KEY}"

echo "Exporting UDM Pro settings from ${UDM_HOST}..."

# Endpoint names and paths (parallel arrays — bash 3.2 compatible)
KEYS="site_settings networks wlans devices firewall_rules firewall_groups routing port_forward dns_records dhcp_reservations"
get_path() {
  case "$1" in
    site_settings)      echo "/rest/setting" ;;
    networks)           echo "/rest/networkconf" ;;
    wlans)              echo "/rest/wlanconf" ;;
    devices)            echo "/rest/device" ;;
    firewall_rules)     echo "/rest/firewallrule" ;;
    firewall_groups)    echo "/rest/firewallgroup" ;;
    routing)            echo "/rest/routing" ;;
    port_forward)       echo "/rest/portforward" ;;
    dns_records)        echo "/rest/dnsrecord" ;;
    dhcp_reservations)  echo "/rest/fixedip" ;;
  esac
}

JSON_PARTS="{"
FIRST=true

for key in $KEYS; do
  path=$(get_path "$key")
  echo "  Fetching ${key}..."
  RESPONSE=$($CURL "${BASE_URL}${path}" 2>/dev/null || echo '{"data":[]}')

  if [ "$FIRST" = true ]; then
    FIRST=false
  else
    JSON_PARTS="${JSON_PARTS},"
  fi
  JSON_PARTS="${JSON_PARTS}\"${key}\":${RESPONSE}"
done

JSON_PARTS="${JSON_PARTS}}"

echo "$JSON_PARTS" | jq '.' > "$EXPORT_FILE"

echo ""
echo "Export complete: ${EXPORT_FILE}"
echo "Size: $(wc -c < "$EXPORT_FILE" | tr -d ' ') bytes"
echo ""
echo "Key settings to review before migration:"
echo "  WAN config:     jq '.networks.data[] | select(.purpose==\"wan\")' ${EXPORT_FILE}"
echo "  Default LAN:    jq '.networks.data[] | select(.name==\"Default\")' ${EXPORT_FILE}"
echo "  DHCP DNS:       jq '.networks.data[] | {name, dhcpdv4_dns}' ${EXPORT_FILE}"
echo "  IDS/IPS:        jq '.site_settings.data[] | select(.key==\"ips\")' ${EXPORT_FILE}"
echo "  Auto-updates:   jq '.site_settings.data[] | select(.key==\"auto_speedtest\") // \"check mgmt key\"' ${EXPORT_FILE}"
echo "  WiFi SSIDs:     jq '.wlans.data[] | {name, security}' ${EXPORT_FILE}"
echo "  Site info:      jq '.site_settings.data[] | select(.key==\"mgmt\")' ${EXPORT_FILE}"
