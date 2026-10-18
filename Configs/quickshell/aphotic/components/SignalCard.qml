import QtQuick
import qs.config
import qs.services

StyledRect {
    id: card

    property string title: ""
    property int tintIndex: 0
    readonly property real headerHeight: card.title.length > 0 ? cardTitle.implicitHeight + Tokens.padding.medium : 0

    radius: Tokens.rounding.medium
    color: Colours.signalStyle.raised
    border.width: 1
    border.color: Colours.signalStyle.hairline

    Elevation {
        target: card
        level: 1
    }

    Rectangle {
        x: card.radius
        width: card.width - card.radius * 2
        height: 1
        color: Colours.signalStyle.edgeLight
    }

    Row {
        id: cardTitle

        visible: card.headerHeight > 0
        x: Tokens.padding.large
        y: Tokens.padding.medium
        spacing: Tokens.spacing.small

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: Tokens.rounding.full
            color: Colours.signalStyle.tint(card.tintIndex)
        }

        SectionLabel {
            label: card.title
        }
    }
}
