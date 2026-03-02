# =============================================================================
# Layer 02-vault-infra: Vault VM Infrastructure - Variables
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
  description = "Proxmox node name — used for Vault secret lookup and VM deployment target"
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
# Vault VM Settings (vault-2 on Proxmox)
# ---------------------------------------------------------

variable "vault_vm_id" {
  description = "Proxmox VM ID for vault-2"
  type        = number
  default     = 5002
}

variable "vault_vm_name" {
  description = "VM hostname for vault-2"
  type        = string
  default     = "vault-2"
}

variable "vault_vm_description" {
  description = "Description for the Vault VM"
  type        = string
  default     = "Vault HA cluster node 2 - Raft integrated storage"
}

variable "vault_cpu_cores" {
  description = "Number of CPU cores for vault-2"
  type        = number
  default     = 2
}

variable "vault_memory_mb" {
  description = "Memory in MB for vault-2"
  type        = number
  default     = 2048
}

variable "vault_os_disk_size_gb" {
  description = "OS disk size in GB for vault-2"
  type        = number
  default     = 40
}

variable "vault_data_disk_size_gb" {
  description = "Raft data disk size in GB for vault-2"
  type        = number
  default     = 20
}

variable "vault_storage_pool" {
  description = "Proxmox storage pool for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "vault_snippet_storage" {
  description = "Proxmox storage for cloud-init snippets and images"
  type        = string
  default     = "local"
}

variable "vault_vm_username" {
  description = "Default username for the Vault VM"
  type        = string
  default     = "admin"
}

# ---------------------------------------------------------
# Packer Template
# ---------------------------------------------------------

variable "vault_template_vm_id" {
  description = "VM ID of the hardened Packer template to clone (Rocky 9 = 9001, Ubuntu 24.04 = 9000)"
  type        = number
  default     = 9001
}

variable "vault_template_node" {
  description = "Proxmox node where the Packer template lives (empty = same as proxmox_node). Enables cross-node cloning."
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# Network Settings
# ---------------------------------------------------------

variable "vault_network_bridge" {
  description = "Network bridge for vault-2"
  type        = string
  default     = "vmbr0"
}

variable "vault_vlan_tag" {
  description = "VLAN tag for vault-2 (Security VLAN)"
  type        = number
  default     = 50
}

variable "vault_ip_address" {
  description = "Static IP address for vault-2 in CIDR notation"
  type        = string
  default     = "10.0.50.2/24"
}

variable "vault_gateway" {
  description = "Network gateway for the Security VLAN"
  type        = string
  default     = "10.0.50.1"
}

variable "vault_domain_name" {
  description = "DNS domain name for Vault nodes"
  type        = string
  default     = "example-lab.local"
}

variable "vault_dns_servers" {
  description = "DNS server addresses for the Vault VM"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

# ---------------------------------------------------------
# SSH
# ---------------------------------------------------------

variable "ssh_public_key" {
  description = "Additional SSH public key to authorize on vault-2 (e.g., your personal key)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------
# Vault Configuration
# ---------------------------------------------------------

variable "vault_version" {
  description = "HashiCorp Vault version to deploy (used by Ansible, stored here for reference)"
  type        = string
  default     = "1.17.6"
}

# ---------------------------------------------------------
# Raft Peer Addresses (all 3 cluster nodes)
# ---------------------------------------------------------

variable "vault_node_1_address" {
  description = "IP address of vault-1 (Mac Mini M4, native macOS)"
  type        = string
  default     = "10.0.10.10"
}

variable "vault_node_2_address" {
  description = "IP address of vault-2 (Proxmox VM)"
  type        = string
  default     = "10.0.50.2"
}

variable "vault_node_3_address" {
  description = "IP address of vault-3 (RPi5 CM5)"
  type        = string
  default     = "10.0.10.13"
}

variable "vault_api_port" {
  description = "Vault API listener port"
  type        = number
  default     = 8200
}

variable "vault_cluster_port" {
  description = "Vault cluster (Raft) communication port"
  type        = number
  default     = 8201
}
