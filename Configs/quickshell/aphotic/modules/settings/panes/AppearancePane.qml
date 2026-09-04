pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services
import qs.modules.settings

Item {
    id: root

    implicitWidth: loader.implicitWidth
    implicitHeight: loader.implicitHeight

    property bool showWallpaperPicker: false

    Loader {
        id: loader

        anchors.fill: parent
        sourceComponent: root.showWallpaperPicker ? wallpaperPickerComp : landingComp
    }

    Component {
        id: wallpaperPickerComp

        WallpaperPicker {
            onBack: root.showWallpaperPicker = false
        }
    }

    Component {
        id: landingComp

        ColumnLayout {
            id: landing

            spacing: Tokens.spacing.largeIncreased

            // Names of downloaded themes that came from the community
            // index rather than shipping with Aphotic -- badges the grid
            // below. Comes from `aphotic theme list --json`'s `core` field
            // (cmd_theme.sh) rather than a second copy of
            // APHOTIC_CORE_THEMES kept here, so the two never drift.
            property var communityNames: []
            // "Available to download" list, kept separate from the
            // locally-scanned Themes.themes grid so an available entry is
            // never indistinguishable from an already-downloaded theme.
            property var communityAvailable: []
            readonly property var communityFiltered: landing.communityAvailable.filter(t => !Themes.themes.some(th => th.name === t.name))

            function refreshCommunity(): void {
                installedCoreProc.running = true;
                communityRemoteProc.running = true;
            }

            Process {
                id: installedCoreProc
                command: ["aphotic", "theme", "list", "--json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            landing.communityNames = JSON.parse(text).filter(t => !t.core).map(t => t.name);
                        } catch (e) {
                            landing.communityNames = [];
                        }
                    }
                }
            }

            Process {
                id: communityRemoteProc
                command: ["aphotic", "theme", "list", "--remote", "--json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            landing.communityAvailable = JSON.parse(text);
                        } catch (e) {
                            landing.communityAvailable = [];
                        }
                    }
                }
            }

            // No enable/disable, no category filter, no security-trust
            // gate here -- those are plugin-specific concepts (see
            // PluginsPane.qml) that don't apply to a directory of
            // wallpapers. Downloading runs as a tracked Process (not a
            // detached terminal like `aphotic plugin install`) since a
            // `cp -r` never needs an interactive AUR prompt.
            Process {
                id: downloadProc
                onExited: {
                    Themes.rescan();
                    landing.refreshCommunity();
                }
            }

            Component.onCompleted: landing.refreshCommunity()

            StyledText {
                text: qsTr("Appearance")
                font: Tokens.font.title.large
            }

            StyledText {
                text: qsTr("Theme")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 3
                columnSpacing: Tokens.spacing.medium
                rowSpacing: Tokens.spacing.medium

                Repeater {
                    model: ScriptModel {
                        values: Themes.themes
                    }

                    StyledRect {
                        id: themeCard

                        required property var modelData
                        readonly property bool active: themeCard.modelData.name === Themes.activeTheme
                        readonly property bool community: landing.communityNames.includes(themeCard.modelData.name)

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 56
                        radius: Tokens.rounding.medium
                        color: themeCard.active ? Colours.layer(Colours.tPalette.m3surfaceContainer, 2) : Colours.tPalette.m3surfaceContainer
                        border.width: themeCard.active ? 2 : 0
                        border.color: Colours.palette.m3primary

                        Behavior on color {
                            CAnim {}
                        }

                        StyledText {
                            anchors.centerIn: parent
                            anchors.margins: Tokens.padding.small
                            width: parent.width - Tokens.padding.small * 2
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: themeCard.modelData.displayName
                            color: themeCard.active ? Colours.legibleAccent(Colours.palette.m3primary, themeCard.color) : Colours.palette.m3onSurface
                            font: Tokens.font.body.medium
                        }

                        MaterialIcon {
                            id: communityBadge

                            visible: themeCard.community
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: Tokens.padding.small
                            text: "public"
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small

                            ToolTip.visible: badgeHover.hovered
                            ToolTip.text: qsTr("Downloaded from the community theme index")
                            ToolTip.delay: 500

                            HoverHandler {
                                id: badgeHover
                            }
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            showHoverBackground: !themeCard.active
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (!themeCard.active)
                                    Themes.setTheme(themeCard.modelData.name, themeCard.modelData.defaultWallpaper);
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.topMargin: Tokens.spacing.small
                text: qsTr("Community Themes")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
            }

            StyledText {
                visible: landing.communityFiltered.length === 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: qsTr("Couldn't reach the aphotic-themes index (offline, or the repo isn't public yet).")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }

            Flow {
                Layout.fillWidth: true
                visible: landing.communityFiltered.length > 0
                spacing: Tokens.spacing.medium

                Repeater {
                    model: landing.communityFiltered

                    StyledRect {
                        id: communityCard

                        required property var modelData

                        width: 220
                        implicitHeight: communityCol.implicitHeight + Tokens.padding.large * 2
                        radius: Tokens.rounding.medium
                        color: Colours.tPalette.m3surfaceContainer

                        ColumnLayout {
                            id: communityCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.padding.large
                            spacing: Tokens.spacing.extraSmall

                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: communityCard.modelData.display_name
                                font: Tokens.font.body.medium
                            }

                            StyledText {
                                visible: (communityCard.modelData.description ?? "").length > 0
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                text: communityCard.modelData.description ?? ""
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }

                            StyledText {
                                Layout.topMargin: Tokens.spacing.extraSmall
                                text: qsTr("%1 wallpapers · %2").arg(communityCard.modelData.wallpaper_count ?? 0).arg(ModelStorage.formatBytes(communityCard.modelData.approx_size_bytes ?? 0))
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }

                            StyledRect {
                                Layout.topMargin: Tokens.spacing.small
                                Layout.alignment: Qt.AlignLeft
                                implicitWidth: downloadLabel.implicitWidth + Tokens.padding.large * 2
                                implicitHeight: 28
                                radius: Tokens.rounding.full
                                color: Colours.palette.m3primary

                                StyledText {
                                    id: downloadLabel
                                    anchors.centerIn: parent
                                    text: qsTr("Download")
                                    color: Colours.contrastOn(Colours.palette.m3primary)
                                    font: Tokens.font.label.small
                                }

                                StateLayer {
                                    anchors.fill: parent
                                    radius: parent.radius
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        downloadProc.command = ["aphotic", "theme", "download", communityCard.modelData.name];
                                        downloadProc.running = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: Themes.wallpapersInActiveTheme.length > 1
                Layout.topMargin: Tokens.spacing.small
                text: qsTr("Wallpaper")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
            }

            Flow {
                // A theme can hold more than one curated wallpaper -- a
                // RowLayout never wraps, so it just ran every pill off the
                // right edge of the panel once a theme had more than a
                // handful. Flow wraps onto more rows instead, and the
                // pane's own Flickable (see SettingsPanel.qml) already
                // scrolls for the height that adds.
                visible: Themes.wallpapersInActiveTheme.length > 1
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Repeater {
                    model: ScriptModel {
                        values: Themes.wallpapersInActiveTheme
                    }

                    StyledRect {
                        id: wallpaperPill

                        required property string modelData
                        readonly property bool active: wallpaperPill.modelData === Themes.activeWallpaper

                        // Layout.preferredWidth/Height only mean something
                        // inside a real Layout -- Flow sizes children from
                        // their own width/height instead, silently ignoring
                        // Layout.* attached properties. Capped at 160 (with
                        // the label eliding inside that) rather than
                        // growing to fit, since a sanitized fetch-extra
                        // filename can run long.
                        height: 32
                        width: Math.min(wallpaperLabel.implicitWidth + Tokens.padding.large * 2, 160)
                        radius: Tokens.rounding.full
                        color: wallpaperPill.active ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

                        StyledText {
                            id: wallpaperLabel
                            anchors.centerIn: parent
                            width: wallpaperPill.width - Tokens.padding.large * 2
                            elide: Text.ElideMiddle
                            text: wallpaperPill.modelData
                            color: wallpaperPill.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            showHoverBackground: !wallpaperPill.active
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Themes.setWallpaperInActiveTheme(wallpaperPill.modelData)
                        }
                    }
                }
            }

            Item {
                id: browseRow

                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                Layout.preferredHeight: rowContent.implicitHeight

                SettingsRow {
                    id: rowContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    icon: "grid_view"
                    label: qsTr("Browse all wallpapers")
                    description: qsTr("View every wallpaper across all themes")

                    MaterialIcon {
                        text: "chevron_right"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }
                }

                StateLayer {
                    anchors.fill: parent
                    radius: Tokens.rounding.extraLarge
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.showWallpaperPicker = true
                }
            }

            StyledText {
                Layout.topMargin: Tokens.spacing.small
                text: qsTr("Wallpaper Slideshow")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
            }

            SettingsGroup {
                Layout.fillWidth: true

                SettingsToggleRow {
                    icon: "slideshow"
                    label: qsTr("Auto-cycle wallpaper")
                    description: qsTr("Randomly advances within the active theme's wallpapers")
                    checked: Settings.wallpaperAutoCycleEnabled
                    onToggled: state => Settings.wallpaperAutoCycleEnabled = state
                }

                SettingsRow {
                    icon: "timer"
                    label: qsTr("Interval")
                    description: qsTr("Every %1 minutes").arg(Settings.wallpaperAutoCycleInterval)

                    RowLayout {
                        spacing: Tokens.spacing.small

                        Repeater {
                            model: [5, 15, 30, 60]

                            StyledRect {
                                id: intervalPill

                                required property int modelData
                                readonly property bool active: intervalPill.modelData === Settings.wallpaperAutoCycleInterval

                                Layout.preferredHeight: 28
                                Layout.preferredWidth: intervalLabel.implicitWidth + Tokens.padding.medium * 2
                                radius: Tokens.rounding.full
                                color: intervalPill.active ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                                StyledText {
                                    id: intervalLabel
                                    anchors.centerIn: parent
                                    text: qsTr("%1m").arg(intervalPill.modelData)
                                    color: intervalPill.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                }

                                StateLayer {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    showHoverBackground: !intervalPill.active
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Settings.wallpaperAutoCycleInterval = intervalPill.modelData
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
