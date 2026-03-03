#!/usr/bin/env bash
# =============================================================================
# Packer Build Script — Vault-Backed Template Builder
# =============================================================================
# Builds hardened VM templates on Proxmox using Packer, with Proxmox API
# credentials sourced from Vault automatically.
#
# Prerequisites:
#   - Vault running and accessible (VAULT_ADDR, VAULT_TOKEN or ~/.vault-token)
#   - VAULT_CACERT set (or defaults to ~/.lab/tls/ca/ca.pem)
#   - ISOs downloaded to Proxmox local:iso/ (automated by Layer 01)
#   - packer >= 1.11 installed
#   - Proxmox API token with TerraformProv role (includes VM.GuestAgent.Audit for IP discovery)
#
# Each template lives in its own subdirectory under packer/ to avoid
# Packer's "all .pkr.hcl files in a directory" merging behavior.
#
# Usage:
#   ./scripts/packer-build.sh                                   # Ubuntu on lab-02 (local-lvm)
#   ./scripts/packer-build.sh lab-02                        # Ubuntu on lab-02 (local-lvm)
#   ./scripts/packer-build.sh lab-02 ubuntu-24.04           # Ubuntu on lab-02 (local-lvm)
#   ./scripts/packer-build.sh lab-02 rocky-9                # Rocky on lab-02 (local-lvm)
#   ./scripts/packer-build.sh lab-02 rocky-9 ssd-thin-0     # Rocky on specific storage pool
#
# Vault secret path: secret/infra/proxmox/<node>
#   Fields: url, token_id, token_secret
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PACKER_DIR="${PROJECT_ROOT}/packer"

# Arguments
NODE="${1:-lab-02}"
TEMPLATE_NAME="${2:-ubuntu-24.04}"
STORAGE_POOL="${3:-}"   # Optional: override Packer default storage pool (local-lvm)

# Resolve template directory and file
TEMPLATE_DIR="${PACKER_DIR}/${TEMPLATE_NAME}"

if [ ! -d "${TEMPLATE_DIR}" ]; then
  echo "ERROR: Packer template directory not found: ${TEMPLATE_DIR}"
  echo ""
  echo "Available templates:"
  for dir in "${PACKER_DIR}"/*/; do
    [ -d "$dir" ] && [ "$(basename "$dir")" != "http" ] && echo "  $(basename "$dir")"
  done
  exit 1
fi

# Find the .pkr.hcl file in the template directory
TEMPLATE_FILE=$(find "${TEMPLATE_DIR}" -maxdepth 1 -name "*.pkr.hcl" | head -1)
if [ -z "${TEMPLATE_FILE}" ]; then
  echo "ERROR: No .pkr.hcl file found in ${TEMPLATE_DIR}"
  exit 1
fi

# ---------------------------------------------------------
# Vault Configuration
# ---------------------------------------------------------

export VAULT_ADDR="${VAULT_ADDR:-https://10.0.10.10:8200}"
export VAULT_CACERT="${VAULT_CACERT:-$HOME/.lab/tls/ca/ca.pem}"

# Resolve token: env var → ~/.vault-token
if [ -z "${VAULT_TOKEN:-}" ] && [ -f "$HOME/.vault-token" ]; then
  export VAULT_TOKEN
  VAULT_TOKEN="$(cat "$HOME/.vault-token")"
fi

if [ -z "${VAULT_TOKEN:-}" ]; then
  echo "ERROR: VAULT_TOKEN not set and ~/.vault-token not found"
  echo ""
  echo "Set your token:"
  echo "  export VAULT_TOKEN=\$(cat ~/.vault-token)"
  echo ""
  echo "Or for bootstrap (no Vault), use manual mode:"
  echo "  cd packer/${TEMPLATE_NAME} && packer build -var-file=../credentials.pkr.hcl ."
  exit 1
fi

# Validate CA cert exists
if [ ! -f "${VAULT_CACERT}" ]; then
  echo "WARNING: Vault CA cert not found at ${VAULT_CACERT}"
  echo "         Set VAULT_CACERT or VAULT_SKIP_VERIFY=true"
fi

# ---------------------------------------------------------
# Vault Connectivity Check
# ---------------------------------------------------------

echo "Vault:    ${VAULT_ADDR}"
echo "Node:     ${NODE}"
echo "Template: ${TEMPLATE_NAME}"
echo ""

if ! vault token lookup > /dev/null 2>&1; then
  echo "ERROR: Cannot connect to Vault at ${VAULT_ADDR}"
  echo "       Check VAULT_ADDR, VAULT_TOKEN, and VAULT_CACERT"
  exit 1
fi

echo "Vault connection verified."

# ---------------------------------------------------------
# Extract Proxmox Credentials from Vault
# ---------------------------------------------------------

VAULT_SECRET_PATH="secret/infra/proxmox/${NODE}"

echo "Reading credentials from: ${VAULT_SECRET_PATH}"

PROXMOX_BASE_URL="$(vault kv get -field=url "${VAULT_SECRET_PATH}")"
PROXMOX_TOKEN_ID="$(vault kv get -field=token_id "${VAULT_SECRET_PATH}")"
PROXMOX_TOKEN_SECRET="$(vault kv get -field=token_secret "${VAULT_SECRET_PATH}")"

if [ -z "${PROXMOX_BASE_URL}" ] || [ -z "${PROXMOX_TOKEN_ID}" ] || [ -z "${PROXMOX_TOKEN_SECRET}" ]; then
  echo "ERROR: Failed to read credentials from Vault at ${VAULT_SECRET_PATH}"
  echo "       Ensure the secret exists with fields: url, token_id, token_secret"
  exit 1
fi

# Packer's Proxmox plugin (Telmate) requires the full API path including /api2/json.
# Vault stores the base URL (e.g., https://10.0.10.2:8006) which works for the
# bpg/proxmox Terraform provider. Append /api2/json for Packer compatibility.
PROXMOX_URL="${PROXMOX_BASE_URL%/}/api2/json"

echo "Credentials loaded for: ${PROXMOX_URL}"
echo ""

# ---------------------------------------------------------
# Build Packer Template
# ---------------------------------------------------------

echo "=========================================="
echo "  Building Packer Template"
echo "  Template: ${TEMPLATE_NAME}"
echo "  Node:     ${NODE}"
echo "  Storage:  ${STORAGE_POOL:-local-lvm (default)}"
echo "  File:     $(basename "${TEMPLATE_FILE}")"
echo "=========================================="
echo ""

cd "${TEMPLATE_DIR}"

# Initialize Packer plugins
packer init .

# Build with optional storage pool override
STORAGE_ARGS=()
if [ -n "${STORAGE_POOL}" ]; then
  STORAGE_ARGS+=(-var "storage_pool=${STORAGE_POOL}")
fi

# Build the template (PACKER_LOG=1 shows SSH host resolution and connection attempts)
export PACKER_LOG=1
packer build \
  -var "proxmox_url=${PROXMOX_URL}" \
  -var "proxmox_token_id=${PROXMOX_TOKEN_ID}" \
  -var "proxmox_token_secret=${PROXMOX_TOKEN_SECRET}" \
  -var "proxmox_node=${NODE}" \
  ${STORAGE_ARGS[@]+"${STORAGE_ARGS[@]}"} \
  .

echo ""
echo "=========================================="
echo "  Build Complete!"
echo "  Template should be visible in Proxmox UI"
echo "=========================================="
