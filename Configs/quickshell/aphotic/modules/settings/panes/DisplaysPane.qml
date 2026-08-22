pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Displays")
        font: Tokens.font.title.large
    }

    StyledText {
        visible: Hypr.monitors.values.length === 0
        text: qsTr("No monitors reported by Hyprland yet")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    // Read-only for now: this Hyprland install uses the Lua config
    // (hl.monitor()/monitors.lua), where `hyprctl keyword monitor ...`
    // outright fails ("keyword can't work with non-legacy parsers") and
    // `hyprctl eval 'hl.monitor({...})'` registers the rule without
    // actually re-applying it live -- confirmed live in this session,
    // scale stayed unchanged either way, and `hyprctl reload` just
    // re-reads monitors.lua's own static rule instead of keeping the
    // eval'd one. A real "change it from here" control needs either a
    // genuine Hyprland Lua runtime API for this (doesn't appear to exist)
    // or rewriting monitors.lua + reload, which is real, riskier follow-up
    // work -- not something to half-wire tonight.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        Repeater {
            model: ScriptModel {
                values: Hypr.monitors.values
            }

            MonitorCard {}
        }
    }

    component MonitorCard: StyledRect {
        id: card

        required property var modelData
        readonly property var info: card.modelData.lastIpcObject ?? {}

        Layout.fillWidth: true
        implicitHeight: content.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "monitor"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: card.modelData.name ?? ""
                        font: Tokens.font.body.medium
                    }

                    StyledText {
                        visible: (card.info.description ?? "").length > 0
                        text: card.info.description ?? ""
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    visible: card.modelData.focused ?? false
                    text: qsTr("Primary")
                    color: Colours.palette.m3primaryOnSurface
                    font: Tokens.font.label.small
                }
            }

            SettingsGroup {
                Layout.fillWidth: true

                SettingsRow {
                    icon: "aspect_ratio"
                    label: qsTr("Resolution & refresh rate")
                    description: `${card.info.width ?? 0}x${card.info.height ?? 0}@${(card.info.refreshRate ?? 0).toFixed(2)}Hz`
                }

                SettingsRow {
                    icon: "zoom_in"
                    label: qsTr("Scale")
                    description: qsTr("%1x").arg((card.modelData.scale ?? 1).toFixed(2))
                }
            }
        }
    }
}
