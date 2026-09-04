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
