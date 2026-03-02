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
# SSH Key Generation (ED25519 for security)
# ---------------------------------------------------------

resource "tls_private_key" "vm_key" {
  algorithm = "ED25519"
}

resource "local_file" "vm_private_key" {
  content         = tls_private_key.vm_key.private_key_openssh
  filename        = "${path.root}/.secrets/${var.name}_ssh_key"
  file_permission = "0600"
}

# ---------------------------------------------------------
# Password Generation
# ---------------------------------------------------------

resource "random_password" "vm_password" {
  length           = 32
  special          = true
  override_special = "_%@"
}

# ---------------------------------------------------------
# Cloud-Init Configuration
# ---------------------------------------------------------

resource "proxmox_virtual_environment_file" "cloud_config" {
  count = var.cloud_init_template != "" ? 1 : 0

  content_type = "snippets"
  datastore_id = var.snippet_storage
  node_name    = var.proxmox_node

  source_raw {
    data = templatefile(var.cloud_init_template, merge(
      {
        hostname = var.name
        ssh_key  = trimspace(tls_private_key.vm_key.public_key_openssh)
      },
      var.cloud_init_vars
    ))
    file_name = "${var.name}-user-data.yaml"
  }
}

# ---------------------------------------------------------
# VM Provisioning Mode
# ---------------------------------------------------------
# Three mutually exclusive paths:
#   1. clone_template_vm_id > 0  → Clone from Packer template (recommended)
#   2. download_cloud_image      → Download raw cloud image and import
#   3. import_from               → Import from existing image
# ---------------------------------------------------------

locals {
  use_clone       = var.clone_template_vm_id > 0
  use_cloud_image = !local.use_clone && var.download_cloud_image
}

# ---------------------------------------------------------
# Cloud Image Download (fallback when not cloning)
# ---------------------------------------------------------

resource "proxmox_virtual_environment_download_file" "cloud_image" {
  count = local.use_cloud_image ? 1 : 0

  content_type = "import"
  datastore_id = var.snippet_storage
  node_name    = var.proxmox_node
  url          = var.cloud_image_url
  file_name    = var.cloud_image_filename
}

# ---------------------------------------------------------
# Virtual Machine
# ---------------------------------------------------------

resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  description = var.description
  tags        = concat(var.tags, ["terraform", "vm"])

  node_name = var.proxmox_node
  vm_id     = var.vm_id
  machine   = var.machine_type != "" ? var.machine_type : null

  depends_on = [
    proxmox_virtual_environment_file.cloud_config,
    proxmox_virtual_environment_download_file.cloud_image,
  ]

  agent {
    enabled = true
  }

  stop_on_destroy = true

  # Clone from Packer-built template (when clone_template_vm_id > 0)
  # node_name enables cross-node cloning — template on one node, VM on another.
  dynamic "clone" {
    for_each = local.use_clone ? [1] : []
    content {
      vm_id     = var.clone_template_vm_id
      node_name = var.clone_template_node != "" ? var.clone_template_node : null
      full      = var.clone_full
    }
  }

  startup {
    order      = var.startup_order
    up_delay   = var.startup_up_delay
    down_delay = var.startup_down_delay
  }

  cpu {
    cores = var.cpu_cores
    type  = var.cpu_type
  }

  memory {
    dedicated = var.memory_mb
    floating  = var.memory_mb
  }

  # Primary OS disk
  # When cloning: disk is inherited from template, import_from is omitted
  # When not cloning: import from downloaded cloud image or existing image
  disk {
    datastore_id = var.storage_pool
    import_from = local.use_clone ? null : (
      local.use_cloud_image ? proxmox_virtual_environment_download_file.cloud_image[0].id : var.import_from
    )
    interface = "scsi0"
    size      = var.os_disk_size_gb
    discard   = var.disk_discard
    ssd       = var.disk_ssd
    iothread  = var.disk_iothread
  }

  # Additional data disks
  # Uses data_storage_pool if set, otherwise falls back to storage_pool.
  # This enables tiered storage: OS disk on fast NVMe, data on HDD.
  dynamic "disk" {
    for_each = var.data_disks
    content {
      datastore_id = var.data_storage_pool != "" ? var.data_storage_pool : var.storage_pool
      interface    = disk.value.interface
      size         = disk.value.size_gb
      discard      = var.disk_discard
      ssd          = var.disk_ssd
      iothread     = var.disk_iothread
    }
  }

  initialization {
    datastore_id = var.storage_pool

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

    user_account {
      keys = compact([
        trimspace(tls_private_key.vm_key.public_key_openssh),
        var.additional_ssh_key != "" ? trimspace(var.additional_ssh_key) : "",
      ])
      password = random_password.vm_password.result
      username = var.vm_username
    }

    user_data_file_id = var.cloud_init_template != "" ? proxmox_virtual_environment_file.cloud_config[0].id : null
  }

  network_device {
    bridge  = var.network_bridge
    vlan_id = var.vlan_tag
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [
      clone,  # Only relevant at creation time — prevents destroy/recreate on drift
      initialization[0].user_account[0].password,
    ]
  }
}

# ---------------------------------------------------------
# SSH Key Injection via QEMU Guest Agent (belt + suspenders)
# ---------------------------------------------------------
# Cloud-init key injection is unreliable on Packer template clones.
# When proxmox_ssh_host is set, this provisioner SSHs to the Proxmox
# host and uses `qm guest exec` to write authorized_keys directly
# inside the VM via the guest agent — guaranteeing SSH access
# regardless of cloud-init behavior.

resource "terraform_data" "ssh_key_injection" {
  count = var.proxmox_ssh_host != "" ? 1 : 0

  triggers_replace = [
    proxmox_virtual_environment_vm.this.id,
    tls_private_key.vm_key.public_key_openssh,
  ]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${path.module}/scripts/inject-ssh-keys.sh"
    environment = {
      PROXMOX_HOST    = var.proxmox_ssh_host
      PROXMOX_USER    = var.proxmox_ssh_user
      PROXMOX_SSH_KEY = var.proxmox_ssh_key
      VM_ID           = proxmox_virtual_environment_vm.this.vm_id
      VM_USER         = var.vm_ssh_user != "" ? var.vm_ssh_user : var.vm_username
      SSH_PUB_KEY     = trimspace(tls_private_key.vm_key.public_key_openssh)
      EXTRA_KEY       = var.additional_ssh_key
    }
  }
}
