pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// A collapsed-by-default settings section: one header row that expands in
// place. This is what keeps the Settings rail a fixed length -- a feature
// too small to justify a whole category, and every plugin-contributed
// pane, docks into the category it belongs to as one of these instead of
// claiming a rail entry of its own. Fifty plugins is fifty header rows
// spread across the categories that own them, not fifty pages.
//
// Content is a Component, not inline children: a collapsed section must
// cost nothing until it is opened, and `expanded` drives a real Loader so
// a section nobody expands never builds its controls at all.
ColumnLayout {
    id: root

    required property string icon
    required property string label
    property string description: ""
    // Either an inline Component (a core section) or a file:// URL out of
    // the plugin registry (a plugin's pane). One section component serves
    // both so a plugin's settings are not a second-class rendering path.
    property Component content: null
    property url source: ""

    property bool expanded: false

    // Set by a host that navigated here from search, so the section it
    // matched opens and marks itself instead of leaving the user on a
    // page of collapsed rows with no indication which one they asked for.
    property bool highlighted: false

    spacing: 0

    StyledRect {
        id: header

        Layout.fillWidth: true
        implicitHeight: headerRow.implicitHeight + Tokens.padding.medium * 2

        color: root.highlighted ? Colours.layer(Colours.tPalette.m3surfaceContainer, 3) : Colours.layer(Colours.tPalette.m3surfaceContainer, 2)
        topLeftRadius: Tokens.rounding.extraLarge
        topRightRadius: Tokens.rounding.extraLarge
        bottomLeftRadius: root.expanded ? Tokens.rounding.extraSmall : Tokens.rounding.extraLarge
        bottomRightRadius: root.expanded ? Tokens.rounding.extraSmall : Tokens.rounding.extraLarge

        Behavior on color {
            CAnim {}
        }
        Behavior on bottomLeftRadius {
            Anim { type: Anim.DefaultEffects }
        }
        Behavior on bottomRightRadius {
            Anim { type: Anim.DefaultEffects }
        }

        StateLayer {
            radius: Tokens.rounding.extraLarge
            onClicked: root.expanded = !root.expanded
        }

        RowLayout {
            id: headerRow

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
                    fontStyle: Tokens.font.icon.small
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.label
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.description.length > 0
                    text: root.description
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }

            MaterialIcon {
                text: "expand_more"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
                rotation: root.expanded ? 180 : 0

                Behavior on rotation {
                    Anim { type: Anim.DefaultEffects }
                }
            }
        }
    }

    // Height is animated on the wrapper while the content itself keeps its
    // natural size, so expanding does not relayout the loaded content on
    // every frame of the transition.
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: root.expanded ? (bodyLoader.item?.implicitHeight ?? 0) + Tokens.padding.medium * 2 : 0
        clip: true
        visible: Layout.preferredHeight > 0

        Behavior on Layout.preferredHeight {
            Anim { type: Anim.Emphasized }
        }

        StyledRect {
            anchors.fill: parent
            color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)
            topLeftRadius: Tokens.rounding.extraSmall
            topRightRadius: Tokens.rounding.extraSmall
            bottomLeftRadius: Tokens.rounding.extraLarge
            bottomRightRadius: Tokens.rounding.extraLarge
        }

        Loader {
            id: bodyLoader

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium
            active: root.expanded
            asynchronous: root.source != ""
            source: root.content ? "" : root.source
            sourceComponent: root.content
        }
    }
}
