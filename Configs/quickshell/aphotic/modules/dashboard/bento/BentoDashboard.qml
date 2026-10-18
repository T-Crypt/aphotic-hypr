pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import qs.config
import qs.components
import qs.services
import qs.services.ai
import qs.services.profile
import ".."

// The Dashboard tab: a grid of live tiles that fills the stage edge to
// edge. Twelve columns by six rows; every tile spans whole cells, so the
// grid stays even at any size. Each tile carries one moving part (a curve,
// a ring, a dot) that moves only when its value does.
Item {
    id: root

    readonly property real gap: Tokens.spacing.large
    readonly property real cellW: (root.width - root.gap * 11) / 12
    readonly property real cellH: (root.height - root.gap * 5) / 6

    // Tiles are placed by cell, not by a layout, so a tile's size never
    // depends on what is inside it.
    component Cell: SignalTile {
        property int col: 0
        property int row: 0
        property int cols: 1
        property int rows: 1

        x: col * (root.cellW + root.gap)
        y: row * (root.cellH + root.gap)
        width: cols * root.cellW + (cols - 1) * root.gap
        height: rows * root.cellH + (rows - 1) * root.gap
    }

    SystemUsageWatch {
        detailed: true
    }

    NetworkUsageWatch {}

    Component.onCompleted: AgentEvents.hold("dashboard-bento", true)
    Component.onDestruction: AgentEvents.hold("dashboard-bento", false)

    property var cpuTrail: []
    property var downTrail: []
    property var upTrail: []

    function push(list: var, value: real): var {
        const next = list.concat([value]);
        return next.length > 40 ? next.slice(next.length - 40) : next;
    }

    Connections {
        target: SystemUsage

        function onCpuPercChanged(): void {
            root.cpuTrail = root.push(root.cpuTrail, SystemUsage.cpuPerc);
        }
    }

    Connections {
        target: NetworkUsage

        function onDownloadSpeedChanged(): void {
            root.downTrail = root.push(root.downTrail, NetworkUsage.downloadSpeed);
            root.upTrail = root.push(root.upTrail, NetworkUsage.uploadSpeed);
        }
    }

    function rate(bytes: real): string {
        const f = NetworkUsage.formatBytes(bytes);
        return `${f.value < 10 ? f.value.toFixed(1) : Math.round(f.value)} ${f.unit}`;
    }

    function gib(kib: real): string {
        return (kib / 1048576).toFixed(1);
    }

    // ── Row 1-2 ─────────────────────────────────────────────────────────

    Cell {
        col: 0
        row: 0
        cols: 4
        rows: 2
        icon: "schedule"
        label: Time.format("dddd")
        accent: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Item {
                Layout.fillHeight: true
            }

            Text {
                text: {
                    Time.minuteStr;
                    return Time.format(Settings.twelveHourClock ? "h:mm" : "HH:mm");
                }
                color: Colours.ink
                font.family: Tokens.font.headline.large.family
                font.pixelSize: Math.min(parent.height * 0.62, parent.width * 0.3)
                font.weight: Font.DemiBold
                font.letterSpacing: -2
            }

            RowLayout {
                spacing: Tokens.spacing.small

                Rectangle {
                    implicitWidth: 28
                    implicitHeight: 3
                    radius: 1.5
                    color: Colours.signal
                }

                StyledText {
                    text: Time.format("MMMM d, yyyy")
                    color: Colours.inkMuted
                    font: Tokens.font.title.small
                }

                StyledText {
                    visible: Settings.twelveHourClock
                    text: Time.amPmStr
                    color: Colours.signal
                    font: Tokens.font.title.small
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }

    Cell {
        col: 4
        row: 0
        cols: 4
        rows: 2
        icon: "memory"
        label: qsTr("Processor")
        figure: SystemUsage.cpuTemp > 0 ? `${Math.round(SystemUsage.cpuTemp)}°C` : ""
        live: SystemUsage.cpuPerc > 0.5

        StyledText {
            id: cpuFigure

            text: `${Math.round(SystemUsage.cpuPerc * 100)}%`
            color: Colours.ink
            font.family: Tokens.font.headline.large.family
            font.pixelSize: Math.max(24, parent.height * 0.26)
            font.weight: Font.Light
        }

        StyledText {
            anchors.left: cpuFigure.right
            anchors.leftMargin: Tokens.spacing.small
            anchors.baseline: cpuFigure.baseline
            text: SystemUsage.cpuName
            color: Colours.inkMuted
            elide: Text.ElideRight
            width: parent.width - cpuFigure.width - Tokens.spacing.small
            font: Tokens.font.label.small
        }

        Spline {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height - cpuFigure.height - Tokens.spacing.small
            values: root.cpuTrail
            peak: 1
        }
    }

    Cell {
        id: media

        readonly property MprisPlayer player: Players.active

        col: 8
        row: 0
        cols: 4
        rows: 2
        icon: "music_note"
        label: media.player?.identity ?? qsTr("Media")
        live: media.player?.isPlaying ?? false

        RowLayout {
            anchors.fill: parent
            spacing: Tokens.spacing.large

            StyledClippingRect {
                Layout.preferredWidth: Math.min(parent.height, parent.width * 0.42)
                Layout.preferredHeight: Layout.preferredWidth
                radius: Tokens.rounding.medium
                color: Colours.signalStyle.raised

                Image {
                    id: art

                    anchors.fill: parent
                    source: media.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 384
                    sourceSize.height: 384
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    text: "album"
                    color: Colours.inkMuted
                    font.pixelSize: parent.width * 0.4
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 2

                Item {
                    Layout.fillHeight: true
                }

                StyledText {
                    Layout.fillWidth: true
                    text: media.player?.trackTitle || qsTr("Nothing playing")
                    color: Colours.ink
                    elide: Text.ElideRight
                    font: Tokens.font.title.builders.medium.weight(Font.Medium).build()
                }

                StyledText {
                    Layout.fillWidth: true
                    text: media.player?.trackArtist ?? ""
                    color: Colours.inkMuted
                    elide: Text.ElideRight
                    font: Tokens.font.body.small
                }

                RowLayout {
                    Layout.topMargin: Tokens.spacing.medium
                    spacing: Tokens.spacing.medium

                    Repeater {
                        model: [
                            { icon: "skip_previous", act: () => media.player?.previous(), main: false },
                            { icon: media.player?.isPlaying ? "pause" : "play_arrow", act: () => media.player?.togglePlaying(), main: true },
                            { icon: "skip_next", act: () => media.player?.next(), main: false }
                        ]

                        StyledRect {
                            id: control

                            required property var modelData

                            implicitWidth: control.modelData.main ? 44 : 34
                            implicitHeight: implicitWidth
                            radius: Tokens.rounding.full
                            color: control.modelData.main ? Qt.alpha(Colours.signal, 0.18) : "transparent"
                            border.width: 1
                            border.color: control.modelData.main ? Colours.signal : Colours.signalStyle.hairline
                            opacity: media.player ? 1 : 0.4

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: control.modelData.icon
                                color: control.modelData.main ? Colours.signal : Colours.ink
                                fontStyle: control.modelData.main ? Tokens.font.icon.large : Tokens.font.icon.medium
                            }

                            Interact {
                                anchors.fill: parent
                                radius: parent.radius
                                onClicked: control.modelData.act()
                            }
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }

    // ── Row 3-4 ─────────────────────────────────────────────────────────

    Cell {
        col: 0
        row: 2
        cols: 2
        rows: 2
        icon: "memory_alt"
        label: qsTr("Memory")

        Ring {
            anchors.fill: parent
            value: SystemUsage.memPerc
            figure: `${Math.round(SystemUsage.memPerc * 100)}%`
            caption: SystemUsage.memTotal > 0 ? `${root.gib(SystemUsage.memUsed)} / ${Math.round(SystemUsage.memTotal / 1048576)} GiB` : ""
        }
    }

    Cell {
        col: 2
        row: 2
        cols: 2
        rows: 2
        icon: "developer_board"
        label: qsTr("Graphics")
        figure: SystemUsage.gpuTemp > 0 ? `${Math.round(SystemUsage.gpuTemp)}°C` : ""

        Ring {
            anchors.fill: parent
            value: SystemUsage.gpuStatsAvailable ? SystemUsage.gpuPerc : 0
            figure: SystemUsage.gpuStatsAvailable ? `${Math.round(SystemUsage.gpuPerc * 100)}%` : "--"
            caption: SystemUsage.gpuDetected ? "" : qsTr("none found")
            colour: Colours.signalTertiary
        }
    }

    Cell {
        col: 4
        row: 2
        cols: 4
        rows: 2
        icon: "network_check"
        label: qsTr("Network")
        live: NetworkUsage.downloadSpeed > 512 * 1024

        RowLayout {
            id: netFigures

            spacing: Tokens.spacing.extraLarge

            Repeater {
                model: [
                    { icon: "south", value: NetworkUsage.downloadSpeed, colour: Colours.signal },
                    { icon: "north", value: NetworkUsage.uploadSpeed, colour: Colours.signalSecondary }
                ]

                RowLayout {
                    id: netFigure

                    required property var modelData

                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        text: netFigure.modelData.icon
                        color: netFigure.modelData.colour
                        fontStyle: Tokens.font.icon.medium
                    }

                    StyledText {
                        text: root.rate(netFigure.modelData.value)
                        color: Colours.ink
                        font: Tokens.font.title.builders.medium.weight(Font.Light).build()
                    }
                }
            }
        }

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height - netFigures.height - Tokens.spacing.small

            Spline {
                anchors.fill: parent
                values: root.downTrail
                peak: 0
            }

            Spline {
                anchors.fill: parent
                values: root.upTrail
                peak: Math.max(1, root.downTrail.reduce((m, v) => Math.max(m, v), 0))
                colour: Colours.signalSecondary
                fill: false
                lineWidth: 1.5
            }
        }
    }

    Cell {
        id: agents

        readonly property var sessions: AgentEvents.liveSessions.slice().sort((a, b) => (a.startedAt - b.startedAt) || (a.id < b.id ? -1 : 1))

        col: 8
        row: 2
        cols: 4
        rows: 2
        icon: "smart_toy"
        label: qsTr("Agents")
        figure: agents.sessions.length > 0 ? String(agents.sessions.length) : ""
        live: AgentEvents.anyRunning
        accent: AgentEvents.anyWaiting

        StyledText {
            anchors.centerIn: parent
            visible: agents.sessions.length === 0
            text: qsTr("No agent running")
            color: Colours.inkMuted
            font: Tokens.font.body.small
        }

        Column {
            anchors.fill: parent
            spacing: Tokens.spacing.small

            Repeater {
                model: agents.sessions.slice(0, Math.max(1, Math.floor(agents.height / 44)))

                StyledRect {
                    id: session

                    required property var modelData
                    readonly property bool waiting: session.modelData.status === "waiting"
                    readonly property bool busy: session.modelData.status === "running" || session.modelData.status === "compacting"

                    width: parent.width
                    height: 32
                    radius: Tokens.rounding.full
                    color: session.waiting ? Qt.alpha(Colours.signal, 0.16) : Qt.alpha(Colours.signalStyle.base, 0.5)
                    border.width: 1
                    border.color: session.waiting ? Colours.signal : Colours.signalStyle.hairline

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.small

                        Rectangle {
                            implicitWidth: 7
                            implicitHeight: 7
                            radius: 3.5
                            color: session.waiting ? Colours.signal : session.busy ? Colours.signalOnSurface : Colours.outline
                        }

                        StyledText {
                            text: AgentRoles.entries.find(e => e.id === session.modelData.harness)?.label ?? session.modelData.harness
                            color: Colours.ink
                            font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: (session.modelData.cwd || "").split("/").pop() || session.modelData.tool || ""
                            color: Colours.inkMuted
                            elide: Text.ElideRight
                            font: Tokens.font.label.small
                        }

                        StyledText {
                            text: session.waiting ? qsTr("waiting") : (session.modelData.tool || session.modelData.status)
                            color: session.waiting ? Colours.signal : Colours.inkMuted
                            font: Tokens.font.mono.small
                        }
                    }

                    Interact {
                        anchors.fill: parent
                        radius: parent.radius
                        onClicked: AgentWindowFocus.focusByCwd(session.modelData.cwd ?? "")
                    }
                }
            }
        }
    }

    // ── Row 5-6 ─────────────────────────────────────────────────────────

    Cell {
        col: 0
        row: 4
        cols: 4
        rows: 2
        icon: "calendar_month"
        label: qsTr("Calendar")
        padding: Tokens.padding.medium

        DashCalendar {
            anchors.centerIn: parent
            scale: Math.min(1.25, parent.width / Math.max(1, implicitWidth), parent.height / Math.max(1, implicitHeight))
        }
    }

    Cell {
        col: 4
        row: 4
        cols: 2
        rows: 2
        icon: Weather.hasData ? Weather.conditionIcon : "cloud_off"
        label: qsTr("Weather")

        Column {
            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Weather.hasData ? Weather.conditionIcon : "cloud_off"
                color: Colours.signal
                font.pixelSize: Math.min(64, root.cellH * 0.5)
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Weather.hasData ? `${Math.round(Weather.currentTemp)}°` : "--"
                color: Colours.ink
                font.family: Tokens.font.headline.large.family
                font.pixelSize: Math.min(48, root.cellH * 0.4)
                font.weight: Font.Light
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Weather.hasData ? Weather.conditionText : qsTr("No location set")
                color: Colours.inkMuted
                font: Tokens.font.label.small
            }
        }
    }

    Cell {
        id: ai

        readonly property var engines: {
            const rows = [];
            const seen = {};
            for (const e of EngineRegistry.liveEngines) {
                if (!seen[e.id]) {
                    seen[e.id] = true;
                    rows.push({ id: e.id, label: e.label || e.id, models: (e.models ?? []).map(m => m.name) });
                }
            }
            const backends = LocalInference.backends;
            for (const owner of Object.keys(backends)) {
                const models = (backends[owner].models ?? []).map(m => m.name);
                if (!seen[owner] && models.length > 0) {
                    seen[owner] = true;
                    rows.push({ id: owner, label: backends[owner].label || owner, models: models });
                }
            }
            return rows.filter(r => r.models.length > 0);
        }
        readonly property int vram: ai.engines.length > 0 ? ResourceEngine.claimsOf(ai.engines[0].id).filter(c => c.resource === "gpu-vram").reduce((t, c) => t + (c.amount ?? 0), 0) : 0

        col: 6
        row: 4
        cols: 2
        rows: 2
        icon: "neurology"
        label: qsTr("Local AI")
        live: ai.engines.length > 0

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: Tokens.spacing.extraSmall

            StyledText {
                width: parent.width
                text: ai.engines.length > 0 ? ai.engines[0].label : qsTr("Idle")
                color: ai.engines.length > 0 ? Colours.ink : Colours.inkMuted
                elide: Text.ElideRight
                font.family: Tokens.font.headline.large.family
                font.pixelSize: Math.min(30, root.cellH * 0.26)
            }

            StyledText {
                width: parent.width
                text: ai.engines.length > 0 ? ai.engines[0].models.join(", ") : qsTr("No model loaded")
                color: Colours.inkMuted
                elide: Text.ElideRight
                font: Tokens.font.label.small
            }

            StyledText {
                visible: ai.vram > 0
                text: qsTr("%1 GiB on the GPU").arg((ai.vram / 1024).toFixed(1))
                color: Colours.signal
                font: Tokens.font.mono.small
            }
        }
    }

    Cell {
        col: 8
        row: 4
        cols: 4
        rows: 1
        icon: "tune"
        label: qsTr("Controls")
        padding: Tokens.padding.medium

        DashQuickToggles {
            anchors.centerIn: parent
            scale: Math.min(1, parent.width / Math.max(1, implicitWidth), parent.height / Math.max(1, implicitHeight))
        }
    }

    Cell {
        col: 8
        row: 5
        cols: 4
        rows: 1
        icon: "timer"
        label: qsTr("Focus")
        live: Pomodoro.running
        figure: Pomodoro.isBreak ? qsTr("break") : ""
        padding: Tokens.padding.medium

        RowLayout {
            anchors.fill: parent
            spacing: Tokens.spacing.large

            StyledText {
                text: Pomodoro.formatTime(Pomodoro.remaining)
                color: Colours.ink
                font.family: Tokens.font.mono.large.family
                font.pixelSize: Math.min(34, parent.height * 0.75)
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 4
                radius: 2
                color: Colours.signalStyle.hairline

                Rectangle {
                    width: parent.width * (1 - Pomodoro.remaining / Math.max(1, Pomodoro.isBreak ? Pomodoro.breakSeconds : Pomodoro.workSeconds))
                    height: parent.height
                    radius: 2
                    color: Pomodoro.isBreak ? Colours.signalTertiary : Colours.signal

                    Behavior on width {
                        Anim {}
                    }
                }
            }

            StyledRect {
                implicitWidth: 40
                implicitHeight: 40
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.signal, 0.18)
                border.width: 1
                border.color: Colours.signal

                MaterialIcon {
                    anchors.centerIn: parent
                    text: Pomodoro.running ? "pause" : "play_arrow"
                    color: Colours.signal
                    fontStyle: Tokens.font.icon.large
                }

                Interact {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: Pomodoro.toggle()
                }
            }
        }
    }
}
