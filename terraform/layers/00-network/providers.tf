# =============================================================================
# Layer 00: Network Infrastructure - Provider Configuration
# =============================================================================
# IMPORTANT: Run this from a WIRED connection to gw-01.
#            WiFi reconfiguration during apply will drop wireless connections.
#
# Dual-mode authentication: reads UniFi credentials and infrastructure
# metadata from Vault by default (secret/infra/unifi).
# Falls back to variable defaults for bootstrap (before Vault exists).
#
# Normal usage (Vault is running):
#   terraform apply
#
# Bootstrap (no Vault yet):
#   terraform apply -var use_vault=false \
#     -var unifi_api_url="https://10.0.4.1" \
#     -var unifi_api_key="<key>"
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    unifi = {
      source  = "filipowm/unifi"
      version = "~> 1.0.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0.0"
    }
  }
}

# ---------------------------------------------------------
# Vault Provider
# ---------------------------------------------------------

provider "vault" {
  address      = var.vault_addr
  token        = var.vault_token
  ca_cert_file = var.vault_ca_cert != "" ? pathexpand(var.vault_ca_cert) : null
}

# ---------------------------------------------------------
# Read UniFi Credentials from Vault (KV v2)
# ---------------------------------------------------------

data "vault_kv_secret_v2" "unifi" {
  count = var.use_vault ? 1 : 0
  mount = "secret"
  name  = "infra/unifi"
}

locals {
  unifi_api_url = var.use_vault ? data.vault_kv_secret_v2.unifi[0].data["api_url"] : var.unifi_api_url
  unifi_api_key = var.use_vault ? data.vault_kv_secret_v2.unifi[0].data["api_key"] : var.unifi_api_key

  # Infrastructure metadata — read from Vault when available, fall back to variable defaults for bootstrap.
  default_lan_network_id = var.use_vault ? data.vault_kv_secret_v2.unifi[0].data["default_lan_network_id"] : var.default_lan_network_id
  switch_closet_mac      = var.use_vault ? data.vault_kv_secret_v2.unifi[0].data["switch_closet_mac"] : var.switch_closet_mac
  switch_minilab_mac     = var.use_vault ? data.vault_kv_secret_v2.unifi[0].data["switch_minilab_mac"] : var.switch_minilab_mac
  switch_rackmate_mac    = var.use_vault ? data.vault_kv_secret_v2.unifi[0].data["switch_rackmate_mac"] : var.switch_rackmate_mac
  switch_pro_xg8_mac     = var.use_vault ? data.vault_kv_secret_v2.unifi[0].data["switch_pro_xg8_mac"] : var.switch_pro_xg8_mac

  # WiFi passphrases
  iot_wlan_passphrase = var.use_vault ? data.vault_kv_secret_v2.unifi[0].data["iot_wlan_passphrase"] : var.iot_wlan_passphrase
}

# ---------------------------------------------------------
# UniFi Provider
# ---------------------------------------------------------

provider "unifi" {
  api_url        = local.unifi_api_url
  allow_insecure = true # Self-signed cert on gw-01

  # API key auth (recommended for controllers v9.0.108+)
  api_key = local.unifi_api_key != "" ? local.unifi_api_key : null

  # Username/password fallback (only used when api_key is empty and use_vault=false)
  username = local.unifi_api_key == "" ? var.unifi_username : null
  password = local.unifi_api_key == "" ? var.unifi_password : null
}
