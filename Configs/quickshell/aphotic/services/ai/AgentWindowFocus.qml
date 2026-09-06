// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// There is no session-to-window link anywhere in this codebase -- a
// harness event carries a `cwd` (agent_hook.py forwards Claude Code's own
// hook payload field) and nothing else that names a surface a human is
// looking at. This answers one narrow question with what that leaves us:
// "is exactly one open window's foreground process sitting in this
// directory?" Built for the pet's `attentionRequired` click-to-focus
// (`PETS.md` PET-03's deferred item), but it names no plugin and reads
// no pet state, so anything else wanting "jump to the window behind this
// session" -- the AI notch tab's planned context-injection rework, for
// one -- calls the same `focusByCwd()`.
//
// A Hyprland client's own pid is the terminal emulator (or editor), never
// the shell/harness running inside it -- so the match walks each
// candidate's descendants looking for one whose cwd is the target
// exactly. `pgrep -P` one level at a time, breadth-first, the same
// child-walk `aphotic_shell_stop` (globalcontrol.sh) already uses rather
// than reading /proc/<pid>/task/<pid>/children directly.
//
// Ambiguity fails silent, not loud: resolves to nothing rather than a
// guess. Verified against a live desktop with `hyprctl clients -j` and a
// hand-run copy of the script below: two kitty windows parked in this
// repo were both real, correct matches, but a long-lived, unrelated GUI
// process launched from a shell that happened to be sitting in the same
// directory matched too, purely because it inherited that cwd at launch
// and never left it. That is not a bug to chase -- cwd is genuinely all
// a session's event carries, and a stray match here is exactly the
// ambiguity case, which already resolves to doing nothing. There is no
// UI here for "which one did you mean" and building one is a real
// feature, not a fallback path worth improvising into this.
Singleton {
    id: root

    property Process _match: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const addresses = text.split("\n").map(l => l.trim()).filter(l => l.length > 0);
                if (addresses.length === 1)
                    WindowList.focus(addresses[0]);
            }
        }
    }

    // Walks the process tree under each Hyprland client's pid looking for
    // a descendant whose cwd resolves to exactly `cwd`. Reads Hyprland
    // state that is already live (`Hypr.toplevels`) rather than shelling
    // out to `hyprctl clients` a second time for data this shell already
    // has.
    // One JS string, deliberately kept to a single line: QML's plain
    // `"..."` string can't hold a raw newline (that needs a backtick
    // template literal, and this script is full of bash's own `${...}`/
    // `$(...)`, which a template literal would try to evaluate as JS).
    // Semicolons stand in for the newlines a normal script would have.
    readonly property string _script: "target=\"$1\"; shift; while [ \"$#\" -ge 2 ]; do addr=\"$1\"; pid=\"$2\"; shift 2; queue=(\"$pid\"); matched=0; while [ \"${#queue[@]}\" -gt 0 ]; do p=\"${queue[0]}\"; queue=(\"${queue[@]:1}\"); if [ \"$(readlink -f \"/proc/$p/cwd\" 2>/dev/null)\" = \"$target\" ]; then matched=1; break; fi; while IFS= read -r child; do [ -n \"$child\" ] && queue+=(\"$child\"); done < <(pgrep -P \"$p\" 2>/dev/null); done; [ \"$matched\" = \"1\" ] && printf '%s\\n' \"$addr\"; done"

    // No-op while a match is already in flight -- a second click before
    // the first resolves would otherwise queue a second Process onto the
    // same object mid-run.
    function focusByCwd(cwd: string): void {
        if (!cwd || root._match.running)
            return;
        const pairs = Hypr.toplevels.values.map(t => [t.address, t.lastIpcObject?.pid ?? 0]).filter(([, pid]) => pid > 0);
        if (pairs.length === 0)
            return;
        const args = ["bash", "-c", root._script, "bash", cwd];
        for (const [address, pid] of pairs)
            args.push(address, String(pid));
        root._match.command = args;
        root._match.running = true;
    }
}
