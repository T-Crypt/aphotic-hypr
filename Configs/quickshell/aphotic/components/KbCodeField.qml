import QtQuick
import qs.config
import qs.services

// Single-line text field for entering xkb codes (layout, variant, model,
// rules). Sized with implicit dimensions rather than Layout attached
// properties because SettingsRow's trailing slot is a plain Item, where
// Layout.* is both unresolvable and ignored. `text` seeds the field; the
// value is committed on Enter or on losing focus.
StyledRect {
    id: root

    property alias placeholderText: placeholder.text
    property string text: ""
    // An "add to a list" entry rather than a bound value: clears after each
    // submit, and only submits on Enter, so clicking away never appends
    // whatever half-typed code was left sitting in it.
    property bool clearOnSubmit: false
    signal submitted(value: string)

    function commit(): void {
        const v = input.text.trim().toLowerCase();
        input.text = root.clearOnSubmit ? "" : v;
        root.submitted(v);
    }

    implicitWidth: 180
    implicitHeight: 32
    radius: Tokens.rounding.full
    color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

    onTextChanged: {
        if (!input.activeFocus)
            input.text = root.text;
    }

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

        onAccepted: root.commit()
        onActiveFocusChanged: {
            if (!input.activeFocus && !root.clearOnSubmit)
                root.commit();
        }

        StyledText {
            id: placeholder

            visible: input.text.length === 0
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }
}
