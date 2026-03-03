#!/usr/bin/env python3
# =============================================================================
# Service Directory Generator — FirbLab Infrastructure
# =============================================================================
# Reads existing IaC data sources (Traefik backends, Ansible inventory, DNS
# config) and generates a unified service directory for emergency reference
# and day-to-day access.
#
# Zero API calls — reads only from Git-tracked files. Works during total
# infrastructure outages because the data comes from the local filesystem.
#
# Prerequisites:
#   pip install pyyaml
#
# Usage:
#   python scripts/generate-service-directory.py
#
# Outputs:
#   docs/service-catalog.yml     — Machine-readable YAML catalog
#   docs/SERVICE-DIRECTORY.md    — Emergency reference (Markdown)
#   docs/service-directory.html  — Searchable HTML (self-contained, dark theme)
#
# Data sources:
#   ansible/roles/traefik-standalone/defaults/main.yml  (Traefik backends)
#   ansible/inventory/hosts.yml                         (Host IPs, VM IDs)
#   terraform/layers/00-network/dns.tf                  (K8s service list)
# =============================================================================

import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed. Run: pip install pyyaml")
    sys.exit(1)


# =============================================================================
# Project paths (relative to repo root)
# =============================================================================
REPO_ROOT = Path(__file__).resolve().parent.parent
TRAEFIK_DEFAULTS = REPO_ROOT / "ansible" / "roles" / "traefik-standalone" / "defaults" / "main.yml"
INVENTORY = REPO_ROOT / "ansible" / "inventory" / "hosts.yml"
DNS_TF = REPO_ROOT / "terraform" / "layers" / "00-network" / "dns.tf"
OUTPUT_DIR = REPO_ROOT / "docs"

# =============================================================================
# Constants — services not parseable from a single IaC file
# =============================================================================

# Auth methods for non-ForwardAuth services (ForwardAuth is detected from config)
AUTH_METHODS = {
    "gitlab": "native-oidc",
    "authentik": "native-auth",
    "mealie": "native-oidc",
    "netbox": "native-oidc",
    "patchmon": "native-oidc",
    "vaultwarden": "native-oidc",
    "openwebui": "native-oidc",
    "actualbudget": "native-oidc",
    "truenas": "native-auth",
    "immich": "native-auth",
    "linkwarden": "native-auth",
    "paperless": "native-auth",
    "plex": "plex-account",
    "portracker": "native-auth",
    "mailarchiver": "native-oidc",
    "ittools": "native-auth",
    "adguard": "basic-auth",
    "gotify": "native-auth",
    "status": "forwardauth",
    "pve-01": "native-auth",
    "pve-02": "native-auth",
    "pve-03": "native-auth",
    "pve-04": "native-auth",
}

# Display names for services (where the ID isn't pretty enough)
DISPLAY_NAMES = {
    "gitlab": "GitLab",
    "authentik": "Authentik",
    "pbs": "Proxmox Backup Server",
    "ghost": "Ghost Blog",
    "roundcube": "Roundcube Webmail",
    "foundryvtt": "FoundryVTT",
    "mealie": "Mealie",
    "netbox": "NetBox",
    "patchmon": "PatchMon",
    "actualbudget": "Actual Budget",
    "vaultwarden": "Vaultwarden",
    "openwebui": "Open WebUI",
    "n8n": "n8n",
    "backrest": "Backrest",
    "homeassistant": "Home Assistant",
    "truenas": "TrueNAS",
    "immich": "Immich",
    "linkwarden": "Linkwarden",
    "paperless": "Paperless-ngx",
    "plex": "Plex",
    "portracker": "Portracker",
    "mailarchiver": "Mail Archiver",
    "ittools": "IT Tools",
    "archive": "FileBrowser",
    "kiwix": "Kiwix",
    "archivebox": "ArchiveBox",
    "bookstack": "BookStack",
    "stirlingpdf": "Stirling PDF",
    "wallabag": "Wallabag",
    "adguard": "AdGuard Home",
    "status": "Uptime Kuma",
    "pve-01": "Proxmox (lab-01)",
    "pve-02": "Proxmox (lab-02)",
    "pve-03": "Proxmox (lab-03)",
    "pve-04": "Proxmox (lab-04)",
}

# K8s services with kubectl port-forward fallback commands
K8S_SERVICES = [
    {
        "name": "ArgoCD",
        "id": "argocd",
        "proxy_url": "https://argocd.home.example-lab.org",
        "kubectl_fallback": "kubectl port-forward svc/argocd-server -n argocd 8080:443",
        "auth_method": "native-oidc",
        "notes": "GitOps deployment dashboard",
    },
    {
        "name": "Grafana",
        "id": "grafana",
        "proxy_url": "https://grafana.home.example-lab.org",
        "kubectl_fallback": "kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80",
        "auth_method": "native-oidc",
        "notes": "Monitoring dashboards",
    },
    {
        "name": "Headlamp",
        "id": "headlamp",
        "proxy_url": "https://headlamp.home.example-lab.org",
        "kubectl_fallback": "kubectl port-forward svc/headlamp -n headlamp 8080:80",
        "auth_method": "native-oidc",
        "notes": "Kubernetes web dashboard",
    },
    {
        "name": "Longhorn",
        "id": "longhorn",
        "proxy_url": "https://longhorn.home.example-lab.org",
        "kubectl_fallback": "kubectl port-forward svc/longhorn-frontend -n longhorn-system 8080:80",
        "auth_method": "none",
        "notes": "Distributed storage UI",
    },
    {
        "name": "SonarQube",
        "id": "sonarqube",
        "proxy_url": "https://sonarqube.home.example-lab.org",
        "kubectl_fallback": "kubectl port-forward svc/sonarqube-sonarqube -n sonarqube 9000:9000",
        "auth_method": "native-auth",
        "notes": "Code quality analysis",
    },
]

# Hetzner services (behind WireGuard tunnel)
HETZNER_SERVICES = [
    {
        "name": "Hetzner Traefik",
        "id": "hetzner-traefik",
        "public_url": None,
        "tunnel_url": "http://10.8.0.1:8888",
        "auth_method": "basic-auth",
        "notes": "Reverse proxy dashboard (WireGuard required)",
    },
    {
        "name": "AdGuard Home",
        "id": "adguard",
        "public_url": "https://adguard.example-lab.org",
        "tunnel_url": "http://10.8.0.1:3000",
        "auth_method": "basic-auth",
        "notes": "DNS ad blocker (WireGuard required)",
    },
    {
        "name": "Uptime Kuma",
        "id": "uptime-kuma",
        "public_url": "https://status.example-lab.org",
        "tunnel_url": "http://10.8.0.1:3001",
        "auth_method": "native-auth",
        "notes": "Service monitoring (WireGuard required)",
    },
    {
        "name": "Gotify",
        "id": "gotify",
        "public_url": "https://gotify.example-lab.org",
        "tunnel_url": "http://10.8.0.1:8080",
        "auth_method": "native-auth",
        "notes": "Push notifications (WireGuard required)",
    },
]

# Bare-metal services (not behind Traefik)
BARE_METAL_SERVICES = [
    {
        "name": "Scanopy",
        "id": "scanopy",
        "vlan": 1,
        "vlan_name": "Default LAN",
        "direct_url": "http://10.0.4.20:60072",
        "auth_method": "native-auth",
        "notes": "Network scanner (lab-08 RPi4)",
    },
    {
        "name": "NUT UPS Server",
        "id": "nut",
        "vlan": 1,
        "vlan_name": "Default LAN",
        "direct_url": "10.0.4.20:3493 (TCP, not HTTP)",
        "auth_method": "none",
        "notes": "UPS monitoring daemon (lab-08 RPi4). No web UI.",
    },
]

# Direct-access services (own TLS, not proxied)
DIRECT_SERVICES = [
    {
        "name": "Vault",
        "id": "vault",
        "vlan": 10,
        "vlan_name": "Management",
        "direct_url": "https://10.0.10.10:8200",
        "auth_method": "token",
        "notes": "Own CA cert. Export VAULT_CACERT=~/.lab/tls/ca/ca.pem",
    },
]


# =============================================================================
# Data loading
# =============================================================================

def load_traefik_backends():
    """Parse traefik_backends from the standalone Traefik role defaults."""
    with open(TRAEFIK_DEFAULTS) as f:
        data = yaml.safe_load(f)
    return data.get("traefik_backends", {})


def load_inventory():
    """Parse Ansible inventory for host IPs and metadata."""
    with open(INVENTORY) as f:
        data = yaml.safe_load(f)
    # Flatten all hosts with their vars into a dict keyed by ansible_host IP
    hosts_by_ip = {}
    hosts_by_name = {}

    def walk_groups(node, path=""):
        if isinstance(node, dict):
            if "hosts" in node:
                for hostname, hostvars in (node["hosts"] or {}).items():
                    if hostvars and "ansible_host" in hostvars:
                        entry = {
                            "hostname": hostname,
                            "ip": hostvars["ansible_host"],
                            "vm_id": hostvars.get("container_vm_id"),
                            "vm_type": "lxc" if hostvars.get("container_vm_id") else "vm",
                        }
                        hosts_by_ip[hostvars["ansible_host"]] = entry
                        hosts_by_name[hostname] = entry
            if "children" in node:
                for child_name, child_node in (node["children"] or {}).items():
                    walk_groups(child_node, f"{path}/{child_name}")

    walk_groups(data.get("all", {}))
    return hosts_by_ip, hosts_by_name


def classify_vlan(ip):
    """Map an IP address to its VLAN ID and name."""
    if ip.startswith("10.0.10."):
        return 10, "Management"
    if ip.startswith("10.0.20."):
        return 20, "Services"
    if ip.startswith("10.0.30."):
        return 30, "DMZ"
    if ip.startswith("10.0.4."):
        return 1, "Default LAN"
    if ip.startswith("10.0.40."):
        return 40, "Storage"
    if ip.startswith("10.0.50."):
        return 50, "Security"
    if ip.startswith("10.0.60."):
        return 60, "IoT"
    if ip.startswith("10.8.0."):
        return None, "WireGuard Tunnel"
    return None, "Unknown"


def parse_backend_url(url):
    """Extract host IP and port from a backend URL."""
    parsed = urlparse(url)
    host = parsed.hostname or ""
    port = parsed.port
    if port is None:
        port = 443 if parsed.scheme == "https" else 80
    return host, port


def get_auth_method(svc_id, forwardauth):
    """Determine auth method for a service."""
    if forwardauth:
        return "forwardauth"
    return AUTH_METHODS.get(svc_id, "native-auth")


def get_display_name(svc_id):
    """Get a human-readable display name for a service."""
    if svc_id in DISPLAY_NAMES:
        return DISPLAY_NAMES[svc_id]
    return svc_id.replace("-", " ").title()


# =============================================================================
# Catalog assembly
# =============================================================================

def build_catalog():
    """Assemble the unified service catalog from all IaC sources."""
    services = []
    backends = load_traefik_backends()
    hosts_by_ip, _ = load_inventory()

    # 1. Traefik-proxied standalone services
    for svc_id, svc in backends.items():
        host_ip, host_port = parse_backend_url(svc["backend_url"])
        # Skip FQDN backends (external domains like gotify.example-lab.org, adguard.example-lab.org).
        # These are Hetzner services proxied by Traefik for LAN convenience; they are
        # already fully represented in HETZNER_SERVICES with tunnel URLs and correct metadata.
        if not host_ip[0].isdigit():
            continue
        vlan_id, vlan_name = classify_vlan(host_ip)
        inv_host = hosts_by_ip.get(host_ip, {})
        aliases = svc.get("aliases", [])
        forwardauth = svc.get("forwardauth", False)

        services.append({
            "name": get_display_name(svc_id),
            "id": svc_id,
            "category": "standalone",
            "vlan": vlan_id,
            "vlan_name": vlan_name,
            "host_ip": host_ip,
            "host_port": host_port,
            "protocol": "https" if svc["backend_url"].startswith("https") else "http",
            "proxy_url": f"https://{svc['subdomain']}.home.example-lab.org",
            "direct_url": svc["backend_url"],
            "proxy_type": "standalone",
            "auth_method": get_auth_method(svc_id, forwardauth),
            "insecure_backend": svc.get("insecure_backend", False),
            "websocket": svc.get("websocket", False),
            "aliases": [f"https://{a}.home.example-lab.org" for a in aliases],
            "inventory_hostname": inv_host.get("hostname", ""),
            "vm_id": inv_host.get("vm_id"),
            "vm_type": inv_host.get("vm_type", ""),
            "notes": "",
        })

    # 2. K8s services
    for svc in K8S_SERVICES:
        services.append({
            "name": svc["name"],
            "id": svc["id"],
            "category": "k8s",
            "vlan": 20,
            "vlan_name": "Services",
            "host_ip": "10.0.20.220",
            "host_port": None,
            "protocol": "https",
            "proxy_url": svc["proxy_url"],
            "direct_url": None,
            "proxy_type": "k8s",
            "auth_method": svc["auth_method"],
            "insecure_backend": False,
            "websocket": False,
            "aliases": [],
            "kubectl_fallback": svc["kubectl_fallback"],
            "notes": svc["notes"],
        })

    # 3. Hetzner services
    for svc in HETZNER_SERVICES:
        services.append({
            "name": svc["name"],
            "id": svc["id"],
            "category": "hetzner",
            "vlan": None,
            "vlan_name": "WireGuard Tunnel",
            "host_ip": "10.8.0.1",
            "host_port": None,
            "protocol": "http",
            "proxy_url": svc.get("public_url"),
            "direct_url": svc["tunnel_url"],
            "proxy_type": "hetzner",
            "auth_method": svc["auth_method"],
            "insecure_backend": False,
            "websocket": False,
            "aliases": [],
            "notes": svc["notes"],
        })

    # 4. Bare-metal services
    for svc in BARE_METAL_SERVICES:
        services.append({
            "name": svc["name"],
            "id": svc["id"],
            "category": "bare-metal",
            "vlan": svc["vlan"],
            "vlan_name": svc["vlan_name"],
            "host_ip": None,
            "host_port": None,
            "protocol": "http",
            "proxy_url": None,
            "direct_url": svc["direct_url"],
            "proxy_type": "none",
            "auth_method": svc["auth_method"],
            "insecure_backend": False,
            "websocket": False,
            "aliases": [],
            "notes": svc["notes"],
        })

    # 5. Direct-access services (Vault)
    for svc in DIRECT_SERVICES:
        services.append({
            "name": svc["name"],
            "id": svc["id"],
            "category": "direct",
            "vlan": svc["vlan"],
            "vlan_name": svc["vlan_name"],
            "host_ip": None,
            "host_port": None,
            "protocol": "https",
            "proxy_url": None,
            "direct_url": svc["direct_url"],
            "proxy_type": "none",
            "auth_method": svc["auth_method"],
            "insecure_backend": False,
            "websocket": False,
            "aliases": [],
            "notes": svc["notes"],
        })

    return services


# =============================================================================
# YAML catalog output
# =============================================================================

def render_yaml(services, generated_at):
    """Write the machine-readable YAML catalog."""
    catalog = {
        "generated_at": generated_at,
        "generator": "scripts/generate-service-directory.py",
        "services": services,
    }
    output_path = OUTPUT_DIR / "service-catalog.yml"
    with open(output_path, "w") as f:
        f.write("# =============================================================================\n")
        f.write("# FirbLab Service Catalog — AUTO-GENERATED\n")
        f.write("# =============================================================================\n")
        f.write("# DO NOT EDIT — regenerate with: python scripts/generate-service-directory.py\n")
        f.write(f"# Generated: {generated_at}\n")
        f.write("# =============================================================================\n\n")
        yaml.dump(catalog, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    print(f"  Written: {output_path}")


# =============================================================================
# Markdown output
# =============================================================================

def auth_badge_md(method):
    """Return a short auth label for Markdown."""
    badges = {
        "forwardauth": "ForwardAuth",
        "native-oidc": "OIDC",
        "native-auth": "Native",
        "plex-account": "Plex",
        "basic-auth": "Basic",
        "token": "Token",
        "none": "None",
    }
    return badges.get(method, method)


def render_markdown(services, generated_at):
    """Write the emergency-reference Markdown file."""
    lines = []
    lines.append("# FirbLab Service Directory")
    lines.append("")
    lines.append("> **AUTO-GENERATED** — do not edit manually.")
    lines.append("> Regenerate: `python scripts/generate-service-directory.py`")
    lines.append(f"> Last generated: {generated_at}")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## Emergency Direct Access")
    lines.append("")
    lines.append("When **Standalone Traefik** (`10.0.10.17`) is down, use the **Direct URL** column.")
    lines.append("When **K8s Traefik** (`10.0.20.220`) is down, use the `kubectl port-forward` commands.")
    lines.append("")
    lines.append("## Security Warning")
    lines.append("")
    lines.append("**ForwardAuth services have NO native authentication when accessed by direct IP.**")
    lines.append("These services are protected only by UFW source restrictions (management/LAN/services networks).")
    lines.append("Direct access bypasses Authentik SSO entirely.")
    lines.append("")

    # Group standalone services by VLAN
    standalone = [s for s in services if s["category"] == "standalone"]
    vlan_order = [
        (10, "Management"),
        (20, "Services"),
        (40, "Storage"),
        (1, "Default LAN"),
        (60, "IoT"),
        (50, "Security"),
    ]

    for vlan_id, vlan_name in vlan_order:
        vlan_services = [s for s in standalone if s["vlan"] == vlan_id]
        if not vlan_services:
            continue
        lines.append(f"## VLAN {vlan_id} -- {vlan_name}")
        lines.append("")
        lines.append("| Service | Proxy URL | Direct URL | Auth | Notes |")
        lines.append("|---------|-----------|------------|------|-------|")
        for s in sorted(vlan_services, key=lambda x: x["name"]):
            proxy = s["proxy_url"] or "N/A"
            direct = s["direct_url"] or "N/A"
            auth = auth_badge_md(s["auth_method"])
            notes_parts = []
            if s.get("insecure_backend"):
                notes_parts.append("self-signed cert")
            if s.get("websocket"):
                notes_parts.append("WebSocket")
            if s.get("aliases"):
                alias_strs = [a.replace("https://", "") for a in s["aliases"]]
                notes_parts.append(f"alias: {', '.join(alias_strs)}")
            if s.get("notes"):
                notes_parts.append(s["notes"])
            if s["auth_method"] == "forwardauth":
                notes_parts.append("**no auth on direct IP**")
            notes = "; ".join(notes_parts)
            lines.append(f"| {s['name']} | {proxy} | {direct} | {auth} | {notes} |")
        lines.append("")

    # K8s services
    k8s = [s for s in services if s["category"] == "k8s"]
    if k8s:
        lines.append("## K8s Services (MetalLB VIP 10.0.20.220)")
        lines.append("")
        lines.append("No direct access — services run behind ClusterIP. Use `kubectl port-forward` when K8s Traefik is down.")
        lines.append("")
        lines.append("| Service | Proxy URL | kubectl Fallback | Auth | Notes |")
        lines.append("|---------|-----------|------------------|------|-------|")
        for s in k8s:
            kubectl = f"`{s.get('kubectl_fallback', 'N/A')}`"
            auth = auth_badge_md(s["auth_method"])
            lines.append(f"| {s['name']} | {s['proxy_url']} | {kubectl} | {auth} | {s.get('notes', '')} |")
        lines.append("")

    # Hetzner services
    hetzner = [s for s in services if s["category"] == "hetzner"]
    if hetzner:
        lines.append("## Hetzner Services (WireGuard Tunnel 10.8.0.1)")
        lines.append("")
        lines.append("All Hetzner services require an active WireGuard tunnel. If WireGuard is down, these are unreachable from the homelab.")
        lines.append("")
        lines.append("| Service | Public URL | Tunnel Direct URL | Auth | Notes |")
        lines.append("|---------|-----------|-------------------|------|-------|")
        for s in hetzner:
            public = s["proxy_url"] or "N/A"
            direct = s["direct_url"] or "N/A"
            auth = auth_badge_md(s["auth_method"])
            lines.append(f"| {s['name']} | {public} | {direct} | {auth} | {s.get('notes', '')} |")
        lines.append("")

    # Bare-metal services
    bare_metal = [s for s in services if s["category"] == "bare-metal"]
    if bare_metal:
        lines.append("## Bare-Metal Services (No Proxy)")
        lines.append("")
        lines.append("| Service | Direct URL | Auth | Notes |")
        lines.append("|---------|------------|------|-------|")
        for s in bare_metal:
            auth = auth_badge_md(s["auth_method"])
            lines.append(f"| {s['name']} | {s['direct_url']} | {auth} | {s.get('notes', '')} |")
        lines.append("")

    # Direct-access services
    direct = [s for s in services if s["category"] == "direct"]
    if direct:
        lines.append("## Direct Access (Own TLS, No Proxy)")
        lines.append("")
        lines.append("| Service | URL | Auth | Notes |")
        lines.append("|---------|-----|------|-------|")
        for s in direct:
            auth = auth_badge_md(s["auth_method"])
            lines.append(f"| {s['name']} | {s['direct_url']} | {auth} | {s.get('notes', '')} |")
        lines.append("")

    output_path = OUTPUT_DIR / "SERVICE-DIRECTORY.md"
    with open(output_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"  Written: {output_path}")


# =============================================================================
# HTML output
# =============================================================================

def auth_color(method):
    """Return CSS color for auth method badges."""
    colors = {
        "native-oidc": "#22c55e",      # green
        "forwardauth": "#eab308",       # yellow (warning)
        "native-auth": "#3b82f6",       # blue
        "plex-account": "#e67e22",      # orange
        "basic-auth": "#3b82f6",        # blue
        "token": "#8b5cf6",             # purple
        "none": "#ef4444",              # red
    }
    return colors.get(method, "#6b7280")


def render_html(services, generated_at):
    """Write the self-contained searchable HTML file."""
    # Build JSON data for JavaScript
    import json
    js_services = []
    for s in services:
        js_services.append({
            "name": s["name"],
            "id": s["id"],
            "category": s["category"],
            "vlan": s.get("vlan"),
            "vlan_name": s.get("vlan_name", ""),
            "proxy_url": s.get("proxy_url") or "",
            "direct_url": s.get("direct_url") or "",
            "auth_method": s.get("auth_method", ""),
            "kubectl_fallback": s.get("kubectl_fallback", ""),
            "notes": s.get("notes", ""),
            "insecure_backend": s.get("insecure_backend", False),
            "websocket": s.get("websocket", False),
            "aliases": s.get("aliases", []),
        })

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>FirbLab Service Directory</title>
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
       background: #0f172a; color: #e2e8f0; min-height: 100vh; padding: 1rem; }}
.header {{ text-align: center; padding: 1.5rem 0 1rem; }}
.header h1 {{ font-size: 1.8rem; color: #f8fafc; margin-bottom: 0.3rem; }}
.header .subtitle {{ color: #94a3b8; font-size: 0.85rem; }}
.warning {{ background: #422006; border: 1px solid #92400e; border-radius: 8px;
            padding: 0.8rem 1rem; margin: 1rem auto; max-width: 900px; font-size: 0.85rem; color: #fbbf24; }}
.search-bar {{ display: flex; justify-content: center; gap: 0.5rem; padding: 0.8rem 0;
               flex-wrap: wrap; max-width: 900px; margin: 0 auto; }}
.search-bar input {{ background: #1e293b; border: 1px solid #334155; border-radius: 6px;
                     padding: 0.5rem 1rem; color: #e2e8f0; font-size: 0.95rem; width: 100%;
                     max-width: 400px; outline: none; }}
.search-bar input:focus {{ border-color: #3b82f6; }}
.filters {{ display: flex; justify-content: center; gap: 0.4rem; flex-wrap: wrap;
            padding: 0.5rem 0; max-width: 900px; margin: 0 auto; }}
.filter-btn {{ background: #1e293b; border: 1px solid #334155; border-radius: 6px;
               padding: 0.35rem 0.75rem; color: #94a3b8; cursor: pointer; font-size: 0.8rem;
               transition: all 0.15s; }}
.filter-btn:hover {{ border-color: #3b82f6; color: #e2e8f0; }}
.filter-btn.active {{ background: #1e40af; border-color: #3b82f6; color: #fff; }}
.services {{ max-width: 900px; margin: 1rem auto; }}
.svc {{ background: #1e293b; border: 1px solid #334155; border-radius: 8px;
        padding: 0.8rem 1rem; margin-bottom: 0.5rem; display: flex;
        justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 0.5rem;
        transition: border-color 0.15s; }}
.svc:hover {{ border-color: #475569; }}
.svc-left {{ flex: 1; min-width: 200px; }}
.svc-name {{ font-weight: 600; font-size: 1rem; color: #f8fafc; }}
.svc-urls {{ font-size: 0.8rem; margin-top: 0.3rem; }}
.svc-urls span {{ display: inline-block; margin-right: 1rem; }}
.svc-urls .label {{ color: #64748b; }}
.svc-urls a, .svc-urls .url {{ color: #38bdf8; cursor: pointer; text-decoration: none; }}
.svc-urls a:hover, .svc-urls .url:hover {{ text-decoration: underline; }}
.svc-right {{ display: flex; gap: 0.4rem; align-items: center; flex-wrap: wrap; }}
.badge {{ padding: 0.15rem 0.5rem; border-radius: 4px; font-size: 0.7rem;
          font-weight: 600; text-transform: uppercase; }}
.vlan-badge {{ background: #334155; color: #94a3b8; }}
.svc-notes {{ font-size: 0.75rem; color: #64748b; width: 100%; margin-top: 0.2rem; }}
.kubectl {{ font-family: monospace; font-size: 0.75rem; color: #a78bfa; cursor: pointer; }}
.kubectl:hover {{ text-decoration: underline; }}
.copy-toast {{ position: fixed; bottom: 1.5rem; right: 1.5rem; background: #22c55e;
               color: #fff; padding: 0.5rem 1rem; border-radius: 6px; font-size: 0.85rem;
               opacity: 0; transition: opacity 0.3s; pointer-events: none; z-index: 100; }}
.copy-toast.show {{ opacity: 1; }}
.hidden {{ display: none; }}
.count {{ text-align: center; color: #64748b; font-size: 0.8rem; padding: 0.5rem; }}
@media (max-width: 600px) {{
  .svc {{ flex-direction: column; align-items: flex-start; }}
  .svc-right {{ width: 100%; }}
  body {{ padding: 0.5rem; }}
  .header h1 {{ font-size: 1.4rem; }}
}}
</style>
</head>
<body>
<div class="header">
  <h1>FirbLab Service Directory</h1>
  <div class="subtitle">Auto-generated {generated_at} &mdash; Emergency reference for direct access when Traefik is down</div>
</div>
<div class="warning">
  <strong>Security:</strong> ForwardAuth services have <strong>no authentication</strong> when accessed by direct IP.
  Only UFW source restrictions protect them. Direct access bypasses Authentik SSO.
</div>
<div class="search-bar">
  <input type="text" id="search" placeholder="Search services, IPs, hostnames..." autofocus>
</div>
<div class="filters" id="filters">
  <button class="filter-btn active" data-filter="all">All</button>
  <button class="filter-btn" data-filter="vlan-10">Mgmt (10)</button>
  <button class="filter-btn" data-filter="vlan-20">Services (20)</button>
  <button class="filter-btn" data-filter="vlan-40">Storage (40)</button>
  <button class="filter-btn" data-filter="vlan-1">LAN (1)</button>
  <button class="filter-btn" data-filter="vlan-60">IoT (60)</button>
  <button class="filter-btn" data-filter="vlan-50">Security (50)</button>
  <button class="filter-btn" data-filter="k8s">K8s</button>
  <button class="filter-btn" data-filter="hetzner">Hetzner</button>
</div>
<div class="count" id="count"></div>
<div class="services" id="services"></div>
<div class="copy-toast" id="toast">Copied!</div>

<script>
const SERVICES = {json.dumps(js_services, indent=2)};

function authBadge(method) {{
  const colors = {{
    'native-oidc': '#22c55e', 'forwardauth': '#eab308', 'native-auth': '#3b82f6',
    'plex-account': '#e67e22', 'basic-auth': '#3b82f6', 'token': '#8b5cf6', 'none': '#ef4444'
  }};
  const labels = {{
    'native-oidc': 'OIDC', 'forwardauth': 'ForwardAuth', 'native-auth': 'Native',
    'plex-account': 'Plex', 'basic-auth': 'Basic', 'token': 'Token', 'none': 'None'
  }};
  const color = colors[method] || '#6b7280';
  const label = labels[method] || method;
  return `<span class="badge" style="background:${{color}}20;color:${{color}};border:1px solid ${{color}}50">${{label}}</span>`;
}}

function copyToClipboard(text) {{
  navigator.clipboard.writeText(text).then(() => {{
    const toast = document.getElementById('toast');
    toast.textContent = 'Copied: ' + text;
    toast.classList.add('show');
    setTimeout(() => toast.classList.remove('show'), 1500);
  }});
}}

function renderServices(filter, search) {{
  const container = document.getElementById('services');
  const countEl = document.getElementById('count');
  let filtered = SERVICES;

  if (filter !== 'all') {{
    if (filter === 'k8s') filtered = filtered.filter(s => s.category === 'k8s');
    else if (filter === 'hetzner') filtered = filtered.filter(s => s.category === 'hetzner');
    else {{
      const vlan = parseInt(filter.replace('vlan-', ''));
      filtered = filtered.filter(s => s.vlan === vlan);
    }}
  }}

  if (search) {{
    const q = search.toLowerCase();
    filtered = filtered.filter(s =>
      s.name.toLowerCase().includes(q) ||
      s.id.toLowerCase().includes(q) ||
      (s.proxy_url && s.proxy_url.toLowerCase().includes(q)) ||
      (s.direct_url && s.direct_url.toLowerCase().includes(q)) ||
      (s.notes && s.notes.toLowerCase().includes(q)) ||
      (s.kubectl_fallback && s.kubectl_fallback.toLowerCase().includes(q))
    );
  }}

  countEl.textContent = `${{filtered.length}} service${{filtered.length !== 1 ? 's' : ''}}`;

  container.innerHTML = filtered.map(s => {{
    let urls = '';
    if (s.proxy_url) {{
      urls += `<span><span class="label">Proxy:</span> <a href="${{s.proxy_url}}" class="url" onclick="event.preventDefault();copyToClipboard('${{s.proxy_url}}')">${{s.proxy_url.replace('https://','')}}</a></span>`;
    }}
    if (s.direct_url) {{
      urls += `<span><span class="label">Direct:</span> <span class="url" onclick="copyToClipboard('${{s.direct_url}}')">${{s.direct_url}}</span></span>`;
    }}
    if (s.kubectl_fallback) {{
      urls += `<br><span class="kubectl" onclick="copyToClipboard('${{s.kubectl_fallback}}')">${{s.kubectl_fallback}}</span>`;
    }}

    let vlanLabel = '';
    if (s.vlan !== null && s.vlan !== undefined) {{
      vlanLabel = `<span class="badge vlan-badge">VLAN ${{s.vlan}}</span>`;
    }} else if (s.category === 'hetzner') {{
      vlanLabel = `<span class="badge vlan-badge">Hetzner</span>`;
    }}

    let notes = [];
    if (s.insecure_backend) notes.push('self-signed cert');
    if (s.websocket) notes.push('WebSocket');
    if (s.aliases && s.aliases.length) notes.push('alias: ' + s.aliases.map(a => a.replace('https://','')).join(', '));
    if (s.auth_method === 'forwardauth') notes.push('no auth on direct IP');
    if (s.notes) notes.push(s.notes);
    const notesHtml = notes.length ? `<div class="svc-notes">${{notes.join(' &middot; ')}}</div>` : '';

    return `<div class="svc">
      <div class="svc-left">
        <div class="svc-name">${{s.name}}</div>
        <div class="svc-urls">${{urls}}</div>
        ${{notesHtml}}
      </div>
      <div class="svc-right">
        ${{vlanLabel}}
        ${{authBadge(s.auth_method)}}
      </div>
    </div>`;
  }}).join('');
}}

// Event listeners
let currentFilter = 'all';
document.querySelectorAll('.filter-btn').forEach(btn => {{
  btn.addEventListener('click', () => {{
    document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    currentFilter = btn.dataset.filter;
    renderServices(currentFilter, document.getElementById('search').value);
  }});
}});
document.getElementById('search').addEventListener('input', (e) => {{
  renderServices(currentFilter, e.target.value);
}});

// Initial render
renderServices('all', '');
</script>
</body>
</html>"""

    output_path = OUTPUT_DIR / "service-directory.html"
    with open(output_path, "w") as f:
        f.write(html)
    print(f"  Written: {output_path}")


# =============================================================================
# Main
# =============================================================================

def main():
    print("FirbLab Service Directory Generator")
    print("=" * 50)

    # Verify data sources exist
    for path, label in [
        (TRAEFIK_DEFAULTS, "Traefik backends"),
        (INVENTORY, "Ansible inventory"),
    ]:
        if not path.exists():
            print(f"ERROR: {label} not found: {path}")
            sys.exit(1)

    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    print(f"\nGenerating catalog ({generated_at})...")

    services = build_catalog()
    print(f"  Found {len(services)} services")

    print("\nRendering outputs...")
    render_yaml(services, generated_at)
    render_markdown(services, generated_at)
    render_html(services, generated_at)

    print(f"\nDone. {len(services)} services documented.")


if __name__ == "__main__":
    main()
