import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
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
import qs.services

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

        BackgroundWindow {}
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
            const win = root.focusedInstance(launcherWindows);
            if (win)
                win.screenState.launcher = !win.screenState.launcher;
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
            const win = root.focusedInstance(sessionWindows);
            if (win)
                win.screenState.session = !win.screenState.session;
        }
    }

    IpcHandler {
        target: "dashboard"

        function toggle(): void {
            const win = root.focusedInstance(dashboardWindows);
            if (win)
                win.screenState.dashboard = !win.screenState.dashboard;
        }
    }

    IpcHandler {
        target: "agent"

        function toggle(): void {
            const win = root.focusedInstance(barWindows);
            if (win)
                win.screenState.agentPanel = !win.screenState.agentPanel;
        }
    }

    IpcHandler {
        target: "settings"

        function toggle(): void {
            const win = root.focusedInstance(settingsWindows);
            if (win)
                win.screenState.settings = !win.screenState.settings;
        }
    }

    IpcHandler {
        target: "intelligence"

        function toggle(): void {
            const win = root.focusedInstance(intelligenceWindows);
            if (win)
                win.screenState.intelligence = !win.screenState.intelligence;
        }
    }

    IpcHandler {
        target: "dnd"

        function toggle(): void {
            DoNotDisturb.toggle();
        }
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            const win = root.focusedInstance(notificationCenterWindows);
            if (win)
                win.screenState.notificationCenter = !win.screenState.notificationCenter;
        }
    }

    IpcHandler {
        target: "pkginstall"

        function toggle(): void {
            if (!PkgSearch.available)
                return;
            const win = root.focusedInstance(pkgInstallWindows);
            if (win)
                win.screenState.pkgInstall = !win.screenState.pkgInstall;
        }
    }

    AreaPicker {}

    ColorPicker {}
}
