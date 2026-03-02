#!/usr/bin/env bash
# =============================================================================
# 1Password → Vaultwarden Migration Script
# =============================================================================
# Imports 1Password vault exports (.1pux) into Vaultwarden using the
# Bitwarden CLI (`bw`). Pulls email and master password from HashiCorp
# Vault automatically — no manual credential entry.
#
# This is a ONE-TIME migration — re-importing creates duplicates
# (Bitwarden has no dedup/upsert logic).
#
# Prerequisites:
#   1. Export each 1Password vault as .1pux from the desktop app:
#      File > Export > Select vault > "1Password Unencrypted Export (.1pux)"
#      (There is no `op export` CLI command — must use the desktop app.)
#
#   2. Install the Bitwarden CLI:
#      brew install bitwarden-cli
#
#   3. Authenticate to Vault (VAULT_ADDR + VAULT_TOKEN must be set):
#      export VAULT_ADDR=https://10.0.10.10:8200
#      export VAULT_TOKEN=$(vault login -method=... -token-only)
#
#   4. Complete user registration at:
#      https://vaultwarden.home.example-lab.org/#/register
#      (use the exact invited email + master password from Vault)
#
# Usage:
#   ./vaultwarden-import-1password.sh <user> /path/to/export1.1pux [export2.1pux ...]
#
#   <user> is "admin" or "user" — maps to Vault fields:
#     admin → admin_email + admin_master_password
#     user → user_email + user_master_password
#
# Example:
#   ./vaultwarden-import-1password.sh admin ~/Desktop/Personal.1pux
#
# What this does NOT handle:
#   - Attachments: The Bitwarden importer ignores files embedded in .1pux.
#     If you need attachments, extract the .1pux (it's a ZIP), find files
#     in the files/ directory, and upload via: bw create attachment --file <f> --itemid <id>
#   - Ongoing sync: This is a one-time import. No incremental sync exists.
#   - Deduplication: Running this twice WILL create duplicate entries.
# =============================================================================
set -euo pipefail

VAULTWARDEN_URL="https://vaultwarden.home.example-lab.org"
VAULT_SECRET_PATH="secret/services/vaultwarden"

# ---------------------------------------------------------------------------
# Argument handling
# ---------------------------------------------------------------------------
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <user> <export1.1pux> [export2.1pux ...]"
    echo ""
    echo "  <user>  admin or user (pulls creds from Vault automatically)"
    echo ""
    echo "Export .1pux files from 1Password 8 desktop app first."
    exit 1
fi

USER_NAME="$1"
shift
EXPORT_FILES=("$@")

# ---------------------------------------------------------------------------
# Validate user argument
# ---------------------------------------------------------------------------
case "$USER_NAME" in
    admin|user)
        EMAIL_FIELD="${USER_NAME}_email"
        PASS_FIELD="${USER_NAME}_master_password"
        ;;
    *)
        echo "ERROR: Unknown user '${USER_NAME}'. Must be 'admin' or 'user'."
        exit 1
        ;;
esac

# Validate export files exist
for f in "${EXPORT_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: Export file not found: $f"
        exit 1
    fi
    if [[ ! "$f" == *.1pux ]]; then
        echo "WARNING: $f does not have .1pux extension — are you sure this is a 1Password export?"
    fi
done

# ---------------------------------------------------------------------------
# Check dependencies
# ---------------------------------------------------------------------------
if ! command -v bw &>/dev/null; then
    echo "ERROR: Bitwarden CLI (bw) not found."
    echo "Install: brew install bitwarden-cli"
    exit 1
fi

if ! command -v vault &>/dev/null; then
    echo "ERROR: HashiCorp Vault CLI not found."
    exit 1
fi

# ---------------------------------------------------------------------------
# Pull credentials from Vault
# ---------------------------------------------------------------------------
echo "[1/4] Reading credentials from Vault..."

if [[ -z "${VAULT_ADDR:-}" ]]; then
    echo "ERROR: VAULT_ADDR not set. Run: export VAULT_ADDR=https://10.0.10.10:8200"
    exit 1
fi

EMAIL=$(vault kv get -mount=secret -field="$EMAIL_FIELD" services/vaultwarden 2>/dev/null) || {
    echo "ERROR: Failed to read ${EMAIL_FIELD} from Vault at ${VAULT_SECRET_PATH}"
    echo "Have you run 'terraform apply' on Layer 02-vault-config?"
    exit 1
}

MASTER_PASSWORD=$(vault kv get -mount=secret -field="$PASS_FIELD" services/vaultwarden 2>/dev/null) || {
    echo "ERROR: Failed to read ${PASS_FIELD} from Vault at ${VAULT_SECRET_PATH}"
    exit 1
}

echo "  User:  ${USER_NAME}"
echo "  Email: ${EMAIL}"
echo "  Pass:  ******* (from Vault)"

echo ""
echo "============================================"
echo "1Password → Vaultwarden Import"
echo "============================================"
echo "Server:  ${VAULTWARDEN_URL}"
echo "Account: ${EMAIL}"
echo "Files:   ${#EXPORT_FILES[@]} export(s)"
for f in "${EXPORT_FILES[@]}"; do
    echo "  - $(basename "$f")"
done
echo "============================================"
echo ""

# ---------------------------------------------------------------------------
# Configure and authenticate
# ---------------------------------------------------------------------------
# Always start clean — bw config fails if a session exists, and stale
# sessions from a different server cause cryptic errors.
echo "[2/4] Configuring Bitwarden CLI for Vaultwarden..."
BW_STATUS=$(bw status 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unauthenticated'))" 2>/dev/null || echo "unauthenticated")

if [[ "$BW_STATUS" != "unauthenticated" ]]; then
    echo "  Logging out of existing session..."
    bw logout 2>/dev/null || true
fi
bw config server "$VAULTWARDEN_URL"

echo "[3/4] Logging in (non-interactive, creds from Vault)..."
export BW_SESSION
BW_SESSION=$(bw login "$EMAIL" "$MASTER_PASSWORD" --raw 2>&1) || {
    echo "ERROR: Failed to login to Vaultwarden."
    echo "  - Is the user registered? Go to: ${VAULTWARDEN_URL}/#/register"
    echo "  - Did you use the exact email and master password from Vault?"
    exit 1
}

if [[ -z "$BW_SESSION" ]]; then
    echo "ERROR: Login returned empty session. Check credentials."
    exit 1
fi
echo "  Logged in and unlocked."

# ---------------------------------------------------------------------------
# Import each export file
# ---------------------------------------------------------------------------
echo "[4/4] Importing 1Password exports..."
echo ""

TOTAL=0
FAILED=0

for f in "${EXPORT_FILES[@]}"; do
    echo "  Importing: $(basename "$f")"
    if bw import 1password1pux "$f" --session "$BW_SESSION" 2>&1; then
        echo "  ✓ Success: $(basename "$f")"
        ((TOTAL++))
    else
        echo "  ✗ FAILED: $(basename "$f")"
        ((FAILED++))
    fi
    echo ""
done

# ---------------------------------------------------------------------------
# Verify and report
# ---------------------------------------------------------------------------
bw sync --session "$BW_SESSION" 2>/dev/null

ITEM_COUNT=$(bw list items --session "$BW_SESSION" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "unknown")

echo "============================================"
echo "Import Complete"
echo "============================================"
echo "Files imported: ${TOTAL}"
echo "Files failed:   ${FAILED}"
echo "Total items in Vaultwarden: ${ITEM_COUNT}"
echo ""
echo "Next steps:"
echo "  1. Verify items at: ${VAULTWARDEN_URL}"
echo "  2. Check for any missing items or formatting issues"
echo "  3. Securely delete the .1pux export files:"
echo "     rm -P ${EXPORT_FILES[*]}"
echo "  4. Attachments are NOT imported — see script header for manual process"
echo "============================================"

# Lock the vault and clear password from memory
unset MASTER_PASSWORD
bw lock --session "$BW_SESSION" 2>/dev/null || true
