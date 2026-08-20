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
import qs.modules.background

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
        model: Quickshell.screens

        BarWindow {
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
            const win = launcherWindows.instances[0];
            if (win)
                win.screenState.launcher = !win.screenState.launcher;
        }
    }

    IpcHandler {
        target: "session"

        function toggle(): void {
            const win = sessionWindows.instances[0];
            if (win)
                win.screenState.session = !win.screenState.session;
        }
    }

    IpcHandler {
        target: "dashboard"

        function toggle(): void {
            const win = dashboardWindows.instances[0];
            if (win)
                win.screenState.dashboard = !win.screenState.dashboard;
        }
    }
}
