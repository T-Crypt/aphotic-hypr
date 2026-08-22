// DesktopClock.qml
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property Item wallpaper
    required property real absX
    required property real absY

    property real clockScale: Config.background.desktopClock.scale
    readonly property bool bgEnabled: Config.background.desktopClock.background.enabled
    readonly property bool blurEnabled: bgEnabled && Config.background.desktopClock.background.blur
    readonly property bool invertColors: Config.background.desktopClock.invertColors
    readonly property bool useLightSet: Colours.light ? !invertColors : invertColors
    readonly property color safePrimary: useLightSet ? Colours.palette.m3onPrimary : Colours.palette.m3primary
    readonly property color safeSecondary: useLightSet ? Colours.palette.m3onSurface : Colours.palette.m3secondary
    readonly property color safeTertiary: useLightSet ? Colours.palette.m3onTertiary : Colours.palette.m3tertiary

    implicitWidth: layout.implicitWidth + (Tokens.padding.large * 4 * root.clockScale)
    implicitHeight: layout.implicitHeight + (Tokens.padding.large * 2 * root.clockScale)

    Item {
        id: clockContainer

        anchors.fill: parent

        layer.enabled: Config.background.desktopClock.shadow.enabled
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: Config.background.desktopClock.shadow.opacity
            shadowBlur: Config.background.desktopClock.shadow.blur
        }

        Loader {
            asynchronous: true
            anchors.fill: parent
            active: root.blurEnabled

            sourceComponent: MultiEffect {
                source: ShaderEffectSource {
                    sourceItem: root.wallpaper
                    sourceRect: Qt.rect(root.absX, root.absY, root.width, root.height)
                }
                maskSource: backgroundPlate
                maskEnabled: true
                blurEnabled: true
                blur: 1
                blurMax: 64
                autoPaddingEnabled: false
            }
        }

        StyledRect {
            id: backgroundPlate

            visible: root.bgEnabled
            anchors.fill: parent
            radius: Tokens.rounding.large * root.clockScale
            opacity: Config.background.desktopClock.background.opacity
            color: Colours.palette.m3surfaceContainer

            layer.enabled: root.blurEnabled
        }

        RowLayout {
            id: layout

            anchors.centerIn: parent
            spacing: Tokens.spacing.large * root.clockScale

            RowLayout {
                spacing: Tokens.spacing.small

                StyledText {
                    text: Time.hourStr
                    font.pointSize: Tokens.fontSize.extraLarge * 3 * root.clockScale
                    font.weight: Font.Bold
                    color: root.safePrimary
                }

                StyledText {
                    text: ":"
                    font.pointSize: Tokens.fontSize.extraLarge * 3 * root.clockScale
                    color: root.safeTertiary
                    opacity: 0.8
                    Layout.topMargin: -Tokens.padding.large * 1.5 * root.clockScale
                }

                StyledText {
                    text: Time.minuteStr
                    font.pointSize: Tokens.fontSize.extraLarge * 3 * root.clockScale
                    font.weight: Font.Bold
                    color: root.safeSecondary
                }

                Loader {
                    asynchronous: true
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: Tokens.padding.large * 1.4 * root.clockScale

                    active: GlobalConfig.services.useTwelveHourClock
                    visible: active

                    sourceComponent: StyledText {
                        text: Time.amPmStr
                        font.pointSize: Tokens.fontSize.large * root.clockScale
                        color: root.safeSecondary
                    }
                }
            }

            StyledRect {
                Layout.fillHeight: true
                Layout.preferredWidth: 4 * root.clockScale
                Layout.topMargin: Tokens.spacing.large * root.clockScale
                Layout.bottomMargin: Tokens.spacing.large * root.clockScale
                radius: Tokens.rounding.full
                color: root.safePrimary
                opacity: 0.8
            }

            ColumnLayout {
                spacing: 0

                StyledText {
                    text: Time.format("MMMM").toUpperCase()
                    font.pointSize: Tokens.fontSize.large * root.clockScale
                    font.letterSpacing: 4
                    font.weight: Font.Bold
                    color: root.safeSecondary
                }

                StyledText {
                    text: Time.format("dd")
                    font.pointSize: Tokens.fontSize.extraLarge * root.clockScale
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                    color: root.safePrimary
                }

                StyledText {
                    text: Time.format("dddd")
                    font.pointSize: Tokens.fontSize.larger * root.clockScale
                    font.letterSpacing: 2
                    color: root.safeSecondary
                }
            }
        }
    }

    Behavior on clockScale {
        Anim {
            duration: Tokens.anim.durations.expressiveDefaultSpatial
        }
    }

    Behavior on implicitWidth {
        Anim {
            duration: Tokens.anim.durations.small
        }
    }
}
