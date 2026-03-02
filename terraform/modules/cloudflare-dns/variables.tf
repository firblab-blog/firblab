# ---------------------------------------------------------
# Required Variables
# ---------------------------------------------------------

variable "domain_name" {
  description = "Domain name for the Cloudflare zone (e.g., example.com)"
  type        = string
}

# ---------------------------------------------------------
# DNS Records
# ---------------------------------------------------------

variable "records" {
  description = "List of DNS records to create in the zone"
  type = list(object({
    name     = string
    type     = string
    content  = string
    proxied  = optional(bool, false)
    priority = optional(number, null)
    comment  = optional(string, null)
    ttl      = optional(number, 1) # 1 = automatic
  }))
  default = []
}
