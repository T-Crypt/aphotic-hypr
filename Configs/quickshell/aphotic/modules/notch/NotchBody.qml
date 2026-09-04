pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property var tiles
    required property var pluginTiles
    required property bool switchable
    required property bool expanded
    required property string shownTileId
    required property var activeTile

    signal cycled
    signal dismissed
    signal picked(string id)

    onShownTileIdChanged: tileEnter.restart()

    // Duck-typed: a plugin tile may expose `property bool attention` to
    // say it has something the user needs to act on. Read off whichever
    // tiles happen to be loaded, so nothing here knows what any of them
    // are about.
    function attentionOf(id: string): bool {
        const count = pluginRepeater.count;
        for (let i = 0; i < count; i++) {
            const loader = pluginRepeater.itemAt(i);
            if (loader?.modelData?.id === id)
                return loader?.item?.attention === true;
        }
        return false;
    }

    readonly property var attentionIds: root.pluginTiles.filter(t => root.attentionOf(t.id)).map(t => t.id)

    spacing: Tokens.spacing.small

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 34
            radius: Tokens.rounding.medium
            color: "transparent"

            StateLayer {
                radius: parent.radius
                disabled: !root.expanded || !root.switchable
                onClicked: root.cycled()
            }

            RowLayout {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.spacing.small

                StyledRect {
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: Tokens.rounding.small
                    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: root.activeTile?.icon ?? "monitoring"
                        color: Colours.palette.m3primaryOnSurface
                        fontStyle: Tokens.font.icon.medium
                        fill: 1
                    }
                }

                StyledText {
                    text: root.activeTile?.label ?? ""
                    font: Tokens.font.title.builders.medium.weight(Font.Medium).build()
                }
            }
        }

        // "close", not an arrow: the hub opens from whichever edge the bar
        // is docked to, so there is no one direction a collapse points in.
        StyledRect {
            implicitWidth: 28
            implicitHeight: 28
            radius: Tokens.rounding.full
            color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

            StateLayer {
                radius: parent.radius
                disabled: !root.expanded
                onClicked: root.dismissed()
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: "close"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }
        }
    }

    Item {
        id: tileHost

        Layout.fillWidth: true
        Layout.preferredHeight: tileHost.shownItem?.implicitHeight ?? 0

        // The surface springs to the new tile's size; the tile itself
        // arrives into that space rather than being there the moment the
        // switch lands. Starts settled so nothing animates on startup.
        property real enterT: 1

        opacity: tileHost.enterT

        Anim {
            id: tileEnter

            target: tileHost
            property: "enterT"
            from: 0
            to: 1
            type: Anim.FastSpatial
        }

        readonly property Item shownItem: {
            if (root.shownTileId === "processes")
                return baseTileLoader;
            const count = pluginRepeater.count;
            const i = root.pluginTiles.findIndex(t => t.id === root.shownTileId);
            if (i < 0 || i >= count)
                return null;
            return pluginRepeater.itemAt(i);
        }

        Loader {
            id: baseTileLoader

            width: tileHost.width
            y: (1 - tileHost.enterT) * Tokens.spacing.medium
            active: root.shownTileId === "processes"
            visible: baseTileLoader.active

            sourceComponent: processComp
        }

        // Every gated-in plugin tile is built, not just the shown one: a
        // tile raising `attention` has to be able to say so while the
        // notch is collapsed and its own body is not on screen, which is
        // the whole point of a notch badge. No static import of any
        // plugin's QML -- `source` is a plain file:// URL out of the
        // registry, so the shell compiles and runs identically whether or
        // not a tile is installed.
        Repeater {
            id: pluginRepeater

            model: root.pluginTiles

            Loader {
                id: pluginTileLoader

                required property var modelData

                width: tileHost.width
                y: (1 - tileHost.enterT) * Tokens.spacing.medium
                asynchronous: true
                visible: root.shownTileId === pluginTileLoader.modelData.id
                source: pluginTileLoader.modelData.componentUrl
            }
        }
    }

    NotchSwitcher {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.extraSmall

        visible: root.switchable
        tiles: root.tiles
        currentId: root.shownTileId
        attentionIds: root.attentionIds
        interactive: root.expanded

        onPicked: id => root.picked(id)
    }

    Component {
        id: processComp
        NotchProcessTile {}
    }
}
