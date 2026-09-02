#!/usr/bin/env bash
# tests/test_install_default_profile.sh
#
# Task D (modular install.sh refactor): a fresh install with none of
# --profile/--with/--opt-in must default to the zero-prompt daily-driver
# path (full profile, no optional layers) rather than the old
# always-interactive wizard -- and --opt-in must still restore that wizard
# for anyone who wants it.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
rm -f aphotic.toml

output=$(bash install.sh --dry-run < /dev/null 2>&1)
status=$?
[[ "$status" -eq 0 ]] || fail "bare install.sh --dry-run exited $status"

echo "$output" | grep -q "profile: full" || fail "expected the bare invocation to default to profile: full"
echo "$output" | grep -q "^  layers: $" || fail "expected the bare invocation to default to no layers"
echo "$output" | grep -qi "daily-driver setup" || fail "expected a note explaining the zero-prompt default"
echo "$output" | grep -q "Optional extra tool sets:" && fail "bare invocation must not show the interactive layer picker"

[[ ! -f aphotic.toml ]] || fail "dry-run should not have written aphotic.toml"

# --opt-in restores just the pickers (not the guided flow, which only
# engages with no flags at all on a TTY): answer profile, preset 1
# (everything), theme.
output=$(printf "full\n1\ndefault\n" | bash install.sh --dry-run --opt-in 2>&1)
echo "$output" | grep -q "Optional extra tool sets:" || fail "expected --opt-in to show the interactive layer picker"
echo "$output" | grep -q "layers: gaming,dev,ai,exploit-recon,exploit-web,exploit-network" \
  || fail "expected --opt-in preset 1 to resolve to the full layer set"

echo "PASS: install.sh default profile (daily-driver) vs --opt-in wizard"
