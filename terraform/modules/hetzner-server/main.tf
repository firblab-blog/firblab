terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.45"
    }
  }
}

# ---------------------------------------------------------
# SSH Key
# ---------------------------------------------------------
# Create a new key unless an existing ssh_key_id is provided.
# Hetzner enforces uniqueness on key material — multiple servers
# sharing the same public key must reuse the same hcloud_ssh_key.

resource "hcloud_ssh_key" "default" {
  count      = var.create_ssh_key ? 1 : 0
  name       = "${var.name}-ssh-key"
  public_key = var.ssh_public_key
  labels     = var.labels
}

locals {
  ssh_key_id = var.create_ssh_key ? hcloud_ssh_key.default[0].id : var.ssh_key_id
}

# ---------------------------------------------------------
# Cloud-Init User Data
# ---------------------------------------------------------

locals {
  # Render cloud-init template if a path is provided, otherwise null
  user_data = var.cloud_init_template != "" ? templatefile(var.cloud_init_template, merge(
    {
      hostname = var.name
    },
    var.cloud_init_vars
  )) : null
}

# ---------------------------------------------------------
# Hetzner Cloud Server
# ---------------------------------------------------------

resource "hcloud_server" "this" {
  name        = var.name
  image       = var.image
  server_type = var.server_type
  location    = var.location

  ssh_keys = [local.ssh_key_id]

  labels = var.labels

  # Cloud-init user data (rendered from template if provided)
  user_data = local.user_data

  lifecycle {
    ignore_changes = [
      user_data, # Prevent server replacement on user_data changes
    ]
  }
}

# ---------------------------------------------------------
# Firewall
# ---------------------------------------------------------

resource "hcloud_firewall" "this" {
  name   = "${var.name}-fw"
  labels = var.labels

  dynamic "rule" {
    for_each = var.firewall_rules
    content {
      direction  = rule.value.direction
      protocol   = rule.value.protocol
      port       = rule.value.port
      source_ips = rule.value.source_ips
    }
  }
}

# ---------------------------------------------------------
# Firewall Attachment
# ---------------------------------------------------------

resource "hcloud_firewall_attachment" "this" {
  firewall_id = hcloud_firewall.this.id
  server_ids  = [hcloud_server.this.id]
}
