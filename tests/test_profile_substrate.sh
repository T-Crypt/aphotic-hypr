#!/usr/bin/env bash
# tests/test_profile_substrate.sh
#
# Structural guards for the Phase 0 profile substrate
# (docs/APHOTIC_UNIFIED_VISION.md section 3.5). These are the invariants
# that can regress silently -- a Timer added "just for now", a kill call
# added to make a suspend actually stick, a resource declared in core so a
# base install starts arbitrating. None of them show up as a broken shell,
# which is exactly why they need a test.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

QS="Configs/quickshell/aphotic"
SUB="$QS/services/profile"
UI="$QS/modules/negotiation"

for f in "$SUB/ProfileEngine.qml" "$SUB/ResourceEngine.qml" "$SUB/ProfileEvents.qml" \
         "$SUB/StateSnapshot.qml" "$SUB/RingBuffer.qml" "$SUB/qmldir" \
         "$UI/NegotiationWindow.qml" "$UI/NegotiationContent.qml" "$UI/qmldir"; do
  [[ -f "$f" ]] || fail "missing $f"
done

# Every substrate type is reachable through its module, not an ad hoc import.
for s in ProfileEngine ProfileEvents ResourceEngine StateSnapshot; do
  grep -q "^singleton $s 1.0 $s.qml\$" "$SUB/qmldir" || fail "$s not registered as a singleton in $SUB/qmldir"
done
grep -q "^RingBuffer 1.0 RingBuffer.qml\$" "$SUB/qmldir" || fail "RingBuffer not registered in $SUB/qmldir"
grep -q "^module qs.services.profile\$" "$SUB/qmldir" || fail "$SUB/qmldir has the wrong module name"

# Single-sourced: exactly one definition of each engine, no per-domain copy.
for s in ProfileEngine ResourceEngine; do
  n=$(find "$QS" -name "$s.qml" | wc -l)
  [[ "$n" -eq 1 ]] || fail "found $n copies of $s.qml -- the engines are single-sourced singletons"
done

# Zero cost when no profile is active: the substrate owns no timer and
# watches no file. StateSnapshot's two Process objects are on-demand only.
for f in "$SUB"/*.qml "$UI"/*.qml; do
  grep -qE '^\s*Timer\s*\{' "$f" && fail "$f declares a Timer -- the substrate must add no polling"
  grep -q 'FileView' "$f" && fail "$f uses a FileView -- the substrate must add no always-on file watch"
  grep -qE '^\s*Timer\s*\{|triggeredOnStart' "$f" && fail "$f looks like it polls"
done

# Comments in these files legitimately name the things the code must never
# do ("never touches kernel/sysctl"), so the safety greps below read code
# only.
code() { grep -vE "^\s*(//|\*|/\*)" "$1"; }

# Never terminates a process directly -- suspension only ever goes through
# the owning profile's own gracefulStop hook.
for f in "$SUB"/*.qml "$UI"/*.qml; do
  code "$f" | grep -qE '"(kill|pkill|killall|systemctl)"|\bkill -|SIGKILL|SIGTERM' \
    && fail "$f can terminate a process -- the Resource Engine only asks the owning plugin to stop"
done

# Never touches kernel/sysctl.
for f in "$SUB"/*.qml; do
  code "$f" | grep -qE 'sysctl|/proc/sys/|/sys/kernel' && fail "$f touches kernel tunables"
done

# Core declares no resources, so a base install has nothing to arbitrate
# and can never raise a negotiation prompt.
# A literal resource key is the tell: shell.qml's IPC handler forwards a
# caller-supplied one, which is fine; a hardcoded "gpu.vram" in core is not.
for f in "$SUB"/*.qml "$UI"/*.qml "$QS/shell.qml"; do
  code "$f" | grep -qE 'declareResource\("' \
    && fail "$f declares a resource with a literal key -- capacity is declared by whoever can measure it, never by core"
done

# Static PanelWindow geometry: the prompt animates its content, never the
# window (docs/APHOTIC_UNIFIED_VISION.md section 1.3).
grep -qE '^\s*Behavior on (implicitWidth|implicitHeight|width|height|x|y)\b' "$UI/NegotiationWindow.qml" \
  && fail "NegotiationWindow animates its own geometry -- PanelWindow geometry stays static"
grep -q 'PanelWindow' "$UI/NegotiationWindow.qml" || fail "NegotiationWindow is not a PanelWindow"

# Every binary the substrate can spawn -- the first element of any exec()
# or `command:` array -- must already be declared in BOTH base profiles,
# since the shell always loads in full regardless of install profile.
for b in $(grep -ohE '(exec\(\[|command:\s*\[)"[^"]+"' "$SUB"/*.qml "$UI"/*.qml | grep -oE '"[^"]+"$' | tr -d '"' | sort -u); do
  case "$b" in
    sh) ;;
    hyprctl) ;;
    # glib2, declared in both base profiles -- the Gaming profile's
    # gamemode D-Bus subscription (Quickshell exposes no DBus client).
    gdbus) ;;
    *) fail "substrate spawns '$b', which this test does not know to be a declared base dependency" ;;
  esac
done
# The substrate introduces no new binary dependency: hyprctl is already
# spawned by the base shell (services/Hypr.qml's keyboard-state read), so
# nothing new needs declaring in profiles/base/{full,minimal}.toml. If a
# future change adds a binary the base shell does not already use, that
# rule kicks in and this guard is where it gets noticed.
grep -q 'hyprctl' "$QS/services/Hypr.qml" \
  || fail "hyprctl is no longer spawned by the base shell -- the substrate now adds it as a new dependency and it must be declared in both profiles/base/*.toml"

echo "PASS: profile substrate"
