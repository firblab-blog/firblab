#!/usr/bin/env python3
# =============================================================================
# NetBox Seed Script — FirbLab Physical Infrastructure
# =============================================================================
# Populates a fresh NetBox instance with FirbLab PHYSICAL infrastructure:
# sites, racks, manufacturers, device types, device roles, devices, VLANs,
# prefixes, IP addresses (physical only), device interfaces, and cables.
#
# Virtual machines (VMs/LXCs), clusters, VM interfaces, and VM IP addresses
# are managed by Terraform Layer 08-netbox-config. Do NOT add VM records here.
#
# Exception: vault-2 (Layer 02-vault-infra) is seeded here because Layer 08
# only covers Layers 03-06. vault-2 will move to Terraform in a future update.
#
# Idempotent: checks if each object exists before creating. Safe to re-run.
#
# Prerequisites:
#   pip install pynetbox
#
# Usage:
#   export NETBOX_URL=http://10.0.20.14:8080
#   export NETBOX_TOKEN=$(vault kv get -mount=secret -field=api_token services/netbox)
#   python scripts/netbox-seed.py
#
# Data source: docs/CURRENT-STATE.md (authoritative inventory)
# =============================================================================

import os
import sys

try:
    import pynetbox
except ImportError:
    print("ERROR: pynetbox not installed. Run: pip install pynetbox")
    sys.exit(1)


def get_or_create(endpoint, search_params, create_params=None):
    """Get existing object or create new one. Returns the object."""
    results = list(endpoint.filter(**search_params))
    if results:
        return results[0]
    params = create_params or search_params
    return endpoint.create(params)


def main():
    url = os.environ.get("NETBOX_URL")
    token = os.environ.get("NETBOX_TOKEN")

    if not url or not token:
        print("ERROR: Set NETBOX_URL and NETBOX_TOKEN environment variables")
        sys.exit(1)

    nb = pynetbox.api(url, token=token)

    print("Seeding NetBox with FirbLab infrastructure data...")
    print(f"  URL: {url}")
    print()

    # =========================================================================
    # Site
    # =========================================================================
    print("[1/11] Creating site...")
    site = get_or_create(nb.dcim.sites, {"name": "FirbLab"}, {
        "name": "FirbLab",
        "slug": "firblab",
        "description": "Home laboratory — multi-node Proxmox cluster with Kubernetes",
        "status": "active",
    })
    print(f"  Site: {site.name} (id={site.id})")

    # =========================================================================
    # Racks
    # =========================================================================
    print("[2/11] Creating racks...")
    rack_closet = get_or_create(nb.dcim.racks, {"name": "Closet Rack"}, {
        "name": "Closet Rack",
        "site": site.id,
        "status": "active",
        "u_height": 12,
        "description": "Network closet — USW Flex 2.5G 5-port, Proxmox nodes, TrueNAS",
    })
    rack_minilab = get_or_create(nb.dcim.racks, {"name": "Minilab Shelf"}, {
        "name": "Minilab Shelf",
        "site": site.id,
        "status": "active",
        "u_height": 6,
        "description": "Desk shelf — switch-02, Mac Mini, RPi5, lab-02/03",
    })
    print(f"  Racks: {rack_closet.name}, {rack_minilab.name}")

    # =========================================================================
    # Manufacturers
    # =========================================================================
    print("[3/11] Creating manufacturers...")
    manufacturers = {}
    for name, slug in [
        ("Ubiquiti", "ubiquiti"),
        ("Intel", "intel"),
        ("Dell", "dell"),
        ("GMKtec", "gmktec"),
        ("Apple", "apple"),
        ("Raspberry Pi Foundation", "raspberry-pi"),
        ("Custom Build", "custom-build"),
        ("ZimaBlade", "zimablade"),
    ]:
        manufacturers[slug] = get_or_create(
            nb.dcim.manufacturers,
            {"name": name},
            {"name": name, "slug": slug},
        )
    print(f"  Manufacturers: {len(manufacturers)}")

    # =========================================================================
    # Device Roles
    # =========================================================================
    print("[4/11] Creating device roles...")
    roles = {}
    for name, slug, color in [
        ("Router", "router", "ff5722"),
        ("Switch", "switch", "2196f3"),
        ("Server (Proxmox)", "server-proxmox", "4caf50"),
        ("Storage", "storage", "ff9800"),
        ("Vault Node", "vault-node", "9c27b0"),
        ("Compute", "compute", "607d8b"),
        ("KVM", "kvm", "795548"),
        ("Archive Appliance", "archive-appliance", "8d6e63"),
        ("IoT", "iot", "e91e63"),
    ]:
        roles[slug] = get_or_create(
            nb.dcim.device_roles,
            {"name": name},
            {"name": name, "slug": slug, "color": color, "vm_role": False},
        )
    print(f"  Device roles: {len(roles)}")

    # =========================================================================
    # Device Types
    # =========================================================================
    print("[5/11] Creating device types...")
    device_types = {}
    type_defs = [
        ("UDM Pro", "ubiquiti", "udm-pro", 1),
        ("USW Flex 2.5G 5", "ubiquiti", "usw-flex-2-5g-5", 1),
        ("USW Flex 2.5G 8", "ubiquiti", "usw-flex-2-5g-8", 1),
        ("Custom i9-12900K Server", "custom-build", "custom-i9-12900k", 2),
        ("Intel N100 Mini PC", "intel", "intel-n100-mini", 1),
        ("GMK Mini PC", "gmktec", "gmk-mini-pc", 1),
        ("Dell Wyse J5005", "dell", "dell-wyse-j5005", 1),
        ("Mac Mini M4", "apple", "mac-mini-m4", 1),
        ("RPi5 CM5", "raspberry-pi", "rpi5-cm5", 1),
        ("Custom i5-9500 Server", "custom-build", "custom-i5-9500", 2),
        ("JetKVM", "custom-build", "jetkvm", 1),
        ("Raspberry Pi 4", "raspberry-pi", "rpi4", 1),
        ("Raspberry Pi 5", "raspberry-pi", "rpi5", 1),
        ("ZimaBlade 7700", "zimablade", "zimablade-7700", 1),
    ]
    for name, mfr_slug, slug, u_height in type_defs:
        device_types[slug] = get_or_create(
            nb.dcim.device_types,
            {"slug": slug},
            {
                "manufacturer": manufacturers[mfr_slug].id,
                "model": name,
                "slug": slug,
                "u_height": u_height,
            },
        )
    print(f"  Device types: {len(device_types)}")

    # =========================================================================
    # Devices
    # =========================================================================
    print("[6/11] Creating devices...")
    devices = {}
    device_defs = [
        # (name, type_slug, role_slug, rack, ip, status)
        ("gw-01", "udm-pro", "router", rack_closet, "10.0.4.1", "active"),
        ("switch-01", "usw-flex-2-5g-5", "switch", rack_closet, None, "active"),
        ("switch-02", "usw-flex-2-5g-8", "switch", rack_minilab, None, "active"),
        ("switch-03", "usw-flex-2-5g-5", "switch", rack_closet, None, "active"),
        ("lab-01", "custom-i9-12900k", "server-proxmox", rack_closet, "10.0.10.42", "active"),
        ("lab-02", "intel-n100-mini", "server-proxmox", rack_minilab, "10.0.10.2", "active"),
        ("lab-03", "gmk-mini-pc", "server-proxmox", rack_minilab, "10.0.10.3", "active"),
        ("lab-04", "dell-wyse-j5005", "server-proxmox", rack_closet, "10.0.10.4", "active"),
        ("vault-1 (Mac Mini)", "mac-mini-m4", "vault-node", rack_minilab, "10.0.10.10", "active"),
        ("vault-3 (RPi5)", "rpi5-cm5", "vault-node", rack_minilab, "10.0.10.13", "active"),
        ("TrueNAS", "custom-i5-9500", "storage", rack_closet, "10.0.40.2", "active"),
        ("JetKVM", "jetkvm", "kvm", rack_minilab, None, "active"),
        ("lab-08", "rpi4", "compute", rack_closet, "10.0.4.20", "active"),
        ("lab-09", "zimablade-7700", "archive-appliance", rack_closet, "10.0.20.20", "active"),
        ("lab-06", "rpi5", "iot", rack_closet, "10.0.60.10", "active"),
    ]
    for name, type_slug, role_slug, rack, ip, status in device_defs:
        devices[name] = get_or_create(
            nb.dcim.devices,
            {"name": name},
            {
                "name": name,
                "device_type": device_types[type_slug].id,
                "role": roles[role_slug].id,
                "site": site.id,
                "rack": rack.id,
                "status": status,
            },
        )
    print(f"  Devices: {len(devices)}")

    # =========================================================================
    # VLAN Group & VLANs
    # =========================================================================
    print("[7/11] Creating VLANs...")
    vlan_group = get_or_create(nb.ipam.vlan_groups, {"name": "FirbLab"}, {
        "name": "FirbLab",
        "slug": "firblab",
        "scope_type": "dcim.site",
        "scope_id": site.id,
    })

    vlans = {}
    vlan_defs = [
        (1, "Default/LAN", "default-lan", "active"),
        (10, "Management", "management", "active"),
        (20, "Services", "services", "active"),
        (30, "DMZ", "dmz", "active"),
        (40, "Storage", "storage", "active"),
        (50, "Security", "security", "active"),
        (60, "IoT", "iot", "active"),
    ]
    for vid, name, slug, status in vlan_defs:
        vlans[vid] = get_or_create(
            nb.ipam.vlans,
            {"vid": vid, "group_id": vlan_group.id},
            {
                "vid": vid,
                "name": name,
                "slug": slug,
                "group": vlan_group.id,
                "site": site.id,
                "status": status,
            },
        )
    print(f"  VLANs: {len(vlans)}")

    # =========================================================================
    # Prefixes
    # =========================================================================
    print("[8/11] Creating prefixes...")
    prefix_defs = [
        ("10.0.4.0/24", 1, "Default/LAN network"),
        ("10.0.10.0/24", 10, "Management network — Proxmox, Vault, GitLab"),
        ("10.0.20.0/24", 20, "Services network — RKE2, standalone services, MetalLB .220-.250"),
        ("10.0.30.0/24", 30, "DMZ network — WireGuard gateway"),
        ("10.0.40.0/24", 40, "Storage network — TrueNAS (10.0.40.2)"),
        ("10.0.50.0/24", 50, "Security network — vault-2"),
        ("10.0.60.0/24", 60, "IoT network — Home Assistant (lab-06)"),
    ]
    for prefix, vlan_id, desc in prefix_defs:
        get_or_create(
            nb.ipam.prefixes,
            {"prefix": prefix},
            {
                "prefix": prefix,
                "vlan": vlans[vlan_id].id,
                "site": site.id,
                "status": "active",
                "description": desc,
            },
        )
    print(f"  Prefixes: {len(prefix_defs)}")

    # =========================================================================
    # IP Addresses (Physical Devices + vault-2)
    # =========================================================================
    # VM/LXC IP addresses are managed by Terraform Layer 08-netbox-config.
    # Only physical device IPs and vault-2 (Layer 02, not yet in Terraform)
    # are seeded here.
    # =========================================================================
    print("[9/11] Creating IP addresses...")
    ip_defs = [
        # (address, description, device_name)
        ("10.0.4.1/24", "gw-01 — router gateway", "gw-01"),
        ("10.0.40.2/24", "TrueNAS (Storage VLAN 40)", "TrueNAS"),
        ("10.0.10.42/24", "lab-01 — main Proxmox node", "lab-01"),
        ("10.0.10.2/24", "lab-02 — pilot Proxmox node", "lab-02"),
        ("10.0.10.3/24", "lab-03 — lightweight services Proxmox", "lab-03"),
        ("10.0.10.4/24", "lab-04 — lightweight compute Proxmox", "lab-04"),
        ("10.0.10.10/24", "vault-1 — Mac Mini M4 (Vault primary)", "vault-1 (Mac Mini)"),
        ("10.0.10.13/24", "vault-3 — RPi5 CM5 (Vault standby)", "vault-3 (RPi5)"),
        ("10.0.4.20/24", "lab-08 — RPi4 Scanopy + NUT (bare metal)", "lab-08"),
        ("10.0.20.20/24", "lab-09 — ZimaBlade archive appliance (bare metal)", "lab-09"),
        ("10.0.60.10/24", "lab-06 — HAOS RPi5 (Home Assistant)", "lab-06"),
        # vault-2 — Layer 02-vault-infra, not yet managed by Terraform Layer 08
        ("10.0.50.2/24", "vault-2 — Proxmox VM on lab-02 (Security VLAN 50)", None),
        # MetalLB VIP — not a VM, infrastructure IP
        ("10.0.20.220/24", "Traefik — MetalLB LoadBalancer VIP", None),
    ]

    ip_objects = {}
    for address, desc, device_name in ip_defs:
        ip = get_or_create(
            nb.ipam.ip_addresses,
            {"address": address},
            {
                "address": address,
                "status": "active",
                "description": desc,
            },
        )
        ip_objects[address] = ip
    print(f"  IP addresses: {len(ip_defs)}")

    # =========================================================================
    # vault-2 Virtual Machine (Layer 02 — not yet in Terraform Layer 08)
    # =========================================================================
    # Clusters, VMs, VM interfaces, and VM IPs for Layers 03-06 are managed
    # by Terraform Layer 08-netbox-config. vault-2 (Layer 02-vault-infra)
    # is the only VM still seeded here.
    # =========================================================================
    print("[10/11] Creating vault-2 VM...")

    # Look up the Proxmox cluster (created by Terraform Layer 08)
    proxmox_clusters = list(nb.virtualization.clusters.filter(name="firblab-cluster"))
    if proxmox_clusters:
        cluster = proxmox_clusters[0]
        get_or_create(
            nb.virtualization.virtual_machines,
            {"name": "vault-2"},
            {
                "name": "vault-2",
                "cluster": cluster.id,
                "site": site.id,
                "vcpus": 2,
                "memory": 4096,
                "disk": 40000,
                "status": "active",
                "description": "Vault standby — Rocky Linux 9, Security VLAN 50 (Layer 02-vault-infra)",
            },
        )
        print(f"  vault-2 created (cluster: {cluster.name})")
    else:
        print("  SKIP vault-2 — firblab-cluster not found (run Terraform Layer 08 first)")

    # =========================================================================
    # Device Interfaces
    # =========================================================================
    # Create physical interfaces on devices and assign IP addresses to them.
    # This enables topology views (cables connect interfaces) and proper IP
    # assignment (IPs belong to interfaces, not directly to devices).
    # =========================================================================
    print("[11/11] Creating device interfaces, cables, and assigning IPs...")

    interfaces = {}
    iface_count = 0

    # --- Switch interfaces (numbered ports) ---
    switch_iface_defs = [
        # (device_name, iface_name, iface_type, description)
        # switch-01 (closet, USW Flex 2.5G 5) — 5-port
        ("switch-01", "Port 1", "1000base-t", "lab-01 (i9-12900K)"),
        ("switch-01", "Port 2", "1000base-t", "TrueNAS"),
        ("switch-01", "Port 3", "1000base-t", "lab-04 (Dell Wyse)"),
        ("switch-01", "Port 4", "1000base-t", "lab-08 (RPi4 Scanopy)"),
        ("switch-01", "Port 5", "1000base-t", "Uplink → gw-01 Port 8"),
        # switch-02 (minilab, USW Flex 2.5G 8) — 10-port
        ("switch-02", "Port 1", "2.5gbase-t", "lab-03 (N100 12GB)"),
        ("switch-02", "Port 2", "2.5gbase-t", "JetKVM"),
        ("switch-02", "Port 3", "2.5gbase-t", "vault-1 (Mac Mini M4)"),
        ("switch-02", "Port 4", "2.5gbase-t", "lab-02 (N100 16GB)"),
        ("switch-02", "Port 5", "2.5gbase-t", "vault-3 (RPi5 CM5)"),
        ("switch-02", "Port 9", "2.5gbase-t", "Uplink → gw-01 Port 7"),
        # switch-03 (rackmate, USW Flex 2.5G 5) — 5-port
        ("switch-03", "Port 2", "1000base-t", "lab-06 (HAOS RPi5 — Home Assistant)"),
        ("switch-03", "Port 4", "1000base-t", "lab-09 (ZimaBlade archive)"),
        ("switch-03", "Port 5", "1000base-t", "Uplink → gw-01 Port 5"),
        # gw-01 — relevant LAN ports
        ("gw-01", "Port 5", "1000base-t", "Rackmate switch uplink"),
        ("gw-01", "Port 7", "1000base-t", "Minilab switch uplink"),
        ("gw-01", "Port 8", "1000base-t", "Closet switch uplink"),
    ]

    for dev_name, iface_name, iface_type, desc in switch_iface_defs:
        device = devices.get(dev_name)
        if not device:
            continue
        key = f"{dev_name}:{iface_name}"
        iface = get_or_create(
            nb.dcim.interfaces,
            {"device_id": device.id, "name": iface_name},
            {
                "device": device.id,
                "name": iface_name,
                "type": iface_type,
                "description": desc,
            },
        )
        interfaces[key] = iface
        iface_count += 1

    # --- Device management interfaces (eth0/eno1) + IP assignment ---
    device_iface_defs = [
        # (device_name, iface_name, iface_type, ip_address, description)
        ("lab-01", "eno1", "1000base-t", "10.0.10.42/24", "Management — VLAN 10"),
        ("lab-02", "eno1", "2.5gbase-t", "10.0.10.2/24", "Management — VLAN 10"),
        ("lab-03", "eno1", "2.5gbase-t", "10.0.10.3/24", "Management — VLAN 10"),
        ("lab-04", "eno1", "1000base-t", "10.0.10.4/24", "Management — VLAN 10"),
        ("vault-1 (Mac Mini)", "en0", "2.5gbase-t", "10.0.10.10/24", "Management — VLAN 10"),
        ("vault-3 (RPi5)", "eth0", "2.5gbase-t", "10.0.10.13/24", "Management — VLAN 10"),
        ("TrueNAS", "eno1", "1000base-t", "10.0.40.2/24", "Storage — VLAN 40"),
        ("gw-01", "eth0", "1000base-t", "10.0.4.1/24", "Default LAN gateway"),
        ("lab-08", "eth0", "1000base-t", "10.0.4.20/24", "Default LAN — VLAN 1 (Scanner Trunk native)"),
        ("lab-09", "eth0", "1000base-t", "10.0.20.20/24", "Services VLAN 20 — archive appliance"),
        ("lab-06", "eth0", "1000base-t", "10.0.60.10/24", "IoT VLAN 60 — Home Assistant"),
    ]

    for dev_name, iface_name, iface_type, ip_addr, desc in device_iface_defs:
        device = devices.get(dev_name)
        if not device:
            continue
        key = f"{dev_name}:{iface_name}"
        iface = get_or_create(
            nb.dcim.interfaces,
            {"device_id": device.id, "name": iface_name},
            {
                "device": device.id,
                "name": iface_name,
                "type": iface_type,
                "description": desc,
            },
        )
        interfaces[key] = iface
        iface_count += 1

        # Assign IP to this interface (ensure correct assignment even on re-run)
        if ip_addr and ip_addr in ip_objects:
            ip_obj = ip_objects[ip_addr]
            if ip_obj.assigned_object_id != iface.id:
                # Clear primary_ip4 on any device referencing this IP first
                for d in nb.dcim.devices.all():
                    if d.primary_ip4 and d.primary_ip4.id == ip_obj.id:
                        d.primary_ip4 = None
                        d.save()
                ip_obj.assigned_object_type = "dcim.interface"
                ip_obj.assigned_object_id = iface.id
                ip_obj.save()

    # --- vault-2 VM interface + IP assignment ---
    # VM interfaces for Layers 03-06 are managed by Terraform Layer 08.
    # Only vault-2 (Layer 02) gets its interface seeded here.
    vault2_vms = list(nb.virtualization.virtual_machines.filter(name="vault-2"))
    if vault2_vms:
        vault2 = vault2_vms[0]
        vault2_iface = get_or_create(
            nb.virtualization.interfaces,
            {"virtual_machine_id": vault2.id, "name": "eth0"},
            {
                "virtual_machine": vault2.id,
                "name": "eth0",
                "description": "vault-2 primary interface",
            },
        )
        iface_count += 1

        # Assign vault-2 IP to its interface
        vault2_ip_addr = "10.0.50.2/24"
        if vault2_ip_addr in ip_objects:
            ip_obj = ip_objects[vault2_ip_addr]
            if ip_obj.assigned_object_id != vault2_iface.id:
                ip_obj.assigned_object_type = "virtualization.vminterface"
                ip_obj.assigned_object_id = vault2_iface.id
                ip_obj.save()

    print(f"  Interfaces: {iface_count}")

    # =========================================================================
    # Cables (Physical Connections)
    # =========================================================================
    # Cables connect device interfaces, enabling netbox-topology-views to
    # render the physical network topology. Source: docs/NETWORK.md switch
    # port assignments.
    # =========================================================================
    print("  Creating cables...")

    cable_count = 0
    cable_defs = [
        # (a_device:a_iface, b_device:b_iface, label, color)
        # switch-01 ↔ gw-01 uplink
        ("switch-01:Port 5", "gw-01:Port 8", "Closet uplink", "4caf50"),
        # switch-02 ↔ gw-01 uplink
        ("switch-02:Port 9", "gw-01:Port 7", "Minilab uplink", "4caf50"),
        # switch-03 ↔ gw-01 uplink
        ("switch-03:Port 5", "gw-01:Port 5", "Rackmate uplink", "4caf50"),
        # switch-01 → devices
        ("switch-01:Port 1", "lab-01:eno1", "lab-01", "2196f3"),
        ("switch-01:Port 2", "TrueNAS:eno1", "TrueNAS", "ff9800"),
        ("switch-01:Port 3", "lab-04:eno1", "lab-04", "2196f3"),
        ("switch-01:Port 4", "lab-08:eth0", "lab-08", "607d8b"),
        # switch-02 → devices
        ("switch-02:Port 1", "lab-03:eno1", "lab-03", "2196f3"),
        # Note: Port 2 (JetKVM) has no management interface — skip
        ("switch-02:Port 3", "vault-1 (Mac Mini):en0", "vault-1", "9c27b0"),
        ("switch-02:Port 4", "lab-02:eno1", "lab-02", "2196f3"),
        ("switch-02:Port 5", "vault-3 (RPi5):eth0", "vault-3", "9c27b0"),
        # switch-03 → devices
        ("switch-03:Port 2", "lab-06:eth0", "lab-06", "e91e63"),
        ("switch-03:Port 4", "lab-09:eth0", "lab-09", "8d6e63"),
    ]

    for a_key, b_key, label, color in cable_defs:
        a_iface = interfaces.get(a_key)
        b_iface = interfaces.get(b_key)
        if not a_iface or not b_iface:
            print(f"  SKIP   {label} — interface not found ({a_key} or {b_key})")
            continue

        # Check if cable already exists (either direction)
        existing = list(nb.dcim.cables.filter(interface_a_id=a_iface.id))
        existing += list(nb.dcim.cables.filter(interface_b_id=a_iface.id))
        if existing:
            cable_count += 1
            continue

        try:
            nb.dcim.cables.create({
                "a_terminations": [
                    {"object_type": "dcim.interface", "object_id": a_iface.id},
                ],
                "b_terminations": [
                    {"object_type": "dcim.interface", "object_id": b_iface.id},
                ],
                "status": "connected",
                "label": label,
                "color": color,
            })
            cable_count += 1
            print(f"  CABLE  {a_key} ↔ {b_key}")
        except Exception as e:
            # Cable may already exist — pynetbox filter doesn't always catch it
            if "already" in str(e).lower() or "occupied" in str(e).lower():
                cable_count += 1
            else:
                print(f"  ERROR  {label}: {e}")

    print(f"  Cables: {cable_count}")

    # =========================================================================
    # Assign primary IPs to devices
    # =========================================================================
    # Re-fetch IP objects — the local references are stale after interface
    # assignment via .save(). NetBox's primary_ip4 assignment requires the
    # IP to be currently assigned to an interface belonging to the target
    # device, so we need fresh objects.
    #
    # VM primary IPs (Layers 03-06) are managed by Terraform Layer 08
    # via netbox_primary_ip resources. Only physical devices and vault-2
    # are assigned here.
    # =========================================================================
    print("  Setting primary IPs on devices...")
    ip_objects = {}
    for ip in nb.ipam.ip_addresses.all():
        ip_objects[str(ip)] = ip

    primary_ip_map = [
        # (device_name, ip_address)
        ("gw-01", "10.0.4.1/24"),
        ("lab-01", "10.0.10.42/24"),
        ("lab-02", "10.0.10.2/24"),
        ("lab-03", "10.0.10.3/24"),
        ("lab-04", "10.0.10.4/24"),
        ("vault-1 (Mac Mini)", "10.0.10.10/24"),
        ("vault-3 (RPi5)", "10.0.10.13/24"),
        ("TrueNAS", "10.0.40.2/24"),
        ("lab-08", "10.0.4.20/24"),
        ("lab-09", "10.0.20.20/24"),
        ("lab-06", "10.0.60.10/24"),
    ]

    for dev_name, ip_addr in primary_ip_map:
        ip_obj = ip_objects.get(ip_addr)
        if not ip_obj:
            continue
        dev_results = list(nb.dcim.devices.filter(name=dev_name))
        if not dev_results:
            continue
        device = dev_results[0]
        if device.primary_ip4 and device.primary_ip4.id == ip_obj.id:
            continue
        device.primary_ip4 = ip_obj.id
        device.save()

    # Set primary IP on vault-2 (only seed-managed VM)
    vault2_ip_obj = ip_objects.get("10.0.50.2/24")
    if vault2_ip_obj:
        vault2_vms = list(nb.virtualization.virtual_machines.filter(name="vault-2"))
        if vault2_vms:
            vault2 = vault2_vms[0]
            if not (vault2.primary_ip4 and vault2.primary_ip4.id == vault2_ip_obj.id):
                ip_obj = nb.ipam.ip_addresses.get(vault2_ip_obj.id)
                if ip_obj.assigned_object_id:
                    vault2.primary_ip4 = ip_obj.id
                    vault2.save()

    print("  Primary IPs assigned")

    # =========================================================================
    # Summary
    # =========================================================================
    print()
    print("=" * 60)
    print("Seeding complete!")
    print("=" * 60)
    print(f"  Site:              1")
    print(f"  Racks:             2")
    print(f"  Manufacturers:     {len(manufacturers)}")
    print(f"  Device types:      {len(device_types)}")
    print(f"  Device roles:      {len(roles)}")
    print(f"  Physical devices:  {len(devices)}")
    print(f"  VLANs:             {len(vlans)}")
    print(f"  Prefixes:          {len(prefix_defs)}")
    print(f"  IP addresses:      {len(ip_defs)} (physical + vault-2)")
    print(f"  Virtual machines:  1 (vault-2 only — others via Terraform Layer 08)")
    print(f"  Interfaces:        {iface_count}")
    print(f"  Cables:            {cable_count}")
    print()
    print("Topology views should now render at:")
    print(f"  {url}/plugins/netbox_topology_views/")
    print()
    print("Next steps:")
    print("  1. Run Terraform Layer 08 to create VM records:")
    print("     cd terraform/layers/08-netbox-config && terraform init && terraform apply")
    print("  2. Verify topology views render correctly")
    print("  3. Run scanopy-netbox-sync.py to tag discovered hosts")
    print("  4. Run netbox-to-d2.py to generate architecture diagram")


if __name__ == "__main__":
    main()
