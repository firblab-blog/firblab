#!/usr/bin/env bash
# =============================================================================
# Home Assistant Config Sync
# =============================================================================
# Syncs HA configuration files from the firblab repo (homeassistant/) to the
# infrastructure/homeassistant GitLab repo. Reads the push token from Vault.
#
# Usage:
#   ./scripts/ha-config-sync.sh                    # auto-commit message
#   ./scripts/ha-config-sync.sh "custom message"   # custom commit message
#
# Prerequisites:
#   - vault CLI authenticated (VAULT_TOKEN set)
#   - Terraform Layer 03 applied (creates the push token)
#   - Vault CA cert at ~/.lab/tls/ca/ca.pem
#
# After pushing, run the Git Pull add-on on HAOS to sync to /config/.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HA_SOURCE="$REPO_ROOT/homeassistant"
WORK_DIR="$(mktemp -d)"
COMMIT_MSG="${1:-Sync HA config from firblab repo}"

# Vault config
export VAULT_ADDR="${VAULT_ADDR:-https://10.0.10.10:8200}"
export VAULT_CACERT="${VAULT_CACERT:-$HOME/.lab/tls/ca/ca.pem}"

# Verify source directory exists
if [ ! -d "$HA_SOURCE" ]; then
  echo "ERROR: $HA_SOURCE does not exist. Nothing to sync."
  exit 1
fi

# Get push URL from Vault
echo "Reading push token from Vault..."
REPO_URL="$(vault kv get -mount=secret -field=repo_url services/gitlab/homeassistant-push)"

if [ -z "$REPO_URL" ]; then
  echo "ERROR: Could not read repo_url from Vault (secret/services/gitlab/homeassistant-push)."
  echo "Has Terraform Layer 03 been applied?"
  exit 1
fi

# Clone, sync, push
echo "Cloning HA config repo..."
git clone --quiet "$REPO_URL" "$WORK_DIR/ha-repo"

echo "Syncing files from $HA_SOURCE..."
# Sync packages, dashboards, and any other config directories
# Exclude files that are templates/snippets (not direct HA config)
for dir in packages dashboards; do
  if [ -d "$HA_SOURCE/$dir" ]; then
    mkdir -p "$WORK_DIR/ha-repo/$dir"
    cp -r "$HA_SOURCE/$dir/." "$WORK_DIR/ha-repo/$dir/"
  fi
done

# Sync .gitignore (CRITICAL: protects .storage/ from git clean/reset)
if [ -f "$HA_SOURCE/.gitignore" ]; then
  cp "$HA_SOURCE/.gitignore" "$WORK_DIR/ha-repo/.gitignore"
fi

# Sync secrets.yaml.example if it exists
if [ -f "$HA_SOURCE/secrets.yaml.example" ]; then
  cp "$HA_SOURCE/secrets.yaml.example" "$WORK_DIR/ha-repo/secrets.yaml.example"
fi

# Check for changes
cd "$WORK_DIR/ha-repo"
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  echo "No changes to sync."
  rm -rf "$WORK_DIR"
  exit 0
fi

# Commit and push
git add -A
git commit -m "$COMMIT_MSG"
echo "Pushing to GitLab..."
git push --quiet

echo "Done. Run Git Pull on HAOS to sync to /config/."

# Cleanup
rm -rf "$WORK_DIR"
