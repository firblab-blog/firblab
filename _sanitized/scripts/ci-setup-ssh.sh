#!/usr/bin/env bash
# =============================================================================
# CI SSH Key Setup — FirbLab GitLab CI/CD
# =============================================================================
# Fetches SSH private keys from Vault and writes them to the filesystem paths
# that ansible/inventory/hosts.yml expects. Called from the .ansible-auto-deploy
# CI template's before_script.
#
# How it works:
#   1. Reads the SSH_HOSTS env var (comma-separated list of Vault hostnames)
#   2. For each host, fetches secret/compute/<host> from Vault via API
#   3. Writes the key to the exact path the Ansible inventory expects
#   4. Creates a symlink so ~/repos/firb-lab/firblab → $CI_PROJECT_DIR
#      (inventory uses absolute paths with ~ expansion)
#
# Required env vars:
#   VAULT_ADDR      — Vault API URL (e.g., https://10.0.10.10:8200)
#   VAULT_TOKEN     — Short-lived token from AppRole login
#   VAULT_CACERT    — Path to CA cert file
#   SSH_HOSTS       — Comma-separated hostnames (e.g., "lab-01,ghost")
#   CI_PROJECT_DIR  — GitLab CI workspace (set automatically by Runner)
#
# Security:
#   - Keys are written with 0600 permissions
#   - Only the keys listed in SSH_HOSTS are fetched (least privilege)
#   - after_script in the CI template cleans up keys when the job finishes
# =============================================================================

set -euo pipefail

VAULT_API="${VAULT_ADDR}/v1/secret/data/compute"
SSH_DIR="$HOME/.ssh"

# ---------------------------------------------------------------------------
# Setup directories
# ---------------------------------------------------------------------------
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Create repo path symlink so inventory ~ paths resolve in the CI container.
# Inventory references: ~/repos/firb-lab/firblab/terraform/layers/.../.secrets/
mkdir -p "$HOME/repos/firb-lab"
ln -sf "${CI_PROJECT_DIR}" "$HOME/repos/firb-lab/firblab"

# Also create .secrets/ directories that Terraform keys expect
mkdir -p "${CI_PROJECT_DIR}/terraform/layers/03-core-infra/.secrets"
mkdir -p "${CI_PROJECT_DIR}/terraform/layers/04-rke2-cluster/.secrets"
mkdir -p "${CI_PROJECT_DIR}/terraform/layers/05-standalone-services/.secrets"

# ---------------------------------------------------------------------------
# Vault hostname → filesystem path mapping
# MUST match ansible/inventory/hosts.yml exactly
# ---------------------------------------------------------------------------
declare -A KEY_PATHS=(
  # --- Manual keys (in ~/.ssh/) ---
  # Proxmox hypervisors
  ["lab-01"]="${SSH_DIR}/id_ed25519_lab-01"
  ["lab-02"]="${SSH_DIR}/id_ed25519_lab-02"
  ["lab-03"]="${SSH_DIR}/id_ed25519_lab-03"
  ["lab-04"]="${SSH_DIR}/id_ed25519_lab-04"
  # Vault cluster
  ["vault-1"]="${SSH_DIR}/id_ed25519_lab-macmini"
  ["vault-2"]="${SSH_DIR}/id_ed25519_vault-2"
  ["vault-3"]="${SSH_DIR}/id_ed25519_lab-rpi5"
  # Bare-metal / standalone
  ["lab-08"]="${SSH_DIR}/id_ed25519_lab-08"
  ["archive"]="${SSH_DIR}/id_ed25519_archive"
  # Hetzner
  ["lab-hetzner"]="${SSH_DIR}/id_ed25519_lab-hetzner"

  # --- Terraform-generated keys (Layer 03 — core-infra) ---
  ["gitlab"]="${SSH_DIR}/id_ed25519_gitlab"
  ["gitlab-runner"]="${SSH_DIR}/id_ed25519_gitlab-runner"

  # --- Terraform-generated keys (Layer 04 — rke2-cluster) ---
  ["rke2-server-1"]="${CI_PROJECT_DIR}/terraform/layers/04-rke2-cluster/.secrets/rke2-server-1_ssh_key"
  ["rke2-server-2"]="${CI_PROJECT_DIR}/terraform/layers/04-rke2-cluster/.secrets/rke2-server-2_ssh_key"
  ["rke2-server-3"]="${CI_PROJECT_DIR}/terraform/layers/04-rke2-cluster/.secrets/rke2-server-3_ssh_key"
  ["rke2-agent-1"]="${CI_PROJECT_DIR}/terraform/layers/04-rke2-cluster/.secrets/rke2-agent-1_ssh_key"
  ["rke2-agent-2"]="${CI_PROJECT_DIR}/terraform/layers/04-rke2-cluster/.secrets/rke2-agent-2_ssh_key"
  ["rke2-agent-3"]="${CI_PROJECT_DIR}/terraform/layers/04-rke2-cluster/.secrets/rke2-agent-3_ssh_key"

  # --- Terraform-generated keys (Layer 05 — standalone-services) ---
  ["ghost"]="${CI_PROJECT_DIR}/terraform/layers/05-standalone-services/.secrets/ghost_ssh_key"
  ["foundryvtt"]="${CI_PROJECT_DIR}/terraform/layers/05-standalone-services/.secrets/foundryvtt_ssh_key"
  ["roundcube"]="${CI_PROJECT_DIR}/terraform/layers/05-standalone-services/.secrets/roundcube_ssh_key"
  ["mealie"]="${CI_PROJECT_DIR}/terraform/layers/05-standalone-services/.secrets/mealie_ssh_key"
  ["wireguard"]="${CI_PROJECT_DIR}/terraform/layers/05-standalone-services/.secrets/wireguard_ssh_key"
  ["netbox"]="${CI_PROJECT_DIR}/terraform/layers/05-standalone-services/.secrets/netbox_ssh_key"
  ["pbs"]="${CI_PROJECT_DIR}/terraform/layers/05-standalone-services/.secrets/pbs_ssh_key"
  ["authentik"]="${CI_PROJECT_DIR}/terraform/layers/05-standalone-services/.secrets/authentik_ssh_key"
  ["patchmon"]="${CI_PROJECT_DIR}/terraform/layers/05-standalone-services/.secrets/patchmon_ssh_key"
  ["actualbudget"]="${CI_PROJECT_DIR}/terraform/layers/05-standalone-services/.secrets/actualbudget_ssh_key"
  ["traefik-proxy"]="${CI_PROJECT_DIR}/terraform/layers/05-standalone-services/.secrets/traefik-proxy_ssh_key"
  ["vaultwarden"]="${CI_PROJECT_DIR}/terraform/layers/05-standalone-services/.secrets/vaultwarden_ssh_key"
  ["backup"]="${CI_PROJECT_DIR}/terraform/layers/05-standalone-services/.secrets/backup_ssh_key"
)

# ---------------------------------------------------------------------------
# Fetch requested keys from Vault (with retry for transient failures)
# ---------------------------------------------------------------------------
if [[ -z "${SSH_HOSTS:-}" ]]; then
  echo "ERROR: SSH_HOSTS env var not set"
  exit 1
fi

MAX_RETRIES=3

fetch_key() {
  local host="$1" dest="$2"
  local attempt http_code body

  for attempt in $(seq 1 "$MAX_RETRIES"); do
    # Capture HTTP status code separately from response body
    http_code=$(curl -s --cacert "$VAULT_CACERT" \
      -H "X-Vault-Token: $VAULT_TOKEN" \
      -o "$dest.tmp" -w '%{http_code}' \
      "${VAULT_API}/${host}" 2>/dev/null) || http_code="000"

    if [[ "$http_code" == "200" ]]; then
      # Extract ssh_private_key from JSON response
      if jq -r '.data.data.ssh_private_key' < "$dest.tmp" > "$dest" 2>/dev/null; then
        rm -f "$dest.tmp"
        return 0
      fi
      echo "  WARN: Vault returned 200 for '${host}' but jq failed to parse response"
      cat "$dest.tmp" >&2
    fi

    rm -f "$dest.tmp" "$dest"
    if [[ "$attempt" -lt "$MAX_RETRIES" ]]; then
      echo "  WARN: Vault fetch for '${host}' failed (HTTP ${http_code}), retry ${attempt}/${MAX_RETRIES}..."
      sleep "$((attempt * 2))"
    fi
  done

  echo "ERROR: Failed to fetch SSH key for '${host}' from Vault after ${MAX_RETRIES} attempts (HTTP ${http_code})"
  return 1
}

FETCHED=0
IFS=',' read -ra HOSTS <<< "$SSH_HOSTS"
for host in "${HOSTS[@]}"; do
  host=$(echo "$host" | xargs)  # trim whitespace

  dest="${KEY_PATHS[$host]:-}"
  if [[ -z "$dest" ]]; then
    echo "ERROR: No key path mapping for host '${host}'"
    echo "  Add it to KEY_PATHS in scripts/ci-setup-ssh.sh"
    exit 1
  fi

  mkdir -p "$(dirname "$dest")"

  if ! fetch_key "$host" "$dest"; then
    exit 1
  fi

  chmod 600 "$dest"
  echo "  SSH key: ${host} → $(basename "$dest")"
  ((FETCHED++)) || true
done

echo "Fetched ${FETCHED} SSH key(s) from Vault."
