# =============================================================================
# Layer 00: Network Infrastructure (gw-01 / UniFi UDM Pro)
# Rover CI visualization: https://github.com/im2nguyen/rover
# =============================================================================
# Manages VLANs, firewall zones, zone policies, port profiles, and DHCP on
# gw-01. This is the foundation layer — all other layers depend on it.
#
# Uses Zone-Based Firewall (UniFi OS 9.x) instead of legacy firewall rules.
# Zone policies define traffic flow between groups of networks.
# =============================================================================

# ---------------------------------------------------------
# VLAN Networks
# ---------------------------------------------------------

resource "unifi_network" "management" {
  name    = "Management"
  purpose = "corporate"

  vlan_id      = 10
  subnet       = "10.0.10.0/24"
  dhcp_enabled = true
  dhcp_start   = "10.0.10.100"
  dhcp_stop    = "10.0.10.200"
  dhcp_lease   = 86400
  dhcp_dns     = var.management_dns_servers
}

resource "unifi_network" "services" {
  name    = "Services"
  purpose = "corporate"

  vlan_id      = 20
  subnet       = "10.0.20.0/24"
  dhcp_enabled = true
  dhcp_start   = "10.0.20.100"
  dhcp_stop    = "10.0.20.200"
  dhcp_lease   = 86400
  dhcp_dns     = var.services_dns_servers
}

resource "unifi_network" "dmz" {
  name    = "DMZ"
  purpose = "corporate"

  vlan_id      = 30
  subnet       = "10.0.30.0/24"
  dhcp_enabled = true
  dhcp_start   = "10.0.30.100"
  dhcp_stop    = "10.0.30.200"
  dhcp_lease   = 86400
  dhcp_dns     = var.dmz_dns_servers
}

resource "unifi_network" "storage" {
  name    = "Storage"
  purpose = "corporate"

  vlan_id      = 40
  subnet       = "10.0.40.0/24"
  dhcp_enabled = true
  dhcp_start   = "10.0.40.100"
  dhcp_stop    = "10.0.40.200"
  dhcp_lease   = 86400
}

resource "unifi_network" "security" {
  name    = "Security"
  purpose = "corporate"

  vlan_id      = 50
  subnet       = "10.0.50.0/24"
  dhcp_enabled = true
  dhcp_start   = "10.0.50.100"
  dhcp_stop    = "10.0.50.200"
  dhcp_lease   = 86400
  dhcp_dns     = var.security_dns_servers
}

resource "unifi_network" "iot" {
  name    = "IoT"
  purpose = "corporate"

  vlan_id      = 60
  subnet       = "10.0.60.0/24"
  dhcp_enabled = true
  dhcp_start   = "10.0.60.100"
  dhcp_stop    = "10.0.60.200"
  dhcp_lease   = 86400
  dhcp_dns     = var.iot_dns_servers
}

# ---------------------------------------------------------
# Firewall Zones
# ---------------------------------------------------------
# Group networks into logical zones for policy application.
# Each zone contains one or more networks that share the
# same security posture.
# ---------------------------------------------------------

resource "unifi_firewall_zone" "management" {
  name     = "Management"
  networks = [unifi_network.management.id]
}

resource "unifi_firewall_zone" "services" {
  name     = "Services"
  networks = [unifi_network.services.id]
}

resource "unifi_firewall_zone" "dmz" {
  name     = "DMZ"
  networks = [unifi_network.dmz.id]
}

resource "unifi_firewall_zone" "storage" {
  name     = "Storage"
  networks = [unifi_network.storage.id]
}

resource "unifi_firewall_zone" "security" {
  name     = "Security"
  networks = [unifi_network.security.id]
}

resource "unifi_firewall_zone" "iot" {
  name     = "IoT"
  networks = [unifi_network.iot.id]
}

# The Default LAN is pre-existing (created by UniFi during setup) so we
# cannot use a data source to look it up — the provider hits a
# deserialization bug on the Default network's IPsec fields.
# Instead we pass the network ID as a variable.
resource "unifi_firewall_zone" "lan" {
  name     = "LAN"
  networks = [local.default_lan_network_id]
}

# ---------------------------------------------------------
# Zone Policies: Management -> All (full access)
# ---------------------------------------------------------
# The Management zone has unrestricted access to every other
# zone (SSH, Proxmox UI, Vault, Ansible/Terraform ops).
# ---------------------------------------------------------

# NOTE: The UniFi API auto-assigns `index` values; they cannot be set directly.
# We use the patched provider from PR #117 (filipowm/terraform-provider-unifi)
# which makes `index` Computed-only to avoid post-apply consistency errors.
# depends_on chains serialize creation to ensure deterministic ordering.

resource "unifi_firewall_zone_policy" "mgmt_to_services" {
  name   = "Management to Services"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.management.id }
  destination = { zone_id = unifi_firewall_zone.services.id }
}

resource "unifi_firewall_zone_policy" "mgmt_to_dmz" {
  name   = "Management to DMZ"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.management.id }
  destination = { zone_id = unifi_firewall_zone.dmz.id }

  depends_on = [unifi_firewall_zone_policy.mgmt_to_services]
}

resource "unifi_firewall_zone_policy" "mgmt_to_storage" {
  name   = "Management to Storage"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.management.id }
  destination = { zone_id = unifi_firewall_zone.storage.id }

  depends_on = [unifi_firewall_zone_policy.mgmt_to_dmz]
}

resource "unifi_firewall_zone_policy" "mgmt_to_security" {
  name   = "Management to Security"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.management.id }
  destination = { zone_id = unifi_firewall_zone.security.id }

  depends_on = [unifi_firewall_zone_policy.mgmt_to_storage]
}

# ---------------------------------------------------------
# Zone Policies: All Lab VLANs -> Management (return traffic)
# ---------------------------------------------------------
# Management has forward policies to all VLANs but needs
# explicit return policies. Without these, services on lab
# VLANs cannot initiate connections back to Management
# (e.g., vault-2 on Security VLAN joining vault-1 on Mgmt).
#
# IMPORTANT: UniFi zone policies are NOT stateful — every
# packet is evaluated independently. A Management->DMZ ALLOW
# policy is useless without a DMZ->Management return policy
# because the reply packets get dropped. ALL zones must have
# bidirectional policies with Management.
# ---------------------------------------------------------

resource "unifi_firewall_zone_policy" "security_to_mgmt" {
  name   = "Security to Management"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.security.id }
  destination = { zone_id = unifi_firewall_zone.management.id }

  depends_on = [unifi_firewall_zone_policy.mgmt_to_security]
}

resource "unifi_firewall_zone_policy" "services_to_mgmt" {
  name   = "Services to Management"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.services.id }
  destination = { zone_id = unifi_firewall_zone.management.id }

  depends_on = [unifi_firewall_zone_policy.security_to_mgmt]
}

resource "unifi_firewall_zone_policy" "storage_to_mgmt" {
  name   = "Storage to Management"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.storage.id }
  destination = { zone_id = unifi_firewall_zone.management.id }

  depends_on = [unifi_firewall_zone_policy.services_to_mgmt]
}

resource "unifi_firewall_zone_policy" "dmz_to_mgmt" {
  name   = "DMZ to Management"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.dmz.id }
  destination = { zone_id = unifi_firewall_zone.management.id }

  depends_on = [unifi_firewall_zone_policy.storage_to_mgmt]
}

# ---------------------------------------------------------
# Zone Policies: Services -> Storage (NFS + iSCSI)
# ---------------------------------------------------------

resource "unifi_firewall_zone_policy" "services_to_storage_nfs" {
  name     = "Services to Storage NFS"
  action   = "ALLOW"
  protocol = "tcp"

  source      = { zone_id = unifi_firewall_zone.services.id }
  destination = {
    zone_id       = unifi_firewall_zone.storage.id
    port_group_id = unifi_firewall_group.nfs_ports.id
  }

  depends_on = [unifi_firewall_zone_policy.dmz_to_mgmt]
}

resource "unifi_firewall_zone_policy" "services_to_storage_iscsi" {
  name     = "Services to Storage iSCSI"
  action   = "ALLOW"
  protocol = "tcp"

  source      = { zone_id = unifi_firewall_zone.services.id }
  destination = {
    zone_id       = unifi_firewall_zone.storage.id
    port_group_id = unifi_firewall_group.iscsi_ports.id
  }

  depends_on = [unifi_firewall_zone_policy.services_to_storage_nfs]
}

# ---------------------------------------------------------
# Zone Policies: Services -> Security (Vault, GitLab, Wazuh)
# ---------------------------------------------------------

resource "unifi_firewall_zone_policy" "services_to_security_vault" {
  name     = "Services to Vault API"
  action   = "ALLOW"
  protocol = "tcp"

  source      = { zone_id = unifi_firewall_zone.services.id }
  destination = {
    zone_id       = unifi_firewall_zone.security.id
    port_group_id = unifi_firewall_group.vault_api_port.id
  }

  depends_on = [unifi_firewall_zone_policy.services_to_storage_iscsi]
}

resource "unifi_firewall_zone_policy" "services_to_security_gitlab" {
  name     = "Services to GitLab"
  action   = "ALLOW"
  protocol = "tcp"

  source      = { zone_id = unifi_firewall_zone.services.id }
  destination = {
    zone_id       = unifi_firewall_zone.security.id
    port_group_id = unifi_firewall_group.gitlab_ports.id
  }

  depends_on = [unifi_firewall_zone_policy.services_to_security_vault]
}

resource "unifi_firewall_zone_policy" "services_to_security_wazuh" {
  name     = "Services to Wazuh"
  action   = "ALLOW"
  protocol = "tcp"

  source      = { zone_id = unifi_firewall_zone.services.id }
  destination = {
    zone_id       = unifi_firewall_zone.security.id
    port_group_id = unifi_firewall_group.wazuh_agent_ports.id
  }

  depends_on = [unifi_firewall_zone_policy.services_to_security_gitlab]
}

resource "unifi_firewall_zone_policy" "services_to_security_monitoring" {
  name     = "Services to Security node_exporter"
  action   = "ALLOW"
  protocol = "tcp"

  # Allows Prometheus (Services VLAN) to scrape node_exporter on vault-2
  # (Security VLAN 50, 10.0.50.2:9100). Without this, port 9100 is
  # blocked by the Security VLAN's default-deny ingress policy.
  source      = { zone_id = unifi_firewall_zone.services.id }
  destination = {
    zone_id       = unifi_firewall_zone.security.id
    port_group_id = unifi_firewall_group.node_exporter_port.id
  }

  depends_on = [unifi_firewall_zone_policy.services_to_security_wazuh]
}

# ---------------------------------------------------------
# Zone Policies: LAN -> Management (workstation access)
# ---------------------------------------------------------
# The workstation (MacBook Pro) lives on the Default LAN and
# needs full access to the Management VLAN for SSH, Ansible,
# Terraform, and other admin operations.
# ---------------------------------------------------------

resource "unifi_firewall_zone_policy" "lan_to_mgmt" {
  name   = "LAN to Management"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.lan.id }
  destination = { zone_id = unifi_firewall_zone.management.id }

  depends_on = [unifi_firewall_zone_policy.services_to_security_monitoring]
}

resource "unifi_firewall_zone_policy" "mgmt_to_lan" {
  name   = "Management to LAN"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.management.id }
  destination = { zone_id = unifi_firewall_zone.lan.id }

  depends_on = [unifi_firewall_zone_policy.lan_to_mgmt]
}

# ---------------------------------------------------------
# Zone Policies: LAN -> All Lab VLANs (workstation admin)
# ---------------------------------------------------------
# The workstation (MacBook Pro) on the Default LAN is the
# primary admin box. It needs access to ALL lab VLANs for:
#   - Security: Vault API, SSH to vault nodes, GitLab, Wazuh
#   - Services: k3s cluster, standalone services (Plex, Ghost, etc.)
#   - DMZ:      WireGuard, internet-facing services
#   - Storage:  NFS/iSCSI management
# This mirrors Management's full access. Without these
# policies, every new VLAN deployment requires re-debugging
# the same inter-VLAN routing issue.
# ---------------------------------------------------------

resource "unifi_firewall_zone_policy" "lan_to_security" {
  name   = "LAN to Security"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.lan.id }
  destination = { zone_id = unifi_firewall_zone.security.id }

  depends_on = [unifi_firewall_zone_policy.mgmt_to_lan]
}

resource "unifi_firewall_zone_policy" "lan_to_services" {
  name   = "LAN to Services"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.lan.id }
  destination = { zone_id = unifi_firewall_zone.services.id }

  depends_on = [unifi_firewall_zone_policy.lan_to_security]
}

resource "unifi_firewall_zone_policy" "lan_to_dmz" {
  name   = "LAN to DMZ"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.lan.id }
  destination = { zone_id = unifi_firewall_zone.dmz.id }

  depends_on = [unifi_firewall_zone_policy.lan_to_services]
}

resource "unifi_firewall_zone_policy" "lan_to_storage" {
  name   = "LAN to Storage"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.lan.id }
  destination = { zone_id = unifi_firewall_zone.storage.id }

  depends_on = [unifi_firewall_zone_policy.lan_to_dmz]
}

# ---------------------------------------------------------
# Zone Policies: All Lab VLANs -> LAN (return traffic)
# ---------------------------------------------------------
# UniFi zone-based firewall requires explicit return policies.
# Without these, SYN-ACKs from lab VLANs back to the LAN are
# dropped even when the forward policy (LAN -> VLAN) exists.
# This matches the LAN↔Management pattern (lan_to_mgmt +
# mgmt_to_lan) which works because it has both directions.
# ---------------------------------------------------------

resource "unifi_firewall_zone_policy" "security_to_lan" {
  name   = "Security to LAN"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.security.id }
  destination = { zone_id = unifi_firewall_zone.lan.id }

  depends_on = [unifi_firewall_zone_policy.lan_to_storage]
}

resource "unifi_firewall_zone_policy" "services_to_lan" {
  name   = "Services to LAN"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.services.id }
  destination = { zone_id = unifi_firewall_zone.lan.id }

  depends_on = [unifi_firewall_zone_policy.security_to_lan]
}

resource "unifi_firewall_zone_policy" "dmz_to_lan" {
  name   = "DMZ to LAN"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.dmz.id }
  destination = { zone_id = unifi_firewall_zone.lan.id }

  depends_on = [unifi_firewall_zone_policy.services_to_lan]
}

resource "unifi_firewall_zone_policy" "storage_to_lan" {
  name   = "Storage to LAN"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.storage.id }
  destination = { zone_id = unifi_firewall_zone.lan.id }

  depends_on = [unifi_firewall_zone_policy.dmz_to_lan]
}

# ---------------------------------------------------------
# Zone Policies: DMZ -> Services (WireGuard tunnel traffic)
# ---------------------------------------------------------
# The WireGuard gateway LXC on DMZ VLAN 30 forwards public
# traffic from Hetzner (via WireGuard tunnel) to homelab
# services on VLAN 20. NAT/masquerade on the LXC means
# service hosts see source IP 10.0.30.2 (LXC's DMZ addr).
# Port-filtered to minimize DMZ attack surface.
# ---------------------------------------------------------

resource "unifi_firewall_zone_policy" "dmz_to_services_http" {
  name     = "DMZ to Services HTTP"
  action   = "ALLOW"
  protocol = "tcp"

  source      = { zone_id = unifi_firewall_zone.dmz.id }
  destination = {
    zone_id       = unifi_firewall_zone.services.id
    port_group_id = unifi_firewall_group.homelab_service_ports.id
  }

  depends_on = [unifi_firewall_zone_policy.storage_to_lan]
}

# ---------------------------------------------------------
# Zone Policies: Services -> DMZ (return traffic)
# ---------------------------------------------------------
# IMPORTANT: UniFi zone policies are NOT stateful. The
# DMZ->Services ALLOW policy lets the initial TCP SYN through,
# but the SYN-ACK reply (Services->DMZ) is a separate packet
# that needs its own ALLOW. Without this, every connection
# from the WireGuard tunnel to homelab services hangs.
# ---------------------------------------------------------

resource "unifi_firewall_zone_policy" "services_to_dmz" {
  name   = "Services to DMZ"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.services.id }
  destination = { zone_id = unifi_firewall_zone.dmz.id }

  depends_on = [unifi_firewall_zone_policy.dmz_to_services_http]
}

# ---------------------------------------------------------
# Zone Policies: Block cross-VLAN (default deny)
# ---------------------------------------------------------

resource "unifi_firewall_zone_policy" "block_dmz_to_storage" {
  name   = "Block DMZ to Storage"
  action = "BLOCK"

  source      = { zone_id = unifi_firewall_zone.dmz.id }
  destination = { zone_id = unifi_firewall_zone.storage.id }

  depends_on = [unifi_firewall_zone_policy.services_to_dmz]
}

resource "unifi_firewall_zone_policy" "block_dmz_to_security" {
  name   = "Block DMZ to Security"
  action = "BLOCK"

  source      = { zone_id = unifi_firewall_zone.dmz.id }
  destination = { zone_id = unifi_firewall_zone.security.id }

  depends_on = [unifi_firewall_zone_policy.block_dmz_to_storage]
}

# ---------------------------------------------------------
# Zone Policies: IoT (VLAN 60)
# ---------------------------------------------------------
# Home Assistant and IoT devices. Needs:
#   - Management access (admin, Ansible, Traefik proxy)
#   - LAN access (workstation HA dashboard)
#   - Services access (Prometheus scraping, HA→services)
#   - Blocked from Storage, Security, DMZ
# ---------------------------------------------------------

resource "unifi_firewall_zone_policy" "mgmt_to_iot" {
  name   = "Management to IoT"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.management.id }
  destination = { zone_id = unifi_firewall_zone.iot.id }

  depends_on = [unifi_firewall_zone_policy.block_dmz_to_security]
}

resource "unifi_firewall_zone_policy" "iot_to_mgmt" {
  name   = "IoT to Management"
  action = "ALLOW"

  # Return traffic + HA → Authentik OIDC (10.0.10.16)
  source      = { zone_id = unifi_firewall_zone.iot.id }
  destination = { zone_id = unifi_firewall_zone.management.id }

  depends_on = [unifi_firewall_zone_policy.mgmt_to_iot]
}

resource "unifi_firewall_zone_policy" "lan_to_iot" {
  name   = "LAN to IoT"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.lan.id }
  destination = { zone_id = unifi_firewall_zone.iot.id }

  depends_on = [unifi_firewall_zone_policy.iot_to_mgmt]
}

resource "unifi_firewall_zone_policy" "iot_to_lan" {
  name   = "IoT to LAN"
  action = "ALLOW"

  source      = { zone_id = unifi_firewall_zone.iot.id }
  destination = { zone_id = unifi_firewall_zone.lan.id }

  depends_on = [unifi_firewall_zone_policy.lan_to_iot]
}

resource "unifi_firewall_zone_policy" "services_to_iot" {
  name   = "Services to IoT"
  action = "ALLOW"

  # Prometheus scraping HA metrics endpoint
  source      = { zone_id = unifi_firewall_zone.services.id }
  destination = { zone_id = unifi_firewall_zone.iot.id }

  depends_on = [unifi_firewall_zone_policy.iot_to_lan]
}

resource "unifi_firewall_zone_policy" "iot_to_services" {
  name   = "IoT to Services"
  action = "ALLOW"

  # Return traffic + HA → services integration
  source      = { zone_id = unifi_firewall_zone.iot.id }
  destination = { zone_id = unifi_firewall_zone.services.id }

  depends_on = [unifi_firewall_zone_policy.services_to_iot]
}

resource "unifi_firewall_zone_policy" "block_dmz_to_iot" {
  name   = "Block DMZ to IoT"
  action = "BLOCK"

  source      = { zone_id = unifi_firewall_zone.dmz.id }
  destination = { zone_id = unifi_firewall_zone.iot.id }

  depends_on = [unifi_firewall_zone_policy.iot_to_services]
}

resource "unifi_firewall_zone_policy" "block_iot_to_dmz" {
  name   = "Block IoT to DMZ"
  action = "BLOCK"

  source      = { zone_id = unifi_firewall_zone.iot.id }
  destination = { zone_id = unifi_firewall_zone.dmz.id }

  depends_on = [unifi_firewall_zone_policy.block_dmz_to_iot]
}

resource "unifi_firewall_zone_policy" "block_iot_to_storage" {
  name   = "Block IoT to Storage"
  action = "BLOCK"

  source      = { zone_id = unifi_firewall_zone.iot.id }
  destination = { zone_id = unifi_firewall_zone.storage.id }

  depends_on = [unifi_firewall_zone_policy.block_iot_to_dmz]
}

resource "unifi_firewall_zone_policy" "block_iot_to_security" {
  name   = "Block IoT to Security"
  action = "BLOCK"

  source      = { zone_id = unifi_firewall_zone.iot.id }
  destination = { zone_id = unifi_firewall_zone.security.id }

  depends_on = [unifi_firewall_zone_policy.block_iot_to_storage]
}

# ---------------------------------------------------------
# Firewall Groups (port groups for zone policies)
# ---------------------------------------------------------

resource "unifi_firewall_group" "vault_api_port" {
  name    = "Vault API Port"
  type    = "port-group"
  members = ["8200"]
}

resource "unifi_firewall_group" "gitlab_ports" {
  name    = "GitLab Ports"
  type    = "port-group"
  members = ["80", "443", "22"]
}

resource "unifi_firewall_group" "wazuh_agent_ports" {
  name    = "Wazuh Agent Ports"
  type    = "port-group"
  members = ["1514", "1515"]
}

resource "unifi_firewall_group" "nfs_ports" {
  name    = "NFS Ports"
  type    = "port-group"
  members = ["2049", "111"]
}

resource "unifi_firewall_group" "iscsi_ports" {
  name    = "iSCSI Ports"
  type    = "port-group"
  members = ["3260"]
}

resource "unifi_firewall_group" "node_exporter_port" {
  name    = "node_exporter Port"
  type    = "port-group"
  members = ["9100"]
}

resource "unifi_firewall_group" "homelab_service_ports" {
  name    = "Homelab Service Ports"
  type    = "port-group"
  # HTTP/HTTPS covers k8s ingress (MetalLB VIP on 10.0.20.220-.250)
  # Standalone service ports: Ghost:2368, Roundcube:8080, Mealie:9000, FoundryVTT:30000
  # Loki NodePort:31100 — honeypot log ingestion from Hetzner Promtail via WireGuard
  # To expose a new service through the WireGuard tunnel: add its port here.
  members = ["80", "443", "2368", "8080", "9000", "30000", "31100"]
}

# ---------------------------------------------------------
# Port Profiles
# ---------------------------------------------------------

resource "unifi_port_profile" "proxmox_trunk" {
  name                  = "Proxmox Trunk"
  forward               = "customize"
  native_networkconf_id = unifi_network.management.id

  # Trunk port allows all lab VLANs
}

resource "unifi_port_profile" "management_access" {
  name                  = "Management Access"
  forward               = "customize"
  native_networkconf_id = unifi_network.management.id
}

resource "unifi_port_profile" "services_access" {
  name                  = "Services Access"
  forward               = "customize"
  native_networkconf_id = unifi_network.services.id
}

resource "unifi_port_profile" "storage_access" {
  name                  = "Storage Access"
  forward               = "customize"
  native_networkconf_id = unifi_network.storage.id
}

resource "unifi_port_profile" "scanner_trunk" {
  name                  = "Scanner Trunk"
  forward               = "all"  # UCG-Fiber zone-based firewall handles filtering — "customize" causes perpetual drift
  native_networkconf_id = local.default_lan_network_id

  # Trunk port for network scanner (lab-08).
  # Native VLAN 1 (Default LAN) — preserves existing 10.0.4.20 address.
  # Tagged VLANs 10/20/30/40/50 — enables L2 scanning via VLAN sub-interfaces.
  # Same trunk mechanism as proxmox_trunk but native on VLAN 1 instead of VLAN 10.
}

resource "unifi_port_profile" "iot_access" {
  name                  = "IoT Access"
  forward               = "customize"
  native_networkconf_id = unifi_network.iot.id
}

resource "unifi_port_profile" "ap_trunk" {
  name                  = "AP Trunk"
  forward               = "all" # Carries AP management (VLAN 1 native) + all SSID VLANs tagged
  # forward = "all" used (not "customize") — same reason as scanner_trunk:
  # "customize" mode causes perpetual Terraform drift on this provider.
  native_networkconf_id = local.default_lan_network_id
}
