pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property string currentCategory
    required property var categories // [{ id, icon, label, description }]

    signal categorySelected(id: string)

    readonly property var filteredCategories: {
        const q = searchInput.text.trim().toLowerCase();
        return q.length === 0 ? root.categories : root.categories.filter(c => c.label.toLowerCase().includes(q) || (c.description ?? "").toLowerCase().includes(q));
    }

    spacing: Tokens.spacing.medium

    StyledRect {
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Tokens.rounding.full
        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "search"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            TextInput {
                id: searchInput

                Layout.fillWidth: true
                clip: true
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurface

                Keys.onEscapePressed: searchInput.text = ""

                StyledText {
                    visible: searchInput.text.length === 0
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Search settings…")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }
        }
    }

    Item {
        id: listArea

        Layout.fillWidth: true
        Layout.fillHeight: true

        Flickable {
            id: listFlick

            anchors.fill: parent
            contentWidth: width
            contentHeight: list.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ColumnLayout {
                id: list

                width: listFlick.width
                spacing: 0

                Repeater {
                    model: ScriptModel {
                        values: root.filteredCategories
                    }

                    StyledRect {
                        id: categoryButton

                        required property var modelData
                        required property int index

                        readonly property bool active: categoryButton.modelData.id === root.currentCategory
                        readonly property bool isFirst: categoryButton.index === 0
                        readonly property bool isLast: categoryButton.index === root.filteredCategories.length - 1

                        Layout.fillWidth: true
                        // Inset on all sides while active, not just a color
                        // swap -- the active fill (m3secondaryContainer) is a
                        // genuinely different, much lighter color family than
                        // the near-black panel/row backdrop (tPalette.
                        // m3surfaceContainer and its layer(2) variant), so a
                        // full-bleed pill fully rounded to extraLarge cut away
                        // a big corner triangle that only ever revealed that
                        // mismatched dark backdrop -- reading as a black notch
                        // at each corner. Insetting means the reveal is even
                        // on every side, an intentional "floating pill" look
                        // instead of an accidental corner-only artifact.
                        Layout.leftMargin: categoryButton.active ? Tokens.padding.extraSmall : 0
                        Layout.rightMargin: categoryButton.active ? Tokens.padding.extraSmall : 0
                        Layout.topMargin: categoryButton.active ? Tokens.padding.extraSmall : 0
                        Layout.bottomMargin: categoryButton.active ? Tokens.padding.extraSmall : 0
                        implicitHeight: rowContent.implicitHeight + Tokens.padding.medium * 2

                        color: categoryButton.active ? Colours.palette.m3secondaryContainer : Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

                        topLeftRadius: stateLayer.pressed ? Tokens.rounding.medium : categoryButton.active ? Tokens.rounding.extraLarge : categoryButton.isFirst ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
                        topRightRadius: stateLayer.pressed ? Tokens.rounding.medium : categoryButton.active ? Tokens.rounding.extraLarge : categoryButton.isFirst ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
                        bottomLeftRadius: stateLayer.pressed ? Tokens.rounding.medium : categoryButton.active ? Tokens.rounding.extraLarge : categoryButton.isLast ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
                        bottomRightRadius: stateLayer.pressed ? Tokens.rounding.medium : categoryButton.active ? Tokens.rounding.extraLarge : categoryButton.isLast ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall

                        Behavior on color {
                            CAnim {}
                        }
                        Behavior on Layout.leftMargin {
                            Anim { type: Anim.DefaultEffects }
                        }
                        Behavior on Layout.rightMargin {
                            Anim { type: Anim.DefaultEffects }
                        }
                        Behavior on Layout.topMargin {
                            Anim { type: Anim.DefaultEffects }
                        }
                        Behavior on Layout.bottomMargin {
                            Anim { type: Anim.DefaultEffects }
                        }
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
                            id: rowContent

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.padding.large
                            spacing: Tokens.spacing.medium

                            StyledRect {
                                // Fixed size, matching SettingsRow's icon
                                // chip in the content pane (36x36, rounded
                                // square) instead of a full circle sized to
                                // the row's height -- keeps the nav rail's
                                // icon treatment visually consistent with the
                                // toggle rows next to it, and frees up
                                // horizontal space for the label/description
                                // text regardless of row height.
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                radius: Tokens.rounding.medium
                                color: categoryButton.active ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                                Behavior on color {
                                    CAnim {}
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: categoryButton.modelData.icon
                                    color: categoryButton.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSecondaryContainer
                                    fontStyle: Tokens.font.icon.builders.medium.weight(Font.Medium).build()
                                    fill: categoryButton.active ? 1 : 0
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: categoryButton.modelData.label
                                    font: Tokens.font.body.medium
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: (categoryButton.modelData.description ?? "").length > 0
                                    text: categoryButton.modelData.description ?? ""
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        StateLayer {
                            id: stateLayer

                            anchors.fill: parent
                            topLeftRadius: categoryButton.topLeftRadius
                            topRightRadius: categoryButton.topRightRadius
                            bottomLeftRadius: categoryButton.bottomLeftRadius
                            bottomRightRadius: categoryButton.bottomRightRadius
                            showHoverBackground: !categoryButton.active

                            onClicked: root.categorySelected(categoryButton.modelData.id)
                        }
                    }
                }
            }
        }

        StyledRect {
            id: railScrollThumb

            visible: listFlick.contentHeight > listFlick.height
            anchors.right: parent.right
            y: listFlick.visibleArea.yPosition * listFlick.height
            width: 3
            height: Math.max(24, listFlick.visibleArea.heightRatio * listFlick.height)
            radius: Tokens.rounding.full
            color: Colours.palette.m3onSurfaceVariant
            opacity: 0.35
        }
    }

    StyledText {
        visible: root.filteredCategories.length === 0
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.medium
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: qsTr("No matches")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }
}
