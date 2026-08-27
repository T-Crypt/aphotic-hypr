import QtQuick
import qs.config
import qs.components
import qs.services

MaterialIcon {
    id: root

    required property color colour

    readonly property bool active: NetworkUsage.downloadSpeed > 1024 || NetworkUsage.uploadSpeed > 1024

    animate: true
    text: "swap_vert"
    color: root.colour
    fill: root.active ? 1 : 0
}
