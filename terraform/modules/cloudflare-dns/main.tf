terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.0"
    }
  }
}

# ---------------------------------------------------------
# Zone Data Lookup
# ---------------------------------------------------------

data "cloudflare_zone" "this" {
  filter = {
    name = var.domain_name
  }
}

# ---------------------------------------------------------
# DNS Records
# ---------------------------------------------------------

locals {
  # Build a map keyed by a unique identifier for each record
  records_map = {
    for idx, record in var.records :
    "${record.name}-${record.type}-${idx}" => record
  }
}

resource "cloudflare_dns_record" "records" {
  for_each = local.records_map

  zone_id  = data.cloudflare_zone.this.id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  proxied  = each.value.proxied
  priority = each.value.priority
  comment  = each.value.comment
  ttl      = each.value.ttl
}
