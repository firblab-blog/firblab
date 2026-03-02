#!/usr/bin/env python3
"""
Merge old Mealie backup recipes into a new instance's backup.
=============================================================================
Problem: Mealie backup restore is destructive — it overwrites the entire
database including users. If you forgot your old password, you're locked out.

Solution: Take a fresh backup from the new instance (with credentials you
know), then merge the old backup's recipe data into it — replacing the
user/group/household IDs with the new instance's IDs so your login works.

Usage:
  # 1. On fresh Mealie, create a backup via Admin > Backups, download it
  # 2. Run this script:
  python3 scripts/mealie-merge-backup.py \
    --old files/mealie/mealie_2026.02.11.03.08.09.zip \
    --new files/mealie/mealie_new_instance.zip \
    --output files/mealie/mealie_merged.zip

  # 3. Upload mealie_merged.zip via Admin > Backups > Upload, then restore
=============================================================================
"""

import argparse
import json
import os
import sys
import zipfile


def main():
    parser = argparse.ArgumentParser(
        description="Merge old Mealie backup recipes into a new instance's backup"
    )
    parser.add_argument(
        "--old", required=True, help="Path to old backup ZIP (has your recipes)"
    )
    parser.add_argument(
        "--new", required=True, help="Path to new backup ZIP (has your current credentials)"
    )
    parser.add_argument(
        "--output", required=True, help="Path for the merged output ZIP"
    )
    args = parser.parse_args()

    # Validate inputs
    for path, label in [(args.old, "Old backup"), (args.new, "New backup")]:
        if not os.path.exists(path):
            print(f"ERROR: {label} not found: {path}", file=sys.stderr)
            sys.exit(1)

    # Extract database.json from both backups
    print(f"Reading old backup: {args.old}")
    with zipfile.ZipFile(args.old) as z:
        old_db = json.loads(z.read("database.json"))

    print(f"Reading new backup: {args.new}")
    with zipfile.ZipFile(args.new) as z:
        new_db = json.loads(z.read("database.json"))

    # Get old and new identity IDs
    old_user_id = old_db["users"][0]["id"]
    old_group_id = old_db["groups"][0]["id"]
    old_household_id = old_db["households"][0]["id"]

    new_user_id = new_db["users"][0]["id"]
    new_group_id = new_db["groups"][0]["id"]
    new_household_id = new_db["households"][0]["id"]

    print(f"\nID Mapping:")
    print(f"  User:      {old_user_id} -> {new_user_id}")
    print(f"  Group:     {old_group_id} -> {new_group_id}")
    print(f"  Household: {old_household_id} -> {new_household_id}")
    print(f"\nOld backup: {len(old_db.get('recipes', []))} recipes")

    # Replace identity sections with new instance's versions
    # These sections contain credentials, preferences, and schema version
    identity_sections = [
        "users",
        "groups",
        "households",
        "household_preferences",
        "group_preferences",
        "alembic_version",
    ]
    for section in identity_sections:
        if section in new_db:
            old_db[section] = new_db[section]
            print(f"  Replaced section: {section}")

    # Clear tokens and secrets that belong to the old instance
    token_sections = [
        "long_live_tokens",
        "password_reset_tokens",
        "invite_tokens",
    ]
    for section in token_sections:
        if section in old_db:
            old_db[section] = []
            print(f"  Cleared section: {section}")

    # Global find-and-replace of old IDs with new IDs throughout all data
    # This updates foreign key references in recipes, categories, tags, etc.
    print("\nRewriting ID references...")
    raw = json.dumps(old_db)
    replacements = [
        (old_user_id, new_user_id, "user"),
        (old_group_id, new_group_id, "group"),
        (old_household_id, new_household_id, "household"),
    ]
    for old_id, new_id, label in replacements:
        count = raw.count(old_id)
        raw = raw.replace(old_id, new_id)
        print(f"  {label}: replaced {count} references")

    merged_db = json.loads(raw)

    # Build the merged ZIP
    # Use old backup as base (has recipe images in data/recipes/), replace database.json
    print(f"\nBuilding merged backup: {args.output}")
    with zipfile.ZipFile(args.old) as old_z:
        with zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED) as out_z:
            for item in old_z.namelist():
                if item == "database.json":
                    # Write the merged database
                    out_z.writestr(
                        "database.json",
                        json.dumps(merged_db, indent=2, ensure_ascii=False),
                    )
                elif item in ("data/.secret", "data/.session_secret"):
                    # Use secrets from new instance if available
                    try:
                        with zipfile.ZipFile(args.new) as new_z:
                            out_z.writestr(item, new_z.read(item))
                    except KeyError:
                        out_z.writestr(item, old_z.read(item))
                else:
                    # Copy everything else (recipe images, etc.) from old backup
                    out_z.writestr(item, old_z.read(item))

    # Summary
    old_size = os.path.getsize(args.old)
    new_size = os.path.getsize(args.output)
    print(f"\nDone!")
    print(f"  Old backup size:    {old_size:,} bytes")
    print(f"  Merged backup size: {new_size:,} bytes")
    print(f"  Recipes preserved:  {len(merged_db.get('recipes', []))}")
    print(f"\nNext steps:")
    print(f"  1. Upload {args.output} via Mealie Admin > Backups > Upload")
    print(f"  2. Click the uploaded backup to restore it")
    print(f"  3. Log in with your NEW instance credentials")


if __name__ == "__main__":
    main()
