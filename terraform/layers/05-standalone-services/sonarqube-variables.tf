# =============================================================================
# SonarQube CE — Variable Definitions
# =============================================================================

variable "sonarqube_vm_id" {
  description = "Proxmox VM ID for SonarQube"
  type        = number
  default     = 5045
}

variable "sonarqube_name" {
  description = "Hostname for SonarQube VM"
  type        = string
  default     = "sonarqube"
}

variable "sonarqube_proxmox_node" {
  description = "Proxmox node for SonarQube VM placement (lab-01 — 64GB RAM for JVM + Elasticsearch)"
  type        = string
  default     = "lab-01"
}

variable "sonarqube_cpu_cores" {
  description = "Number of CPU cores for SonarQube"
  type        = number
  default     = 4
}

variable "sonarqube_memory_mb" {
  description = "Memory in MB for SonarQube (6GB for web JVM + CE JVM + Elasticsearch)"
  type        = number
  default     = 6144
}

variable "sonarqube_os_disk_size_gb" {
  description = "OS disk size in GB for SonarQube"
  type        = number
  default     = 40
}

variable "sonarqube_ip_address" {
  description = "Static IP address for SonarQube in CIDR notation (Services VLAN 20)"
  type        = string
  default     = "10.0.20.18/24"
}
