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
            active: !Shelves.blocked && (Shelves.isOpen(modelData.name,"left") || Shelves.isOpen(modelData.name,"right") || (item?.revealing ?? false))
            sourceComponent: ShelfWindow { modelData: host.modelData }
        }
    }
}
