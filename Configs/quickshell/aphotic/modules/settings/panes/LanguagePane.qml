pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    // Common xkb layout codes for the primary picker. Any currently
    // selected value not in this list (e.g. a custom code the user typed)
    // simply shows no pill as active -- the raw value still applies.
    readonly property var layoutPresets: [
        { value: "us", label: qsTr("US") },
        { value: "us_intl", label: qsTr("US Intl") },
        { value: "gb", label: qsTr("UK") },
        { value: "de", label: qsTr("German") },
        { value: "fr", label: qsTr("French") },
        { value: "es", label: qsTr("Spanish") },
        { value: "pt", label: qsTr("Portuguese") },
        { value: "it", label: qsTr("Italian") },
        { value: "ru", label: qsTr("Russian") },
        { value: "jp", label: qsTr("Japanese") },
        { value: "cn", label: qsTr("Chinese") },
        { value: "br", label: qsTr("Brazilian") },
        { value: "se", label: qsTr("Swedish") },
        { value: "fi", label: qsTr("Finnish") },
        { value: "no", label: qsTr("Norwegian") },
        { value: "dk", label: qsTr("Danish") },
        { value: "pl", label: qsTr("Polish") },
        { value: "tr", label: qsTr("Turkish") },
        { value: "ar", label: qsTr("Arabic") },
        { value: "il", label: qsTr("Hebrew") }
    ]

    readonly property var variantPresets: [
        { value: "", label: qsTr("Default") },
        { value: "intl", label: qsTr("Intl") },
        { value: "dvorak", label: qsTr("Dvorak") },
        { value: "colemak", label: qsTr("Colemak") }
    ]

    readonly property var switchOptionsPresets: [
        { value: "", label: qsTr("None") },
        { value: "grp:alt_shift_toggle", label: qsTr("Alt+Shift") },
        { value: "grp:ctrl_shift_toggle", label: qsTr("Ctrl+Shift") },
        { value: "grp:caps_toggle", label: qsTr("Caps Lock") },
        { value: "grp:win_space_toggle", label: qsTr("Super+Space") }
    ]

    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Language / Keyboard")
        font: Tokens.font.title.large
    }

    StyledText {
        text: qsTr("Primary layout")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Your main keyboard layout. The full list of valid codes comes from xkb — the pills below are just the most common. If yours isn't listed, type it below and press Enter.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsPresetRow {
            icon: "keyboard"
            label: qsTr("Primary layout")
            presets: root.layoutPresets
            value: Settings.kbLayout
            onSelected: value => Settings.kbLayout = value
        }

        SettingsRow {
            icon: "edit"
            label: qsTr("Custom code")

            KbCodeField {
                text: Settings.kbLayout
                onSubmitted: value => Settings.kbLayout = value
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Additional layouts")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Add extra layouts to switch between with your group-toggle key (set below). Choosing a layout from the list keeps your second-plus layouts orderable; type a custom code and press Enter to add it directly.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "add"
            label: qsTr("Add layout")

            KbCodeField {
                placeholderText: qsTr("e.g. de, fr, jp…")
                onSubmitted: value => {
                    const clean = value.trim().toLowerCase();
                    if (clean.length === 0 || Settings.additionalKbLayouts.includes(clean))
                        return;
                    Settings.additionalKbLayouts = [...Settings.additionalKbLayouts, clean];
                }
            }
        }

        Repeater {
            model: Settings.additionalKbLayouts

            SettingsRow {
                required property string modelData
                required property int index

                icon: "language"
                label: root.additionalRowLabel(modelData)
                last: index === Settings.additionalKbLayouts.length - 1

                RowLayout {
                    spacing: Tokens.spacing.medium

                    Item {
                        Layout.fillWidth: true
                    }

                    MaterialIcon {
                        text: "arrow_upward"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                        visible: index > 0

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.small
                            radius: Tokens.rounding.full
                            onClicked: {
                                const arr = [...Settings.additionalKbLayouts];
                                const t = arr[index - 1];
                                arr[index - 1] = arr[index];
                                arr[index] = t;
                                Settings.additionalKbLayouts = arr;
                            }
                        }
                    }

                    MaterialIcon {
                        text: "arrow_downward"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                        visible: index < Settings.additionalKbLayouts.length - 1

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.small
                            radius: Tokens.rounding.full
                            onClicked: {
                                const arr = [...Settings.additionalKbLayouts];
                                const t = arr[index + 1];
                                arr[index + 1] = arr[index];
                                arr[index] = t;
                                Settings.additionalKbLayouts = arr;
                            }
                        }
                    }

                    MaterialIcon {
                        text: "close"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.small
                            radius: Tokens.rounding.full
                            onClicked: Settings.additionalKbLayouts = Settings.additionalKbLayouts.filter((_, i) => i !== index)
                        }
                    }
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        visible: Settings.additionalKbLayouts.length === 0
        text: qsTr("No additional layouts yet. Add one above to enable multi-layout switching.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Variant & switch key")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsPresetRow {
            icon: "tune"
            label: qsTr("Variant")
            description: qsTr("Only applies to the primary layout")
            presets: root.variantPresets
            value: Settings.kbVariant
            onSelected: value => Settings.kbVariant = value
        }

        SettingsPresetRow {
            icon: "swap_horiz"
            label: qsTr("Layout switch key")
            visible: Settings.additionalKbLayouts.length > 0
            presets: root.switchOptionsPresets
            value: Settings.kbOptions
            onSelected: value => Settings.kbOptions = value
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        visible: Settings.additionalKbLayouts.length === 0
        text: qsTr("Add a second layout above to choose a layout-switch key.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("These are written to ~/.config/hypr/custom.lua — the override file install.sh never overwrites — and applied immediately via the compositor's live config API.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    function additionalRowLabel(code: string): string {
        const match = root.layoutPresets.find(p => p.value === code);
        return match ? match.label : code;
    }
}
