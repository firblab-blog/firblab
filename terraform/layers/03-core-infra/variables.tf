# =============================================================================
# Layer 03: Core Infrastructure - Variables
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
  description = "Additional SSH public key to authorize on all services"
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# Shared Infrastructure Settings
# ---------------------------------------------------------

variable "storage_pool" {
  description = "Proxmox storage pool for OS disks (NVMe recommended)"
  type        = string
  default     = "local-lvm"
}

variable "data_storage_pool" {
  description = "Proxmox storage pool for data disks — repos, logs, artifacts. Defaults to storage_pool if empty."
  type        = string
  default     = "ssd-data-02"
}

variable "snippet_storage" {
  description = "Proxmox storage for cloud-init snippets and images"
  type        = string
  default     = "local"
}

variable "clone_template_vm_id" {
  description = "VM ID of a Packer-built hardened template to clone (0 = use cloud image fallback — NOT recommended, will force-replace existing cloned VMs)"
  type        = number
  default     = 9000
}

variable "clone_template_node" {
  description = "Proxmox node where the Packer template lives (empty = same as proxmox_node). Enables cross-node cloning."
  type        = string
  default     = ""
}

variable "download_cloud_image" {
  description = "Whether to download the Ubuntu cloud image (set false if already available, ignored when cloning)"
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
# Network Settings (Management Network — untagged on vmbr0)
# ---------------------------------------------------------

variable "network_bridge" {
  description = "Network bridge for all services"
  type        = string
  default     = "vmbr0"
}

variable "vlan_tag" {
  description = "VLAN tag for all services (null = untagged, native bridge network)"
  type        = number
  default     = null
}

variable "gateway" {
  description = "Network gateway for the Management VLAN"
  type        = string
  default     = "10.0.10.1"
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
# GitLab CE (VM)
# ---------------------------------------------------------

variable "gitlab_proxmox_node" {
  description = "Proxmox node for GitLab VM placement (separate from Runner for independent node moves)"
  type        = string
  default     = "lab-01"
}

variable "gitlab_storage_pool" {
  description = "Storage pool for GitLab OS disk. Restored from PBS to nvme-thin-1 on lab-01."
  type        = string
  default     = "nvme-thin-1"
}

variable "gitlab_data_storage_pool" {
  description = "Storage pool for GitLab data disk. Restored from PBS to nvme-thin-1 on lab-01."
  type        = string
  default     = "nvme-thin-1"
}

variable "gitlab_vm_id" {
  description = "Proxmox VM ID for GitLab CE"
  type        = number
  default     = 3001
}

variable "gitlab_name" {
  description = "Hostname for GitLab CE VM"
  type        = string
  default     = "gitlab"
}

variable "gitlab_cpu_cores" {
  description = "Number of CPU cores for GitLab CE"
  type        = number
  default     = 4
}

variable "gitlab_memory_mb" {
  description = "Memory in MB for GitLab CE"
  type        = number
  default     = 8192
}

variable "gitlab_os_disk_size_gb" {
  description = "OS disk size in GB for GitLab CE"
  type        = number
  default     = 80
}

variable "gitlab_data_disk_size_gb" {
  description = "Data disk size in GB for GitLab CE (repositories, artifacts)"
  type        = number
  default     = 200
}

variable "gitlab_ip_address" {
  description = "Static IP address for GitLab CE in CIDR notation"
  type        = string
  default     = "10.0.10.50/24"
}

# ---------------------------------------------------------
# GitLab Runner (LXC)
# ---------------------------------------------------------

variable "gitlab_runner_proxmox_node" {
  description = "Proxmox node for GitLab Runner LXC placement"
  type        = string
  default     = "lab-02"
}

variable "gitlab_runner_vm_id" {
  description = "Proxmox VM ID for GitLab Runner container"
  type        = number
  default     = 3002
}

variable "gitlab_runner_name" {
  description = "Hostname for GitLab Runner container"
  type        = string
  default     = "gitlab-runner"
}

variable "gitlab_runner_cpu_cores" {
  description = "Number of CPU cores for GitLab Runner"
  type        = number
  default     = 4
}

variable "gitlab_runner_memory_mb" {
  description = "Memory in MB for GitLab Runner"
  type        = number
  default     = 4096
}

variable "gitlab_runner_disk_size_gb" {
  description = "Disk size in GB for GitLab Runner"
  type        = number
  default     = 100
}

variable "gitlab_runner_ip_address" {
  description = "Static IP address for GitLab Runner in CIDR notation"
  type        = string
  default     = "10.0.10.51/24"
}

# ---------------------------------------------------------
# Wazuh Manager (VM) — REMOVED
# ---------------------------------------------------------
# Removed to stay within lab-02's 16 GB RAM budget.
# Uncomment to re-enable (requires adding module back in main.tf).
# ---------------------------------------------------------
# variable "wazuh_vm_id" {
#   default = 3003
# }
# variable "wazuh_name" {
#   default = "wazuh"
# }
# variable "wazuh_cpu_cores" {
#   default = 4
# }
# variable "wazuh_memory_mb" {
#   default = 8192
# }
# variable "wazuh_os_disk_size_gb" {
#   default = 80
# }
# variable "wazuh_data_disk_size_gb" {
#   default = 50
# }
# variable "wazuh_ip_address" {
#   default = "10.0.10.52/24"
# }
