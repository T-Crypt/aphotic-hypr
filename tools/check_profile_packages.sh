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
exit "$missing"
