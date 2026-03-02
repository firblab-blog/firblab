output "zone_id" {
  description = "Cloudflare zone ID"
  value       = data.cloudflare_zone.this.id
}

output "record_ids" {
  description = "Map of record identifier to Cloudflare record ID"
  value       = { for k, v in cloudflare_dns_record.records : k => v.id }
}

output "domain_name" {
  description = "Domain name of the zone"
  value       = var.domain_name
}
