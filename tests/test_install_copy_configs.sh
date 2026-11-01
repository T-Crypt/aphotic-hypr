#!/usr/bin/env bash
# shellcheck disable=SC2034  # CNT is read by config_deploy.sh
# tests/test_install_copy_configs.sh
# A flag-driven install with no terminal used to skip copying configs: the
# prompt's default of "no" left bare Hyprland. resolve_copy_configs copies
# unless --no-configs (or a guided answer) already chose, and asks only
# when a terminal is there to answer.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CNT="[NOTE]"
# shellcheck source=lib/install/ui.sh
source "$ROOT/lib/install/ui.sh"
# shellcheck source=lib/install/config_deploy.sh
source "$ROOT/lib/install/config_deploy.sh"

COPY_CONFIGS=""
resolve_copy_configs </dev/null
[[ "$COPY_CONFIGS" == "1" ]] || fail "no terminal and no choice must copy configs, got '$COPY_CONFIGS'"

COPY_CONFIGS="0"
resolve_copy_configs </dev/null
[[ "$COPY_CONFIGS" == "0" ]] || fail "--no-configs must stay off, got '$COPY_CONFIGS'"

COPY_CONFIGS="1"
resolve_copy_configs </dev/null
[[ "$COPY_CONFIGS" == "1" ]] || fail "a guided yes must stay on, got '$COPY_CONFIGS'"

grep -q -- '--no-configs) COPY_CONFIGS=0' "$ROOT/install.sh" || fail "install.sh does not parse --no-configs"
"$ROOT/install.sh" --help | grep -q -- '--no-configs' || fail "--help does not list --no-configs"

echo "PASS: flag-driven installs with no terminal copy configs; --no-configs opts out"
