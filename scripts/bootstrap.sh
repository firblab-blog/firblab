#!/usr/bin/env bash
# =============================================================================
# firblab Bootstrap Script
# =============================================================================
# One-time orchestration script for initial deployment.
# Follows the phased bootstrap sequence from docs/ARCHITECTURE.md.
#
# Prerequisites:
#   - terraform >= 1.9
#   - ansible >= 2.15
#   - sops + age configured
#   - gw-01 (UniFi UDM Pro) accessible with API credentials
#   - Proxmox node(s) accessible via SSH
#   - Mac Mini UTM VM running (vault-1)
#   - RPi5 running Ubuntu 24.04 (vault-3)
#
# Usage:
#   ./bootstrap.sh [phase]
#   ./bootstrap.sh         # Run all phases interactively
#   ./bootstrap.sh 1       # Run only Phase 1 (Network)
#   ./bootstrap.sh 2       # Run only Phase 2 (Proxmox Base)
#   ./bootstrap.sh 3       # Run only Phase 3 (Vault)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

confirm() {
  echo ""
  read -r -p "$(echo -e "${YELLOW}$1 [y/N]${NC} ")" response
  [[ "$response" =~ ^[Yy]$ ]]
}

# ---------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------
preflight() {
  log "Running pre-flight checks..."

  command -v terraform >/dev/null 2>&1 || error "terraform not found. Install: https://developer.hashicorp.com/terraform/install"
  command -v ansible-playbook >/dev/null 2>&1 || error "ansible not found. Install: pip install ansible"
  command -v sops >/dev/null 2>&1 || error "sops not found. Install: brew install sops"
  command -v age >/dev/null 2>&1 || error "age not found. Install: brew install age"
  command -v vault >/dev/null 2>&1 || warn "vault CLI not found (needed for Phase 3+). Install: brew install vault"

  success "Pre-flight checks passed."
}

# ---------------------------------------------------------
# Phase 1: Network
# ---------------------------------------------------------
phase_1() {
  log "=========================================="
  log "PHASE 1: Network (Layer 00)"
  log "=========================================="
  log "This will configure VLANs and firewall rules on gw-01 (UDM Pro)."
  warn "ENSURE YOU ARE ON A WIRED CONNECTION."

  if ! confirm "Proceed with network configuration?"; then
    log "Skipping Phase 1."
    return
  fi

  cd "${PROJECT_ROOT}/terraform/layers/00-network"
  terraform init
  terraform plan -out=tfplan
  terraform apply tfplan
  rm -f tfplan

  success "Phase 1 complete. VLANs and firewall rules configured."
  log "Verify: ping between VLANs from management host."
}

# ---------------------------------------------------------
# Phase 2: Proxmox Base
# ---------------------------------------------------------
phase_2() {
  log "=========================================="
  log "PHASE 2: Proxmox Base (Layer 01)"
  log "=========================================="

  if ! confirm "Bootstrap Proxmox node(s)?"; then
    log "Skipping Phase 2."
    return
  fi

  log "Running Proxmox bootstrap playbook..."
  cd "${PROJECT_ROOT}"
  ansible-playbook ansible/playbooks/proxmox-bootstrap.yml

  log "Applying Proxmox base Terraform..."
  cd "${PROJECT_ROOT}/terraform/layers/01-proxmox-base"
  terraform init
  terraform plan -out=tfplan
  terraform apply tfplan
  rm -f tfplan

  success "Phase 2 complete. Proxmox base configured."
  log "Verify: Proxmox API accessible, storage pools visible."
}

# ---------------------------------------------------------
# Phase 3: Vault Cluster
# ---------------------------------------------------------
phase_3() {
  log "=========================================="
  log "PHASE 3: Vault HA Cluster (Layer 02)"
  log "=========================================="

  if ! confirm "Deploy Vault HA cluster?"; then
    log "Skipping Phase 3."
    return
  fi

  log "Hardening Mac Mini VM and RPi5..."
  cd "${PROJECT_ROOT}"
  ansible-playbook ansible/playbooks/harden.yml -l macmini,rpi

  log "Creating Vault VM on Proxmox..."
  cd "${PROJECT_ROOT}/terraform/layers/02-vault-infra"
  terraform init
  terraform plan -out=tfplan
  terraform apply tfplan
  rm -f tfplan

  log "Deploying Vault cluster..."
  cd "${PROJECT_ROOT}"
  ansible-playbook ansible/playbooks/vault-deploy.yml

  success "Phase 3 complete."
  log ""
  log "Next steps (manual):"
  log "  1. Initialize Vault: vault operator init"
  log "  2. Unseal Vault nodes"
  log "  3. Apply Layer 02-vault-config: cd terraform/layers/02-vault-config && terraform apply"
  log "  4. Save admin token: terraform output -raw admin_token > ~/.vault-token"
  log "  5. Enable PKI: vault secrets enable pki"
  log "  6. Setup backup cron: crontab -e (add vault-backup.sh every 6 hours)"
  log "  7. Verify: vault status (all 3 nodes)"
}

# ---------------------------------------------------------
# Main
# ---------------------------------------------------------
echo ""
echo "=========================================="
echo "  firblab Bootstrap"
echo "=========================================="
echo ""

preflight

PHASE="${1:-all}"

case "${PHASE}" in
  1) phase_1 ;;
  2) phase_2 ;;
  3) phase_3 ;;
  all)
    phase_1
    phase_2
    phase_3
    echo ""
    success "Bootstrap phases 1-3 complete."
    log "Vault is live. You can now continue with Phases 4+ on lab-02."
    log "See docs/ARCHITECTURE.md for the full deployment sequence."
    ;;
  *)
    error "Unknown phase: ${PHASE}. Use: 1, 2, 3, or all"
    ;;
esac
