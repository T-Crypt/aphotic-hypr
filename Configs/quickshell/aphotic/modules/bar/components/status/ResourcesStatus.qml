import QtQuick
import qs.components
import qs.services
import qs.services.profile

MaterialIcon {
    required property color colour

    readonly property real highLoad: Math.max(SystemUsage.cpuPerc, SystemUsage.memPerc)

    animate: true
    text: "hub"
    color: ResourceEngine.pendingCount > 0 ? "#f4bd72" : highLoad < 0.85 ? colour : Colours.palette.m3error
    fill: 1
}
