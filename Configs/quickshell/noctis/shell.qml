import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.bar
import qs.modules.launcher
import qs.modules.notifications
import qs.modules.osd
import qs.modules.lock

ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens

        BarWindow {}
    }

    Lock {}

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
}
