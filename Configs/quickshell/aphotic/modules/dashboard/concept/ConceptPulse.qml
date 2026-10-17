pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth
import qs.config
import qs.components
import qs.services
import qs.modules.dashboard

// Concept QJX858H: the dashboard as one signal spine.
//
// The machine lives above the line as terrain drawn from live service
// values. The day lives below it as leaves hanging off the spine, each
// one marked on the spine by a 2px accent segment when it has something
// alive in it. Darkness is the resting state: the terrain drains to the
// idle hairline and nothing moves when nothing changes.
//
// Prototype only. Not wired into the live dashboard; renders straight
// from the real services and mounts no sampler of its own.
Item {
    id: root

    readonly property real margin: Tokens.padding.extraExtraLarge
    readonly property bool portrait: stage.height > stage.width

    // Watch registrations live with this surface: closing the dashboard
    // unmounts them, the services stop polling, and the terrain goes
    // quiet with nothing left to draw.
    SystemUsageWatch {}
    NetworkUsageWatch {}

    readonly property bool mediaAlive: Players.active !== null
    readonly property bool focusAlive: Pomodoro.running
    readonly property bool weatherAlive: Weather.hasData
    readonly property bool controlsAlive: Nmcli.wifiEnabled
        || (Bluetooth.defaultAdapter?.enabled ?? false)
        || DoNotDisturb.enabled

    // The accent segment under a leaf marks it only while it is alive;
    // a resting leaf leaves its stretch of spine dark.
    readonly property var leaves: [mediaLeaf, focusLeaf, weatherLeaf, controlsLeaf]
    readonly property var leafAlive: [root.mediaAlive, root.focusAlive, root.weatherAlive, root.controlsAlive]

    // The probe seeds the terrain's trails; the live surface never does.
    property alias terrain: terrain

    SurfaceReveal {
        id: reveal

        anchors.fill: parent
        shown: true
        edge: "bottom"

        Item {
            id: stage

            anchors.fill: parent

            // The clock resolves out of noise through SignalText. The
            // low-rate shimmer clock belongs to this surface: it runs
            // only while the dashboard is open, and never under reduced
            // motion, where the text holds resolved and still.
            SignalText {
                id: clock

                x: root.margin
                y: root.margin
                text: Time.hourStr + ":" + Time.minuteStr
                ink: Colours.ink
                glow: Colours.signalStyle.accentLine
                pixelSize: root.portrait ? 96 : 132
                weight: Font.DemiBold
                letterSpacing: 8
                property real progress: 0

                Component.onCompleted: {
                    // Reduced motion never resolves from noise: the time
                    // is shown settled from the first frame.
                    if (Motion.reducedMotion)
                        clock.progress = 1;
                }

                Connections {
                    target: Time

                    // Every minute the clock re-resolves out of noise:
                    // one visible beat of light, then rest again.
                    function onMinuteStrChanged(): void {
                        clock.progress = 0;
                    }
                }

                Timer {
                    id: shimmerClock

                    interval: 84

                    running: !Motion.reducedMotion
                    repeat: true
                    onTriggered: {
                        clock.time = (clock.time + 0.25) % 3600;
                        if (clock.progress < 1)
                            clock.progress = Math.min(1, clock.progress + 0.08);
                    }
                }

                ActivityProbe {
                    name: "dashboard.concept.shimmer"
                    kind: "render"
                    timer: shimmerClock
                }
            }

            StyledText {
                id: dateLine

                anchors.left: parent.left
                anchors.leftMargin: root.margin
                anchors.top: clock.bottom
                anchors.topMargin: Tokens.spacing.small
                text: Time.format("dddd, MMMM d")
                color: Colours.inkMuted
                font: Tokens.font.label.builders.medium.weight(Font.Medium).letterSpacing(1.4).build()
            }

            PulseTerrain {
                id: terrain

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: dateLine.bottom
                anchors.topMargin: Tokens.spacing.extraLarge
                height: root.portrait
                    ? Math.max(120, Math.min(220, stage.height * 0.18))
                    : Math.max(140, Math.min(300, stage.height * 0.3))
            }

            Row {
                id: readouts

                anchors.right: parent.right
                anchors.rightMargin: root.margin
                anchors.top: terrain.top
                anchors.topMargin: Tokens.spacing.large
                spacing: Tokens.spacing.extraLarge

                component Readout: Column {
                    id: readout

                    required property string value
                    required property string label

                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        text: readout.value
                        color: Colours.ink
                        font: Tokens.font.title.builders.medium.weight(Font.DemiBold).build()
                    }

                    StyledText {
                        text: readout.label.toUpperCase()
                        color: Colours.inkMuted
                        font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
                    }
                }

                Readout {
                    value: `${Math.round(SystemUsage.cpuPerc * 100)}%`
                    label: qsTr("CPU")
                }

                Readout {
                    value: SystemUsage.gpuStatsAvailable ? `${Math.round(SystemUsage.gpuPerc * 100)}%` : qsTr("N/A")
                    label: qsTr("GPU")
                }

                Readout {
                    value: `${Math.round(SystemUsage.memPerc * 100)}%`
                    label: qsTr("Memory")
                }

                Readout {
                    value: `${Math.round(NetworkUsage.downloadSpeed / 1024)} KiB/s`
                    label: qsTr("Network")
                }
            }

            // The spine. A 1px idle hairline carrying one 2px accent
            // segment under every leaf that is alive. This is
            // SignalLine's active-segment vocabulary grown past the one
            // active segment the bar's line can express; if the concept
            // ships, the multi-segment form generalises back into
            // SignalLine rather than living here.
            Item {
                id: spine

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: terrain.bottom
                anchors.topMargin: Tokens.spacing.extraLarge
                height: 3

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 1
                    color: Colours.signalStyle.hairline
                }

                Repeater {
                    model: root.leaves

                    Rectangle {
                        id: segment

                        required property Item modelData
                        readonly property int index: root.leaves.indexOf(modelData)
                        readonly property bool alive: root.leafAlive[segment.index] ?? false
                        // Leaves sit under the spine in both orientations,
                        // so the segment tracks whichever container holds
                        // the leaf right now.
                        readonly property Item container: root.portrait ? dayColumn : dayRow

                        x: segment.container.x + modelData.x + modelData.width / 2 - width / 2
                        y: 1
                        width: Tokens.spacing.large
                        height: 2
                        radius: Tokens.rounding.full
                        color: Colours.signalStyle.accentLine
                        opacity: segment.alive ? 1 : 0
                        visible: segment.opacity > 0

                        Behavior on opacity {
                            Anim {
                                type: Anim.FastEffects
                            }
                        }
                    }
                }
            }

            // Landscape: the day's leaves spread across the full width
            // under the spine, so the row reads as one line of hanging
            // cards rather than a cluster in one corner.
            Row {
                id: dayRow

                x: root.margin
                anchors.top: spine.bottom
                anchors.topMargin: Tokens.spacing.extraExtraLarge
                visible: !root.portrait
                spacing: {
                    const used = root.leaves.reduce((sum, leaf) => sum + leaf.implicitWidth, 0);
                    const room = calendarLeaf.x - dayRow.x - used;
                    return Math.max(Tokens.spacing.extraLarge, room / (root.leaves.length + 1));
                }

                DashMedia {
                    id: mediaLeaf
                }

                DashPomodoro {
                    id: focusLeaf
                }

                DashWeather {
                    id: weatherLeaf

                    visible: Weather.hasData
                }

                DashQuickToggles {
                    id: controlsLeaf
                }
            }

            // Portrait: the same leaves stack in a column at the left
            // edge while the calendar keeps the right side.
            Column {
                id: dayColumn

                x: root.margin
                anchors.top: spine.bottom
                anchors.topMargin: Tokens.spacing.extraExtraLarge
                visible: root.portrait
                spacing: Tokens.spacing.extraLarge

                DashMedia {
                    id: mediaLeafP
                }

                DashPomodoro {
                    id: focusLeafP
                }

                DashWeather {
                    id: weatherLeafP

                    visible: Weather.hasData
                }

                DashQuickToggles {
                    id: controlsLeafP
                }
            }

            DashCalendar {
                id: calendarLeaf

                anchors.right: parent.right
                anchors.rightMargin: root.margin
                anchors.top: spine.bottom
                anchors.topMargin: Tokens.spacing.extraExtraLarge
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: root.margin
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.margin
                spacing: Tokens.spacing.small

                Repeater {
                    model: CommandCenterTabs.list

                    Rectangle {
                        id: tabDot

                        required property var modelData

                        readonly property bool active: modelData.id === "dashboard"

                        anchors.verticalCenter: parent.verticalCenter
                        width: active ? Tokens.spacing.large : Tokens.spacing.extraSmall
                        height: Tokens.spacing.extraSmall
                        radius: Tokens.rounding.full
                        color: active ? Colours.signalStyle.accentLine : Colours.signalStyle.hairline
                    }
                }
            }
        }
    }
}
