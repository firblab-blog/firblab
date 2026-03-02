# WireGuard Site-to-Site Tunnel: Hetzner Gateway <-> Homelab

## Architecture

```
Internet --> Hetzner VPS (203.0.113.10)
               |
               | Traefik (HTTPS termination, Let's Encrypt)
               |
               | WireGuard Server (10.8.0.1, UDP 51820)
               |
          [WireGuard Tunnel]
               |
               | WireGuard Client (10.8.0.2)
               |
          DMZ LXC (10.0.30.2, VLAN 30, lab-03)
               |
               | NAT/Masquerade (source IP -> 10.0.30.2)
               |
          gw-01 (inter-VLAN routing, DMZ -> Services)
               |
          Services VLAN 20
          ├── Ghost       (10.0.20.10:2368)
          ├── Roundcube   (10.0.20.11:8080)
          ├── FoundryVTT  (10.0.20.12:30000)
          ├── Mealie       (10.0.20.13:9000)
          └── RKE2/MetalLB (10.0.20.220-.250:80/443)
```

## Components

| Component | Location | Managed By |
|-----------|----------|------------|
| WireGuard Server | Hetzner VPS (Docker) | Terraform Layer 06 (cloud-init) |
| Peer Configs (S3) | Hetzner Object Storage | cloud-init Phase 8.5 |
| Peer Configs (Vault) | `secret/services/wireguard/*` | `scripts/sync-wg-peers-to-vault.sh` |
| DMZ->Services Policy | gw-01 | Terraform Layer 00 |
| WireGuard LXC | lab-03 (VLAN 30) | Terraform Layer 05 |
| WireGuard Client | DMZ LXC | Ansible `wireguard-deploy.yml` |
| UFW Rules | Service hosts + RKE2 | Ansible group_vars |
| gw-01 Backup | gw-01 VPN Client | Manual (see below) |

## Deployment Sequence

```
1. Seed S3 creds into Vault:
   vault kv patch -mount=secret infra/hetzner \
     s3_access_key=... s3_secret_key=... s3_endpoint=... s3_bucket=...

2. Layer 02: terraform apply
   (adds S3 fields to Vault schema)

3. Layer 00: terraform apply
   (adds DMZ->Services zone policy + homelab_service_ports group)

4. Layer 05: terraform apply
   (provisions WireGuard LXC on DMZ VLAN 30)

5. Layer 06: terraform destroy && terraform apply
   (redeploy with S3 upload + homelab peer routes)

6. Bootstrap LXC:
   cd ansible
   ansible-playbook -i inventory/hosts.yml playbooks/lxc-bootstrap.yml \
     --limit wireguard -e "ansible_user=root"

7. Deploy WireGuard client:
   ansible-playbook -i inventory/hosts.yml playbooks/wireguard-deploy.yml

8. Update UFW on service hosts:
   ansible-playbook -i inventory/hosts.yml playbooks/ghost-deploy.yml --tags firewall
   ansible-playbook -i inventory/hosts.yml playbooks/mealie-deploy.yml --tags firewall
   ansible-playbook -i inventory/hosts.yml playbooks/foundryvtt-deploy.yml --tags firewall
   ansible-playbook -i inventory/hosts.yml playbooks/roundcube-deploy.yml --tags firewall

9. Sync peer configs to Vault:
   ./scripts/sync-wg-peers-to-vault.sh

10. Test end-to-end:
    curl -v https://blog.example-lab.org
    curl -v https://mealie.example-lab.org
```

## Verification

```bash
# On DMZ LXC (wireguard):
wg show wg0                           # Check tunnel status + handshake
ping -c 3 10.8.0.1                    # Ping Hetzner through tunnel

# On Hetzner:
ping 10.0.20.10                    # Ghost through tunnel
curl http://10.0.20.10:2368        # Ghost HTTP through tunnel

# From internet:
curl -v https://blog.example-lab.org      # Full path: Traefik -> WG -> NAT -> Ghost
curl -v https://mealie.example-lab.org    # Full path: Traefik -> WG -> NAT -> Mealie
```

## Adding a New Service

After the tunnel is established, exposing a new homelab service requires only:

1. **Add port to firewall group** (if not 80/443): Edit `homelab_service_ports` in
   `terraform/layers/00-network/main.tf` and `terraform apply`

2. **Add Traefik route** on Hetzner: SSH to Hetzner, edit
   `/opt/gateway/config/services.yml` to add the new router + service, or add to
   the cloud-init template and redeploy

3. **Add UFW rule on service host**: Add the port to the host's Ansible group_vars
   and re-run the deploy playbook with `--tags firewall`

4. **Add DNS record** (optional): Already covered by wildcard `*.example-lab.org` CNAME,
   but add explicit record for clarity in `terraform/layers/06-hetzner/main.tf`

**No tunnel changes. No zone policy structural changes. No WireGuard config changes.**

For k8s services behind MetalLB (10.0.20.220-.250 via ports 80/443): only step 2
is needed. The port group already includes 80 and 443, and the RKE2 UFW rules
already allow DMZ traffic.

## gw-01 Backup Peer (Manual Setup)

The filipowm/unifi Terraform provider has no WireGuard resources. The gw-01
WireGuard VPN Client must be configured through the UniFi UI. This is a one-time
bootstrap step that serves as a backup tunnel if the DMZ LXC goes down.

### Prerequisites

- Hetzner gateway deployed with at least 2 WireGuard peers
- `peer2.conf` available (from S3 or Vault)
- Hetzner server's `wg0.conf` updated to route homelab subnets through peer2
  (same `AllowedIPs` modification as peer1 — see cloud-init Phase 8.6)

### Download Peer Config

```bash
# From Vault (after sync):
vault kv get -mount=secret -field=config services/wireguard/peer2

# From S3 directly:
aws s3 cp s3://<bucket>/peers/peer2.conf /tmp/peer2.conf \
  --endpoint-url https://<s3-endpoint>
```

### UniFi UI Configuration

1. **Settings -> VPN -> VPN Client**
2. Click **Create New**
3. Select **WireGuard** as the VPN type
4. Enter configuration:
   - **Name:** `Hetzner Gateway`
   - **Configuration:** Paste the contents of `peer2.conf`
5. **Important:** Modify the config before saving:
   - Change `AllowedIPs` from `0.0.0.0/0` to `10.8.0.0/24`
     (only route tunnel traffic, not a full tunnel)
   - Ensure `PersistentKeepalive = 25` is set
6. Save and **do NOT enable** (keep disabled until needed for failover)

### Modify Hetzner Server for peer2 Routes

If using peer2 as an active backup, you need to update the Hetzner server's
WireGuard config to route homelab subnets through peer2 as well:

```bash
# SSH to Hetzner server
ssh root@203.0.113.10

# Edit the WireGuard server config
docker exec wireguard bash -c "
  sed -i '/# peer2\$/,/AllowedIPs/ s|AllowedIPs = .*|AllowedIPs = 10.8.0.3/32, 10.0.20.0/24, 10.0.30.0/24|' /config/wg_confs/wg0.conf
"

# Hot-reload (no tunnel interruption)
docker exec wireguard bash -c "wg syncconf wg0 <(wg-quick strip /config/wg_confs/wg0.conf)"
```

### Failover Procedure

1. **Disable DMZ LXC WireGuard:**
   ```bash
   ssh root@10.0.30.2 "systemctl stop wg-quick@wg0"
   ```

2. **Enable gw-01 VPN Client:**
   UniFi Settings -> VPN -> VPN Client -> Hetzner Gateway -> Enable

3. **Verify:**
   From Hetzner: `ping 10.0.20.10` (Ghost through tunnel via gw-01)

4. **Restore primary:**
   - Disable gw-01 VPN Client
   - `ssh root@10.0.30.2 "systemctl start wg-quick@wg0"`

### Important Notes

- **Only one peer should be active at a time** for the same homelab subnets.
  If both peer1 (LXC) and peer2 (gw-01) are active simultaneously, the
  Hetzner server will route to whichever peer had the most recent handshake.
- The gw-01 VPN Client does NOT support NAT/masquerade by default. Traffic
  from Hetzner through peer2 will arrive at service hosts with source IP
  `10.8.0.3` (gw-01's WireGuard IP). You may need static routes for
  `10.8.0.0/24` on gw-01 pointing to the WireGuard interface.
- The LXC approach (peer1) is preferred because NAT/masquerade simplifies
  routing — no static route changes needed on gw-01.

## Peer Allocation

| Peer | IP | Purpose | Status |
|------|------|---------|--------|
| peer1 | 10.8.0.2 | DMZ LXC (primary tunnel) | Active |
| peer2 | 10.8.0.3 | gw-01 (backup) | Standby |
| peer3-20 | 10.8.0.4-21 | Available for future use | Unused |
