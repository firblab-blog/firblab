# ---------------------------------------------------------
# Required Variables
# ---------------------------------------------------------

variable "proxmox_node" {
  description = "Proxmox node name to deploy the cluster on"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for VM access (added alongside auto-generated keys)"
  type        = string
}

# ---------------------------------------------------------
# Cluster Identity
# ---------------------------------------------------------

variable "cluster_name" {
  description = "Name of the RKE2 cluster (used in hostnames and tags)"
  type        = string
  default     = "rke2"
}

variable "vm_id_start" {
  description = "Starting VM ID for cluster nodes (servers first, then agents)"
  type        = number
  default     = 4000
}

# ---------------------------------------------------------
# Cluster Sizing
# ---------------------------------------------------------

variable "master_count" {
  description = "Number of server (control plane) nodes"
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Number of agent (worker) nodes"
  type        = number
  default     = 3
}

# ---------------------------------------------------------
# Server Compute Resources
# ---------------------------------------------------------

variable "master_cpu_cores" {
  description = "CPU cores per server node"
  type        = number
  default     = 2
}

variable "master_memory_mb" {
  description = "Memory in MB per server node"
  type        = number
  default     = 4096
}

variable "master_os_disk_size_gb" {
  description = "OS disk size in GB per server node"
  type        = number
  default     = 40
}

# ---------------------------------------------------------
# Agent Compute Resources
# ---------------------------------------------------------

variable "worker_cpu_cores" {
  description = "CPU cores per agent node"
  type        = number
  default     = 4
}

variable "worker_memory_mb" {
  description = "Memory in MB per agent node"
  type        = number
  default     = 8192
}

variable "worker_os_disk_size_gb" {
  description = "OS disk size in GB per agent node"
  type        = number
  default     = 40
}

# ---------------------------------------------------------
# Storage
# ---------------------------------------------------------

variable "data_disk_size_gb" {
  description = "Data disk size in GB for Longhorn storage on all nodes"
  type        = number
  default     = 200
}

variable "data_storage_pool" {
  description = "Proxmox storage pool for Longhorn data disks (empty = same as storage_pool)"
  type        = string
  default     = ""
}

variable "storage_pool" {
  description = "Proxmox storage pool for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "snippet_storage" {
  description = "Proxmox storage for cloud-init snippets"
  type        = string
  default     = "local"
}

# ---------------------------------------------------------
# Template Cloning (Packer-built templates)
# ---------------------------------------------------------

variable "clone_template_vm_id" {
  description = "VM ID of a Packer-built template to clone (0 = disabled, use cloud image instead)"
  type        = number
  default     = 0
}

variable "clone_template_node" {
  description = "Proxmox node where the Packer template lives (empty = same as proxmox_node). Enables cross-node cloning."
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# Cloud Image (fallback when not cloning from template)
# ---------------------------------------------------------

variable "download_cloud_image" {
  description = "Whether to download the cloud image (set false if already available, ignored when cloning)"
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

# ---------------------------------------------------------
# IP Address Offsets
# ---------------------------------------------------------
# Last octet offset for server and agent IPs within the VLAN subnet.
# Example: offset 40 with gateway 10.0.20.1 → servers at .40, .41, .42
# Ensure these don't collide with other services on the same VLAN.

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
# Network
# ---------------------------------------------------------

variable "network_bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

variable "vlan_tag" {
  description = "VLAN tag for RKE2 cluster network segmentation"
  type        = number
  default     = 20
}

variable "gateway" {
  description = "Network gateway for the cluster VLAN"
  type        = string
  default     = "10.0.20.1"
}

variable "domain_name" {
  description = "DNS domain name"
  type        = string
  default     = "example-lab.local"
}

variable "dns_servers" {
  description = "DNS server addresses"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

# ---------------------------------------------------------
# SSH Key Injection via QEMU Guest Agent
# ---------------------------------------------------------

variable "proxmox_ssh_host" {
  description = "Proxmox host IP for guest-agent SSH key injection (empty = disabled)"
  type        = string
  default     = ""
}

variable "proxmox_ssh_user" {
  description = "SSH username for Proxmox host"
  type        = string
  default     = "admin"
}

variable "proxmox_ssh_key" {
  description = "Path to SSH private key for Proxmox host (prevents fail2ban by using IdentitiesOnly)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# RKE2 Configuration
# ---------------------------------------------------------

variable "rke2_version" {
  description = "RKE2 version to install on the cluster nodes"
  type        = string
  default     = "v1.32.11+rke2r3"
}
