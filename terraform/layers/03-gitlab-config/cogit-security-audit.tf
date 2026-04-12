# =============================================================================
# Cogit — Security Audit Roadmap: M11 Issues
# =============================================================================
# Bootstraps all findings from the March 2026 comprehensive security audit
# into GitLab as trackable issues under Milestone 11.
#
# Audit scope: full application stack evaluated against FedRAMP and NIST
# 800-53 requirements for GovCloud AWS deployment.
#
# Findings: 22 total (1 CRITICAL, 8 HIGH, 9 MEDIUM, 4 LOW)
#
# Severity → label mapping:
#   CRITICAL → severity::critical, priority::critical
#   HIGH     → severity::high, priority::high
#   MEDIUM   → severity::medium, priority::medium
#   LOW      → severity::low, priority::low
#
# Remediation phases:
#   Week 1-2: CRITICAL + HIGH (SA-01 through SA-09)
#   Week 3-4: MEDIUM (SA-10 through SA-17)
#   Week 5-6: LOW + process (SA-18 through SA-22)
# =============================================================================

locals {
  cogit_project_id       = gitlab_project.projects["cogit"].id
  cogit_m11_milestone_id = gitlab_project_milestone.cogit["m11"].milestone_id
}

###############################################
# M11 Tracking Issue
###############################################

resource "gitlab_project_issue" "cogit_m11_tracking" {
  project      = local.cogit_project_id
  title        = "M11: Security Audit Remediation — master tracking"
  state        = "opened"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "priority::critical"]
  description  = <<-EOT
    Master tracking issue for Milestone 11: Security Audit Remediation.

    Full audit report: `cogit-security-audit-report.docx` in repo root.

    ## Summary

    | Severity | Count | Blocking? |
    |----------|-------|-----------|
    | CRITICAL | 1 | Yes |
    | HIGH | 8 | Yes |
    | MEDIUM | 9 | Yes (FedRAMP) |
    | LOW | 4 | No |

    ## Phase 1: Immediate (Week 1-2) — CRITICAL + HIGH

    - [ ] SA-01: x-cogit-caller-context header allows full auth bypass
    - [ ] SA-02: Health endpoint discloses auth configuration
    - [ ] SA-03: Workbench proxy header auth without signature validation
    - [ ] SA-04: No CSRF protection on mutation endpoints
    - [ ] SA-05: No HTTP request body size limit on service
    - [ ] SA-06: MCP adapter stdin buffer unbounded
    - [ ] SA-07: No rate limiting on any endpoint
    - [ ] SA-08: Security scans set to allow_failure in CI/CD
    - [ ] SA-09: --no-audit flag in container builds

    ## Phase 2: Short-Term (Week 3-4) — MEDIUM

    - [ ] SA-10: No HSTS (Strict-Transport-Security) header
    - [ ] SA-11: CSP allows unsafe-inline for styles
    - [ ] SA-12: Nginx reverse proxy not hardened
    - [ ] SA-13: Containers run as root
    - [ ] SA-14: No image signing or SBOM generation
    - [ ] SA-15: Insecure registry communication enabled
    - [ ] SA-16: No database row-level security
    - [ ] SA-17: Audit events table is mutable
    - [ ] SA-18: Hardcoded PostgreSQL credentials in compose files

    ## Phase 3: Medium-Term (Week 5-6) — LOW + Process

    - [ ] SA-19: Incomplete logging redaction key coverage
    - [ ] SA-20: No CORS policy configured
    - [ ] SA-21: Missing security response headers
    - [ ] SA-22: SonarQube exports committed to repository

    ## Exit Criteria

    - All CRITICAL and HIGH findings verified resolved via automated tests
    - All MEDIUM findings resolved or documented with approved risk acceptance
    - NIST 800-53 control mapping shows no FAIL ratings on AC-3, SC-5, SC-8, SC-23
    - Re-audit confirms FedRAMP readiness
    - Penetration test scheduled and scoped
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

###############################################
# CRITICAL Findings
###############################################

resource "gitlab_project_issue" "cogit_sa01" {
  project      = local.cogit_project_id
  title        = "SA-01: x-cogit-caller-context header allows full auth bypass"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::critical", "priority::critical", "scope::auth", "nist::ac", "nist::ia"]
  description  = <<-EOT
    ## Finding: CRITICAL

    **NIST Controls:** AC-3, IA-2
    **Location:** `apps/service/src/index.ts:9186-9210`, `packages/shared-schemas/src/index.ts:219-272`

    ## Description

    When `trustHttpCallerHeaders` is enabled, any HTTP client can inject an arbitrary JSON caller
    context via the `x-cogit-caller-context` header. The `parseCallerContext` function accepts
    attacker-supplied `principalType`, `capabilities`, and `isAuthenticated` flag without server-side
    verification against any identity store. An attacker can claim `admin:system` capability and
    full authentication status.

    ## Impact

    Complete authentication and authorization bypass. Attacker gains arbitrary capabilities
    including `admin:system`, `write:policy`, and `write:memory`. All access controls become advisory.

    ## Attack Vector

    ```bash
    curl -X POST http://target/api/policy/reviews \
      -H 'x-cogit-caller-context: {"principalId":"attacker","principalType":"user","authMethod":"local","isAuthenticated":true,"capabilities":["admin:system","write:policy"],"scopes":["*"]}' \
      -H 'Content-Type: application/json' \
      -d '{"policyId":"critical","decision":"approve"}'
    ```

    ## Remediation

    - [ ] Implement HMAC signature validation on the `x-cogit-caller-context` header
    - [ ] Reverse proxy must sign the header with a shared secret
    - [ ] Service must verify the HMAC before trusting the content
    - [ ] Strip the header at the edge proxy for requests originating outside the trusted network
    - [ ] Add integration test: unsigned header is rejected with 403
    - [ ] Add integration test: tampered header is rejected with 403

    ## Repo Touchpoints

    - `apps/service/src/index.ts` — `resolveHttpCaller` function
    - `packages/shared-schemas/src/index.ts` — `parseCallerContext` function
    - `packages/platform-auth/src/index.ts` — capability validation
    - `ops/docker/workbench-proxy.nginx.conf` — header stripping
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

###############################################
# HIGH Findings
###############################################

resource "gitlab_project_issue" "cogit_sa02" {
  project      = local.cogit_project_id
  title        = "SA-02: Health endpoint discloses auth configuration"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::high", "priority::high", "scope::api", "nist::ac", "nist::si"]
  description  = <<-EOT
    ## Finding: HIGH

    **NIST Controls:** AC-3, SI-11
    **Location:** `apps/service/src/index.ts:7159-7172, 1345-1350`

    ## Description

    The unauthenticated `/api/health` endpoint returns the full auth configuration including whether
    `trustHttpCallerHeaders` is enabled, whether `allowAnonymousLocalReads` is true, and the exact
    default capabilities assigned to unauthenticated callers. This provides an attacker with a
    complete reconnaissance map of the authentication posture, confirming whether SA-01 is exploitable.

    ## Impact

    Attacker can determine if SA-01 (caller context injection) is exploitable before attempting it.
    Reveals database backend type, migration status, and deployment posture.

    ## Remediation

    - [ ] Move all auth configuration details behind a `read:ops` capability check
    - [ ] Health endpoint should return only `status: ok/degraded` and basic version info
    - [ ] Readiness endpoint should omit `caller_header_mode` detail for unauthenticated requests
    - [ ] Add test: unauthenticated `/api/health` does not contain auth config

    ## Repo Touchpoints

    - `apps/service/src/index.ts` — health handler, `getServiceStatus` function
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa03" {
  project      = local.cogit_project_id
  title        = "SA-03: Workbench proxy header auth without signature validation"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::high", "priority::high", "scope::auth", "scope::infra", "nist::ac", "nist::ia"]
  description  = <<-EOT
    ## Finding: HIGH

    **NIST Controls:** AC-3, IA-2, IA-8
    **Location:** `apps/workbench/src/index.ts:496-509`, `ops/docker/workbench-proxy.nginx.conf`

    ## Description

    The workbench trusts `x-cogit-workbench-user` and `x-forwarded-user` headers for authentication.
    These headers are trivially spoofable by any client that can reach the workbench port. The nginx
    proxy config hardcodes `local-operator` without any actual authentication (`auth_basic` or
    `auth_request`). If the workbench port is exposed, any client is authenticated as `local-operator`.

    Additionally, the actor ID resolved from these headers is injected into mutation request bodies
    (`initiatedBy`, `decidedBy`, `createdBy`, `actorId`), meaning an attacker can poison the audit
    trail by spoofing the user identity header.

    ## Impact

    Authentication bypass on all workbench mutations including policy reviews, task creation, and
    configuration changes. Audit trail poisoning via actor ID injection.

    ## Remediation

    - [ ] Add HMAC signature validation on proxy user headers
    - [ ] Implement `auth_basic` or `auth_request` in nginx config
    - [ ] Never hardcode user identities in proxy config
    - [ ] Strip proxy auth headers from client requests at the edge
    - [ ] Create `workbench-proxy.managed.nginx.conf.example` with real auth
    - [ ] Add test: spoofed `X-Forwarded-User` header is rejected without valid HMAC

    ## Repo Touchpoints

    - `apps/workbench/src/index.ts` — `isWorkbenchRequestAuthorized`, `resolveWorkbenchActorId`, `injectWorkbenchActorField`
    - `ops/docker/workbench-proxy.nginx.conf` — proxy auth config
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa04" {
  project      = local.cogit_project_id
  title        = "SA-04: No CSRF protection on mutation endpoints"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::high", "priority::high", "scope::frontend", "scope::api", "nist::sc"]
  description  = <<-EOT
    ## Finding: HIGH

    **NIST Controls:** SC-23, SI-10
    **Location:** `apps/workbench/src/index.ts` (all POST/PUT/PATCH routes)

    ## Description

    No CSRF tokens, double-submit cookies, SameSite cookie attributes, or origin validation exist
    on any mutation endpoint. A cross-site request from a malicious page can trigger policy approvals,
    task creation, memory writes, and configuration changes if the user has an active session.

    ## Impact

    Cross-site request forgery allows unauthorized state mutations. Policy decisions, audit-trail
    entries, and configuration changes can be triggered by visiting a malicious website.

    ## Remediation

    - [ ] Implement synchronizer token pattern (CSRF tokens) on all state-changing endpoints
    - [ ] Set `SameSite=Strict` on all cookies
    - [ ] Validate `Origin` and `Referer` headers on mutations
    - [ ] Add test: mutation without valid CSRF token returns 403
    - [ ] Add test: cross-origin mutation request is rejected

    ## Repo Touchpoints

    - `apps/workbench/src/index.ts` — `proxyWorkbenchMutation`, all POST/PUT/PATCH route handlers
    - `packages/platform-http/src/index.ts` — request handling
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa05" {
  project      = local.cogit_project_id
  title        = "SA-05: No HTTP request body size limit on service"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::high", "priority::high", "scope::api", "nist::sc"]
  description  = <<-EOT
    ## Finding: HIGH

    **NIST Controls:** SC-5
    **Location:** `apps/service/src/index.ts` (readRequestBody function)

    ## Description

    While the workbench enforces a 1MB body limit via `MAX_WORKBENCH_REQUEST_BODY_BYTES`, the
    service HTTP handler does not enforce a body size limit on all paths. An attacker can send an
    arbitrarily large POST body to exhaust process memory.

    ## Impact

    Denial of service via memory exhaustion. A single large request can crash the service process.

    ## Remediation

    - [ ] Enforce `MAX_HTTP_REQUEST_BODY_BYTES` (1MB) on all service request body reads
    - [ ] Return HTTP 413 Payload Too Large when exceeded
    - [ ] Add test: POST body exceeding 1MB returns 413
    - [ ] Verify all code paths through `readRequestBody` / `parseJsonBody` enforce the limit

    ## Repo Touchpoints

    - `apps/service/src/index.ts` — `readRequestBody`, `parseJsonBody`, request handler
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa06" {
  project      = local.cogit_project_id
  title        = "SA-06: MCP adapter stdin buffer unbounded"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::high", "priority::high", "scope::api", "nist::sc"]
  description  = <<-EOT
    ## Finding: HIGH

    **NIST Controls:** SC-5
    **Location:** `apps/mcp-adapter/src/index.ts:70-76`

    ## Description

    The MCP stdio adapter reads from stdin without an upper bound on buffer size. Malformed or
    malicious input can grow the buffer indefinitely until the process runs out of memory.

    ## Impact

    Denial of service on any system running the MCP adapter. Particularly dangerous in IDE
    integrations where the adapter runs alongside the developer's tools.

    ## Remediation

    - [ ] Set maximum buffer size of 10MB
    - [ ] Emit error and close connection on overflow
    - [ ] Add test: input exceeding 10MB triggers error and graceful shutdown

    ## Repo Touchpoints

    - `apps/mcp-adapter/src/index.ts` — stdin read loop, buffer accumulation
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa07" {
  project      = local.cogit_project_id
  title        = "SA-07: No rate limiting on any endpoint"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::high", "priority::high", "scope::api", "scope::infra", "nist::sc", "nist::si"]
  description  = <<-EOT
    ## Finding: HIGH

    **NIST Controls:** SC-5, SI-10
    **Location:** `apps/service/src/index.ts`, `apps/workbench/src/index.ts`

    ## Description

    No application-layer rate limiting exists on any HTTP endpoint. Preflight runs, ingest
    operations, registration, and policy mutations are all unbounded.

    ## Impact

    Denial of service via request flooding. Resource exhaustion on database and compute.
    Brute-force attacks on any future authentication mechanism.

    ## Remediation

    - [ ] Implement per-IP sliding window rate limiting
    - [ ] Read endpoints: 100-1000 req/min
    - [ ] Write endpoints: 10-50 req/min
    - [ ] Preflight/ingest: 20-100 req/min
    - [ ] Return HTTP 429 Too Many Requests with `Retry-After` header
    - [ ] Add test: exceeding rate limit returns 429
    - [ ] Consider nginx-level `limit_req_zone` as defense-in-depth

    ## Repo Touchpoints

    - `apps/service/src/index.ts` — request handler, new middleware
    - `apps/workbench/src/index.ts` — request handler, new middleware
    - `ops/docker/workbench-proxy.nginx.conf` — `limit_req_zone`
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa08" {
  project      = local.cogit_project_id
  title        = "SA-08: Security scans set to allow_failure in CI/CD"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::high", "priority::high", "scope::cicd", "nist::sa", "nist::si"]
  description  = <<-EOT
    ## Finding: HIGH

    **NIST Controls:** SA-10, SA-11, SI-2
    **Location:** `.gitlab-ci.yml:182,196,318`

    ## Description

    Semgrep SAST and Trivy vulnerability scanning are configured with `allow_failure: true`.
    This means HIGH and CRITICAL security findings do not block image publication or deployment.

    ## Impact

    Known vulnerabilities can be deployed to production. FedRAMP SI-2 (Flaw Remediation) requires
    that identified vulnerabilities are remediated before deployment.

    ## Remediation

    - [ ] Set `allow_failure: false` on `security:semgrep` job
    - [ ] Set `allow_failure: false` on `security:trivy:fs` job
    - [ ] Establish a documented exception process for false positives (via `.trivyignore` and semgrep exclusions)
    - [ ] Add baseline files for known acceptable findings
    - [ ] Verify pipeline blocks on HIGH/CRITICAL findings

    ## Repo Touchpoints

    - `.gitlab-ci.yml` — `security:semgrep`, `security:trivy:fs` jobs
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa09" {
  project      = local.cogit_project_id
  title        = "SA-09: --no-audit flag in container builds"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::high", "priority::high", "scope::infra", "scope::cicd", "nist::sa"]
  description  = <<-EOT
    ## Finding: HIGH

    **NIST Controls:** SA-10, SA-11
    **Location:** `ops/docker/service.Dockerfile:21`, `ops/docker/workbench.Dockerfile`

    ## Description

    Both Dockerfiles use `npm ci --no-audit` which suppresses npm's built-in vulnerability
    check during image builds. This means known-vulnerable packages are installed silently.

    ## Impact

    Supply chain vulnerability gap. Images may contain packages with known CVEs that would
    have been caught by `npm audit`.

    ## Remediation

    - [ ] Remove `--no-audit` flag from both Dockerfiles
    - [ ] Add a separate `RUN npm audit --audit-level=high` step after `npm ci`
    - [ ] Verify the build fails if a HIGH or CRITICAL vulnerability is found
    - [ ] Add test: build with known-vulnerable package fails

    ## Repo Touchpoints

    - `ops/docker/service.Dockerfile` — `npm ci` command
    - `ops/docker/workbench.Dockerfile` — `npm ci` command
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

###############################################
# MEDIUM Findings
###############################################

resource "gitlab_project_issue" "cogit_sa10" {
  project      = local.cogit_project_id
  title        = "SA-10: No HSTS (Strict-Transport-Security) header"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::medium", "priority::medium", "scope::api", "scope::frontend", "nist::sc"]
  description  = <<-EOT
    ## Finding: MEDIUM

    **NIST Controls:** SC-8, SC-23
    **Location:** `apps/workbench/src/index.ts:3042-3052`, `apps/service/src/index.ts`

    ## Description

    Neither the service nor workbench sets the `Strict-Transport-Security` header. This allows
    protocol downgrade attacks where a MITM can strip TLS and serve content over plain HTTP.

    ## Remediation

    - [ ] Add `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload` to all responses
    - [ ] Add to `applySecurityHeaders` in both service and workbench
    - [ ] Add test: all responses include HSTS header

    ## Repo Touchpoints

    - `apps/workbench/src/index.ts` — `applySecurityHeaders`
    - `apps/service/src/index.ts` — response headers
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa11" {
  project      = local.cogit_project_id
  title        = "SA-11: CSP allows unsafe-inline for styles"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::medium", "priority::medium", "scope::frontend", "nist::si"]
  description  = <<-EOT
    ## Finding: MEDIUM

    **NIST Controls:** SI-3
    **Location:** `apps/workbench/src/index.ts:3042-3052`

    ## Description

    The Content-Security-Policy header includes `style-src 'unsafe-inline'` because the workbench
    generates inline `<style>` blocks at runtime. This weakens XSS protections.

    ## Remediation

    - [ ] Move inline styles to an external CSS file served from the same origin
    - [ ] Update CSP to `style-src 'self'`
    - [ ] Add test: CSP header does not contain `unsafe-inline`

    ## Repo Touchpoints

    - `apps/workbench/src/index.ts` — `applySecurityHeaders`, HTML generation
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa12" {
  project      = local.cogit_project_id
  title        = "SA-12: Nginx reverse proxy not hardened"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::medium", "priority::medium", "scope::infra", "nist::sc", "nist::cm"]
  description  = <<-EOT
    ## Finding: MEDIUM

    **NIST Controls:** SC-5, SC-7, SC-8, CM-6
    **Location:** `ops/docker/workbench-proxy.nginx.conf`

    ## Description

    The nginx configuration lacks `server_tokens off` (leaks version), has no TLS block, no rate
    limiting (`limit_req_zone`), no security response headers, and hardcodes a static user identity.

    ## Remediation

    - [ ] Add `server_tokens off`
    - [ ] Add TLS configuration block with modern cipher suite
    - [ ] Add `limit_req_zone` with per-IP rate limiting
    - [ ] Add security headers: HSTS, X-Content-Type-Options, X-Frame-Options
    - [ ] Create `workbench-proxy.managed.nginx.conf.example` with production-ready config
    - [ ] Replace hardcoded `local-operator` with dynamic `$remote_user` from real auth
    - [ ] Add comments marking the existing config as local-development-only

    ## Repo Touchpoints

    - `ops/docker/workbench-proxy.nginx.conf` — full rewrite for managed posture
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa13" {
  project      = local.cogit_project_id
  title        = "SA-13: Containers run as root"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::medium", "priority::medium", "scope::infra", "nist::ac", "nist::cm"]
  description  = <<-EOT
    ## Finding: MEDIUM

    **NIST Controls:** AC-6, CM-6
    **Location:** `ops/docker/service.Dockerfile`, `ops/docker/workbench.Dockerfile`

    ## Description

    Neither Dockerfile contains a `USER` directive. Both containers run as root by default,
    violating the principle of least privilege.

    ## Remediation

    - [ ] Add `USER node:node` to both Dockerfiles before ENTRYPOINT
    - [ ] Ensure writable directories (state, logs) are owned by the `node` user
    - [ ] Add `HEALTHCHECK` instruction to both Dockerfiles
    - [ ] Add test: container process runs as non-root

    ## Repo Touchpoints

    - `ops/docker/service.Dockerfile`
    - `ops/docker/workbench.Dockerfile`
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa14" {
  project      = local.cogit_project_id
  title        = "SA-14: No image signing or SBOM generation"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::medium", "priority::medium", "scope::cicd", "nist::si", "nist::sa", "nist::cm"]
  description  = <<-EOT
    ## Finding: MEDIUM

    **NIST Controls:** SI-7, SA-10, CM-8
    **Location:** CI/CD pipeline (image publish stage)

    ## Description

    Published container images are not cryptographically signed. No Software Bill of Materials
    (SBOM) is generated. There is no way to verify image provenance or audit the dependency tree.

    ## Remediation

    - [ ] Implement Cosign for container image signing in the publish stage
    - [ ] Generate SBOM using Syft or CycloneDX during the package stage
    - [ ] Attach SBOM as an attestation to the registry image
    - [ ] Add verification step: deployment rejects unsigned images
    - [ ] Store signing keys in Vault

    ## Repo Touchpoints

    - `.gitlab-ci.yml` — `image:publish:service`, `image:publish:workbench` jobs
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa15" {
  project      = local.cogit_project_id
  title        = "SA-15: Insecure registry communication enabled"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::medium", "priority::medium", "scope::cicd", "nist::sc"]
  description  = <<-EOT
    ## Finding: MEDIUM

    **NIST Controls:** SC-8
    **Location:** `.gitlab-ci.yml:354`

    ## Description

    The CI/CD pipeline sets `COGIT_REGISTRY_INSECURE: true` for deployment triggers, enabling
    unencrypted HTTP communication with the container registry.

    ## Remediation

    - [ ] Set `COGIT_REGISTRY_INSECURE: false`
    - [ ] Configure TLS certificates for the internal registry
    - [ ] Verify deployment triggers use HTTPS for registry communication

    ## Repo Touchpoints

    - `.gitlab-ci.yml` — deploy stage variables
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa16" {
  project      = local.cogit_project_id
  title        = "SA-16: No database row-level security"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::medium", "priority::medium", "scope::database", "nist::ac"]
  description  = <<-EOT
    ## Finding: MEDIUM

    **NIST Controls:** AC-3, AC-6
    **Location:** `migrations/postgres/`

    ## Description

    PostgreSQL migrations do not implement Row-Level Security (RLS) policies. All authenticated
    users can access all data regardless of their principal identity. Access control is enforced
    only at the service layer.

    ## Impact

    If an attacker bypasses the application layer (e.g., via SA-01), they have unrestricted
    access to all data. No defense-in-depth at the database level.

    ## Remediation

    - [ ] Design RLS policies for sensitive tables (projects, conversations, reviews, audit_events)
    - [ ] Create PostgreSQL roles corresponding to application principal types
    - [ ] Enable row filtering based on project/workspace ownership
    - [ ] Add migration to apply RLS policies
    - [ ] Add parity test: RLS enforcement matches application-layer authorization

    ## Repo Touchpoints

    - `migrations/postgres/` — new migration for RLS
    - `packages/platform-db/src/index.ts` — connection role setting
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa17" {
  project      = local.cogit_project_id
  title        = "SA-17: Audit events table is mutable"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::medium", "priority::medium", "scope::database", "nist::au"]
  description  = <<-EOT
    ## Finding: MEDIUM

    **NIST Controls:** AU-9, AU-10
    **Location:** `migrations/sqlite/0001`, `migrations/postgres/0001`

    ## Description

    The `audit_events` table has no database-level protection against UPDATE or DELETE operations.
    An attacker with database access can modify or destroy audit records.

    ## Remediation

    - [ ] PostgreSQL: add trigger `BEFORE UPDATE OR DELETE ON audit_events RAISE EXCEPTION 'Audit events are immutable'`
    - [ ] SQLite: add trigger with `SELECT RAISE(ABORT, 'Audit events are immutable')`
    - [ ] Add migration for both backends
    - [ ] Add test: UPDATE on audit_events fails with error
    - [ ] Add test: DELETE on audit_events fails with error
    - [ ] Consider append-only table pattern or WAL-based audit export

    ## Repo Touchpoints

    - `migrations/sqlite/` — new migration
    - `migrations/postgres/` — new migration
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa18" {
  project      = local.cogit_project_id
  title        = "SA-18: Hardcoded PostgreSQL credentials in compose files"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::medium", "priority::medium", "scope::infra", "nist::ia"]
  description  = <<-EOT
    ## Finding: MEDIUM

    **NIST Controls:** IA-5
    **Location:** `compose.postgres.yaml`, `.gitlab-ci.yml`

    ## Description

    Default database credentials (`user: cogit`, `password: cogit`) are hardcoded in compose files
    and CI configuration. While intended for local development and testing, the pattern could be
    copied to production.

    ## Remediation

    - [ ] Use environment variable references in compose files
    - [ ] Add a CI check that verifies no hardcoded passwords appear in deployment-targeted files
    - [ ] Add `.env.example` with placeholder values
    - [ ] Document that production deployments must use Vault-backed credentials

    ## Repo Touchpoints

    - `compose.postgres.yaml`
    - `.gitlab-ci.yml` — PostgreSQL service definitions
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

###############################################
# LOW Findings
###############################################

resource "gitlab_project_issue" "cogit_sa19" {
  project      = local.cogit_project_id
  title        = "SA-19: Incomplete logging redaction key coverage"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::low", "priority::low", "scope::api", "nist::au"]
  description  = <<-EOT
    ## Finding: LOW

    **NIST Controls:** AU-3, SI-11
    **Location:** `packages/platform-logging/src/index.ts`

    ## Description

    Default redaction keys cover `authorization`, `cookie`, `password`, `secret`, and `token`.
    However, `connectionstring`, `postgresurl`, `dburi`, and vault-prefixed keys are not covered.

    ## Remediation

    - [ ] Add `connectionstring`, `postgresurl`, `dburi`, `databaseurl`, `vault` to default redaction keys
    - [ ] Add test: log entry containing a postgres URL is redacted

    ## Repo Touchpoints

    - `packages/platform-logging/src/index.ts` — default redaction key list
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa20" {
  project      = local.cogit_project_id
  title        = "SA-20: No CORS policy configured"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::low", "priority::low", "scope::api", "nist::sc"]
  description  = <<-EOT
    ## Finding: LOW

    **NIST Controls:** SC-23
    **Location:** `apps/service/src/index.ts`, `apps/workbench/src/index.ts`

    ## Description

    No explicit CORS headers or preflight handling exists. The application relies on same-origin
    policy and network isolation for cross-origin protection.

    ## Remediation

    - [ ] Implement an explicit CORS policy with a strict allowlist of trusted origins
    - [ ] Handle OPTIONS preflight requests
    - [ ] Validate the `Origin` header on all requests
    - [ ] Add test: cross-origin request without allowed origin returns 403

    ## Repo Touchpoints

    - `apps/service/src/index.ts` — new CORS middleware
    - `apps/workbench/src/index.ts` — new CORS middleware
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa21" {
  project      = local.cogit_project_id
  title        = "SA-21: Missing security response headers"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::low", "priority::low", "scope::frontend", "nist::sc"]
  description  = <<-EOT
    ## Finding: LOW

    **NIST Controls:** SC-23
    **Location:** `apps/workbench/src/index.ts`

    ## Description

    The `Referrer-Policy` and `Permissions-Policy` headers are not set. The `X-Powered-By` header
    (if present from Node.js defaults) is not stripped.

    ## Remediation

    - [ ] Add `Referrer-Policy: strict-origin-when-cross-origin`
    - [ ] Add `Permissions-Policy: camera=(), microphone=(), geolocation=()`
    - [ ] Strip `X-Powered-By` header
    - [ ] Add test: all expected security headers are present in response

    ## Repo Touchpoints

    - `apps/workbench/src/index.ts` — `applySecurityHeaders`
    - `apps/service/src/index.ts` — response headers
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}

resource "gitlab_project_issue" "cogit_sa22" {
  project      = local.cogit_project_id
  title        = "SA-22: SonarQube exports committed to repository"
  milestone_id = local.cogit_m11_milestone_id
  labels       = ["security", "type::security-audit", "severity::low", "priority::low", "scope::cicd", "nist::cm"]
  description  = <<-EOT
    ## Finding: LOW

    **NIST Controls:** CM-6
    **Location:** `.gitleaks-baseline.json`, `ops/sonarqube/exports/`

    ## Description

    The gitleaks baseline contains 954 fingerprints of detected secrets, mostly from SonarQube
    export files. While these appear to be test/analysis artifacts, they inflate the baseline
    and could mask real secrets.

    ## Remediation

    - [ ] Add `ops/sonarqube/exports/` to `.gitignore`
    - [ ] Regenerate the gitleaks baseline from a clean state
    - [ ] Verify the new baseline has a manageable number of fingerprints

    ## Repo Touchpoints

    - `.gitignore`
    - `.gitleaks-baseline.json`
    - `ops/sonarqube/exports/`
  EOT

  lifecycle {
    ignore_changes = [state, description]
  }

  depends_on = [gitlab_project.projects, gitlab_project_milestone.cogit]
}
