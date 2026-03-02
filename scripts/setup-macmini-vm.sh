#!/usr/bin/env bash
# =============================================================================
# Mac Mini M4 - UTM Linux VM Setup
# =============================================================================
# This is now fully automated via Ansible. Run the playbooks below from the
# firblab repo root on your workstation (MacBook).
#
# The VM will host:
#   - Vault primary node (vault-1) at 10.0.10.11
#   - Unseal Vault instance (lightweight, port 8210)
#
# Prerequisites:
#   - Mac Mini M4 with macOS 15+, reachable via SSH
#   - SSH key: ~/.ssh/id_ed25519_lab-macmini
#   - Internet access on Mac Mini (for Rocky qcow2 download)
#
# =============================================================================

set -euo pipefail

cat <<'EOF'
============================================
  Mac Mini M4 - Vault VM Setup
============================================

All steps are now automated via Ansible playbooks.
Run these commands from the firblab repo root:

  Step 1: Bootstrap macOS host (SSH, pf firewall, Homebrew, UTM)
  ──────────────────────────────────────────────────────────────
  ansible-playbook ansible/playbooks/macos-bootstrap.yml

  Step 2: Create UTM VM (Rocky Linux 9 ARM64, GenericCloud qcow2)
  ──────────────────────────────────────────────────────────────
  ansible-playbook ansible/playbooks/macos-vm-create.yml

  Step 3: Harden the Linux VM
  ──────────────────────────────────────────────────────────────
  ansible-playbook ansible/playbooks/harden.yml --limit lab-macmini-vm

  Step 4: Deploy Vault
  ──────────────────────────────────────────────────────────────
  ansible-playbook ansible/playbooks/vault-deploy.yml

VM Specs:
  Name:       vault-1
  OS:         Rocky Linux 9 (GenericCloud qcow2)
  Arch:       ARM64 (aarch64) via QEMU/Hypervisor.framework
  CPU:        2 cores
  Memory:     4096 MB
  Disk 1:     40 GB (OS, resized qcow2)
  Disk 2:     20 GB (Vault data, mounted at /opt/vault/data)
  Network:    Bridged to en0 (Management VLAN 10)
  IP:         10.0.10.11/24
  User:       admin (SSH key auth, passwordless sudo)
  SELinux:    Enforcing (targeted policy)

============================================
EOF
