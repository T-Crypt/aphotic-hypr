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
    // summarize(), not build(): the popout shows planes and two counts,
    // so it has no reason to lay out the map's nodes and edges.
    readonly property var flow: Model.summarize(ResourceEngine.claims, ResourceEngine.resources, ProfileEngine.states, ProfileEngine.profiles, ({
        ai: InstallProfile.aiEnabled,
        gaming: InstallProfile.gamingEnabled,
        security: InstallProfile.securityEnabled,
        dev: InstallProfile.devEnabled
    }), WorkloadPassports.live, ActionReceipts.all)
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
                    color: plane.modelData.phase === "negotiate" ? "#f4bd72" : plane.modelData.active ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
                }
                StyledText {
                    text: plane.modelData.label
                    font: Tokens.font.label.medium
                    opacity: plane.modelData.installed ? 1 : 0.45
                }
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        text: root.flow.pendingActions
            ? qsTr("%1 claims · %2 contended · %3 action pending · SUPER+D → Flow").arg(root.flow.claimCount).arg(root.flow.contentionCount).arg(root.flow.pendingActions)
            : root.flow.staleCount
                ? qsTr("%1 claims · %2 contended · %3 stale · SUPER+D → Flow").arg(root.flow.claimCount).arg(root.flow.contentionCount).arg(root.flow.staleCount)
                : qsTr("%1 claims · %2 contended · SUPER+D → Flow").arg(root.flow.claimCount).arg(root.flow.contentionCount)
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
        wrapMode: Text.WordWrap
    }
}
