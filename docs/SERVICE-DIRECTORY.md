# FirbLab Service Directory

> **AUTO-GENERATED** — do not edit manually.
> Regenerate: `python scripts/generate-service-directory.py`
> Last generated: 2026-02-23 16:25:42 UTC

---

## Emergency Direct Access

When **Standalone Traefik** (`10.0.10.17`) is down, use the **Direct URL** column.
When **K8s Traefik** (`10.0.20.220`) is down, use the `kubectl port-forward` commands.

## Security Warning

**ForwardAuth services have NO native authentication when accessed by direct IP.**
These services are protected only by UFW source restrictions (management/LAN/services networks).
Direct access bypasses Authentik SSO entirely.

## VLAN 10 -- Management

| Service | Proxy URL | Direct URL | Auth | Notes |
|---------|-----------|------------|------|-------|
| Authentik | https://auth.home.example-lab.org | http://10.0.10.16:9000 | Native | WebSocket |
| Backrest | https://backrest.home.example-lab.org | http://10.0.10.18:9898 | ForwardAuth | **no auth on direct IP** |
| GitLab | https://gitlab.home.example-lab.org | http://10.0.10.50:80 | OIDC | WebSocket; alias: git.home.example-lab.org |
| Proxmox (lab-01) | https://pve-01.home.example-lab.org | https://10.0.10.42:8006 | Native | self-signed cert; WebSocket |
| Proxmox (lab-02) | https://pve-02.home.example-lab.org | https://10.0.10.2:8006 | Native | self-signed cert; WebSocket |
| Proxmox (lab-03) | https://pve-03.home.example-lab.org | https://10.0.10.3:8006 | Native | self-signed cert; WebSocket |
| Proxmox (lab-04) | https://pve-04.home.example-lab.org | https://10.0.10.4:8006 | Native | self-signed cert; WebSocket |
| Proxmox Backup Server | https://pbs.home.example-lab.org | https://10.0.10.15:8007 | ForwardAuth | self-signed cert; **no auth on direct IP** |

## VLAN 20 -- Services

| Service | Proxy URL | Direct URL | Auth | Notes |
|---------|-----------|------------|------|-------|
| Actual Budget | https://actualbudget.home.example-lab.org | http://10.0.20.16:5006 | OIDC | WebSocket |
| ArchiveBox | https://archivebox.home.example-lab.org | http://10.0.20.20:8082 | ForwardAuth | **no auth on direct IP** |
| BookStack | https://bookstack.home.example-lab.org | http://10.0.20.20:8083 | ForwardAuth | **no auth on direct IP** |
| FileBrowser | https://archive.home.example-lab.org | http://10.0.20.20:8080 | ForwardAuth | **no auth on direct IP** |
| FoundryVTT | https://foundryvtt.home.example-lab.org | http://10.0.20.12:30000 | ForwardAuth | WebSocket; **no auth on direct IP** |
| Ghost Blog | https://ghost.home.example-lab.org | http://10.0.20.10:2368 | ForwardAuth | **no auth on direct IP** |
| Kiwix | https://kiwix.home.example-lab.org | http://10.0.20.20:8081 | ForwardAuth | **no auth on direct IP** |
| Mealie | https://mealie.home.example-lab.org | http://10.0.20.13:9000 | OIDC |  |
| NetBox | https://netbox.home.example-lab.org | http://10.0.20.14:8080 | OIDC |  |
| Open WebUI | https://openwebui.home.example-lab.org | http://10.0.20.18:3000 | OIDC | WebSocket |
| PatchMon | https://patchmon.home.example-lab.org | http://10.0.20.15:3000 | OIDC | WebSocket |
| Roundcube Webmail | https://mail.home.example-lab.org | http://10.0.20.11:8080 | ForwardAuth | **no auth on direct IP** |
| Stirling PDF | https://stirlingpdf.home.example-lab.org | http://10.0.20.20:8084 | ForwardAuth | **no auth on direct IP** |
| Vaultwarden | https://vaultwarden.home.example-lab.org | http://10.0.20.19:8000 | OIDC | WebSocket |
| Wallabag | https://wallabag.home.example-lab.org | http://10.0.20.20:8085 | ForwardAuth | **no auth on direct IP** |
| n8n | https://n8n.home.example-lab.org | http://10.0.20.18:5678 | ForwardAuth | WebSocket; **no auth on direct IP** |

## VLAN 40 -- Storage

| Service | Proxy URL | Direct URL | Auth | Notes |
|---------|-----------|------------|------|-------|
| Immich | https://immich.home.example-lab.org | http://10.0.40.2:30041 | Native |  |
| Linkwarden | https://linkwarden.home.example-lab.org | http://10.0.40.2:30243 | Native |  |
| Paperless-ngx | https://paperless.home.example-lab.org | http://10.0.40.2:30070 | Native |  |
| Plex | https://plex.home.example-lab.org | http://10.0.40.2:32400 | Plex | WebSocket |
| Portracker | https://portracker.home.example-lab.org | http://10.0.40.2:30233 | Native |  |
| TrueNAS | https://truenas.home.example-lab.org | https://10.0.40.2 | Native | self-signed cert; WebSocket |

## VLAN 60 -- IoT

| Service | Proxy URL | Direct URL | Auth | Notes |
|---------|-----------|------------|------|-------|
| Home Assistant | https://homeassistant.home.example-lab.org | http://10.0.60.10:8123 | ForwardAuth | WebSocket; **no auth on direct IP** |

## K8s Services (MetalLB VIP 10.0.20.220)

No direct access — services run behind ClusterIP. Use `kubectl port-forward` when K8s Traefik is down.

| Service | Proxy URL | kubectl Fallback | Auth | Notes |
|---------|-----------|------------------|------|-------|
| ArgoCD | https://argocd.home.example-lab.org | `kubectl port-forward svc/argocd-server -n argocd 8080:443` | OIDC | GitOps deployment dashboard |
| Grafana | https://grafana.home.example-lab.org | `kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80` | OIDC | Monitoring dashboards |
| Headlamp | https://headlamp.home.example-lab.org | `kubectl port-forward svc/headlamp -n headlamp 8080:80` | OIDC | Kubernetes web dashboard |
| Longhorn | https://longhorn.home.example-lab.org | `kubectl port-forward svc/longhorn-frontend -n longhorn-system 8080:80` | None | Distributed storage UI |
| SonarQube | https://sonarqube.home.example-lab.org | `kubectl port-forward svc/sonarqube-sonarqube -n sonarqube 9000:9000` | Native | Code quality analysis |

## Hetzner Services (WireGuard Tunnel 10.8.0.1)

All Hetzner services require an active WireGuard tunnel. If WireGuard is down, these are unreachable from the homelab.

| Service | Public URL | Tunnel Direct URL | Auth | Notes |
|---------|-----------|-------------------|------|-------|
| Hetzner Traefik | N/A | http://10.8.0.1:8888 | Basic | Reverse proxy dashboard (WireGuard required) |
| AdGuard Home | https://adguard.example-lab.org | http://10.8.0.1:3000 | Basic | DNS ad blocker (WireGuard required) |
| Uptime Kuma | https://status.example-lab.org | http://10.8.0.1:3001 | Native | Service monitoring (WireGuard required) |
| Gotify | https://gotify.example-lab.org | http://10.8.0.1:8080 | Native | Push notifications (WireGuard required) |

## Hetzner Honeypot (lab-honeypot)

Dedicated cybersecurity deception server. All honeypot ports are intentionally public. Real SSH is on port 2222 (restricted). Logs ship to homelab Loki via WireGuard client tunnel through the gateway.

| Service | Public Port(s) | Protocol | Purpose | Notes |
|---------|---------------|----------|---------|-------|
| Cowrie | 22 (SSH), 23 (Telnet) | TCP | Interactive SSH/Telnet honeypot | Captures credentials, commands, uploaded files |
| OpenCanary | 21 (FTP), 3306 (MySQL), 3389 (RDP), 5900 (VNC), 6379 (Redis) | TCP | Multi-protocol honeypot | Alerts on connection attempts |
| Dionaea | 445 (SMB), 5060 (SIP/UDP), 8080 (HTTP), 8443 (HTTPS) | TCP/UDP | Malware capture honeypot | Traps exploit payloads |
| Endlessh | 2223 | TCP | SSH tarpit | Holds connections open indefinitely |
| Grafana Alloy | N/A (outbound) | -- | Log shipper | Ships to Loki via WireGuard tunnel |

> **DNS:** honeypot.example-lab.org | **IP:** 203.0.113.11 | **Managed by:** Terraform Layer 06 + Ansible `honeypot-deploy.yml`

## Bare-Metal Services (No Proxy)

| Service | Direct URL | Auth | Notes |
|---------|------------|------|-------|
| Scanopy | http://10.0.4.20:60072 | Native | Network scanner (lab-08 RPi4) |
| NUT UPS Server | 10.0.4.20:3493 (TCP, not HTTP) | None | UPS monitoring daemon (lab-08 RPi4). No web UI. |

## Direct Access (Own TLS, No Proxy)

| Service | URL | Auth | Notes |
|---------|-----|------|-------|
| Vault | https://10.0.10.10:8200 | Token | Own CA cert. Export VAULT_CACERT=~/.lab/tls/ca/ca.pem |

