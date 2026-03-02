# ---------------------------------------------------------
# Required Variables
# ---------------------------------------------------------

variable "name" {
  description = "Server hostname and resource name prefix"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for server access (not needed if ssh_key_id is provided)"
  type        = string
  default     = ""
}

variable "ssh_key_id" {
  description = "Existing hcloud_ssh_key ID to reuse (skips creating a new key). Use when multiple servers share the same key."
  type        = number
  default     = null
}

# ---------------------------------------------------------
# Server Configuration
# ---------------------------------------------------------

variable "server_type" {
  description = "Hetzner server type (cpx11, cpx21, cpx31, cpx41, etc.)"
  type        = string
  default     = "cpx21"
}

variable "location" {
  description = "Hetzner datacenter location (fsn1, nbg1, hel1, ash)"
  type        = string
  default     = "fsn1"
}

variable "image" {
  description = "Server OS image"
  type        = string
  default     = "ubuntu-24.04"
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

# ---------------------------------------------------------
# Firewall
# ---------------------------------------------------------

variable "firewall_rules" {
  description = "List of firewall rules to apply to the server"
  type = list(object({
    direction  = string
    protocol   = string
    port       = string
    source_ips = list(string)
  }))
  default = []
}

# ---------------------------------------------------------
# Metadata
# ---------------------------------------------------------

variable "labels" {
  description = "Labels to apply to all Hetzner resources"
  type        = map(string)
  default     = {}
}
