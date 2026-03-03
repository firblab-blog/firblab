#!/usr/bin/env python3
# =============================================================================
# NetBox → D2 Diagram Generator — FirbLab Infrastructure
# =============================================================================
# Queries the NetBox API and generates a D2 diagram-as-code file representing
# the full FirbLab network topology: physical devices, VMs, VLANs, cables,
# and inter-VLAN zone policies.
#
# The generated D2 file can be rendered to SVG by the existing CI pipeline
# (ci-templates/d2-ci.yml) or locally with:
#   d2 --theme 300 --layout elk docs/diagrams/network-topology.d2 output.svg
#
# Prerequisites:
#   pip install pynetbox
#
# Usage:
#   export NETBOX_URL=http://10.0.20.14:8080
#   export NETBOX_TOKEN=$(vault kv get -mount=secret -field=api_token services/netbox)
#   python scripts/netbox-to-d2.py
#
# Output:
#   docs/diagrams/network-topology.d2 (overwrites existing hand-maintained file)
#
# Data flow:
#   NetBox API (devices, VMs, VLANs, IPs, cables) → this script → D2 file → CI → SVG
# =============================================================================

import os
import sys
from collections import defaultdict
from datetime import datetime, timezone

try:
    import pynetbox
except ImportError:
    print("ERROR: pynetbox not installed. Run: pip install pynetbox")
    sys.exit(1)


# =============================================================================
# D2 Style Configuration
# =============================================================================

VLAN_COLORS = {
    1: "#f5f5f5",    # Default/LAN — light gray
    10: "#e3f2fd",   # Management — light blue
    20: "#fff3e0",   # Services — light orange
    30: "#fce4ec",   # DMZ — light red/pink
    40: "#f3e5f5",   # Storage — light purple
    50: "#fff9c4",   # Security — light yellow
    60: "#e8f5e9",   # IoT — light green
}

ROLE_ICONS = {
    "router": "🔀",
    "switch": "🔌",
    "server-proxmox": "🖥️",
    "storage": "💾",
    "vault-node": "🔐",
    "compute": "⚙️",
    "kvm": "🖲️",
    "cloud-server": "☁️",
    "discovered": "❓",
}

OUTPUT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "docs", "diagrams", "network-topology.d2",
)


# =============================================================================
# Helpers
# =============================================================================

def slugify(name):
    """Convert a name to a valid D2 identifier."""
    return (
        name.lower()
        .replace(" ", "-")
        .replace("(", "")
        .replace(")", "")
        .replace("/", "-")
        .replace(".", "-")
        .replace(",", "")
    )


def ip_to_vlan(ip_str, prefixes_by_vlan):
    """Determine which VLAN an IP belongs to by matching prefixes."""
    import ipaddress

    try:
        addr = ipaddress.ip_address(ip_str.split("/")[0])
    except ValueError:
        return None

    for vlan_id, prefix_str in prefixes_by_vlan.items():
        try:
            net = ipaddress.ip_network(prefix_str, strict=False)
            if addr in net:
                return vlan_id
        except ValueError:
            continue

    return None


def get_primary_ip(obj):
    """Extract primary IPv4 string from a device or VM object."""
    if obj.primary_ip4:
        return str(obj.primary_ip4).split("/")[0]
    return None


def get_device_label(device):
    """Build a human-readable label for a device."""
    ip = get_primary_ip(device)
    parts = [device.name]
    if ip:
        parts.append(ip)
    # Only add device type if it differs from the device name (avoids
    # duplicate labels like "USW Flex 2.5G 8\nUSW Flex 2.5G 8")
    if device.device_type and str(device.device_type) != device.name:
        parts.append(str(device.device_type))
    return "\\n".join(parts)


def get_vm_label(vm):
    """Build a human-readable label for a VM."""
    ip = get_primary_ip(vm)
    parts = [vm.name]
    if ip:
        parts.append(ip)
    desc = vm.description or ""
    # Extract short role from description (e.g., "Ghost blog — LXC on lab-03")
    if "—" in desc:
        role_part = desc.split("—")[0].strip()
        if role_part != vm.name:
            parts.append(role_part)
    return "\\n".join(parts)


# =============================================================================
# Data Fetching
# =============================================================================

def fetch_all_data(nb):
    """Fetch all relevant data from NetBox API."""
    print("  Fetching devices...")
    devices = list(nb.dcim.devices.all())
    print(f"    {len(devices)} devices")

    print("  Fetching VMs...")
    vms = list(nb.virtualization.virtual_machines.all())
    print(f"    {len(vms)} VMs")

    print("  Fetching VLANs...")
    vlans = list(nb.ipam.vlans.all())
    print(f"    {len(vlans)} VLANs")

    print("  Fetching prefixes...")
    prefixes = list(nb.ipam.prefixes.all())
    print(f"    {len(prefixes)} prefixes")

    print("  Fetching IP addresses...")
    ips = list(nb.ipam.ip_addresses.all())
    print(f"    {len(ips)} IPs")

    print("  Fetching cables...")
    cables = list(nb.dcim.cables.all())
    print(f"    {len(cables)} cables")

    print("  Fetching clusters...")
    clusters = list(nb.virtualization.clusters.all())
    print(f"    {len(clusters)} clusters")

    return {
        "devices": devices,
        "vms": vms,
        "vlans": vlans,
        "prefixes": prefixes,
        "ips": ips,
        "cables": cables,
        "clusters": clusters,
    }


# =============================================================================
# D2 Generation
# =============================================================================

def generate_d2(data):
    """Generate D2 diagram source from NetBox data."""
    lines = []

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    lines.append("# FirbLab Network Topology")
    lines.append(f"# Auto-generated from NetBox by scripts/netbox-to-d2.py")
    lines.append(f"# Last generated: {timestamp}")
    lines.append("# Rendered automatically by CI pipeline (ci-templates/d2-ci.yml)")
    lines.append("")
    lines.append("direction: down")
    lines.append("")

    # --- Build prefix → VLAN lookup ---
    prefixes_by_vlan = {}
    vlan_names = {}
    for vlan in data["vlans"]:
        vlan_names[vlan.vid] = vlan.name
    for prefix in data["prefixes"]:
        if prefix.vlan:
            prefixes_by_vlan[prefix.vlan.vid] = str(prefix.prefix)

    # --- Classify devices by VLAN ---
    # Devices with primary IPs get placed in their VLAN container
    # Devices without IPs (switches) are placed at root level
    device_by_vlan = defaultdict(list)
    root_devices = []

    for device in data["devices"]:
        ip = get_primary_ip(device)
        if ip:
            vlan_id = ip_to_vlan(ip, prefixes_by_vlan)
            if vlan_id:
                device_by_vlan[vlan_id].append(device)
            else:
                root_devices.append(device)
        else:
            role_slug = device.role.slug if device.role else ""
            if role_slug in ("router", "switch"):
                root_devices.append(device)

    # --- Classify VMs by VLAN ---
    vm_by_vlan = defaultdict(list)
    for vm in data["vms"]:
        ip = get_primary_ip(vm)
        if ip:
            vlan_id = ip_to_vlan(ip, prefixes_by_vlan)
            if vlan_id:
                vm_by_vlan[vlan_id].append(vm)

    # --- gw-01 (core router) ---
    lines.append("# --- Core Router ---")
    udm = None
    for device in data["devices"]:
        if device.role and device.role.slug == "router":
            udm = device
            break

    if udm:
        ip = get_primary_ip(udm) or ""
        sid = slugify(udm.name)
        lines.append(f'{sid}: "{udm.name}" {{')
        lines.append(f'  shape: rectangle')
        lines.append(f'  style.fill: "#e8f5e9"')
        lines.append(f'  label: "{udm.name}\\n{ip}\\nCore Router / Firewall"')
        lines.append("}")
        lines.append("")

    # --- Switches at root level ---
    switches = [d for d in root_devices if d.role and d.role.slug == "switch"]
    if switches:
        lines.append("# --- Switches ---")
        for sw in switches:
            sid = slugify(sw.name)
            lines.append(f'{sid}: "{sw.name}" {{')
            lines.append(f'  shape: rectangle')
            lines.append(f'  style.fill: "#e0e0e0"')
            # Only show device type on separate line if it differs from name
            dt = str(sw.device_type) if sw.device_type else ""
            if dt and dt != sw.name:
                lines.append(f'  label: "{sw.name}\\n{dt}"')
            else:
                lines.append(f'  label: "{sw.name}"')
            lines.append("}")
        lines.append("")

    # --- VLAN containers ---
    lines.append("# --- VLANs ---")
    for vlan_id in sorted(VLAN_COLORS.keys()):
        vlan_name = vlan_names.get(vlan_id, f"VLAN {vlan_id}")
        prefix = prefixes_by_vlan.get(vlan_id, "")
        color = VLAN_COLORS.get(vlan_id, "#ffffff")
        vid = f"vlan-{vlan_id}"

        lines.append(f'{vid}: "VLAN {vlan_id} — {vlan_name}\\n{prefix}" {{')
        lines.append(f'  style.fill: "{color}"')

        # Devices in this VLAN
        vlan_devices = device_by_vlan.get(vlan_id, [])
        for device in sorted(vlan_devices, key=lambda d: d.name):
            did = slugify(device.name)
            label = get_device_label(device)
            lines.append(f'  {did}: "{label}"')

        # VMs in this VLAN
        vlan_vms = vm_by_vlan.get(vlan_id, [])
        for vm in sorted(vlan_vms, key=lambda v: v.name):
            vid_vm = slugify(vm.name)
            label = get_vm_label(vm)
            lines.append(f'  {vid_vm}: "{label}"')

        # Special case: empty VLAN 40 note
        if vlan_id == 40 and not vlan_devices and not vlan_vms:
            lines.append(f'  label: "VLAN {vlan_id} — {vlan_name}\\n{prefix}\\n(empty — TrueNAS pending migration)"')

        lines.append("}")
        lines.append("")

    # --- Switch ↔ gw-01 uplinks ---
    lines.append("# --- Switch uplinks ---")
    if udm:
        for sw in switches:
            sid = slugify(sw.name)
            uid = slugify(udm.name)
            lines.append(f'{sid} -> {uid}: "Uplink"')
    lines.append("")

    # --- VLAN trunks from gw-01 ---
    lines.append("# --- VLAN trunks ---")
    if udm:
        uid = slugify(udm.name)
        for vlan_id in sorted(VLAN_COLORS.keys()):
            vid = f"vlan-{vlan_id}"
            lines.append(f'{uid} -> {vid}')
    lines.append("")

    # --- Zone policies (inter-VLAN rules) ---
    # These are static — they come from Terraform Layer 00, not NetBox.
    # NetBox doesn't model firewall rules, so we hardcode the known policies.
    lines.append("# --- Zone policies (inter-VLAN rules) ---")
    lines.append("# Source: terraform/layers/00-network/main.tf")
    zone_policies = [
        ("vlan-10", "vlan-20", "ALLOW ALL", "#4caf50", False),
        ("vlan-10", "vlan-30", "ALLOW ALL", "#4caf50", False),
        ("vlan-10", "vlan-40", "ALLOW ALL", "#4caf50", False),
        ("vlan-10", "vlan-50", "ALLOW ALL", "#4caf50", False),
        ("vlan-1", "vlan-10", "ALLOW ALL", "#4caf50", False),
        ("vlan-1", "vlan-20", "ALLOW ALL", "#4caf50", False),
        ("vlan-1", "vlan-30", "ALLOW ALL", "#4caf50", False),
        ("vlan-1", "vlan-40", "ALLOW ALL", "#4caf50", False),
        ("vlan-1", "vlan-50", "ALLOW ALL", "#4caf50", False),
        ("vlan-20", "vlan-40", "NFS/iSCSI", "#ff9800", False),
        ("vlan-20", "vlan-50", "Vault 8200", "#ff9800", False),
        ("vlan-30", "vlan-20", "Service ports", "#ff9800", False),
        ("vlan-30", "vlan-40", "BLOCK", "#f44336", True),
        ("vlan-30", "vlan-50", "BLOCK", "#f44336", True),
    ]
    for src, dst, label, color, dashed in zone_policies:
        style = f'style.stroke: "{color}"'
        if dashed:
            style += "; style.stroke-dash: 5"
        lines.append(f'{src} -> {dst}: "{label}" {{{style}}}')
    lines.append("")

    # --- External (Hetzner) ---
    hetzner_vms = [
        vm for vm in data["vms"]
        if any(c.name == "hetzner-nbg1" for c in data["clusters"]
               if vm.cluster and vm.cluster.id == c.id)
    ]
    if hetzner_vms:
        lines.append("# --- External (Hetzner) ---")
        hvm = hetzner_vms[0]
        ip = get_primary_ip(hvm) or "46.x.x.x"
        # Mask public IP in diagram
        masked_ip = ip.split(".")[0] + ".x.x.x" if not ip.startswith("10.") else ip
        lines.append(f'hetzner: "Hetzner Gateway" {{')
        lines.append(f'  shape: cloud')
        lines.append(f'  label: "{hvm.name}\\n{masked_ip}\\nTraefik + WireGuard"')
        lines.append("}")
        lines.append("")
        lines.append('internet: Internet {')
        lines.append('  shape: cloud')
        lines.append('  style.fill: "#eceff1"')
        lines.append("}")
        lines.append("")
        lines.append('internet -> hetzner: "HTTPS (443)\\nWireGuard (51820)"')
        # Find WireGuard VM in DMZ
        wg_vms = [vm for vm in vm_by_vlan.get(30, []) if "wireguard" in vm.name.lower()]
        if wg_vms:
            wg_id = f"vlan-30.{slugify(wg_vms[0].name)}"
            lines.append(f'hetzner -> {wg_id}: "WireGuard Tunnel\\n10.8.0.0/24"')
        lines.append("")

    return "\n".join(lines) + "\n"


# =============================================================================
# Main
# =============================================================================

def main():
    url = os.environ.get("NETBOX_URL")
    token = os.environ.get("NETBOX_TOKEN")

    if not url or not token:
        print("ERROR: Set NETBOX_URL and NETBOX_TOKEN environment variables")
        print()
        print("Usage:")
        print("  export NETBOX_URL=http://10.0.20.14:8080")
        print("  export NETBOX_TOKEN=$(vault kv get -mount=secret -field=api_token services/netbox)")
        print("  python scripts/netbox-to-d2.py")
        sys.exit(1)

    print("NetBox → D2 Diagram Generator")
    print("=" * 60)
    print(f"  NetBox: {url}")
    print(f"  Output: {OUTPUT_PATH}")
    print()

    nb = pynetbox.api(url, token=token)

    print("[1/3] Fetching data from NetBox...")
    data = fetch_all_data(nb)
    print()

    print("[2/3] Generating D2 diagram...")
    d2_content = generate_d2(data)

    device_count = len(data["devices"])
    vm_count = len(data["vms"])
    vlan_count = len(data["vlans"])
    cable_count = len(data["cables"])
    print(f"  Diagram includes: {device_count} devices, {vm_count} VMs, {vlan_count} VLANs, {cable_count} cables")
    print()

    print("[3/3] Writing D2 file...")
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        f.write(d2_content)
    print(f"  Written to: {OUTPUT_PATH}")
    print()

    print("=" * 60)
    print("Done! Render locally with:")
    print(f"  d2 --theme 300 --layout elk {OUTPUT_PATH} output.svg")
    print()
    print("Or commit to trigger CI pipeline rendering.")


if __name__ == "__main__":
    main()
