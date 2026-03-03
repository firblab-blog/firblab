#!/usr/bin/env bash
# =============================================================================
# Sync WireGuard Peer Configs from Hetzner S3 to Vault KV
# =============================================================================
# Downloads WireGuard peer configs from Hetzner Object Storage (S3) and
# stores them in Vault KV at secret/services/wireguard/<peer-name>.
#
# This script is meant to run AFTER the WireGuard tunnel is established
# (i.e., after wireguard-deploy.yml succeeds). Once the tunnel is up,
# Vault is reachable from the homelab, and peer configs should be synced
# to Vault for IaC/GitOps access.
#
# Each peer config is stored as a single KV secret with fields:
#   - config: full WireGuard config file contents
#   - synced_at: ISO 8601 timestamp of sync
#
# The server public key is stored at secret/services/wireguard/server.
#
# Prerequisites:
#   - vault CLI authenticated (VAULT_ADDR, VAULT_TOKEN, VAULT_CACERT set)
#   - aws CLI installed
#   - S3 credentials (from Vault or environment)
#
# Usage:
#   export VAULT_ADDR=https://10.0.10.10:8200
#   export VAULT_TOKEN=hvs.xxxxx
#   export VAULT_CACERT=~/.lab/tls/ca/ca.pem
#   ./sync-wg-peers-to-vault.sh
#
# Or with explicit S3 credentials:
#   S3_ACCESS_KEY=xxx S3_SECRET_KEY=xxx S3_ENDPOINT=region1.your-objectstorage.com \
#   S3_BUCKET=firblab-wireguard ./sync-wg-peers-to-vault.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------
# Configuration
# ---------------------------------------------------------
VAULT_MOUNT="${VAULT_MOUNT:-secret}"
VAULT_PATH_PREFIX="${VAULT_PATH_PREFIX:-services/wireguard}"
S3_BUCKET="${S3_BUCKET:-firblab-wireguard}"
TMPDIR_BASE="${TMPDIR:-/tmp}"
WORK_DIR=""

# ---------------------------------------------------------
# Cleanup trap
# ---------------------------------------------------------
cleanup() {
  if [[ -n "${WORK_DIR:-}" && -d "${WORK_DIR}" ]]; then
    rm -rf "${WORK_DIR}"
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------
# Resolve S3 credentials (Vault → env fallback)
# ---------------------------------------------------------
resolve_s3_credentials() {
  if [[ -n "${S3_ACCESS_KEY:-}" && -n "${S3_SECRET_KEY:-}" && -n "${S3_ENDPOINT:-}" && -n "${S3_BUCKET:-}" ]]; then
    echo "Using S3 credentials from environment"
    return
  fi

  echo "Reading S3 credentials from Vault (${VAULT_MOUNT}/infra/hetzner)..."
  local vault_json
  vault_json=$(vault kv get -mount="${VAULT_MOUNT}" -format=json infra/hetzner) || {
    echo "ERROR: Failed to read S3 credentials from Vault."
    echo "  Either set VAULT_ADDR/VAULT_TOKEN/VAULT_CACERT or provide S3_* env vars."
    exit 1
  }

  S3_ACCESS_KEY=$(echo "${vault_json}" | jq -r '.data.data.s3_access_key')
  S3_SECRET_KEY=$(echo "${vault_json}" | jq -r '.data.data.s3_secret_key')
  S3_ENDPOINT=$(echo "${vault_json}" | jq -r '.data.data.s3_endpoint')

  if [[ -z "${S3_ACCESS_KEY}" || -z "${S3_ENDPOINT}" ]]; then
    echo "ERROR: S3 credentials in Vault are empty. Seed them first:"
    echo "  vault kv patch -mount=secret infra/hetzner s3_access_key=... s3_secret_key=... s3_endpoint=..."
    exit 1
  fi
}

# ---------------------------------------------------------
# Main
# ---------------------------------------------------------
main() {
  echo "=== WireGuard Peer Config Sync: S3 → Vault ==="
  echo ""

  # Check prerequisites
  command -v vault >/dev/null 2>&1 || { echo "ERROR: vault CLI not found"; exit 1; }
  command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI not found"; exit 1; }
  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found"; exit 1; }

  # Resolve S3 credentials
  resolve_s3_credentials

  # Create temp working directory
  WORK_DIR=$(mktemp -d "${TMPDIR_BASE}/wg-sync-XXXXXX")
  chmod 700 "${WORK_DIR}"

  # Configure AWS CLI for Hetzner S3
  export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY}"
  export AWS_SECRET_ACCESS_KEY="${S3_SECRET_KEY}"
  export AWS_DEFAULT_REGION="eu-central-1"
  local S3_URL="https://${S3_ENDPOINT}"

  # Download all peer configs from S3
  echo "Downloading peer configs from s3://${S3_BUCKET}/peers/..."
  aws s3 sync "s3://${S3_BUCKET}/peers/" "${WORK_DIR}/peers/" --endpoint-url "${S3_URL}" --quiet || {
    echo "ERROR: Failed to download peer configs from S3."
    echo "  Check S3 credentials and bucket name."
    exit 1
  }

  # Count downloaded files
  local peer_count
  peer_count=$(find "${WORK_DIR}/peers/" -name "*.conf" 2>/dev/null | wc -l | tr -d ' ')
  echo "Downloaded ${peer_count} peer config(s)"

  if [[ "${peer_count}" -eq 0 ]]; then
    echo "WARNING: No peer configs found in S3. Has the Hetzner gateway been deployed?"
    exit 0
  fi

  # Sync server public key
  if [[ -f "${WORK_DIR}/peers/server_public_key" ]]; then
    local server_pubkey
    server_pubkey=$(cat "${WORK_DIR}/peers/server_public_key")
    echo "Syncing server public key to Vault..."
    vault kv put -mount="${VAULT_MOUNT}" "${VAULT_PATH_PREFIX}/server" \
      public_key="${server_pubkey}" \
      synced_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null
    echo "  → ${VAULT_MOUNT}/${VAULT_PATH_PREFIX}/server"
  fi

  # Sync each peer config
  for conf_file in "${WORK_DIR}/peers/"*.conf; do
    local peer_name
    peer_name=$(basename "${conf_file}" .conf)
    local config_content
    config_content=$(cat "${conf_file}")

    echo "Syncing ${peer_name} to Vault..."
    vault kv put -mount="${VAULT_MOUNT}" "${VAULT_PATH_PREFIX}/${peer_name}" \
      config="${config_content}" \
      synced_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null
    echo "  → ${VAULT_MOUNT}/${VAULT_PATH_PREFIX}/${peer_name}"
  done

  echo ""
  echo "=== Sync complete: ${peer_count} peer(s) synced to Vault ==="
  echo ""
  echo "Verify:"
  echo "  vault kv list -mount=${VAULT_MOUNT} ${VAULT_PATH_PREFIX}"
  echo "  vault kv get -mount=${VAULT_MOUNT} ${VAULT_PATH_PREFIX}/peer1"
}

main "$@"
