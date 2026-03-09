#!/usr/bin/env python3
"""
Configure Uptime Kuma via raw Socket.IO calls.

Replaces lucasheld.uptime_kuma collection which is incompatible with
Uptime Kuma 1.23.x (uptime-kuma-api 1.2.1 login fails against 1.23.17).

In Uptime Kuma 1.23.x the Socket.IO API changed: getMonitorList and
getNotificationList return True (ACK only) and send actual data via
separate monitorList / notificationList events. After login, Uptime Kuma
automatically pushes both events to the authenticated client, so we
register event handlers and wait for them rather than using sio.call()
return values for those two calls.

All inputs via environment variables — no shell escaping issues, no
special character mangling (!, *, etc.):
  UK_URL            Uptime Kuma base URL (e.g. http://127.0.0.1:3001)
  UK_USERNAME       Admin username
  UK_PASSWORD       Admin password
  UK_GOTIFY_TOKEN   Gotify app token for Uptime Kuma notifications
  GOTIFY_URL        Gotify base URL for the notification channel
  UK_MONITORS_JSON  JSON array of monitor definitions (from group_vars)

Outputs a single JSON line to stdout for Ansible to parse:
  {"changed": true/false, "msg": "...", "created": [...], "skipped": [...]}
  {"failed": true, "msg": "..."}  on error (exits 1)
"""

import json
import os
import sys
import threading

import socketio

UK_URL = os.environ["UK_URL"]
UK_USERNAME = os.environ["UK_USERNAME"]
UK_PASSWORD = os.environ["UK_PASSWORD"]
UK_GOTIFY_TOKEN = os.environ["UK_GOTIFY_TOKEN"]
GOTIFY_URL = os.environ["GOTIFY_URL"]
monitors = json.loads(os.environ["UK_MONITORS_JSON"])

# ---------------------------------------------------------------------------
# Event-driven state collection
# Uptime Kuma 1.23.x pushes monitorList / notificationList as events,
# not as callback return values. Register handlers before connecting.
# ---------------------------------------------------------------------------
_monitor_list_ready = threading.Event()
_notif_list_ready = threading.Event()
_existing_monitors = {}
_existing_notifs = []

sio = socketio.Client(logger=False, engineio_logger=False)


@sio.on("monitorList")
def on_monitor_list(data):
    global _existing_monitors
    if isinstance(data, dict):
        _existing_monitors = data
    _monitor_list_ready.set()


@sio.on("notificationList")
def on_notif_list(data):
    global _existing_notifs
    if isinstance(data, list):
        _existing_notifs = data
    _notif_list_ready.set()


def fail(msg):
    print(json.dumps({"failed": True, "msg": msg}))
    try:
        sio.disconnect()
    except Exception:
        pass
    sys.exit(1)


try:
    sio.connect(UK_URL, transports=["websocket"])
except Exception as e:
    print(json.dumps({"failed": True, "msg": f"Connection failed: {e}"}))
    sys.exit(1)

# ---------------------------------------------------------------------------
# First-run setup (idempotent)
# ---------------------------------------------------------------------------
# Attempt to create the admin account via Socket.IO. On a fresh instance this
# succeeds (ok=True). On subsequent runs Uptime Kuma returns ok=False with
# "Setup is done" — that is not an error, just means we skip ahead to login.
# This replaces the old POST /setup REST approach which does not exist in 1.23.x.
try:
    setup_result = sio.call("setup", (UK_USERNAME, UK_PASSWORD), timeout=15)
    # ok=True  → first-run: admin account just created, proceed to login.
    # ok=False → already initialized ("Setup is done"): not an error, proceed to login.
except Exception:
    # Uptime Kuma 2.x silently ignores the "setup" event when the instance is
    # already initialized — it never fires the callback, so sio.call() raises
    # TimeoutError. Treat this identically to ok=False: proceed to login.
    # If credentials are wrong, login below will fail and surface the error.
    setup_result = None

# ---------------------------------------------------------------------------
# Login
# ---------------------------------------------------------------------------
login_result = sio.call(
    "login",
    {"username": UK_USERNAME, "password": UK_PASSWORD, "token": ""},
    timeout=15,
)
if not login_result or not login_result.get("ok"):
    fail(f"Login failed: {login_result}")

# ---------------------------------------------------------------------------
# Wait for Uptime Kuma to push monitorList and notificationList.
# These are emitted automatically after a successful login.
# Explicit getMonitorList / getNotificationList calls return True (ACK only)
# in 1.23.x — the events above carry the real data.
# ---------------------------------------------------------------------------
if not _monitor_list_ready.wait(timeout=15):
    fail("Timed out waiting for monitorList event after login")
if not _notif_list_ready.wait(timeout=15):
    fail("Timed out waiting for notificationList event after login")

existing_monitors = _existing_monitors
existing_monitor_names = {m["name"] for m in existing_monitors.values()}

existing_notifs = _existing_notifs
gotify_notif_id = next(
    (n["id"] for n in existing_notifs if n["name"] == "Gotify"), None
)

# ---------------------------------------------------------------------------
# Create or update Gotify notification channel (idempotent upsert)
# ---------------------------------------------------------------------------
# addNotification(notification, notificationID) — None → create, ID → update.
# Always call regardless of whether the channel already exists: this ensures
# the gotifyserverurl and token stay in sync with the current config (e.g. if
# GOTIFY_URL changed from the Hetzner instance to the internal one).
notif_result = sio.call(
    "addNotification",
    (
        {
            "name": "Gotify",
            "type": "gotify",
            "gotifyserverurl": GOTIFY_URL,
            "gotifyapplicationToken": UK_GOTIFY_TOKEN,
            "gotifyPriority": 5,
            "isDefault": True,
            "active": True,
            "applyExisting": False,
        },
        gotify_notif_id,  # None → create new; existing ID → update in place
    ),
    timeout=15,
)
if not notif_result or not notif_result.get("ok"):
    fail(f"Failed to create/update Gotify notification: {notif_result}")
gotify_notif_id = notif_result["id"]

# ---------------------------------------------------------------------------
# Reconcile: delete monitors that are no longer in the desired config.
# This keeps Uptime Kuma in sync with group_vars — removing a monitor from
# hetzner.yml removes it from the UI on the next run (IaC source of truth).
# ---------------------------------------------------------------------------
desired_names = {m["name"] for m in monitors}
deleted = []

for monitor_data in existing_monitors.values():
    if monitor_data["name"] not in desired_names:
        del_result = sio.call("deleteMonitor", monitor_data["id"], timeout=15)
        if not del_result or not del_result.get("ok"):
            fail(
                f"Failed to delete removed monitor '{monitor_data['name']}': {del_result}"
            )
        deleted.append(monitor_data["name"])

# ---------------------------------------------------------------------------
# Create monitors (upsert — skip if name+type match, delete+recreate on mismatch)
# ---------------------------------------------------------------------------
created = []
skipped = []

for monitor in monitors:
    existing = next(
        (m for m in existing_monitors.values() if m["name"] == monitor["name"]),
        None,
    )

    if existing is not None:
        if existing.get("type") == monitor["type"]:
            skipped.append(monitor["name"])
            continue
        # Type mismatch (e.g. stale "tcp" monitor that should now be "port") —
        # delete the old record and fall through to recreate with the correct type.
        del_result = sio.call("deleteMonitor", existing["id"], timeout=15)
        if not del_result or not del_result.get("ok"):
            fail(
                f"Failed to delete monitor '{monitor['name']}' for type update "
                f"(old type={existing.get('type')!r}): {del_result}"
            )

    payload = {
        "name": monitor["name"],
        "type": monitor["type"],
        "interval": monitor.get("interval", 60),
        "retryInterval": 60,
        "maxretries": 0,
        "active": True,
        "notificationIDList": {str(gotify_notif_id): True},
        # Uptime Kuma field name is accepted_statuscodes (no underscore in status+codes)
        "accepted_statuscodes": monitor.get("accepted_status_codes", ["200-299"]),
    }

    if monitor["type"] == "http":
        payload.update(
            {
                "url": monitor["url"],
                "method": "GET",
                "maxredirects": 10,
                "ignoreTls": monitor.get("ignore_tls", False),
            }
        )
    elif monitor["type"] == "port":
        payload["hostname"] = monitor["hostname"]
        payload["port"] = int(monitor["port"])
    elif monitor["type"] == "ping":
        payload["hostname"] = monitor["hostname"]

    result = sio.call("add", payload, timeout=15)
    if not result or not result.get("ok"):
        fail(f"Failed to create monitor '{monitor['name']}': {result}")
    created.append(monitor["name"])

sio.disconnect()

print(
    json.dumps(
        {
            "changed": len(created) > 0 or len(deleted) > 0,
            "msg": (
                f"Created {len(created)}, skipped {len(skipped)} existing, "
                f"deleted {len(deleted)} removed"
            ),
            "created": created,
            "skipped": skipped,
            "deleted": deleted,
        }
    )
)
