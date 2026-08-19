#!/usr/bin/env python3
"""Check every package referenced in profiles/*.toml against official
Arch repos and the AUR. Prints official/AUR/MISSING for each package."""
import tomllib
import urllib.request
import json
import time
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_packages():
    pkgs = set()
    for base in sorted((ROOT / "profiles" / "base").glob("*.toml")):
        d = tomllib.load(open(base, "rb"))
        for pkg in d["packages"].get("prep", []) + d["packages"].get("main", []):
            pkgs.add(pkg)
    for layer in sorted((ROOT / "profiles" / "layers").glob("*.toml")):
        d = tomllib.load(open(layer, "rb"))
        for pkg in d["packages"].get("prep", []) + d["packages"].get("main", []):
            pkgs.add(pkg)
    return pkgs


def check_official(pkg):
    url = f"https://archlinux.org/packages/search/json/?name={pkg}"
    try:
        with urllib.request.urlopen(url, timeout=10) as r:
            data = json.load(r)
        return len(data.get("results", [])) > 0
    except Exception:
        return None


def check_aur(pkg):
    url = f"https://aur.archlinux.org/rpc/v5/info/{pkg}"
    try:
        with urllib.request.urlopen(url, timeout=10) as r:
            data = json.load(r)
        return data.get("resultcount", 0) > 0
    except Exception:
        return None


def main():
    pkgs = load_packages()
    missing = []
    for pkg in sorted(pkgs):
        in_official = check_official(pkg)
        time.sleep(0.3)
        in_aur = check_aur(pkg)
        time.sleep(0.3)
        if in_official:
            status = "official"
        elif in_aur:
            status = "AUR"
        else:
            status = "!!! NOT FOUND !!!"
            missing.append(pkg)
        print(f"{pkg:35s} {status}")

    if missing:
        print("\n--- MISSING ---")
        for m in missing:
            print(m)
        sys.exit(1)
    print("\nAll packages verified.")


if __name__ == "__main__":
    main()
