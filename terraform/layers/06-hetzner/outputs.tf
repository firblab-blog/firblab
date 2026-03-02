# =============================================================================
# Layer 06: Hetzner - Outputs
# =============================================================================

# ---------------------------------------------------------
# Gateway Server Outputs
# ---------------------------------------------------------

output "server_ip" {
  description = "Public IPv4 address of the Hetzner gateway server"
  value       = module.server.server_ip
}

output "server_id" {
  description = "Hetzner Cloud server ID (gateway)"
  value       = module.server.server_id
}

output "server_name" {
  description = "Hetzner Cloud server name (gateway)"
  value       = module.server.server_name
}

# ---------------------------------------------------------
# Honeypot Server Outputs
# ---------------------------------------------------------

output "honeypot_server_ip" {
  description = "Public IPv4 address of the Hetzner honeypot server"
  value       = module.honeypot_server.server_ip
}

output "honeypot_server_id" {
  description = "Hetzner Cloud server ID (honeypot)"
  value       = module.honeypot_server.server_id
}

output "honeypot_server_name" {
  description = "Hetzner Cloud server name (honeypot)"
  value       = module.honeypot_server.server_name
}

# ---------------------------------------------------------
# DNS Outputs
# ---------------------------------------------------------

output "dns_zone_id" {
  description = "Cloudflare DNS zone ID for the domain"
  value       = module.dns.zone_id
}

output "dns_domain" {
  description = "Primary domain name"
  value       = module.dns.domain_name
}

output "dns_record_ids" {
  description = "Map of DNS record identifiers to Cloudflare record IDs"
  value       = module.dns.record_ids
}

# ---------------------------------------------------------
# Service Credentials (sensitive)
# ---------------------------------------------------------

output "gotify_password" {
  description = "Gotify admin password"
  value       = random_password.gotify.result
  sensitive   = true
}

output "traefik_dashboard_password" {
  description = "Traefik dashboard password (user: admin)"
  value       = random_password.traefik_dashboard.result
  sensitive   = true
}

output "adguard_password" {
  description = "AdGuard Home admin password"
  value       = random_password.adguard.result
  sensitive   = true
}

# ---------------------------------------------------------
# Connection Summary
# ---------------------------------------------------------

output "gateway_summary" {
  description = "Gateway server configuration summary"
  value = {
    server_name    = module.server.server_name
    server_type    = var.server_type
    location       = var.location
    image          = var.image
    ipv4_address   = module.server.server_ip
    domain         = local.domain_name
    wireguard_port = var.wireguard_port
  }
}

output "ssh_command" {
  description = "SSH command to connect to the gateway (port 2222 — non-standard port to reduce bot noise)"
  value       = "ssh -p 2222 root@${module.server.server_ip}"
}

output "honeypot_summary" {
  description = "Honeypot server configuration summary"
  value = {
    server_name  = module.honeypot_server.server_name
    server_type  = var.honeypot_server_type
    location     = var.location
    image        = var.image
    ipv4_address = module.honeypot_server.server_ip
    dns_record   = "honeypot.${local.domain_name}"
  }
}

output "honeypot_ssh_command" {
  description = "SSH command to connect to the honeypot (port 2222 — port 22 is Cowrie)"
  value       = "ssh -p 2222 root@${module.honeypot_server.server_ip}"
}
