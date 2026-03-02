# =============================================================================
# Layer 00: Managed Switch Devices
# =============================================================================
# Defines UniFi switch devices and their port-to-profile assignments.
# Port overrides assign VLAN port profiles to specific physical switch ports,
# ensuring deterministic VLAN enforcement at the physical layer.
#
# Four switches are directly connected to gw-01 (flat topology):
#   - switch-01 (closet, USW Flex 2.5G 5)  → gw-01 2.5G Port 1
#   - switch-02 (minilab, USW Flex 2.5G 8)  → gw-01 2.5G Port 2
#   - switch-03 (rackmate, USW Flex 2.5G 5) → gw-01 2.5G Port 3
#   - switch-04 (closet, USW Pro XG 8 PoE)  → gw-01 SFP+ 1 (10G DAC)
#
# Uplink ports are NOT overridden — they are auto-managed by the controller.
#
# See docs/NETWORK.md "Physical Switch Port Assignments" for the full mapping.
#
# Apply strategy:
#   1. Import existing devices: terraform import unifi_device.switch_closet <mac>
#   2. terraform plan — verify only port overrides are added
#   3. terraform apply — assigns profiles (no traffic disruption for VLAN 10 devices)
# =============================================================================

# ---------------------------------------------------------
# Switch A: USW Flex 2.5G 5-port (closet)
# ---------------------------------------------------------
# Uplink: Port 5 → gw-01 Port 8
#
# Port 1: lab-01 (Proxmox Trunk)
# Port 2: TrueNAS — Storage Access (VLAN 40, static 10.0.40.2)
# Port 3: lab-04 (Proxmox Trunk)
# Port 4: lab-08 (Scanner Trunk)
# Port 5: gw-01 uplink — auto-managed
# ---------------------------------------------------------

resource "unifi_device" "switch_closet" {
  mac  = local.switch_closet_mac
  name = "switch-01"

  # Port 1: FREED — lab-01 moved to switch-04 (Pro XG 8) Port 1

  # Port 2: TrueNAS — Storage VLAN 40 (static 10.0.40.2)
  # Dell OptiPlex 3070: i5-9500, 16 GB RAM, NFS/SMB + Plex/Immich/Paperless apps
  port_override {
    number          = 2
    name            = "TrueNAS"
    port_profile_id = unifi_port_profile.storage_access.id
  }

  # Port 3: lab-04 — lightweight compute (Dell Wyse, J5005, 20GB)
  # Proxmox Trunk: native VLAN 10, tagged 20/30/40/50
  port_override {
    number          = 3
    name            = "lab-04"
    port_profile_id = unifi_port_profile.proxmox_trunk.id
  }

  # Port 4: lab-08 — RPi4 network scanner + NUT UPS server (NVMe via USB enclosure)
  # Scanner Trunk: native VLAN 1, tagged 10/20/30/40/50
  # Enables full L2 scanning across all VLANs via VLAN sub-interfaces
  port_override {
    number          = 4
    name            = "lab-08 (Scanner)"
    port_profile_id = unifi_port_profile.scanner_trunk.id
  }
}

# ---------------------------------------------------------
# Switch B: USW Flex 2.5G 8 (minilab)
# ---------------------------------------------------------
# 10 physical ports: 8 copper + 1 uplink (port 9) + 1 SFP (port 10)
# Uplink: Port 9 → gw-01 Port 7
#
# Port 1: lab-03 (Proxmox Trunk)
# Port 2: JetKVM (Management Access)
# Port 3: Mac Mini / vault-1 (Management Access)
# Port 4: lab-02 (Proxmox Trunk)
# Port 5: RPi5 CM5 / vault-3 (Management Access)
# Port 6-7: Empty — no override
# Port 8: lab-11 / CM4 8GB — Home Assistant (IoT Access — VLAN 60)
# Port 9: gw-01 uplink — auto-managed
# Port 10: SFP, empty — no override
# ---------------------------------------------------------

resource "unifi_device" "switch_minilab" {
  mac  = local.switch_minilab_mac
  name = "switch-02"

  # Port 1: lab-03 — lightweight services (N100, 12GB)
  # Proxmox Trunk: native VLAN 10, tagged 20/30/40/50
  port_override {
    number          = 1
    name            = "lab-03"
    port_profile_id = unifi_port_profile.proxmox_trunk.id
  }

  # Port 2: JetKVM — KVM-over-IP for Mac Mini management
  # Management Access: VLAN 10 untagged
  port_override {
    number          = 2
    name            = "JetKVM"
    port_profile_id = unifi_port_profile.management_access.id
  }

  # Port 3: Mac Mini — vault-1 primary (macOS native)
  # Management Access: VLAN 10 untagged
  port_override {
    number          = 3
    name            = "Mac Mini (vault-1)"
    port_profile_id = unifi_port_profile.management_access.id
  }

  # Port 4: lab-02 — pilot node (N100, 16GB)
  # Proxmox Trunk: native VLAN 10, tagged 20/30/40/50
  port_override {
    number          = 4
    name            = "lab-02"
    port_profile_id = unifi_port_profile.proxmox_trunk.id
  }

  # Port 5: RPi5 CM5 — vault-3 standby (Ubuntu 24.04 ARM64)
  # Management Access: VLAN 10 untagged
  port_override {
    number          = 5
    name            = "RPi5 CM5 (vault-3)"
    port_profile_id = unifi_port_profile.management_access.id
  }

  # Port 8: lab-11 — Home Assistant (RPi CM4 8GB, HAOS)
  # IoT Access: VLAN 60 untagged
  port_override {
    number          = 8
    name            = "lab-11 (Home Assistant)"
    port_profile_id = unifi_port_profile.iot_access.id
  }
}

# ---------------------------------------------------------
# Switch C: USW Flex 2.5G 5-port (rackmate)
# ---------------------------------------------------------
# K3s RPi5 cluster + archive appliance.
# Uplink: Port 5 → gw-01 Port 5 (FE)
#
# Port 1: k3s-server-1 / RPi5 8GB (Services Access — VLAN 20)
# Port 2: k3s-server-2 / RPi5 8GB (Services Access — VLAN 20)
# Port 3: k3s-server-3 / RPi5 4GB (Services Access — VLAN 20)
# Port 4: lab-09 / ZimaBlade 7700 (Services Access — VLAN 20)
# Port 5: gw-01 uplink — auto-managed
# ---------------------------------------------------------

resource "unifi_device" "switch_rackmate" {
  mac  = local.switch_rackmate_mac
  name = "switch-03"

  # Port 1: k3s-server-1 / RPi5 8GB — K3s cluster node
  # Services Access: VLAN 20 untagged
  port_override {
    number          = 1
    name            = "k3s-server-1 (RPi5 8GB)"
    port_profile_id = unifi_port_profile.services_access.id
  }

  # Port 2: k3s-server-2 / RPi5 8GB — K3s cluster node
  # Services Access: VLAN 20 untagged
  port_override {
    number          = 2
    name            = "k3s-server-2 (RPi5 8GB)"
    port_profile_id = unifi_port_profile.services_access.id
  }

  # Port 3: k3s-server-3 / RPi5 4GB — K3s cluster node
  # Services Access: VLAN 20 untagged
  port_override {
    number          = 3
    name            = "k3s-server-3 (RPi5 4GB)"
    port_profile_id = unifi_port_profile.services_access.id
  }

  # Port 4: lab-09 / ZimaBlade 7700 — archive appliance
  # MAC: 52:54:00:11:22:09 — Services VLAN 20 (untagged)
  port_override {
    number          = 4
    name            = "lab-09 (Archive)"
    port_profile_id = unifi_port_profile.services_access.id
  }

  # Port 5: gw-01 uplink — auto-managed
}

# ---------------------------------------------------------
# Switch D: USW Pro XG 8 PoE (closet, 10G backbone)
# ---------------------------------------------------------
# 10G multi-speed switch providing high-bandwidth uplink to
# gw-01 via SFP+ DAC and 10G connectivity for lab-01
# via Mellanox CX4121C dual-SFP28 NIC.
#
# Uplink: SFP+ 2 (port 10) → gw-01 (10G DAC) — auto-managed
#
# 10G Port 1: (empty — lab-01 onboard 1GbE disconnected, migrated to SFP+ 1)
# 10G Port 2: U7 Pro (AP Trunk — native VLAN 1, all SSIDs tagged)
# 10G Port 3-8: (future)
# SFP+ 1 (port 9): lab-01 (Proxmox Trunk) via Mellanox CX4121C Port 1
# SFP+ 2 (port 10): gw-01 uplink — auto-managed
#
# Note: lab-01's Mellanox Port 2 is a direct DAC to TrueNAS
# (point-to-point storage link, 10.10.10.1/30 ↔ 10.10.10.2/30).
# Not switch-connected.
# ---------------------------------------------------------

resource "unifi_device" "switch_pro_xg8" {
  mac  = local.switch_pro_xg8_mac
  name = "switch-04"

  # 10G Port 2: U7 Pro — wireless AP
  # AP Trunk: native VLAN 1 (AP management/adoption), all SSID VLANs tagged
  # PoE++ provides more than enough power; frees up a gateway LAN port
  port_override {
    number          = 2
    name            = "U7 Pro"
    port_profile_id = unifi_port_profile.ap_trunk.id
  }

  # SFP+ 1 (port 9): lab-01 — main compute node (i9-12900K, 64GB)
  # Proxmox Trunk: native VLAN 10, tagged 20/30/40/50
  # Connected via Mellanox CX4121C SFP28 Port 1 (10G DAC)
  # Confirmed: SFP+ 1 = port 9, SFP+ 2 = port 10 (uplink) in UniFi controller.
  port_override {
    number          = 9
    name            = "lab-01 (10G)"
    port_profile_id = unifi_port_profile.proxmox_trunk.id
  }
}
