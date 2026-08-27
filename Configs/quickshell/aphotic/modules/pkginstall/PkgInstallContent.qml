pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState

    readonly property bool open: root.screenState.pkgInstall
    readonly property int cardWidth: 560
    readonly property int cardHeight: 480

    implicitWidth: root.cardWidth
    implicitHeight: root.cardHeight
    width: root.implicitWidth
    height: root.implicitHeight

    state: root.open ? "open" : ""

    states: State {
        name: "open"
        PropertyChanges {
            card.opacity: 1
            card.scale: 1
        }
    }

    transitions: [
        Transition {
            from: ""
            to: "open"
            NumberAnimation {
                properties: "opacity,scale"
                duration: Tokens.anim.durations.small
                easing: Tokens.anim.emphasizedDecel
            }
        },
        Transition {
            from: "open"
            to: ""
            NumberAnimation {
                properties: "opacity,scale"
                duration: Tokens.anim.durations.expressiveFastEffects
                easing: Tokens.anim.emphasizedAccel
            }
        }
    ]

    onOpenChanged: {
        if (root.open) {
            searchInput.text = "";
            PkgSearch.setQuery("");
            searchInput.forceActiveFocus();
        }
    }

    StyledRect {
        id: card

        width: root.width
        height: root.height
        opacity: 0
        scale: 0.96
        transformOrigin: Item.Center

        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: 0.5
            shadowBlur: 0.5
            shadowVerticalOffset: 2
        }

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "search"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: searchInput.implicitHeight

                    TextInput {
                        id: searchInput

                        anchors.left: parent.left
                        anchors.right: parent.right
                        clip: true
                        font: Tokens.font.body.large
                        color: Colours.palette.m3onSurface

                        Keys.onEscapePressed: root.screenState.pkgInstall = false
                        Keys.onReturnPressed: {
                            if (list.currentItem)
                                list.currentItem.execute();
                        }
                        Keys.onDownPressed: list.incrementCurrentIndex()
                        Keys.onUpPressed: list.decrementCurrentIndex()

                        onTextChanged: PkgSearch.setQuery(text)
                    }

                    StyledText {
                        anchors.left: searchInput.left
                        anchors.right: searchInput.right
                        anchors.verticalCenter: searchInput.verticalCenter
                        elide: Text.ElideRight
                        text: qsTr("Search packages (official + AUR)…")
                        font: searchInput.font
                        color: Colours.palette.m3onSurfaceVariant
                        visible: searchInput.text.length === 0
                    }
                }

                MaterialIcon {
                    visible: PkgSearch.searching
                    text: "sync"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: PkgSearch.errorText.length > 0
                text: PkgSearch.errorText
                color: Colours.palette.m3error
                font: Tokens.font.body.small
                wrapMode: Text.Wrap
            }

            ListView {
                id: list

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Tokens.spacing.small
                currentIndex: 0

                model: ScriptModel {
                    values: PkgSearch.results
                    onValuesChanged: list.currentIndex = 0
                }

                highlight: StyledRect {
                    radius: Tokens.rounding.medium
                    color: Colours.palette.m3onSurface
                    opacity: 0.08
                }
                highlightFollowsCurrentItem: true

                delegate: PkgResultItem {
                    width: list.width
                    screenState: root.screenState
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: list.count === 0 && searchInput.text.trim().length > 0 && !PkgSearch.searching
                    text: qsTr("No results")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }
            }
        }
    }
}
