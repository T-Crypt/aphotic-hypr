import QtQuick
import qs.config
import qs.services

Column {
    id: readout

    required property string value
    property string total: ""
    required property string label
    property bool small: false

    spacing: Tokens.spacing.extraSmall

    Row {
        spacing: Tokens.spacing.extraSmall

        StyledText {
            id: valueText

            text: readout.value
            color: Colours.ink
            font: (readout.small ? Tokens.font.title.builders.small : Tokens.font.title.builders.large).weight(Font.DemiBold).build()
        }

        StyledText {
            anchors.baseline: valueText.baseline
            visible: readout.total.length > 0
            text: readout.total
            color: Colours.inkMuted
            font: Tokens.font.body.builders.small.weight(Font.Medium).build()
        }
    }

    SectionLabel {
        label: readout.label
    }
}
