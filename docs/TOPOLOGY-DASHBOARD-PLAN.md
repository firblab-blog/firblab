# FirbLab OS — Topology Dashboard Feature Plan

**Status:** Planning (not started)
**FirbLab OS Spec Reference:** Section 15, UI Functional Domain #1 — Topology Graph
**Created:** 2026-02-19

---

## 1. Vision

An interactive, real-time infrastructure topology dashboard — the visual centerpiece of FirbLab OS. Like homelab-hub's Cytoscape.js map, but **zero manual entry**. Every node, edge, VLAN grouping, and health status is pulled live from APIs that already exist in the infrastructure stack.

This is not a standalone dashboard. It is a **first-class feature of the FirbLab OS control plane UI**, rendering the infrastructure graph that the deterministic core (Layer 1) already models internally.

---

## 2. Data Sources (All Existing)

### 2.1 NetBox — Authoritative Inventory (Primary)

**API:** `http://10.0.20.14:8080/api/`
**Auth:** API token (`secret/services/netbox` → `api_token`)
**Already proven:** `netbox-to-d2.py` and `scanopy-netbox-sync.py` consume this API today.

| Endpoint | Data | Graph Use |
|----------|------|-----------|
| `/api/dcim/devices/` | Physical hardware (Proxmox nodes, switches, RPis, NAS, etc.) | Top-level nodes |
| `/api/virtualization/virtual-machines/` | VMs and LXCs with cluster/host assignment | Child nodes under hosts |
| `/api/ipam/vlans/` | VLAN definitions (ID, name, subnet) | Grouping containers, color coding |
| `/api/ipam/ip-addresses/` | IP assignments linked to interfaces | Node labels, tooltips |
| `/api/dcim/interfaces/` | Physical NIC interfaces + port assignments | Edge data (device → switch) |
| `/api/virtualization/interfaces/` | VM/LXC virtual interfaces | Edge data (VM → host) |
| `/api/dcim/cables/` | Physical cable connections (device ↔ switch) | Physical topology edges |
| `/api/dcim/sites/` | Site container | Root grouping |
| `/api/extras/tags/` | Tags (terraform-managed, scanopy-discovered) | Visual markers |

**Key relationships already modeled in NetBox (seeded by `netbox-seed.py` + Terraform Layer 08):**
- Devices → Interfaces → IPs
- VMs → Cluster → Host device
- Cables → Device A interface ↔ Device B interface
- IPs → VLAN membership

### 2.2 Prometheus — Live Health & Metrics Overlay

**API:** `http://10.0.20.220:9090/api/v1/` (via MetalLB VIP, K8s Traefik)
**Auth:** None required (internal network; FirbLab OS control node will be on Management VLAN)
**Already deployed:** Prometheus + node-exporter on RKE2 cluster.

| Query | Data | Graph Use |
|-------|------|-----------|
| `up{job="node-exporter"}` | Host alive/dead | Node border color (green/red) |
| `node_cpu_seconds_total` | CPU utilization | Tooltip, optional heat map |
| `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes` | RAM usage % | Tooltip, size scaling |
| `node_filesystem_avail_bytes` | Disk free | Tooltip, warning indicator |
| `node_network_receive_bytes_total` | Network throughput | Edge thickness + animated traffic flow |
| `container_cpu_usage_seconds_total` | Per-container CPU (K8s) | K8s workload overlay |

**Note:** Prometheus only covers hosts with node-exporter. Bare-metal hosts without it (TrueNAS, HAOS, lab-09) will show inventory-only (from NetBox) without live metrics. Future: push gateway or custom exporters.

### 2.3 Scanopy — Discovered Devices (Audit/Diff Layer)

**API:** `http://10.0.4.20:60072/api/v1/`
**Auth:** Session cookie (email/password from `secret/services/scanopy`)
**Already proven:** `scanopy-netbox-sync.py` consumes this API daily.

| Endpoint | Data | Graph Use |
|----------|------|-----------|
| `GET /api/v1/hosts` | All discovered hosts (hostname, IPs, OS, status) | "Unknown device" indicators |
| `GET /api/v1/interfaces` | IP + MAC per host | MAC address display, duplicate detection |
| `GET /api/v1/subnets` | Scanned subnets (VLAN-aligned) | Scan coverage overlay |

**Unique value:** Scanopy discovers devices that may NOT be in NetBox. The dashboard can show:
- **Managed (NetBox + Scanopy):** Green — known and discovered
- **Managed only (NetBox, not discovered):** Yellow — in inventory but scanner can't see it (wrong VLAN? powered off?)
- **Discovered only (Scanopy, not in NetBox):** Red — unknown device on the network (security alert)

This diff view is a killer feature no existing dashboard provides.

### 2.4 FirbLab OS Model Engine (Future — Phase 2+)

When the deterministic core is built, the topology dashboard reads directly from the model engine's infrastructure graph rather than assembling it from multiple APIs. The model engine becomes the authoritative aggregator.

Until then, the dashboard is a standalone read-only SPA that queries the three APIs above.

---

## 3. Architecture

### 3.1 Phase 1: Standalone SPA (Pre-Control Plane)

```
┌─────────────────────────────────────────────────────┐
│  Browser (SPA)                                       │
│  ┌─────────────────────────────────────────────────┐ │
│  │  Cytoscape.js Graph + Controls                  │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────────────┐│ │
│  │  │ Map View │ │Tree View │ │ Diff/Audit View  ││ │
│  │  └──────────┘ └──────────┘ └──────────────────┘│ │
│  └──────────────────┬──────────────────────────────┘ │
│                     │ fetch()                        │
└─────────────────────┼────────────────────────────────┘
                      │
       ┌──────────────┼──────────────┐
       │              │              │
       ▼              ▼              ▼
   NetBox API    Prometheus API   Scanopy API
  (inventory)     (metrics)      (discovery)
```

**No backend.** The SPA makes CORS-enabled fetch() calls directly to the three APIs. All rendering and data merging happens client-side.

**CORS consideration:** NetBox and Prometheus both support CORS headers. Scanopy may need a small CORS config tweak. Alternatively, the standalone Traefik proxy (10.0.10.17) can add CORS headers at the proxy layer.

**Deployment:** Static files (HTML/CSS/JS) served from the control node, or from any lightweight container. Behind Traefik + Authentik ForwardAuth for authentication.

### 3.2 Phase 2: FirbLab OS Web UI Module

When the FirbLab OS control plane is built, the topology dashboard becomes a route/module within its Web UI (spec section 15). The control plane's API server acts as the aggregation backend, removing the need for browser-to-API CORS:

```
Browser → FirbLab OS UI → /api/topology → Model Engine → NetBox + Prometheus + Scanopy
```

The Cytoscape.js frontend code is reused almost entirely — only the data fetch layer changes (from direct API calls to a single `/api/topology` endpoint).

---

## 4. Graph Data Model

### 4.1 Node Types

| Type | Source | Visual | Icon Strategy |
|------|--------|--------|---------------|
| `switch` | NetBox device (role: switch) | Hexagon | Network switch icon |
| `router` | NetBox device (role: router) | Hexagon | Router icon |
| `proxmox-host` | NetBox device (role: server-proxmox) | Large rounded rect | Server icon |
| `bare-metal` | NetBox device (role: varies) | Rounded rect | Device-specific |
| `vm` | NetBox VM (type: vm) | Rounded rect (small) | OS icon or service logo |
| `lxc` | NetBox VM (type: lxc, or tag) | Rounded rect (small, dashed border) | Container icon |
| `k8s-workload` | Prometheus / ArgoCD (future) | Circle cluster | K8s icon |
| `service` | NetBox VM services / tags | Badge on parent | Service logo |
| `unknown` | Scanopy only (not in NetBox) | Diamond (warning) | ⚠️ |

### 4.2 Edge Types

| Type | Source | Visual |
|------|--------|--------|
| `physical-cable` | NetBox cables | Solid thick line |
| `host-vm` | NetBox VM → cluster host | Solid thin line |
| `vlan-member` | NetBox IP → VLAN | Colored by VLAN (used for grouping) |
| `uplink` | NetBox cable (switch → router) | Thick line with arrow |
| `api-dependency` | Manual or future model | Dashed line |

### 4.3 VLAN Grouping

Nodes are grouped into VLAN containers (colored backgrounds), matching the homelab-hub screenshot style:

| VLAN | Color | Label |
|------|-------|-------|
| 1 (Default) | Light gray | Default/LAN |
| 10 (Management) | Light blue | Management |
| 20 (Services) | Light orange | Services |
| 30 (DMZ) | Light pink | DMZ |
| 40 (Storage) | Light purple | Storage |
| 50 (Security) | Light yellow | Security |
| 60 (IoT) | Light green | IoT |

---

## 5. Views

### 5.1 Map View (Primary)

Interactive Cytoscape.js graph. Drag-and-drop nodes, zoom, pan. VLAN-colored grouping containers. Edges show physical and logical relationships.

**Layout options:**
- **Hierarchical (default):** Router at top → switches → hosts → VMs → services (like homelab-hub's depth-first layout)
- **Force-directed:** Organic clustering (good for discovery/audit view)
- **Grid:** Organized by VLAN columns
- **User-saved layouts:** Persist node positions to localStorage (or control plane DB in Phase 2)

### 5.2 Tree View

Collapsible hierarchical view (like homelab-hub's Tree View):
```
gw-01 (Router)
├── switch-01 (Closet)
│   ├── lab-01 (10.0.10.42) — 🟢 CPU: 34% RAM: 71%
│   │   ├── rke2-server-1 (10.0.20.40) — 🟢
│   │   ├── rke2-server-2 (10.0.20.41) — 🟢
│   │   ├── rke2-server-3 (10.0.20.42) — 🟢
│   │   ├── rke2-agent-1 (10.0.20.50) — 🟢
│   │   ├── rke2-agent-2 (10.0.20.51) — 🟢
│   │   ├── rke2-agent-3 (10.0.20.52) — 🟢
│   │   └── ai-gpu (10.0.20.18) — 🟢 GPU: 12%
│   ├── lab-04 (10.0.10.4) — 🟢 CPU: 8% RAM: 42%
│   │   ├── netbox (10.0.20.14) — 🟢
│   │   ├── pbs (10.0.10.15) — 🟢
│   │   ├── authentik (10.0.10.16) — 🟢
│   │   └── traefik-proxy (10.0.10.17) — 🟢
│   └── TrueNAS (10.0.40.2) — ⚪ (no metrics)
├── switch-02 (Minilab)
│   ├── lab-02 (10.0.10.2) — 🟢
│   │   ├── gitlab (10.0.10.50) — 🟢
│   │   ├── gitlab-runner (10.0.10.51) — 🟢
│   │   └── vault-2 (10.0.50.2) — 🟢
│   ├── vault-1 / Mac Mini (10.0.10.10) — 🟢
│   └── vault-3 / RPi5 CM5 (10.0.10.13) — 🟢
├── switch-03 (Rackmate)
│   ├── lab-09 / Archive (10.0.20.20) — 🟢
│   └── HAOS RPi5 (10.0.60.10) — 🟢
└── lab-08 (10.0.4.20) — Direct
    └── Scanopy + NUT
```

### 5.3 Diff/Audit View (Unique Feature)

Side-by-side comparison:

| Status | NetBox | Scanopy | Action |
|--------|--------|---------|--------|
| 🟢 Managed | ✅ lab-01 (10.0.10.42) | ✅ Discovered (MAC: aa:bb:cc:dd:ee:ff) | — |
| 🟡 Stale | ✅ roundcube (10.0.20.11) | ❌ Not discovered | Investigate (powered off? wrong VLAN?) |
| 🔴 Unknown | ❌ Not in NetBox | ✅ 10.0.20.178 (MAC: xx:yy:zz) | Security alert — unmanaged device |

This view is the **security radar** of the homelab. Scanopy's multi-VLAN scanner finds everything on the wire. NetBox is the authoritative inventory. Mismatches = action items.

### 5.4 Metrics Overlay (Toggle)

When enabled, Prometheus data overlays onto the graph:
- **Node borders:** Green (healthy), yellow (>80% resource), red (down/unreachable)
- **Tooltips:** CPU%, RAM%, disk free, uptime, last scrape
- **Edge thickness:** Proportional to network throughput between nodes
- **Heat map mode:** Nodes sized/colored by resource utilization

### 5.5 Live Traffic Flow (Inspired by UniFi Topology)

UniFi's topology view shows animated traffic flowing between devices — it's one of the most visually satisfying features of the UniFi UI. We replicate this with Prometheus network metrics:

- **Animated edge particles:** Small dots flowing along edges, speed/density proportional to `node_network_receive_bytes_total` rate between connected hosts
- **Bidirectional flow:** Separate particles for TX/RX, different colors (e.g., blue upstream, orange downstream)
- **Throughput labels:** Optional Mbps/Gbps labels on edges, updated every 30s
- **Cytoscape.js implementation:** Use `cytoscape-edge-axtensions` or custom canvas overlay to draw animated particles along edge paths. Alternatively, the `cytoscape.js-edge-bend-editing` extension or a lightweight custom animation loop using `requestAnimationFrame`.

**Data source:** Prometheus `rate(node_network_receive_bytes_total{device="eth0"}[1m])` per host. Map source→destination via NetBox cable data (interface A on device A ↔ interface B on device B).

**Why this beats UniFi's version:**
- UniFi only shows devices it knows about (UniFi-adopted devices + direct clients). Your topology shows EVERYTHING — VMs, K8s nodes, bare-metal, cross-VLAN traffic
- UniFi gets clunky with 20+ devices because it renders them all in a flat row with no grouping. Our VLAN containers + collapsible host groups handle density gracefully
- UniFi's topology is read-only from UniFi's perspective. Ours cross-references NetBox + Scanopy + Prometheus

### 5.6 Density Management (Solving the UniFi Clunkiness Problem)

The core UX problem with UniFi's topology (and any graph with many nodes) is that it renders everything flat. With 30+ devices, the view becomes an unreadable horizontal scroll.

Solutions built into this design:

1. **VLAN compound nodes** — Devices are grouped inside their VLAN container. Collapse a VLAN to hide its children → the entire Services VLAN with 15 VMs becomes one node showing "Services (15 devices, 12 healthy)"
2. **Host-level collapsing** — Click a Proxmox host to expand/collapse its VMs. lab-01 with 7 VMs can show as one node or expand to show all children
3. **Zoom-semantic detail** — Zoomed out: show only physical hosts + health indicators. Zoomed in: show VMs, services, ports, metrics. Like a geographic map with detail levels
4. **VLAN filtering** — Toggle VLANs on/off in the legend (like homelab-hub's Networks panel). Show only Management + Services, hide DMZ/Storage/IoT
5. **Search with focus** — Search for a node → graph zooms to it and highlights its connections, dimming everything else
6. **Saved views** — Save named layout configurations: "Physical overview" (collapsed), "Full detail" (expanded), "Security audit" (Scanopy diff highlighted)

---

## 6. Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| Graph rendering | **Cytoscape.js** | Proven (homelab-hub uses it), interactive, extensible, excellent layout algorithms |
| UI framework | **Svelte** (or vanilla JS for Phase 1) | Lightweight, reactive, fast. Svelte if this becomes a FirbLab OS UI module. Vanilla JS for standalone prototype. |
| Styling | **Pico CSS** + custom dark theme | Minimal, dark-mode native (matches homelab-hub aesthetic) |
| HTTP client | **fetch()** | Native browser API, no dependencies |
| Build | **Vite** (if Svelte) or **none** (if vanilla) | Zero-config, fast HMR |
| Deployment | **Static files in Docker** (nginx-alpine or served by control node) | <10 MB image, behind Traefik + ForwardAuth |

### Why Not a Backend?

Phase 1 is read-only. All three APIs are accessible from the browser (same network, CORS-enabled via Traefik). A backend API aggregation layer adds:
- Another service to maintain
- Another failure point
- Another container
- No benefit for read-only data

Phase 2 (FirbLab OS control plane) provides the backend naturally — the model engine is the aggregator.

---

## 7. Data Fetching Strategy

### 7.1 Initial Load

On page load, fetch in parallel:

```javascript
const [devices, vms, vlans, ips, cables, interfaces, vmInterfaces] = await Promise.all([
  netbox('/api/dcim/devices/?limit=0'),
  netbox('/api/virtualization/virtual-machines/?limit=0'),
  netbox('/api/ipam/vlans/?limit=0'),
  netbox('/api/ipam/ip-addresses/?limit=0'),
  netbox('/api/dcim/cables/?limit=0'),
  netbox('/api/dcim/interfaces/?limit=0'),
  netbox('/api/virtualization/interfaces/?limit=0'),
]);
```

Then merge into the Cytoscape.js graph model.

### 7.2 Prometheus Overlay (Async)

After the graph renders, fetch metrics in the background:

```javascript
// Batch query for all node-exporter targets
const health = await prometheus('/api/v1/query?query=up{job="node-exporter"}');
const cpu = await prometheus('/api/v1/query?query=100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)');
const ram = await prometheus('/api/v1/query?query=(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100');
```

Map `instance` labels to NetBox IPs → update node styles.

### 7.3 Scanopy Diff (On-Demand)

Scanopy data loads only when the user opens the Diff/Audit view (it requires auth and is slower):

```javascript
const scanopyHosts = await scanopy('/api/v1/hosts');
const scanopyInterfaces = await scanopy('/api/v1/interfaces');
// Merge by IP address against NetBox data
```

### 7.4 Auto-Refresh

- **Prometheus metrics:** Poll every 30s (configurable)
- **NetBox inventory:** Poll every 5 min (inventory rarely changes)
- **Scanopy diff:** Manual refresh only (scans run on schedule)

---

## 8. Graph Construction Algorithm

```
1. Create VLAN compound nodes (containers)
2. For each NetBox device:
   a. Determine VLAN from primary IP → prefix → VLAN assignment
   b. Create node inside VLAN container
   c. Add metadata (role, IPs, tags)
3. For each NetBox VM:
   a. Find parent host (cluster → device)
   b. Create node, add host→VM edge
   c. Determine VLAN from IP
4. For each NetBox cable:
   a. Create edge between device interfaces
5. For each Prometheus target:
   a. Match instance IP to NetBox node
   b. Apply health styling (border color)
   c. Inject metrics into tooltip data
6. Apply layout algorithm
7. Restore saved positions (if any)
```

---

## 9. FirbLab OS Integration Points

This feature maps directly to the FIRBLAB-OS.md (v0.3) specification:

| Spec Section | Integration |
|--------------|-------------|
| §3 Layered Architecture | Dashboard is a **Layer 2 (Operational Intelligence)** consumer — reads, never writes |
| §5 Declarative Model | Phase 2: reads from Model Engine's infrastructure graph instead of raw APIs |
| §6 State Model | Visualizes all four states: desired (Git model), recorded (Terraform state), actual (Prometheus + Scanopy) |
| §7 Reconciliation | Diff/Audit view IS the visual reconciliation — shows drift between inventory and reality |
| §13 Capacity Planning | Metrics overlay feeds the Capacity Dashboard (spec §15.5) |
| §15 UI Domains | This IS domain #1 (Topology Graph) + feeds into #5 (Capacity Dashboard) |
| §16 Audit | All API queries are logged; Scanopy diff alerts are audit events |

### Control Plane API Endpoint (Phase 2)

```
GET /api/topology
  → Returns merged graph model:
    {
      nodes: [...],       // NetBox devices + VMs + Scanopy unknowns
      edges: [...],       // Cables + host→VM + VLAN membership
      vlans: [...],       // Grouping containers
      metrics: {...},     // Prometheus health overlay
      diff: {...}         // NetBox ↔ Scanopy reconciliation
    }
```

The frontend Cytoscape.js code remains identical — only the data source URL changes.

---

## 10. Security

| Concern | Mitigation |
|---------|-----------|
| No authentication on dashboard | Traefik + Authentik ForwardAuth (same pattern as Ghost, n8n, Archive) |
| API tokens in browser | **Never.** Tokens are injected server-side. Phase 1: Traefik proxy adds auth headers. Phase 2: control plane backend holds tokens. |
| CORS exposure | Traefik reverse proxy scopes CORS to `*.home.example-lab.org` origin only |
| Read-only enforcement | Dashboard makes only GET requests. No write endpoints consumed. |
| Scanopy credentials | Phase 1: proxy via Traefik with auth injection. Phase 2: control plane backend handles Scanopy auth server-side. |

### API Token Injection (Phase 1)

Instead of shipping tokens to the browser, use Traefik middleware to inject auth headers:

```yaml
# Traefik dynamic config — proxy NetBox API with token injection
http:
  routers:
    topology-netbox-proxy:
      rule: "Host(`topology.home.example-lab.org`) && PathPrefix(`/netbox-api/`)"
      middlewares: [authentik-forwardauth, netbox-auth-inject, strip-prefix-netbox]
      service: netbox-backend

  middlewares:
    netbox-auth-inject:
      headers:
        customRequestHeaders:
          Authorization: "Token {{ netbox_api_token }}"
    strip-prefix-netbox:
      stripPrefix:
        prefixes: ["/netbox-api"]

  services:
    netbox-backend:
      loadBalancer:
        servers:
          - url: "http://10.0.20.14:8080"
```

The SPA calls `/netbox-api/api/dcim/devices/` → Traefik strips the prefix, injects the NetBox token, proxies to NetBox. The browser never sees the token.

Same pattern for Prometheus and Scanopy.

---

## 11. Deployment Plan

### Phase 1: Standalone SPA (Deploy on RPi 5 or existing LXC)

| Step | Action | Tool |
|------|--------|------|
| 1 | Build the SPA (Cytoscape.js + CSS + fetch logic) | Local dev |
| 2 | Create GitLab repo `infrastructure/firblab-topology` | Terraform Layer 03 |
| 3 | Dockerize (nginx-alpine serving static files) | Dockerfile |
| 4 | Add to Terraform Layer 05 or deploy on existing host | Terraform or Ansible |
| 5 | Add Traefik backend (`topology.home.example-lab.org`) | Ansible traefik-proxy-deploy.yml |
| 6 | Add DNS record | Terraform Layer 00 |
| 7 | Add ForwardAuth provider in Authentik | Terraform Layer 07 |
| 8 | Add API proxy routes (NetBox, Prometheus, Scanopy) | Ansible traefik-proxy-deploy.yml |
| 9 | Backup (SQLite-free — just static files + localStorage) | N/A (code in GitLab) |

**Resource requirements:** ~20 MB RAM (nginx serving static files). Could run on literally any machine. Recommend: LXC on lab-04 (has headroom) or container on lab-03. RPi 5 is overkill but available.

### Phase 2: FirbLab OS UI Module

When the control plane is built, the SPA becomes a module:
1. Move Cytoscape.js code into the FirbLab OS frontend
2. Replace direct API fetches with `/api/topology` control plane endpoint
3. Control plane backend handles all API auth + data merging
4. Remove Traefik proxy routes (no longer needed)

---

## 12. File Structure (Phase 1)

```
firblab-topology/
├── index.html              # Entry point
├── css/
│   └── style.css           # Dark theme, Pico CSS base
├── js/
│   ├── app.js              # Main init, view switching
│   ├── graph.js            # Cytoscape.js graph construction + layouts
│   ├── fetcher.js          # API client (NetBox, Prometheus, Scanopy)
│   ├── merger.js           # Data merging + diff logic
│   ├── views/
│   │   ├── map.js          # Map view (Cytoscape.js)
│   │   ├── tree.js         # Tree view (collapsible)
│   │   └── diff.js         # Diff/Audit view (table)
│   └── config.js           # API endpoints, refresh intervals, VLAN colors
├── icons/                  # Service logos (SVG)
├── Dockerfile              # nginx-alpine + static files
├── docker-compose.yml      # Dev/prod deploy
└── README.md
```

**Estimated size:** ~500-800 lines of JS, ~200 lines of CSS. Under 1,000 lines total.

---

## 13. Implementation Phases

### Phase 1a: Core Graph (MVP)
- [ ] NetBox → Cytoscape.js graph (devices, VMs, cables, VLANs)
- [ ] VLAN compound nodes with color coding
- [ ] Hierarchical layout (router → switches → hosts → VMs)
- [ ] Node click → detail tooltip (IP, role, VLAN, tags)
- [ ] Dark theme (Pico CSS base)
- [ ] Map View + Tree View toggle
- [ ] Dockerize + deploy behind Traefik/ForwardAuth

### Phase 1b: Live Metrics Overlay
- [ ] Prometheus health check (up/down → node border color)
- [ ] CPU/RAM metrics in tooltips
- [ ] Auto-refresh (30s metrics, 5m inventory)
- [ ] Heat map mode toggle
- [ ] Live traffic flow animation on edges (UniFi-inspired)
- [ ] Edge throughput labels (Mbps/Gbps)

### Phase 1c: Audit/Diff View
- [ ] Scanopy API integration (via Traefik proxy)
- [ ] NetBox ↔ Scanopy reconciliation logic
- [ ] Diff table view (managed / stale / unknown)
- [ ] Unknown device alert indicators on map

### Phase 1d: Polish
- [ ] Service logo icons (SVG)
- [ ] User-saved node positions (localStorage)
- [ ] Multiple layout algorithms (hierarchical, force-directed, grid)
- [ ] Collapsible VLAN containers + host-level expand/collapse
- [ ] Zoom-semantic detail levels (physical overview ↔ full detail)
- [ ] VLAN toggle filtering (legend checkboxes)
- [ ] Search with focus (zoom + highlight connections)
- [ ] Saved named views ("Physical overview", "Full detail", "Security audit")
- [ ] Search/filter (by name, IP, VLAN, status)
- [ ] Keyboard shortcuts
- [ ] Export graph as PNG/SVG

### Phase 2: FirbLab OS Integration
- [ ] Move into FirbLab OS frontend codebase
- [ ] `/api/topology` backend endpoint
- [ ] Model Engine integration (replace raw API calls)
- [ ] Drift visualization (desired vs actual state diff)
- [ ] Agent proposal overlay (show proposed changes on graph)
- [ ] Historical state comparison (time-travel topology)

---

## 14. Why This Is a Killer Feature

1. **Zero manual entry.** Every homelab dashboard (homelab-hub, homepage, homarr) requires you to manually add your devices. This is populated automatically from your infrastructure-as-code pipeline.

2. **Live health overlay.** Not just a static inventory — real-time Prometheus metrics make it operational, not decorative.

3. **Security radar.** The Scanopy diff view answers "is anything on my network that shouldn't be?" — a question no existing dashboard even asks.

4. **Portable.** When this moves into FirbLab OS, every user who deploys the platform gets this dashboard automatically. Their NetBox, their Prometheus, their Scanopy — all feeding the same graph. No configuration needed beyond what site.yml already provides.

5. **Resume material.** This is a portfolio-grade feature that demonstrates: API integration, real-time data visualization, security monitoring, infrastructure-as-code principles, and full-stack development. Directly relevant to the "Production-Grade Homelab Infrastructure" project on the resume.

---

## 15. Open Questions

1. **Deploy target for Phase 1:** LXC on lab-04 (minimal resources, near NetBox), or dedicated container on lab-03? Or just serve from Traefik proxy LXC itself (it's nginx-based already)?
2. **Svelte or vanilla JS for Phase 1?** Vanilla keeps it dependency-free and trivially portable. Svelte makes it easier to build into FirbLab OS later. Given Phase 2 plans, Svelte is probably the right call even for Phase 1.
3. **Scanopy CORS:** Does Scanopy's Flask backend allow CORS out of the box, or do we need the Traefik proxy approach? Likely Traefik proxy either way (for token injection security).
4. **K8s workload visibility:** Do we show individual pods/deployments, or just the RKE2 nodes? Phase 1: nodes only. Phase 2: optional ArgoCD-aware workload overlay.
5. **Graph persistence:** Save layout positions server-side (API) or client-side (localStorage)? Phase 1: localStorage. Phase 2: control plane DB.
