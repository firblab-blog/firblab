# =============================================================================
# Layer 08-netbox-config: NetBox VM Record Management
# =============================================================================
# Manages NetBox virtual machine records, interfaces, and IP addresses for
# all Terraform-provisioned VMs/LXCs. Makes Terraform the authoritative owner
# of VM lifecycle in NetBox — creating/destroying a VM in Terraform auto-
# matically creates/destroys the corresponding NetBox record.
#
# Physical infrastructure (devices, cables, VLANs, prefixes) remains managed
# by the seed script (scripts/netbox-seed.py).
#
# Resources created per VM:
#   1. netbox_virtual_machine  — VM record with vCPUs, RAM, disk
#   2. netbox_interface        — eth0 interface
#   3. netbox_ip_address       — Primary IP with CIDR
#   4. netbox_primary_ip       — Primary IP assignment
# =============================================================================

# =============================================================================
# Section 1: Foundation — Site, Cluster Types, Clusters, Tags
# =============================================================================

resource "netbox_tag" "terraform_managed" {
  name      = "terraform-managed"
  slug      = "terraform-managed"
  color_hex = "00bcd4"
}

resource "netbox_site" "firblab" {
  name   = "FirbLab"
  slug   = "firblab"
  status = "active"
}

# ---------------------------------------------------------------------------
# Cluster Types
# ---------------------------------------------------------------------------

resource "netbox_cluster_type" "proxmox" {
  name = "Proxmox VE"
  slug = "proxmox-ve"
}

resource "netbox_cluster_type" "hetzner" {
  name = "Hetzner Cloud"
  slug = "hetzner-cloud"
}

# ---------------------------------------------------------------------------
# Clusters
# ---------------------------------------------------------------------------

resource "netbox_cluster" "firblab" {
  name            = "firblab-cluster"
  cluster_type_id = netbox_cluster_type.proxmox.id
  site_id         = netbox_site.firblab.id
}

resource "netbox_cluster" "hetzner" {
  name            = "hetzner-cloud"
  cluster_type_id = netbox_cluster_type.hetzner.id
}

# =============================================================================
# Section 2: VM Definitions — Single Source of Truth
# =============================================================================
# All VM specs derived from Terraform layer variables (03-06). Disk sizes are
# OS disk only (in MB) — data disks and passthrough disks are not tracked here.
#
# Proxmox node assignments match the actual layer configurations:
#   lab-01: RKE2 cluster (6 VMs), AI GPU
#   lab-02: GitLab, GitLab Runner
#   lab-03: Ghost, FoundryVTT, Roundcube, Mealie, WireGuard,
#               Actual Budget, Vaultwarden
#   lab-04: NetBox, PBS, Authentik, PatchMon, Traefik Proxy
# =============================================================================

locals {
  # -------------------------------------------------------------------------
  # Proxmox VMs/LXCs (Layers 03-06, firblab-cluster)
  # -------------------------------------------------------------------------
  proxmox_vms = {
    # --- Layer 03: Core Infrastructure (lab-02, Management VLAN 10) ---
    gitlab = {
      vcpus        = 4
      memory_mb    = 8192
      disk_size_mb = 80000 # 80 GB
      ip_address   = "10.0.10.50/24"
      node         = "lab-02"
    }
    gitlab-runner = {
      vcpus        = 2
      memory_mb    = 4096
      disk_size_mb = 100000 # 100 GB
      ip_address   = "10.0.10.51/24"
      node         = "lab-02"
    }

    # --- Layer 04: RKE2 Cluster (lab-01, Services VLAN 20) ---
    rke2-server-1 = {
      vcpus        = 4
      memory_mb    = 6144
      disk_size_mb = 40000 # 40 GB
      ip_address   = "10.0.20.40/24"
      node         = "lab-01"
    }
    rke2-server-2 = {
      vcpus        = 4
      memory_mb    = 6144
      disk_size_mb = 40000 # 40 GB
      ip_address   = "10.0.20.41/24"
      node         = "lab-01"
    }
    rke2-server-3 = {
      vcpus        = 4
      memory_mb    = 6144
      disk_size_mb = 40000 # 40 GB
      ip_address   = "10.0.20.42/24"
      node         = "lab-01"
    }
    rke2-agent-1 = {
      vcpus        = 4
      memory_mb    = 10240
      disk_size_mb = 40000 # 40 GB
      ip_address   = "10.0.20.50/24"
      node         = "lab-01"
    }
    rke2-agent-2 = {
      vcpus        = 4
      memory_mb    = 10240
      disk_size_mb = 40000 # 40 GB
      ip_address   = "10.0.20.51/24"
      node         = "lab-01"
    }
    rke2-agent-3 = {
      vcpus        = 4
      memory_mb    = 10240
      disk_size_mb = 40000 # 40 GB
      ip_address   = "10.0.20.52/24"
      node         = "lab-01"
    }

    # --- Layer 05: Standalone Services (lab-03, Services VLAN 20) ---
    ghost = {
      vcpus        = 1
      memory_mb    = 1024
      disk_size_mb = 20000 # 20 GB
      ip_address   = "10.0.20.10/24"
      node         = "lab-03"
    }
    foundryvtt = {
      vcpus        = 2
      memory_mb    = 4096
      disk_size_mb = 40000 # 40 GB
      ip_address   = "10.0.20.12/24"
      node         = "lab-03"
    }
    roundcube = {
      vcpus        = 1
      memory_mb    = 1024
      disk_size_mb = 10000 # 10 GB
      ip_address   = "10.0.20.11/24"
      node         = "lab-03"
    }
    mealie = {
      vcpus        = 1
      memory_mb    = 1024
      disk_size_mb = 10000 # 10 GB
      ip_address   = "10.0.20.13/24"
      node         = "lab-03"
    }
    actualbudget = {
      vcpus        = 1
      memory_mb    = 512
      disk_size_mb = 10000 # 10 GB
      ip_address   = "10.0.20.16/24"
      node         = "lab-03"
    }
    vaultwarden = {
      vcpus        = 1
      memory_mb    = 512
      disk_size_mb = 4000 # 4 GB
      ip_address   = "10.0.20.19/24"
      node         = "lab-03"
    }

    # --- Layer 05: Standalone Services (lab-03, DMZ VLAN 30) ---
    wireguard = {
      vcpus        = 1
      memory_mb    = 256
      disk_size_mb = 4000 # 4 GB
      ip_address   = "10.0.30.2/24"
      node         = "lab-03"
    }

    # --- Layer 05: Standalone Services (lab-04, Services VLAN 20) ---
    netbox = {
      vcpus        = 2
      memory_mb    = 4096
      disk_size_mb = 40000 # 40 GB
      ip_address   = "10.0.20.14/24"
      node         = "lab-04"
    }
    patchmon = {
      vcpus        = 2
      memory_mb    = 2048
      disk_size_mb = 40000 # 40 GB
      ip_address   = "10.0.20.15/24"
      node         = "lab-04"
    }

    # --- Layer 05: Standalone Services (lab-04, Management VLAN 10) ---
    pbs = {
      vcpus        = 2
      memory_mb    = 4096
      disk_size_mb = 32000 # 32 GB
      ip_address   = "10.0.10.15/24"
      node         = "lab-04"
    }
    authentik = {
      vcpus        = 2
      memory_mb    = 2048
      disk_size_mb = 40000 # 40 GB
      ip_address   = "10.0.10.16/24"
      node         = "lab-04"
    }
    traefik-proxy = {
      vcpus        = 1
      memory_mb    = 512
      disk_size_mb = 10000 # 10 GB
      ip_address   = "10.0.10.17/24"
      node         = "lab-04"
    }

    # --- Layer 05: Standalone Services (lab-01, Services VLAN 20) ---
    ai-gpu = {
      vcpus        = 8
      memory_mb    = 16384
      disk_size_mb = 50000 # 50 GB
      ip_address   = "10.0.20.18/24"
      node         = "lab-01"
    }
  }

  # -------------------------------------------------------------------------
  # Hetzner Cloud VMs (Layer 06, hetzner-cloud cluster)
  # -------------------------------------------------------------------------
  # The gateway server gets a dynamic public IP from Hetzner. Since we can't
  # hardcode it, the IP address must be set via variable after Layer 06 apply.
  # Specs from Layer 06 variables: cpx22 = 3 vCPUs, 4GB RAM, 80GB disk.
  # -------------------------------------------------------------------------
  hetzner_vms = {
    lab-gateway = {
      vcpus        = 3
      memory_mb    = 4096
      disk_size_mb = 80000 # 80 GB (cpx22 default)
    }
  }
}

# =============================================================================
# Section 3: Proxmox VM Resources (for_each)
# =============================================================================

# ---------------------------------------------------------------------------
# Virtual Machine Records
# ---------------------------------------------------------------------------

resource "netbox_virtual_machine" "proxmox" {
  for_each = local.proxmox_vms

  name         = each.key
  cluster_id   = netbox_cluster.firblab.id
  site_id      = netbox_site.firblab.id
  vcpus        = each.value.vcpus
  memory_mb    = each.value.memory_mb
  disk_size_mb = each.value.disk_size_mb
  comments     = "Managed by Terraform Layer 08. Proxmox node: ${each.value.node}"
  tags         = [netbox_tag.terraform_managed.name]
}

# ---------------------------------------------------------------------------
# Network Interfaces (eth0 on each VM)
# ---------------------------------------------------------------------------

resource "netbox_interface" "proxmox_eth0" {
  for_each = local.proxmox_vms

  name               = "eth0"
  virtual_machine_id = netbox_virtual_machine.proxmox[each.key].id
}

# ---------------------------------------------------------------------------
# IP Addresses
# ---------------------------------------------------------------------------

resource "netbox_ip_address" "proxmox_primary" {
  for_each = local.proxmox_vms

  ip_address                   = each.value.ip_address
  status                       = "active"
  virtual_machine_interface_id = netbox_interface.proxmox_eth0[each.key].id
  tags                         = [netbox_tag.terraform_managed.name]
}

# ---------------------------------------------------------------------------
# Primary IP Assignments
# ---------------------------------------------------------------------------

resource "netbox_primary_ip" "proxmox" {
  for_each = local.proxmox_vms

  ip_address_id      = netbox_ip_address.proxmox_primary[each.key].id
  virtual_machine_id = netbox_virtual_machine.proxmox[each.key].id
  ip_address_version = 4
}

# =============================================================================
# Section 4: Hetzner VM Resources
# =============================================================================

resource "netbox_virtual_machine" "hetzner" {
  for_each = local.hetzner_vms

  name         = each.key
  cluster_id   = netbox_cluster.hetzner.id
  vcpus        = each.value.vcpus
  memory_mb    = each.value.memory_mb
  disk_size_mb = each.value.disk_size_mb
  comments     = "Managed by Terraform Layer 08. Hetzner Cloud cpx22 (Nuremberg)."
  tags         = [netbox_tag.terraform_managed.name]
}

resource "netbox_interface" "hetzner_eth0" {
  for_each = local.hetzner_vms

  name               = "eth0"
  virtual_machine_id = netbox_virtual_machine.hetzner[each.key].id
}

# Hetzner IP address — requires the public IP from Layer 06 output.
# Set via: terraform apply -var hetzner_gateway_ip="x.x.x.x/32"
# Skip creation if no IP is provided (first-time bootstrap).
resource "netbox_ip_address" "hetzner_primary" {
  for_each = var.hetzner_gateway_ip != "" ? local.hetzner_vms : {}

  ip_address                   = "${var.hetzner_gateway_ip}/32"
  status                       = "active"
  virtual_machine_interface_id = netbox_interface.hetzner_eth0[each.key].id
  tags                         = [netbox_tag.terraform_managed.name]
}

resource "netbox_primary_ip" "hetzner" {
  for_each = var.hetzner_gateway_ip != "" ? local.hetzner_vms : {}

  ip_address_id      = netbox_ip_address.hetzner_primary[each.key].id
  virtual_machine_id = netbox_virtual_machine.hetzner[each.key].id
  ip_address_version = 4
}
