# =============================================================================
# Layer 04: RKE2 Cluster - Variables
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
  description = "Proxmox API token (format: user@realm!token=secret) — only used when use_vault=false (bootstrap)"
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------
# SSH
# ---------------------------------------------------------

variable "ssh_public_key" {
  description = "SSH public key to authorize on all cluster nodes"
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# Cluster Identity
# ---------------------------------------------------------

variable "cluster_name" {
  description = "Name prefix for the RKE2 cluster resources"
  type        = string
  default     = "rke2"
}

variable "vm_id_start" {
  description = "Starting VM ID for cluster nodes (servers first, then agents)"
  type        = number
  default     = 4000
}

# ---------------------------------------------------------
# Server Node Configuration
# ---------------------------------------------------------

variable "master_count" {
  description = "Number of server (control plane) nodes"
  type        = number
  default     = 3
}

variable "master_cpu_cores" {
  description = "Number of CPU cores per server node"
  type        = number
  default     = 2
}

variable "master_memory_mb" {
  description = "Memory in MB per server node"
  type        = number
  default     = 5120
}

variable "master_os_disk_size_gb" {
  description = "OS disk size in GB per server node"
  type        = number
  default     = 40
}

# ---------------------------------------------------------
# Agent Node Configuration
# ---------------------------------------------------------

variable "worker_count" {
  description = "Number of agent (worker) nodes"
  type        = number
  default     = 2
}

variable "worker_cpu_cores" {
  description = "Number of CPU cores per agent node"
  type        = number
  default     = 4
}

variable "worker_memory_mb" {
  description = "Memory in MB per agent node"
  type        = number
  default     = 10240
}

variable "worker_os_disk_size_gb" {
  description = "OS disk size in GB per agent node"
  type        = number
  default     = 40
}

# ---------------------------------------------------------
# Longhorn Data Disk
# ---------------------------------------------------------

variable "data_disk_size_gb" {
  description = "Data disk size in GB for Longhorn storage on all nodes (scsi1)"
  type        = number
  default     = 200
}

variable "data_storage_pool" {
  description = "Proxmox storage pool for Longhorn data disks (empty = same as storage_pool)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# RKE2 Configuration
# ---------------------------------------------------------

variable "rke2_version" {
  description = "RKE2 version to install (DISA STIG-certified distribution)"
  type        = string
  default     = "v1.32.11+rke2r3"
}

# ---------------------------------------------------------
# Template Cloning (Packer-built templates)
# ---------------------------------------------------------

variable "clone_template_vm_id" {
  description = "VM ID of a Packer-built template to clone (0 = disabled, use cloud image instead)"
  type        = number
  default     = 9000
}

variable "clone_template_node" {
  description = "Proxmox node where the Packer template lives (empty = same as proxmox_node)"
  type        = string
  default     = "lab-01"
}

# ---------------------------------------------------------
# Cloud Image (fallback when not cloning from template)
# ---------------------------------------------------------

variable "download_cloud_image" {
  description = "Whether to download the Ubuntu cloud image (set false if already available)"
  type        = bool
  default     = true
}

variable "cloud_image_url" {
  description = "URL to download the Ubuntu 24.04 cloud image from"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "cloud_image_filename" {
  description = "Filename for the downloaded cloud image"
  type        = string
  default     = "noble-server-cloudimg-amd64.qcow2"
}

# ---------------------------------------------------------
# Storage
# ---------------------------------------------------------

variable "storage_pool" {
  description = "Proxmox storage pool for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "snippet_storage" {
  description = "Proxmox storage for cloud-init snippets and images"
  type        = string
  default     = "local"
}

# ---------------------------------------------------------
# IP Address Offsets
# ---------------------------------------------------------

variable "server_ip_offset" {
  description = "Starting last-octet offset for server node IPs (e.g., 40 → .40, .41, .42)"
  type        = number
  default     = 40
}

variable "agent_ip_offset" {
  description = "Starting last-octet offset for agent node IPs (e.g., 50 → .50, .51, .52)"
  type        = number
  default     = 50
}

# ---------------------------------------------------------
# Network Settings (Services VLAN 20)
# ---------------------------------------------------------

variable "network_bridge" {
  description = "Network bridge for cluster nodes"
  type        = string
  default     = "vmbr0"
}

variable "vlan_tag" {
  description = "VLAN tag for cluster nodes (Services VLAN)"
  type        = number
  default     = 20
}

variable "gateway" {
  description = "Network gateway for the Services VLAN"
  type        = string
  default     = "10.0.20.1"
}

variable "domain_name" {
  description = "DNS domain name"
  type        = string
  default     = "example-lab.local"
}

variable "dns_servers" {
  description = "DNS server addresses — use VLAN 20 gateway for internal resolution (*.home.example-lab.org via gw-01)"
  type        = list(string)
  default     = ["10.0.20.1", "1.1.1.1"]
}
