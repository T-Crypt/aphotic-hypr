pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

StyledRect {
    id: root

    required property string icon
    required property string label
    property string description: ""

    // Connected-list positioning (ported from caelestia's Nexus
    // ConnectedRect pattern): a standalone row defaults to fully rounded
    // on every corner (first=last=true). Rows placed inside a
    // SettingsGroup get these stamped automatically so consecutive rows
    // in one logical section render as a single seamless card, only the
    // first/last row rounded on its outer edge.
    property bool first: true
    property bool last: true

    default property alias trailing: trailingSlot.data

    Layout.fillWidth: true
    Layout.preferredHeight: rowLayout.implicitHeight + Tokens.padding.medium * 2
    implicitHeight: rowLayout.implicitHeight + Tokens.padding.medium * 2

    color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)
    topLeftRadius: root.first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
    topRightRadius: root.first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
    bottomLeftRadius: root.last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
    bottomRightRadius: root.last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall

    Behavior on topLeftRadius {
        Anim { type: Anim.DefaultEffects }
    }
    Behavior on topRightRadius {
        Anim { type: Anim.DefaultEffects }
    }
    Behavior on bottomLeftRadius {
        Anim { type: Anim.DefaultEffects }
    }
    Behavior on bottomRightRadius {
        Anim { type: Anim.DefaultEffects }
    }

    RowLayout {
        id: rowLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        StyledRect {
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            radius: Tokens.rounding.medium
            color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

            MaterialIcon {
                anchors.centerIn: parent
                text: root.icon
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.label
                elide: Text.ElideRight
                font: Tokens.font.body.medium
            }

            StyledText {
                visible: root.description.length > 0
                Layout.fillWidth: true
                text: root.description
                elide: Text.ElideRight
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }

        Item {
            id: trailingSlot

            Layout.preferredWidth: childrenRect.width
            Layout.preferredHeight: childrenRect.height
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
