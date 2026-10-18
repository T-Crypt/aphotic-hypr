#!/usr/bin/env bash
# tools/check_profile_packages.sh
# Every package a base profile lists must resolve from a synced repo or the
# AUR. A typo or a package dropped upstream otherwise surfaces only as a
# failed install on someone's machine. Needs a synced pacman database.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
missing=0
LIST="$(mktemp)"
trap 'rm -f "$LIST"' EXIT
for profile in full minimal; do
  for field in prep main; do
    python3 "$ROOT/lib/toml/merge.py" --base "$ROOT/profiles/base/$profile.toml" --layers "" --field "$field"
  done
done | tr ' ' '\n' | sed '/^$/d' | sort -u > "$LIST"
aur=()
while read -r pkg; do
  pacman -Si "$pkg" &>/dev/null || aur+=("$pkg")
done < "$LIST"
if ((${#aur[@]})); then
  query="$(printf '&arg[]=%s' "${aur[@]}")"
  found="$(curl -fsS "https://aur.archlinux.org/rpc/v5/info?${query#&}" | python3 -c 'import sys,json;print("\n".join(r["Name"] for r in json.load(sys.stdin)["results"]))')"
  for pkg in "${aur[@]}"; do
    if grep -qx -- "$pkg" <<<"$found"; then
      echo "aur   $pkg"
    else
      echo "MISSING $pkg (in no synced repo and not on the AUR)"
      missing=1
    fi
  done
fi
echo "checked $(wc -l < "$LIST") packages, ${#aur[@]} from the AUR"

# Flatpak applications live in an optional [flatpak] table and never touch
# pacman, so they don't pollute the package list above. Check them against
# the Flathub remote instead.
flatpak_missing=0
FLATPAK_LIST="$(mktemp)"
trap 'rm -f "$LIST" "$FLATPAK_LIST"' EXIT
for profile in full minimal; do
  python3 "$ROOT/lib/toml/merge.py" --base "$ROOT/profiles/base/$profile.toml" --field flatpak
done | sort -u > "$FLATPAK_LIST"
if ! command -v flatpak >/dev/null 2>&1; then
  echo "SKIP flatpak (flatpak not installed on this machine)"
elif ! flatpak remotes --system 2>/dev/null | awk '{print $1}' | grep -qx -- flathub; then
  echo "SKIP flatpak (Flathub remote not configured on this machine)"
else
  while read -r id; do
    [[ -n "$id" ]] || continue
    if flatpak remote-info --system flathub "$id" &>/dev/null; then
      echo "flatpak  $id"
    else
      echo "MISSING $id (not on Flathub)"
      flatpak_missing=1
    fi
  done < "$FLATPAK_LIST"
fi
echo "checked $(wc -l < "$FLATPAK_LIST") Flatpak apps"
exit $((missing || flatpak_missing))
