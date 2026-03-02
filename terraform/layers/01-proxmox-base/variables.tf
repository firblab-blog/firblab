# =============================================================================
# Layer 01: Proxmox Base - Variables
# =============================================================================

# ---------------------------------------------------------
# Vault Connection (source of truth for secrets)
# ---------------------------------------------------------

variable "use_vault" {
  description = "Read Proxmox credentials from Vault (set false for bootstrap before Vault exists)"
  type        = bool
  default     = true
}

variable "vault_addr" {
  description = "Vault API address"
  type        = string
  default     = "https://10.0.10.10:8200"
}

variable "vault_token" {
  description = "Vault authentication token (reads from VAULT_TOKEN env var or ~/.vault-token)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_ca_cert" {
  description = "Path to Vault TLS CA certificate (empty = use VAULT_CACERT env var)"
  type        = string
  default     = "~/.lab/tls/ca/ca.pem"
}

# ---------------------------------------------------------
# Proxmox Connection
# ---------------------------------------------------------

variable "proxmox_node" {
  description = "Proxmox node name — used for Vault secret lookup and resource targeting"
  type        = string
  default     = "lab-01"
}

variable "proxmox_api_url" {
  description = "Proxmox API URL — only used when use_vault=false (bootstrap)"
  type        = string
  default     = ""
}

variable "proxmox_api_token" {
  description = "Proxmox API token (format: USER@REALM!TOKENID=SECRET) — only used when use_vault=false (bootstrap)"
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------
# Proxmox Nodes
# ---------------------------------------------------------

variable "proxmox_nodes" {
  description = <<-EOT
    Map of Proxmox node names to their configuration.
    Once nodes are clustered, the Proxmox API on any node can manage all of them,
    so all nodes can be listed here and targeted via a single provider endpoint.
  EOT
  type = map(object({
    name = string
    ip   = string
  }))
  default = {
    "lab-01" = {
      name = "lab-01"
      ip   = "10.0.10.42"
    }
    "lab-02" = {
      name = "lab-02"
      ip   = "10.0.10.2"
    }
    "lab-03" = {
      name = "lab-03"
      ip   = "10.0.10.3"
    }
    "lab-04" = {
      name = "lab-04"
      ip   = "10.0.10.4"
    }
  }
}

# ---------------------------------------------------------
# SSH
# ---------------------------------------------------------

variable "ssh_public_key" {
  description = "SSH public key for cloud-init provisioning"
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# Storage
# ---------------------------------------------------------

variable "vm_storage_pool" {
  description = "Proxmox storage pool for VM disks and imported images"
  type        = string
  default     = "local-lvm"
}

variable "iso_storage_pool" {
  description = "Proxmox storage pool for ISOs and cloud images"
  type        = string
  default     = "local"
}

variable "snippet_storage_pool" {
  description = "Proxmox storage pool for cloud-init snippets"
  type        = string
  default     = "local"
}

# ---------------------------------------------------------
# Cloud Image (fallback for VMs not using Packer templates)
# ---------------------------------------------------------

variable "cloud_image_url" {
  description = "URL to download the cloud image from"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "cloud_image_filename" {
  description = "Filename for the downloaded cloud image on Proxmox storage"
  type        = string
  default     = "noble-server-cloudimg-amd64.img"
}

# ---------------------------------------------------------
# Packer ISOs (downloaded to local:iso/ for Packer builds)
# ---------------------------------------------------------

variable "packer_isos" {
  description = "Map of ISOs to download for Packer template builds"
  type = map(object({
    url      = string
    filename = string
    checksum = optional(string, "")
  }))
  default = {
    "ubuntu-24.04" = {
      url      = "https://releases.ubuntu.com/24.04.2/ubuntu-24.04.2-live-server-amd64.iso"
      filename = "ubuntu-24.04.2-live-server-amd64.iso"
    }
    "rocky-9" = {
      url      = "https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9-latest-x86_64-minimal.iso"
      filename = "Rocky-9-latest-x86_64-minimal.iso"
    }
  }
}

# ---------------------------------------------------------
# LXC Container Templates (downloaded to local:vztmpl/)
# ---------------------------------------------------------

variable "lxc_templates" {
  description = "Map of LXC container templates to download for container-based workloads"
  type = map(object({
    url      = string
    filename = string
  }))
  default = {
    "ubuntu-24.04" = {
      url      = "http://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
      filename = "ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    }
  }
}

# ---------------------------------------------------------
# Network
# ---------------------------------------------------------

variable "network_bridge" {
  description = "Default network bridge on Proxmox hosts"
  type        = string
  default     = "vmbr0"
}
