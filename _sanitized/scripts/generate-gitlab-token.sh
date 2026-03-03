#!/bin/bash
# =============================================================================
# Generate GitLab Personal Access Token
# =============================================================================
# Creates a Personal Access Token for the root user on the GitLab CE instance
# via gitlab-rails runner (SSH). This is the one manual bootstrap step needed
# before Terraform can manage GitLab resources.
#
# The token is used by Terraform Layer 03-gitlab-config to create groups,
# projects, labels, and branch protections. After generation, store the token
# in Vault at secret/services/gitlab/admin.
#
# Prerequisites:
#   - GitLab CE running (deployed by Layer 03 + Ansible)
#   - SSH access to GitLab VM (admin user, key-based auth)
#   - Vault CLI available (for storing the token)
#
# Usage:
#   bash scripts/generate-gitlab-token.sh                    # Default: 10.0.10.50
#   bash scripts/generate-gitlab-token.sh 10.0.10.50      # Explicit host
#   SSH_KEY=~/.ssh/custom_key bash scripts/generate-gitlab-token.sh
#
# After running, store in Vault:
#   vault kv put secret/services/gitlab/admin \
#     personal_access_token="glpat-xxxx" \
#     root_password="xxxx"
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
GITLAB_HOST="${1:-10.0.10.50}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gitlab}"
SSH_USER="admin"
TOKEN_NAME="terraform-automation"

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if [ ! -f "$SSH_KEY" ]; then
  echo "ERROR: SSH key not found: $SSH_KEY" >&2
  echo "Extract it from Terraform output:" >&2
  echo "  cd terraform/layers/03-core-infra" >&2
  echo "  terraform output -raw gitlab_ssh_private_key > ~/.ssh/id_ed25519_gitlab" >&2
  echo "  chmod 600 ~/.ssh/id_ed25519_gitlab" >&2
  echo "  ssh-keygen -y -f ~/.ssh/id_ed25519_gitlab > ~/.ssh/id_ed25519_gitlab.pub" >&2
  exit 1
fi

echo "=== GitLab PAT Generator ==="
echo "Host: ${GITLAB_HOST}"
echo "SSH Key: ${SSH_KEY}"
echo "Token Name: ${TOKEN_NAME}"
echo ""

# ---------------------------------------------------------------------------
# Generate PAT via gitlab-rails runner
# ---------------------------------------------------------------------------
echo "Generating Personal Access Token for root user..."

TOKEN=$(ssh -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new "${SSH_USER}@${GITLAB_HOST}" \
  "sudo gitlab-rails runner \"
user = User.find_by(username: 'root')
if user.nil?
  STDERR.puts 'ERROR: Root user not found'
  exit 1
end

# Remove any existing token with the same name (idempotent)
user.personal_access_tokens.where(name: '${TOKEN_NAME}').destroy_all

token = user.personal_access_tokens.create!(
  name: '${TOKEN_NAME}',
  scopes: ['api'],
  expires_at: 1.year.from_now
)

puts token.token
\"" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  echo "ERROR: Failed to generate token" >&2
  exit 1
fi

echo ""
echo "✓ Personal Access Token created successfully!"
echo ""

# ---------------------------------------------------------------------------
# Read initial root password (if still available)
# ---------------------------------------------------------------------------
ROOT_PASS=$(ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "${SSH_USER}@${GITLAB_HOST}" \
  "sudo grep '^Password:' /etc/gitlab/initial_root_password 2>/dev/null | awk '{print \$2}'" 2>/dev/null || true)

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
echo "Token: ${TOKEN}"
echo ""
echo "==========================================="
echo "Store in Vault (copy and run):"
echo "==========================================="
echo ""
if [ -n "$ROOT_PASS" ]; then
  echo "  vault kv put secret/services/gitlab/admin \\"
  echo "    personal_access_token='${TOKEN}' \\"
  echo "    root_password='${ROOT_PASS}'"
else
  echo "  # Root password file already consumed — provide it manually"
  echo "  vault kv put secret/services/gitlab/admin \\"
  echo "    personal_access_token='${TOKEN}' \\"
  echo "    root_password='<your-root-password>'"
fi
echo ""
echo "==========================================="
echo "Or for Terraform direct usage (bootstrap):"
echo "==========================================="
echo ""
echo "  export TF_VAR_gitlab_token='${TOKEN}'"
echo ""
