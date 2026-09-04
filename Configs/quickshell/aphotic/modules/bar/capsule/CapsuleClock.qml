pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState

    readonly property var fontStyle: Tokens.font.body.builders.small.scale(1.1).build()
    readonly property string timeText: Settings.twelveHourClock ? `${Time.hourStr}:${Time.minuteStr} ${Time.amPmStr.toLowerCase()}` : `${Time.hourStr}:${Time.minuteStr}`
    readonly property string dateText: Time.format("ddd d MMM")

    // Sized to whichever label is wider so the hover swap never reflows
    // the capsule around it.
    implicitWidth: Math.max(timeMetrics.width, dateMetrics.width) + Tokens.padding.medium * 2
    implicitHeight: Math.round(Settings.barInnerWidth * 0.72)

    TextMetrics {
        id: timeMetrics
        font: root.fontStyle
        text: root.timeText
    }

    TextMetrics {
        id: dateMetrics
        font: root.fontStyle
        text: root.dateText
    }

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.full
        color: "transparent"

        StateLayer {
            radius: parent.radius
            onClicked: root.screenState.dashboard = !root.screenState.dashboard
        }
    }

    HoverHandler {
        id: hover
    }

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        y: (parent.height - height) / 2 + (hover.hovered ? -9 : 0)
        text: root.timeText
        color: Colours.palette.m3onSurface
        font: root.fontStyle
        opacity: hover.hovered ? 0 : 1

        Behavior on y {
            enabled: Settings.capsuleAnimations
            Anim { type: Anim.FastSpatial }
        }
        Behavior on opacity {
            enabled: Settings.capsuleAnimations
            Anim { type: Anim.FastEffects }
        }
    }

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        y: (parent.height - height) / 2 + (hover.hovered ? 0 : 9)
        text: root.dateText
        color: Colours.palette.m3primaryOnSurface
        font: root.fontStyle
        opacity: hover.hovered ? 1 : 0
        visible: opacity > 0

        Behavior on y {
            enabled: Settings.capsuleAnimations
            Anim { type: Anim.FastSpatial }
        }
        Behavior on opacity {
            enabled: Settings.capsuleAnimations
            Anim { type: Anim.FastEffects }
        }
    }
}
