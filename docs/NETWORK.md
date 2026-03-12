# Network Architecture

This document describes the full network design for the firblab homelab infrastructure. It covers VLAN segmentation, IP addressing, firewall policy, WireGuard tunneling, reverse proxy routing, Proxmox host networking, and the Infrastructure-as-Code tooling used to manage it all.

Use this as the primary reference when troubleshooting connectivity, onboarding new hosts, or modifying firewall rules.

---

## Table of Contents

- [Overview](#overview)
- [VLAN Layout](#vlan-layout)
- [Static IP Assignments](#static-ip-assignments)
- [Inter-VLAN Firewall Rules](#inter-vlan-firewall-rules)
- [Firewall Rule Details](#firewall-rule-details)
- [CyberSecure / IDS/IPS](#cybersecure--idsips)
- [Proxmox Host Network Configuration](#proxmox-host-network-configuration)
- [Physical Switch Port Assignments](#physical-switch-port-assignments)
- [WireGuard Architecture](#wireguard-architecture)
- [Reverse Proxy Strategy](#reverse-proxy-strategy)
- [DNS Architecture](#dns-architecture)
- [Infrastructure-as-Code Management](#infrastructure-as-code-management)
- [Operational Notes](#operational-notes)

---

## Overview

The network is built around gw-01 (Ubiquiti UCG-Fiber) acting as the core router and firewall. Six VLANs segment traffic by trust level and function. All VLAN definitions, firewall rules, DHCP configuration, and port profiles are declared in Terraform and applied to gw-01 via the UniFi provider -- nothing is configured manually through the UniFi UI after initial bootstrap.

A site-to-site WireGuard tunnel connects a Hetzner gateway server (the public-facing gateway) to the homelab DMZ VLAN for inbound traffic routing. Client VPN access also terminates on the Hetzner side. A second Hetzner server (lab-honeypot) runs cybersecurity deception services with a separate WireGuard client tunnel for log shipping.

**Key design principles:**

- The Management VLAN (10) has unrestricted access to all other VLANs (the administrative control plane).
- The Default/LAN (1) currently has full access to all lab VLANs (workstation admin access). This will be tightened once port profiles are fully enforced.
- The Storage VLAN (40) accepts inbound connections only and has no outbound access.
- The Security VLAN (50) is restricted to outbound update traffic only (apt, Docker registries).
- All internet-facing traffic enters through Hetzner and traverses the WireGuard tunnel to reach homelab services.

---

## VLAN Layout

| VLAN ID | Name | Subnet | Gateway | DHCP Range | Purpose |
|---------|------|--------|---------|------------|---------|
| 1 | Default/LAN | 10.0.4.0/24 | 10.0.4.1 | .100-.254 | gw-01 default network, workstation. Isolated from lab VLANs except Management (admin access). |
| 10 | Management | 10.0.10.0/24 | 10.0.10.1 | .100-.200 | Proxmox hosts, gw-01, Mac Mini, RPi, SSH access. The administrative control plane. |
| 20 | Services | 10.0.20.0/24 | 10.0.20.1 | .100-.200 | RKE2 cluster nodes, standalone application VMs and LXCs (Ghost, FoundryVTT, Mealie, etc.). |
| 30 | DMZ | 10.0.30.0/24 | 10.0.30.1 | .100-.200 | WireGuard endpoint, any internet-facing services. Heavily restricted from reaching internal VLANs. |
| 40 | Storage | 10.0.40.0/24 | 10.0.40.1 | .100-.200 | NFS shares, Longhorn replication traffic, backup data transfers. Accept-only -- no outbound. |
| 50 | Security | 10.0.50.0/24 | 10.0.50.1 | .100-.200 | Vault cluster node (vault-2). Isolated sensitive infrastructure. |
| 60 | IoT | 10.0.60.0/24 | 10.0.60.1 | .100-.200 | Home Assistant, IoT devices. Restricted cross-VLAN access. |

All VLANs use a /24 subnet with a 24-hour DHCP lease. Static assignments for infrastructure hosts are outside the DHCP range (below .100). The DHCP range .100-.200 leaves .201-.254 available for additional static reservations or special-purpose ranges (such as MetalLB on the Services VLAN).

---

## Static IP Assignments

### Management VLAN (10)

| IP Address | Hostname | Role |
|------------|----------|------|
| 10.0.10.1 | gw-01 | Default gateway, VLAN router, firewall |
| 10.0.10.2 | lab-02 | Proxmox host (pilot node, N100 16GB -- GitLab, vault-2, Runner) |
| 10.0.10.3 | lab-03 | Proxmox host (lightweight services, Intel N100 12GB -- Ghost, Mealie, Roundcube) |
| 10.0.10.4 | lab-04 | Proxmox host (Dell Wyse, Pentium J5005 20GB -- NetBox) |
| 10.0.10.42 | lab-01 | Proxmox host (main compute, i9-12900K 64GB -- RKE2 cluster, 6 VMs) |
| 10.0.10.10 | vault-1 | Vault primary -- Mac Mini M4 (native macOS) |
| 10.0.10.13 | vault-3 | Vault standby -- RPi5 CM5 (Ubuntu 24.04 ARM64, bare metal) |
| 10.0.10.50 | gitlab | GitLab CE (VM on lab-02, port 80/443) |
| 10.0.10.51 | gitlab-runner | GitLab Runner (LXC on lab-02, Docker executor) |
| 10.0.10.90 | lab-08 (vlan10) | Scanopy scanner sub-interface (RPi4, VLAN 10 L2 scanning) |

### Services VLAN (20)

| IP Address / Range | Hostname | Role |
|--------------------|----------|------|
| 10.0.20.1 | -- | Default gateway |
| 10.0.20.10 | ghost | Ghost blog (LXC on lab-03, port 2368) |
| 10.0.20.11 | roundcube | Roundcube webmail (LXC on lab-03, port 8080) |
| 10.0.20.12 | foundryvtt | FoundryVTT virtual tabletop (VM on lab-03, port 30000) |
| 10.0.20.13 | mealie | Mealie recipe manager (LXC on lab-03, port 9000) |
| 10.0.20.14 | netbox | NetBox DCIM/IPAM (VM on lab-04, port 8080) |
| 10.0.20.15 | patchmon | PatchMon patch monitoring (VM on lab-04, port 3000) |
| 10.0.20.16 | actualbudget | Actual Budget personal finance (LXC on lab-03, port 5006) |
| 10.0.20.18 | ai-gpu | AI GPU VM (lab-01, ports 11434/3000/5678) |
| 10.0.20.19 | vaultwarden | Vaultwarden password vault (LXC on lab-03, port 8000) |
| 10.0.20.20 | lab-09 / archive | Archive appliance (ZimaBlade 7700 bare-metal, switch-03 Port 4, ports 8080-8085: FileBrowser, Kiwix, ArchiveBox, BookStack, Stirling PDF, Wallabag) |
| 10.0.20.90 | lab-08 (vlan20) | Scanopy scanner sub-interface (RPi4, VLAN 20 L2 scanning) |
| 10.0.20.21-.59 | (reserved) | Static assignments for future VMs, LXCs, and bare-metal devices |
| 10.0.20.60 | k3s-server-1 | K3s server node (RPi5 8GB bare-metal, switch-03 Port 1) |
| 10.0.20.61 | k3s-server-2 | K3s server node (RPi5 8GB bare-metal, switch-03 Port 2) |
| 10.0.20.62 | k3s-server-3 | K3s server node (RPi5 4GB bare-metal, switch-03 Port 3) |
| 10.0.20.63-.89 | (reserved) | Static assignments for future VMs, LXCs, and bare-metal devices |
| 10.0.20.100-.200 | (DHCP pool) | Dynamic assignments |
| 10.0.20.200-.219 | K3s MetalLB pool | K3s LoadBalancer IPs — Traefik (.200), Loki (.201) |
| 10.0.20.220-.250 | RKE2 MetalLB pool | RKE2 LoadBalancer IPs — Traefik (.220) |

Two non-overlapping MetalLB pools on the Services VLAN. K3s pool defined in `k8s/k3s-platform/metallb/config.yaml`, RKE2 pool in `k8s/platform/metallb/helm/values.yaml`.

### Default/LAN (VLAN 1)

| IP Address | Hostname | Role |
|------------|----------|------|
| 10.0.4.1 | gw-01 | Default gateway, core router |
| 10.0.4.20 | lab-08 | Scanopy network scanner + NUT UPS server (RPi4, bare metal, NVMe via USB enclosure) |

> **Note:** lab-08 is on VLAN 1 (Default LAN) as its native/primary VLAN. Its switch port uses a Scanner Trunk profile (native VLAN 1, tagged 10/20/30/40/50) with 802.1Q sub-interfaces (eth0.10 through eth0.50) giving the Scanopy daemon full Layer 2 ARP/MAC scanning on all VLANs. The LAN zone also has bidirectional ALLOW ALL policies to every lab VLAN.

### DMZ VLAN (30)

| IP Address | Hostname | Role |
|------------|----------|------|
| 10.0.30.1 | -- | Default gateway |
| 10.0.30.2 | wireguard | WireGuard gateway LXC (lab-03, VM ID 5020). Site-to-site tunnel to Hetzner, NAT/masquerade to Services VLAN 20. |
| 10.0.30.90 | lab-08 (vlan30) | Scanopy scanner sub-interface (RPi4, VLAN 30 L2 scanning) |

### Storage VLAN (40)

| IP Address | Hostname | Role |
|------------|----------|------|
| 10.0.40.1 | -- | Default gateway |
| 10.0.40.2 | TrueNAS | NFS, Plex, ZFS backups (i5-9500, 16GB, ZFS). Storage Access port profile on switch-01 Port 2. |
| 10.0.40.90 | lab-08 (vlan40) | Scanopy scanner sub-interface (RPi4, VLAN 40 L2 scanning) |

### Security VLAN (50)

| IP Address | Hostname | Role |
|------------|----------|------|
| 10.0.50.1 | -- | Default gateway |
| 10.0.50.2 | vault-2 | Vault standby -- Proxmox VM (Rocky Linux 9 x86_64) |
| 10.0.50.90 | lab-08 (vlan50) | Scanopy scanner sub-interface (RPi4, VLAN 50 L2 scanning) |

> **Note:** GitLab CE is on Management VLAN 10 (10.0.10.50), NOT Security VLAN 50. Wazuh Manager is not deployed (removed due to lab-02 RAM constraint).

### IoT VLAN (60)

| IP Address | Hostname | Role |
|------------|----------|------|
| 10.0.60.1 | -- | Default gateway |
| 10.0.60.10 | lab-11 / homeassistant | Home Assistant OS (HAOS) on RPi CM4 8GB Lite |

---

## Zone-Based Firewall

Firewall policies are managed declaratively in Terraform using the **Zone-Based Firewall** model (UniFi OS 9.x). Each VLAN is assigned to a firewall zone, and policies define allowed/blocked traffic between zones.

See `terraform/layers/00-network/main.tf` for the full configuration.

### Zone Mapping

| Zone | Network(s) | VLAN |
|------|-----------|------|
| Management | Management | 10 |
| Services | Services | 20 |
| DMZ | DMZ | 30 |
| Storage | Storage | 40 |
| Security | Security | 50 |
| IoT | IoT | 60 |
| LAN | Default | 1 |

### Zone Policy Summary

| Source Zone | Destination Zone | Action | Ports |
|------------|-----------------|--------|-------|
| Management | Services | ALLOW | All |
| Management | DMZ | ALLOW | All |
| Management | Storage | ALLOW | All |
| Management | Security | ALLOW | All |
| Management | LAN | ALLOW | All |
| Security | Management | ALLOW | All |
| Services | Management | ALLOW | All |
| Storage | Management | ALLOW | All |
| DMZ | Management | ALLOW | All |
| Services | Storage | ALLOW | NFS (2049, 111), iSCSI (3260) |
| Services | Security | ALLOW | Vault API (8200) |
| Services | Security | ALLOW | GitLab (80, 443, 22) |
| Services | Security | ALLOW | Wazuh (1514, 1515) |
| LAN | Management | ALLOW | All |
| LAN | Security | ALLOW | All |
| LAN | Services | ALLOW | All |
| LAN | DMZ | ALLOW | All |
| LAN | Storage | ALLOW | All |
| Security | LAN | ALLOW | All |
| Services | LAN | ALLOW | All |
| DMZ | LAN | ALLOW | All |
| Storage | LAN | ALLOW | All |
| DMZ | Services | ALLOW | Homelab Service Ports (80, 443, 2368, 8080, 9000, 30000) |
| Services | DMZ | ALLOW | All (return traffic — zone policies are stateless) |
| DMZ | Storage | BLOCK | All |
| DMZ | Security | BLOCK | All |
| Management | IoT | ALLOW | All |
| IoT | Management | ALLOW | All |
| LAN | IoT | ALLOW | All |
| IoT | LAN | ALLOW | All |
| Services | IoT | ALLOW | All |
| IoT | Services | ALLOW | All |
| DMZ | IoT | BLOCK | All |
| IoT | DMZ | BLOCK | All |
| IoT | Storage | BLOCK | All |
| IoT | Security | BLOCK | All |

### Zone Policy Details

Policies are evaluated in order of their `index`. Lower numbers are evaluated first. The general structure:

- **1000-1099**: Management full-access policies
- **2000-2099**: Selective allow policies (specific permitted cross-zone traffic)
- **9000-9099**: Block policies (explicit deny between zones)

**Management (10) -- full access (rule 2000)**

The Management VLAN is the administrative control plane. It has unrestricted access to all other VLANs. This is required for SSH access to all hosts, Proxmox Web UI (port 8006), Vault management, and Ansible/Terraform operations.

**Services (20) -- selective access to Storage and Security**

The RKE2 cluster and standalone services need to reach:
- Storage VLAN for persistent data: NFS on ports 2049 and 111 (TCP), iSCSI on port 3260 (TCP). Longhorn uses iSCSI for distributed block storage replication.
- Security VLAN for secrets and CI/CD: Vault API on port 8200 (TCP), GitLab on ports 80, 443, and 22 (TCP), and Wazuh agent enrollment on ports 1514 and 1515 (TCP).

All other cross-VLAN traffic from Services is dropped, including direct access to the DMZ.

**DMZ (30) -- WireGuard tunnel traffic, port-filtered**

The DMZ hosts the WireGuard gateway LXC (10.0.30.2) which terminates the site-to-site tunnel from Hetzner. Traffic from the tunnel is NATted (masqueraded to 10.0.30.2) and forwarded to the Services VLAN through a port-filtered zone policy. Allowed ports are defined in the `homelab_service_ports` firewall group: HTTP (80), HTTPS (443), Ghost (2368), Roundcube (8080), Mealie (9000), and FoundryVTT (30000). To expose a new service, add its port to the firewall group. The DMZ has bidirectional ALLOW with Management (required because UniFi zone policies are not stateful — Management→DMZ SSH/Ansible needs return traffic). The DMZ is blocked from reaching Storage and Security VLANs entirely. Host-level UFW on Management hosts provides the second layer of defense against DMZ-initiated connections.

**Storage (40) -- accept-only, no outbound**

The Storage VLAN is a data sink. It accepts inbound NFS and iSCSI connections from the Services VLAN but initiates no outbound connections. This limits the blast radius if a storage host is compromised.

**Security (50) -- restricted outbound**

Hosts on the Security VLAN (Vault, Wazuh, GitLab) are allowed outbound access only for package updates (apt repositories) and Docker image pulls. All other outbound traffic is blocked. Inbound access is limited to the specific ports allowed from the Services VLAN.

**Default/LAN (1) -- workstation admin access**

The Default LAN hosts the workstation (MacBook Pro) which is the primary admin box. It has ALLOW policies to all lab VLANs (Management, Security, Services, DMZ, Storage) and bidirectional return policies. This mirrors Management's full access for SSH, Ansible, Terraform, Vault API, GitLab, and other admin operations. Without these policies, every new VLAN deployment requires re-debugging inter-VLAN routing from the workstation.

> **NOTE:** The LAN → all ALLOW policies explain why all devices currently work despite having no port profiles assigned to switch ports. Once port profiles are enforced and the broad LAN ALLOW policies are tightened, only correctly profiled ports will have VLAN access.

**IoT (60) -- Home Assistant and smart devices**

The IoT VLAN hosts Home Assistant (HAOS on RPi CM4 8GB, NVMe via USB) and future IoT devices. Permitted cross-VLAN access:
- Management VLAN (bidirectional): admin SSH, Traefik reverse proxy (10.0.10.17 → HA:8123), HA → Authentik OIDC (10.0.10.16), HA → Proxmox API (port 8006, read-only monitoring), HA → GitLab (via Traefik, Git Pull config sync).
- LAN (bidirectional): workstation access to HA dashboard during setup and daily use.
- Services VLAN (bidirectional): Prometheus scraping HA metrics endpoint, HA pushing data to services.

The IoT VLAN is blocked from reaching Storage (no NFS/iSCSI needed), Security (no direct Vault access), and DMZ (no internet-facing exposure). IoT devices reach the internet via their VLAN gateway (10.0.60.1) — zone policies only control inter-VLAN traffic.

---

## CyberSecure / IDS/IPS

**Managed by:** Terraform Layer 00 (`terraform/layers/00-network/security.tf`)

UCG-Fiber CyberSecure settings are codified in Terraform where the provider supports them. The UCG-Fiber has hardware-accelerated IPS offload, so throughput impact is minimal.

### Terraform-Managed Settings

| Feature | Setting | Scope | Notes |
|---------|---------|-------|-------|
| **Intrusion Prevention** | IPS mode (active blocking) | All 7 VLANs | Blocks threats, not just detection |
| **Deep Packet Inspection** | Enabled + fingerprinting | Site-wide | App identification for traffic visibility |
| **Torrent Blocking** | Enabled | Site-wide | No legitimate P2P use case |
| **SSL Inspection** | Off | Site-wide | We manage TLS at the app layer (Vault CA, Let's Encrypt) |

### Manual UI Settings

These features are configured via the UniFi UI because the Terraform provider either has bugs (Read returns empty lists, causing perpetual drift) or lacks resources entirely.

**Configured via UI:**

| Feature | Setting | Status | Configuration Path |
|---------|---------|--------|-------------------|
| **Ad Blocking** | IoT (60) + Default LAN (1) | ✅ Configured | CyberSecure → Ad Blocking |
| **Region/Country Blocking** | RU, CN, KP, IR + additional | ✅ Configured | CyberSecure → Region Blocking |

**Not configured (skipped):**

| Feature | Configuration Path | Notes |
|---------|-------------------|-------|
| DNS Content Filter | CyberSecure → Content Filter | Provider bug (Read returns empty) |
| Encrypted DNS (DoH/DoT) | CyberSecure → Encrypted DNS | No provider resource |
| Per-App Blocking | CyberSecure → App Blocking | No provider resource |
| Traffic Logging | CyberSecure → Traffic Logging | No provider resource |

### Security Layers (Defense in Depth)

Network security is applied at multiple layers:

1. **Gateway (UCG-Fiber):** Zone-based firewall policies (inter-VLAN routing) + IDS/IPS (threat detection/blocking) + DNS content filtering
2. **Host firewall (UFW/iptables):** Per-host port-level access control (Ansible-managed)
3. **Application (Traefik):** TLS termination (Let's Encrypt DNS-01), Authentik ForwardAuth, security headers
4. **Endpoint (hosts):** CrowdSec, fail2ban, Wazuh agent enrollment

---

## Proxmox Host Network Configuration

All four Proxmox hosts (`lab-01`, `lab-02`, `lab-03`, `lab-04`) use VLAN-aware bridging on `vmbr0`. This allows any VM or LXC on the host to be assigned to any VLAN by setting a VLAN tag on its network interface -- no additional bridges needed per VLAN.

### Bridge Configuration

```
auto vmbr0
iface vmbr0 inet static
    address 10.0.10.X/24        # .2=lab-02, .3=lab-03, .4=lab-04, .42=lab-01
    gateway 10.0.10.1           # gw-01 on Management VLAN
    bridge-ports <physical-nic>    # e.g., eno1
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
```

The host management IP is on the Management VLAN (10). The physical NIC connects to a UniFi switch port configured with the "Proxmox Trunk" port profile, which passes all lab VLAN tags.

### How It Works

- The Proxmox host itself communicates on VLAN 10 (untagged/native on the trunk).
- VMs and LXCs are assigned a VLAN tag in their Proxmox network configuration (e.g., `tag=20` for Services).
- The VLAN-aware bridge handles 802.1Q tagging transparently.
- The UniFi switch port must be set to the "Proxmox Trunk" port profile (managed by Terraform) to allow tagged traffic for the lab VLANs.
- Ansible renders `bridge-vids` from the canonical lab VLAN inventory (`network_vlans` in `ansible/inventory/group_vars/all.yml`) instead of using a `1-4094` or `2-4094` range.
- This is required for Mellanox `mlx5` NICs such as `lab-01`: their hardware VLAN table tops out at 512 entries, so broad ranges cause the driver to drop VLAN programming during boot.
- Ansible also enables promiscuous mode on the management bridge port automatically for Mellanox `mlx5` NICs unless a host overrides that behavior. On `lab-01`, this is required for ARP/neigh resolution to survive reboot consistently.
- `lab-01` still keeps `bridge-pvid 1` on `vmbr0` because its management link relies on the native/untagged side of the trunk, but the allowed VLAN set is now resolved the same way as every other Proxmox node.

### Storage Bridge (vmbr1) — lab-01 Only

lab-01 has a dedicated `vmbr1` bridge for point-to-point 10G storage traffic to TrueNAS, bypassing the switch fabric entirely.

```
auto vmbr1
iface vmbr1 inet static
    address 10.10.10.1/30
    bridge-ports enp10s0f1np1    # Mellanox CX4121C Port 2 (SFP28)
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware no
    mtu 9000
```

- **Peer:** TrueNAS at `10.10.10.2/30` (Mellanox CX4121C Port 2)
- **Link:** Direct-attach copper (DAC), 10G, jumbo frames (MTU 9000)
- **Subnet:** `10.10.10.0/30` — a dedicated L3 domain separate from any VLAN. Uses a distinct subnet because TrueNAS middleware rejects overlapping networks across interfaces (a /30 within the Storage VLAN /24 on enp2s0 fails validation).
- **NFS ACLs:** TrueNAS NFS exports must include `10.10.10.1` (or `10.10.10.0/30`) in allowed networks for shares accessed over this link.
- **Purpose:** Host-level NFS/iSCSI mounts for Proxmox storage. VMs on lab-01 reach TrueNAS via the switched path (`10.0.40.2` through vmbr0 VLAN 40) by default.
- **IaC:** `proxmox_storage_bridge_ports` / `proxmox_storage_ip` / `proxmox_storage_mtu` in `ansible/inventory/host_vars/lab-01.yml`, template `ansible/playbooks/templates/proxmox-interfaces.j2`

### Management

This configuration is deployed and maintained via Ansible:

```
# Initial bootstrap (connects as root — first time only):
ansible-playbook ansible/playbooks/proxmox-bootstrap.yml --limit lab-01

# Day-2 network updates (connects as admin — safe for already-bootstrapped nodes):
ansible-playbook ansible/playbooks/proxmox-network-update.yml --limit lab-01
```

The bootstrap playbook templates the `/etc/network/interfaces` file using `proxmox-interfaces.j2`, sets up the admin user, hardens SSH, and configures host-level iptables rules that restrict access to the management subnet only (SSH on port 22, Proxmox UI on port 8006, cluster ports 5405-5412, migration ports 60000-60050). The `proxmox-network-update.yml` playbook provides a safe day-2 path to re-deploy network configuration without requiring root access.

See `ansible/playbooks/proxmox-bootstrap.yml` for the full implementation.

---

## Physical Switch Port Assignments

Four switches distribute connectivity across three physical locations. All switches connect directly to gw-01 (flat topology -- no daisy-chaining). All port profiles are managed by Terraform (Layer 00, `devices.tf`).

### Switch A: "switch-01" — USW Flex 2.5G 5-port (closet)

- **MAC:** `52:54:00:11:22:01`
- **Uplink:** Port 5 → gw-01 2.5G Port 1

| Port | Device | Port Profile | VLAN(s) | Notes |
|------|--------|-------------|---------|-------|
| 1 | *(empty)* | -- | -- | Freed — lab-01 moved to switch-04 Port 1 |
| 2 | TrueNAS (js-4) @ 10.0.40.2 | Storage Access | VLAN 40 (Storage) | NFS, Plex, backups (i5-9500, 16GB, ZFS). Migrated from Default LAN to Storage VLAN 40. |
| 3 | lab-04 (Dell Wyse 20GB) | Proxmox Trunk | Native 10, Tagged 20/30/40/50 | Lightweight compute — NetBox VM (5030, 10.0.20.14) |
| 4 | lab-08 (RPi4) @ 10.0.4.20 | Scanner Trunk | Native 1, Tagged 10/20/30/40/50 | Scanopy network scanner + NUT UPS server. NVMe boot via USB enclosure. Trunk gives daemon L2 ARP/MAC scanning on all VLANs via sub-interfaces. |
| 5 | gw-01 uplink | *(auto-managed)* | Trunk | Uplink -- carries all VLAN traffic |

### Switch B: "switch-02" — USW Flex 2.5G 8 (minilab)

- **MAC:** `52:54:00:11:22:02`
- **Uplink:** Port 9 → gw-01 2.5G Port 2
- **Ports:** 8 copper + 1 uplink (port 9) + 1 SFP (port 10)

| Port | Device | Port Profile | VLAN(s) | Notes |
|------|--------|-------------|---------|-------|
| 1 | lab-03 (N100 12GB) | Proxmox Trunk | Native 10, Tagged 20/30/40/50 | Lightweight services |
| 2 | JetKVM | Management Access | VLAN 10 untagged | KVM-over-IP for Mac Mini management |
| 3 | Mac Mini / vault-1 | Management Access | VLAN 10 untagged | Vault primary @ 10.0.10.10 |
| 4 | lab-02 (N100 16GB) | Proxmox Trunk | Native 10, Tagged 20/30/40/50 | Pilot node: GitLab, vault-2, Runner |
| 5 | RPi5 CM5 / vault-3 | Management Access | VLAN 10 untagged | Vault standby @ 10.0.10.13 |
| 6-7 | *(empty)* | -- | -- | Available for future devices |
| 8 | lab-11 (CM4 8GB) @ 10.0.60.10 | IoT Access | VLAN 60 (IoT) | Home Assistant OS (HAOS). RPi CM4 Wireless 8GB Lite (CM4108000), NVMe SSD via USB enclosure. |
| 9 | gw-01 uplink | *(auto-managed)* | Trunk | Uplink -- carries all VLAN traffic |
| 10 | *(SFP, empty)* | -- | -- | |

### Switch C: "switch-03" — USW Flex 2.5G 5-port (rackmate)

- **MAC:** `52:54:00:11:22:03`
- **Uplink:** Port 5 → gw-01 2.5G Port 3

| Port | Device | Port Profile | VLAN(s) | Notes |
|------|--------|-------------|---------|-------|
| 1 | k3s-server-1 (RPi5 8GB) | Services Access | VLAN 20 untagged | K3s server node @ 10.0.20.60 |
| 2 | k3s-server-2 (RPi5 8GB) | Services Access | VLAN 20 untagged | K3s server node @ 10.0.20.61 |
| 3 | k3s-server-3 (RPi5 4GB) | Services Access | VLAN 20 untagged | K3s server node @ 10.0.20.62 |
| 4 | lab-09 / ZimaBlade 7700 | Services Access | VLAN 20 | Archive appliance (MAC: 52:54:00:11:22:09, GbE). Kiwix, ArchiveBox, BookStack, Stirling PDF, Wallabag, FileBrowser. |
| 5 | gw-01 uplink | *(auto-managed)* | Trunk | Uplink — 2.5 GbE (was 100 Mbps on UDM Pro) |

### Switch D: "switch-04" — USW Pro XG 8 PoE (closet)

- **MAC:** `52:54:00:11:22:04`
- **Uplink:** SFP+ 2 (port 10) → gw-01 (10G DAC backbone)
- **Ports:** 8x 10G multi-speed RJ45 (1-8) + 2x SFP+ (9-10)

| Port | Device | Port Profile | VLAN(s) | Notes |
|------|--------|-------------|---------|-------|
| 1 | *(empty)* | -- | -- | Previously lab-01 onboard 1GbE (moved to SFP+ 1). |
| 2 | U7 Pro (10.0.4.133) | AP Trunk | Native 1, All VLANs tagged | Wireless AP. PoE++ powered. Moved from gw-01 Port 4. |
| 3-8 | *(empty)* | -- | -- | Available for future 10G devices. |
| SFP+ 1 (port 9) | lab-01 (i9-12900K) | Proxmox Trunk | Native 10, Tagged 20/30/40/50 | Main compute. 10G via Mellanox CX4121C SFP28 Port 1 (DAC). Mellanox Port 2: direct DAC to TrueNAS (point-to-point storage, not switch-connected). |
| SFP+ 2 (port 10) | gw-01 uplink | *(auto-managed)* | Trunk | 10G DAC backbone to UCG-Fiber |

### Port Profile Reference

| Profile Name | Native VLAN | Tagged VLANs | Use Case |
|--------------|-------------|-------------|----------|
| Proxmox Trunk | 10 (Management) | 20, 30, 40, 50 | Proxmox hosts -- VMs get VLAN tags via VLAN-aware vmbr0 |
| Management Access | 10 (Management) | None | Single-VLAN hosts on Management (Mac Mini, RPi, JetKVM) |
| Services Access | 20 (Services) | None | Single-VLAN hosts on Services |
| Storage Access | 40 (Storage) | None | TrueNAS (10.0.40.2), NAS devices |
| Scanner Trunk | 1 (Default LAN) | 10, 20, 30, 40, 50 | Network scanner host -- L2 presence on all VLANs via sub-interfaces |
| IoT Access | 60 (IoT) | None | Single-VLAN hosts on IoT (Home Assistant, smart devices) |

### STP Priority Assignments

All switches connect directly to gw-01 (flat topology — no daisy-chaining). STP priorities are staggered to ensure deterministic root bridge election. Managed by Ansible (`unifi-config` role), triggered from Terraform Layer 00.

| Switch | Priority | Rationale |
|--------|----------|-----------|
| gw-01 (UCG-Fiber) | *(self-managed)* | Gateway — always root bridge |
| switch-04 (USW Pro XG 8 PoE) | 4096 | 10G backbone, highest-bandwidth uplink to gateway |
| switch-01 (USW Flex 2.5G 5, closet) | 8192 | Main compute (lab-01, lab-04) |
| switch-02 (USW Flex 2.5G 8, minilab) | 12288 | Pilot node, Vault cluster nodes, Home Assistant |
| switch-03 (USW Flex 2.5G 5, rackmate) | 16384 | K3s cluster, archive appliance |

---

## WireGuard Architecture

A site-to-site WireGuard tunnel connects the Hetzner gateway server to the homelab DMZ VLAN. This is the sole ingress path for external traffic reaching homelab services. A second Hetzner server (lab-honeypot) runs dedicated honeypot services and connects back to the gateway via a WireGuard client tunnel for log shipping.

### Tunnel Topology

```
                        Public Internet
                              |
              +---------------+---------------+
              |                               |
   +----------+----------+         +----------+----------+
   |  Hetzner Gateway    |         |  Hetzner Honeypot   |
   |  lab-gateway    |         |  lab-honeypot   |
   |  (cpx22, Nuremberg) |         |  (cpx22, Nuremberg) |
   |                     |         |                     |
   |  Traefik v3         |         |  Cowrie (SSH/Telnet)|
   |  WireGuard server   |<--------+  OpenCanary (FTP,   |
   |  AdGuard Home       |  WG     |    MySQL, RDP, VNC, |
   |  CrowdSec + Fail2ban|  client |    Redis)           |
   |  Gotify + Uptime    |         |  Dionaea (SMB, SIP, |
   +----------+----------+         |    HTTP, HTTPS)     |
              |                    |  Endlessh (tarpit)  |
              | WireGuard tunnel   |  Grafana Alloy      |
              | Subnet: 10.8.0.0/24|    (logs -> Loki)   |
              |                    +---------------------+
   +----------+----------+           DNS: honeypot.example-lab.org
   |  WireGuard LXC      |           IP: 203.0.113.11
   |  DMZ VLAN (30)      |  <-- 10.0.30.2
   |  lab-03         |  <-- NAT/masquerade to eth0
   +----------+----------+
              |
              | Routed via gw-01
              | (DMZ -> Services, port-filtered:
              |  80, 443, 2368, 8080, 9000, 30000)
              |
   +----------+----------+
   |  Services VLAN (20) |
   |                     |
   |  Ghost     (.10)    |  <-- Blog (port 2368)
   |  Roundcube (.11)    |  <-- Webmail (port 8080)
   |  FoundryVTT(.12)    |  <-- Virtual tabletop (port 30000)
   |  Mealie    (.13)    |  <-- Recipe manager (port 9000)
   |  RKE2/MetalLB       |  <-- k8s services (.220-.250, ports 80/443)
   +---------------------+
```

> **Note:** The honeypot server runs a WireGuard **client** that connects to the gateway's WireGuard server. This tunnel carries Grafana Alloy log traffic from the honeypot back to the homelab Loki instance. The honeypot has no direct route to homelab VLANs -- all log shipping flows through the gateway's tunnel.

### Tunnel Details

#### Site-to-Site Tunnel (Gateway <-> Homelab)

| Parameter | Hetzner Gateway (Server) | Homelab Side (Client) |
|-----------|----------------------|----------------------|
| Role | WireGuard server (Docker) | WireGuard client (native) |
| Tunnel IP | 10.8.0.1/24 | 10.8.0.2/32 |
| Listen port | 51820 (public) | -- (initiates outbound) |
| Host | lab-gateway (cpx22, Nuremberg) | DMZ LXC 10.0.30.2 (lab-03) |
| AllowedIPs (server-side) | -- | 10.8.0.2/32, 10.0.20.0/24, 10.0.30.0/24 |
| AllowedIPs (client-side) | 10.8.0.0/24 | -- |
| PersistentKeepalive | -- | 25s |
| PostUp/PostDown | -- | NAT/masquerade on eth0 |
| Managed by | Terraform Layer 06 (cloud-init) | Ansible `wireguard-deploy.yml` |

#### Honeypot Log Tunnel (Honeypot -> Gateway)

| Parameter | Honeypot Side (Client) | Gateway Side (Server) |
|-----------|----------------------|----------------------|
| Role | WireGuard client (Docker) | WireGuard server (Docker) |
| Tunnel IP | Assigned by gateway (10.8.0.x/32) | 10.8.0.1/24 |
| Listen port | -- (initiates outbound) | 51820 |
| Host | lab-honeypot (cpx22, Nuremberg) | lab-gateway (cpx22, Nuremberg) |
| Purpose | Grafana Alloy ships honeypot logs to homelab Loki via gateway tunnel | Relays log traffic to homelab |
| DNS | honeypot.example-lab.org | -- |
| Managed by | Ansible `honeypot-deploy.yml` | Terraform Layer 06 (cloud-init, peer config) |

### Traffic Flows

**Inbound public traffic (e.g., https://blog.example.com):**

1. DNS resolves to Hetzner VPS public IP (Cloudflare DNS, managed by Terraform).
2. Traefik on Hetzner terminates TLS (Let's Encrypt ACME).
3. Traefik forwards the request through the WireGuard tunnel to the homelab backend (e.g., Ghost at 10.0.20.x).
4. The WireGuard LXC on DMZ VLAN (30) receives the packet and routes it to the Services VLAN (20) via gw-01.
5. gw-01 firewall allows DMZ-to-Services HTTP/HTTPS traffic to the specific backend IP.
6. The response traverses the same path in reverse.

**Client VPN access (remote administration):**

1. Up to 20 WireGuard peers configured on the Hetzner VPS.
2. Authenticated clients receive a tunnel IP in the 10.8.0.0/24 range.
3. Routes to 10.0.10.0/24 (Management) and 10.0.20.0/24 (Services) are pushed to the client.
4. Traffic is forwarded through the site-to-site tunnel to the homelab.

**NAT/masquerade design:**

The WireGuard LXC uses iptables NAT/masquerade on its eth0 interface. Traffic exiting the LXC toward VLAN 20 gets source-NATted to 10.0.30.2 (the LXC's DMZ address). Service hosts respond to 10.0.30.2, which gw-01 routes back to the DMZ VLAN, and the LXC puts the response back into the tunnel. This avoids needing static routes for 10.8.0.0/24 on gw-01.

### Hetzner Honeypot Server (lab-honeypot)

A dedicated cpx22 (4 vCPU, 8GB) running Ubuntu 24.04 in Hetzner Nuremberg. Provisioned by Terraform Layer 06, services deployed by Ansible (`honeypot-deploy.yml`). DNS: `honeypot.example-lab.org`. IP: `203.0.113.11`.

**Services:**

| Service | Port(s) | Protocol | Purpose |
|---------|---------|----------|---------|
| Cowrie | 22 (SSH), 23 (Telnet) | TCP | Interactive SSH/Telnet honeypot — captures credentials, commands, uploaded files |
| OpenCanary | 21 (FTP), 3306 (MySQL), 3389 (RDP), 5900 (VNC), 6379 (Redis) | TCP | Multi-protocol honeypot — alerts on connection attempts |
| Dionaea | 445 (SMB), 5060 (SIP), 8080 (HTTP), 8443 (HTTPS) | TCP/UDP | Malware capture honeypot — traps exploit payloads |
| Endlessh | 2223 | TCP | SSH tarpit — holds connections open indefinitely to waste attacker time |
| Grafana Alloy | -- (outbound only) | -- | Log aggregation agent — ships all honeypot logs to homelab Loki via WireGuard tunnel |

**Hetzner Firewall:**

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 2222 | TCP | WireGuard tunnel + home network | Real SSH (admin access) |
| 51820 | UDP | 0.0.0.0/0, ::/0 | WireGuard client (connect to gateway) |
| 21 | TCP | 0.0.0.0/0, ::/0 | FTP honeypot (OpenCanary) |
| 22 | TCP | 0.0.0.0/0, ::/0 | SSH honeypot (Cowrie) |
| 23 | TCP | 0.0.0.0/0, ::/0 | Telnet honeypot (Cowrie) |
| 445 | TCP | 0.0.0.0/0, ::/0 | SMB honeypot (Dionaea) |
| 3306 | TCP | 0.0.0.0/0, ::/0 | MySQL honeypot (OpenCanary) |
| 3389 | TCP | 0.0.0.0/0, ::/0 | RDP honeypot (OpenCanary) |
| 5060 | UDP | 0.0.0.0/0, ::/0 | SIP honeypot (Dionaea) |
| 5900 | TCP | 0.0.0.0/0, ::/0 | VNC honeypot (OpenCanary) |
| 6379 | TCP | 0.0.0.0/0, ::/0 | Redis honeypot (OpenCanary) |
| 8080 | TCP | 0.0.0.0/0, ::/0 | HTTP honeypot (Dionaea) |
| 8443 | TCP | 0.0.0.0/0, ::/0 | HTTPS honeypot (Dionaea) |

> **Note:** All honeypot ports are intentionally public -- attracting attacker traffic is the purpose. Real SSH on port 2222 is restricted to the WireGuard tunnel CIDR and home network only. The server has no route to homelab VLANs; log traffic flows through the WireGuard client tunnel to the gateway, then through the site-to-site tunnel to Loki.

---

## Reverse Proxy Strategy

Traffic is routed through three Traefik instances depending on where it originates and what it targets.

### External: Traefik on Hetzner

- **Traefik v3** runs on the Hetzner VPS as a Docker container (`network_mode: host`).
- Handles TLS termination for all public-facing domains (`*.example-lab.org`) using Let's Encrypt ACME HTTP-01.
- Routes requests to homelab backends through the WireGuard tunnel based on hostname.
- Provides middleware for security headers, rate limiting, and basic auth (dashboard).

Example route: `blog.example-lab.org` -> Traefik (Hetzner) -> WireGuard tunnel -> Ghost (10.0.20.10:2368 on Services VLAN).

### Internal: K8s Traefik Ingress Controller (RKE2)

- **Traefik v3** (Helm chart v35, deployed via ArgoCD wave 0) handles routing for RKE2 K8s workloads.
- Receives MetalLB LoadBalancer VIP at `10.0.20.220` (Services VLAN 20).
- 2 replicas with pod anti-affinity across agent nodes.
- TLS certificates issued by cert-manager via `letsencrypt-dns` ClusterIssuer (Let's Encrypt DNS-01 via Cloudflare API).
- OWASP security headers applied to all `websecure` traffic via `default-headers` Middleware.
- Services: SonarQube, Headlamp, Longhorn UI, ArgoCD.

Example route: `argocd.home.example-lab.org` -> gw-01 DNS -> MetalLB VIP (10.0.20.220) -> K8s Traefik -> ArgoCD server.

### Internal: K3s Traefik Ingress Controller (RPi5)

- **Traefik v3** (Helm, deployed via `k3s-platform-deploy.yml`) handles routing for K3s monitoring workloads.
- Receives MetalLB LoadBalancer VIP at `10.0.20.200` (Services VLAN 20).
- 1 replica, pinned to `example-lab.org/ram-tier: standard` nodes (8GB).
- TLS certificates issued by cert-manager via `letsencrypt-dns` ClusterIssuer.
- Services: Grafana (monitoring stack).
- Loki receives a separate LoadBalancer VIP at `10.0.20.201` for direct log ingestion.

Example route: `grafana.home.example-lab.org` -> gw-01 DNS -> MetalLB VIP (10.0.20.200) -> K3s Traefik -> Grafana.

### Internal: Standalone Traefik Proxy (LXC)

- **Traefik v3** runs as a Docker container on `traefik-proxy` LXC (VM 5033, lab-04, Management VLAN 10, `10.0.10.17`).
- Handles TLS termination for ALL non-K8s services (`*.home.example-lab.org`) using Let's Encrypt DNS-01 via Cloudflare (`CF_DNS_API_TOKEN`).
- Authentik ForwardAuth middleware protects services without native OIDC (Ghost, Roundcube, FoundryVTT, Actual Budget, PBS).
- Lives on Management VLAN 10 for direct L2 access to management backends (GitLab, Authentik, PBS). Reaches Services VLAN 20 backends via inter-VLAN routing.
- Services: GitLab, Authentik, PBS, Ghost, Roundcube, FoundryVTT, Mealie, NetBox, PatchMon, Actual Budget.
- Managed by: Terraform Layer 05 (LXC provisioning) + Ansible role `traefik-standalone` (app deployment).

Example route: `gitlab.home.example-lab.org` -> gw-01 DNS -> Standalone Traefik (10.0.10.17) -> GitLab (10.0.10.50:80).

---

## DNS Architecture

| Scope | Provider | Location | Purpose |
|-------|----------|----------|---------|
| Internal lab (`*.home.example-lab.org`) | gw-01 built-in DNS | gw-01 | Resolves internal service hostnames for all VLAN DHCP clients. Managed via `unifi_dns_record` in Layer 00. |
| External (public domains) | AdGuard Home | Hetzner VPS | DNS filtering for external queries, upstream to Cloudflare |
| Cluster-internal | CoreDNS | RKE2 cluster | Service discovery within the Kubernetes cluster (*.svc.cluster.local) |
| Cluster-internal (`*.home.example-lab.org`) | CoreDNS (custom zone) | RKE2 cluster | Dedicated forward to gw-01 + Cloudflare, 300s cache. Prevents NXDOMAIN for internal hostnames inside pods. |
| Cluster-internal | CoreDNS | K3s cluster | Service discovery within K3s (*.svc.cluster.local) |
| Cluster-internal (`*.home.example-lab.org`) | CoreDNS (custom config) | K3s cluster | Forward to gw-01 (10.0.20.1). ConfigMap `coredns-custom` in kube-system namespace. Required for Grafana OIDC (auth.home.example-lab.org resolution). |
| Authoritative DNS | Cloudflare | Cloud | Public DNS records for `*.example-lab.org`, managed by Terraform via `modules/cloudflare-dns/` |

### Internal DNS (home.example-lab.org)

All internal services are accessible via `<service>.home.example-lab.org` hostnames. The gw-01's built-in DNS forwarder serves these records to all DHCP clients on every VLAN — no separate DNS server needed.

DNS records are managed as `unifi_dns_record` resources in `terraform/layers/00-network/dns.tf`:

- **RKE2 K8s workloads** → RKE2 Traefik MetalLB VIP (`10.0.20.220`). cert-manager issues TLS via `letsencrypt-dns` ClusterIssuer.
- **K3s workloads** → K3s Traefik MetalLB VIP (`10.0.20.200`). cert-manager issues TLS via `letsencrypt-dns` ClusterIssuer.
- **Standalone + management services** → Standalone Traefik proxy (`10.0.10.17`). Traefik issues TLS via Let's Encrypt DNS-01 (Cloudflare).
- **Direct access** → own IPs (Vault, Proxmox nodes). Own TLS, no proxy needed.

| Hostname | Target | Proxy | Backend |
|----------|--------|-------|---------|
| sonarqube.home.example-lab.org | 10.0.20.220 | K8s Traefik | K8s workload |
| grafana.home.example-lab.org | 10.0.20.200 | K3s Traefik | K3s monitoring (migrated from RKE2) |
| headlamp.home.example-lab.org | 10.0.20.220 | K8s Traefik | K8s platform |
| longhorn.home.example-lab.org | 10.0.20.220 | K8s Traefik | K8s platform (ForwardAuth) |
| argocd.home.example-lab.org | 10.0.20.220 | K8s Traefik | K8s platform (OIDC) |
| gitlab.home.example-lab.org | 10.0.10.17 | Standalone Traefik | GitLab (10.0.10.50:80) |
| git.home.example-lab.org | 10.0.10.17 | Standalone Traefik | GitLab alias |
| auth.home.example-lab.org | 10.0.10.17 | Standalone Traefik | Authentik (10.0.10.16:9000) |
| pbs.home.example-lab.org | 10.0.10.17 | Standalone Traefik | PBS (10.0.10.15:8007, ForwardAuth) |
| ghost.home.example-lab.org | 10.0.10.17 | Standalone Traefik | Ghost LXC (10.0.20.10:2368, ForwardAuth) |
| mail.home.example-lab.org | 10.0.10.17 | Standalone Traefik | Roundcube LXC (10.0.20.11:8080, ForwardAuth) |
| foundryvtt.home.example-lab.org | 10.0.10.17 | Standalone Traefik | FoundryVTT VM (10.0.20.12:30000, ForwardAuth) |
| mealie.home.example-lab.org | 10.0.10.17 | Standalone Traefik | Mealie LXC (10.0.20.13:9000) |
| netbox.home.example-lab.org | 10.0.10.17 | Standalone Traefik | NetBox VM (10.0.20.14:8080) |
| patchmon.home.example-lab.org | 10.0.10.17 | Standalone Traefik | PatchMon VM (10.0.20.15:3000) |
| actualbudget.home.example-lab.org | 10.0.10.17 | Standalone Traefik | Actual Budget LXC (10.0.20.16:5006, ForwardAuth) |
| vault.home.example-lab.org | 10.0.10.10 | — | Direct (own CA TLS) |
| pve-01.home.example-lab.org | 10.0.10.42 | — | Direct (self-signed) |
| pve-02.home.example-lab.org | 10.0.10.2 | — | Direct (self-signed) |
| pve-03.home.example-lab.org | 10.0.10.3 | — | Direct (self-signed) |
| pve-04.home.example-lab.org | 10.0.10.4 | — | Direct (self-signed) |

### TLS Certificates

| Scope | Issuer | Method | Managed By |
|-------|--------|--------|------------|
| Internal user-facing (`*.home.example-lab.org`) | Let's Encrypt | DNS-01 via Cloudflare API | cert-manager `letsencrypt-dns` ClusterIssuer |
| External public (`*.example-lab.org`) | Let's Encrypt | HTTP-01 | Hetzner Traefik ACME |
| Machine-to-machine (ESO, cert-manager internal) | Vault PKI | Kubernetes auth | cert-manager `vault-issuer` ClusterIssuer |

Each VLAN's DHCP hands out the gw-01 gateway IP as the primary DNS server (e.g., `10.0.10.1` for Management VLAN), with `1.1.1.1` as fallback. gw-01 resolves `*.home.example-lab.org` locally and forwards all other queries upstream. Configurable per VLAN via Terraform variables (`management_dns_servers`, `services_dns_servers`, etc.).

**Note:** The Default LAN (VLAN 1) is not managed by Terraform due to a provider deserialization bug. Its DHCP DNS must be set manually in the UniFi UI to `10.0.4.1` (gw-01 gateway). This is a known IaC gap.

### Kubernetes CoreDNS Custom Zones

K8s pods don't see `/etc/hosts` entries — they rely exclusively on CoreDNS for name resolution. The default CoreDNS Corefile forwards all non-cluster queries to `/etc/resolv.conf` with a 30-second cache, which can cause intermittent NXDOMAIN for `*.home.example-lab.org` when gw-01 is slow to respond (breaking OIDC token exchange, Git sync, etc.).

A `HelmChartConfig` resource (`rke2-coredns-config.yaml`) deployed to `/var/lib/rancher/rke2/server/manifests/` adds a dedicated CoreDNS server block for `home.example-lab.org`:

| Setting | Value |
|---------|-------|
| Cache TTL | 300 seconds (vs. 30s default) |
| Primary upstream | `10.0.20.1` (gw-01 Services VLAN gateway) |
| Fallback upstream | `1.1.1.1` (Cloudflare, authoritative for `example-lab.org`) |
| Forward policy | `sequential` (primary first, fallback on failure) |
| Managed by | Ansible `rke2` role (`rke2-coredns-config.yaml.j2` template) |
| Configurable via | `rke2_coredns_custom_zones` in `group_vars/rke2_cluster.yml` |

The RKE2 embedded Helm controller reconciles the HelmChartConfig against the `rke2-coredns` HelmChart. CoreDNS hot-reloads the new Corefile within ~30 seconds via its `reload` plugin (no pod restart required).

---

## Infrastructure-as-Code Management

### Terraform Provider

Network configuration is split between Terraform (primary) and Ansible (provider gap-filling). The `filipowm/unifi` Terraform provider manages most resources. An Ansible role handles settings the provider cannot manage due to missing attributes or bugs.

| Property | Value |
|----------|-------|
| Provider source | `filipowm/unifi` |
| Version constraint | `~> 1.0.0` |
| Authentication | API key (recommended for v9.0.108+), or username/password fallback |
| TLS | `allow_insecure = true` (self-signed cert on gw-01) |

### Managed Resources

The following UniFi resources are declared in `terraform/layers/00-network/`:

- **`unifi_network`** -- VLAN definitions (ID, subnet, DHCP range, DNS servers) — `main.tf`
- **`unifi_firewall_zone`** -- Firewall zones grouping networks by security posture — `main.tf`
- **`unifi_firewall_zone_policy`** -- Zone-to-zone traffic policies (ALLOW/BLOCK with port group filtering) — `main.tf`
- **`unifi_firewall_group`** -- Port groups referenced by zone policies (Vault API, GitLab, Wazuh, NFS, iSCSI) — `main.tf`
- **`unifi_port_profile`** -- Switch port profiles (Proxmox Trunk, Management Access, Services Access, Storage Access) — `main.tf`
- **`unifi_dns_record`** -- Internal DNS records for `*.home.example-lab.org` (served by gw-01 to all DHCP clients) — `dns.tf`
- **`unifi_device`** -- Physical switch adoption and port-to-profile assignments — `devices.tf`
- **`unifi_setting_ips`** -- IDS/IPS mode, per-VLAN enablement, threat categories — `security.tf`
- **`unifi_setting_dpi`** -- Deep Packet Inspection (application identification) — `security.tf`
- **`unifi_setting_ssl_inspection`** -- SSL inspection mode (kept off) — `security.tf`
- **`unifi_wlan`** -- WiFi SSIDs (IoT: "Fellowship of the Ping") — `wifi.tf`

### Ansible-Managed Settings (Provider Gaps)

The following settings are managed by the `unifi-config` Ansible role, triggered from Terraform via `terraform_data` + `local-exec` in `ansible.tf`. These are settings the filipowm/unifi provider cannot handle.

| Setting | Reason | Ansible Task | Status |
|---------|--------|--------------|--------|
| STP bridge priority per switch | No `stp_priority` attribute on `unifi_device` | `stp.yml` | Active |
| DNS content filters | Provider bug: Read returns `[]`, causes state drift | `dns_filters.yml` | Planned (Phase 2) |
| Ad blocking per network | Provider bug: Read returns `[]`, sensitive mismatch | `ad_blocking.yml` | Planned (Phase 2) |
| Region/country blocking | No provider resource | -- | UI-only (documented) |

Full gap inventory: `ansible/roles/unifi-config/defaults/main.yml`

### Layer 00 File Layout

```
terraform/layers/00-network/
    main.tf                   # VLANs, firewall zones, zone policies, port profiles
    dns.tf                    # Internal DNS records (*.home.example-lab.org)
    devices.tf                # Switch device resources and port override assignments
    security.tf               # IDS/IPS, DPI, SSL inspection settings
    wifi.tf                   # WiFi SSID definitions
    ansible.tf                # terraform_data triggers for Ansible gap-filling
    variables.tf              # UniFi credentials, per-VLAN DNS, switch MACs, STP priorities
    outputs.tf                # VLAN IDs, network IDs, subnets, port profile IDs, device IDs
    providers.tf              # Provider config (filipowm/unifi + hashicorp/vault)
    terraform.tfvars.example  # Template with placeholder credentials
```

### Outputs

Layer 00 exports the following outputs for use by downstream layers:

| Output | Description |
|--------|-------------|
| `vlan_ids` | Map of VLAN name to VLAN ID (e.g., `management = 10`) |
| `network_ids` | Map of VLAN name to UniFi network resource ID |
| `subnets` | Map of VLAN name to CIDR (e.g., `services = "10.0.20.0/24"`) |
| `port_profile_ids` | Map of port profile name to UniFi resource ID |
| `device_ids` | Map of switch name to UniFi device resource ID |

### Applying Network Changes

```bash
cd terraform/layers/00-network
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with real gw-01 credentials

terraform init
terraform plan
terraform apply
```

**IMPORTANT:** Always run `terraform apply` for Layer 00 from a **wired** connection to gw-01. Applying network or WiFi changes over a wireless connection will drop the connection mid-apply, potentially leaving the configuration in a partially applied state. If this happens, re-run `terraform apply` from a wired connection to converge to the desired state.

### Post-Bootstrap

After Vault is operational (Layer 02), UniFi credentials should be migrated from the `.tfvars` file to Vault at `secret/unifi/api`. The provider configuration can then source credentials from Vault:

```hcl
data "vault_generic_secret" "unifi" {
  path = "secret/unifi/api"
}

provider "unifi" {
  username       = data.vault_generic_secret.unifi.data["username"]
  password       = data.vault_generic_secret.unifi.data["password"]
  api_url        = data.vault_generic_secret.unifi.data["url"]
  allow_insecure = true
}
```

---

## Operational Notes

### Adding a New VLAN

1. Add a `unifi_network` resource in `terraform/layers/00-network/main.tf`.
2. Add a `unifi_firewall_zone` resource and assign the new network to it.
3. Add `unifi_firewall_zone_policy` resources for allowed/blocked traffic to/from the new zone.
4. Add a DNS variable in `variables.tf` if the VLAN needs custom DNS servers.
4. Add the VLAN to the `outputs.tf` maps.
5. Run `terraform plan` and `terraform apply` from a wired connection.
6. If Proxmox VMs/LXCs need access to the new VLAN, no bridge changes are needed -- the VLAN-aware bridge on `vmbr0` handles any VLAN tag automatically.

### Adding a New Host to a VLAN

1. Assign the host a static IP outside the DHCP range (below .100).
2. Update the static IP assignments table in this document.
3. If the host is a Proxmox VM or LXC, set the VLAN tag in its network configuration.
4. If the host is a physical device, assign its UniFi switch port to the appropriate port profile via Terraform.

### Troubleshooting Connectivity

- **Cannot reach a host across VLANs:** Check the firewall rules table above. Most cross-VLAN traffic is blocked by default. Verify the source VLAN is allowed to reach the destination VLAN and port.
- **DHCP not working on a VLAN:** Confirm the VLAN is defined in `main.tf` with `dhcp_enabled = true`. Check that the host's switch port has the correct port profile or VLAN tag.
- **Terraform apply fails with connection error:** Ensure you are on a wired connection. Verify the gw-01 API URL and credentials in `terraform.tfvars`.
- **WireGuard tunnel down:** Check the WireGuard LXC on DMZ VLAN (30). Verify the Hetzner endpoint is reachable (`ping <hetzner-public-ip>`). Check WireGuard logs on both sides (`wg show`).
- **MetalLB IPs unreachable:** Verify the requesting host is on the Services VLAN (20) or Management VLAN (10). MetalLB L2 advertisements are only visible on the local broadcast domain (Services VLAN).

### Firewall Rule Index Allocation

| Range | Purpose |
|-------|---------|
| 2000-2009 | Management VLAN allow rules |
| 2010-2019 | Services-to-Storage allow rules |
| 2020-2029 | Services-to-Security allow rules |
| 2030-2039 | DMZ-to-Services allow rules |
| 2040-2099 | (Reserved for future allow rules) |
| 3000-3099 | Explicit block rules between VLANs |
| 3100-3199 | Default LAN isolation rules |

### Related Documentation

- **Architecture overview:** `docs/ARCHITECTURE.md`
- **Security design (Vault, hardening, certificates):** `docs/SECURITY.md`
- **Deployment procedures:** `docs/DEPLOYMENT.md`
- **Proxmox bootstrap playbook:** `ansible/playbooks/proxmox-bootstrap.yml`
- **WireGuard deployment playbook:** `ansible/playbooks/wireguard-deploy.yml`
- **Layer 00 Terraform config:** `terraform/layers/00-network/`
- **Layer 06 Hetzner config:** `terraform/layers/06-hetzner/`
- **MetalLB config (RKE2):** `k8s/platform/metallb/helm/values.yaml`
- **MetalLB config (K3s):** `k8s/k3s-platform/metallb/config.yaml`
