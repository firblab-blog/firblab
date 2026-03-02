# ---------------------------------------------------------
# Vault Connection (source of truth for secrets)
# ---------------------------------------------------------

variable "use_vault" {
  description = "Read UniFi credentials from Vault (set false for bootstrap before Vault exists)"
  type        = bool
  default     = true
}

variable "vault_addr" {
  description = "Vault API address"
  type        = string
  default     = "https://10.0.10.10:8200"
}

variable "vault_token" {
  description = "Vault authentication token (reads from VAULT_TOKEN env var or ~/.vault-token)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_ca_cert" {
  description = "Path to Vault TLS CA certificate (empty = use VAULT_CACERT env var)"
  type        = string
  default     = "~/.lab/tls/ca/ca.pem"
}

# ---------------------------------------------------------
# UniFi Connection (bootstrap-only when use_vault=false)
# ---------------------------------------------------------

variable "unifi_username" {
  description = "UniFi controller username — only used when use_vault=false (bootstrap)"
  type        = string
  default     = ""
}

variable "unifi_password" {
  description = "UniFi controller password — only used when use_vault=false (bootstrap)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "unifi_api_url" {
  description = "UniFi controller API URL — only used when use_vault=false (bootstrap)"
  type        = string
  default     = ""
}

variable "unifi_api_key" {
  description = "UniFi API key — only used when use_vault=false (bootstrap)"
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------
# Default LAN (pre-existing network)
# ---------------------------------------------------------
# The Default network is created by UniFi during initial setup
# and is not managed by Terraform. We need its ID to create a
# firewall zone so the workstation can reach the Management VLAN.
#
# Auto-discovered by scripts/seed-unifi-to-vault.sh and stored
# in Vault (secret/infra/unifi). For bootstrap, pass via -var flag.
# ---------------------------------------------------------

variable "default_lan_network_id" {
  description = "UniFi network ID of the pre-existing Default LAN (not managed by Terraform)"
  type        = string
  default     = ""  # From Vault (secret/infra/unifi) or -var flag at bootstrap
}

# ---------------------------------------------------------
# DNS Configuration per VLAN
# ---------------------------------------------------------

variable "management_dns_servers" {
  description = "DNS servers for Management VLAN (gw-01 gateway only — no public DNS, prevents Cloudflare wildcard from overriding *.home.example-lab.org internal records)"
  type        = list(string)
  default     = ["10.0.10.1"]
}

variable "services_dns_servers" {
  description = "DNS servers for Services VLAN (gw-01 gateway only — no public DNS)"
  type        = list(string)
  default     = ["10.0.20.1"]
}

variable "dmz_dns_servers" {
  description = "DNS servers for DMZ VLAN (gw-01 gateway only — no public DNS)"
  type        = list(string)
  default     = ["10.0.30.1"]
}

variable "security_dns_servers" {
  description = "DNS servers for Security VLAN (gw-01 gateway only — no public DNS)"
  type        = list(string)
  default     = ["10.0.50.1"]
}

variable "iot_dns_servers" {
  description = "DNS servers for IoT VLAN (gw-01 gateway only — no public DNS)"
  type        = list(string)
  default     = ["10.0.60.1"]
}

# ---------------------------------------------------------
# Switch MAC Addresses
# ---------------------------------------------------------
# MAC addresses of the four managed switches. Required for
# unifi_device resources. Auto-discovered by
# scripts/seed-unifi-to-vault.sh and stored in Vault
# (secret/infra/unifi). For bootstrap, pass via -var flags.
#
# Format: lowercase colon-separated (aa:bb:cc:dd:ee:ff)
# ---------------------------------------------------------

variable "switch_closet_mac" {
  description = "MAC address of the USW Flex 2.5G 5-port switch (closet, switch-01)"
  type        = string
  default     = ""  # From Vault or -var flag
}

variable "switch_minilab_mac" {
  description = "MAC address of the USW Flex 2.5G 8-port switch (minilab, switch-02)"
  type        = string
  default     = ""  # From Vault or -var flag
}

variable "switch_rackmate_mac" {
  description = "MAC address of the USW Flex 2.5G 5-port switch (rackmate, switch-03)"
  type        = string
  default     = ""  # From Vault or -var flag
}

variable "switch_pro_xg8_mac" {
  description = "MAC address of the USW Pro XG 8 PoE switch (closet, switch-04)"
  type        = string
  default     = ""  # Filled after device adoption
}

# ---------------------------------------------------------
# WiFi Passphrases
# ---------------------------------------------------------

variable "iot_wlan_passphrase" {
  description = "WPA passphrase for the IoT WiFi SSID — only used when use_vault=false (bootstrap)"
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------
# Ansible Provider Gap-Filling
# ---------------------------------------------------------
# Settings the filipowm/unifi provider cannot manage due to
# missing attributes or provider bugs. Passed to the Ansible
# unifi-config role via terraform_data + local-exec (ansible.tf).
#
# See: ansible/roles/unifi-config/defaults/main.yml for the
# full provider gap inventory and migration status.
# ---------------------------------------------------------

variable "switch_stp_priorities" {
  description = <<-EOT
    STP bridge priority per switch device (MAC → priority).
    Valid priorities: multiples of 4096, range 0-61440. Default 32768.
    Lower value = higher priority = more likely to become root bridge.
    The gateway (gw-01) manages its own STP priority.
  EOT
  type        = map(number)
  default = {
    # switch-04 (USW Pro XG 8 PoE, 10G backbone) — root bridge candidate
    "52:54:00:11:22:04" = 4096
    # switch-01 (USW Flex 2.5G 5, closet) — main compute
    "52:54:00:11:22:01" = 8192
    # switch-02 (USW Flex 2.5G 8, minilab) — Vault nodes
    "52:54:00:11:22:02" = 12288
    # switch-03 (USW Flex 2.5G 5, rackmate) — HA, archive
    "52:54:00:11:22:03" = 16384
  }
}
