# FirbLab Portfolio Roadmap

Tracks career portfolio work to maximize job search impact.

Last updated: 2026-03-02

## Completed

- [x] **Resume bullets** — drafted from real codebase audit (13K lines TF, 43 roles, 61 playbooks, 75 firewall policies, etc.)
- [x] **LinkedIn project** — "FirbLab — Production-Grade Homelab Infrastructure Platform" created
- [x] **Sanitization pipeline** — `scripts/sanitize.py` + `scripts/sanitize.yml` for repeatable firblab → firblab-public sync
- [x] **firblab-public repo** — GitLab project (Terraform Layer 03), GitHub push mirror (`example-lab-blog/firblab`), PAT in Vault at `secret/services/github`

## In Progress

(nothing currently)

## Planned

### Multi-Cloud Free-Tier Layer
Add `terraform/layers/09-multicloud/` deploying a small workload to AWS, GCP, and Azure free tiers. Same Terraform patterns, same ArgoCD GitOps, different clouds. Neutralizes the "homelab only" objection in interviews.
- AWS Free Tier: small EKS or EC2 + S3
- GCP Free Tier: GKE autopilot or Compute Engine
- Azure Free Tier: AKS or App Service
- All managed from the same repo with the same Terraform/ArgoCD patterns

### CIS-Hardened Packer Templates (Standalone Repo)
Extract and generalize the Packer templates (`packer/ubuntu-24.04/`, `packer/rocky-9/`) into a standalone open-source repo that works on Proxmox, VMware, AWS, GCP, etc. There's a gap in this space — most public Packer templates aren't CIS-hardened.
- Multi-builder support (proxmox-iso, amazon-ebs, googlecompute, vsphere-iso)
- CIS Benchmark Level 1 compliance out of the box
- CI pipeline that validates hardening with InSpec/OpenSCAP

### Blog Posts
1. **GitLab/Authentik Migration Story** — "I migrated production services between physical hosts with zero data loss using PBS backups and IaC." Punchline: it was easy because the infrastructure was built right.
2. **CIS-Hardened VM Templates** — Deep dive into the Packer → Terraform → Ansible hardening pipeline. What CIS benchmarks cover, what Packer bakes vs what Ansible enforces, how to validate.
3. **Vault Cluster with Transit Auto-Unseal** — Building a 3-node Raft cluster on consumer hardware with a separate unseal Vault instance. The chicken-and-egg problem and how transit seal solves it.

### firblab-os (Separate Project)
The portable "build your own FirbLab" product. Different from firblab-public (which is the portfolio). Existing scaffolding in `/Users/admin/repos/firblab-os/`. Needs the stripping work completed per `docs/STRIPPING-HANDOFF.md`.

## Target Roles
- Platform Engineer
- DevOps Engineer / SRE
- Infrastructure Engineer
- Cloud Engineer

## Certifications to Consider
- CKA (Certified Kubernetes Administrator) — should be passable now with RKE2 experience
- HashiCorp Terraform Associate — trivial given TF depth
- AWS SAA renewal (expired Dec 2023) — already passed once
