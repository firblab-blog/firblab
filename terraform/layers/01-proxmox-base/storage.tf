# =============================================================================
# Layer 01: Proxmox Base — NFS Storage Registration
# =============================================================================
# Registers TrueNAS NFS exports as Proxmox storage backends.
#
# truenas-10g: Backup storage over the dedicated 10G point-to-point DAC link
# between lab-01 and TrueNAS (10.10.10.0/30). Restricted to lab-01
# only — other nodes cannot reach this subnet.
#
# Prerequisites:
#   - TrueNAS NFS service enabled (Ansible: truenas-deploy.yml)
#   - NFS export ACL allows 10.10.10.0/30 (Ansible: truenas role defaults)
#   - lab-01 vmbr1 storage bridge active (10.10.10.1/30)
#   - TrueNAS Mellanox interface active (10.10.10.2/30)
# =============================================================================

resource "proxmox_virtual_environment_storage_nfs" "truenas_10g" {
  id      = "truenas-10g"
  server  = "10.10.10.2"
  export  = "/mnt/backups/firb-lab-01"
  nodes   = ["lab-01"]
  content = ["backup", "iso", "vztmpl", "snippets"]
  options = "vers=4.2"
}
