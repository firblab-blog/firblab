# =============================================================================
# Proxmox Backup Server — Base Template
# =============================================================================
# Packer template to create a PBS VM template on Proxmox.
# Produces tmpl-pbs-base (VM ID 9002) for cloning by Terraform.
#
# PBS version and Debian codename are controlled by variables (pbs_version,
# pbs_debian_codename). Update those defaults when upgrading PBS releases.
#
# PBS uses its own Debian-based installer (not Ubuntu autoinstall). The
# automated installation requires a pre-prepared ISO with the answer file
# baked in using proxmox-auto-install-assistant.
#
# Prerequisites:
#   1. Download PBS ISO (version controlled by pbs_version variable):
#        wget https://enterprise.proxmox.com/iso/proxmox-backup-server_<pbs_version>.iso
#        (current default: 4.1-1)
#
#   2. Install proxmox-auto-install-assistant (on any Debian/Ubuntu host):
#        apt install proxmox-auto-install-assistant xorriso
#
#   3. Prepare the ISO with the answer file:
#        proxmox-auto-install-assistant prepare-iso \
#          proxmox-backup-server_<pbs_version>.iso \
#          --fetch-from iso \
#          --answer-file ../http/pbs-answer.toml
#
#      This creates: proxmox-backup-server_<pbs_version>-auto.iso
#
#   4. Upload the prepared ISO to Proxmox:
#        scp proxmox-backup-server_<pbs_version>-auto.iso \
#          admin@10.0.10.42:/var/lib/vz/template/iso/
#
# Vault-backed usage (recommended):
#   export VAULT_ADDR="https://10.0.10.10:8200"
#   export VAULT_TOKEN="$(cat ~/.vault-token)"
#   export VAULT_CACERT="$HOME/.lab/tls/ca/ca.pem"
#   ./scripts/packer-build.sh lab-01 pbs
#
# Manual usage:
#   cd packer/pbs
#   packer init .
#   packer build -var-file=../credentials.pkr.hcl .
#
# NOTE: PBS does NOT use cloud-init. IP/hostname are baked into the
# answer file with the production IP (10.0.10.15). Terraform's
# cloud-init initialization block is ignored — the IP from the answer
# file IS the final IP. SSH key injection is handled by Ansible.
#
# PBS doesn't ship with qemu-guest-agent, so Packer can't auto-discover
# the VM IP. ssh_host matches the answer file IP — fully deterministic.
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

variable "pbs_version" {
  type        = string
  default     = "4.1-1"
  description = "PBS version string (e.g., 4.1-1) — used in ISO filename and template description"
}

variable "pbs_debian_codename" {
  type        = string
  default     = "trixie"
  description = "Debian codename for PBS repositories (trixie for PBS 4.x, bookworm for 3.x)"
}

variable "proxmox_url" {
  type        = string
  default     = ""
  description = "Proxmox API URL with full path — packer-build.sh appends /api2/json automatically"
}

variable "proxmox_token_id" {
  type        = string
  default     = ""
  description = "Proxmox API token ID — provided by packer-build.sh from Vault"
}

variable "proxmox_token_secret" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Proxmox API token secret — provided by packer-build.sh from Vault"
}

variable "proxmox_node" {
  type        = string
  default     = "lab-01"
  description = "Target Proxmox node name (build on lab-01, clone cross-node)"
}

variable "vm_id" {
  type        = number
  default     = 9002
  description = "VM ID for the template (9000=Ubuntu, 9001=Rocky, 9002=PBS)"
}

variable "template_name" {
  type        = string
  default     = "tmpl-pbs-base"
  description = "Name for the resulting VM template"
}

variable "iso_file" {
  type        = string
  default     = ""
  description = "Path to the PREPARED PBS ISO in Proxmox storage. Leave empty to auto-compute from pbs_version."
}

variable "ssh_password" {
  type        = string
  default     = "packer-temp"
  sensitive   = true
  description = "Root password set in the PBS answer file (used for Packer SSH provisioning). PBS 4.x requires min 8 chars."
}

variable "ssh_host" {
  type        = string
  default     = "10.0.10.15"
  description = "Production IP for PBS — must match the answer file [network] cidr. PBS has no guest agent pre-installed."
}

variable "storage_pool" {
  type        = string
  default     = "local-lvm"
  description = "Proxmox storage pool for VM disk"
}

# Computed locals — derive ISO path from version if not explicitly set
locals {
  iso_file = var.iso_file != "" ? var.iso_file : "local:iso/proxmox-backup-server_${var.pbs_version}-auto.iso"
}

# -----------------------------------------------------------------------------
# Source: Proxmox ISO Builder
# -----------------------------------------------------------------------------
# PBS installer is Debian-based. The pre-prepared ISO boots directly into
# automated installation mode (10-second timeout, then auto-selects
# "Automated Installation" boot entry).
# -----------------------------------------------------------------------------

source "proxmox-iso" "pbs" {
  # Proxmox connection
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # VM general settings
  vm_id                = var.vm_id
  vm_name              = var.template_name
  template_description = "Proxmox Backup Server ${var.pbs_version} - Base Template - Built by Packer"

  # qemu_agent = true sets the agent:1 flag on the VM config (needed by
  # Terraform after cloning), BUT Packer also uses it for IP discovery via
  # the guest agent API. Since PBS doesn't ship with qemu-guest-agent
  # (we install it in provisioners), we must provide ssh_host explicitly
  # so Packer doesn't hang waiting for the agent.
  qemu_agent = true

  # VM hardware settings
  os       = "l26"
  cpu_type = "x86-64-v2-AES"
  cores    = 2
  memory   = 4096

  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "scsi"
    disk_size    = "32G"
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

  # Boot ISO — pre-prepared with answer file baked in
  boot_iso {
    iso_file = local.iso_file
    unmount  = true
  }

  # PBS automated installer auto-selects "Automated Installation" after 10s.
  # No boot command needed — the prepared ISO handles everything.
  # We just wait for the installer to complete.
  boot_command = []
  boot_wait    = "15s"

  # SSH provisioning connection — PBS installs as root
  # ssh_host must match the production IP in pbs-answer.toml (PBS has no guest agent).
  communicator           = "ssh"
  ssh_host               = var.ssh_host
  ssh_username           = "root"
  ssh_password           = var.ssh_password
  ssh_timeout            = "30m"
  ssh_handshake_attempts = 100
  ssh_pty                = true

  # No cloud-init — PBS manages its own configuration
  cloud_init = false
}

# -----------------------------------------------------------------------------
# Build: Post-Installation Hardening
# -----------------------------------------------------------------------------
# PBS is Debian-based. Apply baseline hardening similar to Ubuntu template
# but without cloud-init (PBS doesn't use it).
#
# PBS comes with its own services (proxmox-backup, proxmox-backup-proxy).
# We harden the OS layer without touching PBS-specific config (that's
# Ansible's job).
# -----------------------------------------------------------------------------

build {
  name    = "pbs-base"
  sources = ["source.proxmox-iso.pbs"]

  # Wait for PBS installer to finish and system to be fully booted
  provisioner "shell" {
    inline = [
      "echo 'Waiting for PBS installation to complete...'",
      "sleep 10",
      "echo 'PBS installation complete. System is ready for provisioning.'"
    ]
  }

  # Disable PBS enterprise repository (requires subscription)
  # Enable the no-subscription repository for updates
  # PBS 4.x (Debian 13/Trixie) uses deb822 .sources format, not .list
  provisioner "shell" {
    inline = [
      "echo '=== Configure PBS Repositories ==='",
      "# Disable enterprise repo — handle both .list (PBS 3.x) and .sources (PBS 4.x) formats",
      "if [ -f /etc/apt/sources.list.d/pbs-enterprise.list ]; then",
      "  sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pbs-enterprise.list",
      "fi",
      "if [ -f /etc/apt/sources.list.d/pbs-enterprise.sources ]; then",
      "  sed -i 's/^Enabled: .*/Enabled: no/' /etc/apt/sources.list.d/pbs-enterprise.sources",
      "  grep -q '^Enabled:' /etc/apt/sources.list.d/pbs-enterprise.sources || echo 'Enabled: no' >> /etc/apt/sources.list.d/pbs-enterprise.sources",
      "fi",
      "# Add no-subscription repo (codename: ${var.pbs_debian_codename})",
      "echo 'deb http://download.proxmox.com/debian/pbs ${var.pbs_debian_codename} pbs-no-subscription' > /etc/apt/sources.list.d/pbs-no-subscription.list",
      "apt-get update",
    ]
  }

  # Install QEMU guest agent (required for Terraform/Packer IP discovery)
  provisioner "shell" {
    inline = [
      "echo '=== Install QEMU Guest Agent ==='",
      "apt-get install -y qemu-guest-agent",
      "systemctl enable qemu-guest-agent",
      "systemctl start qemu-guest-agent",
    ]
  }

  # System updates and essential packages
  provisioner "shell" {
    inline = [
      "echo '=== System Updates ==='",
      "apt-get -y dist-upgrade",
      "apt-get install -y curl wget jq",
    ]
  }

  # SSH hardening — same as Ubuntu template baseline
  provisioner "shell" {
    inline = [
      "echo '=== SSH Hardening ==='",
      "# PBS installs openssh-server by default",
      "sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config",
      "sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sed -i 's/^#\\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config",
      "sed -i 's/^#\\?X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config",
      "sed -i 's/^#\\?AllowAgentForwarding.*/AllowAgentForwarding no/' /etc/ssh/sshd_config",
      "sed -i 's/^#\\?AllowTcpForwarding.*/AllowTcpForwarding no/' /etc/ssh/sshd_config",
      "",
      "# Client-side hardening",
      "mkdir -p /etc/ssh/ssh_config.d",
      "echo 'Host *' > /etc/ssh/ssh_config.d/hardened.conf",
      "echo '    KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256' >> /etc/ssh/ssh_config.d/hardened.conf",
      "echo '    HostKeyAlgorithms ssh-ed25519,ssh-rsa' >> /etc/ssh/ssh_config.d/hardened.conf",
      "echo '    Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com' >> /etc/ssh/ssh_config.d/hardened.conf",
      "",
      "systemctl enable ssh",
      "sshd -t || (echo 'SSHD configuration error' && exit 1)",
    ]
  }

  # Firewall setup — UFW with PBS-specific ports
  provisioner "shell" {
    inline = [
      "echo '=== Firewall Setup ==='",
      "apt-get -y install ufw",
      "ufw default deny incoming",
      "ufw default allow outgoing",
      "ufw allow ssh",
      "ufw allow 8007/tcp comment 'PBS Web UI and API'",
      "echo 'y' | ufw enable",
    ]
  }

  # System hardening — fail2ban + kernel params
  provisioner "shell" {
    inline = [
      "echo '=== System Hardening ==='",
      "",
      "# fail2ban",
      "apt-get -y install fail2ban",
      "systemctl enable fail2ban",
      "",
      "# Disable unused filesystems",
      "echo 'install cramfs /bin/true' > /etc/modprobe.d/disable-filesystems.conf",
      "echo 'install freevxfs /bin/true' >> /etc/modprobe.d/disable-filesystems.conf",
      "echo 'install jffs2 /bin/true' >> /etc/modprobe.d/disable-filesystems.conf",
      "echo 'install hfs /bin/true' >> /etc/modprobe.d/disable-filesystems.conf",
      "echo 'install hfsplus /bin/true' >> /etc/modprobe.d/disable-filesystems.conf",
      "echo 'install squashfs /bin/true' >> /etc/modprobe.d/disable-filesystems.conf",
      "echo 'install udf /bin/true' >> /etc/modprobe.d/disable-filesystems.conf",
      "",
      "# Kernel security parameters",
      "echo 'kernel.randomize_va_space = 2' > /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.all.rp_filter = 1' >> /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.default.rp_filter = 1' >> /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.tcp_syncookies = 1' >> /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.icmp_echo_ignore_broadcasts = 1' >> /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.all.accept_redirects = 0' >> /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.default.accept_redirects = 0' >> /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.all.secure_redirects = 0' >> /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.default.secure_redirects = 0' >> /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.all.send_redirects = 0' >> /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv4.conf.default.send_redirects = 0' >> /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv6.conf.all.accept_redirects = 0' >> /etc/sysctl.d/99-security.conf",
      "echo 'net.ipv6.conf.default.accept_redirects = 0' >> /etc/sysctl.d/99-security.conf",
      "sysctl --system",
      "",
      "# Secure umask",
      "echo 'umask 027' >> /etc/bash.bashrc",
      "echo 'umask 027' >> /etc/profile",
    ]
  }

  # First-boot SSH host key regeneration — PBS has no cloud-init, so we need
  # a systemd oneshot service to regenerate host keys after template cloning.
  # Without this, SSH refuses to start on cloned VMs (no hostkeys available).
  provisioner "shell" {
    inline = [
      "echo '=== Create SSH Host Key Regeneration Service ==='",
      "cat > /etc/systemd/system/regenerate-ssh-host-keys.service <<'UNIT'",
      "[Unit]",
      "Description=Regenerate SSH host keys if missing (first boot after clone)",
      "Before=ssh.service",
      "ConditionPathExistsGlob=!/etc/ssh/ssh_host_*_key",
      "",
      "[Service]",
      "Type=oneshot",
      "ExecStart=/usr/bin/ssh-keygen -A",
      "RemainAfterExit=yes",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "UNIT",
      "systemctl daemon-reload",
      "systemctl enable regenerate-ssh-host-keys.service",
    ]
  }

  # Template cleanup — prepare for cloning
  provisioner "shell" {
    inline = [
      "echo '=== Template Cleanup ==='",
      "# Remove SSH host keys — regenerated on first boot by regenerate-ssh-host-keys.service",
      "rm -f /etc/ssh/ssh_host_*",
      "# Clean package cache",
      "apt-get -y autoremove --purge",
      "apt-get -y clean",
      "apt-get -y autoclean",
      "# Reset machine identity",
      "truncate -s 0 /etc/machine-id",
      "rm -f /var/lib/dbus/machine-id",
      "sync",
    ]
  }
}
