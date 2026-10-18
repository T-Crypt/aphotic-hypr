pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth
import qs.config
import qs.components
import qs.services
import qs.modules.dashboard

Item {
    id: root

    readonly property real margin: Tokens.padding.extraExtraLarge
    readonly property bool portrait: stage.height > stage.width

    // Inside the dashboard's own tab frame the surface draws no dark
    // gradient of its own; the frame and the window's dim layer already
    // carry that. Default false keeps the standalone probe's full
    // composition unchanged.
    property bool embedded: false

    property bool shown: true

    SystemUsageWatch {}
    NetworkUsageWatch {}

    readonly property bool mediaAlive: Players.active !== null
    readonly property bool focusAlive: Pomodoro.running
    readonly property bool weatherAlive: Weather.hasData
    readonly property bool controlsAlive: Nmcli.wifiEnabled || (Bluetooth.defaultAdapter?.enabled ?? false) || DoNotDisturb.enabled

    readonly property var leaves: [mediaLeaf, focusLeaf, weatherLeaf, controlsLeaf]
    readonly property var shownLeaves: leaves.filter(l => l.present)

    property alias terrain: terrain

    function rate(bytes: real): string {
        if (bytes >= 1024 * 1024)
            return qsTr("%1 MiB/s").arg((bytes / 1048576).toFixed(1));
        return qsTr("%1 KiB/s").arg(Math.round(bytes / 1024));
    }

    function gib(kib: real): string {
        return (kib / 1048576).toFixed(1);
    }

    component Leaf: Item {
        id: leaf

        required property string label
        required property bool alive
        property bool present: true
        default property alias content: body.data

        readonly property int slot: root.shownLeaves.indexOf(leaf)
        readonly property real slotWidth: root.portrait ? dayZone.width : dayZone.width / Math.max(1, root.shownLeaves.length)

        visible: leaf.present
        x: root.portrait ? 0 : leaf.slot * leaf.slotWidth
        y: root.portrait ? root.shownLeaves.slice(0, leaf.slot).reduce((sum, l) => sum + l.implicitHeight + Tokens.spacing.extraLarge, 0) : 0
        width: leaf.slotWidth
        implicitHeight: title.implicitHeight + Tokens.spacing.medium + body.childrenRect.height

        Rectangle {
            visible: root.portrait
            x: -Tokens.spacing.medium
            width: 2
            height: leaf.implicitHeight
            radius: Tokens.rounding.full
            color: Colours.signalStyle.accentLine
            opacity: leaf.alive ? 1 : 0
        }

        StyledText {
            id: title

            anchors.horizontalCenter: root.portrait ? undefined : parent.horizontalCenter
            text: leaf.label.toUpperCase()
            color: leaf.alive ? Colours.ink : Colours.inkMuted
            font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.6).build()
        }

        Item {
            id: body

            anchors.top: title.bottom
            anchors.topMargin: Tokens.spacing.medium
            x: root.portrait ? 0 : (leaf.width - body.childrenRect.width) / 2
            width: body.childrenRect.width
            height: body.childrenRect.height
        }
    }

    SurfaceReveal {
        id: reveal

        anchors.fill: parent
        shown: root.shown
        edge: "bottom"

        Item {
            id: stage

            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                visible: !root.embedded
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.alpha(Colours.shadow, 0.66)
                    }
                    GradientStop {
                        position: 0.62
                        color: Qt.alpha(Colours.shadow, 0.66)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Colours.shadow, 0.4)
                    }
                }
            }

            SignalText {
                id: clock

                x: root.margin
                y: root.margin
                text: {
                    Time.minuteStr;
                    return Time.format(Settings.twelveHourClock ? "h:mm AP" : "HH:mm");
                }
                family: Tokens.font.headline.large.family
                ink: Colours.ink
                glow: Colours.signalStyle.accentLine
                pixelSize: root.portrait ? 88 : Math.round(Math.max(72, Math.min(128, stage.height * 0.1)))
                weight: Font.DemiBold
                letterSpacing: 2
                property real progress: 0

                Component.onCompleted: {
                    if (Motion.reducedMotion)
                        clock.progress = 1;
                }

                Connections {
                    target: Time

                    function onMinuteStrChanged(): void {
                        if (!Motion.reducedMotion)
                            clock.progress = 0;
                    }
                }

                Timer {
                    id: shimmerClock

                    interval: 84
                    running: !Motion.reducedMotion && clock.progress < 1
                    repeat: true
                    onTriggered: {
                        clock.time = (clock.time + 0.25) % 3600;
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
                anchors.topMargin: Tokens.spacing.extraSmall
                text: Time.format("dddd, MMMM d")
                color: Colours.ink
                opacity: 0.72
                font: Tokens.font.title.builders.small.weight(Font.Medium).letterSpacing(0.6).build()
            }

            Grid {
                id: readouts

                columns: root.portrait ? 2 : 4
                columnSpacing: Tokens.spacing.extraLarge * 1.5
                rowSpacing: Tokens.spacing.large
                anchors.right: root.portrait ? undefined : parent.right
                anchors.rightMargin: root.margin
                anchors.left: root.portrait ? parent.left : undefined
                anchors.leftMargin: root.margin
                y: root.portrait ? dateLine.y + dateLine.height + Tokens.spacing.extraLarge : dateLine.y + dateLine.height - readouts.height

                component Readout: Column {
                    id: readout

                    required property string value
                    property string total: ""
                    required property string label

                    spacing: Tokens.spacing.extraSmall

                    Row {
                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            text: readout.value
                            color: Colours.ink
                            font: Tokens.font.title.builders.large.weight(Font.DemiBold).build()
                        }

                        StyledText {
                            anchors.baseline: parent.children[0].baseline
                            visible: readout.total.length > 0
                            text: readout.total
                            color: Colours.inkMuted
                            font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                        }
                    }

                    StyledText {
                        text: readout.label.toUpperCase()
                        color: Colours.inkMuted
                        font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.6).build()
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
                    value: root.gib(SystemUsage.memUsed)
                    total: qsTr("/ %1 GiB").arg(root.gib(SystemUsage.memTotal))
                    label: qsTr("Memory")
                }

                Readout {
                    value: root.rate(NetworkUsage.downloadSpeed)
                    label: qsTr("Network")
                }
            }

            PulseTerrain {
                id: terrain

                anchors.left: parent.left
                anchors.right: parent.right
                y: (root.portrait ? readouts.y + readouts.height : dateLine.y + dateLine.height) + Tokens.spacing.extraLarge * 1.5
                height: {
                    if (root.portrait)
                        return Math.max(110, Math.min(180, stage.height * 0.14));
                    const below = 3 + Tokens.spacing.extraExtraLarge + Math.max(dayZone.height, calendarLeaf.height) + root.margin * 2;
                    return Math.max(90, Math.min(300, stage.height - terrain.y - below));
                }
            }

            Item {
                id: spine

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: terrain.bottom
                height: 3

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 1
                    color: Colours.signalStyle.hairline
                }

                Repeater {
                    model: root.portrait ? [] : root.shownLeaves

                    Rectangle {
                        id: segment

                        required property Item modelData

                        x: dayZone.x + segment.modelData.x + segment.modelData.width / 2 - width / 2
                        y: 0
                        width: Tokens.spacing.extraLarge * 2
                        height: 2
                        radius: Tokens.rounding.full
                        color: Colours.signalStyle.accentLine
                        opacity: segment.modelData.alive ? 1 : 0
                        visible: segment.opacity > 0

                        Behavior on opacity {
                            Anim {
                                type: Anim.FastEffects
                            }
                        }
                    }
                }
            }

            Item {
                id: dayZone

                x: root.margin
                anchors.top: spine.bottom
                anchors.topMargin: Tokens.spacing.extraExtraLarge
                width: root.portrait ? stage.width * 0.48 - root.margin : calendarLeaf.x - root.margin - Tokens.spacing.extraExtraLarge
                height: childrenRect.height

                Leaf {
                    id: mediaLeaf

                    label: qsTr("Now playing")
                    alive: root.mediaAlive

                    DashMedia {}
                }

                Leaf {
                    id: focusLeaf

                    label: qsTr("Timer")
                    alive: root.focusAlive

                    DashPomodoro {}
                }

                Leaf {
                    id: weatherLeaf

                    label: qsTr("Weather")
                    alive: root.weatherAlive
                    present: Weather.hasData

                    DashWeather {}
                }

                Leaf {
                    id: controlsLeaf

                    label: qsTr("Controls")
                    alive: root.controlsAlive

                    DashQuickToggles {}
                }
            }

            Column {
                id: calendarLeaf

                anchors.right: parent.right
                anchors.rightMargin: root.margin
                anchors.top: spine.bottom
                anchors.topMargin: Tokens.spacing.extraExtraLarge
                spacing: Tokens.spacing.medium

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Calendar").toUpperCase()
                    color: Colours.ink
                    font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.6).build()
                }

                DashCalendar {}
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
