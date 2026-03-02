# =============================================================================
# Rocky Linux 9 - Hardened Base Template
# =============================================================================
# Packer template to create a hardened Rocky Linux 9 VM template on Proxmox.
# Produces tmpl-rocky-9-base (VM ID 9001) with CIS Level 1 baseline
# hardening baked in. Terraform clones this template for production VMs
# that require the RedHat ecosystem (SELinux, firewalld, dnf).
#
# Vault-backed usage (recommended — Vault is running):
#   export VAULT_ADDR="https://10.0.10.10:8200"
#   export VAULT_TOKEN="$(cat ~/.vault-token)"
#   export VAULT_CACERT="$HOME/.lab/tls/ca/ca.pem"
#   ./scripts/packer-build.sh lab-02 rocky-9
#
# Manual usage (bootstrap — no Vault yet):
#   cd packer/rocky-9
#   packer init .
#   packer build -var-file=../credentials.pkr.hcl .
#
# Hardening boundary:
#   Packer bakes the IMMUTABLE BASELINE (~30% of CIS controls):
#     SSH hardening, firewalld, fail2ban, kernel security params, disabled
#     filesystems, secure /tmp + shared memory, password quality,
#     auditd, SELinux enforcing, template cleanup.
#   Ansible enforces RUNTIME STATE (~70% of CIS controls):
#     AIDE, auditd rules, file permissions, USB storage, cron perms,
#     per-host firewalld rules, Wazuh enrollment.
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
  default     = 9001
  description = "VM ID for the template"
}

variable "template_name" {
  type        = string
  default     = "tmpl-rocky-9-base"
  description = "Name for the resulting VM template"
}

variable "iso_file" {
  type        = string
  default     = "local:iso/Rocky-9-latest-x86_64-minimal.iso"
  description = "Path to the Rocky Linux 9 ISO in Proxmox storage"
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

source "proxmox-iso" "rocky" {
  # Proxmox connection
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # VM general settings
  vm_id                = var.vm_id
  vm_name              = var.template_name
  template_description = "Rocky Linux 9 - Hardened Base Template - Built by Packer"
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

  # Kickstart boot command
  # Rocky 9 Minimal ISO boots with ISOLINUX (BIOS/SeaBIOS), NOT GRUB2.
  # The boot menu shows: "Press Tab for full configuration options"
  #
  # ISOLINUX key sequence:
  #   <up>    — Ensure "Install Rocky Linux 9" is highlighted (it's the default,
  #             but <up> guarantees we're on the first entry)
  #   <tab>   — Opens the ISOLINUX parameter edit line, showing:
  #             "vmlinuz initrd=initrd.img inst.stage2=... quiet"
  #   Append: " inst.text inst.ks=http://..." to point Anaconda at our kickstart
  #   <enter> — Boot with the modified kernel parameters
  #
  # Note: inst.text forces text-mode install (safer for headless Packer builds).
  # If the kickstart is fully unattended, inst.cmdline can be used instead.
  boot_command = [
    "<wait3><wait3><wait3>",
    "<up><tab>",
    " inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/rocky9-ks.cfg",
    "<enter>"
  ]

  boot_wait = "15s"

  http_directory = "${path.root}/../http"

  # SSH provisioning connection
  communicator           = "ssh"
  ssh_username           = var.ssh_username
  ssh_password           = var.ssh_password
  ssh_timeout            = "45m"
  ssh_handshake_attempts = 200
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
  name    = "rocky-9-base"
  sources = ["source.proxmox-iso.rocky"]

  # Wait for system to be ready
  provisioner "shell" {
    inline = [
      "while ! sudo test -f /var/lib/cloud/instance/boot-finished && ! sudo test -f /root/ks-post.log; do echo 'Waiting for post-install...'; sleep 2; done",
      "sleep 5",
      "echo 'System ready for provisioning.'"
    ]
  }

  # System updates and essential packages
  provisioner "shell" {
    inline = [
      "echo '=== System Updates ==='",
      "sudo dnf -y update",
      "sudo dnf -y install qemu-guest-agent cloud-init curl wget jq",
      "sudo dnf -y install dnf-automatic",
      "sudo systemctl enable qemu-guest-agent",

      # Configure automatic security updates
      "sudo sed -i 's/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf",
      "sudo sed -i 's/^upgrade_type.*/upgrade_type = security/' /etc/dnf/automatic.conf",
      "sudo systemctl enable dnf-automatic.timer",
    ]
  }

  # SSH hardening
  provisioner "shell" {
    inline = [
      "echo '=== SSH Hardening ==='",
      "sudo dnf -y install openssh-server",
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

      "sudo systemctl enable sshd",
      "sudo sshd -t || (echo 'SSHD configuration error' && exit 1)",
    ]
  }

  # Firewall setup (firewalld — RedHat ecosystem)
  provisioner "shell" {
    inline = [
      "echo '=== Firewall Setup (firewalld) ==='",
      "sudo dnf -y install firewalld",
      "sudo systemctl enable firewalld",
      "sudo systemctl start firewalld",
      "sudo firewall-cmd --set-default-zone=drop",
      "sudo firewall-cmd --permanent --zone=drop --add-service=ssh",
      "sudo firewall-cmd --reload",
    ]
  }

  # System hardening
  provisioner "shell" {
    inline = [
      "echo '=== System Hardening ==='",

      # fail2ban
      "sudo dnf -y install epel-release",
      "sudo dnf -y install fail2ban",
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
      "sudo dnf -y install libpwquality",
      "sudo sed -i 's/^# minlen.*/minlen = 12/' /etc/security/pwquality.conf",
      "sudo sed -i 's/^# dcredit.*/dcredit = -1/' /etc/security/pwquality.conf",
      "sudo sed -i 's/^# ucredit.*/ucredit = -1/' /etc/security/pwquality.conf",
      "sudo sed -i 's/^# ocredit.*/ocredit = -1/' /etc/security/pwquality.conf",
      "sudo sed -i 's/^# lcredit.*/lcredit = -1/' /etc/security/pwquality.conf",

      # Secure umask
      "echo 'umask 027' | sudo tee -a /etc/bashrc",
      "echo 'umask 027' | sudo tee -a /etc/profile",

      # Ensure SELinux is enforcing (CIS requirement for RedHat)
      "sudo sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config",
      "sudo sed -i 's/^SELINUXTYPE=.*/SELINUXTYPE=targeted/' /etc/selinux/config",

      # Remove unnecessary packages
      "sudo dnf -y remove telnet rsh 2>/dev/null || true",
    ]
  }

  # Audit logging
  provisioner "shell" {
    inline = [
      "echo '=== Audit Logging ==='",
      "sudo dnf -y install audit",
      "sudo systemctl enable auditd",
      "sudo sed -i 's/^#max_log_file.*/max_log_file = 50/' /etc/audit/auditd.conf",
      "sudo sed -i 's/^max_log_file.*/max_log_file = 50/' /etc/audit/auditd.conf",
      "sudo sed -i 's/^#space_left_action.*/space_left_action = email/' /etc/audit/auditd.conf",
      "sudo sed -i 's/^space_left_action.*/space_left_action = email/' /etc/audit/auditd.conf",
      "sudo sed -i 's/^#action_mail_acct.*/action_mail_acct = root/' /etc/audit/auditd.conf",
      "sudo sed -i 's/^action_mail_acct.*/action_mail_acct = root/' /etc/audit/auditd.conf",
    ]
  }

  # Cloud-init cleanup for template reuse
  provisioner "shell" {
    inline = [
      "echo '=== Template Cleanup ==='",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo rm -f /etc/udev/rules.d/70-persistent-*",
      "sudo dnf -y autoremove",
      "sudo dnf clean all",
      "sudo cloud-init clean --logs",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo rm -f /root/ks-post.log",
      "sudo rm -f /root/anaconda-ks.cfg",
      "sudo rm -f /root/original-ks.cfg",
      "sudo sync",
    ]
  }
}
