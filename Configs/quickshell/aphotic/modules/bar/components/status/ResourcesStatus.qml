import QtQuick
import qs.components
import qs.services

MaterialIcon {
    required property color colour

    SystemUsageWatch {
        detailed: false
    }

    readonly property real highLoad: Math.max(SystemUsage.cpuPerc, SystemUsage.memPerc)
    readonly property bool posture: ResourcePosture.surfaced && ResourcePosture.level !== "settling"

    animate: true
    text: "hub"
    color: posture ? Colours.posture(ResourcePosture.level, colour) : highLoad < 0.85 ? colour : Colours.palette.m3error
    fill: 1
}
