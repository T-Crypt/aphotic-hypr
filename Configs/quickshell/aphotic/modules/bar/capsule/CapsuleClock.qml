pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState

    readonly property var fontStyle: Tokens.font.body.builders.small.scale(1.1).build()
    readonly property string timeText: Settings.twelveHourClock ? `${Time.hourStr}:${Time.minuteStr} ${Time.amPmStr.toLowerCase()}` : `${Time.hourStr}:${Time.minuteStr}`
    readonly property string dateText: Time.format("ddd d MMM")

    // Horizontal is sized to whichever label is wider, so the hover swap
    // never reflows the pill around it. Vertical is pinned to the strip's
    // thickness -- laying the wide horizontal form out in a side-docked
    // strip pushed the text clean off the pill and off the screen, and out
    // of the window's input mask with it.
    implicitWidth: Settings.barHorizontal ? Math.max(timeMetrics.width, dateMetrics.width) + Tokens.padding.medium * 2 : Settings.barInnerWidth
    implicitHeight: Settings.barHorizontal ? Math.round(Settings.barInnerWidth * 0.72) : (stacked.item?.implicitHeight ?? 0) + Tokens.padding.small * 2

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

    // Time slides up and out while the date slides in behind it. There is
    // no room for that trade in a one-icon-wide strip, so the vertical form
    // below just stacks the digits instead.
    Loader {
        anchors.fill: parent
        active: Settings.barHorizontal

        sourceComponent: Item {
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                y: (parent.height - height) / 2 + (hover.hovered ? -9 : 0)
                text: root.timeText
                color: Colours.palette.m3onSurface
                font: root.fontStyle
                opacity: hover.hovered ? 0 : 1

                Behavior on y {
                    enabled: Settings.capsuleAnimations
                    Anim {
                        type: Anim.FastSpatial
                    }
                }
                Behavior on opacity {
                    enabled: Settings.capsuleAnimations
                    Anim {
                        type: Anim.FastEffects
                    }
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
                    Anim {
                        type: Anim.FastSpatial
                    }
                }
                Behavior on opacity {
                    enabled: Settings.capsuleAnimations
                    Anim {
                        type: Anim.FastEffects
                    }
                }
            }
        }
    }

    Loader {
        id: stacked

        anchors.centerIn: parent
        active: !Settings.barHorizontal

        sourceComponent: ColumnLayout {
            spacing: -2

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Time.hourStr
                color: Colours.palette.m3onSurface
                font: root.fontStyle
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Time.minuteStr
                color: Colours.palette.m3onSurfaceVariant
                font: root.fontStyle
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: Settings.twelveHourClock
                text: Time.amPmStr.toLowerCase()
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.builders.small.scale(0.9).build()
            }
        }
    }
}
