pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components
import qs.modules.shelves

// A shelf tab shown in the notch rather than on a shelf edge. The notch
// has no edge, so `edge` reads "notch": a plugin that lays itself out
// against its host gets one honest answer, and the same content it would
// have drawn on a shelf draws here without a second implementation.
Item {
    id: root

    required property var tab
    required property string screen
    required property bool active

    ShelfTabView {
        anchors.fill: parent
        tab: root.tab
        output: root.screen
        edge: "notch"
        screen: root.screen
        active: root.active
    }
}