FIRBLAB OS

Distributed Homelab Control Plane

Enterprise Architecture Specification (v0.4)

⸻

1. Executive Summary

Firblab OS is a deterministic, GitOps-native, Vault-first infrastructure control plane designed for heterogeneous homelab environments.

It provides:
	•	Declarative infrastructure orchestration
	•	Deterministic reconciliation
	•	Secret lifecycle enforcement
	•	Hybrid cloud integration
	•	Capacity intelligence
	•	AI-assisted operational advisory
	•	Strict safety and quorum protection

Firblab is not a container manager.
It is not a dashboard.
It is the authoritative control plane for infrastructure state.

⸻

2. Architectural Principles

2.1 Determinism Over Automation

All infrastructure mutation must flow through deterministic execution paths.
AI may recommend but never directly mutate.

2.2 Git as Constitution

The declarative model stored in Git is the sole source of truth.

2.3 Vault as Security Root

All secret generation, storage, and rotation occurs in Vault.
Runtime systems must not depend on Vault availability.

2.4 Separation of Concerns

Terraform = Infrastructure provisioning
Ansible = Configuration convergence
Control Plane = Orchestration + Safety
Agents = Advisory

2.5 Non-Destructive Default

Unmanaged resources are flagged, not destroyed.
Destructive actions require explicit approval.

2.6 Own the Core — Adapt the Rest

Firblab OS owns its data model, persistence layer, and orchestration logic.
No external tool sits in the critical path. PostgreSQL and Redis are the only
infrastructure dependencies — both are battle-tested, vendor-neutral, and
will outlive any homelab tool.

Third-party tools (inventory UIs, network scanners, DCIM platforms) integrate
as optional adapters. If an adapter's upstream project dies, the control plane
does not blink. Adapters are replaceable; the core is not.

⸻

3. Layered System Architecture

Firblab OS is divided into three strict layers.

⸻

Layer 3: Agentic Workforce (Advisory Only)
	•	Infrastructure Engineer Agent
	•	Support Engineer Agent
	•	Security Engineer Agent
	•	Capacity Planner Agent
	•	Software Engineer Agent

⸻

Layer 2: Operational Intelligence
	•	Metrics Aggregator
	•	Drift Analyzer
	•	Capacity Forecaster
	•	Event Classifier
	•	Log Summarizer

⸻

Layer 1: Deterministic Infrastructure Core
	•	Model Engine
	•	Git Manager
	•	Plan Generator
	•	Terraform Executor
	•	Ansible Executor
	•	Vault Client
	•	Reconciliation Engine
	•	State Manager
	•	Apply Pipeline
	•	Policy Validator

Only Layer 1 may mutate infrastructure.

⸻

4. Control Plane Runtime Architecture

Firblab runs on a dedicated external control node.

Minimum Requirements:
	•	2+ CPU cores
	•	4GB RAM recommended (8GB for full adapter stack)
	•	Encrypted disk
	•	Persistent storage for Terraform state

4.1 Core Data Layer

PostgreSQL is the sole persistent data store. Firblab OS owns the schema —
infrastructure inventory, audit log, reconciliation state, agent proposals,
and capacity metrics all live in PostgreSQL under Firblab OS's control.

Redis provides:
	•	Response caching (API queries, topology renders)
	•	Pub/sub event bus (drift events, agent notifications, apply status)
	•	Session state for the Web UI
	•	Rate limiting for API and agent actions

No ORM abstraction that hides the database. The schema is a first-class
artifact, version-controlled and migrated explicitly.

4.2 Dependency Boundary

Hard dependencies (core cannot function without these):
	•	PostgreSQL — data persistence, inventory model, audit log
	•	Redis — caching, event bus, session state
	•	Git — source of truth for declarative model
	•	Vault — secret lifecycle (graceful degradation if unavailable)

Soft dependencies (optional adapters, removable without impact):
	•	Scanopy — network discovery feed
	•	RackPeek — lightweight inventory visualization export
	•	NetBox — DCIM/IPAM import/export for power users
	•	Prometheus — metrics ingestion for capacity planning
	•	Any future third-party tool

If a soft dependency is unavailable, the feature it powers degrades gracefully.
The control plane continues to operate, plan, and apply.

4.3 High-Level Runtime Diagram

            ┌────────────────────┐
            │      Web UI        │
            └─────────┬──────────┘
                      │
            ┌─────────▼──────────┐
            │     API / Core     │
            ├────────────────────┤
            │ Model Engine       │
            │ Plan Engine        │
            │ Policy Engine      │
            │ Drift Engine       │
            │ Agent Runtime      │
            └──┬──────────────┬──┘
               │              │
     ┌─────────▼────┐  ┌─────▼─────┐
     │  PostgreSQL   │  │   Redis   │
     │  (inventory,  │  │  (cache,  │
     │   audit,      │  │  pub/sub, │
     │   state)      │  │  events)  │
     └──────────────┘  └───────────┘
               │
 ┌────────────┬───────┼─────────┬────────────┐
 ▼            ▼       ▼         ▼            ▼

Terraform    Ansible  Proxmox   Hetzner    Ubiquiti
Executor     Runner     API       API         API

⸻

5. Declarative Model Specification

The model defines desired infrastructure state.

Core Domains:
	•	Nodes
	•	Roles
	•	Capabilities
	•	Stacks
	•	Networking
	•	Storage
	•	Cloud Integration
	•	Policies

Example:

nodes:
  - name: proxmox-01
    role: compute
    capabilities: [gpu]

stacks:
  media:
    enabled: true

vault:
  mode: ha

networking:
  vlans:
    - id: 10
      purpose: internal

Lifecycle:
UI → Modify Model → Commit to Git → Plan → Apply

⸻

6. State Model

Firblab tracks four states.
	1.	Desired State (Git Model)
	2.	Planned State (Terraform Plan)
	3.	Recorded State (Terraform State File)
	4.	Actual State (Provider APIs)

Drift occurs when states diverge.

⸻

7. Reconciliation State Machine

Reconciliation Loop (Periodic):

[Pull Git]
↓
[Load Terraform State]
↓
[Query Providers]
↓
[Compare Graphs]
↓
[Generate Drift Report]
↓
[Surface in UI]

Drift Classification:
	•	Unmanaged Resource
	•	Configuration Drift
	•	Missing Resource
	•	Policy Violation

No automatic destructive reconciliation occurs.

⸻

8. Apply Lifecycle Flow

Apply State Machine:

IDLE
↓
VALIDATING_MODEL
↓
GENERATING_PLAN
↓
AWAITING_CONFIRMATION
↓
LOCK_ACQUIRED
↓
EXECUTING_TERRAFORM
↓
EXECUTING_ANSIBLE
↓
POST_APPLY_HEALTH_CHECK
↓
RELEASE_LOCK
↓
IDLE

Failure Paths:
	•	Plan Failure → Abort
	•	Health Check Failure → Safe Mode Trigger

Global Lock prevents concurrent applies.

⸻

9. Shadow Planning Engine

Before destructive change:
	•	Validate quorum requirements
	•	Validate Vault HA minimums
	•	Validate Kubernetes quorum
	•	Validate minimum compute nodes
	•	Validate networking isolation rules

If violation detected:
→ Block Apply

⸻

10. Vault Lifecycle

Vault Responsibilities:
	•	Secret generation
	•	Secret rotation
	•	Credential brokering
	•	Encryption services

Secret Injection Flow:

[Generate Secret]
↓
[Store in Vault]
↓
[Inject via Template]
↓
[Deploy Service]

Vault Failure Handling:
	•	Runtime services unaffected
	•	New deployments paused
	•	Control plane remains functional

⸻

11. Agent Runtime Architecture

Agents operate in proposal mode.

Agent Flow:

[Event Trigger]
↓
[Context Gathering]
↓
[Analysis]
↓
[Generate Proposal]
↓
[Create Branch + Model Diff]
↓
[Open PR]
↓
[Plan Generated]
↓
[Human Review]
↓
[Apply via Core]

Agents have no direct execution privileges.

⸻

12. Agent Guardrail Policy Engine

Before accepting agent proposal:
	•	Validate schema
	•	Validate policy rules
	•	Validate quorum
	•	Validate capacity
	•	Validate security posture

If validation fails:
→ Reject Proposal

⸻

13. Capacity Planning Engine

Inputs:
	•	Prometheus metrics
	•	Proxmox API
	•	Storage telemetry
	•	GPU utilization

Outputs:
	•	Headroom metrics
	•	Growth trend projection
	•	Saturation date estimate
	•	Scaling recommendations

Agents may propose expansion based on forecasts.

⸻

14. Safety Modes

Safe Mode Trigger Conditions:
	•	Vault quorum loss
	•	Terraform state corruption
	•	Missing control node integrity
	•	Severe drift anomaly

Safe Mode State Machine:

NORMAL
↓
ANOMALY_DETECTED
↓
SAFE_MODE_ENABLED
↓
MANUAL_RECOVERY_REQUIRED

In Safe Mode:
	•	Apply disabled
	•	Drift visible
	•	Recovery workflow exposed

⸻

15. UI Functional Domains
	1.	Topology Graph
	2.	Drift Center
	3.	Apply Center
	4.	Vault Status Dashboard
	5.	Capacity Dashboard
	6.	Agent Console
	7.	Audit Log Viewer

All changes are auditable.

⸻

16. Audit & Compliance

Every action recorded:
	•	Model change
	•	Plan generation
	•	Apply execution
	•	Agent proposal
	•	Vault access

Immutable audit log maintained on control node.

⸻

17. Failure Recovery Model

Recovery Hierarchy:
	1.	Restart failed services
	2.	Reconcile from Git
	3.	Restore Terraform state backup
	4.	Restore Vault from snapshot
	5.	Rebuild control node

Git + Vault snapshots ensure rebuildability.

⸻

18. Extensibility Model

Core remains deterministic.
Plugins extend capabilities without altering authority boundaries.

18.1 Plugin Categories

	•	Stack modules — pre-packaged service definitions (media stack, monitoring stack)
	•	Provider adapters — inbound/outbound integrations with external tools
	•	Agent types — specialized AI advisory agents
	•	Policy packs — reusable validation rule sets

18.2 Integration Adapter Architecture

External tools connect to Firblab OS through a standardized adapter interface.
Adapters are unidirectional (inbound OR outbound) and stateless — they translate
between Firblab OS's internal model and the external tool's data format.

Inbound adapters (feed data INTO Firblab OS):
	•	Scanopy → discovered hosts, services, interfaces, topology
	•	Proxmox API → VMs, LXCs, node resources, storage
	•	UniFi API → switches, APs, port states, clients
	•	Hetzner API → cloud servers, firewalls, volumes
	•	Prometheus → metrics snapshots for capacity planning

Outbound adapters (export data FROM Firblab OS):
	•	RackPeek → YAML inventory export for lightweight visualization
	•	NetBox → DCIM/IPAM sync for users who want NetBox alongside
	•	Ansible inventory → dynamic inventory generation from internal model
	•	Terraform variables → auto-generated tfvars from model state

Adapter lifecycle:
	•	Adapters are registered, not hardcoded
	•	Each adapter declares its sync direction, schedule, and failure mode
	•	Adapter failure triggers a warning, not a control plane error
	•	Adapters can be enabled/disabled per deployment without code changes

18.3 Evaluated Tools (Decision Record)

The following tools were evaluated for core integration and rejected as
hard dependencies. All remain available as optional adapters.

RackPeek (v1.0.0, AGPL-3.0, C#/Blazor):
	•	Lightweight YAML-based infrastructure documentation with web UI
	•	Single container, ~50MB RAM, no database
	•	No REST API, no auto-discovery, no IPAM
	•	Decision: outbound adapter for simple inventory visualization
	•	Risk: v1.0.0 project with 6 contributors — too immature for core dependency

NetBox (v4.2.6, Apache 2.0, Python/Django):
	•	Industry-standard DCIM + IPAM with REST/GraphQL API
	•	6 containers, 4-8GB RAM, PostgreSQL + Redis
	•	Terraform provider, Ansible dynamic inventory, plugin ecosystem
	•	Decision: bidirectional adapter for power users who want full DCIM
	•	Risk: resource footprint too heavy to bundle as a default dependency

Scanopy (v0.14.8, AGPL-3.0, Rust/Svelte):
	•	Automatic network discovery via SNMP, port scanning, Docker socket
	•	3 containers, ~2-4GB RAM, PostgreSQL, privileged daemon
	•	REST API, Prometheus metrics, distributed scanning
	•	Decision: inbound adapter for network auto-discovery
	•	Risk: pre-1.0, privileged daemon requirement, AGPL license

Nautobot (v3.0.7, Apache 2.0, Python/Django):
	•	NetBox fork with Jobs engine, GraphQL, SSoT plugins
	•	4+ containers, 4-8GB RAM, same footprint as NetBox
	•	Decision: no adapter planned — NetBox adapter covers this niche
	•	Risk: smaller community than NetBox, no unique advantage for homelab

⸻

19. MVP Definition

Phase 1:
	•	Deterministic core
	•	Git integration
	•	Terraform execution
	•	Ansible execution
	•	Vault integration
	•	Drift detection (basic)
	•	Proxmox provider
	•	Hetzner backup support
	•	Agent advisory mode

⸻

20. Strategic Positioning

Firblab OS is:
	•	A deterministic infrastructure brain
	•	A reconciliation engine
	•	A GitOps enforcement platform
	•	An AI-assisted operations layer
	•	A reproducible homelab operating system

Agents are employees.
The deterministic core is executive authority.
Git is the constitution.

⸻

End of Specification v0.4