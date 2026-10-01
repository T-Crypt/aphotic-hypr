pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services
Scope {
    id: root
    readonly property var instances: hosts.instances
    readonly property int mountedCount: Array.from(hosts.instances).filter(h => h.item !== null).length
    Variants {
        id: hosts
        model: Quickshell.screens
        delegate: Loader {
            id: host
            required property var modelData
            // Mounted while an edge is open, while one is finishing its
            // close, or while an edge the user gave a visible handle to
            // still has one to show. Nothing else keeps a window alive.
            active: !Shelves.blocked && (Shelves.isOpen(modelData.name,"left")
                || Shelves.isOpen(modelData.name,"right")
                || (item?.revealing ?? false)
                || Shelves.handleActive(modelData.name))
            sourceComponent: ShelfWindow { modelData: host.modelData }
        }
    }
}