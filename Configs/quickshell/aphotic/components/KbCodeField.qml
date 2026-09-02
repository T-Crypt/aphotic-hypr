import QtQuick
import qs.config
import qs.components

// Single-line text field for entering xkb codes (layout, variant, model,
// rules). Mirrors the AI pane's entry boxes (Host / Pull new model): a
// pill StyledRect lifted a layer above the containing SettingsRow, with a
// native TextInput so glyphs keep the theme's onSurface color (a
// QtQuick.Controls TextField with a null background rendered un-themed,
// near-black text). `text` seeds the field; pressing Enter emits
// `submitted` with the trimmed, lowercased value.
StyledRect {
    id: root

    property string text: ""
    property string placeholderText: ""
    signal submitted(value: string)

    Layout.preferredWidth: 160
    Layout.preferredHeight: 32
    radius: Tokens.rounding.full
    color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

    TextInput {
        id: input

        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        font: Tokens.font.label.small
        color: Colours.palette.m3onSurface
        text: root.text

        Keys.onReturnPressed: {
            const v = input.text.trim().toLowerCase();
            root.submitted(v);
        }

        StyledText {
            visible: input.text.length === 0
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.placeholderText
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }
}
