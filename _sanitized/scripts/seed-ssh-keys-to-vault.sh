#!/usr/bin/env bash
# =============================================================================
# Seed SSH Keys to Vault — FirbLab Infrastructure
# =============================================================================
# One-time script to populate secret/compute/<hostname> in Vault with SSH
# private keys for hosts NOT managed by Terraform (Proxmox nodes, Vault cluster,
# bare-metal devices, Hetzner cloud server).
#
# Terraform-managed hosts (Layers 03/04/05) have their keys written to Vault
# automatically via vault_kv_secret_v2 resources. This script covers the rest.
#
# Prerequisites:
#   - Vault CLI authenticated (VAULT_ADDR, VAULT_TOKEN set)
#   - SSH key files exist at the expected paths on this workstation
#   - Layer 02-vault-config applied (gitlab-ci policy includes compute/*)
#
# Usage:
#   export VAULT_ADDR=https://10.0.10.10:8200
#   export VAULT_TOKEN=<your-token>
#   export VAULT_CACERT=~/.lab/tls/ca/ca.pem
#   ./scripts/seed-ssh-keys-to-vault.sh
#
# Idempotent: Safe to re-run. Overwrites existing secrets with current keys.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Hostname → SSH key path mappings
# These are hosts with manually-managed keys (not Terraform-generated).
# ---------------------------------------------------------------------------
HOSTS=(
  # Proxmox hypervisors (VLAN 10)
  "lab-01:~/.ssh/id_ed25519_lab-01"
  "lab-02:~/.ssh/id_ed25519_lab-02"
  "lab-03:~/.ssh/id_ed25519_lab-03"
  "lab-04:~/.ssh/id_ed25519_lab-04"
  # Vault cluster
  "vault-1:~/.ssh/id_ed25519_lab-macmini"
  "vault-2:~/.ssh/id_ed25519_vault-2"
  "vault-3:~/.ssh/id_ed25519_lab-rpi5"
  # Bare-metal / standalone
  "lab-08:~/.ssh/id_ed25519_lab-08"
  "archive:~/.ssh/id_ed25519_archive"
  # Hetzner cloud
  "lab-hetzner:~/.ssh/id_ed25519_lab-hetzner"
)

echo "=== Seed SSH Keys to Vault ==="
echo ""

SEEDED=0
ERRORS=0

for entry in "${HOSTS[@]}"; do
  hostname="${entry%%:*}"
  keypath="${entry##*:}"
  expanded=$(eval echo "$keypath")

  if [[ ! -f "$expanded" ]]; then
    echo "SKIP: $hostname — key not found at $expanded"
    continue
  fi

  if vault kv put -mount=secret "compute/$hostname" \
    ssh_private_key=@"$expanded" > /dev/null 2>&1; then
    echo "  OK: secret/compute/$hostname ← $keypath"
    ((SEEDED++)) || true
  else
    echo "ERROR: Failed to write secret/compute/$hostname"
    ((ERRORS++)) || true
  fi
done

echo ""
echo "Seeded $SEEDED keys to Vault."

if [[ $ERRORS -gt 0 ]]; then
  echo "FAILED: $ERRORS key(s) could not be written."
  exit 1
fi

echo ""
echo "Verify: vault kv list -mount=secret compute/"
echo "DONE."
