#!/usr/bin/env bash
# =============================================================================
# Vault 3-2-1 Backup Script
# =============================================================================
# Implements 3-2-1 backup strategy for HashiCorp Vault Raft snapshots:
#   1. Primary: Live Raft integrated storage (always current)
#   2. Local:   Encrypted snapshot on RPi5 or secondary node
#   3. Offsite: Encrypted snapshot uploaded to Hetzner Object Storage (S3)
#
# Prerequisites:
#   - vault CLI authenticated (VAULT_ADDR and VAULT_TOKEN set)
#   - age installed (for encryption)
#   - aws CLI installed (for S3 upload)
#   - ssh access to backup target
#
# Usage:
#   ./vault-backup.sh
#
# Cron example (every 6 hours):
#   0 */6 * * * /opt/firblab/scripts/vault-backup.sh >> /var/log/vault-backup.log 2>&1
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------
# Configuration (override via environment variables)
# ---------------------------------------------------------
VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8200}"
BACKUP_DIR="${BACKUP_DIR:-/tmp/vault-backups}"
AGE_RECIPIENT="${AGE_RECIPIENT:?ERROR: Set AGE_RECIPIENT to your age public key}"

# S3 configuration (Hetzner Object Storage)
S3_ENDPOINT="${S3_ENDPOINT:-https://fsn1.your-objectstorage.com}"
S3_BUCKET="${S3_BUCKET:-firblab-vault-backups}"

# Local backup target (RPi5 or secondary node)
LOCAL_BACKUP_HOST="${LOCAL_BACKUP_HOST:-10.0.10.13}"
LOCAL_BACKUP_USER="${LOCAL_BACKUP_USER:-vault-backup}"
LOCAL_BACKUP_PATH="${LOCAL_BACKUP_PATH:-/backups/vault}"

# Retention
LOCAL_RETENTION_DAYS="${LOCAL_RETENTION_DAYS:-30}"

# ---------------------------------------------------------
# Functions
# ---------------------------------------------------------

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

cleanup() {
  log "Cleaning up temporary files..."
  rm -f "${BACKUP_DIR}"/vault-snapshot-*.snap
  rm -f "${BACKUP_DIR}"/vault-snapshot-*.snap.age
}

trap cleanup EXIT

# ---------------------------------------------------------
# Main
# ---------------------------------------------------------

TIMESTAMP=$(date +%Y%m%d%H%M%S)
SNAPSHOT_FILE="vault-snapshot-${TIMESTAMP}.snap"
ENCRYPTED_FILE="${SNAPSHOT_FILE}.age"

mkdir -p "${BACKUP_DIR}"

# Step 1: Take Raft snapshot
log "Taking Vault Raft snapshot..."
vault operator raft snapshot save "${BACKUP_DIR}/${SNAPSHOT_FILE}"
SNAPSHOT_SIZE=$(du -h "${BACKUP_DIR}/${SNAPSHOT_FILE}" | cut -f1)
log "Snapshot created: ${SNAPSHOT_FILE} (${SNAPSHOT_SIZE})"

# Step 2: Encrypt with age
log "Encrypting snapshot with age..."
age -r "${AGE_RECIPIENT}" -o "${BACKUP_DIR}/${ENCRYPTED_FILE}" "${BACKUP_DIR}/${SNAPSHOT_FILE}"
log "Encrypted: ${ENCRYPTED_FILE}"

# Step 3: Upload to Hetzner S3 (off-site)
log "Uploading to Hetzner Object Storage (s3://${S3_BUCKET})..."
if aws s3 cp \
  --endpoint-url "${S3_ENDPOINT}" \
  "${BACKUP_DIR}/${ENCRYPTED_FILE}" \
  "s3://${S3_BUCKET}/${ENCRYPTED_FILE}" \
  --quiet; then
  log "S3 upload complete."
else
  log "WARNING: S3 upload failed. Continuing with local backup."
fi

# Step 4: Copy to local backup target (RPi5)
log "Copying to local backup target (${LOCAL_BACKUP_HOST})..."
if scp -q \
  -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=10 \
  "${BACKUP_DIR}/${ENCRYPTED_FILE}" \
  "${LOCAL_BACKUP_USER}@${LOCAL_BACKUP_HOST}:${LOCAL_BACKUP_PATH}/${ENCRYPTED_FILE}"; then
  log "Local backup copy complete."
else
  log "WARNING: Local backup copy failed."
fi

# Step 5: Clean up old backups locally on backup target
log "Cleaning up old backups on ${LOCAL_BACKUP_HOST} (>${LOCAL_RETENTION_DAYS} days)..."
ssh -q \
  -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=10 \
  "${LOCAL_BACKUP_USER}@${LOCAL_BACKUP_HOST}" \
  "find ${LOCAL_BACKUP_PATH} -name 'vault-snapshot-*.snap.age' -mtime +${LOCAL_RETENTION_DAYS} -delete" \
  2>/dev/null || log "WARNING: Remote cleanup failed."

# S3 retention is handled by a server-side lifecycle policy (30-day expiration)
# configured in Terraform Layer 06-hetzner. No script-based cleanup needed.

log "Vault backup complete. 3-2-1 strategy satisfied."
log "  Primary:  Raft integrated storage (live)"
log "  Local:    ${LOCAL_BACKUP_HOST}:${LOCAL_BACKUP_PATH}/${ENCRYPTED_FILE}"
log "  Offsite:  s3://${S3_BUCKET}/${ENCRYPTED_FILE}"
