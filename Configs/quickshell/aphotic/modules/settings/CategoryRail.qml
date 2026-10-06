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

    // Optional -- what the search box matches against when it has one, so
    // a plugin's pane stays reachable by name even though it renders as a
    // section inside another category's pane rather than as a rail entry
    // (see config/SettingsCategories.qml). Absent for reuse sites that
    // pass a plain category list with no search.
    property var searchIndex: [] // [{ id, icon, label, description, categoryId, sectionId }]

    // PluginsPane.qml reuses this component for its own much-shorter
    // category filter (7 fixed categories, no reason to search) rather
    // than duplicating the pill-list styling -- but the search box's
    // placeholder ("Search settings…") is real navigation-rail-specific
    // copy, and its ~48px pushed every category pill down by that much
    // with nothing equivalent on the neighboring "Browse available"
    // column, reading as visibly off-center between the two. Off by
    // default would break the main Settings rail's own search, so this
    // defaults true and only PluginsPane opts out.
    property bool showSearch: true

    signal categorySelected(id: string, sectionId: string)

    readonly property var groupOrder: [...new Set(root.categories.map(c => c.group ?? ""))]

    readonly property var _categoryEntries: root.categories.map(c => ({
        id: c.id,
        icon: c.icon,
        label: c.label,
        description: c.description ?? "",
        group: c.group ?? "",
        categoryId: c.id,
        sectionId: ""
    }))

    // Sections only ever appear as results, never at rest -- a rail that
    // listed them unprompted would be the long rail this design removes.
    readonly property var filteredCategories: {
        const q = searchInput.text.trim().toLowerCase();
        if (q.length === 0)
            return root._categoryEntries;
        const pool = root.searchIndex.length > 0 ? root.searchIndex : root._categoryEntries;
        return pool.filter(e => e.label.toLowerCase().includes(q) || (e.description ?? "").toLowerCase().includes(q));
    }

    spacing: Tokens.spacing.medium

    StyledRect {
        id: searchBox

        Layout.fillWidth: true
        Layout.preferredHeight: 36
        visible: root.showSearch
        radius: Tokens.rounding.full
        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

        GradedOutline {
            radius: searchBox.radius
            level: 2
            accent: searchInput.activeFocus
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: searchInput.forceActiveFocus()
        }

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
                // Enter opens the top match, so search works without the mouse.
                Keys.onReturnPressed: {
                    const hit = root.filteredCategories[0];
                    if (hit)
                        root.categorySelected(hit.categoryId, hit.sectionId ?? "");
                }

                StyledText {
                    visible: searchInput.text.length === 0
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Search settings…")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }

            MaterialIcon {
                visible: searchInput.text.length > 0
                text: "close"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small

                StateLayer {
                    anchors.fill: parent
                    anchors.margins: -Tokens.padding.extraSmall
                    radius: Tokens.rounding.full
                    onClicked: searchInput.text = ""
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

                        readonly property bool isSection: (categoryButton.modelData.sectionId ?? "").length > 0
                        readonly property bool active: !categoryButton.isSection && categoryButton.modelData.categoryId === root.currentCategory
                        readonly property bool isFirst: categoryButton.index === 0
                        readonly property bool isLast: categoryButton.index === root.filteredCategories.length - 1
                        readonly property color tint: Colours.signalStyle.tint(root.groupOrder.indexOf(categoryButton.modelData.group ?? ""))
                        // First entry of its group, at rest: carries the group header.
                        readonly property bool groupStart: !categoryButton.isSection && (categoryButton.modelData.group ?? "").length > 0 && (categoryButton.index === 0 || (root.filteredCategories[categoryButton.index - 1]?.group ?? "") !== categoryButton.modelData.group) && searchInput.text.trim().length === 0

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
                        Layout.leftMargin: (categoryButton.active ? Tokens.padding.extraSmall : 0) + (categoryButton.isSection ? Tokens.spacing.large : 0)
                        Layout.rightMargin: categoryButton.active ? Tokens.padding.extraSmall : 0
                        Layout.topMargin: (categoryButton.active ? Tokens.padding.extraSmall : 0) + (categoryButton.groupStart ? groupHeader.implicitHeight + Tokens.spacing.large - (categoryButton.index === 0 ? Tokens.spacing.medium : 0) : 0)
                        Layout.bottomMargin: categoryButton.active ? Tokens.padding.extraSmall : 0
                        implicitHeight: rowContent.implicitHeight + Tokens.padding.medium * 2

                        color: (categoryButton.active ? Qt.alpha(categoryButton.tint, 0.13) : "transparent")

                        topLeftRadius: Tokens.rounding.medium
                        topRightRadius: Tokens.rounding.medium
                        bottomLeftRadius: Tokens.rounding.medium
                        bottomRightRadius: Tokens.rounding.medium

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

                        GradedOutline {
                            topLeftRadius: categoryButton.topLeftRadius
                            topRightRadius: categoryButton.topRightRadius
                            bottomLeftRadius: categoryButton.bottomLeftRadius
                            bottomRightRadius: categoryButton.bottomRightRadius
                            showRim: categoryButton.active || stateLayer.containsMouse
                            accent: categoryButton.active
                            accentColour: categoryButton.tint
                            hovered: stateLayer.containsMouse
                        }

                        StyledText {
                            id: groupHeader

                            visible: categoryButton.groupStart
                            x: Tokens.padding.medium
                            y: -implicitHeight - Tokens.spacing.small
                            text: (categoryButton.modelData.group ?? "").toUpperCase()
                            color: Colours.palette.m3onSurfaceVariant
                            opacity: 0.75
                            font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
                        }

                        StyledRect {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: parent.height - Tokens.padding.small * 2
                            radius: Tokens.rounding.full
                            color: categoryButton.tint
                            opacity: categoryButton.active ? 1 : 0

                            Behavior on opacity {
                                Anim { type: Anim.DefaultEffects }
                            }
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
                                color: Qt.alpha(categoryButton.tint, categoryButton.active ? 0.32 : 0.18)

                                Behavior on color {
                                    CAnim {}
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: categoryButton.modelData.icon
                                    color: Colours.legibleAccent(categoryButton.tint, Colours.signalStyle.surface)
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
                                    color: !categoryButton.active ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface
                                    font: categoryButton.active ? Tokens.font.body.builders.medium.weight(Font.DemiBold).build() : Tokens.font.body.medium
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

                            onClicked: root.categorySelected(categoryButton.modelData.categoryId, categoryButton.modelData.sectionId ?? "")
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
