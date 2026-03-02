# Layer 00 Network Cutover Directive

## ⚠️ Mandatory Compliance

You are operating inside this repository and MUST strictly adhere to:

- `CLAUDE.md` in the repository root
- `docs/NETWORK.md`
- All other documentation inside the `docs/` directory

If any instruction in this directive conflicts with repository documentation, the repository documentation takes precedence.

Do not:
- Introduce workarounds
- Use `null_resource`
- Use SSH hacks
- Use `local-exec`
- Use Ansible for network configuration
- Perform manual UI configuration

All changes must be implemented as clean, deterministic Infrastructure as Code.

---

# Objective

Complete Layer 00 Terraform configuration so that:

1. All switch port profiles are managed via Terraform.
2. The physical topology is flattened (no daisy chaining).
3. VLAN enforcement is explicit and deterministic.
4. No reliance exists on default LAN permissiveness.
5. Terraform state matches actual infrastructure.

---

# Current Physical Topology

All managed switches are now directly connected to the UDM Pro.

```
UDM Pro (js-udm-1)
├── pbs d3:cf (offline)
├── Home-CloudKey
├── Rackmate (personal/gaming devices – not infra-critical)
├── switch-01 (5-port) – CLOSET
│       └── firblab-win 91:72
│           mealie
│           bc:24:11
│           ghost
│           vault-02
│           js-4
│           vault-01 32:38
│           plex-server
│           snappymail
│           js-1
│           foundryvtt 65:b3
│           vault-03 64:ff
│           gitlab 7f:fc
│           vault-16 16:14
│
├── USW Flex 2.5G 8 – MINILAB
│       └── bc:24:11
│           js-9 (offline)
│           js-7 (offline)
│           jetkvm
│           Linux PC
│           admins-Mini
│           2c:cf:67
│
├── U7 Pro (WiFi AP)
└── js-3 (offline)
```

Design state:
- Two managed switches (closet + minilab)
- Flat topology (each switch one hop from UDM Pro)
- Rackmate exists but is not part of strict infra policy enforcement

---

# Audit Findings

- VLANs exist on UDM Pro ✅
- Firewall zones exist ✅
- Switch ports currently have NO port profiles assigned ❌
- `storage_access` profile exists in code but not in Terraform state
- LAN → all ALLOW policies currently explain why everything still works
- k3s inventory contains VLAN/IP mismatch (must be corrected before deployment)

---

# Provider Confirmation

Provider in use:

```
filipowm/unifi
```

Confirmed capabilities:

- `unifi_device` resource is available
- `port_override` blocks support port profile assignment
- Full port profile management is achievable via Terraform

No workaround mechanisms are permitted.

---

# Design Principles

1. Flat topology only.
2. All VLAN enforcement occurs via switch port profiles.
3. No implicit LAN bleed.
4. Deterministic port assignment in Terraform.
5. Incremental cutover only — never mass VLAN migration.
6. Documentation and Terraform state must remain aligned.

---

# VLAN Cutover Plan (Ordered Execution)

### Phase 1 – Safe Devices (Already VLAN 10)
- lab-02
- Mac Mini
- RPi5

### Phase 2 – Storage Migration
- TrueNAS → VLAN 40 (`storage_access` profile)

### Phase 3 – Remaining Hosts
- Fresh installs
- Remaining servers

### Special Requirement
- JetKVM must remain on Management VLAN.

---

# Terraform Work Required (Layer 00)

You must:

1. Define `unifi_device` resources for:
   - switch-01 (closet switch)
   - switch-02 (minilab switch)

2. Implement `port_override` blocks for each relevant port.

3. Use placeholder MAC values until confirmed:
   - `REPLACE_FIRBSWITCH01_MAC`
   - `REPLACE_FIRBSWITCH02_MAC`

4. Ensure:
   - Clean `terraform plan`
   - No drift
   - No unexpected changes

Do not proceed to apply until MAC addresses are confirmed.

---

# Documentation Updates Required

You must:

- Update `docs/NETWORK.md` to reflect flattened topology
- Document LAN → all ALLOW behavior
- Fix k3s VLAN/IP mismatch in documentation
- Ensure port profile documentation matches Terraform

---

# Operational Constraints

- No full-network downtime
- No broad VLAN reassignment in a single apply
- No UI configuration outside Terraform
- No deviation from repository architecture standards

---

# Immediate Next Step

1. Define `unifi_device` resources for both switches.
2. Structure `port_override` blocks.
3. Wait for MAC addresses before apply.

If anything is unclear, request clarification before modifying Terraform.

Operate conservatively. Prioritize correctness over speed.

