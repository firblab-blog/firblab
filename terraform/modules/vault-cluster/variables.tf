# ---------------------------------------------------------
# Required Variables
# ---------------------------------------------------------

variable "nodes" {
  description = "List of all Vault cluster nodes (Terraform manages proxmox-vm types, Ansible manages the rest)"
  type = list(object({
    node_id     = string
    address     = string
    node_type   = string # "proxmox-vm", "bare-metal", "rpi"
    description = string
  }))

  validation {
    condition     = length(var.nodes) >= 1
    error_message = "At least one Vault node must be defined."
  }
}

variable "nodes_config" {
  description = "Per-node Proxmox configuration (only needed for proxmox-vm type nodes, keyed by node_id)"
  type = map(object({
    vm_id          = number
    proxmox_node   = string
    storage_pool   = optional(string, "local-lvm")
    snippet_storage = optional(string, "local")
    network_bridge = optional(string, "vmbr0")
    vlan_tag       = optional(number, 50)
    subnet_mask    = optional(string, "24")
    gateway        = optional(string, "10.0.50.1")
  }))
  default = {}
}

variable "ssh_public_key" {
  description = "SSH public key for VM access (added alongside auto-generated keys)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# Vault Configuration
# ---------------------------------------------------------

variable "vault_version" {
  description = "HashiCorp Vault version to install"
  type        = string
  default     = "1.17.6"
}

variable "api_port" {
  description = "Vault API listener port"
  type        = number
  default     = 8200
}

variable "cluster_port" {
  description = "Vault cluster (Raft) communication port"
  type        = number
  default     = 8201
}

variable "domain_name" {
  description = "DNS domain name for Vault nodes"
  type        = string
  default     = "example-lab.local"
}

variable "dns_servers" {
  description = "DNS server addresses"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

# ---------------------------------------------------------
# Compute Resources (for Proxmox VMs)
# ---------------------------------------------------------

variable "cpu_cores" {
  description = "CPU cores per Vault VM"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "Memory in MB per Vault VM"
  type        = number
  default     = 4096
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB"
  type        = number
  default     = 40
}

variable "data_disk_size_gb" {
  description = "Raft data disk size in GB"
  type        = number
  default     = 20
}

# ---------------------------------------------------------
# Cloud Image
# ---------------------------------------------------------

variable "download_cloud_image" {
  description = "Whether to download the cloud image (set false if already available)"
  type        = bool
  default     = true
}

variable "cloud_image_url" {
  description = "URL to download the Ubuntu cloud image from"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "cloud_image_filename" {
  description = "Filename for the downloaded cloud image"
  type        = string
  default     = "noble-server-cloudimg-amd64.qcow2"
}

variable "cloud_init_template" {
  description = "Path to cloud-init template file for Vault VMs"
  type        = string
  default     = ""
}

variable "vm_username" {
  description = "Default username for the Vault VMs"
  type        = string
  default     = "admin"
}
