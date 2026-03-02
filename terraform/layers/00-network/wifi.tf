# =============================================================================
# WiFi Networks (WLANs)
# =============================================================================
# Manages UniFi wireless network SSIDs. Each WLAN is bound to a VLAN via
# network_id, so WiFi clients land on the correct network segment with
# the appropriate firewall zone policies applied.
#
# The UCG-Fiber controller manages WLAN configs; the U7 Pro AP broadcasts them.
#
# Adding a new WiFi network:
#   1. Add a unifi_wlan resource below
#   2. Store passphrase in Vault (vault kv patch secret/infra/unifi key=value)
#   3. Add the local + variable for the passphrase in providers.tf + variables.tf
#   4. terraform apply Layer 00
# =============================================================================

# ---------------------------------------------------------
# Default User Group (rate limiting / bandwidth control)
# ---------------------------------------------------------
# UniFi creates this automatically. Required by unifi_wlan resources.
# ---------------------------------------------------------

data "unifi_user_group" "default" {
  name = "Default"
}

# ---------------------------------------------------------
# Default AP Group (broadcast target for WLANs)
# ---------------------------------------------------------
# The controller creates a default AP group when APs are adopted.
# Omitting `name` returns the default group. Required by the UniFi
# API — WLANs fail with api.err.ApGroupMissing without it.
# ---------------------------------------------------------

data "unifi_ap_group" "default" {}

# ---------------------------------------------------------
# IoT WiFi — "Fellowship of the Ping"
# ---------------------------------------------------------
# Bound to VLAN 60 (IoT). All IoT zone policies apply:
#   - ↔ Management: ALLOW (admin access, Traefik proxy, Authentik OIDC)
#   - ↔ LAN: ALLOW (workstation access to HA dashboard)
#   - ↔ Services: ALLOW (Prometheus scraping, HA integrations)
#   - → Storage: BLOCK
#   - → Security: BLOCK
#   - → DMZ: BLOCK
#
# Security: WPA2/WPA3 transitional (WPA3 for capable devices,
# WPA2 fallback for older IoT hardware). L2 client isolation
# prevents compromised IoT devices from attacking each other.
# ---------------------------------------------------------

resource "unifi_wlan" "iot" {
  name       = "Fellowship of the Ping"
  security   = "wpapsk"
  passphrase = local.iot_wlan_passphrase

  # Bind to IoT VLAN 60, broadcast on all APs
  network_id    = unifi_network.iot.id
  user_group_id = data.unifi_user_group.default.id
  ap_group_ids  = [data.unifi_ap_group.default.id]

  # WPA2/WPA3 transitional mode — many IoT devices only support WPA2
  wpa3_support    = true
  wpa3_transition = true
  pmf_mode        = "optional" # Required for WPA3, optional allows WPA2 fallback

  # Broadcast on both bands — most IoT devices use 2.4 GHz (better range)
  wlan_band  = "both"
  no2ghz_oui = false # Allow 2.4 GHz for devices that need it

  # Security hardening
  l2_isolation = true # Isolate clients from each other at L2

  # Roaming (useful if multiple APs are added later)
  fast_roaming_enabled = true
  bss_transition       = true
}
