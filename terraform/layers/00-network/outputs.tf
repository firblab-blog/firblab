output "vlan_ids" {
  description = "Map of VLAN names to VLAN IDs"
  value = {
    management = 10
    services   = 20
    dmz        = 30
    storage    = 40
    security   = 50
    iot        = 60
  }
}

output "network_ids" {
  description = "Map of VLAN names to UniFi network resource IDs"
  value = {
    default    = nonsensitive(local.default_lan_network_id)
    management = unifi_network.management.id
    services   = unifi_network.services.id
    dmz        = unifi_network.dmz.id
    storage    = unifi_network.storage.id
    security   = unifi_network.security.id
    iot        = unifi_network.iot.id
  }
}

output "subnets" {
  description = "Map of VLAN names to subnets"
  value = {
    management = "10.0.10.0/24"
    services   = "10.0.20.0/24"
    dmz        = "10.0.30.0/24"
    storage    = "10.0.40.0/24"
    security   = "10.0.50.0/24"
    iot        = "10.0.60.0/24"
  }
}

output "port_profile_ids" {
  description = "Map of port profile names to IDs"
  value = {
    proxmox_trunk     = unifi_port_profile.proxmox_trunk.id
    management_access = unifi_port_profile.management_access.id
    services_access   = unifi_port_profile.services_access.id
    storage_access    = unifi_port_profile.storage_access.id
    scanner_trunk     = unifi_port_profile.scanner_trunk.id
    iot_access        = unifi_port_profile.iot_access.id
  }
}

output "device_ids" {
  description = "Map of switch names to UniFi device resource IDs"
  value = {
    switch_closet   = unifi_device.switch_closet.id
    switch_minilab  = unifi_device.switch_minilab.id
    switch_rackmate = unifi_device.switch_rackmate.id
    switch_pro_xg8  = unifi_device.switch_pro_xg8.id
  }
}
