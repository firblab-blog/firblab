#!/usr/bin/env python3
"""Listing watcher — scrapes auction sites, sends Gotify alerts for new listings.

Deployed alongside changedetection.io on the same LXC. Scrapes GovDeals and
AllSurplus search pages, extracts individual listing cards, filters by keyword,
and pushes Gotify notifications for new finds.

Environment variables:
  GOTIFY_URL        — Gotify server URL (e.g. https://gotify.home.example-lab.org)
  GOTIFY_TOKEN      — Gotify application token
  SEARCHES          — JSON array of {"name": "...", "url": "..."} objects
  KEYWORDS          — Comma-separated keywords to match in listing titles
  CHECK_INTERVAL    — Seconds between scrape cycles (default: 1800)
  SEEN_FILE         — Path to persist seen listing IDs (default: /data/seen.json)
"""

import hashlib
import json
import os
import sys
import time

import requests
from bs4 import BeautifulSoup
from pathlib import Path

GOTIFY_URL = os.environ.get("GOTIFY_URL", "")
GOTIFY_TOKEN = os.environ.get("GOTIFY_TOKEN", "")
SEEN_FILE = Path(os.environ.get("SEEN_FILE", "/data/seen.json"))
INTERVAL = int(os.environ.get("CHECK_INTERVAL", "1800"))
KEYWORDS = [k.strip().lower() for k in os.environ.get("KEYWORDS", "").split(",") if k.strip()]
SEARCHES = json.loads(os.environ.get("SEARCHES", "[]"))
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36"

# CSS selectors — GovDeals/AllSurplus use React; try multiple patterns.
# If the site changes its HTML structure, update these selectors.
CARD_SEL = "[data-testid='asset-card'], .asset-card, .search-result-item, article, .lot-card, .card"
TITLE_SEL = "h2, h3, .asset-title, [data-testid='asset-title'], .lot-title, .card-title"


def load_seen():
    return set(json.loads(SEEN_FILE.read_text())) if SEEN_FILE.exists() else set()


def save_seen(seen):
    SEEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    SEEN_FILE.write_text(json.dumps(list(seen)))


def notify(title, msg):
    if not GOTIFY_URL or not GOTIFY_TOKEN:
        return
    try:
        requests.post(
            f"{GOTIFY_URL}/message",
            params={"token": GOTIFY_TOKEN},
            json={"title": title, "message": msg, "priority": 5},
            timeout=10,
        )
    except Exception as e:
        print(f"[WARN] Gotify: {e}", flush=True)


def scrape(url):
    try:
        r = requests.get(url, headers={"User-Agent": UA}, timeout=30)
        r.raise_for_status()
        soup = BeautifulSoup(r.text, "html.parser")
        listings = []
        for card in soup.select(CARD_SEL):
            title_el = card.select_one(TITLE_SEL)
            link_el = card.select_one("a[href]")
            if title_el and link_el:
                href = link_el.get("href", "")
                if href and not href.startswith("http"):
                    base = url.split("/search")[0] if "/search" in url else url.rsplit("/", 1)[0]
                    href = base.rstrip("/") + "/" + href.lstrip("/")
                listings.append({"title": title_el.get_text(strip=True), "url": href})
        if not listings:
            print(f"[INFO] No listings parsed at {url} (may need JS rendering — use changedetection.io for this URL)", flush=True)
        return listings
    except Exception as e:
        print(f"[WARN] Scrape {url}: {e}", flush=True)
        return []


def matches(title):
    if not KEYWORDS:
        return True
    t = title.lower()
    return any(kw in t for kw in KEYWORDS)


def main():
    if not SEARCHES:
        print("[ERROR] No SEARCHES configured. Set SEARCHES env var.", flush=True)
        sys.exit(1)

    seen = load_seen()
    print(
        f"Listing watcher started: {len(SEARCHES)} searches, {len(KEYWORDS)} keywords, "
        f"{len(seen)} previously seen, interval={INTERVAL}s",
        flush=True,
    )

    while True:
        new_count = 0
        for search in SEARCHES:
            name, url = search["name"], search["url"]
            for listing in scrape(url):
                lid = hashlib.md5(listing["url"].encode()).hexdigest()
                if lid not in seen and matches(listing["title"]):
                    seen.add(lid)
                    new_count += 1
                    notify(name, f"{listing['title']}\n{listing['url']}")
                    print(f"[NEW] [{name}] {listing['title']}", flush=True)
            save_seen(seen)
        if new_count:
            print(f"[INFO] Found {new_count} new listing(s) this cycle", flush=True)
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
