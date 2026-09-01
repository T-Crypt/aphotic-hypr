pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// One capture/restore path for desktop state, shared by every profile
// regardless of which domain triggered the transition -- a gaming profile
// and a security profile restore through the exact same code, so "did it
// come back" is one behaviour to get right instead of four.
//
// Restore is the only automatic action anywhere in this substrate, and it
// is a rollback: every part is diffed against live state first and skipped
// when it already matches, so restoring never writes back something the
// user changed themselves and never re-applies a monitor mode that is
// already correct.
//
// The monitors part is asynchronous, and has to be. Quickshell's cached
// Hyprland monitor data (HyprlandMonitor.lastIpcObject) is only refreshed
// on monitor add/remove/focus events, and a runtime monitor
// reconfiguration emits none of those -- verified live: after
// `hl.monitor({... scale = 1.25})`, hyprctl reports the new scale and
// Quickshell still reports the old one indefinitely. Capturing from that
// cache silently records stale geometry and the restore diff then compares
// stale against stale and skips, so both sides read `hyprctl -j monitors`
// directly instead. That is one process spawn per capture and per restore
// of a profile that asked for monitors, and none at all otherwise.
//
// Deliberately in-memory only. Persisting snapshots across a shell restart
// would mean deciding whether to auto-roll-back state captured by a
// profile that died with the shell, which is a real design question with
// no consumer yet -- see the PR for this branch.
Singleton {
    id: root

    readonly property var allParts: ["theme", "workspace", "monitors", "notifications"]

    readonly property var snapshots: root._snapshots
    readonly property var capturedIds: Object.keys(root._snapshots)
    readonly property int queuedJobs: root._jobs.length

    // What the last rollback actually wrote back. restore() is
    // asynchronous, so this is how a caller (or `qs ipc call profile
    // state`) sees which parts genuinely differed.
    readonly property var lastRestore: root._lastRestore

    signal captured(profileId: string, parts: var)
    signal restored(profileId: string, applied: var)

    property var _snapshots: ({})
    property var _jobs: []
    property bool _reading: false
    property var _lastRestore: null

    // Returns the snapshot. `complete` is false until the monitors read
    // lands; callers that must not mutate state before the capture is
    // finished wait for captured() (ProfileEngine parks in APPLY).
    function capture(profileId: string, parts: var): var {
        const wanted = (Array.isArray(parts) && parts.length > 0 ? parts : root.allParts).filter(p => root.allParts.includes(p));
        const snapshot = {
            profileId: profileId,
            at: Date.now(),
            parts: wanted,
            complete: !wanted.includes("monitors")
        };

        if (wanted.includes("theme"))
            snapshot.theme = root._captureTheme();
        if (wanted.includes("workspace"))
            snapshot.workspace = root._captureWorkspace();
        if (wanted.includes("notifications"))
            snapshot.notifications = root._captureNotifications();

        root._store(profileId, snapshot);

        if (snapshot.complete)
            root.captured(profileId, wanted);
        else
            root._enqueue({ kind: "capture", profileId: profileId });

        return snapshot;
    }

    function snapshotOf(profileId: string): var {
        return root._snapshots[profileId] ?? null;
    }

    function isComplete(profileId: string): bool {
        return !!root._snapshots[profileId]?.complete;
    }

    function discard(profileId: string): void {
        if (!root._snapshots[profileId])
            return;
        const next = Object.assign({}, root._snapshots);
        delete next[profileId];
        root._snapshots = next;
    }

    // Emits restored(profileId, appliedParts) when the rollback has been
    // issued; appliedParts holds only the parts that actually differed.
    function restore(profileId: string): bool {
        const snapshot = root._snapshots[profileId];
        if (!snapshot) {
            root.restored(profileId, []);
            return false;
        }
        if (!snapshot.monitors) {
            root._finishRestore(profileId, []);
            return true;
        }
        root._enqueue({ kind: "restore", profileId: profileId });
        return true;
    }

    function _store(profileId: string, snapshot: var): void {
        const next = Object.assign({}, root._snapshots);
        next[profileId] = snapshot;
        root._snapshots = next;
    }

    function _finishRestore(profileId: string, applied: var): void {
        const snapshot = root._snapshots[profileId];
        if (!snapshot)
            return;

        if (snapshot.theme && root._restoreTheme(snapshot.theme))
            applied.push("theme");
        if (snapshot.notifications && root._restoreNotifications(snapshot.notifications))
            applied.push("notifications");
        if (snapshot.workspace && root._restoreWorkspace(snapshot.workspace))
            applied.push("workspace");

        root.discard(profileId);
        root._lastRestore = { profileId: profileId, applied: applied, at: Date.now() };
        root.restored(profileId, applied);
    }

    function _captureTheme(): var {
        return {
            theme: Themes.activeTheme,
            wallpaper: Themes.activeWallpaper
        };
    }

    function _restoreTheme(snap: var): bool {
        if (!snap.theme)
            return false;
        if (snap.theme === Themes.activeTheme && snap.wallpaper === Themes.activeWallpaper)
            return false;
        Themes.setTheme(snap.theme, snap.wallpaper);
        return true;
    }

    // Window-to-workspace placement is recorded but never replayed:
    // dragging the user's windows back where a profile found them is a
    // destructive action dressed up as a rollback. What restores is focus.
    function _captureWorkspace(): var {
        return {
            focusedMonitor: Hypr.focusedMonitor?.name ?? "",
            focusedWorkspace: Hypr.activeWsId,
            monitors: Hypr.monitors.values.map(m => ({
                name: m.name,
                activeWorkspace: m.lastIpcObject?.activeWorkspace?.id ?? -1,
                specialWorkspace: m.lastIpcObject?.specialWorkspace?.name ?? ""
            })),
            toplevels: Hypr.toplevels.values.map(t => ({
                address: t.address,
                workspace: t.workspace?.id ?? -1,
                title: t.title ?? ""
            }))
        };
    }

    // The originally-focused monitor's workspace goes last so focus ends up
    // where it started -- a workspace focus follows that workspace to
    // whichever monitor owns it, which is also why no focusmonitor dispatch
    // is needed. Special workspaces are recorded but not replayed: the only
    // way to set one is a toggle, and a toggle is not a rollback.
    function _restoreWorkspace(snap: var): bool {
        const focusLast = snap.monitors.find(m => m.name === snap.focusedMonitor);
        const others = snap.monitors.filter(m => m.name !== snap.focusedMonitor);
        let changed = false;

        for (const entry of others.concat(focusLast ? [focusLast] : [])) {
            const live = Hypr.monitors.values.find(m => m.name === entry.name);
            if (!live || entry.activeWorkspace < 0)
                continue;

            const wsDiffers = (live.lastIpcObject?.activeWorkspace?.id ?? -1) !== entry.activeWorkspace;
            const focusDiffers = entry.name === snap.focusedMonitor && Hypr.focusedMonitor?.name !== entry.name;
            if (!wsDiffers && !focusDiffers)
                continue;

            Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = ${entry.activeWorkspace} })` : `workspace ${entry.activeWorkspace}`);
            changed = true;
        }
        return changed;
    }

    function monitorState(ipc: var): var {
        return {
            name: ipc.name ?? "",
            disabled: !!ipc.disabled,
            width: ipc.width ?? 0,
            height: ipc.height ?? 0,
            refresh: typeof ipc.refreshRate === "number" ? ipc.refreshRate.toFixed(2) : "preferred",
            x: ipc.x ?? 0,
            y: ipc.y ?? 0,
            scale: ipc.scale ?? 1,
            transform: ipc.transform ?? 0
        };
    }

    function monitorKey(state: var): string {
        return `${state.disabled}|${state.width}x${state.height}@${state.refresh}|${state.x}x${state.y}|${state.scale}|${state.transform}`;
    }

    // Monitor layout is config, not an action, so this is `hyprctl` rather
    // than a dispatch -- and the two config parsers take it differently:
    // `hyprctl keyword` is refused outright under the Lua parser ("keyword
    // can't work with non-legacy parsers"), where the runtime equivalent is
    // hl.monitor() through `hyprctl eval`. Both forms verified live; the
    // disabled branch is the one case not exercised (single-output rig).
    function monitorCommand(state: var): string {
        const mode = `${state.width}x${state.height}@${state.refresh}`;
        if (Hypr.usingLua) {
            if (state.disabled)
                return `hyprctl eval 'hl.monitor({ output = "${state.name}", disabled = true })'`;
            const fields = [`output = "${state.name}"`, `mode = "${mode}"`, `position = "${state.x}x${state.y}"`, `scale = ${state.scale}`];
            if (state.transform)
                fields.push(`transform = ${state.transform}`);
            return `hyprctl eval 'hl.monitor({ ${fields.join(", ")} })'`;
        }
        if (state.disabled)
            return `hyprctl keyword monitor '${state.name},disable'`;
        const spec = `${state.name},${mode},${state.x}x${state.y},${state.scale}`;
        return `hyprctl keyword monitor '${state.transform ? `${spec},transform,${state.transform}` : spec}'`;
    }

    function _captureNotifications(): var {
        return {
            dnd: Settings.dndEnabled
        };
    }

    function _restoreNotifications(snap: var): bool {
        if (Settings.dndEnabled === snap.dnd)
            return false;
        Settings.dndEnabled = snap.dnd;
        return true;
    }

    // One reader, one job at a time. The _reading guard is load-bearing, not
    // defensive: completing a capture emits captured(), which runs the
    // profile's onApply, which may itself capture -- that re-entrant
    // _enqueue lands while this handler is still unwinding, so without the
    // flag both it and the tail of _completeJob would start a read.
    function _enqueue(job: var): void {
        root._jobs = root._jobs.concat([job]);
        root._pump();
    }

    function _pump(): void {
        if (root._reading || root._jobs.length === 0)
            return;
        root._reading = true;
        monitorRead.exec(["hyprctl", "-j", "monitors"]);
    }

    function _completeJob(live: var): void {
        root._reading = false;
        const job = root._jobs[0];
        root._jobs = root._jobs.slice(1);

        if (job) {
            if (job.kind === "capture")
                root._completeCapture(job.profileId, live);
            else
                root._completeRestore(job.profileId, live);
        }

        root._pump();
    }

    function _completeCapture(profileId: string, live: var): void {
        const snapshot = root._snapshots[profileId];
        if (!snapshot)
            return;
        snapshot.monitors = live.map(m => root.monitorState(m));
        snapshot.complete = true;
        root._store(profileId, snapshot);
        root.captured(profileId, snapshot.parts);
    }

    function _completeRestore(profileId: string, live: var): void {
        const snapshot = root._snapshots[profileId];
        if (!snapshot)
            return;

        const commands = [];
        for (const entry of snapshot.monitors) {
            const current = live.find(m => m.name === entry.name);
            if (!current)
                continue;
            if (root.monitorKey(root.monitorState(current)) === root.monitorKey(entry))
                continue;
            commands.push(root.monitorCommand(entry));
        }

        const applied = [];
        if (commands.length > 0) {
            monitorConfig.exec(["sh", "-c", commands.join("; ")]);
            applied.push("monitors");
        }
        root._finishRestore(profileId, applied);
    }

    Process {
        id: monitorRead

        stdout: StdioCollector {
            onStreamFinished: {
                let live = [];
                try {
                    live = JSON.parse(text);
                } catch (e) {
                    console.warn(`StateSnapshot: could not read monitors: ${e}`);
                }
                root._completeJob(Array.isArray(live) ? live : []);
            }
        }
    }

    Process {
        id: monitorConfig
    }
}
