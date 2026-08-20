import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.bar
import qs.modules.launcher

ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens

        BarWindow {}
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
