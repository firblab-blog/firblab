#!/bin/bash
# =============================================================================
# FirbLab Hetzner Honeypot — Cloud-Init Bootstrap
# =============================================================================
# Bootstraps the dedicated honeypot server: Docker, SSH port migration,
# WireGuard client (downloads peer config from S3), and system hardening.
# The actual honeypot services (Cowrie, OpenCanary, Dionaea, Endlessh, Alloy)
# are deployed later by Ansible (honeypot-deploy.yml).
#
# Injected variables:
#   hostname              — Server hostname (auto-injected by module)
#   ssh_port              — Real SSH port (2222)
#   docker_network        — Docker bridge network CIDR
#   s3_access_key         — Hetzner S3 access key (for peer config download)
#   s3_secret_key         — Hetzner S3 secret key
#   s3_endpoint           — Hetzner S3 endpoint
#   s3_bucket             — S3 bucket name containing WireGuard peer configs
#   wireguard_peer        — Peer name to download (e.g., peer2)
#   wireguard_allowed_ips — AllowedIPs for the WireGuard client (homelab subnets)
#
# Cloud-init output log: /var/log/cloud-init-output.log
# Custom log: /var/log/firblab-setup.log
# =============================================================================

set -euxo pipefail

# Redirect all output to log file AND stdout (cloud-init captures stdout)
exec > >(tee -a /var/log/firblab-setup.log) 2>&1

echo "=== FirbLab Honeypot Bootstrap Started at $(date) ==="
echo "Hostname: ${hostname}"

# -----------------------------------------------------------------------------
# Phase 1: System Setup
# -----------------------------------------------------------------------------

echo "Phase 1: System setup..."
PRIVATE_IP=$(hostname -I | awk '{print $1}')
HOSTNAME_CURRENT=$(hostname)
if ! grep -q "$${HOSTNAME_CURRENT}" /etc/hosts; then
    echo "$${PRIVATE_IP} $${HOSTNAME_CURRENT}" >> /etc/hosts
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Unattended security upgrades
apt-get install -y unattended-upgrades apt-listchanges

cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'UNATTENDED'
Unattended-Upgrade::Allowed-Origins {
    "$${distro_id}:$${distro_codename}-security";
    "$${distro_id}ESMApps:$${distro_codename}-apps-security";
    "$${distro_id}ESM:$${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UNATTENDED

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AUTOUPGRADES'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
AUTOUPGRADES

systemctl enable unattended-upgrades
systemctl start unattended-upgrades

# Required packages
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    jq \
    net-tools \
    python3 \
    python3-pip \
    wireguard \
    unzip

echo "Phase 1 complete."

# -----------------------------------------------------------------------------
# Phase 2: Docker Installation
# -----------------------------------------------------------------------------

echo "Phase 2: Installing Docker..."
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker

# Docker Compose plugin (modern method — 'docker compose' not 'docker-compose')
apt-get install -y docker-compose-plugin

echo "Phase 2 complete."

# -----------------------------------------------------------------------------
# Phase 3: SSH Port Migration (port 22 reserved for Cowrie)
# -----------------------------------------------------------------------------

echo "Phase 3: Moving SSH to port ${ssh_port}..."

# Harden sshd
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-firblab.conf <<'SSHDCONF'
Port ${ssh_port}
PasswordAuthentication no
PermitRootLogin prohibit-password
MaxAuthTries 3
SSHDCONF

# Ubuntu 24.04 uses systemd socket activation — sshd_config Port is ignored.
# Must override ssh.socket to change the listening port.
mkdir -p /etc/systemd/system/ssh.socket.d
cat > /etc/systemd/system/ssh.socket.d/override.conf <<SSHSOCKET
[Socket]
ListenStream=
ListenStream=0.0.0.0:${ssh_port}
ListenStream=[::]:${ssh_port}
SSHSOCKET

systemctl daemon-reload
systemctl restart ssh.socket
systemctl restart ssh
echo "  SSH moved to port ${ssh_port}"

echo "Phase 3 complete."

# -----------------------------------------------------------------------------
# Phase 4: Directory Structure
# -----------------------------------------------------------------------------

echo "Phase 4: Creating directories..."
mkdir -p /opt/firblab/honeypot

echo "Phase 4 complete."

# -----------------------------------------------------------------------------
# Phase 5: WireGuard Client (tunnel to gateway for log shipping)
# -----------------------------------------------------------------------------
# Downloads a pre-generated peer config from the gateway's S3 bucket.
# Modifies AllowedIPs to only route homelab subnets (not 0.0.0.0/0),
# so honeypot traffic goes directly to the internet, not through the tunnel.
# Removes DNS directive to keep the honeypot's own DNS resolution.

echo "Phase 5: Setting up WireGuard client..."

if [ -n "${s3_access_key}" ] && [ -n "${s3_bucket}" ]; then
  # Install AWS CLI v2 for S3 access
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp/aws-install
  /tmp/aws-install/aws/install
  rm -rf /tmp/awscliv2.zip /tmp/aws-install

  # Configure AWS CLI for Hetzner S3
  mkdir -p /root/.aws
  cat >> /root/.aws/credentials <<AWSCREDS_VALS
[default]
aws_access_key_id = ${s3_access_key}
aws_secret_access_key = ${s3_secret_key}
AWSCREDS_VALS
  chmod 600 /root/.aws/credentials

  cat > /root/.aws/config <<AWSCONFIG
[default]
region = auto
output = json
AWSCONFIG

  S3_ENDPOINT="https://${s3_endpoint}"

  # Download peer config from S3 — retry loop for first-time deploy
  # (gateway may still be generating peer configs)
  echo "Downloading WireGuard peer config (${wireguard_peer}) from S3..."
  WG_DOWNLOADED=false
  for i in $(seq 1 30); do
    if aws s3 cp "s3://${s3_bucket}/peers/${wireguard_peer}.conf" /etc/wireguard/wg0.conf \
        --endpoint-url "$${S3_ENDPOINT}" 2>/dev/null; then
      echo "  Downloaded ${wireguard_peer}.conf successfully"
      WG_DOWNLOADED=true
      break
    fi
    echo "  Peer config not yet available, retrying... ($${i}/30)"
    sleep 20
  done

  # Clean up AWS credentials — no longer needed on the honeypot
  rm -rf /root/.aws

  if [ "$${WG_DOWNLOADED}" = "true" ]; then
    # Restrict AllowedIPs to homelab subnets only (not 0.0.0.0/0)
    # This ensures honeypot internet traffic stays direct, only Loki-bound
    # traffic routes through the WireGuard tunnel to the gateway
    sed -i "s|AllowedIPs = .*|AllowedIPs = ${wireguard_allowed_ips}|" /etc/wireguard/wg0.conf

    # Remove DNS directive — honeypot should use its own DNS, not the
    # gateway's AdGuard Home
    sed -i '/^DNS = /d' /etc/wireguard/wg0.conf

    chmod 600 /etc/wireguard/wg0.conf

    # Enable and start WireGuard
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0

    echo "  WireGuard tunnel is up"
    wg show wg0 || true
  else
    echo "  WARNING: Failed to download WireGuard peer config after 30 attempts"
    echo "  Log shipping to Loki will not work until wg0.conf is configured"
  fi
else
  echo "Phase 5 skipped — no S3 credentials configured"
fi

echo "Phase 5 complete."

# -----------------------------------------------------------------------------
# Phase 6: System Hardening
# -----------------------------------------------------------------------------

echo "Phase 6: System hardening..."

# Ensure log files exist
touch /var/log/auth.log /var/log/syslog
chmod 644 /var/log/auth.log /var/log/syslog

echo "Phase 6 complete."

# -----------------------------------------------------------------------------
# Bootstrap Complete
# -----------------------------------------------------------------------------

echo "=== FirbLab Honeypot Bootstrap Complete at $(date) ==="
echo "Server is ready for Ansible deployment (honeypot-deploy.yml)"
echo "SSH: ssh -p ${ssh_port} root@$(hostname -I | awk '{print $1}')"
