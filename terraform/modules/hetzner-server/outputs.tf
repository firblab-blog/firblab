output "server_id" {
  description = "Hetzner server ID"
  value       = hcloud_server.this.id
}

output "server_ip" {
  description = "Server public IPv4 address"
  value       = hcloud_server.this.ipv4_address
}

output "server_ipv6" {
  description = "Server public IPv6 address"
  value       = hcloud_server.this.ipv6_address
}

output "server_name" {
  description = "Server name"
  value       = hcloud_server.this.name
}

output "ssh_key_id" {
  description = "Hetzner SSH key ID (for reuse by other server modules)"
  value       = local.ssh_key_id
}
