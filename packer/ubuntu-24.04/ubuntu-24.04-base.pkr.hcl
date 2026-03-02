# =============================================================================
# Ubuntu Server Noble (24.04 LTS) - Hardened Base Template
# =============================================================================
# Packer template to create a hardened Ubuntu 24.04 VM template on Proxmox.
# Produces tmpl-ubuntu-2404-base (VM ID 9000) with CIS Level 1 baseline
# hardening baked in. Terraform clones this template for all production VMs.
#
# Vault-backed usage (recommended — Vault is running):
#   export VAULT_ADDR="https://10.0.10.10:8200"
#   export VAULT_TOKEN="$(cat ~/.vault-token)"
#   export VAULT_CACERT="$HOME/.lab/tls/ca/ca.pem"
#   ./scripts/packer-build.sh lab-02
#
# Manual usage (bootstrap — no Vault yet):
#   cd packer/ubuntu-24.04
#   packer init .
#   packer build -var-file=../credentials.pkr.hcl .
#
# Hardening boundary:
#   Packer bakes the IMMUTABLE BASELINE (~30% of CIS controls):
#     SSH hardening, UFW, fail2ban, kernel security params, disabled
#     filesystems, secure /tmp + shared memory, password quality,
#     auditd, template cleanup.
#   Ansible enforces RUNTIME STATE (~70% of CIS controls):
#     AIDE, AppArmor, auditd rules, file permissions, USB storage,
#     cron perms, per-host UFW rules, Wazuh enrollment.
#   Both layers are idempotent — running both is safe and correct.
# =============================================================================

packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "proxmox_url" {
  type        = string
  default     = ""
  description = "Proxmox API URL with full path (e.g., https://10.0.10.2:8006/api2/json) — packer-build.sh appends /api2/json to the base URL from Vault automatically"
}

variable "proxmox_token_id" {
  type        = string
  default     = ""
  description = "Proxmox API token ID (e.g., packer@pam!packer-token) — provided by packer-build.sh from Vault"
}

variable "proxmox_token_secret" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Proxmox API token secret — provided by packer-build.sh from Vault"
}

variable "proxmox_node" {
  type        = string
  default     = "lab-02"
  description = "Target Proxmox node name"
}

variable "vm_id" {
  type        = number
  default     = 9000
  description = "VM ID for the template"
}

variable "template_name" {
  type        = string
  default     = "tmpl-ubuntu-2404-base"
  description = "Name for the resulting VM template"
}

variable "iso_file" {
  type        = string
  default     = "local:iso/ubuntu-24.04.2-live-server-amd64.iso"
  description = "Path to the Ubuntu ISO in Proxmox storage"
}

variable "ssh_username" {
  type        = string
  default     = "admin"
  description = "SSH username for Packer provisioning"
}

variable "ssh_password" {
  type        = string
  default     = "packer"
  sensitive   = true
  description = "SSH password for Packer provisioning (replaced by SSH keys post-build)"
}

variable "storage_pool" {
  type        = string
  default     = "local-lvm"
  description = "Proxmox storage pool for VM disk"
}

# -----------------------------------------------------------------------------
# Source: Proxmox ISO Builder
# -----------------------------------------------------------------------------

source "proxmox-iso" "ubuntu" {
  # Proxmox connection
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # VM general settings
  vm_id                = var.vm_id
  vm_name              = var.template_name
  template_description = "Ubuntu 24.04 LTS (Noble) - Hardened Base Template - Built by Packer"
  qemu_agent           = true

  # VM hardware settings
  os       = "l26"
  cpu_type = "x86-64-v2-AES"
  cores    = 2
  memory   = 4096

  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "scsi"
    disk_size    = "40G"
    storage_pool = var.storage_pool
    format       = "raw"
    ssd          = true
    discard      = true
    io_thread    = true
  }

  network_adapters {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = false
  }

  # Boot ISO
  boot_iso {
    iso_file = var.iso_file
    unmount  = true
  }

  # Autoinstall boot command
  boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    "<bs><bs><bs><bs><wait>",
    "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<wait>",
    "<f10><wait>"
  ]

  boot_wait = "10s"

  http_directory = "${path.root}/../http"

  # SSH provisioning connection
  communicator           = "ssh"
  ssh_username           = var.ssh_username
  ssh_password           = var.ssh_password
  ssh_timeout            = "30m"
  ssh_handshake_attempts = 100
  ssh_pty                = true

  # Cloud-init drive for Proxmox template
  cloud_init              = true
  cloud_init_storage_pool = "local"
}

# -----------------------------------------------------------------------------
# Build: Base Image Hardening
# -----------------------------------------------------------------------------
# These provisioners bake the IMMUTABLE BASELINE into the template.
# Ansible handles runtime enforcement and per-host configuration afterward.
# See header comment for the full Packer-vs-Ansible hardening boundary.
# -----------------------------------------------------------------------------

build {
  name    = "ubuntu-2404-base"
  sources = ["source.proxmox-iso.ubuntu"]

  # Wait for cloud-init to finish
  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      "echo 'Cloud-init finished.'"
    ]
  }

  # System updates and essential packages
  provisioner "shell" {
    inline = [
      "echo '=== System Updates ==='",
      "sudo apt-get update",
      "sudo apt-get -y dist-upgrade",
      "sudo apt-get install -y qemu-guest-agent cloud-init curl wget jq",
      "sudo apt-get install -y unattended-upgrades apt-listchanges",
      "sudo systemctl enable qemu-guest-agent",

      # Configure automatic security updates
      "echo 'Unattended-Upgrade::Allowed-Origins:: \"Ubuntu:noble-security\";' | sudo tee -a /etc/apt/apt.conf.d/50unattended-upgrades",
      "echo 'APT::Periodic::Update-Package-Lists \"1\";' | sudo tee -a /etc/apt/apt.conf.d/20auto-upgrades",
      "echo 'APT::Periodic::Unattended-Upgrade \"1\";' | sudo tee -a /etc/apt/apt.conf.d/20auto-upgrades",
    ]
  }

  # SSH hardening
  provisioner "shell" {
    inline = [
      "echo '=== SSH Hardening ==='",
      "sudo apt-get install -y openssh-server",
      "sudo ssh-keygen -A",

      # Server-side hardening
      "sudo sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/^#\\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config",
      "sudo sed -i 's/^#\\?X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/^#\\?AllowAgentForwarding.*/AllowAgentForwarding no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/^#\\?AllowTcpForwarding.*/AllowTcpForwarding no/' /etc/ssh/sshd_config",
      "echo 'Protocol 2' | sudo tee -a /etc/ssh/sshd_config",

      # Client-side hardening
      "sudo mkdir -p /etc/ssh/ssh_config.d",
      "echo 'Host *' | sudo tee /etc/ssh/ssh_config.d/hardened.conf",
      "echo '    KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256' | sudo tee -a /etc/ssh/ssh_config.d/hardened.conf",
      "echo '    HostKeyAlgorithms ssh-ed25519,ssh-rsa' | sudo tee -a /etc/ssh/ssh_config.d/hardened.conf",
      "echo '    Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com' | sudo tee -a /etc/ssh/ssh_config.d/hardened.conf",

      "sudo systemctl enable ssh",
      "sudo sshd -t || (echo 'SSHD configuration error' && exit 1)",
    ]
  }

  # Firewall setup
  provisioner "shell" {
    inline = [
      "echo '=== Firewall Setup ==='",
      "sudo apt-get -y install ufw",
      "sudo ufw default deny incoming",
      "sudo ufw default allow outgoing",
      "sudo ufw allow ssh",
      "echo 'y' | sudo ufw enable",
    ]
  }

  # System hardening
  provisioner "shell" {
    inline = [
      "echo '=== System Hardening ==='",

      # fail2ban
      "sudo apt-get -y install fail2ban",
      "sudo systemctl enable fail2ban",

      # Disable unused filesystems
      "echo 'install cramfs /bin/true' | sudo tee /etc/modprobe.d/disable-filesystems.conf",
      "echo 'install freevxfs /bin/true' | sudo tee -a /etc/modprobe.d/disable-filesystems.conf",
      "echo 'install jffs2 /bin/true' | sudo tee -a /etc/modprobe.d/disable-filesystems.conf",
      "echo 'install hfs /bin/true' | sudo tee -a /etc/modprobe.d/disable-filesystems.conf",
      "echo 'install hfsplus /bin/true' | sudo tee -a /etc/modprobe.d/disable-filesystems.conf",
      "echo 'install squashfs /bin/true' | sudo tee -a /etc/modprobe.d/disable-filesystems.conf",
      "echo 'install udf /bin/true' | sudo tee -a /etc/modprobe.d/disable-filesystems.conf",

      # Kernel security parameters
      "echo 'kernel.randomize_va_space = 2' | sudo tee /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.all.rp_filter = 1' | sudo tee -a /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.default.rp_filter = 1' | sudo tee -a /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.tcp_syncookies = 1' | sudo tee -a /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.icmp_echo_ignore_broadcasts = 1' | sudo tee -a /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.all.accept_redirects = 0' | sudo tee -a /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.default.accept_redirects = 0' | sudo tee -a /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.all.secure_redirects = 0' | sudo tee -a /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.default.secure_redirects = 0' | sudo tee -a /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.all.send_redirects = 0' | sudo tee -a /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.default.send_redirects = 0' | sudo tee -a /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv6.conf.all.accept_redirects = 0' | sudo tee -a /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv6.conf.default.accept_redirects = 0' | sudo tee -a /etc/sysctl.d/99-security.conf",
      "sudo sysctl --system",

      # Secure shared memory
      "echo 'tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0' | sudo tee -a /etc/fstab",

      # Secure /tmp
      "echo 'tmpfs /tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime 0 0' | sudo tee -a /etc/fstab",

      # Password quality
      "sudo apt-get -y install libpam-pwquality",
      "sudo sed -i 's/^# minlen.*/minlen = 12/' /etc/security/pwquality.conf",
      "sudo sed -i 's/^# dcredit.*/dcredit = -1/' /etc/security/pwquality.conf",
      "sudo sed -i 's/^# ucredit.*/ucredit = -1/' /etc/security/pwquality.conf",
      "sudo sed -i 's/^# ocredit.*/ocredit = -1/' /etc/security/pwquality.conf",
      "sudo sed -i 's/^# lcredit.*/lcredit = -1/' /etc/security/pwquality.conf",

      # Secure umask
      "echo 'umask 027' | sudo tee -a /etc/bash.bashrc",
      "echo 'umask 027' | sudo tee -a /etc/profile",

      # Remove unnecessary packages
      "sudo apt-get -y remove telnet rsh-client rsh-redone-client 2>/dev/null || true",
    ]
  }

  # Audit logging
  provisioner "shell" {
    inline = [
      "echo '=== Audit Logging ==='",
      "sudo apt-get -y install auditd audispd-plugins",
      "sudo systemctl enable auditd",
      "sudo sed -i 's/^#max_log_file.*/max_log_file = 50/' /etc/audit/auditd.conf",
      "sudo sed -i 's/^#space_left_action.*/space_left_action = email/' /etc/audit/auditd.conf",
      "sudo sed -i 's/^#action_mail_acct.*/action_mail_acct = root/' /etc/audit/auditd.conf",
    ]
  }

  # Cloud-init cleanup for template reuse
  provisioner "shell" {
    inline = [
      "echo '=== Template Cleanup ==='",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
      "sudo rm -f /etc/netplan/00-installer-config.yaml",
      "sudo apt-get -y autoremove --purge",
      "sudo apt-get -y clean",
      "sudo apt-get -y autoclean",
      "sudo cloud-init clean --logs",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo sync",
    ]
  }
}
