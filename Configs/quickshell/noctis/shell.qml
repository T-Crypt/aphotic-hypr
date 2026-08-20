import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.bar
import qs.modules.launcher
import qs.modules.notifications
import qs.modules.osd
import qs.modules.lock
import qs.modules.session
import qs.modules.dashboard

ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens

        BarWindow {}
    }

    Variants {
        id: dashboardWindows
        model: Quickshell.screens

        DashboardWindow {}
    }

    Lock {}

    Variants {
        id: sessionWindows
        model: Quickshell.screens

        SessionWindow {}
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

        LauncherWindow {}
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
