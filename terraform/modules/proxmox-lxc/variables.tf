# ---------------------------------------------------------
# Required Variables
# ---------------------------------------------------------

variable "name" {
  description = "Container hostname"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID for this container"
  type        = number
}

variable "proxmox_node" {
  description = "Proxmox node name to deploy on"
  type        = string
}

# ---------------------------------------------------------
# Compute Resources
# ---------------------------------------------------------

variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "Dedicated memory in MB"
  type        = number
  default     = 2048
}

variable "swap_mb" {
  description = "Swap memory in MB"
  type        = number
  default     = 512
}

variable "disk_size_gb" {
  description = "Root disk size in GB"
  type        = number
  default     = 20
}

variable "storage_pool" {
  description = "Proxmox storage pool for the container disk"
  type        = string
  default     = "local-lvm"
}

# ---------------------------------------------------------
# Network
# ---------------------------------------------------------

variable "network_bridge" {
  description = "Network bridge name"
  type        = string
  default     = "vmbr0"
}

variable "vlan_tag" {
  description = "VLAN tag for network segmentation (null for untagged)"
  type        = number
  default     = null
}

variable "ip_address" {
  description = "IP address (CIDR notation) or 'dhcp'"
  type        = string
  default     = "dhcp"
}

variable "gateway" {
  description = "Network gateway IP (required if ip_address is not 'dhcp')"
  type        = string
  default     = ""
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
# Container Configuration
# ---------------------------------------------------------

variable "template" {
  description = "LXC template file ID (e.g., local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst)"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "os_type" {
  description = "Operating system type (ubuntu, debian, centos, etc.)"
  type        = string
  default     = "ubuntu"
}

variable "description" {
  description = "Container description"
  type        = string
  default     = "Managed by Terraform"
}

variable "tags" {
  description = "Additional tags for the container"
  type        = list(string)
  default     = []
}

variable "docker_enabled" {
  description = "Enable Docker support (nesting feature)"
  type        = bool
  default     = true
}

variable "started" {
  description = "Whether the container should be started"
  type        = bool
  default     = true
}

variable "start_on_boot" {
  description = "Whether the container should start on host boot"
  type        = bool
  default     = true
}

# ---------------------------------------------------------
# SSH
# ---------------------------------------------------------

variable "additional_ssh_key" {
  description = "Additional SSH public key to add to the container (e.g., your personal key)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# Startup Order
# ---------------------------------------------------------

variable "startup_order" {
  description = "Boot order (lower = starts earlier)"
  type        = string
  default     = "3"
}

variable "startup_up_delay" {
  description = "Delay in seconds before starting the next resource"
  type        = string
  default     = "60"
}

variable "startup_down_delay" {
  description = "Delay in seconds before stopping the next resource"
  type        = string
  default     = "30"
}
