# =============================================================================
# Guardrail — Product Roadmap: Milestones and Issues
# =============================================================================
# Bootstraps the full Guardrail product roadmap into GitLab.
#
# Milestone structure (from guardrail-product-plan.md):
#   M1 "Guardrail is Credible"      — P0 items (foundational correctness)
#   M2 "Guardrail is Useful Daily"  — P1 workflow/delivery items
#   M3 "Guardrail is Hard to Skip"  — P1 coverage/trust/operator items
#   M4 "Guardrail is Product-Grade" — P2 enforcement, metrics, distribution
#
# Issue priority label mapping:
#   P0 → priority::critical
#   P1 → priority::high
#   P2 → priority::medium
#
# Execution order (from guardrail-backlog.md):
#   P0.1 upstream sync → P0.2 provenance → P0.3 review system → P0.4 extraction
#   → P0.5 detection → P0.6 packs → P0.7 passive-mode → P0.8 MCP preflight
#   → P0.9 bootstrap → P0.10 standalone cleanup → P1 → P2
# =============================================================================

locals {
  guardrail_id = gitlab_project.projects["guardrail"].id
}

###############################################
# Milestones
###############################################

resource "gitlab_project_milestone" "guardrail_m1" {
  project     = local.guardrail_id
  title       = "M1: Guardrail is Credible"
  description = <<-EOT
    Guardrail knows what the repo uses, which sources are authoritative, and can
    sync and review them reliably. The core trust model is in place. P0 work only.

    Exit bar: upstream sync for a few core ecosystems, explicit source version and
    freshness tracking, review queues, version-aware pack resolution, stronger
    `get_guidance_context`.
  EOT

  depends_on = [gitlab_project.projects]
}

resource "gitlab_project_milestone" "guardrail_m2" {
  project     = local.guardrail_id
  title       = "M2: Guardrail is Useful Daily"
  description = <<-EOT
    Guardrail is a natural part of agent workflows: strong MCP preflight, reliable
    passive-mode projections, better matching, coverage diagnostics, and bootstrap
    source strategy. P1 items that make Guardrail worth reaching for every day.

    Exit bar: strong MCP workflow, better passive-mode files, coverage and warning
    reporting, improved pack layering.
  EOT

  depends_on = [gitlab_project.projects]
}

resource "gitlab_project_milestone" "guardrail_m3" {
  project     = local.guardrail_id
  title       = "M3: Guardrail is Hard to Skip"
  description = <<-EOT
    Guardrail is concretely usable across major agent environments, has a proper
    auth model, operator control surfaces, and is validated with real client
    workflows. P1 items that drive adoption and trust.

    Exit bar: validated Claude Code/Codex/Cursor/Windsurf/Replit workflows,
    project-aware authz, operator review surfaces, hard to imagine working without.
  EOT

  depends_on = [gitlab_project.projects]
}

resource "gitlab_project_milestone" "guardrail_m4" {
  project     = local.guardrail_id
  title       = "M4: Guardrail is Product-Grade"
  description = <<-EOT
    Guardrail can be distributed, upgraded, and relied on as a workflow dependency.
    Evidence exists that it improves coding-agent outcomes. P2 work.

    Exit bar: stable packaging, upgrade path, enforcement options, team workflows,
    telemetry and ROI story.
  EOT

  depends_on = [gitlab_project.projects]
}

###############################################
# P0 Issues — Milestone 1: Guardrail is Credible
###############################################

resource "gitlab_project_issue" "guardrail_p0_1_upstream_sync" {
  project      = local.guardrail_id
  title        = "P0.1 Real upstream sync engine"
  milestone_id = gitlab_project_milestone.guardrail_m1.milestone_id
  labels       = ["enhancement", "priority::critical"]
  description  = <<-EOT
    Guardrail must sync authoritative sources instead of relying mainly on local
    or bundled content. This is the foundation everything else depends on.

    ## Must Ship

    - [ ] Executable fetch strategies in the source registry
    - [ ] Fetchers for official docs repos, versioned docs pages, release-tagged content,
          and pinned URLs
    - [ ] Persisted source revision, source version, fetch metadata, and last-successful
          sync state
    - [ ] Explicit sync failure states: fetch failed, parse failed, source disappeared,
          extraction drift
    - [ ] Manual and on-demand sync entrypoints through MCP and HTTP/API

    ## Repo Touchpoints

    - `src/sources/source-registry.ts`
    - `src/tools/sync-source.ts`
    - `src/tools/sync-source-doc.ts`
    - `src/sources/sync-state.ts`
    - `src/db/schema.sql`
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m1]
}

resource "gitlab_project_issue" "guardrail_p0_2_provenance" {
  project      = local.guardrail_id
  title        = "P0.2 First-class source provenance and freshness"
  milestone_id = gitlab_project_milestone.guardrail_m1.milestone_id
  labels       = ["enhancement", "priority::critical"]
  description  = <<-EOT
    Serious users need to know exactly where guidance came from and whether it is
    current. Provenance must be visible at every layer.

    ## Must Ship

    - [ ] Source version and revision fields on synced documents and compiled rules
    - [ ] Freshness labels and stale reasons
    - [ ] Last sync and last good sync metadata
    - [ ] Source provenance surfaced in MCP, API, and passive-mode outputs

    ## Repo Touchpoints

    - `src/guidance/types.ts`
    - `src/db/schema.sql`
    - `src/guidance/renderer.ts`
    - `src/sync/instructions.ts`
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m1]
}

resource "gitlab_project_issue" "guardrail_p0_3_review_system" {
  project      = local.guardrail_id
  title        = "P0.3 Explicit review system"
  milestone_id = gitlab_project_milestone.guardrail_m1.milestone_id
  labels       = ["enhancement", "priority::critical"]
  description  = <<-EOT
    Imported guidance cannot silently become active policy. The review model must
    be explicit, auditable, and wired through MCP and API.

    ## Must Ship

    - [ ] Explicit review entities, not just pending rules
    - [ ] Review queue model for new imports and changed upstream revisions
    - [ ] Review decisions with rationale and timestamps
    - [ ] Review diffs tied to source revision and affected packs
    - [ ] Review state surfaced through MCP and HTTP/API

    ## Repo Touchpoints

    - `src/tools/approve-guidance.ts`
    - `src/sync/review-diffs.ts`
    - `src/http-server.ts`
    - `src/db/schema.sql`
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m1]
}

resource "gitlab_project_issue" "guardrail_p0_4_extraction" {
  project      = local.guardrail_id
  title        = "P0.4 Better rule extraction and compilation quality"
  milestone_id = gitlab_project_milestone.guardrail_m1.milestone_id
  labels       = ["enhancement", "priority::critical"]
  description  = <<-EOT
    Noisy or weak extracted rules will kill trust quickly. Extraction must produce
    guidance that is crisp, explainable, and reviewable.

    ## Must Ship

    - [ ] Extraction strategies beyond markdown bullet parsing
    - [ ] Stable imported rule identity across revisions
    - [ ] Deduplication and normalization of equivalent guidance
    - [ ] Evidence references for extracted rules
    - [ ] Validation to reject weak, duplicate, or unsupported compiled guidance

    ## Repo Touchpoints

    - `src/sources/markdown-extractor.ts`
    - `src/tools/import-guidance.ts`
    - `src/import/fingerprint.ts`
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m1]
}

resource "gitlab_project_issue" "guardrail_p0_5_detection" {
  project      = local.guardrail_id
  title        = "P0.5 Version-aware technology detection"
  milestone_id = gitlab_project_milestone.guardrail_m1.milestone_id
  labels       = ["enhancement", "priority::critical"]
  description  = <<-EOT
    If Guardrail cannot identify the real stack and likely versions, it cannot serve
    trustworthy guidance. Detection must be confident and explainable.

    ## Must Ship

    - [ ] Richer version extraction from lockfiles, manifests, runtime configs,
          Dockerfiles, CI files, and provider metadata
    - [ ] Stronger monorepo and mixed-stack detection
    - [ ] Confidence per detected technology/framework/toolchain
    - [ ] Detection diffs exposed through API and MCP

    ## Repo Touchpoints

    - `src/technology/detect.ts`
    - `src/technology/types.ts`
    - `src/tools/detect-technologies.ts`
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m1]
}

resource "gitlab_project_issue" "guardrail_p0_6_packs" {
  project      = local.guardrail_id
  title        = "P0.6 First-class pack model and version-aware resolution"
  milestone_id = gitlab_project_milestone.guardrail_m1.milestone_id
  labels       = ["enhancement", "priority::critical"]
  description  = <<-EOT
    Packs are the main explanation for why a repo gets certain guidance. They must
    be first-class stored entities, not thin resolver conveniences.

    ## Must Ship

    - [ ] Stored pack state per project
    - [ ] Explicit pack source set, resolved version, review policy, activation
          reasons, and state
    - [ ] Version-aware resolution instead of mostly static selectors
    - [ ] Richer "why attached / why not attached" output

    ## Repo Touchpoints

    - `src/packs/resolver.ts`
    - `src/packs/types.ts`
    - `src/policy/compose.ts`
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m1]
}

resource "gitlab_project_issue" "guardrail_p0_7_passive_mode" {
  project      = local.guardrail_id
  title        = "P0.7 Trustworthy passive-mode outputs"
  milestone_id = gitlab_project_milestone.guardrail_m1.milestone_id
  labels       = ["enhancement", "priority::critical"]
  description  = <<-EOT
    Serious users work across clients that depend on local instruction files. Passive
    outputs must be safe projections of reviewed policy, not noisy dumps.

    ## Must Ship

    - [ ] Target-specific projection rules for `AGENTS.md` and `CLAUDE.md`
    - [ ] Approved guidance only — never project unapproved or stale guidance silently
    - [ ] Visible provenance, freshness, and review-backed status in outputs
    - [ ] Omission or warning behavior for stale or pending guidance
    - [ ] Preview and diff before sync

    ## Repo Touchpoints

    - `src/sync/instructions.ts`
    - `src/tools/sync-instructions.ts`
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m1]
}

resource "gitlab_project_issue" "guardrail_p0_8_mcp_preflight" {
  project      = local.guardrail_id
  title        = "P0.8 MCP preflight that feels indispensable"
  milestone_id = gitlab_project_milestone.guardrail_m1.milestone_id
  labels       = ["enhancement", "priority::critical"]
  description  = <<-EOT
    MCP is the strongest path to active guidance consumption by coding agents. It is
    the flagship interface and must feel that way.

    ## Must Ship

    - [ ] Hardened `get_guidance_context` and `get_effective_policy`
    - [ ] Stable structured outputs for guidance, warnings, stale state, missing
          coverage, and blockers
    - [ ] Higher-level preflight workflow support
    - [ ] Reduced noise and clearer reasoning in rendered outputs

    ## Repo Touchpoints

    - `src/tools/get-guidance-context.ts`
    - `src/tools/get-effective-policy.ts`
    - `src/guidance/context.ts`
    - `src/guidance/renderer.ts`
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m1]
}

resource "gitlab_project_issue" "guardrail_p0_9_bootstrap" {
  project      = local.guardrail_id
  title        = "P0.9 Bootstrap and install experience"
  milestone_id = gitlab_project_milestone.guardrail_m1.milestone_id
  labels       = ["enhancement", "priority::critical"]
  description  = <<-EOT
    If setup is annoying, users will skip Guardrail even if the core is good. Zero
    to useful must be minutes, not hours.

    ## Must Ship

    - [ ] One-command bootstrap
    - [ ] First-run: detection, pack attachment, default source sync, passive projection
    - [ ] `guardrail doctor` / status command (service, staleness, pending reviews,
          coverage gaps)
    - [ ] Sane solo-user defaults

    ## Repo Touchpoints

    - `src/bootstrap/bootstrap-project.ts`
    - `src/bootstrap/project-root.ts`
    - `src/config/config.ts`
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m1]
}

resource "gitlab_project_issue" "guardrail_p0_10_cleanup" {
  project      = local.guardrail_id
  title        = "P0.10 Product cleanup of WAR-shaped setup/config seams"
  milestone_id = gitlab_project_milestone.guardrail_m1.milestone_id
  labels       = ["enhancement", "priority::high"]
  description  = <<-EOT
    Standalone product credibility suffers when core setup surfaces still look
    transitional or platform-shell-shaped from the WAR origin.

    ## Must Ship

    - [ ] Rename remaining WAR-shaped config types and helpers
    - [ ] Remove platform-shell semantics from live setup/config surfaces
    - [ ] Make package and config naming consistent with standalone Guardrail

    ## Repo Touchpoints

    - `packages/config/src/index.ts`
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m1]
}

###############################################
# P1 Issues — Milestones 2 and 3
###############################################
# M2 "Useful Daily": matching, pack layering, coverage diagnostics, source strategy
# M3 "Hard to Skip": authz/API, operator surfaces, agent-surface recipes

resource "gitlab_project_issue" "guardrail_p1_1_matching" {
  project      = local.guardrail_id
  title        = "P1.1 Stronger matching intelligence"
  milestone_id = gitlab_project_milestone.guardrail_m2.milestone_id
  labels       = ["enhancement", "priority::high"]
  description  = <<-EOT
    Matching on globs and token overlap is not enough. Guardrail must feel like
    project judgment, not a rule bucket.

    ## Must Ship

    - [ ] Move beyond globs and token overlap
    - [ ] Match on service area, changed files, task type, risk class, and
          monorepo package/workspace
    - [ ] Distinguish baseline guidance, task guidance, warnings, and blockers
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m2]
}

resource "gitlab_project_issue" "guardrail_p1_5_pack_layering" {
  project      = local.guardrail_id
  title        = "P1.5 Better pack layering"
  milestone_id = gitlab_project_milestone.guardrail_m2.milestone_id
  labels       = ["enhancement", "priority::high"]
  description  = <<-EOT
    Pack composition must support team and org contexts, and override semantics must
    be explicit and inspectable.

    ## Must Ship

    - [ ] Add org/team/project override layers
    - [ ] Add temporary overrides and waivers
    - [ ] Make precedence and override reasoning more explicit
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m2]
}

resource "gitlab_project_issue" "guardrail_p1_6_coverage_diagnostics" {
  project      = local.guardrail_id
  title        = "P1.6 Coverage diagnostics"
  milestone_id = gitlab_project_milestone.guardrail_m2.milestone_id
  labels       = ["enhancement", "priority::high"]
  description  = <<-EOT
    Guardrail must warn when it cannot help. Missing, stale, or review-blocked
    coverage is information that must reach the user.

    ## Must Ship

    - [ ] Detect unsupported stacks
    - [ ] Detect no-source and no-pack cases
    - [ ] Detect stale-backed active policy
    - [ ] Detect pending-review gaps that affect the current task
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m2]
}

resource "gitlab_project_issue" "guardrail_p1_7_source_strategy" {
  project      = local.guardrail_id
  title        = "P1.7 Stronger bootstrap source strategy"
  milestone_id = gitlab_project_milestone.guardrail_m2.milestone_id
  labels       = ["enhancement", "priority::high"]
  description  = <<-EOT
    Bundled guidance should become a fallback, not the default. Seeded
    authoritative-source sync is the right default for new installs.

    ## Must Ship

    - [ ] Move from bundled guidance as a stopgap toward seeded authoritative-source sync
    - [ ] Keep bundled content only as fallback or offline bootstrap
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m2]
}

resource "gitlab_project_issue" "guardrail_p1_2_authz_api" {
  project      = local.guardrail_id
  title        = "P1.2 Project-aware authorization and safer HTTP/API exposure"
  milestone_id = gitlab_project_milestone.guardrail_m3.milestone_id
  labels       = ["enhancement", "priority::high", "security"]
  description  = <<-EOT
    One shared service token is not a real auth model. The API must be safe to
    expose to operator tooling without being a brittle internal-only server.

    ## Must Ship

    - [ ] Replace one shared service-token model with project-aware authz
    - [ ] Formalize route schemas and split route logic into service layers
    - [ ] Add policy explanation, review, and coverage endpoints

    ## Repo Touchpoints

    - `packages/auth/src/index.ts`
    - `src/http-server.ts`
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m3]
}

resource "gitlab_project_issue" "guardrail_p1_3_operator_surfaces" {
  project      = local.guardrail_id
  title        = "P1.3 Operator and reviewer control surfaces"
  milestone_id = gitlab_project_milestone.guardrail_m3.milestone_id
  labels       = ["enhancement", "priority::high"]
  description  = <<-EOT
    Humans need a manageable control plane. Teams must be able to manage Guardrail
    without drowning in review noise.

    ## Must Ship

    - [ ] Source health view
    - [ ] Active packs view
    - [ ] Pending reviews queue
    - [ ] Stale coverage view
    - [ ] Effective policy explanation
    - [ ] Review-impact previews before approval
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m3]
}

resource "gitlab_project_issue" "guardrail_p1_4_agent_coverage" {
  project      = local.guardrail_id
  title        = "P1.4 Agent-surface-specific delivery recipes"
  milestone_id = gitlab_project_milestone.guardrail_m3.milestone_id
  labels       = ["enhancement", "priority::high"]
  description  = <<-EOT
    Guardrail must not be generic in theory only. It must be concretely usable in
    each major agent environment with documented, validated setup.

    ## Must Ship

    - [ ] Validate and document Guardrail workflows for Claude Code, Codex, Cursor,
          Windsurf, and Replit
    - [ ] Define recommended setup per client (MCP, local file sync, API bridge,
          or wrapper workflow)
    - [ ] Align passive projections with each tool's real behavior
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m3]
}

###############################################
# P2 Issues — Milestone 4: Guardrail is Product-Grade
###############################################

resource "gitlab_project_issue" "guardrail_p2_1_enforcement" {
  project      = local.guardrail_id
  title        = "P2.1 Advisory, warn, and block workflow modes"
  milestone_id = gitlab_project_milestone.guardrail_m4.milestone_id
  labels       = ["enhancement", "priority::medium"]
  description  = <<-EOT
    Move from advisory guidance to relied-on workflow control. Enforcement must be
    optional at first, but designed from the start.

    ## Must Ship

    - [ ] Add policy states: advisory, warn, block
    - [ ] Add high-risk workflow gating (secrets, auth/security code, infra changes,
          destructive migrations, prod config)
    - [ ] Add override and exception workflows with expiration and rationale capture
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m4]
}

resource "gitlab_project_issue" "guardrail_p2_2_proof_of_value" {
  project      = local.guardrail_id
  title        = "P2.2 Evaluation harness and proof-of-value framework"
  milestone_id = gitlab_project_milestone.guardrail_m4.milestone_id
  labels       = ["enhancement", "priority::medium"]
  description  = <<-EOT
    Guardrail becomes mandatory only if it makes coding agents materially more correct
    on real codebases. Evidence is required, not just claims.

    ## Must Ship

    - [ ] Benchmark before/after coding-agent behavior on representative repos
    - [ ] Track stale-source rate, preflight usage, and guidance impact metrics
    - [ ] Instrument preflight usage, passive sync coverage, pack activation coverage
    - [ ] Prove Guardrail improves outcomes on real repos
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m4]
}

resource "gitlab_project_issue" "guardrail_p2_3_distribution" {
  project      = local.guardrail_id
  title        = "P2.3 Team workflows and distribution polish"
  milestone_id = gitlab_project_milestone.guardrail_m4.milestone_id
  labels       = ["enhancement", "priority::medium"]
  description  = <<-EOT
    Guardrail must be installable, upgradeable, and usable by teams without heavy
    ceremony.

    ## Must Ship

    - [ ] Stable packaging and upgrade flow
    - [ ] Migration-safe storage evolution
    - [ ] Shared deployments and collaboration-friendly workflows
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m4]
}

resource "gitlab_project_issue" "guardrail_p2_4_operator_ux" {
  project      = local.guardrail_id
  title        = "P2.4 Richer operator UX"
  milestone_id = gitlab_project_milestone.guardrail_m4.milestone_id
  labels       = ["enhancement", "priority::medium"]
  description  = <<-EOT
    The operator control plane needs polish for teams managing Guardrail at scale.

    ## Must Ship

    - [ ] Polished admin views
    - [ ] Better review diff presentation
    - [ ] Project history and lineage views
    - [ ] Impact summaries across repos and packs
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m4]
}

resource "gitlab_project_issue" "guardrail_p2_5_ecosystem_depth" {
  project      = local.guardrail_id
  title        = "P2.5 Expanded ecosystem depth"
  milestone_id = gitlab_project_milestone.guardrail_m4.milestone_id
  labels       = ["enhancement", "priority::medium"]
  description  = <<-EOT
    Broader and deeper ecosystem coverage increases adoption surface and guidance
    quality for long-tail stacks.

    ## Must Ship

    - [ ] Deeper official-source coverage for major ecosystems
          (TypeScript/Node, Python, Go, Rust, Docker, Terraform, Kubernetes)
    - [ ] Better version negotiation for long-tail frameworks and platform stacks
  EOT

  depends_on = [gitlab_project_milestone.guardrail_m4]
}
