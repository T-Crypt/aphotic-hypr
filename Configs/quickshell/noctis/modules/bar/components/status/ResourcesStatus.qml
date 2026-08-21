import QtQuick
import qs.components
import qs.services

MaterialIcon {
    required property color colour

    readonly property real highLoad: Math.max(SystemUsage.cpuPerc, SystemUsage.memPerc)

    animate: true
    text: "memory"
    color: highLoad < 0.85 ? colour : Colours.palette.m3error
    fill: 1
}
