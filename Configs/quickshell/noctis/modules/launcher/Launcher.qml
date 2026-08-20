pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState

    implicitWidth: Tokens.sizes.launcher.width
    implicitHeight: search.implicitHeight + Tokens.padding.large * 3 + list.height

    visible: opacity > 0
    opacity: screenState.launcher ? 1 : 0

    Behavior on opacity {
        Anim {}
    }

    onVisibleChanged: {
        if (visible) {
            search.text = "";
            search.forceActiveFocus();
        }
    }

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainerHigh
    }

    Column {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.padding.large

        Item {
            width: parent.width
            height: search.implicitHeight

            TextInput {
                id: search

                anchors.left: parent.left
                anchors.right: parent.right
                clip: true

                font: Tokens.font.body.large
                color: Colours.palette.m3onSurface

                Keys.onEscapePressed: root.screenState.launcher = false
                Keys.onReturnPressed: {
                    const entry = list.currentItem?.modelData;
                    if (entry) {
                        entry.execute();
                        root.screenState.launcher = false;
                    }
                }
                Keys.onDownPressed: list.incrementCurrentIndex()
                Keys.onUpPressed: list.decrementCurrentIndex()
            }

            StyledText {
                anchors.left: search.left
                anchors.verticalCenter: search.verticalCenter
                text: qsTr("Search apps…")
                font: search.font
                color: Colours.palette.m3onSurfaceVariant
                visible: search.text.length === 0
            }
        }

        ListView {
            id: list

            readonly property int shown: Math.min(Tokens.sizes.launcher.maxShown, count)

            width: parent.width
            height: Tokens.sizes.launcher.itemHeight * shown + Tokens.spacing.small * Math.max(0, shown - 1)
            clip: true
            spacing: Tokens.spacing.small
            currentIndex: 0

            model: ScriptModel {
                values: {
                    const query = search.text.trim().toLowerCase();
                    const all = DesktopEntries.applications.values.filter(a => !a.noDisplay);
                    const filtered = query.length === 0 ? all : all.filter(a => a.name.toLowerCase().includes(query));
                    return filtered.sort((a, b) => a.name.localeCompare(b.name)).slice(0, Tokens.sizes.launcher.maxShown);
                }
                onValuesChanged: list.currentIndex = 0
            }

            highlight: StyledRect {
                radius: Tokens.rounding.medium
                color: Colours.palette.m3onSurface
                opacity: 0.08
            }
            highlightFollowsCurrentItem: true

            delegate: AppItem {
                screenState: root.screenState
            }
        }
    }
}
