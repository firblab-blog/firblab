#!/usr/bin/env python3
# =============================================================================
# Scanopy → NetBox Sync Script — FirbLab Infrastructure
# =============================================================================
# Syncs network discovery data from Scanopy into NetBox:
#   - Matches discovered hosts to existing NetBox devices/VMs by IP
#   - Updates interface MAC addresses from ARP discovery
#   - Creates new IP address records for unknown hosts
#   - Tags synced objects with "scanopy-discovered" for traceability
#
# Idempotent: safe to re-run. Updates existing records, skips unchanged.
#
# Prerequisites:
#   pip install pynetbox requests
#
# Usage:
#   export NETBOX_URL=http://10.0.20.14:8080
#   export NETBOX_TOKEN=$(vault kv get -mount=secret -field=api_token services/netbox)
#   export SCANOPY_URL=http://10.0.4.20:60072
#   export SCANOPY_EMAIL=$(vault kv get -mount=secret -field=admin_email services/scanopy)
#   export SCANOPY_PASSWORD=$(vault kv get -mount=secret -field=admin_password services/scanopy)
#   python scripts/scanopy-netbox-sync.py
#
# Data flow:
#   Scanopy daemon (multi-VLAN scanner) → Scanopy API
#     GET /api/v1/hosts (host objects) + GET /api/v1/interfaces (IP/MAC data)
#     → This script (merges by host_id) → NetBox API (pynetbox)
# =============================================================================

import os
import sys

try:
    import pynetbox
except ImportError:
    print("ERROR: pynetbox not installed. Run: pip install pynetbox")
    sys.exit(1)

try:
    import requests
except ImportError:
    print("ERROR: requests not installed. Run: pip install requests")
    sys.exit(1)


# =============================================================================
# Scanopy API Client
# =============================================================================

class ScanopyClient:
    """Minimal Scanopy REST API client with session cookie auth."""

    def __init__(self, base_url, email, password):
        self.base_url = base_url.rstrip("/")
        self.session = requests.Session()
        self._login(email, password)

    def _login(self, email, password):
        resp = self.session.post(
            f"{self.base_url}/api/auth/login",
            json={"email": email, "password": password},
        )
        resp.raise_for_status()

    def get_hosts(self, limit=100, offset=0):
        """Fetch discovered hosts (without interface data).

        Uses /api/v1/hosts — the versioned endpoint. Note: host objects
        return with empty `interfaces` arrays. Interface data (IP, MAC)
        must be fetched separately via get_interfaces() and merged by
        host_id. See get_all_interfaces().
        """
        resp = self.session.get(
            f"{self.base_url}/api/v1/hosts",
            params={"limit": limit, "offset": offset},
        )
        resp.raise_for_status()
        return resp.json()

    def get_all_hosts(self):
        """Paginate through all discovered hosts."""
        all_hosts = []
        offset = 0
        limit = 100
        while True:
            data = self.get_hosts(limit=limit, offset=offset)
            # Handle both {data: [...]} and direct [...] response formats
            hosts = data.get("data", data) if isinstance(data, dict) else data
            if not hosts:
                break
            all_hosts.extend(hosts)
            if len(hosts) < limit:
                break
            offset += limit
        return all_hosts

    def get_interfaces(self, limit=1000, offset=0):
        """Fetch all discovered interfaces (contains IP + MAC + host_id)."""
        resp = self.session.get(
            f"{self.base_url}/api/v1/interfaces",
            params={"limit": limit, "offset": offset},
        )
        resp.raise_for_status()
        return resp.json()

    def get_all_interfaces(self):
        """Paginate through all discovered interfaces."""
        all_ifaces = []
        offset = 0
        limit = 1000
        while True:
            data = self.get_interfaces(limit=limit, offset=offset)
            ifaces = data.get("data", data) if isinstance(data, dict) else data
            if not ifaces:
                break
            all_ifaces.extend(ifaces)
            if len(ifaces) < limit:
                break
            offset += limit
        return all_ifaces

    def get_subnets(self):
        """Fetch discovered subnets."""
        resp = self.session.get(f"{self.base_url}/api/v1/subnets")
        resp.raise_for_status()
        data = resp.json()
        return data.get("data", data) if isinstance(data, dict) else data


# =============================================================================
# Helpers
# =============================================================================

def get_or_create(endpoint, search_params, create_params=None):
    """Get existing object or create new one. Returns the object."""
    results = list(endpoint.filter(**search_params))
    if results:
        return results[0]
    params = create_params or search_params
    return endpoint.create(params)


def ensure_tag(nb, name, slug, color="9e9e9e"):
    """Ensure a tag exists in NetBox."""
    return get_or_create(
        nb.extras.tags,
        {"slug": slug},
        {"name": name, "slug": slug, "color": color},
    )


def extract_ip(host):
    """Extract the primary IP address string from a Scanopy host object.

    Scanopy's list endpoint returns hosts with empty `interfaces` arrays.
    We merge interfaces separately into `_interfaces` before calling this.
    Interface objects have fields like: ip_address, address, ip, addresses.
    """
    if not isinstance(host, dict):
        return None

    # Direct field on host (unlikely but handle it)
    ip = host.get("ip_address") or host.get("ip") or host.get("address")
    if ip and isinstance(ip, str):
        return ip.split("/")[0]

    # Check merged interfaces (_interfaces from separate API call)
    for iface in host.get("_interfaces", host.get("interfaces", [])):
        if not isinstance(iface, dict):
            continue
        # Try direct IP fields on interface
        for field in ("ip_address", "ip", "address"):
            val = iface.get(field)
            if val and isinstance(val, str):
                return val.split("/")[0]
        # Try nested addresses list
        for addr in iface.get("ip_addresses", iface.get("addresses", [])):
            if isinstance(addr, dict):
                a = addr.get("address") or addr.get("ip") or addr.get("ip_address")
                if a:
                    return a.split("/")[0]
            elif isinstance(addr, str):
                return addr.split("/")[0]

    return None


def extract_mac(host):
    """Extract MAC address from a Scanopy host object."""
    if not isinstance(host, dict):
        return None

    mac = host.get("mac_address") or host.get("mac")
    if mac:
        return mac.upper()

    # Check merged interfaces
    for iface in host.get("_interfaces", host.get("interfaces", [])):
        if not isinstance(iface, dict):
            continue
        mac = iface.get("mac_address") or iface.get("mac") or iface.get("hw_address")
        if mac:
            return mac.upper()

    return None


def extract_hostname(host):
    """Extract hostname from a Scanopy host object."""
    if isinstance(host, dict):
        return (
            host.get("hostname")
            or host.get("name")
            or host.get("friendly_name")
            or host.get("dns_name")
            or ""
        )
    return ""


def find_netbox_match(nb, ip_str):
    """Find a matching device or VM in NetBox by IP address.

    Returns (obj_type, obj) where obj_type is 'device' or 'vm', or (None, None).
    """
    # Search IP addresses with the host portion
    for cidr in [f"{ip_str}/24", f"{ip_str}/32"]:
        ips = list(nb.ipam.ip_addresses.filter(address=cidr))
        for ip_obj in ips:
            if ip_obj.assigned_object:
                iface = ip_obj.assigned_object
                if hasattr(iface, "device") and iface.device:
                    device = nb.dcim.devices.get(iface.device.id)
                    return ("device", device)
                if hasattr(iface, "virtual_machine") and iface.virtual_machine:
                    vm = nb.virtualization.virtual_machines.get(
                        iface.virtual_machine.id
                    )
                    return ("vm", vm)

    # Fallback: search devices by name matching the IP description
    ips = list(nb.ipam.ip_addresses.filter(address=f"{ip_str}/24"))
    if ips:
        return ("ip_only", ips[0])

    return (None, None)


# =============================================================================
# Main Sync Logic
# =============================================================================

def main():
    # -------------------------------------------------------------------------
    # Configuration from environment
    # -------------------------------------------------------------------------
    netbox_url = os.environ.get("NETBOX_URL")
    netbox_token = os.environ.get("NETBOX_TOKEN")
    scanopy_url = os.environ.get("SCANOPY_URL")
    scanopy_email = os.environ.get("SCANOPY_EMAIL")
    scanopy_password = os.environ.get("SCANOPY_PASSWORD")

    missing = []
    if not netbox_url:
        missing.append("NETBOX_URL")
    if not netbox_token:
        missing.append("NETBOX_TOKEN")
    if not scanopy_url:
        missing.append("SCANOPY_URL")
    if not scanopy_email:
        missing.append("SCANOPY_EMAIL")
    if not scanopy_password:
        missing.append("SCANOPY_PASSWORD")

    if missing:
        print(f"ERROR: Missing environment variables: {', '.join(missing)}")
        print()
        print("Usage:")
        print("  export NETBOX_URL=http://10.0.20.14:8080")
        print("  export NETBOX_TOKEN=$(vault kv get -mount=secret -field=api_token services/netbox)")
        print("  export SCANOPY_URL=http://10.0.4.20:60072")
        print("  export SCANOPY_EMAIL=$(vault kv get -mount=secret -field=admin_email services/scanopy)")
        print("  export SCANOPY_PASSWORD=$(vault kv get -mount=secret -field=admin_password services/scanopy)")
        print("  python scripts/scanopy-netbox-sync.py")
        sys.exit(1)

    # -------------------------------------------------------------------------
    # Connect to APIs
    # -------------------------------------------------------------------------
    print("Scanopy → NetBox Sync")
    print("=" * 60)

    print(f"  NetBox:  {netbox_url}")
    print(f"  Scanopy: {scanopy_url}")
    print()

    nb = pynetbox.api(netbox_url, token=netbox_token)
    scanopy = ScanopyClient(scanopy_url, scanopy_email, scanopy_password)

    # -------------------------------------------------------------------------
    # Ensure required NetBox objects
    # -------------------------------------------------------------------------
    print("[1/4] Setting up NetBox prerequisites...")

    discovered_tag = ensure_tag(
        nb,
        "Scanopy Discovered",
        "scanopy-discovered",
        color="00bcd4",
    )

    # Device role for unknown hosts discovered by scanning
    discovered_role = get_or_create(
        nb.dcim.device_roles,
        {"slug": "discovered"},
        {
            "name": "Discovered",
            "slug": "discovered",
            "color": "ff9800",
            "vm_role": False,
        },
    )

    # Generic device type for discovered devices
    unknown_manufacturer = get_or_create(
        nb.dcim.manufacturers,
        {"slug": "unknown"},
        {"name": "Unknown", "slug": "unknown"},
    )
    unknown_type = get_or_create(
        nb.dcim.device_types,
        {"slug": "unknown-discovered"},
        {
            "manufacturer": unknown_manufacturer.id,
            "model": "Unknown (Discovered)",
            "slug": "unknown-discovered",
            "u_height": 0,
        },
    )

    # Get the FirbLab site
    sites = list(nb.dcim.sites.filter(slug="firblab"))
    site = sites[0] if sites else None
    if not site:
        print("  WARNING: FirbLab site not found. Run netbox-seed.py first.")
        print("  Discovered devices will be created without a site.")

    print(f"  Tag: {discovered_tag.name}")
    print(f"  Role: {discovered_role.name}")
    print()

    # -------------------------------------------------------------------------
    # Fetch Scanopy data
    # -------------------------------------------------------------------------
    print("[2/4] Fetching hosts from Scanopy...")
    hosts = scanopy.get_all_hosts()
    print(f"  Discovered hosts: {len(hosts)}")

    if not hosts:
        print("No hosts discovered by Scanopy. Nothing to sync.")
        return

    # Fetch interfaces separately (host list endpoint returns empty arrays)
    interfaces = scanopy.get_all_interfaces()
    print(f"  Discovered interfaces: {len(interfaces)}")

    # Build host_id → interfaces lookup
    iface_by_host = {}
    for iface in interfaces:
        host_id = iface.get("host_id") or iface.get("host", {}).get("id", "")
        if host_id:
            iface_by_host.setdefault(host_id, []).append(iface)

    # Merge interfaces into host objects
    hosts_with_ip = 0
    for host in hosts:
        hid = host.get("id", "")
        if hid in iface_by_host:
            host["_interfaces"] = iface_by_host[hid]
            hosts_with_ip += 1

    print(f"  Hosts with interfaces: {hosts_with_ip}")
    print()

    # -------------------------------------------------------------------------
    # Sync hosts to NetBox
    # -------------------------------------------------------------------------
    print("[3/4] Syncing hosts to NetBox...")

    stats = {"matched": 0, "created_ip": 0, "created_device": 0, "skipped": 0, "updated_mac": 0}

    for host in hosts:
        ip_str = extract_ip(host)
        if not ip_str:
            stats["skipped"] += 1
            continue

        mac = extract_mac(host)
        hostname = extract_hostname(host)
        label = hostname or ip_str

        # Try to match existing NetBox object
        match_type, match_obj = find_netbox_match(nb, ip_str)

        if match_type in ("device", "vm"):
            # Existing device or VM found — update if needed
            stats["matched"] += 1

            # Add scanopy-discovered tag if not present
            existing_tags = [t.slug for t in (match_obj.tags or [])]
            if "scanopy-discovered" not in existing_tags:
                tags = [{"slug": t} for t in existing_tags] + [{"slug": "scanopy-discovered"}]
                match_obj.tags = tags
                match_obj.save()

            print(f"  MATCH  {label:30s} → {match_type}:{match_obj.name}")

        elif match_type == "ip_only":
            # IP exists but not assigned to a device — tag it
            stats["matched"] += 1
            existing_tags = [t.slug for t in (match_obj.tags or [])]
            if "scanopy-discovered" not in existing_tags:
                tags = [{"slug": t} for t in existing_tags] + [{"slug": "scanopy-discovered"}]
                match_obj.tags = tags
                match_obj.save()
            print(f"  MATCH  {label:30s} → ip:{match_obj.address}")

        else:
            # No match — create IP address record for the discovered host
            # Use /24 CIDR which matches our VLAN prefix structure
            cidr = f"{ip_str}/24"
            ip_obj = get_or_create(
                nb.ipam.ip_addresses,
                {"address": cidr},
                {
                    "address": cidr,
                    "status": "active",
                    "description": f"Scanopy discovery: {label}",
                    "tags": [{"slug": "scanopy-discovered"}],
                },
            )
            stats["created_ip"] += 1
            print(f"  NEW IP {label:30s} → {cidr}")

    print()

    # -------------------------------------------------------------------------
    # Sync subnets
    # -------------------------------------------------------------------------
    print("[4/4] Verifying subnet alignment...")

    try:
        subnets = scanopy.get_subnets()
        netbox_prefixes = {str(p.prefix): p for p in nb.ipam.prefixes.all()}

        for subnet in subnets:
            cidr = subnet.get("cidr") or subnet.get("network") or subnet.get("prefix")
            if not cidr:
                continue
            if cidr in netbox_prefixes:
                print(f"  OK     {cidr} — exists in NetBox")
            else:
                print(f"  MISS   {cidr} — in Scanopy but not in NetBox")
    except Exception as e:
        print(f"  WARNING: Could not fetch subnets from Scanopy: {e}")
        print("  Subnet verification skipped.")

    print()

    # -------------------------------------------------------------------------
    # Summary
    # -------------------------------------------------------------------------
    print("=" * 60)
    print("Sync complete!")
    print("=" * 60)
    print(f"  Hosts from Scanopy:  {len(hosts)}")
    print(f"  Matched in NetBox:   {stats['matched']}")
    print(f"  New IPs created:     {stats['created_ip']}")
    print(f"  Skipped (no IP):     {stats['skipped']}")
    print()
    print("Review new discoveries in NetBox:")
    print(f"  {netbox_url}/ipam/ip-addresses/?tag=scanopy-discovered")


if __name__ == "__main__":
    main()
