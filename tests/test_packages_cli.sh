#!/usr/bin/env bash
# tests/test_packages_cli.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

OK_LOG="$WORKDIR/ok.log"
ERR_LOG="$WORKDIR/err.log"

aphotic_ok()  { echo "$*" >> "$OK_LOG"; }
aphotic_err() { echo "$*" >> "$ERR_LOG"; }
# Matches the real aphotic_log (globalcontrol.sh): prints to stdout, same as
# aphotic_cmd_packages' own `check` (no --notify) output path relies on.
aphotic_log() { printf '%s\n' "$*"; }
aphotic_require() {
    command -v "$1" >/dev/null 2>&1 || { aphotic_err "missing dependency: $1"; return 1; }
}

source "$ROOT/Configs/.local/lib/aphotic/commands/cmd_packages.sh"

export HOME="$WORKDIR/home"
mkdir -p "$HOME"

mkdir -p "$WORKDIR/bin"
export PATH="$WORKDIR/bin:$PATH"

reset_logs() { : > "$OK_LOG"; : > "$ERR_LOG"; }

# Shadow checkupdates/yay for the whole test, not just the "has updates"
# case -- this machine may have real ones on PATH already, and a fake bin
# dir prepended to PATH still loses to them if they're not shadowed here
# too (command -v finds the real binary if this dir's stub doesn't exist
# yet at call time).
HYPRCTL_LOG="$WORKDIR/hyprctl.log"
cat > "$WORKDIR/bin/hyprctl" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$HYPRCTL_LOG"
EOF
chmod +x "$WORKDIR/bin/hyprctl"

cat > "$WORKDIR/bin/checkupdates" <<'EOF'
#!/usr/bin/env bash
true
EOF
chmod +x "$WORKDIR/bin/checkupdates"
cat > "$WORKDIR/bin/yay" <<'EOF'
#!/usr/bin/env bash
true
EOF
chmod +x "$WORKDIR/bin/yay"

# --- check: stubs report zero updates -> zero counts, no notify ---
reset_logs
out="$(aphotic_cmd_packages check)"
echo "$out" | grep -q "no pending package updates" || fail "expected a no-updates message, got: $out"
[[ -f "$HYPRCTL_LOG" ]] && fail "hyprctl should not be called by a plain 'check' with zero updates"

# --- check: stubs now report real pending updates ---
cat > "$WORKDIR/bin/checkupdates" <<'EOF'
#!/usr/bin/env bash
printf 'pkg-a 1.0-1 -> 1.0-2\npkg-b 2.0-1 -> 2.0-2\n'
EOF
cat > "$WORKDIR/bin/yay" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "-Qua" ]] && printf 'aur-pkg 3.0-1 -> 3.0-2\n'
EOF

reset_logs
out="$(aphotic_cmd_packages check)"
echo "$out" | grep -q "2 official" || fail "expected '2 official' in output, got: $out"
echo "$out" | grep -q "1 AUR" || fail "expected '1 AUR' in output, got: $out"
echo "$out" | grep -q "yay -Sua" || fail "expected the yay hint in output, got: $out"

# --- check --notify: same counts, delivered via hyprctl instead of stdout ---
: > "$HYPRCTL_LOG"
out="$(aphotic_cmd_packages check --notify)"
[[ -z "$out" ]] || fail "expected --notify to produce no stdout, got: $out"
grep -q "notify" "$HYPRCTL_LOG" || fail "expected hyprctl notify to have been called, log: $(cat "$HYPRCTL_LOG" 2>/dev/null)"
grep -q "2 official + 1 AUR" "$HYPRCTL_LOG" || fail "expected the combined official+AUR count in the notification, got: $(cat "$HYPRCTL_LOG")"

# --- set-timer: fake systemctl logging every call ---
SYSTEMCTL_LOG="$WORKDIR/systemctl.log"
cat > "$WORKDIR/bin/systemctl" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$SYSTEMCTL_LOG"
exit 0
EOF
chmod +x "$WORKDIR/bin/systemctl"
OVERRIDE_DIR="$HOME/.config/systemd/user/aphotic-package-check.timer.d"

: > "$SYSTEMCTL_LOG"
aphotic_cmd_packages set-timer daily
grep -q "enable --now aphotic-package-check.timer" "$SYSTEMCTL_LOG" || fail "expected 'daily' to enable --now the timer, log: $(cat "$SYSTEMCTL_LOG")"
[[ -f "$OVERRIDE_DIR/override.conf" ]] && fail "expected no override.conf for the 'daily' (shipped-default) frequency"

: > "$SYSTEMCTL_LOG"
aphotic_cmd_packages set-timer weekly
[[ -f "$OVERRIDE_DIR/override.conf" ]] || fail "expected set-timer weekly to write an override.conf"
grep -q "OnCalendar=weekly" "$OVERRIDE_DIR/override.conf" || fail "expected OnCalendar=weekly in the override, got: $(cat "$OVERRIDE_DIR/override.conf")"
grep -q "enable --now aphotic-package-check.timer" "$SYSTEMCTL_LOG" || fail "expected 'weekly' to enable --now the timer"

: > "$SYSTEMCTL_LOG"
aphotic_cmd_packages set-timer off
grep -q "disable --now aphotic-package-check.timer" "$SYSTEMCTL_LOG" || fail "expected 'off' to disable --now the timer, log: $(cat "$SYSTEMCTL_LOG")"

# Switching back to daily must clear a previously-written override.
aphotic_cmd_packages set-timer weekly >/dev/null
[[ -f "$OVERRIDE_DIR/override.conf" ]] || fail "sanity: weekly override should exist before testing removal"
aphotic_cmd_packages set-timer daily >/dev/null
[[ -f "$OVERRIDE_DIR/override.conf" ]] && fail "expected set-timer daily to remove a prior weekly override.conf"

# Invalid frequency is rejected, not silently ignored.
reset_logs
if aphotic_cmd_packages set-timer bogus 2>/dev/null; then
    fail "expected an unknown frequency to fail"
fi

echo "PASS: aphotic packages check/--notify/set-timer (advisory-only, never applies updates itself)"
