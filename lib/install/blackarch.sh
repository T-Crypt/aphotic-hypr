#!/usr/bin/env bash
set -euo pipefail

BLACKARCH_STRAP_URL="https://blackarch.org/strap.sh"
# blackarch.org moved the published checksum from /strap.sh.sha1sum (now a
# soft-404 that serves the homepage with HTTP 200 instead of erroring) to
# /checksums/strap -- same file BlackArch's own downloads.html now points
# at. The old URL made ensure_blackarch_repo() below always fail its
# checksum check (comparing the real strap.sh hash against garbage HTML),
# silently blocking the BlackArch repo -- and with it every exploit-*
# layer package that isn't also on the AUR or in Arch's official repos.
BLACKARCH_STRAP_SHA1SUM_URL="https://blackarch.org/checksums/strap"
BLACKARCH_KEYRING_PKG="blackarch-keyring"

blackarch_repo_present() {
  grep -q '^\[blackarch\]' /etc/pacman.conf 2>/dev/null
}

print_blackarch_warning() {
  cat <<'EOF'

[WARNING] The "exploit" layer adds the BlackArch repo to /etc/pacman.conf.
BlackArch is a large, fast-moving repo layered on top of Arch, and it is
not held to the same stability bar as Arch's own official repos:
  - Some BlackArch packages shadow/replace official ones (its own rebuilds
    of common tools are the classic case) if a later `sudo pacman -Syu`
    pulls one in without you noticing.
  - The repo occasionally ships a broken package between fixes.

If something breaks after enabling it:
  - Force-reinstall the official copy of a broken package:
      sudo pacman -S extra/<package>
  - Remove BlackArch entirely: delete the [blackarch] block this script
    appends to /etc/pacman.conf, then:
      sudo pacman -R blackarch-keyring
      sudo pacman -Syyuu
  - Full walkthrough: docs/exploit-layer.md

EOF
}

# Downloads BlackArch's official strap.sh and verifies it against their
# published sha1sum before running it as root -- strap.sh's job is just
# appending a [blackarch] section to /etc/pacman.conf and importing/
# signing their key, but it's still a third-party script run as root, so
# it gets the same "verify before execute" treatment a careful sysadmin
# would give it by hand rather than a blind curl-pipe-sudo.
ensure_blackarch_repo() {
  if blackarch_repo_present; then
    return 0
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[dry-run] would download, verify, and run blackarch.org/strap.sh to enable the BlackArch repo"
    return 0
  fi

  local workdir strap_sh strap_sum expected_sum actual_sum
  workdir=$(mktemp -d)
  trap 'rm -rf "$workdir"' RETURN
  strap_sh="$workdir/strap.sh"
  strap_sum="$workdir/strap.sh.sha1sum"

  curl -fsSL "$BLACKARCH_STRAP_URL" -o "$strap_sh" || { echo "Failed to download $BLACKARCH_STRAP_URL" >&2; return 1; }
  curl -fsSL "$BLACKARCH_STRAP_SHA1SUM_URL" -o "$strap_sum" || { echo "Failed to download $BLACKARCH_STRAP_SHA1SUM_URL" >&2; return 1; }

  expected_sum=$(awk '{print $1}' "$strap_sum")
  actual_sum=$(sha1sum "$strap_sh" | awk '{print $1}')
  if ! [[ "$expected_sum" =~ ^[0-9a-f]{40}$ ]]; then
    echo "$BLACKARCH_STRAP_SHA1SUM_URL didn't return a sha1sum (got: ${expected_sum:0:40}...) -- blackarch.org likely moved/renamed it again. Nothing was changed." >&2
    return 1
  fi
  if [[ "$expected_sum" != "$actual_sum" ]]; then
    echo "BlackArch strap.sh checksum mismatch (expected $expected_sum, got $actual_sum) -- refusing to run it. Nothing was changed." >&2
    return 1
  fi

  chmod +x "$strap_sh"
  sudo "$strap_sh"
  sudo pacman -Sy --noconfirm
}
