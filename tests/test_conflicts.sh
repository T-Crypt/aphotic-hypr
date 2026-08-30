#!/usr/bin/env bash
# tests/test_conflicts.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CNT="[NOTE]"; CWR="[WARNING]"; CAT="[ATTENTION]"; CER="[ERROR]"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
INSTLOG="$WORKDIR/install.log"
source "$ROOT/lib/install/conflicts.sh"

# detect_conflicting_ui_packages: only flags what's actually "installed"
pacman() { [[ "$1" == "-Qq" ]] && printf "bash\nwaybar\nrofi-wayland\ncurl\n"; }
mapfile -t found < <(detect_conflicting_ui_packages)
[[ "${found[*]}" == "waybar rofi-wayland" ]] || fail "expected waybar+rofi-wayland detected, got: ${found[*]:-<none>}"

pacman() { [[ "$1" == "-Qq" ]] && printf "bash\ncurl\n"; }
mapfile -t found < <(detect_conflicting_ui_packages)
[[ ${#found[@]} -eq 0 ]] || fail "expected no conflicting packages on a clean system, got: ${found[*]}"

# conflicting_package_role: every listed package maps to a real role, not
# the "a role Aphotic's shell already owns" catch-all
for pkg in "${CONFLICTING_UI_PACKAGES[@]}"; do
  role="$(conflicting_package_role "$pkg")"
  [[ "$role" != "a role Aphotic's shell already owns" ]] || fail "$pkg has no specific role mapping"
done

# check_conflicting_packages: silent no-op when nothing conflicts
pacman() { [[ "$1" == "-Qq" ]] && printf "bash\ncurl\n"; }
sudo() { echo "SUDO_CALLED_UNEXPECTEDLY: $*"; }
export -f sudo
out=$(check_conflicting_packages < /dev/null 2>&1)
[[ -z "$out" ]] || fail "expected no output on a clean system, got: $out"

pacman() { [[ "$1" == "-Qq" ]] && printf "bash\nwaybar\ndunst\n"; }

# non-interactive, no flag -> leaves packages, never calls sudo
out=$(STRIP_CONFLICTS="" check_conflicting_packages < /dev/null 2>&1)
echo "$out" | grep -q "Leaving waybar dunst installed" || fail "expected default-keep message, got: $out"
echo "$out" | grep -q "SUDO_CALLED_UNEXPECTEDLY" && fail "sudo should not run with no flag and no TTY: $out"

# --keep-conflicts (STRIP_CONFLICTS=0) -> leaves packages, never calls sudo
out=$(STRIP_CONFLICTS="0" check_conflicting_packages < /dev/null 2>&1)
echo "$out" | grep -q "Leaving waybar dunst installed" || fail "expected --keep-conflicts to leave packages, got: $out"
echo "$out" | grep -q "SUDO_CALLED_UNEXPECTEDLY" && fail "sudo should not run with --keep-conflicts: $out"
unset -f sudo
true

# --strip-conflicts + dry-run -> only prints the plan, no real sudo call
sudo() { fail "sudo must not run under --dry-run"; }
export -f sudo
out=$(DRY_RUN=1 STRIP_CONFLICTS="1" check_conflicting_packages < /dev/null 2>&1)
echo "$out" | grep -qF "[dry-run] would run: sudo pacman -Rns --noconfirm waybar dunst" || fail "expected dry-run removal plan, got: $out"
unset -f sudo

# --strip-conflicts, real run -> removes via pacman -Rns, logged to INSTLOG
sudo() { echo "SUDO_CALLED: $*" >> "$INSTLOG"; }
export -f sudo
: > "$INSTLOG"
DRY_RUN=0 STRIP_CONFLICTS="1" check_conflicting_packages < /dev/null > /dev/null
grep -qF "SUDO_CALLED: pacman -Rns --noconfirm waybar dunst" "$INSTLOG" || fail "expected sudo pacman -Rns waybar dunst in $INSTLOG, got: $(cat "$INSTLOG")"
unset -f sudo

echo "PASS: conflicting UI package detection + role mapping + strip/keep gating"
