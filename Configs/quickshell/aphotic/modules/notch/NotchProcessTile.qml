pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    readonly property bool byMem: ProcessUsage.sortBy === "mem"
    readonly property bool byGpu: ProcessUsage.sortBy === "gpu"
    readonly property color metricColour: root.byGpu ? Colours.palette.m3secondary : root.byMem ? Colours.palette.m3tertiary : Colours.palette.m3primary

    // Padded to a constant length so the tile's implicitHeight -- and
    // therefore the notch's animated height -- does not twitch as
    // processes come and go, or jump once the first real sample lands.
    readonly property var rows: {
        const list = ProcessUsage.processes.slice();
        while (list.length < Config.notch.processCount)
            list.push(null);
        return list;
    }

    readonly property real peak: {
        const first = ProcessUsage.processes[0];
        if (!first)
            return 0;
        return root.metricOf(first);
    }

    // Says which of the three empty states this is: unsupported hardware,
    // a sweep that has not landed yet, or a supported GPU with nothing
    // currently holding VRAM.
    readonly property string emptyNote: {
        if (ProcessUsage.processes.length > 0)
            return "";
        if (root.byGpu && !ProcessUsage.gpuSupported)
            return qsTr("Per-process VRAM needs an NVIDIA GPU");
        if (root.byGpu && !ProcessUsage.gpuAvailable)
            return qsTr("reading VRAM…");
        if (!ProcessUsage.primed)
            return qsTr("sampling…");
        return root.byGpu ? qsTr("nothing holding VRAM") : "";
    }

    function metricOf(entry: var): real {
        if (root.byGpu)
            return entry.gpuMib;
        return root.byMem ? entry.rssKib : entry.cpu;
    }

    function labelFor(entry: var): string {
        if (root.byGpu)
            return entry.gpuMib >= 1024 ? `${(entry.gpuMib / 1024).toFixed(1)} GiB` : `${entry.gpuMib} MiB`;
        if (root.byMem) {
            const fmt = SystemUsage.formatKib(entry.rssKib);
            return `${fmt.value.toFixed(fmt.unit === "GiB" ? 1 : 0)} ${fmt.unit}`;
        }
        return `${entry.cpu.toFixed(entry.cpu >= 10 ? 0 : 1)}%`;
    }

    spacing: Tokens.spacing.extraSmall

    // One cell width for all three, measured off the widest string any of
    // them can ever hold, so a reading crossing 9%->10% cannot shove its
    // neighbours sideways.
    TextMetrics {
        id: metricCell

        font: Tokens.font.label.small
        text: "GPU 100%"
    }

    component Metric: StyledText {
        required property string label
        required property real perc

        // An equal share each, so the three sit flush to both margins and
        // evenly apart. preferredWidth alongside fillWidth is what makes
        // the shares equal rather than proportional to each string, which
        // is also why a reading crossing 9%->10% cannot shove its
        // neighbours sideways.
        Layout.fillWidth: true
        Layout.preferredWidth: metricCell.width
        text: `${label} ${Math.round(perc * 100)}%`
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
    }

    component SortChip: StyledRect {
        id: sortChip

        required property string key
        required property string label
        readonly property bool active: ProcessUsage.sortBy === sortChip.key

        implicitWidth: sortChipLabel.implicitWidth + Tokens.padding.small * 2
        implicitHeight: 20
        radius: Tokens.rounding.full
        color: sortChip.active ? Colours.palette.m3secondaryContainer : "transparent"

        Behavior on color {
            CAnim {}
        }

        StateLayer {
            radius: parent.radius
            onClicked: ProcessUsage.sortBy = sortChip.key
        }

        StyledText {
            id: sortChipLabel

            anchors.centerIn: parent
            text: sortChip.label
            color: sortChip.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.builders.small.weight(Font.Medium).build()
        }
    }

    // Its own row rather than sharing one with the sort chips: three
    // readings and three chips came to 445px against 388 of content, which
    // is what was eliding "GPU 42%" down to "GP...". Splitting them costs
    // one text line of height and leaves both rows with real slack.
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Metric {
            label: qsTr("CPU")
            perc: SystemUsage.cpuPerc
            horizontalAlignment: Text.AlignLeft
        }

        Metric {
            label: qsTr("RAM")
            perc: SystemUsage.memPerc
            horizontalAlignment: Text.AlignHCenter
        }

        // Only where there is a live figure: gpuStatsAvailable is false
        // when no vendor tool is installed, and a hardcoded "GPU 0%" beside
        // two real meters is worse than no segment at all. A layout skips
        // an invisible item entirely, so the remaining two re-spread across
        // the full width rather than leaving a hole. It ticks at
        // SystemUsage's fast cadence, which Notch.qml opts into for exactly
        // as long as this tile is up.
        Metric {
            visible: SystemUsage.gpuStatsAvailable
            label: qsTr("GPU")
            perc: SystemUsage.gpuPerc
            horizontalAlignment: Text.AlignRight
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: Tokens.spacing.extraSmall
        spacing: Tokens.spacing.extraSmall

        Item {
            Layout.fillWidth: true
        }

        SortChip {
            key: "cpu"
            label: qsTr("CPU")
        }

        SortChip {
            key: "mem"
            label: qsTr("Memory")
        }

        SortChip {
            key: "gpu"
            label: qsTr("GPU")
        }
    }

    Repeater {
        model: root.rows

        StyledRect {
            id: row

            required property var modelData
            required property int index

            Layout.fillWidth: true
            implicitHeight: 24
            radius: Tokens.rounding.small
            color: row.modelData ? Colours.layer(Colours.palette.m3surfaceContainerHigh, 2) : "transparent"

            StyledRect {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: row.modelData && root.peak > 0 ? parent.width * Math.min(1, root.metricOf(row.modelData) / root.peak) : 0
                radius: parent.radius
                color: Qt.alpha(root.metricColour, 0.28)

                Behavior on width {
                    Anim { type: Anim.DefaultEffects }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.small
                anchors.rightMargin: Tokens.padding.small
                spacing: Tokens.spacing.small
                visible: !!row.modelData

                StyledText {
                    Layout.fillWidth: true
                    text: row.modelData?.name ?? ""
                    elide: Text.ElideRight
                    font: Tokens.font.body.medium
                }

                StyledText {
                    text: row.modelData ? String(row.modelData.pid) : ""
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.mono.small
                }

                StyledText {
                    text: row.modelData ? root.labelFor(row.modelData) : ""
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.mono.builders.small.weight(Font.Medium).build()
                    horizontalAlignment: Text.AlignRight

                    // Fixed width so the right column stays a column: the
                    // values change every tick and a mono face still
                    // shifts the whole row when the digit count does.
                    Layout.preferredWidth: 62
                }
            }

            StyledText {
                anchors.centerIn: parent
                width: parent.width - Tokens.padding.small * 2
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: row.index === 0 && !row.modelData && root.emptyNote.length > 0
                text: root.emptyNote
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }
    }
}
