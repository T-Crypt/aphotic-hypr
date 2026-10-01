pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components
import qs.services
import qs.modules.shelves

// The panel one shelf tab shows, in the shelf's own budget. The tab
// handles above it live in ShelfTabStrip; this is only the content, and
// it is destroyed with the shelf.
Item {
    id: root

    required property string output
    required property string edge
    required property string screen

    ShelfTabView {
        anchors.fill: parent
        tab: Shelves.tabFor(root.output,root.edge)
        output: root.output
        edge: root.edge
        screen: root.screen
        active: true
        acknowledge: true
    }
}