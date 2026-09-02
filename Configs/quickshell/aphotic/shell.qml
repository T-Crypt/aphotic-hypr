import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.modules.bar
import qs.modules.launcher
import qs.modules.notifications
import qs.modules.osd
import qs.modules.lock
import qs.modules.session
import qs.modules.dashboard
import qs.modules.settings
import qs.modules.background
import qs.modules.areapicker
import qs.modules.colorpicker
import qs.modules.intelligence
import qs.modules.notificationcenter
import qs.modules.pkginstall
import qs.modules.wallpaperpicker
import qs.modules.keybinds
import qs.modules.negotiation
import qs.services
import qs.services.profile

ShellRoot {
    id: root

    function screenStateFor(screen: var): ScreenState {
        for (let i = 0; i < screenStates.instances.length; i++) {
            const s = screenStates.instances[i];
            if (s.modelData === screen)
                return s;
        }
        return null;
    }

    // Every IPC toggle() below used to just grab `instances[0]` -- the
    // first screen in Quickshell.screens' own enumeration order, which
    // has no relationship to which monitor the user is actually looking
    // at. On a single-monitor box that's harmless (there's only one
    // instance), which is exactly why this went unnoticed -- on multi-
    // monitor it meant every keybind/IPC-triggered popout (Settings,
    // Dashboard, launcher, ...) always opened on whichever screen
    // happened to enumerate first, never the focused one. Each window
    // instance sets `screen: modelData` from its own Quickshell.screens
    // entry (see DashboardWindow.qml etc.), and Quickshell.screens
    // entries expose `.name` matching the Wayland output name Hyprland's
    // own HyprlandMonitor also reports -- so matching on that name finds
    // the instance actually on the focused monitor. Falls back to
    // instances[0] if nothing matches (no monitor focused yet at
    // startup, or a screen genuinely isn't in this repeater for some
    // reason) rather than returning null and silently dropping the toggle.
    function focusedInstance(variants: var): var {
        const name = Hypr.focusedMonitor?.name;
        if (name) {
            for (let i = 0; i < variants.instances.length; i++) {
                const w = variants.instances[i];
                if (w.screen?.name === name)
                    return w;
            }
        }
        return variants.instances[0] ?? null;
    }

    // One shared ScreenState per screen — every window below is given the
    // SAME instance for its screen, so a toggle from one module (e.g. the
    // bar's power button setting screenState.session) is actually observed
    // by the window that owns that flag (e.g. SessionWindow's `visible:
    // screenState.session` binding). Each window previously created its own
    // independent ScreenState, which never synced with anyone else's.
    Variants {
        id: screenStates
        model: Quickshell.screens

        ScreenState {}
    }

    Variants {
        model: Quickshell.screens

        BackgroundWindow {
            screenState: root.screenStateFor(modelData)
        }
    }

    Variants {
        id: barWindows
        model: Quickshell.screens

        BarWindow {
            screenState: root.screenStateFor(modelData)
        }
    }

    Variants {
        id: dockWindows
        model: Quickshell.screens

        DockWindow {
            screenState: root.screenStateFor(modelData)
        }
    }

    Variants {
        id: dashboardWindows
        model: Quickshell.screens

        DashboardWindow {
            screenState: root.screenStateFor(modelData)
        }
    }

    Variants {
        id: settingsWindows
        model: Quickshell.screens

        SettingsWindow {
            screenState: root.screenStateFor(modelData)
        }
    }

    Variants {
        id: intelligenceWindows
        model: Quickshell.screens

        IntelligenceWindow {
            screenState: root.screenStateFor(modelData)
        }
    }

    Variants {
        id: notificationCenterWindows
        model: Quickshell.screens

        NotificationCenterWindow {
            screenState: root.screenStateFor(modelData)
        }
    }

    Variants {
        id: pkgInstallWindows
        model: Quickshell.screens

        PkgInstallWindow {
            screenState: root.screenStateFor(modelData)
        }
    }

    Variants {
        id: wallpaperPickerWindows
        model: Quickshell.screens

        WallpaperPickerWindow {
            screenState: root.screenStateFor(modelData)
        }
    }

    Variants {
        id: keybindsCheatsheetWindows
        model: Quickshell.screens

        KeybindsCheatsheetWindow {
            screenState: root.screenStateFor(modelData)
        }
    }

    // Backs both the per-target IpcHandlers below (kept as thin aliases
    // for back-compat -- `qs ipc call launcher toggle` etc. still work
    // unchanged) and the uniform `aphotic toggle(name)` dispatcher, so
    // every future toggle-shaped surface only needs one new map entry
    // instead of a whole new IpcHandler block. Deliberately does NOT
    // cover the eight verb-bearing targets (mpris, brightness, picker,
    // lock, hypr, audio, notifs, bar) -- those take real arguments or
    // dispatch more than one action, so collapsing them here would just
    // be forcing a shape that doesn't fit.
    readonly property var _toggleTargets: ({
        launcher: () => {
            const win = root.focusedInstance(launcherWindows);
            if (win)
                win.screenState.launcher = !win.screenState.launcher;
        },
        session: () => {
            const win = root.focusedInstance(sessionWindows);
            if (win)
                win.screenState.session = !win.screenState.session;
        },
        dashboard: () => {
            const win = root.focusedInstance(dashboardWindows);
            if (win)
                win.screenState.dashboard = !win.screenState.dashboard;
        },
        agent: () => {
            const win = root.focusedInstance(barWindows);
            if (win)
                win.screenState.agentPanel = !win.screenState.agentPanel;
        },
        settings: () => {
            const win = root.focusedInstance(settingsWindows);
            if (win)
                win.screenState.settings = !win.screenState.settings;
        },
        intelligence: () => {
            const win = root.focusedInstance(intelligenceWindows);
            if (win)
                win.screenState.intelligence = !win.screenState.intelligence;
        },
        dnd: () => DoNotDisturb.toggle(),
        notifications: () => {
            const win = root.focusedInstance(notificationCenterWindows);
            if (win)
                win.screenState.notificationCenter = !win.screenState.notificationCenter;
        },
        pkginstall: () => {
            if (!PkgSearch.available)
                return;
            const win = root.focusedInstance(pkgInstallWindows);
            if (win)
                win.screenState.pkgInstall = !win.screenState.pkgInstall;
        },
        colorpicker: () => colorPicker.toggle(),
        wallpaperpicker: () => {
            const win = root.focusedInstance(wallpaperPickerWindows);
            if (win)
                win.screenState.wallpaperPicker = !win.screenState.wallpaperPicker;
        },
        keybindscheatsheet: () => {
            const win = root.focusedInstance(keybindsCheatsheetWindows);
            if (win)
                win.screenState.keybindsCheatsheet = !win.screenState.keybindsCheatsheet;
        }
    })

    // Single entry point every future toggle-shaped surface can bind to
    // with zero new plumbing: `qs -c aphotic ipc call aphotic toggle
    // <name>`. Unknown names warn instead of throwing -- a typo'd name
    // (or a keybind referencing a surface from a branch that hasn't
    // landed yet) should be visible in the log, not a hard IPC error.
    IpcHandler {
        target: "aphotic"

        function toggle(name: string): void {
            const fn = root._toggleTargets[name];
            if (fn)
                fn();
            else
                console.warn(`aphotic toggle: unknown name '${name}'`);
        }
    }

    // Mounted only while the Resource Engine actually has a conflict to
    // ask about, so a base install with no opt-in profile carries no
    // negotiation surface at all rather than a hidden one per screen.
    // Unmount is held for one animation duration (same closeTimer shape as
    // PkgInstallWindow) so answering the prompt plays the card's fade-out
    // instead of the window vanishing under it.
    readonly property bool negotiationOpen: ResourceEngine.pending !== null
    property bool negotiationMounted: false

    onNegotiationOpenChanged: {
        if (root.negotiationOpen) {
            negotiationCloseTimer.stop();
            root.negotiationMounted = true;
        } else {
            negotiationCloseTimer.restart();
        }
    }

    Timer {
        id: negotiationCloseTimer
        interval: Tokens.anim.durations.normal
        onTriggered: root.negotiationMounted = false
    }

    LazyLoader {
        active: root.negotiationMounted

        NegotiationWindow {}
    }

    // Declares "gpu-vram" (vendor-routed off SystemUsage's existing
    // detection) and keeps the catch-all per-process claims for GPU
    // memory held by anything that isn't a domain plugin. Mounted here
    // rather than under services/ai because it is core resource
    // accounting, not an AI surface -- Ollama only ever claims against
    // the resource this declares.
    GpuVramSource {}

    // The profile substrate's inspection/drive surface (Phase 0 --
    // docs/APHOTIC_UNIFIED_VISION.md section 3.5). Lives here rather than
    // inside the singletons so declaring the IPC target doesn't
    // instantiate them: ProfileEngine, ProfileEvents and StateSnapshot
    // stay uncreated until a plugin (or one of these calls) first touches
    // them. Profile *registration* is deliberately not here -- a
    // descriptor carries hooks, which don't cross an IPC boundary.
    IpcHandler {
        target: "profile"

        function state(): string {
            return JSON.stringify({
                profiles: Object.keys(ProfileEngine.profiles),
                active: ProfileEngine.activeIds,
                phases: ProfileEngine.states,
                resources: ResourceEngine.resources,
                claims: ResourceEngine.claims,
                pending: ResourceEngine.pending,
                pendingCount: ResourceEngine.pendingCount,
                dormant: ResourceEngine.dormant,
                snapshots: StateSnapshot.capturedIds,
                lastRestore: StateSnapshot.lastRestore,
                subscribers: ProfileEvents.subscriberCount
            }, null, 2);
        }

        function declare(resource: string, spec: string): string {
            try {
                return ResourceEngine.declareResource(resource, JSON.parse(spec || "{}")) ? "ok" : "rejected";
            } catch (e) {
                return `bad spec: ${e}`;
            }
        }

        function claim(json: string): string {
            try {
                const negotiation = ResourceEngine.register(JSON.parse(json));
                return negotiation ? `negotiation ${negotiation.id}` : "ok";
            } catch (e) {
                return `bad claim: ${e}`;
            }
        }

        function release(id: string): string {
            ResourceEngine.release(id);
            return "ok";
        }

        function resolve(decision: string): string {
            if (!ResourceEngine.pending)
                return "nothing pending";
            return ResourceEngine.resolve(decision) ? "ok" : `expected one of ${ResourceEngine.decisions.join("/")}`;
        }

        function activate(id: string, trigger: string): string {
            return ProfileEngine.activate(id, trigger) ? ProfileEngine.phaseOf(id) : "refused";
        }

        function deactivate(id: string, reason: string): string {
            return ProfileEngine.deactivate(id, reason) ? ProfileEngine.phaseOf(id) : "refused";
        }

        function snapshot(id: string, parts: string): string {
            return JSON.stringify(StateSnapshot.capture(id, parts ? parts.split(",") : []), null, 2);
        }

        function restore(id: string): string {
            return StateSnapshot.restore(id) ? "started" : "no snapshot";
        }

        function reset(): string {
            ResourceEngine.reset();
            return "ok";
        }
    }

    Lock {}

    Variants {
        id: sessionWindows
        model: Quickshell.screens

        SessionWindow {
            screenState: root.screenStateFor(modelData)
        }
    }

    Variants {
        model: Quickshell.screens

        OsdWindow {}
    }

    Variants {
        model: Quickshell.screens

        NotificationsWindow {}
    }

    Variants {
        id: launcherWindows
        model: Quickshell.screens

        LauncherWindow {
            screenState: root.screenStateFor(modelData)
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root._toggleTargets.launcher();
        }

        function openWallpapers(): void {
            const win = root.focusedInstance(launcherWindows);
            if (!win)
                return;
            if (!win.screenState.launcher)
                win.screenState.launcherPrefill = "~";
            win.screenState.launcher = true;
        }
    }

    IpcHandler {
        target: "session"

        function toggle(): void {
            root._toggleTargets.session();
        }
    }

    IpcHandler {
        target: "dashboard"

        function toggle(): void {
            root._toggleTargets.dashboard();
        }
    }

    IpcHandler {
        target: "agent"

        function toggle(): void {
            root._toggleTargets.agent();
        }
    }

    IpcHandler {
        target: "settings"

        function toggle(): void {
            root._toggleTargets.settings();
        }
    }

    IpcHandler {
        target: "intelligence"

        function toggle(): void {
            root._toggleTargets.intelligence();
        }
    }

    IpcHandler {
        target: "dnd"

        function toggle(): void {
            root._toggleTargets.dnd();
        }
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            root._toggleTargets.notifications();
        }
    }

    IpcHandler {
        target: "pkginstall"

        function toggle(): void {
            root._toggleTargets.pkginstall();
        }
    }

    IpcHandler {
        target: "wallpaperpicker"

        function toggle(): void {
            root._toggleTargets.wallpaperpicker();
        }
    }

    AreaPicker {}

    ColorPicker {
        id: colorPicker
    }
}
