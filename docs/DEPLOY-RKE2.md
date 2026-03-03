# RKE2 Cluster Deployment Guide

## Current State

RKE2 cluster is **deployed and operational**:
- 6/6 nodes Ready (3 servers + 3 agents on VLAN 20)
- ArgoCD syncing 17+ applications (app-of-apps pattern, sync waves 0/1/2)
- Vault kubernetes auth configured (External Secrets Operator + cert-manager)
- Access via direct kubeconfig (`~/.kube/rke2-config`) or SSH tunnel (`~/.kube/rke2-config-tunnel`)

---

## Deployment Sequence

### Step 1: Terraform — Provision 5 VMs

**Prerequisite:** Packer template VM 9000 (`tmpl-ubuntu-2404-base`) must exist on lab-01.

```bash
# Load SSH key for Proxmox SFTP (cloud-init snippet uploads)
ssh-add ~/.ssh/id_ed25519_lab-01

cd ~/repos/firblab/terraform/layers/04-rke2-cluster
terraform init
terraform plan -var proxmox_node=lab-01
terraform apply -var proxmox_node=lab-01
```

**If Vault is down** (bootstrap mode):
```bash
terraform plan -var proxmox_node=lab-01 \
  -var use_vault=false \
  -var proxmox_api_url="https://10.0.10.2:8006" \
  -var proxmox_api_token_id="terraform@pam!terraform-token" \
  -var proxmox_api_token_secret="<secret>"
```

**Expected VMs:**

| Hostname | VM ID | IP | Role | CPU | RAM | Disk |
|----------|-------|-----|------|-----|-----|------|
| rke2-server-1 | 4000 | 10.0.20.40 | Server (init) | 2 | 4GB | 40GB |
| rke2-server-2 | 4001 | 10.0.20.41 | Server | 2 | 4GB | 40GB |
| rke2-server-3 | 4002 | 10.0.20.42 | Server | 2 | 4GB | 40GB |
| rke2-agent-1 | 4003 | 10.0.20.50 | Agent | 4 | 8GB | 40GB |
| rke2-agent-2 | 4004 | 10.0.20.51 | Agent | 4 | 8GB | 40GB |
| rke2-agent-3 | 4005 | 10.0.20.52 | Agent | 4 | 8GB | 40GB |

**Verify:** SSH to each node: `ssh -i terraform/layers/04-rke2-cluster/.secrets/rke2-server-1_ssh_key admin@10.0.20.40`

### Step 2: Ansible — Deploy RKE2

```bash
cd ~/repos/firblab

# Add all node SSH keys
for key in terraform/layers/04-rke2-cluster/.secrets/*_ssh_key; do
  ssh-add "$key"
done

# Syntax check (already passed, but good to confirm)
ansible-playbook ansible/playbooks/rke2-deploy.yml --syntax-check

# Deploy (use -vv for verbose if debugging)
ansible-playbook ansible/playbooks/rke2-deploy.yml
```

**Playbook execution order:**
1. All 6 nodes in parallel: common + hardening + RKE2 prerequisites + STIG configs
2. rke2-server-1 only (serial: 1): cluster-init, generate token
3. rke2-server-2, rke2-server-3 (serial: 1 each): join cluster
4. rke2-agent-1, rke2-agent-2, rke2-agent-3 (parallel): join cluster
5. Post-deploy: label nodes, verify health, fix kubeconfig

**Verify:**
```bash
# Option 1: Direct access (if inter-VLAN routing is working)
export KUBECONFIG=~/.kube/rke2-config
kubectl get nodes        # All 6 should be Ready
kubectl get pods -A      # System pods running

# Option 2: Via SSH tunnel (reliable — bypasses gw-01 routing issues)
# Terminal 1: Open tunnel through Proxmox jump host
ssh -L 6443:10.0.20.40:6443 \
  -i ~/.ssh/id_ed25519_lab-01 -o IdentitiesOnly=yes \
  admin@10.0.10.42 -N &

# Terminal 2: Use tunnel kubeconfig (server: https://127.0.0.1:6443)
export KUBECONFIG=~/.kube/rke2-config-tunnel
kubectl get nodes        # All 6 should be Ready
kubectl get pods -A      # System pods running
```

### Workstation Access (Day-to-Day)

The `rke2-deploy.yml` playbook (Play 5) automatically downloads the kubeconfig to your
Mac workstation. Two variants are created:

| File | Server Address | Use Case |
|------|----------------|----------|
| `~/.kube/rke2-config` | `https://10.0.20.40:6443` | Direct access (VLAN 1 → VLAN 20) |
| `~/.kube/rke2-config-tunnel` | `https://127.0.0.1:6443` | SSH tunnel (reliable fallback) |

#### Direct Access (default)

The gw-01 zone policy "LAN to Services" (Terraform Layer 00) allows VLAN 1 → VLAN 20
traffic. Direct access should work from the workstation:

```bash
export KUBECONFIG=~/.kube/rke2-config
kubectl get nodes        # All 6 should be Ready
```

#### SSH Tunnel (fallback)

If direct access times out (gw-01 reconfiguration, routing issues), use an SSH tunnel
through a Proxmox jump host on VLAN 10:

```bash
# Open tunnel: Mac → lab-01 (VLAN 10) → RKE2 API (VLAN 20)
ssh -L 6443:10.0.20.40:6443 \
  -i ~/.ssh/id_ed25519_lab-01 -o IdentitiesOnly=yes \
  admin@10.0.10.42 -N &

export KUBECONFIG=~/.kube/rke2-config-tunnel
kubectl get nodes
```

#### ArgoCD UI

```bash
export KUBECONFIG=~/.kube/rke2-config
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Browser: https://localhost:8080
# Username: admin
# Password:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

#### Shell Alias (optional)

Add to `~/.zshrc` for convenience:

```bash
alias k='KUBECONFIG=~/.kube/rke2-config kubectl'
alias kt='KUBECONFIG=~/.kube/rke2-config-tunnel kubectl'
alias argocd-ui='KUBECONFIG=~/.kube/rke2-config kubectl port-forward -n argocd svc/argocd-server 8080:443'
```

---

### Step 3: Configure Vault Kubernetes Auth

The auth backend and roles already exist in Vault (Terraform 02-vault-config). After the
cluster is live, configure the auth backend with the Ansible playbook:

```bash
cd ~/repos/firblab
export VAULT_ADDR=https://10.0.10.10:8200
export VAULT_TOKEN=hvs.xxxxx
export VAULT_CACERT=~/.lab/tls/ca/ca.pem
ansible-playbook ansible/playbooks/vault-k8s-auth.yml
```

This playbook:
1. Creates `vault-auth` ServiceAccount + ClusterRoleBinding in kube-system (token review)
2. Creates a long-lived token Secret for Vault's token reviewer JWT
3. Distributes the Vault CA cert to `cert-manager` and `external-secrets` namespaces
4. Configures Vault's kubernetes auth backend (`kubernetes_host`, CA cert, JWT)
5. Verifies auth by testing a kubernetes login from the cluster

**Requires:** Vault CLI on Mac, valid `VAULT_TOKEN`, Vault CA cert at `~/.lab/tls/ca/ca.pem`

### Step 4: ArgoCD Bootstrap + Platform Deployment (GitOps)

All platform services are managed declaratively by ArgoCD. The Ansible playbook handles
the full bootstrap: installing ArgoCD, configuring the GitLab repo, and applying the
root app-of-apps. After that, ArgoCD manages everything.

```bash
cd ~/repos/firblab
ansible-playbook ansible/playbooks/argocd-bootstrap.yml
```

The playbook:
1. Creates the `argocd` namespace
2. Installs ArgoCD from upstream manifests (CRDs + controllers)
3. Waits for argocd-server, repo-server, and application-controller
4. Registers the GitLab repository (`http://10.0.10.50/infrastructure/firblab.git`)
5. Applies the root app-of-apps Application (`k8s/argocd/install.yml`)
6. Verifies all 17 child Applications are created and syncing

#### 4.2 ArgoCD Deploys Everything (automatic)

ArgoCD sync waves control deployment ordering — no manual intervention needed:

| Wave | Applications | Purpose |
|------|-------------|---------|
| **0** | metallb, traefik, cert-manager, external-secrets, gatekeeper, longhorn, monitoring-prometheus, monitoring-loki, trivy-operator, gitlab-agent | Helm chart installs (controllers) |
| **1** | metallb-config, traefik-config, cert-manager-config, external-secrets-config, longhorn-config, gatekeeper-policies | Post-install CRD configs |
| **2** | mealie, sonarqube | Workload applications |

**Monitor sync progress:**
```bash
# Watch all apps sync
kubectl -n argocd get applications -w

# Detailed status with sync + health
kubectl -n argocd get applications \
  -o custom-columns=NAME:.metadata.name,WAVE:.metadata.annotations.'argocd\.argoproj\.io/sync-wave',SYNC:.status.sync.status,HEALTH:.status.health.status

# ArgoCD CLI (optional)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
argocd login localhost:8080 --insecure
argocd app list
```

#### 4.3 Network Policies (per-namespace, applied manually or via ArgoCD)
```bash
# Apply to each workload namespace after apps create them
kubectl apply -f k8s/platform/network-policies/default-deny-all.yaml -n <namespace>
kubectl apply -f k8s/platform/network-policies/allow-dns.yaml -n <namespace>
kubectl apply -f k8s/platform/network-policies/allow-monitoring.yaml -n <namespace>
```

#### Directory Structure Reference

ArgoCD Application manifests reference these paths:

```
k8s/platform/
├── cert-manager/
│   └── cluster-issuer.yaml          # ClusterIssuer (wave 1 Git source)
├── external-secrets/
│   ├── cluster-secret-store.yaml    # ClusterSecretStore (wave 1 Git source)
│   └── gitlab-agent-token.yaml      # ExternalSecret: agent token from Vault
├── gitlab-agent/
│   └── helm/values.yaml             # GitLab Agent Helm values (wave 0 $values ref)
├── metallb/
│   └── config.yaml                  # IPAddressPool + L2Advertisement (wave 1 Git source)
├── gatekeeper/
│   ├── helm/values.yaml             # Helm values (wave 0 $values ref)
│   └── policies/                    # ConstraintTemplates + Constraints (wave 1 Git source)
│       ├── templates/               # 9 ConstraintTemplate YAMLs
│       └── constraints.yaml
├── traefik/
│   ├── helm/values.yaml             # Helm values (wave 0 $values ref)
│   └── manifests/
│       └── default-headers.yaml     # Middleware CRD (wave 1 Git source)
├── longhorn/
│   ├── helm/values.yaml             # Helm values (wave 0 $values ref)
│   └── manifests/
│       └── basic-auth-middleware.yaml  # Middleware CRD (wave 1 Git source)
├── monitoring/
│   ├── prometheus/values.yaml       # kube-prometheus-stack Helm values (wave 0 $values ref)
│   └── loki/values.yaml             # loki-stack Helm values (wave 0 $values ref)
└── network-policies/                # Applied per-namespace
```

### Step 5: Post-Deploy Verification

```bash
# Cluster health
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running | grep -v Completed

# Gatekeeper constraints active
kubectl get constraints

# Test constraint enforcement (should be denied)
kubectl run test --image=nginx:latest -n default 2>&1 | grep -i denied

# CIS profile
kubectl -n kube-system get cm

# Audit logging (on rke2-server-1)
ssh admin@10.0.20.40 'sudo tail -5 /var/lib/rancher/rke2/server/logs/audit.log'

# cert-manager can issue certs
kubectl get clusterissuer vault-issuer

# ESO can reach Vault
kubectl get clustersecretstores vault-backend
```

---

## Known Issues / Gotchas

1. **Alertmanager Gotify token is a PLACEHOLDER** in `k8s/platform/monitoring/prometheus/values.yaml`. Update after Hetzner Layer 06 deploys the Gotify instance.

2. **Vault access uses IP directly** (`10.0.10.10:8200`) — no DNS resolution required. The `vault-k8s-auth.yml` playbook distributes the Vault CA cert as k8s Secrets for TLS verification.

3. **Bootstrap chicken-and-egg**: If applying Terraform changes to the switch port that hosts Vault, connectivity will temporarily break. Use `use_vault=false` for that apply.

4. **fail2ban + ssh-agent**: Multiple keys in agent can trigger fail2ban bans. Use `-i <key> -o IdentitiesOnly=yes` when SSHing manually.

5. **`ansible.cfg`** exists in the repo root with `roles_path = ansible/roles` and `inventory = ansible/inventory/hosts.yml`. Run playbooks from the repo root directory.

6. **ArgoCD GitLab access**: Authentication is handled by a deploy token created by Terraform Layer 03-gitlab-config (`gitlab_deploy_token.argocd_readonly`). The token is stored in Vault at `secret/services/gitlab` and injected into the ArgoCD repo Secret by `argocd-bootstrap.yml`. No manual token management needed — the full pipeline is: Terraform creates token → writes to Vault → Ansible reads from Vault → configures ArgoCD.

---

## Architecture Summary

```
lab-01 (Proxmox, 24 CPU, 64GB RAM)
├── rke2-server-1 (VM 4000) — 10.0.20.40, 2 CPU, 4GB, cluster-init
├── rke2-server-2 (VM 4001) — 10.0.20.41, 2 CPU, 4GB, join
├── rke2-server-3 (VM 4002) — 10.0.20.42, 2 CPU, 4GB, join
├── rke2-agent-1  (VM 4003) — 10.0.20.50, 4 CPU, 8GB, workloads
├── rke2-agent-2  (VM 4004) — 10.0.20.51, 4 CPU, 8GB, workloads
└── rke2-agent-3  (VM 4005) — 10.0.20.52, 4 CPU, 8GB, workloads

Platform Stack:
  Gatekeeper → MetalLB → Traefik → cert-manager → Longhorn
  → External Secrets → Monitoring → ArgoCD → Trivy

Network: VLAN 20 (Services), MetalLB pool 10.0.20.220-250
Storage: Longhorn (2 replicas, 50GB data disk per agent)
CNI: Canal (Calico + Flannel) — native NetworkPolicy
Ingress: Traefik (TLS 1.2+, OWASP headers, HTTP→HTTPS redirect)
Secrets: Vault (kubernetes auth, External Secrets Operator)
Compliance: DISA STIG (profile: cis), CIS Benchmark, FIPS 140-2
```

---

## Vault Secrets to Seed Before Deploy

These must exist in Vault before platform services can consume them:

```bash
# Grafana admin credentials
vault kv put secret/services/grafana username=admin password=<password>

# ArgoCD admin password (if using ESO for it)
vault kv put secret/services/argocd admin_password=<password>

# Mealie API token (if using ESO)
vault kv put secret/services/mealie api_token=<token>
```

---

## Resource Budget — lab-01 Only

lab-01 is dedicated to the RKE2 cluster. GitLab, Runner, and vault-2 are on lab-02. Standalone services target lab-03.

| Component | CPU | RAM |
|-----------|-----|-----|
| 3x servers (control plane) | 6 cores | 12 GB |
| 3x agents (workloads) | 12 cores | 24 GB |
| Proxmox overhead | ~1 core | ~2 GB |
| **Total allocated** | **19 cores** | **38 GB** |
| **Remaining on lab-01** | **5 cores** | **26 GB** |

Good headroom. A 4th agent (`worker_count=4`, +4 CPU/+8 GB) or bumping agents to 12 GB each (`worker_memory_mb=12288`) is still possible if needed.
