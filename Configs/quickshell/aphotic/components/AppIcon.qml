pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.config
import qs.services
import qs.utils

Item {
    id: root

    property string name: ""
    property var appClass: ""
    property string fallbackGlyph: "apps"
    // Pixel size for the image branch. Left at 0 the glyph metrics decide,
    // which is what the workspace pills want -- they sized to their text
    // before this component existed.
    property real size: 0
    property font fontStyle: Tokens.font.icon.small
    property int grade: Colours.light ? 0 : -25
    property color colour: Colours.palette.m3onSurface
    property bool animate: false
    property bool asynchronous: false

    readonly property var resolved: Icons.resolveAppIcon(root.name, root.appClass, root.fallbackGlyph)

    implicitWidth: loader.item?.implicitWidth ?? 0
    implicitHeight: loader.item?.implicitHeight ?? 0

    Loader {
        id: loader

        anchors.centerIn: parent
        sourceComponent: root.resolved.kind === "image" ? imageComp : glyphComp
    }

    Component {
        id: imageComp

        IconImage {
            source: root.resolved.value
            asynchronous: root.asynchronous
            implicitSize: root.size > 0 ? root.size : Math.round(root.fontStyle.pointSize * 1.35)
        }
    }

    Component {
        id: glyphComp

        MaterialIcon {
            text: root.resolved.value
            color: root.colour
            fontStyle: root.fontStyle
            grade: root.grade
            animate: root.animate
        }
    }
}
