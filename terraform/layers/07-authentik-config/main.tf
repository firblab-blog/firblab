# =============================================================================
# Layer 07-authentik-config: Authentik SSO/IDP Configuration
# =============================================================================
# Creates the SSO integration layer for all FirbLab services:
#   - 2 groups (admins, users)
#   - 1+ user accounts (non-admin family/household members)
#   - 13 OIDC providers (native SSO services)
#   - 14 ForwardAuth proxy providers (services without native OIDC)
#   - 8 bookmark applications (dashboard links, no SSO)
#   - 35 applications total
#   - Embedded proxy outpost (ForwardAuth) with provider attachments
#   - 12 Vault secrets (OIDC credentials for K8s ESO + Ansible)
#   - 1 custom scope mapping (email_verified override for Vaultwarden)
#
# Note: SonarQube CE 26.x dropped OIDC support (no native OIDC, third-party
# plugin broken since 25.1). SonarQube SSO deferred — use ForwardAuth if needed.
#
# Adding a new OIDC service:
#   1. Add entry to local.oauth2_providers map
#   2. terraform apply
#
# Adding a new ForwardAuth service:
#   1. Add entry to local.proxy_providers map
#   2. Add authentik-forwardauth middleware to the IngressRoute
#   3. terraform apply
#
# Adding a bookmark (no SSO, dashboard link only):
#   1. Add entry to local.bookmark_apps map
#   2. terraform apply
# =============================================================================

# ---------------------------------------------------------
# Data Sources — Flows, Scopes, Signing Key
# ---------------------------------------------------------

# Default authorization flow — implicit consent (no user approval prompt)
data "authentik_flow" "default_authorization" {
  slug = "default-provider-authorization-implicit-consent"
}

# Default invalidation (logout) flow
data "authentik_flow" "default_invalidation" {
  slug = "default-provider-invalidation-flow"
}

# OIDC scope mappings — openid, email, profile
# NOTE: groups claim is included in the built-in profile scope by default.
# Authentik's profile mapping returns:
#   "groups": [group.name for group in request.user.groups.all()]
# No separate groups scope exists or is needed.
# Fetch only openid + profile scopes from built-in mappings.
# The built-in email scope is EXCLUDED because it returns
# email_verified: false (Authentik 2025.10+). We replace it
# with our custom email_verified scope mapping (see below).
data "authentik_property_mapping_provider_scope" "oauth2" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-profile",
  ]
}

# Self-signed certificate for JWT signing (created by Authentik at first boot)
data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

# ---------------------------------------------------------
# Groups
# ---------------------------------------------------------

resource "authentik_group" "admins" {
  name         = "authentik-admins"
  is_superuser = true
}

resource "authentik_group" "users" {
  name         = "authentik-users"
  is_superuser = false
}

# ---------------------------------------------------------
# Users
# ---------------------------------------------------------

resource "authentik_user" "users" {
  for_each = local.users

  username  = each.key
  name      = each.value.name
  email     = each.value.email
  groups    = each.value.groups
  is_active = true
}

# ---------------------------------------------------------
# Locals — Provider Configuration Data
# ---------------------------------------------------------

locals {
  # ---------------------------------------------------------------------------
  # Users — Authentik user accounts
  # ---------------------------------------------------------------------------
  # Password is set on first login via Authentik's enrollment/recovery flow.
  # Users authenticate via SSO for OIDC apps (Mealie, etc.) and ForwardAuth
  # apps (Actual Budget, Ghost, etc.).
  # ---------------------------------------------------------------------------
  users = {
    jadmin = {
      name   = "Example Admin"
      email  = "admin@example-lab.org"
      groups = [authentik_group.admins.id]
    }
    buser = {
      name   = "Example User"
      email  = "user@example-lab.org"
      groups = [authentik_group.users.id]
    }
  }

  # ---------------------------------------------------------------------------
  # OAuth2 Providers — native OIDC services
  # ---------------------------------------------------------------------------
  # Each entry creates:
  #   1. authentik_provider_oauth2 (OIDC provider)
  #   2. authentik_application (linked to provider)
  #   3. vault_kv_secret_v2 (client_id + client_secret → Vault)
  # ---------------------------------------------------------------------------
  oauth2_providers = {
    grafana = {
      name      = "Grafana"
      client_id = "grafana"
      redirect_uris = [
        { matching_mode = "strict", url = "https://grafana.home.example-lab.org/login/generic_oauth" },
      ]
      app_group       = "Monitoring"
      meta_launch_url = "https://grafana.home.example-lab.org"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/grafana.svg"
      vault_path      = "k8s/grafana-oidc"
    }
    argocd = {
      name      = "ArgoCD"
      client_id = "argocd"
      redirect_uris = [
        { matching_mode = "strict", url = "https://argocd.home.example-lab.org/auth/callback" },
      ]
      app_group       = "Platform"
      meta_launch_url = "https://argocd.home.example-lab.org"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/argo-cd.svg"
      vault_path      = "k8s/argocd-oidc"
    }
    gitlab = {
      name      = "GitLab"
      client_id = "gitlab"
      redirect_uris = [
        { matching_mode = "strict", url = "https://gitlab.home.example-lab.org/users/auth/openid_connect/callback" },
      ]
      app_group       = "Infrastructure"
      meta_launch_url = "https://gitlab.home.example-lab.org"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/gitlab.svg"
      vault_path      = "services/gitlab/oidc"
    }
    vault = {
      name      = "Vault"
      client_id = "vault"
      redirect_uris = [
        { matching_mode = "strict", url = "https://10.0.10.10:8200/ui/vault/auth/oidc/oidc/callback" },
      ]
      app_group       = "Infrastructure"
      meta_launch_url = "https://10.0.10.10:8200"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/hashicorp-vault.svg"
      vault_path      = "services/vault/oidc"
    }
    proxmox = {
      name      = "Proxmox VE"
      client_id = "proxmox"
      redirect_uris = [
        { matching_mode = "strict", url = "https://10.0.10.42:8006" },
        { matching_mode = "strict", url = "https://10.0.10.2:8006" },
        { matching_mode = "strict", url = "https://10.0.10.3:8006" },
        { matching_mode = "strict", url = "https://10.0.10.4:8006" },
      ]
      app_group       = "Infrastructure"
      meta_launch_url = "https://10.0.10.42:8006"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/proxmox.svg"
      vault_path      = "services/proxmox/oidc"
    }
    headlamp = {
      name      = "Headlamp"
      client_id = "headlamp"
      redirect_uris = [
        { matching_mode = "strict", url = "https://headlamp.home.example-lab.org/oidc-callback" },
      ]
      app_group       = "Platform"
      meta_launch_url = "https://headlamp.home.example-lab.org"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/headlamp.svg"
      vault_path      = "k8s/headlamp-oidc"
    }
    netbox = {
      name      = "NetBox"
      client_id = "netbox"
      redirect_uris = [
        { matching_mode = "strict", url = "http://10.0.20.14:8080/oauth/complete/oidc/" },
      ]
      app_group       = "Infrastructure"
      meta_launch_url = "http://10.0.20.14:8080"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/netbox.svg"
      vault_path      = "services/netbox/oidc"
    }
    mealie = {
      name      = "Mealie"
      client_id = "mealie"
      redirect_uris = [
        { matching_mode = "strict", url = "http://10.0.20.13:9000/login" },
        { matching_mode = "strict", url = "http://10.0.20.13:9000/login?direct=1" },
      ]
      app_group       = "Applications"
      meta_launch_url = "http://10.0.20.13:9000"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/mealie.svg"
      vault_path      = "services/mealie/oidc"
    }
    patchmon = {
      name      = "PatchMon"
      client_id = "patchmon"
      redirect_uris = [
        { matching_mode = "strict", url = "http://10.0.20.15:3000/api/v1/auth/oidc/callback" },
      ]
      app_group       = "Infrastructure"
      meta_launch_url = "http://10.0.20.15:3000"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/patchmon.svg"
      vault_path      = "services/patchmon/oidc"
    }
    actualbudget = {
      name      = "Actual Budget"
      client_id = "actualbudget"
      redirect_uris = [
        { matching_mode = "strict", url = "https://actualbudget.home.example-lab.org/openid/callback" },
      ]
      app_group       = "Applications"
      meta_launch_url = "https://actualbudget.home.example-lab.org"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/actual-budget.svg"
      vault_path      = "services/actualbudget/oidc"
    }
    vaultwarden = {
      name      = "Vaultwarden"
      client_id = "vaultwarden"
      redirect_uris = [
        { matching_mode = "strict", url = "https://vaultwarden.home.example-lab.org/identity/connect/oidc-signin" },
      ]
      app_group       = "Security"
      meta_launch_url = "https://vaultwarden.home.example-lab.org"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/vaultwarden.svg"
      vault_path      = "services/vaultwarden/oidc"
    }
    openwebui = {
      name      = "Open WebUI"
      client_id = "openwebui"
      redirect_uris = [
        { matching_mode = "strict", url = "https://openwebui.home.example-lab.org/oauth/oidc/callback" },
      ]
      app_group       = "AI"
      meta_launch_url = "https://openwebui.home.example-lab.org"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/open-webui.svg"
      vault_path      = "services/openwebui/oidc"
    }
    mailarchiver = {
      name      = "Mail Archiver"
      client_id = "mailarchiver"
      redirect_uris = [
        { matching_mode = "strict", url = "https://archiver.home.example-lab.org/oidc-signin-completed" },
      ]
      app_group       = "Applications"
      meta_launch_url = "https://archiver.home.example-lab.org"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/mailarchiver.svg"
      vault_path      = "services/mailarchiver/oidc"
    }
    freshrss = {
      name      = "FreshRSS"
      client_id = "freshrss"
      redirect_uris = [
        { matching_mode = "strict", url = "https://freshrss.home.example-lab.org/i/oidc/" },
        # http:// URI required because the FreshRSS image's Apache template has a bug:
        # OIDCXForwardedHeaders is silently not applied when the env var contains
        # multiple space-separated header names (Define/IfDefine pattern fails with
        # spaces in the Define name). Without OIDCXForwardedHeaders, mod_auth_openidc
        # cannot trust X-Forwarded-Proto from Traefik and falls back to http://.
        # A custom conf-enabled volume mount (oidc-forwarded.conf) also fixes this
        # properly — both URIs remain registered as belt-and-suspenders.
        { matching_mode = "strict", url = "http://freshrss.home.example-lab.org/i/oidc/" },
      ]
      app_group       = "Applications"
      meta_launch_url = "https://freshrss.home.example-lab.org"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/freshrss.svg"
      vault_path      = "services/freshrss/oidc"
    }
  }

  # ---------------------------------------------------------------------------
  # Proxy Providers — ForwardAuth for services without native OIDC
  # ---------------------------------------------------------------------------
  # Each entry creates:
  #   1. authentik_provider_proxy (forward_single mode)
  #   2. authentik_application (linked to provider)
  # No Vault secrets needed — ForwardAuth doesn't use client_id/secret.
  # ---------------------------------------------------------------------------
  proxy_providers = {
    longhorn = {
      name          = "Longhorn UI"
      external_host = "https://longhorn.home.example-lab.org"
      app_group     = "Platform"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/rancher-longhorn.svg"
    }
    ghost = {
      name          = "Ghost"
      external_host = "https://ghost.home.example-lab.org"
      app_group     = "Applications"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/png/ghost.png"
    }
    roundcube = {
      name          = "Roundcube"
      external_host = "https://mail.home.example-lab.org"
      app_group     = "Applications"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/roundcube.svg"
    }
    foundryvtt = {
      name          = "FoundryVTT"
      external_host = "https://foundryvtt.home.example-lab.org"
      app_group     = "Applications"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/png/foundry-virtual-tabletop.png"
    }
    n8n = {
      name          = "n8n"
      external_host = "https://n8n.home.example-lab.org"
      app_group     = "AI"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/n8n.svg"
    }

    changedetection = {
      name          = "changedetection.io"
      external_host = "https://changedetection.home.example-lab.org"
      app_group     = "Applications"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/changedetection-io.svg"
    }

    # Archive appliance (lab-09) — 6 services behind Traefik ForwardAuth
    archive = {
      name          = "FileBrowser"
      external_host = "https://archive.home.example-lab.org"
      app_group     = "Applications"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/file-browser.svg"
    }
    kiwix = {
      name          = "Kiwix"
      external_host = "https://kiwix.home.example-lab.org"
      app_group     = "Applications"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/kiwix.svg"
    }
    archivebox = {
      name          = "ArchiveBox"
      external_host = "https://archivebox.home.example-lab.org"
      app_group     = "Applications"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/archivebox.svg"
    }
    bookstack = {
      name          = "BookStack"
      external_host = "https://bookstack.home.example-lab.org"
      app_group     = "Applications"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/bookstack.svg"
    }
    stirlingpdf = {
      name          = "Stirling PDF"
      external_host = "https://stirlingpdf.home.example-lab.org"
      app_group     = "Applications"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/stirling-pdf.svg"
    }
    wallabag = {
      name          = "Wallabag"
      external_host = "https://wallabag.home.example-lab.org"
      app_group     = "Applications"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/wallabag.svg"
    }
    maps = {
      name          = "Maps"
      external_host = "https://maps.home.example-lab.org"
      app_group     = "Applications"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/openstreetmap.svg"
    }
    calibreweb = {
      name          = "Calibre-Web"
      external_host = "https://calibreweb.home.example-lab.org"
      app_group     = "Applications"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/calibre-web.svg"
    }
    searxng = {
      name          = "SearXNG"
      external_host = "https://search.home.example-lab.org"
      app_group     = "Applications"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/searxng.svg"
    }
    homeassistant = {
      name          = "Home Assistant"
      external_host = "https://homeassistant.home.example-lab.org"
      app_group     = "Home Automation"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/home-assistant.svg"
    }

    # Backup monitoring — Backrest UI (LXC on Management VLAN 10)
    backrest = {
      name          = "Backrest"
      external_host = "https://backrest.home.example-lab.org"
      app_group     = "Infrastructure"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/backrest.svg"
    }

    # Proxmox Backup Server — no native OIDC, use ForwardAuth
    pbs = {
      name          = "Proxmox Backup Server"
      external_host = "https://pbs.home.example-lab.org"
      app_group     = "Infrastructure"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/proxmox.svg"
    }

    # Internal Uptime Kuma monitoring — no native OIDC, use ForwardAuth
    status = {
      name          = "Uptime Kuma (Internal)"
      external_host = "https://status.home.example-lab.org"
      app_group     = "Infrastructure"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/uptime-kuma.svg"
    }

    # SonarQube CE — static code analysis, GitLab ALM integration
    # No native OIDC (CE 26.x dropped it). ForwardAuth gates access.
    sonarqube = {
      name          = "SonarQube"
      external_host = "https://sonarqube.home.example-lab.org"
      app_group     = "Infrastructure"
      meta_icon     = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/sonarqube.svg"
    }
    cogit = {
      name          = "Cogit"
      external_host = "https://cogit.home.example-lab.org"
      app_group     = "Infrastructure"
    }

  }

  # ---------------------------------------------------------------------------
  # Bookmark Applications — dashboard links without SSO providers
  # ---------------------------------------------------------------------------
  # Each entry creates:
  #   1. authentik_application (no provider — acts as a clickable link)
  # Services here don't support OIDC and aren't behind Traefik ForwardAuth.
  # ---------------------------------------------------------------------------
  bookmark_apps = {
    plex = {
      name            = "Plex"
      meta_launch_url = "https://10.0.40.2:32400/web"
      app_group       = "Media"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/plex.svg"
    }
    scanopy = {
      name            = "Scanopy"
      meta_launch_url = "http://10.0.4.20:60072"
      app_group       = "Applications"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/scanopy.svg"
    }
    truenas = {
      name            = "TrueNAS"
      meta_launch_url = "https://10.0.40.2"
      app_group       = "Infrastructure"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/truenas-scale.svg"
    }
    immich = {
      name            = "Immich"
      meta_launch_url = "https://immich.home.example-lab.org"
      app_group       = "Media"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/immich.svg"
    }
    linkwarden = {
      name            = "Linkwarden"
      meta_launch_url = "https://linkwarden.home.example-lab.org"
      app_group       = "Applications"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/linkwarden.svg"
    }
    paperless = {
      name            = "Paperless-NGX"
      meta_launch_url = "https://paperless.home.example-lab.org"
      app_group       = "Applications"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/paperless-ngx.svg"
    }
    portracker = {
      name            = "Portracker"
      meta_launch_url = "https://portracker.home.example-lab.org"
      app_group       = "Infrastructure"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/portracker.svg"
    }
    ittools = {
      name            = "IT Tools"
      meta_launch_url = "https://tools.home.example-lab.org"
      app_group       = "Applications"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/it-tools.svg"
    }
    jetkvm = {
      name            = "JetKVM"
      meta_launch_url = "http://10.0.10.112"
      app_group       = "Infrastructure"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/jetkvm.svg"
    }

    # --- Hetzner Gateway Services ---
    # Admin tools on the Hetzner cloud server. Gotify and AdGuard are routed via
    # the standalone Traefik proxy at home.example-lab.org (proxied to *.example-lab.org).
    # Both services have native auth — no ForwardAuth wrapper needed.
    traefik_hetzner = {
      name            = "Traefik (Hetzner)"
      meta_launch_url = "https://traefik.example-lab.org"
      app_group       = "Hetzner Gateway"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/traefik.svg"
    }
    adguard = {
      name            = "AdGuard Home"
      meta_launch_url = "https://adguard.home.example-lab.org"
      app_group       = "Hetzner Gateway"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/adguard-home.svg"
    }
    gotify = {
      name            = "Gotify"
      meta_launch_url = "https://gotify.home.example-lab.org"
      app_group       = "Hetzner Gateway"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/gotify.svg"
    }
    uptimekuma = {
      name            = "Uptime Kuma (Public)"
      meta_launch_url = "https://status.example-lab.org"
      app_group       = "Hetzner Gateway"
      meta_icon       = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/uptime-kuma.svg"
    }
  }
}

# ---------------------------------------------------------
# Custom Scope Mapping — email_verified Override
# ---------------------------------------------------------
# Authentik 2025.10+ returns email_verified: false by default.
# Vaultwarden requires email_verified: true to authenticate
# users via OIDC. This custom scope mapping overrides the
# default email scope. Applied to ALL providers — returning
# email_verified: true is safe and correct for all services
# (users are verified by Authentik enrollment).
# ---------------------------------------------------------

resource "authentik_property_mapping_provider_scope" "email_verified" {
  name       = "Email (verified override)"
  scope_name = "email"
  expression = <<-EOT
    return {
        "email": request.user.email,
        "email_verified": True,
    }
  EOT
}

# ---------------------------------------------------------
# OAuth2 Providers (Native OIDC)
# ---------------------------------------------------------

resource "authentik_provider_oauth2" "oauth2" {
  for_each = local.oauth2_providers

  name               = each.value.name
  client_id          = each.value.client_id
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  signing_key        = data.authentik_certificate_key_pair.default.id

  # Use default openid + profile scopes, plus our custom email scope
  # (replaces default email mapping with email_verified: true).
  property_mappings = setunion(
    [for id in data.authentik_property_mapping_provider_scope.oauth2.ids : id],
    [authentik_property_mapping_provider_scope.email_verified.id]
  )

  allowed_redirect_uris = each.value.redirect_uris
}

# ---------------------------------------------------------
# OAuth2 Applications
# ---------------------------------------------------------

resource "authentik_application" "oauth2" {
  for_each = local.oauth2_providers

  name              = each.value.name
  slug              = each.key
  protocol_provider = authentik_provider_oauth2.oauth2[each.key].id
  group             = each.value.app_group
  meta_launch_url   = each.value.meta_launch_url
  meta_icon         = each.value.meta_icon

  depends_on = [authentik_provider_oauth2.oauth2]
}

# ---------------------------------------------------------
# Proxy Providers (ForwardAuth)
# ---------------------------------------------------------

resource "authentik_provider_proxy" "proxy" {
  for_each = local.proxy_providers

  name               = each.value.name
  external_host      = each.value.external_host
  mode               = "forward_single"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
}

# ---------------------------------------------------------
# Proxy Applications
# ---------------------------------------------------------

resource "authentik_application" "proxy" {
  for_each = local.proxy_providers

  name              = each.value.name
  slug              = each.key
  protocol_provider = authentik_provider_proxy.proxy[each.key].id
  group             = each.value.app_group
  meta_launch_url   = each.value.external_host
  meta_icon         = try(each.value.meta_icon, null)

  depends_on = [authentik_provider_proxy.proxy]
}

# ---------------------------------------------------------
# Bookmark Applications (Dashboard Links, No SSO)
# ---------------------------------------------------------

resource "authentik_application" "bookmark" {
  for_each = local.bookmark_apps

  name            = each.value.name
  slug            = each.key
  group           = each.value.app_group
  meta_launch_url = each.value.meta_launch_url
  meta_icon       = each.value.meta_icon
}

# ---------------------------------------------------------
# Access Control — Application Authorization Policies
# ---------------------------------------------------------
# By default, all Authentik applications are visible to all
# authenticated users. These policies restrict infrastructure
# and admin tools to the admins group only.
#
# Applications NOT listed here remain open to all users:
#   Mealie, Actual Budget, Plex (user-facing apps)
# ---------------------------------------------------------

# Expression policy: deny if user is NOT in authentik-admins
resource "authentik_policy_expression" "admin_only" {
  name       = "admin-only"
  expression = "return request.user.is_superuser or ak_is_group_member(request.user, name=\"authentik-admins\")"
}

# Apps restricted to admins only (infrastructure/platform tools)
locals {
  admin_only_oauth2_apps = toset([
    "grafana", "argocd", "gitlab", "vault", "proxmox",
    "headlamp", "netbox", "patchmon", "vaultwarden", "openwebui",
    "mailarchiver",
  ])
  admin_only_proxy_apps = toset([
    "longhorn", "n8n", "homeassistant", "pbs",
  ])
  admin_only_bookmark_apps = toset([
    "truenas", "scanopy", "jetkvm",
    "traefik_hetzner", "adguard", "gotify", "uptimekuma",
  ])
}

resource "authentik_policy_binding" "admin_only_oauth2" {
  for_each = local.admin_only_oauth2_apps

  target = authentik_application.oauth2[each.key].uuid
  policy = authentik_policy_expression.admin_only.id
  order  = 0
}

resource "authentik_policy_binding" "admin_only_proxy" {
  for_each = local.admin_only_proxy_apps

  target = authentik_application.proxy[each.key].uuid
  policy = authentik_policy_expression.admin_only.id
  order  = 0
}

resource "authentik_policy_binding" "admin_only_bookmark" {
  for_each = local.admin_only_bookmark_apps

  target = authentik_application.bookmark[each.key].uuid
  policy = authentik_policy_expression.admin_only.id
  order  = 0
}

# ---------------------------------------------------------
# Outpost — Embedded Proxy (ForwardAuth)
# ---------------------------------------------------------
# Attach all proxy providers to the EMBEDDED outpost (the built-in
# outpost that runs inside the Authentik server process). This is
# the outpost that handles:
#   http://10.0.10.16:9000/outpost.goauthentik.io/auth/traefik
#
# NOTE: Do NOT create a separate authentik_outpost resource — a
# standalone proxy outpost with no service_connection shows "Not
# available" and cannot handle ForwardAuth requests. The embedded
# outpost is the only one that works for Docker Compose deployments.
# ---------------------------------------------------------

data "authentik_outpost" "embedded" {
  name = "authentik Embedded Outpost"
}

resource "authentik_outpost_provider_attachment" "proxy" {
  for_each = local.proxy_providers

  outpost           = data.authentik_outpost.embedded.id
  protocol_provider = authentik_provider_proxy.proxy[each.key].id
}

# ---------------------------------------------------------
# Vault Secrets — OIDC Credentials
# ---------------------------------------------------------
# Writes client_id + client_secret to Vault for each OAuth2 provider.
# K8s services:   secret/k8s/<service>-oidc    (consumed by ESO)
# Standalone:     secret/services/<svc>/oidc   (consumed by Ansible)
# ---------------------------------------------------------

resource "vault_kv_secret_v2" "oidc_credentials" {
  for_each = local.oauth2_providers

  mount = "secret"
  name  = each.value.vault_path

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.oauth2[each.key].client_id
    client_secret = authentik_provider_oauth2.oauth2[each.key].client_secret
  })

  depends_on = [authentik_provider_oauth2.oauth2]
}
