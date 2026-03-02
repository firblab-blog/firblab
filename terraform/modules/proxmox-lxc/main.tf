terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.81.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4"
    }
  }
}

# ---------------------------------------------------------
# SSH Key Generation
# ---------------------------------------------------------

resource "tls_private_key" "container_key" {
  algorithm = "ED25519"
}

resource "local_file" "container_private_key" {
  content         = tls_private_key.container_key.private_key_openssh
  filename        = "${path.root}/.secrets/${var.name}_ssh_key"
  file_permission = "0600"
}

# ---------------------------------------------------------
# Password Generation
# ---------------------------------------------------------

resource "random_password" "container_password" {
  length  = 32
  special = true
}

# ---------------------------------------------------------
# Unprivileged LXC Container
# ---------------------------------------------------------

resource "proxmox_virtual_environment_container" "this" {
  node_name = var.proxmox_node
  vm_id     = var.vm_id

  description   = var.description
  tags          = concat(var.tags, ["terraform", "lxc"])
  started       = var.started
  start_on_boot = var.start_on_boot
  unprivileged  = true # Always unprivileged for security

  operating_system {
    template_file_id = var.template
    type             = var.os_type
  }

  cpu {
    cores = var.cpu_cores
    units = 1024
  }

  memory {
    dedicated = var.memory_mb
    swap      = var.swap_mb
  }

  network_interface {
    name    = "eth0"
    bridge  = var.network_bridge
    vlan_id = var.vlan_tag
    enabled = true
  }

  disk {
    datastore_id = var.storage_pool
    size         = var.disk_size_gb
  }

  features {
    nesting = true   # Always enabled — required for systemd 255+ (Ubuntu 24.04) in unprivileged LXC, and for Docker
    keyctl  = false  # Disabled for security
    fuse    = false  # Disabled unless needed
    mount   = []     # No special mount permissions
  }

  console {
    enabled   = true
    tty_count = 2
    type      = "shell"
  }

  initialization {
    hostname = var.name

    user_account {
      keys = compact([
        trimspace(tls_private_key.container_key.public_key_openssh),
        var.additional_ssh_key != "" ? trimspace(var.additional_ssh_key) : "",
      ])
      password = random_password.container_password.result
    }

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.ip_address != "dhcp" ? var.gateway : null
      }
    }

    dns {
      domain  = var.domain_name
      servers = var.dns_servers
    }
  }

  startup {
    order      = var.startup_order
    up_delay   = var.startup_up_delay
    down_delay = var.startup_down_delay
  }

  lifecycle {
    ignore_changes = [
      # Ignore password drift after creation
      initialization[0].user_account[0].password,
      # Bind mounts are applied out-of-band via pct set (local-exec) because
      # bpg/proxmox requires root@pam for bind mounts, not API token auth.
      # Ignoring here prevents Terraform from seeing the mount_point Proxmox
      # reports back and force-replacing the container to remove it.
      mount_point,
    ]
  }
}
