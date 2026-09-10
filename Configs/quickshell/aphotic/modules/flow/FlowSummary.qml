pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services
import qs.services.profile
import "FlowModel.js" as Model

ColumnLayout {
    id: root
    readonly property var flow: Model.build(ResourceEngine.claims, ResourceEngine.resources, ProfileEngine.states, ProfileEngine.profiles)
    spacing: 8
    StyledText {
        text: qsTr("Aphotic Flow")
        color: Colours.palette.m3primary
        font: Tokens.font.title.medium
    }
    RowLayout {
        Layout.fillWidth: true
        Repeater {
            model: root.flow.planes
            ColumnLayout {
                id: plane
                required property var modelData
                Layout.fillWidth: true
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 3
                    radius: 2
                    color: plane.modelData.phase === "negotiate" ? "#f4bd72" : plane.modelData.phase === "monitor" || plane.modelData.phase === "claims active" ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
                }
                StyledText { text: plane.modelData.label; font: Tokens.font.label.medium }
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        text: qsTr("%1 claims · %2 contended · SUPER+D → Flow").arg(root.flow.claimCount).arg(root.flow.contentionCount)
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
        wrapMode: Text.WordWrap
    }
}
