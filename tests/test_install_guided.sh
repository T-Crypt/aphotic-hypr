#!/usr/bin/env bash
# tests/test_install_guided.sh
#
# The guided (no-flags, TTY) install path in lib/install/guided.sh: the
# four ordered steps, the batched add-ons step that replaced five
# scattered prompts, the summary gate, and -- most importantly -- that
# none of it engages for a flag-driven or non-TTY run, which is what
# every scripted/CI caller relies on.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CNT="[NOTE]"; COK="[OK]"; CER="[ERROR]"; CWR="[WARNING]"; CAT="[ATTENTION]"; CAC="[ACTION]"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
INSTLOG="$WORKDIR/install.log"
APHOTIC_BACKUP_ROOT="$WORKDIR/.config-backup"

source "$ROOT/lib/install/ui.sh"
source "$ROOT/lib/install/backup.sh"
source "$ROOT/lib/install/wizard.sh"
source "$ROOT/lib/install/conflicts.sh"
source "$ROOT/lib/install/guided.sh"

# Answers are fed from a real file, not a pipe: guided_configure calls the
# pickers in command substitutions, and only a seekable fd keeps the read
# position shared across those subshells.
answers() { printf '%b' "$1" > "$WORKDIR/answers"; }

# --- the gate: a flag-driven, no-TTY run must never enter the guided flow
cd "$ROOT"
rm -f aphotic.toml
output=$(bash install.sh --dry-run --profile full --theme default < /dev/null 2>&1)
echo "$output" | grep -q "Guided setup" && fail "--dry-run must not enter the guided flow"
echo "$output" | grep -q "Ready to install" && fail "--dry-run must not show the guided summary"
echo "$output" | grep -q "profile: full" || fail "expected the flag-driven dry-run plan, got: $output"

output=$(bash install.sh --dry-run < /dev/null 2>&1)
echo "$output" | grep -q "Guided setup" && fail "a bare no-TTY run must not enter the guided flow"
echo "$output" | grep -qi "daily-driver setup" || fail "expected the zero-prompt daily-driver default to survive"

# --- steps 1-3, accepting every default
DETECTED_APHOTIC_INSTALL=0 DETECTED_APHOTIC_PROFILE="" DETECTED_APHOTIC_LAYERS=""
PROFILE="" LAYERS="" THEME=""
GUIDED_STEP=0 GUIDED_STEPS=4
answers '\n\n\n'
guided_configure < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
[[ "$PROFILE" == "full" ]] || fail "expected default profile 'full', got '$PROFILE'"
[[ -z "$LAYERS" ]] || fail "expected no extras by default, got '$LAYERS'"
[[ "$THEME" == "tokyonight" ]] || fail "expected default theme 'tokyonight', got '$THEME'"
grep -q "Step 1 of 4" "$WORKDIR/out" || fail "expected numbered steps, got: $(cat "$WORKDIR/out")"
grep -q "Step 3 of 4: how it looks" "$WORKDIR/out" || fail "expected step 3 to be the theme picker"

# --- steps 1-3, minimal + every extra + first theme
PROFILE="" LAYERS="" THEME=""
GUIDED_STEP=0 GUIDED_STEPS=4
answers '2\n1\n1\n'
guided_configure < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
[[ "$PROFILE" == "minimal" ]] || fail "expected 'minimal' for choice 2, got '$PROFILE'"
[[ "$LAYERS" == "gaming,dev,ai,exploit" ]] || fail "expected all extras, got '$LAYERS'"
[[ "$THEME" == "gruvbox" ]] || fail "expected 'gruvbox' for theme 1, got '$THEME'"

# --- an existing install is offered back, and skips steps 1-2
DETECTED_APHOTIC_INSTALL=1 DETECTED_APHOTIC_PROFILE="minimal" DETECTED_APHOTIC_LAYERS="gaming,dev"
PROFILE="" LAYERS="" THEME=""
GUIDED_STEP=0 GUIDED_STEPS=4
answers '\n\n'
guided_configure < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
[[ "$PROFILE" == "minimal" ]] || fail "expected the saved profile to be reused, got '$PROFILE'"
[[ "$LAYERS" == "gaming,dev" ]] || fail "expected the saved extras to be reused, got '$LAYERS'"
[[ "$THEME" == "tokyonight" ]] || fail "expected the theme to still be asked, got '$THEME'"
grep -q "Step 1 of 2" "$WORKDIR/out" || fail "expected a 2-step flow when reusing, got: $(cat "$WORKDIR/out")"
DETECTED_APHOTIC_INSTALL=0

# --- step 4: pressing Enter turns nothing on
DETECTED_NVIDIA_PRESENT="true" DETECTED_NVIDIA_DRIVER=""
LAYERS="" ASSISTANT="" ACTIVATE_STARSHIP="" ACTIVATE_ZSH="" COPY_CONFIGS=""
GUIDED_STEP=3 GUIDED_STEPS=4
answers '\n'
guided_step_addons < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
[[ "$ASSISTANT" == "false" ]] || fail "expected the assistant off by default, got '$ASSISTANT'"
[[ "$ACTIVATE_STARSHIP" == "0" ]] || fail "expected starship off by default, got '$ACTIVATE_STARSHIP'"
[[ "$ACTIVATE_ZSH" == "0" ]] || fail "expected zsh off by default, got '$ACTIVATE_ZSH'"
[[ "$COPY_CONFIGS" == "1" ]] || fail "guided installs must always deploy configs, got '$COPY_CONFIGS'"
grep -q "No add-ons selected" "$WORKDIR/out" || fail "expected the empty selection echoed back"
grep -q "Step 4 of 4" "$WORKDIR/out" || fail "expected the add-ons step numbered 4"

# --- step 4: numbers select, garbage is reported and ignored
answers '1 2 nope 9\n'
guided_step_addons < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
[[ "$ASSISTANT" == "true" ]] || fail "expected add-on 1 (assistant) selected"
[[ "$ACTIVATE_STARSHIP" == "1" ]] || fail "expected add-on 2 (starship) selected"
[[ "$ACTIVATE_ZSH" == "0" ]] || fail "expected add-on 3 left alone"
grep -q 'Ignoring "nope"' "$WORKDIR/out" || fail "expected non-numeric input to be reported"
grep -q 'Ignoring "9"' "$WORKDIR/out" || fail "expected out-of-range input to be reported"
grep -q "Add-ons: Aphotic Assistant, starship prompt" "$WORKDIR/out" \
  || fail "expected the selection echoed back as a readable list, got: $(cat "$WORKDIR/out")"

# --- step 4: no NVIDIA card means no assistant row at all, so the numbers shift
DETECTED_NVIDIA_PRESENT="false"
answers '1\n'
guided_step_addons < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
[[ "$ASSISTANT" == "false" ]] || fail "the assistant must not be offered without an NVIDIA card"
[[ "$ACTIVATE_STARSHIP" == "1" ]] || fail "expected 1 to be starship when the assistant row is absent"
grep -q "Aphotic Assistant" "$WORKDIR/out" && fail "assistant row shown without an NVIDIA card"

# --- the summary gate: declining stops without touching anything
DETECTED_NVIDIA_PRESENT="true" DETECTED_NVIDIA_DRIVER="nvidia-dkms" NVIDIA_DRIVER_ACTION="keep"
PROFILE="full" LAYERS="gaming,ai" THEME="tokyonight" NO_BACKUP=0
ASSISTANT="false" ACTIVATE_STARSHIP=0 ACTIVATE_ZSH=0
answers 'n\n'
set +e
output=$(guided_plan_and_confirm "qt6-wayland
jq" "quickshell
kitty
firefox" < "$WORKDIR/answers" 2>&1)
status=$?
set -e
[[ "$status" -eq 0 ]] || fail "declining the summary should exit 0, got $status"
echo "$output" | grep -q "5 to install" || fail "expected the package count in the summary, got: $output"
echo "$output" | grep -q "keeping the NVIDIA driver you already have" || fail "expected the NVIDIA plan line, got: $output"
echo "$output" | grep -q "gaming -- Steam" || fail "expected extras spelled out in plain language, got: $output"
echo "$output" | grep -q "full desktop (Aphotic plus browser" || fail "expected a plain-language profile line, got: $output"
echo "$output" | grep -q "No packages were installed" || fail "expected an explicit nothing-happened message, got: $output"

answers 'y\n'
guided_plan_and_confirm "jq" "quickshell" < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1 \
  || fail "accepting the summary should return 0"

# --- the replaced-role packages question moves ahead of the summary, and
#     only records an answer there (the removal still happens in prep)
pacman() { [[ "$1" == "-Qq" ]] && printf "bash\nwaybar\n"; }
sudo() { echo "SUDO_CALLED_UNEXPECTEDLY: $*"; }
export -f sudo
STRIP_CONFLICTS=""
answers '\n'
prompt_conflicting_packages < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
[[ "$STRIP_CONFLICTS" == "1" ]] || fail "expected the default answer to remove replaced-role packages, got '$STRIP_CONFLICTS'"
grep -q "SUDO_CALLED_UNEXPECTEDLY" "$WORKDIR/out" && fail "the early question must not uninstall anything itself"

STRIP_CONFLICTS=""
answers 'n\n'
prompt_conflicting_packages < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
[[ "$STRIP_CONFLICTS" == "0" ]] || fail "expected 'n' to keep the packages, got '$STRIP_CONFLICTS'"

# an explicit --strip-conflicts/--keep-conflicts is never re-asked
STRIP_CONFLICTS="0"
answers 'y\n'
prompt_conflicting_packages < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
[[ "$STRIP_CONFLICTS" == "0" ]] || fail "a flag-set answer must not be overridden by the prompt"
unset -f sudo pacman

echo "PASS: guided install flow (steps, batched add-ons, summary gate, flag bypass)"
