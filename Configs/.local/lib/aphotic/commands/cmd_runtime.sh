#!/usr/bin/env bash
# aphotic runtime — the running shell's composed state in one read: which
# surface owns each screen, the runtime context, the Resource Engine's
# posture (quiet/settling/pressure/contention/negotiating), every
# repeating piece of work the shell has loaded and whether it is live,
# and the enabled plugins. Modules that are not loaded report nothing:
# absence from the activity list means not constructed.
# @cmd: runtime
# @cmd.desc: Show surfaces, runtime context, resource posture and shell activity
# @cmd.group: CORE
# @cmd.opt: [--json]            | Print the raw JSON instead of the summary
# @cmd.opt: back                | Close whatever owns the keyboard on the focused screen

_aphotic_runtime_fetch() {
    aphotic_require qs || return 1
    local out
    if ! out="$(qs -c aphotic ipc call aphotic runtime 2>/dev/null)"; then
        aphotic_err "failed to reach the running shell via qs ipc -- is 'qs -c aphotic' running?"
        return 1
    fi
    printf '%s\n' "$out"
}

# JSON on stdin -> the human summary. Only prints what the shell reported.
_aphotic_runtime_summary() {
    python3 -c '
import json, sys
try:
    s = json.load(sys.stdin)
except Exception as e:
    print("unreadable runtime state: %s" % e, file=sys.stderr)
    sys.exit(1)
ctx = s.get("context", {})
res = s.get("resources", {})
print("APHOTIC RUNTIME")
print()
print("%-14s %s" % ("Context", ctx.get("current", "?")))
level = res.get("level", "?")
line = level.upper()
if res.get("headline"):
    line += "  " + res["headline"]
if level != "quiet" and not res.get("surfaced"):
    line += "  (held back by context)"
print("%-14s %s" % ("Resources", line))
print("%-14s %s" % ("Engine", "dormant" if res.get("dormant") else "tracking claims"))
render = s.get("render", {})
print("%-14s %s" % ("Motion", "decorative" if render.get("decorative") else "gated"))
print()
focused = s.get("focusedScreen", "")
for sc in s.get("screens", []):
    mark = "*" if sc.get("screen") == focused else " "
    owner = sc.get("focusOwner") or "-"
    stack = ", ".join(sc.get("stack", [])) or "-"
    print("%s %-12s %-9s owner=%-18s open=%s" % (mark, sc.get("screen", "?"), sc.get("mode", "?"), owner, stack))
act = s.get("activity") or {}
probes = act.get("probes") or []
if probes:
    print()
    print("Activity  %d active, %d idle, ~%s scheduled wakeups/min" % (act.get("active", 0), act.get("idle", 0), act.get("wakeupsPerMinute", 0)))
    for p in probes:
        state = "ACTIVE" if p.get("active") else "idle"
        every = p.get("interval") or 0
        cadence = ("every %gs" % (every / 1000.0)) if every else ""
        inst = (" x%d" % p["instances"]) if p.get("instances", 1) > 1 else ""
        print("  %-26s %-7s %-7s %s%s" % (p.get("name", "?"), p.get("kind", ""), state, cadence, inst))
plug = s.get("plugins") or {}
if plug:
    names = plug.get("enabled") or []
    line = ", ".join(names) if names else "none"
    if plug.get("safeMode"):
        line += "  (safe mode: none loaded)"
    print()
    print("%-14s %s" % ("Plugins", line))
hist = res.get("history") or []
if hist:
    print()
    print("Recent negotiations")
    for h in hist[:5]:
        print("  %-10s %s: %s vs %s" % (h.get("decision", "?"), h.get("label") or h.get("resource", "?"), h.get("requestor", "?"), h.get("claimant", "?")))
'
}

aphotic_cmd_runtime() {
    local sub="${1:-}"
    case "$sub" in
        --json)
            _aphotic_runtime_fetch
            ;;
        back)
            aphotic_require qs || return 1
            local out
            if ! out="$(qs -c aphotic ipc call aphotic back 2>/dev/null)"; then
                aphotic_err "failed to reach the running shell via qs ipc -- is 'qs -c aphotic' running?"
                return 1
            fi
            [[ -n "$out" ]] && aphotic_ok "closed ${out}" || aphotic_ok "nothing to close"
            ;;
        "")
            local json
            json="$(_aphotic_runtime_fetch)" || return 1
            _aphotic_runtime_summary <<<"$json"
            ;;
        -h|--help)
            cat <<USAGE
Usage: aphotic runtime [--json|back]

  (none)    Surfaces per screen, runtime context and resource posture
  --json    The raw state the shell reported
  back      Close whatever owns the keyboard on the focused screen
USAGE
            ;;
        *)
            aphotic_err "unknown runtime subcommand: ${sub}"
            return 1
            ;;
    esac
}
