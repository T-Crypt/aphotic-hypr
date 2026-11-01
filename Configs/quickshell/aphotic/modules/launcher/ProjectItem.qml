pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.services.ai
import qs.services.profile

Item {
    id: root

    required property var modelData
    required property ScreenState screenState

    width: ListView.view?.width ?? 0
    implicitHeight: Tokens.sizes.launcher.itemHeight

    function execute(): void {
        const harness = Harnesses.visible.find(h => h.launch.length > 0);
        // zsh -i so the launch command resolves on the user's interactive PATH.
        Quickshell.execDetached(harness
            ? ["kitty", "--directory", root.modelData.path, "zsh", "-ic", 'exec "$@"', "zsh", ...harness.launch]
            : ["kitty", "--directory", root.modelData.path]);
        // The editor is a full-profile app; minimal still gets the terminal.
        Quickshell.execDetached(["sh", "-c", 'command -v code >/dev/null && exec code "$1"', "sh", root.modelData.path]);
        // Fire-and-forget notification to any plugin declaring the
        // project-hook capability -- see cmd_plugin.sh's
        // run-project-hooks / _aphotic_plugin_run_hook_by_capability.
        // Plugins never replace the launch above, they just get told.
        Quickshell.execDetached(["aphotic", "plugin", "run-project-hooks", root.modelData.path]);
        DevProfile.projectOpened(root.modelData.path);
    }

    Interact {
        radius: Tokens.rounding.large
        onClicked: {
            root.execute();
            root.screenState.launcher = false;
        }
    }

    Row {
        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        MaterialIcon {
            id: icon

            anchors.verticalCenter: parent.verticalCenter
            text: root.modelData.icon === "code" ? "code" : "folder"
            fontStyle: Tokens.font.icon.large
            color: Colours.inkMuted
        }

        Column {
            anchors.verticalCenter: icon.verticalCenter
            width: parent.width - icon.width - parent.spacing

            StyledText {
                text: root.modelData.name
                font: Tokens.font.body.medium
                elide: Text.ElideRight
                width: parent.width
            }

            StyledText {
                text: root.modelData.path
                font: Tokens.font.body.small
                color: Colours.inkMuted
                elide: Text.ElideRight
                width: parent.width
            }
        }
    }
}
