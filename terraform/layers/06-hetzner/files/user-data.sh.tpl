#!/bin/bash
# =============================================================================
# FirbLab Hetzner Gateway — Cloud-Init Bootstrap
# =============================================================================
# Bootstraps the gateway server with Docker, WireGuard, Traefik, and services.
# Rendered by Terraform templatefile() — variables injected at plan time.
#
# Injected variables:
#   hostname           — Server hostname (auto-injected by module)
#   domain_name        — Primary domain (e.g., example-lab.org)
#   wireguard_port     — WireGuard UDP port
#   wireguard_network  — WireGuard subnet CIDR (e.g., 10.8.0.0/24)
#   wireguard_peers    — Number of WireGuard peers to generate
#   letsencrypt_email  — Email for Let's Encrypt certificates
#   docker_network     — Docker bridge network CIDR
#   traefik_dashboard_hash — bcrypt hash for Traefik dashboard auth
#   gotify_password    — Generated password for Gotify
#   adguard_password   — Generated bcrypt hash for AdGuard
#
# Cloud-init output log: /var/log/cloud-init-output.log
# Custom log: /var/log/firblab-setup.log
# =============================================================================

set -euxo pipefail

# Redirect all output to log file AND stdout (cloud-init captures stdout)
exec > >(tee -a /var/log/firblab-setup.log) 2>&1

echo "=== FirbLab Gateway Bootstrap Started at $(date) ==="
echo "Hostname: ${hostname}"
echo "Domain: ${domain_name}"

# -----------------------------------------------------------------------------
# Phase 1: System Setup
# -----------------------------------------------------------------------------

echo "Phase 1: System setup..."
PRIVATE_IP=$(hostname -I | awk '{print $1}')
HOSTNAME_CURRENT=$(hostname)
if ! grep -q "$${HOSTNAME_CURRENT}" /etc/hosts; then
    echo "$${PRIVATE_IP} $${HOSTNAME_CURRENT}" >> /etc/hosts
fi

# Detect public IP for WireGuard SERVERURL
SERVER_IP=$(curl -s --max-time 10 https://api.ipify.org || curl -s --max-time 10 https://ifconfig.me || echo "UNKNOWN")
echo "Detected public IP: $${SERVER_IP}"

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
    unzip \
    jq \
    net-tools \
    psmisc \
    qrencode

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
# Phase 3: DNS Setup (disable systemd-resolved for AdGuard)
# -----------------------------------------------------------------------------

echo "Phase 3: Configuring DNS..."
systemctl disable systemd-resolved
systemctl stop systemd-resolved
sleep 2

if systemctl is-active --quiet systemd-resolved; then
    echo "WARNING: systemd-resolved still running, forcing stop..."
    systemctl kill -s SIGKILL systemd-resolved
    sleep 2
fi

# Static resolv.conf (temporary — AdGuard takes over port 53)
rm -f /etc/resolv.conf
cat > /etc/resolv.conf <<'RESOLVEOF'
nameserver 1.1.1.1
nameserver 1.0.0.1
RESOLVEOF
chattr +i /etc/resolv.conf

echo "Phase 3 complete."

# -----------------------------------------------------------------------------
# Phase 4: Application Directory Structure
# -----------------------------------------------------------------------------

echo "Phase 4: Creating directories..."
mkdir -p /opt/firblab/services
mkdir -p /opt/firblab/traefik/dynamic
mkdir -p /opt/firblab/traefik/letsencrypt
mkdir -p /opt/firblab/adguard/conf
mkdir -p /opt/firblab/adguard/work
mkdir -p /opt/firblab/wireguard/peers
mkdir -p /opt/firblab/fail2ban/jail.d

touch /opt/firblab/traefik/letsencrypt/acme.json
chmod 600 /opt/firblab/traefik/letsencrypt/acme.json

echo "Phase 4 complete."

# -----------------------------------------------------------------------------
# Phase 5: Bootstrap Compose (WireGuard only)
# -----------------------------------------------------------------------------
# Writes a minimal docker-compose.yml with ONLY the WireGuard service so
# Phase 7 can start it for peer generation, S3 upload, and homelab route
# setup (Phases 8, 8.5, 8.6). All other service configs are managed by
# Ansible via ansible/playbooks/gateway-deploy.yml after first boot.
#
# The full docker-compose.yml (all 10 services) is deployed by Ansible's
# hetzner-gateway role. Docker Compose sees WireGuard already running with
# matching config and leaves it in place; the remaining services are started.
# The wireguard-data volume persists all peer configs across this handoff.
# -----------------------------------------------------------------------------

echo "Phase 5: Writing bootstrap compose (WireGuard only)..."

cat > /opt/firblab/services/docker-compose.yml <<COMPOSEYML
# Bootstrap only — Ansible deploys the full stack via gateway-deploy.yml
# DO NOT EDIT — managed by Ansible after first boot
volumes:
  wireguard-data:

services:
  wireguard:
    image: linuxserver/wireguard:latest
    container_name: wireguard
    restart: unless-stopped
    network_mode: host
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
      - SERVERURL=$${SERVER_IP}
      - SERVERPORT=${wireguard_port}
      - PEERS=${wireguard_peers}
      - PEERDNS=auto
      - INTERNAL_SUBNET=${wireguard_network}
      - ALLOWEDIPS=0.0.0.0/0
      - LOG_CONFS=true
    volumes:
      - wireguard-data:/config
      - /lib/modules:/lib/modules:ro
    security_opt:
      - no-new-privileges:true
COMPOSEYML

echo "Phase 5 complete."

# -----------------------------------------------------------------------------
# Phase 6: System Configuration
# -----------------------------------------------------------------------------

echo "Phase 6: System configuration..."

touch /var/log/auth.log /var/log/syslog
chmod 644 /var/log/auth.log /var/log/syslog

# IP forwarding for WireGuard
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv4.conf.all.src_valid_mark=1" >> /etc/sysctl.conf
sysctl -p

# SSH on non-standard port 2222 to reduce bot noise
# Ubuntu 24.04 uses systemd socket activation — sshd_config Port is ignored.
# Must override ssh.socket to change the listening port.
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-firblab.conf <<'SSHDCONF'
Port 2222
PasswordAuthentication no
PermitRootLogin prohibit-password
MaxAuthTries 3
SSHDCONF

# Override systemd socket activation to listen on 2222 only
mkdir -p /etc/systemd/system/ssh.socket.d
cat > /etc/systemd/system/ssh.socket.d/override.conf <<'SSHSOCKET'
[Socket]
ListenStream=
ListenStream=0.0.0.0:2222
ListenStream=[::]:2222
SSHSOCKET

systemctl daemon-reload
systemctl restart ssh.socket
systemctl restart ssh
echo "  SSH moved to port 2222"

echo "Phase 6 complete."

# -----------------------------------------------------------------------------
# Phase 7: Start Services
# -----------------------------------------------------------------------------

echo "Phase 7: Starting WireGuard (bootstrap only)..."
# Start WireGuard only — needed for peer generation (Phase 8), S3 upload (Phase 8.5),
# and homelab route setup (Phase 8.6). The full service stack is started by Ansible
# (ansible/playbooks/gateway-deploy.yml) after first boot.
cd /opt/firblab/services
docker compose pull wireguard --ignore-pull-failures
docker compose up -d wireguard

echo "Waiting 20s for WireGuard to initialize and generate peer configs..."
sleep 20

echo "Phase 7 complete."

# -----------------------------------------------------------------------------
# Phase 8: WireGuard Peer Generation Script
# -----------------------------------------------------------------------------

echo "Phase 8: Installing WireGuard peer script..."
cat > /opt/firblab/wireguard/generate-peer.sh <<'WGPEERSCRIPT'
#!/bin/bash
# WireGuard Peer Generation Script
# Usage: ./generate-peer.sh <peer-name>
set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <peer-name>"
    echo "Example: $0 laptop"
    exit 1
fi

PEER_NAME="$1"
PEER_DIR="/config/peer_$${PEER_NAME}"
CONFIG_FILE="$${PEER_DIR}/$${PEER_NAME}.conf"
QR_FILE="$${PEER_DIR}/$${PEER_NAME}.png"

if [ ! -d "/config" ]; then
    echo "This script must be run inside the WireGuard container"
    echo "Run: docker exec -it wireguard /app/generate-peer.sh $${PEER_NAME}"
    exit 1
fi

if [ -d "$${PEER_DIR}" ]; then
    echo "Peer '$${PEER_NAME}' already exists!"
    echo "Config: $${CONFIG_FILE}"
    echo "QR Code: $${QR_FILE}"
    exit 0
fi

echo "Generating WireGuard peer: $${PEER_NAME}"
mkdir -p "$${PEER_DIR}"

PEER_PRIVATE_KEY=$(wg genkey)
PEER_PUBLIC_KEY=$(echo "$${PEER_PRIVATE_KEY}" | wg pubkey)

SERVER_PUBLIC_KEY=$(cat /config/server/publickey-server)
SERVER_ENDPOINT=$(grep "Endpoint" /config/peer1/peer1.conf | cut -d'=' -f2 | xargs)
ALLOWED_IPS=$(grep "AllowedIPs" /config/peer1/peer1.conf | cut -d'=' -f2 | xargs)
DNS=$(grep "DNS" /config/peer1/peer1.conf | cut -d'=' -f2 | xargs)
INTERNAL_SUBNET=$(grep "INTERNAL_SUBNET" /config/.donoteditthisfile | cut -d'=' -f2)

LAST_IP=$(ls -d /config/peer* 2>/dev/null | wc -l)
PEER_IP="$${INTERNAL_SUBNET%.*}.$((LAST_IP + 10))"

cat > "$${CONFIG_FILE}" <<EOF
[Interface]
PrivateKey = $${PEER_PRIVATE_KEY}
Address = $${PEER_IP}/32
DNS = $${DNS}

[Peer]
PublicKey = $${SERVER_PUBLIC_KEY}
Endpoint = $${SERVER_ENDPOINT}
AllowedIPs = $${ALLOWED_IPS}
PersistentKeepalive = 25
EOF

qrencode -t PNG -o "$${QR_FILE}" < "$${CONFIG_FILE}"

cat >> /config/wg_confs/wg0.conf <<EOF

[Peer]
# $${PEER_NAME}
PublicKey = $${PEER_PUBLIC_KEY}
AllowedIPs = $${PEER_IP}/32
EOF

wg syncconf wg0 <(wg-quick strip /config/wg_confs/wg0.conf)

echo "Peer '$${PEER_NAME}' created successfully!"
echo "Configuration: $${CONFIG_FILE}"
echo "QR Code: $${QR_FILE}"
echo "Peer IP: $${PEER_IP}"
echo ""
echo "Download config: docker cp wireguard:$${CONFIG_FILE} ./$${PEER_NAME}.conf"
WGPEERSCRIPT

chmod +x /opt/firblab/wireguard/generate-peer.sh

echo "Phase 8 complete."

# -----------------------------------------------------------------------------
# Phase 8.5: Upload WireGuard Peer Configs to S3
# -----------------------------------------------------------------------------
# Uploads all generated peer configs to Hetzner Object Storage (S3) for
# retrieval by the homelab WireGuard LXC. This breaks the Vault chicken-and-egg
# problem — Vault is not reachable until the tunnel is established.
# After the tunnel is up, a separate script syncs configs to Vault.

echo "Phase 8.5: Uploading WireGuard peer configs to S3..."

if [ -n "${s3_access_key}" ] && [ -n "${s3_bucket}" ]; then
  # Install AWS CLI v2 (not available via apt on Ubuntu 24.04)
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  apt-get install -y -q unzip
  unzip -q /tmp/awscliv2.zip -d /tmp/aws-install
  /tmp/aws-install/aws/install
  rm -rf /tmp/awscliv2.zip /tmp/aws-install

  # Configure AWS CLI for Hetzner S3
  mkdir -p /root/.aws
  cat > /root/.aws/credentials <<'AWSCREDS'
[default]
AWSCREDS
  # Write credentials separately (not in quoted heredoc — needs Terraform interpolation)
  cat >> /root/.aws/credentials <<AWSCREDS_VALS
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

  # Wait for WireGuard to generate peer configs (stored in Docker volume)
  echo "Waiting for WireGuard peer configs..."
  for i in $(seq 1 60); do
    PEER_COUNT=$(docker exec wireguard ls /config 2>/dev/null | grep -c "^peer" || true)
    if [ "$${PEER_COUNT}" -ge 1 ]; then
      echo "Found $${PEER_COUNT} peer directories"
      break
    fi
    echo "  Waiting... ($${i}/60)"
    sleep 5
  done

  # Upload each peer config to S3
  docker exec wireguard ls /config | grep "^peer" | while read PEER_DIR; do
    # linuxserver/wireguard names files as peerN.conf (no underscore)
    CONF_NAME=$(echo "$${PEER_DIR}" | sed 's/peer_/peer/')
    CONF_FILE="/config/$${PEER_DIR}/$${CONF_NAME}.conf"
    if docker exec wireguard test -f "$${CONF_FILE}"; then
      docker cp "wireguard:$${CONF_FILE}" "/tmp/$${PEER_DIR}.conf"
      aws s3 cp "/tmp/$${PEER_DIR}.conf" "s3://${s3_bucket}/peers/$${PEER_DIR}.conf" \
        --endpoint-url "$${S3_ENDPOINT}" 2>&1 || echo "Warning: Failed to upload $${PEER_DIR}"
      rm -f "/tmp/$${PEER_DIR}.conf"
      echo "  Uploaded $${PEER_DIR}.conf to S3"
    else
      echo "  Skipping $${PEER_DIR} — no conf file found at $${CONF_FILE}"
    fi
  done

  # Upload server public key alongside peer configs (consumers expect peers/server_public_key)
  if docker exec wireguard test -f /config/server/publickey-server; then
    docker cp wireguard:/config/server/publickey-server /tmp/server_public_key
    aws s3 cp /tmp/server_public_key "s3://${s3_bucket}/peers/server_public_key" \
      --endpoint-url "$${S3_ENDPOINT}" 2>&1 || echo "Warning: Failed to upload server publickey"
    rm -f /tmp/server_public_key
    echo "  Uploaded server public key to S3"
  fi

  echo "Phase 8.5 complete."
else
  echo "Phase 8.5 skipped — no S3 credentials configured."
fi

# -----------------------------------------------------------------------------
# Phase 8.6: Configure Homelab Peer Routes
# -----------------------------------------------------------------------------
# Modify the homelab peer's AllowedIPs on the server side to include homelab
# subnets. This tells the WireGuard kernel module to route 10.0.20.0/24
# and 10.0.30.0/24 through the tunnel to the homelab peer.
# Without this, Traefik's connections to homelab IPs have no route.

echo "Phase 8.6: Configuring homelab peer routes..."

# Wait for WireGuard config to be fully written
sleep 5

# The homelab peer's tunnel IP (peer1 = 10.8.0.2)
HOMELAB_PEER="${homelab_peer_name}"
HOMELAB_PEER_IP="10.8.0.2"
HOMELAB_ALLOWED="$${HOMELAB_PEER_IP}/32, ${homelab_subnets}"

# Modify the peer's AllowedIPs in the server's wg0.conf
# The linuxserver image creates entries like:
#   [Peer]
#   # peer1
#   PublicKey = ...
#   AllowedIPs = 10.8.0.2/32
docker exec wireguard bash -c "
  sed -i '/# $${HOMELAB_PEER}\$/,/AllowedIPs/ s|AllowedIPs = .*|AllowedIPs = $${HOMELAB_ALLOWED}|' /config/wg_confs/wg0.conf
"

# Hot-reload WireGuard config without restarting
docker exec wireguard bash -c "wg syncconf wg0 <(wg-quick strip /config/wg_confs/wg0.conf)"

# Add kernel routes for homelab subnets.
# The linuxserver/wireguard Docker image uses `wg` (not `wg-quick`), so
# AllowedIPs alone does NOT create kernel routes. Without explicit routes,
# packets destined for 192.168.x.x go out the public internet instead of
# through the WireGuard tunnel.
# Since the container runs with network_mode: host, these routes are on the
# host's routing table and persist until reboot. A systemd unit ensures they
# survive reboots (created below).
IFS=',' read -ra SUBNETS <<< "${homelab_subnets}"
for SUBNET in "$${SUBNETS[@]}"; do
  SUBNET=$(echo "$${SUBNET}" | xargs)  # trim whitespace
  if [ -n "$${SUBNET}" ]; then
    ip route add "$${SUBNET}" dev wg0 2>/dev/null || \
      echo "  Route for $${SUBNET} already exists"
    echo "  Added route: $${SUBNET} dev wg0"
  fi
done

# Create a systemd unit to restore routes on reboot (wg0 is managed by Docker,
# not wg-quick, so there's no PostUp hook on the host side).
cat > /etc/systemd/system/wireguard-routes.service <<WGROUTESVC
[Unit]
Description=WireGuard homelab subnet routes
After=docker.service firblab-services.service
Wants=firblab-services.service

[Service]
Type=oneshot
RemainAfterExit=yes
$(for SUBNET in "$${SUBNETS[@]}"; do
  SUBNET=$(echo "$${SUBNET}" | xargs)
  [ -n "$${SUBNET}" ] && echo "ExecStart=/sbin/ip route add $${SUBNET} dev wg0"
done)

[Install]
WantedBy=multi-user.target
WGROUTESVC

systemctl daemon-reload
systemctl enable wireguard-routes.service

echo "  Homelab peer $${HOMELAB_PEER} AllowedIPs set to: $${HOMELAB_ALLOWED}"
echo "Phase 8.6 complete."

# -----------------------------------------------------------------------------
# Phase 9: Systemd Service for Auto-Restart
# -----------------------------------------------------------------------------

echo "Phase 9: Creating systemd services..."
cat > /etc/systemd/system/firblab-services.service <<'SYSTEMD'
[Unit]
Description=FirbLab Gateway Services
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/firblab/services
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable firblab-services.service

echo "Phase 9 complete."

# -----------------------------------------------------------------------------
# Complete
# -----------------------------------------------------------------------------

echo ""
echo "=== FirbLab Gateway Bootstrap Completed at $(date) ==="
echo ""
echo "Service Status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "Services:"
echo "  Traefik Dashboard: https://traefik.${domain_name}"
echo "  AdGuard Home:      http://$${SERVER_IP}:3000"
echo "  Uptime Kuma:       http://$${SERVER_IP}:3001"
echo "  Gotify:            http://$${SERVER_IP}:8080"
echo "  WireGuard:         udp://$${SERVER_IP}:${wireguard_port}"
echo ""
echo "SSH on port 2222:"
echo "  ssh -p 2222 root@$${SERVER_IP}"
echo ""
echo "Homelab services (via WireGuard tunnel):"
echo "  Blog:       https://blog.${domain_name}"
echo "  Mealie:     https://food.${domain_name}"
echo "  FoundryVTT: https://foundryvtt.${domain_name}"
echo ""
echo "Generate WireGuard peers:"
echo "  docker exec -it wireguard /app/generate-peer.sh <peer-name>"
