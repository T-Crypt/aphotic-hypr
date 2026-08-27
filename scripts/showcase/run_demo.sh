#!/usr/bin/env bash
set -uo pipefail

APHOTIC_BIN="${APHOTIC_BIN:-aphotic}"
QS_BIN="${QS_BIN:-qs}"

HAS_WTYPE=0
command -v wtype >/dev/null 2>&1 && HAS_WTYPE=1

label() {
    printf '\n[%s] %s (%ss)\n' "$1" "$2" "$3" >&2
}

step() {
    label "SHOWCASE" "$1" "$2"
    sleep "$2"
}

operator() {
    label "OPERATOR ACTION" "$1" "$2"
    sleep "$2"
}

qsipc() {
    local target="$1" fn="$2" arg="${3:-}"
    if [[ -n "$arg" ]]; then
        "$QS_BIN" -c aphotic ipc call "$target" "$fn" "$arg" >/dev/null 2>&1
    else
        "$QS_BIN" -c aphotic ipc call "$target" "$fn" >/dev/null 2>&1
    fi
    return 0
}

type_char() {
    if [[ "$HAS_WTYPE" -eq 1 ]]; then
        wtype -- "$1"
    else
        printf '  (wtype not installed -- type manually: %s)\n' "$1" >&2
    fi
}

clear_char() {
    if [[ "$HAS_WTYPE" -eq 1 ]]; then
        wtype -k BackSpace
    else
        printf '  (wtype not installed -- clear the typed character manually)\n' >&2
    fi
}

printf '=== Aphotic-Hypr showcase demo sequence ===\n' >&2
printf 'Requires on PATH: aphotic, qs, kitty, notify-send, pamixer\n' >&2
printf 'Optional: wtype (Scene 4 prefix typing, otherwise manual)\n' >&2
printf 'Total runtime: 156s live + operator steps\n\n' >&2

step "Scene 1 -- Cold open: desktop at rest" 4

"$APHOTIC_BIN" theme set hackthebox >/dev/null 2>&1
step "Scene 2 -- Theme: HackTheBox (aphotic theme set hackthebox)" 4
"$APHOTIC_BIN" theme set nordic >/dev/null 2>&1
step "Scene 2 -- Theme: Nordic (Super+. cycles the same way)" 4
"$APHOTIC_BIN" theme set windows11 >/dev/null 2>&1
step "Scene 2 -- Theme: Windows 11" 4

operator "Scene 3 -- Hover: volume -> Wi-Fi -> Bluetooth -> battery -> host info -> Pomodoro -> resources" 20
operator "Scene 3 -- Left-click the Claude Code agent indicator, then again to close (toggle, not hover)" 4

qsipc launcher toggle
step "Scene 4 -- Launcher (Super+A): app search" 3
type_char ">"
step "Scene 4 -- Clipboard history mode (>)" 3
clear_char
type_char ":"
step "Scene 4 -- Emoji picker mode (:)" 3
clear_char
type_char "/"
step "Scene 4 -- Window switch mode (/)" 3
clear_char
type_char "~"
step "Scene 4 -- Wallpaper mode (~)" 3
clear_char
type_char "@"
step "Scene 4 -- Project jump mode (@)" 3
clear_char
qsipc launcher toggle
step "Scene 4 -- Launcher closed" 2

qsipc picker open
operator "Scene 5 -- Drag-select a region (client-window snapping)" 4
qsipc picker openFreeze
operator "Scene 5 -- Freeze-mode: drag-select on the frozen frame" 4

notify-send "Aphotic" "Showcase notification -- Aphotic-Hypr" -a "Aphotic" >/dev/null 2>&1
step "Scene 6 -- Notification toast" 3
pamixer -i 5 >/dev/null 2>&1
step "Scene 6 -- Volume OSD" 3
qsipc brightness set "40%"
step "Scene 6 -- Brightness OSD down" 2
qsipc brightness set "90%"
step "Scene 6 -- Brightness OSD up" 2

qsipc dashboard toggle
step "Scene 7 -- Command Center (Super+D): Dashboard tab" 3
operator "Scene 7 -- Click Performance tab" 3
operator "Scene 7 -- Click Workspaces tab" 3
operator "Scene 7 -- Click Wallpapers tab" 3
operator "Scene 7 -- Click AI Chat tab" 3
qsipc dashboard toggle
step "Scene 7 -- Command Center closed" 2

qsipc settings toggle
step "Scene 8 -- Settings (Super+I): Appearance theme grid" 3
operator "Scene 8 -- Click Browse all wallpapers" 3
operator "Scene 8 -- Click Theme Creator: build a palette live" 4
operator "Scene 8 -- Click Personalization: accent overrides" 3
operator "Scene 8 -- Click Bar: style/orientation toggle" 3
operator "Scene 8 -- Click AI: Ollama model manager" 3
operator "Scene 8 -- Click Power & Security" 3
operator "Scene 8 -- Click Workspace Profiles" 3
operator "Scene 8 -- Click Plugins pane" 3
operator "Scene 8 -- Click System: doctor output" 3
qsipc settings toggle
step "Scene 8 -- Settings closed" 2

kitty -e bash -lc "aphotic plugin list --remote; sleep 3" >/dev/null 2>&1 &
step "Scene 9 -- aphotic plugin list --remote (terminal)" 4
qsipc settings toggle
operator "Scene 9 -- Settings -> Plugins -> Install OpenRGB Sync" 6
qsipc settings toggle
step "Scene 9 -- Settings closed" 2

qsipc lock engage
step "Scene 10 -- Lock screen (Super+L)" 3
qsipc lock unlock
step "Scene 10 -- Unlocked" 2
qsipc session toggle
step "Scene 10 -- Session/power menu (Super+Backspace)" 3
qsipc session toggle
step "Scene 10 -- Session menu closed" 2

kitty -e "$APHOTIC_BIN" play snake >/dev/null 2>&1 &
step "Scene 11 -- aphotic play snake (terminal)" 4
operator "Scene 11 -- Close the game terminal (q or Ctrl+C)" 2

printf '\n[SHOWCASE] Demo sequence complete -- stop recording now.\n' >&2
