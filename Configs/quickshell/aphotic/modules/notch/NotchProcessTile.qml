pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    readonly property bool byMem: ProcessUsage.sortBy === "mem"

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
        return root.byMem ? first.rssKib : first.cpu;
    }

    function metricOf(entry: var): real {
        return root.byMem ? entry.rssKib : entry.cpu;
    }

    function labelFor(entry: var): string {
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

        StyledText {
            text: qsTr("CPU %1%  ·  RAM %2%").arg(Math.round(SystemUsage.cpuPerc * 100)).arg(Math.round(SystemUsage.memPerc * 100))
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

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
                color: Qt.alpha(root.byMem ? Colours.palette.m3tertiary : Colours.palette.m3primary, 0.28)

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
                visible: row.index === 0 && !row.modelData && !ProcessUsage.primed
                text: qsTr("sampling…")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }
    }
}
