pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.components
import qs.config
import qs.services
import qs.modules.bar
Item {
    id: root
    required property string output
    required property string edge
    readonly property var config: Shelves.config(output)[edge]
    readonly property var items: WindowList.dockItems(config.pinned,output,config.allOutputs)
    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer
    }
    MouseArea { objectName: "shelf-interior"; anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    Flickable {
        id: scroll
        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        clip: true
        contentWidth: width
        contentHeight: column.height
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: column
            width: scroll.width
            spacing: Tokens.spacing.small
            Repeater {
                model: root.items
                DockAppIcon {
                    id: icon
                    required property var modelData
                    item: modelData
                    width: scroll.width
                    height: Settings.barInnerWidth
                    animateScale: RenderGate.decorative
                    magnifyScale: root.config.magnify && RenderGate.decorative && hover.hovered
                        ? 1 + 0.15 * Math.pow(Math.max(0,1 - Math.abs(icon.y + icon.height/2 - hover.point.position.y)/90),2) : 1
                    property QtObject _sonarTarget: Loader {
                        active: Settings.sonarEnabled
                        sourceComponent: EchoTarget {
                            target: icon
                            targetId: "core:shelf/" + root.edge + "/" + icon.item.key
                            label: icon.item.name
                        }
                    }
                }
            }
        }
        HoverHandler { id: hover; enabled: root.config.magnify && RenderGate.decorative }
    }
}
