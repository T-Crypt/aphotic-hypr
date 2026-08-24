pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services

// First increment of a standalone theme-creation flow, deliberately
// separate from AppearancePane (which only *selects* an existing theme,
// never define/edit one). Creates a *static* theme: a fixed colorscheme
// under ~/.config/wallust/colorschemes/<slug>.json (pywal format) plus a
// matching ~/.config/awww/<slug>/theme.toml that points [engine].colorscheme
// at it -- see themes/THEME_SPEC.md's "Fixed colorschemes" section. This
// is purely additive to ~/.config -- it never touches the git repo, so
// there's nothing to commit here.
ColumnLayout {
    id: root

    readonly property var _defaultColours: ({
        background: "#1a1b26",
        foreground: "#c0caf5",
        cursor: "#c0caf5",
        color0: "#15161e",
        color1: "#f7768e",
        color2: "#9ece6a",
        color3: "#e0af68",
        color4: "#7aa2f7",
        color5: "#bb9af7",
        color6: "#7dcfff",
        color7: "#a9b1d6",
        color8: "#414868",
        color9: "#f7768e",
        color10: "#9ece6a",
        color11: "#e0af68",
        color12: "#7aa2f7",
        color13: "#bb9af7",
        color14: "#7dcfff",
        color15: "#c0caf5"
    })

    property string themeName: ""
    readonly property string themeSlug: root.themeName.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
    readonly property string awwwDir: `${Quickshell.env("HOME")}/.config/awww`
    readonly property string themeDir: `${root.awwwDir}/${root.themeSlug}`

    property var colours: root._defaultColours

    property string createStatus: ""
    property bool created: false

    function setColour(key: string, value: string): void {
        const next = Object.assign({}, root.colours);
        next[key] = value;
        root.colours = next;
    }

    function _hexToRgb(hex: string): var {
        const h = hex.replace("#", "");
        return [parseInt(h.substring(0, 2), 16), parseInt(h.substring(2, 4), 16), parseInt(h.substring(4, 6), 16)];
    }

    function createTheme(): void {
        if (root.themeSlug.length === 0) {
            root.createStatus = qsTr("Name it first.");
            return;
        }

        const c = root.colours;
        const schemeJson = JSON.stringify({
            special: { background: c.background, foreground: c.foreground, cursor: c.cursor },
            colors: {
                color0: c.color0, color1: c.color1, color2: c.color2, color3: c.color3,
                color4: c.color4, color5: c.color5, color6: c.color6, color7: c.color7,
                color8: c.color8, color9: c.color9, color10: c.color10, color11: c.color11,
                color12: c.color12, color13: c.color13, color14: c.color14, color15: c.color15
            }
        }, null, 2);

        const themeToml = [
            "[theme]",
            `display_name = "${root.themeName.trim()}"`,
            `description = "Static, hand-picked palette -- created via the Theme Creator."`,
            "",
            "[engine]",
            `colorscheme = "${root.themeSlug}"`,
            "",
            "[wallpaper]",
            'default = "wallpaper.png"'
        ].join("\n");

        const bg = root._hexToRgb(c.background);
        const accent = root._hexToRgb(c.color4);
        const wallpaperScript = [
            "from PIL import Image",
            "w, h = 1920, 1080",
            `top = (${bg[0]}, ${bg[1]}, ${bg[2]})`,
            `bottom = (${accent[0]}, ${accent[1]}, ${accent[2]})`,
            "grad = Image.new('RGB', (1, h))",
            "for y in range(h):",
            "    t = y / (h - 1)",
            "    grad.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))",
            `grad.resize((w, h)).save('${root.themeDir}/wallpaper.png')`
        ].join("\n");

        // Heredoc terminators must be alone on their own line, so these
        // steps are newline-joined (not `&&`-joined -- that would land
        // "APHOTIC_..._EOF && next-command" on one line and the shell
        // would never see the heredoc close). `set -e` gets the same
        // fail-fast behaviour without needing `&&` between them.
        const script = [
            "set -e",
            `mkdir -p '${root.themeDir}' "${Quickshell.env("HOME")}/.config/wallust/colorschemes"`,
            `cat > '${root.themeDir}/theme.toml' <<'APHOTIC_THEME_TOML_EOF'\n${themeToml}\nAPHOTIC_THEME_TOML_EOF`,
            `cat > "${Quickshell.env("HOME")}/.config/wallust/colorschemes/${root.themeSlug}.json" <<'APHOTIC_SCHEME_JSON_EOF'\n${schemeJson}\nAPHOTIC_SCHEME_JSON_EOF`,
            `python3 -c "${wallpaperScript.replace(/"/g, "\\\"")}"`
        ].join("\n");

        createProc.command = ["sh", "-c", script];
        createProc.running = true;
    }

    Process {
        id: createProc
        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: createErr
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                root.created = true;
                root.createStatus = qsTr("Created at %1").arg(root.themeDir);
            } else {
                root.created = false;
                root.createStatus = qsTr("Failed: %1").arg(createErr.text.trim().length > 0 ? createErr.text.trim() : qsTr("see logs"));
            }
        }
    }

    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Theme Creator")
        font: Tokens.font.title.large
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Build a static theme with a fixed, hand-picked palette instead of one derived from a wallpaper. Creates a real theme folder under ~/.config/awww -- it shows up in Appearance's theme grid like any other once created.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "edit"
            label: qsTr("Theme name")
            description: root.themeSlug.length > 0 ? qsTr("Folder: ~/.config/awww/%1").arg(root.themeSlug) : qsTr("Used for both the display name and the folder")

            StyledRect {
                implicitWidth: 220
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                TextInput {
                    id: nameInput
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    clip: true
                    text: root.themeName
                    onTextChanged: root.themeName = text

                    StyledText {
                        visible: nameInput.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("My Theme")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        SettingsRow {
            icon: "folder_open"
            label: qsTr("Theme folder")
            description: root.created ? root.themeDir : qsTr("Available once created")

            MaterialIcon {
                text: "folder_open"
                color: root.created ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3outlineVariant

                StateLayer {
                    anchors.fill: parent
                    anchors.margins: -Tokens.padding.small
                    radius: Tokens.rounding.full
                    disabled: !root.created
                    onClicked: Quickshell.execDetached(["thunar", root.themeDir])
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Special")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    RowLayout {
        spacing: Tokens.spacing.large

        Repeater {
            model: [
                { key: "background", label: qsTr("Background") },
                { key: "foreground", label: qsTr("Foreground") },
                { key: "cursor", label: qsTr("Cursor") }
            ]

            ColumnLayout {
                id: specialCol

                required property var modelData
                spacing: Tokens.spacing.extraSmall / 2

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: specialCol.modelData.label
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                ColorPickerField {
                    Layout.alignment: Qt.AlignHCenter
                    allowUnset: false
                    value: root.colours[specialCol.modelData.key]
                    onValueChanged: root.setColour(specialCol.modelData.key, value)
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Normal colours")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    Flow {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Repeater {
            model: 8

            ColorPickerField {
                required property int index

                allowUnset: false
                value: root.colours[`color${index}`]
                onValueChanged: root.setColour(`color${index}`, value)
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Bright colours")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    Flow {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Repeater {
            model: 8

            ColorPickerField {
                required property int index

                allowUnset: false
                value: root.colours[`color${8 + index}`]
                onValueChanged: root.setColour(`color${8 + index}`, value)
            }
        }
    }

    RowLayout {
        Layout.topMargin: Tokens.spacing.medium
        spacing: Tokens.spacing.medium

        StyledRect {
            implicitWidth: createLabel.implicitWidth + Tokens.padding.large * 2
            implicitHeight: 40
            radius: Tokens.rounding.medium
            color: Colours.palette.m3primary

            StyledText {
                id: createLabel
                anchors.centerIn: parent
                text: qsTr("Create theme")
                color: Colours.contrastOn(Colours.palette.m3primary)
                font: Tokens.font.body.medium
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                onClicked: root.createTheme()
            }
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            visible: root.createStatus.length > 0
            text: root.createStatus
            color: root.created ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3error
            font: Tokens.font.body.small
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.bottomMargin: Tokens.spacing.medium
        wrapMode: Text.Wrap
        text: qsTr("After creating, run \"aphotic theme list\" or reopen Appearance to switch to it -- switching themes and previewing swatch changes live is a follow-up increment.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }
}
