#!/usr/bin/env python3
"""Sync runbooks/ directory with runbooks.json manifest.

Modes:
  (default)          Scan runbooks/, add missing files to runbooks.json
  --validate         Check manifest matches files, exit 1 on drift (for CI)
  --new <filename>   Scaffold a new runbook script + add to manifest
"""

import argparse
import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(SCRIPT_DIR, "runbooks.json")
RUNBOOKS_DIR = os.path.join(SCRIPT_DIR, "runbooks")

EXTENSION_MAP = {
    ".ps1": "PowerShell72",
    ".py": "Python3",
}

PS1_BOILERPLATE = """\
Connect-AzAccount -Identity

# TODO: implement runbook logic
Write-Output "Runbook complete."
"""

PY_BOILERPLATE = """\
import automationassets

# TODO: implement runbook logic
print("Runbook complete.")
"""

BOILERPLATE = {
    ".ps1": PS1_BOILERPLATE,
    ".py": PY_BOILERPLATE,
}


def filename_to_name(filename: str) -> str:
    """Convert kebab-case filename to PascalCase runbook name.

    Example: cleanup-unused-disks.ps1 -> Cleanup-UnusedDisks
    """
    stem = os.path.splitext(filename)[0]
    parts = stem.split("-", 1)
    if len(parts) == 1:
        return parts[0].capitalize()
    prefix = parts[0].capitalize()
    suffix = "".join(word.capitalize() for word in parts[1].split("-"))
    return f"{prefix}-{suffix}"


def load_manifest() -> dict:
    if os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            return json.load(f)
    return {}


def save_manifest(data: dict) -> None:
    with open(MANIFEST, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def scan_runbooks() -> set:
    if not os.path.isdir(RUNBOOKS_DIR):
        return set()
    return {
        f
        for f in os.listdir(RUNBOOKS_DIR)
        if os.path.isfile(os.path.join(RUNBOOKS_DIR, f))
        and os.path.splitext(f)[1] in EXTENSION_MAP
    }


def make_entry(filename: str) -> dict:
    ext = os.path.splitext(filename)[1]
    return {
        "name": filename_to_name(filename),
        "description": f"TODO: add description for {filename}",
        "runbook_type": EXTENSION_MAP[ext],
    }


def cmd_sync() -> None:
    manifest = load_manifest()
    files = scan_runbooks()
    added = 0
    for f in sorted(files):
        if f not in manifest:
            manifest[f] = make_entry(f)
            print(f"Added {f} to manifest")
            added += 1
    if added:
        save_manifest(manifest)
        print(f"Manifest updated: {added} entry(ies) added")
    else:
        print("Manifest already up to date")


def cmd_validate() -> None:
    manifest = load_manifest()
    files = scan_runbooks()
    manifest_keys = set(manifest.keys())

    missing_from_manifest = files - manifest_keys
    missing_from_disk = manifest_keys - files
    errors = []

    if missing_from_manifest:
        for f in sorted(missing_from_manifest):
            errors.append(f"File {f} exists in runbooks/ but not in manifest")
    if missing_from_disk:
        for f in sorted(missing_from_disk):
            errors.append(f"Manifest entry {f} has no matching file in runbooks/")

    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"OK: manifest and runbooks/ are in sync ({len(manifest)} runbook(s))")


def cmd_new(filename: str) -> None:
    ext = os.path.splitext(filename)[1]
    if ext not in EXTENSION_MAP:
        print(f"ERROR: unsupported extension '{ext}'. Use: {', '.join(EXTENSION_MAP)}", file=sys.stderr)
        sys.exit(1)

    filepath = os.path.join(RUNBOOKS_DIR, filename)
    if os.path.exists(filepath):
        print(f"ERROR: {filepath} already exists", file=sys.stderr)
        sys.exit(1)

    os.makedirs(RUNBOOKS_DIR, exist_ok=True)
    with open(filepath, "w") as f:
        f.write(BOILERPLATE[ext])
    print(f"Created {filepath}")

    manifest = load_manifest()
    manifest[filename] = make_entry(filename)
    save_manifest(manifest)
    print(f"Added {filename} to manifest")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--validate", action="store_true", help="Check manifest matches files (CI mode)")
    group.add_argument("--new", metavar="FILENAME", help="Scaffold a new runbook and add to manifest")
    args = parser.parse_args()

    if args.validate:
        cmd_validate()
    elif args.new:
        cmd_new(args.new)
    else:
        cmd_sync()


if __name__ == "__main__":
    main()
