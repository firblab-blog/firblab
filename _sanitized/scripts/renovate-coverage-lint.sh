#!/usr/bin/env bash
# =============================================================================
# Renovate Coverage Lint — FirbLab CI/CD
# =============================================================================
# Validates that every version-pinned variable in Ansible role defaults and
# inventory group_vars has Renovate Bot coverage.
#
# Two coverage patterns:
#   Pattern A (*_image variables): Self-describing "registry/name:tag" format.
#     Auto-detected by Renovate regex manager — no annotation needed.
#     Validated: variable value must match "name:tag" format.
#
#   Pattern B (*_version variables): Require a "# renovate: datasource=X depName=Y"
#     annotation comment on the line immediately above.
#     Used ONLY for non-Docker sources (GitHub releases, PyPI, apt packages).
#
# Exit codes:
#   0 — All version variables have Renovate coverage.
#   1 — One or more gaps found (missing annotation or bad format).
#
# Usage:
#   ./scripts/renovate-coverage-lint.sh
#   CI: runs as part of the ansible:renovate-coverage job in .gitlab-ci.yml
# =============================================================================

set -euo pipefail

ERRORS=0
CHECKED=0

# ---------------------------------------------------------------------------
# Allowlist: variables intentionally excluded from Renovate tracking.
# Add entries here with a comment explaining why.
# ---------------------------------------------------------------------------
ALLOWLIST=(
  "honeypot_cowrie_image"        # No versioned Docker tags available (only :latest + SHA)
  "gitlab_runner_docker_image"   # Meta-image for runner executor — pinned to stable
  "ai_gpu_rocm_version"          # AMD ROCm APT repo version — no Renovate datasource
  "honeypot_cowrie_ssh_version"  # Fake SSH banner string, not a software version
  "vault_version"                # TODO: Add github-releases annotation when Vault role is refactored
  "vault_tls_min_version"        # TLS protocol minimum (e.g., "1.2") — config setting, not software
)

is_allowlisted() {
  local var="$1"
  for allowed in "${ALLOWLIST[@]}"; do
    if [[ "$var" == "$allowed" ]]; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Check *_image variables (Pattern A) — verify format
# ---------------------------------------------------------------------------
check_image_vars() {
  local file="$1"
  local line_num=0

  while IFS= read -r line; do
    ((line_num++)) || true

    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    # Match variables ending in _image:
    if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*_image):[[:space:]]*\"(.+)\" ]]; then
      local var_name="${BASH_REMATCH[1]}"
      local var_value="${BASH_REMATCH[2]}"
      ((CHECKED++)) || true

      # Check allowlist
      if is_allowlisted "$var_name"; then
        continue
      fi

      # Verify format: "registry/name:tag" where tag is at least 2 chars.
      # This mirrors Renovate's regex exactly — single-char tags (e.g. ":2") pass
      # this format check visually but Renovate can't track them. Requiring 2+ chars
      # ensures the version is a real semver/pre-release tag, not a floating major.
      if [[ ! "$var_value" =~ ^[a-z0-9][a-z0-9._/-]+:[a-zA-Z0-9][a-zA-Z0-9._-] ]]; then
        echo "ERROR: $file:$line_num: $var_name value '$var_value' does not match expected image:tag format (tag must be 2+ chars; use a pinned semver tag, not a floating major like ':2')"
        ((ERRORS++)) || true
      fi
    fi
  done < "$file"
}

# ---------------------------------------------------------------------------
# Check *_version variables (Pattern B) — verify annotation exists
# ---------------------------------------------------------------------------
check_version_vars() {
  local file="$1"
  local prev_line=""
  local line_num=0

  while IFS= read -r line; do
    ((line_num++)) || true

    # Skip comments and empty lines for variable matching
    if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// /}" ]]; then
      prev_line="$line"
      continue
    fi

    # Match variables ending in _version:
    if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*_version):[[:space:]] ]]; then
      local var_name="${BASH_REMATCH[1]}"
      ((CHECKED++)) || true

      # Check allowlist
      if is_allowlisted "$var_name"; then
        prev_line="$line"
        continue
      fi

      # Check if the previous non-blank line has a # renovate: annotation
      if [[ ! "$prev_line" =~ \#[[:space:]]*renovate: ]]; then
        echo "ERROR: $file:$line_num: $var_name missing '# renovate: datasource=X depName=Y' annotation on preceding line"
        echo "  FIX: If this is a Docker image, convert to *_image format (Pattern A) instead."
        echo "       If non-Docker (GitHub release, PyPI, apt), add the annotation comment."
        ((ERRORS++)) || true
      fi
    fi

    prev_line="$line"
  done < "$file"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "=== Renovate Coverage Lint ==="
echo ""

# Scan all Ansible role defaults
for file in ansible/roles/*/defaults/main.yml; do
  [[ -f "$file" ]] || continue
  check_image_vars "$file"
  check_version_vars "$file"
done

# Scan inventory group_vars (for monitoring agents, RKE2, etc.)
for file in ansible/inventory/group_vars/*.yml; do
  [[ -f "$file" ]] || continue
  check_version_vars "$file"
done

echo "Checked $CHECKED version-pinned variables."
echo ""

if [[ $ERRORS -gt 0 ]]; then
  echo "FAILED: Found $ERRORS variable(s) without Renovate coverage."
  echo ""
  echo "How to fix:"
  echo "  Docker services: Use *_image variable with full image:tag value."
  echo "    Example: myapp_image: \"registry/name:1.2.3\""
  echo ""
  echo "  Non-Docker (GitHub releases, PyPI, apt): Add annotation comment."
  echo "    Example: # renovate: datasource=github-releases depName=org/repo"
  echo "             myapp_version: \"1.2.3\""
  echo ""
  echo "  Intentional exclusion: Add variable name to ALLOWLIST in this script."
  exit 1
fi

echo "PASSED: All version variables have Renovate coverage."
