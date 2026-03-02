# =============================================================================
# CyberSecure Settings (IDS/IPS, DPI, SSL Inspection)
# =============================================================================
# Manages UCG-Fiber CyberSecure features via Terraform. These are site-wide
# singleton settings — one resource of each type per UniFi site.
#
# What Terraform manages:
#   - IDS/IPS mode and per-VLAN enablement
#   - Threat category selection
#   - P2P/torrent blocking
#   - Deep Packet Inspection (app identification/fingerprinting)
#   - SSL inspection mode (kept off — we manage TLS ourselves)
#
# What requires manual UI configuration:
#   - DNS content filtering (provider bug: Read returns empty, causes drift)
#   - Ad blocking per VLAN (provider bug: Read returns empty, causes drift)
#   - Region/Country blocking (no provider resource)
#   - Encrypted DNS / DoH/DoT enforcement (no provider resource)
#   - Per-app blocking rules (no provider resource)
#   - Traffic logging/analytics (no provider resource)
#
# Provider bugs (filipowm/unifi v1.0.x):
#   dns_filters — Write succeeds but Read returns [], causing "element vanished"
#   ad_blocked_networks — same Read issue, plus sensitive value mismatch
#   These features WORK on the controller but can't be round-tripped in state.
#   Configure via UCG-Fiber UI → CyberSecure → Content Filter / Ad Blocking.
#
# Requires: filipowm/unifi provider >= 1.0.0, UniFi controller >= 8.0
# =============================================================================

# ---------------------------------------------------------
# IDS/IPS
# ---------------------------------------------------------
# IPS mode actively blocks threats (not just detection like IDS).
# UCG-Fiber has hardware offload so throughput impact is minimal.
# ---------------------------------------------------------

resource "unifi_setting_ips" "main" {
  ips_mode = "ips"

  # Enable IPS on ALL VLANs — detect lateral movement across every segment.
  # UCG-Fiber hardware offload handles the throughput. Even Storage (VLAN 40)
  # benefits from IPS for detecting compromised hosts trying to exfiltrate
  # via NFS/iSCSI paths.
  enabled_networks = [
    local.default_lan_network_id, # VLAN 1  — workstation (admin box)
    unifi_network.management.id,  # VLAN 10 — Proxmox, Vault, GitLab
    unifi_network.services.id,    # VLAN 20 — RKE2, standalone apps
    unifi_network.dmz.id,         # VLAN 30 — WireGuard, internet-facing
    unifi_network.storage.id,     # VLAN 40 — NFS, iSCSI
    unifi_network.security.id,    # VLAN 50 — Vault cluster
    unifi_network.iot.id,         # VLAN 60 — Home Assistant, IoT
  ]

  # Threat categories — pinned from controller state to prevent drift.
  # These are the Emerging Threats (ET) / Suricata rulesets that the UCG-Fiber
  # enables by default when IPS is activated. Add/remove as needed.
  enabled_categories = [
    # Threat intelligence feeds
    "botcc",                   # Known botnet C&C servers
    "ciarmy",                  # CI Army threat intelligence
    "compromised",             # Known compromised hosts
    "dark-web-blocker-list",   # Dark web exit nodes
    "dshield",                 # DShield top attackers
    "malicious-hosts",         # Known malicious hosts
    "tor",                     # Tor exit nodes

    # Emerging Threats (ET) rulesets
    "emerging-activex",        # ActiveX exploits
    "emerging-attackresponse", # Attack response patterns
    "emerging-dns",            # DNS-based threats
    "emerging-dos",            # Denial of service
    "emerging-exploit",        # Exploit attempts
    "emerging-ftp",            # FTP attacks
    "emerging-games",          # Gaming protocol abuse
    "emerging-icmp",           # ICMP-based attacks
    "emerging-imap",           # IMAP attacks
    "emerging-malware",        # Malware signatures
    "emerging-misc",           # Miscellaneous threats
    "emerging-mobile",         # Mobile malware
    "emerging-netbios",        # NetBIOS/SMB attacks
    "emerging-p2p",            # P2P protocol detection
    "emerging-pop3",           # POP3 attacks
    "emerging-rpc",            # RPC-based attacks
    "emerging-scan",           # Network scanning
    "emerging-shellcode",      # Shellcode detection
    "emerging-smtp",           # SMTP attacks
    "emerging-snmp",           # SNMP attacks
    "emerging-sql",            # SQL injection
    "emerging-telnet",         # Telnet attacks
    "emerging-tftp",           # TFTP attacks
    "emerging-useragent",      # Suspicious user agents
    "emerging-voip",           # VoIP protocol abuse
    "emerging-webapps",        # Web application attacks
    "emerging-webclient",      # Web client exploits
    "emerging-webserver",      # Web server attacks
    "emerging-worm",           # Worm propagation
  ]

  # Block P2P/torrent traffic — no legitimate use case in this homelab
  restrict_torrents = true

  # --- Provider Bug Workarounds ---
  # dns_filters and ad_blocked_networks are NOT managed here because the
  # provider's Read function returns empty lists after apply, causing
  # perpetual "element vanished" errors. Configure these via the UI.
  #
  # Ad Blocking (UCG-Fiber → CyberSecure → Ad Blocking):
  #   ✅ IoT (VLAN 60): Enabled
  #   ✅ Default LAN (VLAN 1): Enabled
  #
  # Region/Country Blocking (no provider resource):
  #   ✅ Configured via UI (RU, CN, KP, IR + additional countries)
  #
  # DNS Content Filtering: Not configured (skipped for now)
}

# ---------------------------------------------------------
# Deep Packet Inspection (DPI)
# ---------------------------------------------------------
# Enables application identification and traffic fingerprinting.
# This provides visibility into what applications are using the
# network (visible in the UniFi dashboard under Traffic).
# Does NOT block anything — just identifies and categorizes.
# ---------------------------------------------------------

resource "unifi_setting_dpi" "main" {
  enabled                = true
  fingerprinting_enabled = true
}

# ---------------------------------------------------------
# SSL Inspection — Explicitly Off
# ---------------------------------------------------------
# We manage TLS ourselves at the application layer:
#   - Vault: CA-signed TLS (own PKI)
#   - Traefik: Let's Encrypt ACME via DNS-01
#   - K8s: cert-manager with Let's Encrypt
#
# Gateway-level MITM inspection would:
#   - Break Vault transit seal (certificate pinning)
#   - Interfere with ACME DNS-01 challenge flows
#   - Add latency to every TLS connection
#   - Require distributing a gateway CA to all hosts
#
# Codified here so the setting is tracked in state and cannot
# be accidentally enabled via the UI without a Terraform diff.
# ---------------------------------------------------------

resource "unifi_setting_ssl_inspection" "main" {
  state = "off"
}
