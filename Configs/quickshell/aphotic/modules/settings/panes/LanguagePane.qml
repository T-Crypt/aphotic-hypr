pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
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
        { value: "gb", label: qsTr("UK") },
        { value: "de", label: qsTr("German") },
        { value: "fr", label: qsTr("French") },
        { value: "es", label: qsTr("Spanish") },
        { value: "it", label: qsTr("Italian") },
        { value: "pt", label: qsTr("Portuguese") },
        { value: "br", label: qsTr("Brazilian") },
        { value: "ru", label: qsTr("Russian") },
        { value: "jp", label: qsTr("Japanese") },
        { value: "cn", label: qsTr("Chinese") },
        { value: "se", label: qsTr("Swedish") },
        { value: "no", label: qsTr("Norwegian") },
        { value: "dk", label: qsTr("Danish") },
        { value: "fi", label: qsTr("Finnish") },
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

    function layoutLabel(code: string): string {
        const match = root.layoutPresets.find(p => p.value === code);
        return match ? match.label : code;
    }

    function moveLayout(from: int, to: int): void {
        const arr = [...Settings.additionalKbLayouts];
        const moved = arr[from];
        arr[from] = arr[to];
        arr[to] = moved;
        Settings.additionalKbLayouts = arr;
    }

    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Language")
        font: Tokens.font.title.large
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Your keyboard layout, in xkb codes. The pills are the common ones -- any other code works too, typed by hand. Everything here is written to ~/.config/hypr/keyboard.lua and applied to the running session immediately.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Primary layout")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsPresetRow {
                icon: "keyboard"
                label: qsTr("Layout")
                presets: root.layoutPresets
                value: Settings.kbLayout
                onSelected: value => Settings.kbLayout = value
            }

            SettingsRow {
                icon: "edit"
                label: qsTr("Custom code")
                description: qsTr("Any xkb code not listed above -- press Enter to apply")

                KbCodeField {
                    text: Settings.kbLayout
                    placeholderText: qsTr("e.g. ua")
                    onSubmitted: value => Settings.kbLayout = value
                }
            }

            SettingsPresetRow {
                icon: "tune"
                label: qsTr("Variant")
                description: qsTr("Applies to the primary layout only")
                presets: root.variantPresets
                value: Settings.kbVariant
                onSelected: value => Settings.kbVariant = value
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Additional layouts")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsRow {
                icon: "add"
                label: qsTr("Add a layout")
                description: qsTr("Press Enter to add it to the switch order below")

                KbCodeField {
                    placeholderText: qsTr("e.g. de, fr, jp")
                    clearOnSubmit: true
                    onSubmitted: value => {
                        if (value.length === 0 || value === Settings.kbLayout || Settings.additionalKbLayouts.includes(value))
                            return;
                        Settings.additionalKbLayouts = [...Settings.additionalKbLayouts, value];
                    }
                }
            }

            Repeater {
                model: Settings.additionalKbLayouts

                SettingsRow {
                    id: layoutRow

                    required property string modelData
                    required property int index

                    icon: "language"
                    label: root.layoutLabel(layoutRow.modelData)
                    description: layoutRow.modelData

                    RowLayout {
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: "arrow_upward"
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small
                            visible: layoutRow.index > 0

                            StateLayer {
                                anchors.fill: parent
                                anchors.margins: -Tokens.padding.small
                                radius: Tokens.rounding.full
                                onClicked: root.moveLayout(layoutRow.index, layoutRow.index - 1)
                            }
                        }

                        MaterialIcon {
                            text: "arrow_downward"
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small
                            visible: layoutRow.index < Settings.additionalKbLayouts.length - 1

                            StateLayer {
                                anchors.fill: parent
                                anchors.margins: -Tokens.padding.small
                                radius: Tokens.rounding.full
                                onClicked: root.moveLayout(layoutRow.index, layoutRow.index + 1)
                            }
                        }

                        MaterialIcon {
                            text: "delete"
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small

                            StateLayer {
                                anchors.fill: parent
                                anchors.margins: -Tokens.padding.small
                                radius: Tokens.rounding.full
                                onClicked: Settings.additionalKbLayouts = Settings.additionalKbLayouts.filter((_, i) => i !== layoutRow.index)
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            visible: Settings.additionalKbLayouts.length === 0
            text: qsTr("No additional layouts yet -- add one to enable layout switching.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        visible: Settings.additionalKbLayouts.length > 0

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Switching")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsPresetRow {
                icon: "swap_horiz"
                label: qsTr("Switch key")
                description: qsTr("Cycles through %1 in order").arg([Settings.kbLayout || "us", ...Settings.additionalKbLayouts].join(", "))
                presets: root.switchOptionsPresets
                value: Settings.kbOptions
                onSelected: value => Settings.kbOptions = value
            }
        }
    }
}
