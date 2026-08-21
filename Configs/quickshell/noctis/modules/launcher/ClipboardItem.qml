pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property var modelData
    required property ScreenState screenState

    width: ListView.view?.width ?? 0
    implicitHeight: Tokens.sizes.launcher.itemHeight

    function execute(): void {
        // $1 is a positional shell parameter, not string-interpolated, so
        // raw cliphist lines can't break out of the command regardless of
        // what bytes they contain.
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "_", root.modelData.raw]);
    }

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: {
            root.execute();
            root.screenState.launcher = false;
        }
    }

    StyledText {
        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        verticalAlignment: Text.AlignVCenter
        text: root.modelData.preview
        font: Tokens.font.body.medium
        elide: Text.ElideRight
    }
}
