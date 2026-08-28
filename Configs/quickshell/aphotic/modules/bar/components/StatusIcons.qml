pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.utils
import qs.modules.bar.components.status

Item {
    id: root

    required property ScreenState screenState

    property color colour: Colours.palette.m3secondaryOnSurface

    readonly property int spacing: Tokens.spacing.medium / 2
    // Real gap BETWEEN pills -- previously a single 1px divider line
    // inside one continuous background, which read as "no separation,
    // one shape" rather than distinct groups.
    readonly property int groupSpacing: Tokens.spacing.small

    // Bar.qml's checkPopout reads this for group-aware hit-testing: find
    // which pill's own bounds contain the hover position first, THEN
    // the nearest icon within just that pill -- tightly scoped to each
    // pill's real extent rather than one flat search across every icon
    // regardless of which group it's visually in.
    readonly property var groupContainers: {
        const result = [];
        for (let i = 0; i < groupRepeater.count; i++) {
            const pill = groupRepeater.itemAt(i);
            if (pill)
                result.push({ pill, icons: pill.icons });
        }
        return result;
    }

    // groupDivider entries now just mark a split point between pills
    // instead of rendering as a visible line -- the pills' own gap does
    // that job.
    readonly property var groups: {
        const values = root.Config.bar.statusIcons.values.filter(e => e.enabled);
        const out = [];
        let current = [];
        for (const v of values) {
            if (v.id === "groupDivider") {
                if (current.length > 0) {
                    out.push(current);
                    current = [];
                }
            } else {
                current.push(v);
            }
        }
        if (current.length > 0)
            out.push(current);
        return out;
    }

    implicitWidth: Settings.barHorizontal ? groupLayout.implicitWidth : Settings.barInnerWidth
    implicitHeight: Settings.barHorizontal ? Settings.barInnerWidth : groupLayout.implicitHeight


    GridLayout {
        id: groupLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        flow: Settings.barHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
        rowSpacing: root.groupSpacing
        columnSpacing: root.groupSpacing

        states: State {
            name: "vertical"
            when: Settings.barHorizontal

            AnchorChanges {
                target: groupLayout
                anchors.left: undefined
                anchors.top: root.top
                anchors.bottom: root.bottom
                anchors.right: root.right
            }
        }

        Repeater {
            id: groupRepeater

            model: root.groups

            StyledRect {
                id: pill

                required property var modelData
                readonly property alias icons: pillIcons
                property Item hoveredEntry: null

                color: Colours.palette.m3surfaceContainerHigh
                radius: Tokens.rounding.full
                clip: true

                Layout.preferredWidth: Settings.barHorizontal ? pillIcons.implicitWidth + Tokens.padding.medium * 2 : Settings.barInnerWidth
                Layout.preferredHeight: Settings.barHorizontal ? Settings.barInnerWidth : pillIcons.implicitHeight + Tokens.padding.medium * 2

                HoverPill {
                    container: pillIcons
                    hoveredEntry: pill.hoveredEntry
                    thickness: Settings.barHorizontal ? pill.height : pill.width
                }

                HoverHandler {
                    id: pillHover
                    onPointChanged: {
                        if (!pillHover.hovered)
                            return;
                        const local = pill.mapToItem(pillIcons, pillHover.point.position.x, pillHover.point.position.y);
                        pill.hoveredEntry = BarHit.nearestAt(pillIcons, local.x, local.y);
                    }
                    onHoveredChanged: {
                        if (!pillHover.hovered)
                            pill.hoveredEntry = null;
                    }
                }

                GridLayout {
                    id: pillIcons

                    anchors.centerIn: parent
                    flow: Settings.barHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
                    rowSpacing: root.spacing
                    columnSpacing: root.spacing

                    Repeater {
                        model: ScriptModel {
                            values: pill.modelData
                        }

                        DelegateChooser {
                            role: "id"

                            DelegateChoice {
                                roleValue: "lockStatus"
                                delegate: EntryWrapper {
                                    LockStatus {
                                        colour: root.colour
                                        parentSpacing: root.spacing
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "audio"
                                delegate: EntryWrapper {
                                    MaterialIcon {
                                        animate: true
                                        text: Icons.getVolumeIcon(Audio.volume, Audio.muted)
                                        color: root.colour
                                        fontStyle: Tokens.font.icon.medium
                                        fill: 1
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "microphone"
                                delegate: EntryWrapper {
                                    name: "audio" // Mic opens audio popout

                                    MaterialIcon {
                                        animate: true
                                        text: Icons.getMicVolumeIcon(Audio.sourceVolume, Audio.sourceMuted)
                                        color: root.colour
                                        fontStyle: Tokens.font.icon.medium
                                        fill: 1
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "kbLayout"
                                delegate: EntryWrapper {
                                    StyledText {
                                        animate: true
                                        text: Hypr.kbLayout
                                        color: root.colour
                                        font: Tokens.font.mono.medium
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "network"
                                delegate: EntryWrapper {
                                    MaterialIcon {
                                        animate: true
                                        text: Nmcli.activeEthernet ? "cable" : Nmcli.active ? Icons.getNetworkIcon(Nmcli.active.strength ?? 0) : "wifi_off"
                                        color: Settings.statusIconWifiColor.length > 0 ? Settings.statusIconWifiColor : root.colour

                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -Tokens.padding.small
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Quickshell.execDetached(["nm-connection-editor"])
                                        }
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "bluetooth"
                                delegate: EntryWrapper {
                                    BluetoothStatus {
                                        colour: Settings.statusIconBluetoothColor.length > 0 ? Settings.statusIconBluetoothColor : root.colour

                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -Tokens.padding.small
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Quickshell.execDetached(["blueman-manager"])
                                        }
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "vpn"
                                delegate: EntryWrapper {
                                    VpnStatus {
                                        colour: root.colour
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "battery"
                                delegate: EntryWrapper {
                                    BatteryStatus {
                                        colour: Settings.statusIconPowerProfileColor.length > 0 ? Settings.statusIconPowerProfileColor : root.colour
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "resources"
                                delegate: EntryWrapper {
                                    ResourcesStatus {
                                        colour: Settings.statusIconPerformanceColor.length > 0 ? Settings.statusIconPerformanceColor : root.colour
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "hostInfo"
                                delegate: EntryWrapper {
                                    HostInfoStatus {
                                        colour: Settings.statusIconHostInfoColor.length > 0 ? Settings.statusIconHostInfoColor : root.colour
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "networkSpeed"
                                delegate: EntryWrapper {
                                    NetworkSpeedStatus {
                                        colour: root.colour
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "pomodoro"
                                delegate: EntryWrapper {
                                    PomodoroStatus {
                                        colour: Settings.statusIconPomodoroColor.length > 0 ? Settings.statusIconPomodoroColor : root.colour
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "dnd"
                                delegate: EntryWrapper {
                                    DndStatus {
                                        colour: Settings.statusIconDndColor.length > 0 ? Settings.statusIconDndColor : root.colour
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "notifCenter"
                                delegate: EntryWrapper {
                                    NotifCenterStatus {
                                        colour: root.colour
                                        screenState: root.screenState
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Simple uniform spacing (pillIcons' own rowSpacing/columnSpacing)
    // replaces the old per-item topGap/bottomGap edge-margin-gating --
    // that machinery existed only to avoid a phantom gap around
    // lockStatus when it collapses to zero width, which only ever
    // happens within one pill (the System group). Accepting that one
    // minor, rare cosmetic edge case (a slightly wider gap around a
    // collapsed lockStatus icon) in exchange for real per-pill grouping
    // without threading first/last-present indices through 13 delegate
    // call sites that would each need it.
    component EntryWrapper: Item {
        required property var modelData
        required property int index
        default property Item item
        property string name: modelData.id.toLowerCase()

        Layout.alignment: Settings.barHorizontal ? Qt.AlignVCenter : Qt.AlignHCenter

        implicitWidth: item?.implicitWidth ?? 0
        implicitHeight: item?.implicitHeight ?? 0

        children: item
    }
}
