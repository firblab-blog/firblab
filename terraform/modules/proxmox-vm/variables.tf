# ---------------------------------------------------------
# Required Variables
# ---------------------------------------------------------

variable "name" {
  description = "VM hostname"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID"
  type        = number
}

variable "proxmox_node" {
  description = "Proxmox node name to deploy on"
  type        = string
}

# ---------------------------------------------------------
# Compute Resources
# ---------------------------------------------------------

variable "machine_type" {
  description = "QEMU machine type. Use 'q35' for PCI passthrough (GPU, NIC). Default '' uses Proxmox default (i440fx)."
  type        = string
  default     = ""
}

variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "cpu_type" {
  description = "CPU type (e.g., x86-64-v2-AES, host)"
  type        = string
  default     = "x86-64-v2-AES"
}

variable "memory_mb" {
  description = "Memory in MB (dedicated and floating)"
  type        = number
  default     = 4096
}

# ---------------------------------------------------------
# Storage
# ---------------------------------------------------------

variable "os_disk_size_gb" {
  description = "OS disk size in GB"
  type        = number
  default     = 40
}

variable "data_disks" {
  description = "Additional data disks to attach"
  type = list(object({
    interface = string
    size_gb   = number
  }))
  default = []
}

variable "storage_pool" {
  description = "Proxmox storage pool for VM disks (OS disk and data disks unless data_storage_pool is set)"
  type        = string
  default     = "local-lvm"
}

variable "data_storage_pool" {
  description = "Proxmox storage pool for data disks (defaults to storage_pool if empty). Use to place bulk data on slower/larger storage (e.g., HDD) while keeping OS disk on fast storage (e.g., NVMe)."
  type        = string
  default     = ""
}

variable "snippet_storage" {
  description = "Proxmox storage for cloud-init snippets"
  type        = string
  default     = "local"
}

# ---------------------------------------------------------
# Disk Performance
# ---------------------------------------------------------

variable "disk_discard" {
  description = "Pass discard/TRIM requests to underlying storage (on/ignore). Use 'on' for SSD/NVMe-backed LVM-thin."
  type        = string
  default     = "on"
}

variable "disk_ssd" {
  description = "Present disk as SSD to guest OS. Enables proper I/O scheduler and TRIM awareness."
  type        = bool
  default     = true
}

variable "disk_iothread" {
  description = "Dedicate an I/O thread per disk. Requires virtio-scsi-single controller."
  type        = bool
  default     = true
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
  description = "Proxmox node where the source template lives (empty = same as proxmox_node). Enables cross-node cloning in a cluster."
  type        = string
  default     = ""
}

variable "clone_full" {
  description = "Perform a full clone (true) or linked clone (false)"
  type        = bool
  default     = true
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
  description = "URL to download the cloud image from"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "cloud_image_filename" {
  description = "Filename for the downloaded cloud image"
  type        = string
  default     = "noble-server-cloudimg-amd64.qcow2"
}

variable "import_from" {
  description = "Existing image ID to import from (used when download_cloud_image is false)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# Cloud-Init
# ---------------------------------------------------------

variable "cloud_init_template" {
  description = "Path to cloud-init user-data template file (empty string to skip)"
  type        = string
  default     = ""
}

variable "cloud_init_vars" {
  description = "Additional variables to pass to the cloud-init template"
  type        = map(string)
  default     = {}
}

variable "vm_username" {
  description = "Default username for the VM"
  type        = string
  default     = "admin"
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
# SSH
# ---------------------------------------------------------

variable "additional_ssh_key" {
  description = "Additional SSH public key (e.g., your personal key)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# SSH Key Injection via QEMU Guest Agent
# ---------------------------------------------------------
# Cloud-init key injection is unreliable on Packer template clones.
# When proxmox_ssh_host is set, a local-exec provisioner SSHs to the
# Proxmox host and uses `qm guest exec` to write authorized_keys
# directly inside the VM via the guest agent — guaranteeing SSH access
# regardless of cloud-init behavior.

variable "proxmox_ssh_host" {
  description = "Proxmox host IP for guest-agent SSH key injection (empty = disabled)"
  type        = string
  default     = ""
}

variable "proxmox_ssh_user" {
  description = "SSH username for Proxmox host (used by guest agent key injection)"
  type        = string
  default     = "admin"
}

variable "proxmox_ssh_key" {
  description = "Path to SSH private key for Proxmox host (prevents fail2ban by using IdentitiesOnly)"
  type        = string
  default     = ""
}

variable "vm_ssh_user" {
  description = "Override VM user for SSH key injection (when VM user differs from cloud-init user, e.g., PBS uses root but cloud-init defaults to admin)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# Metadata
# ---------------------------------------------------------

variable "description" {
  description = "VM description"
  type        = string
  default     = "Managed by Terraform"
}

variable "tags" {
  description = "Additional tags for the VM"
  type        = list(string)
  default     = []
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
