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
    readonly property bool fillViewport: true

    property bool showWallpaperPicker: false
    property bool showCommunityThemes: false

    // Lives on the pane rather than inside a page so the landing badge
    // and the Community Themes page read one fetch between them, and
    // navigating back and forth doesn't re-run the CLI each time.
    //
    // Names of downloaded themes that came from the community index
    // rather than shipping with Aphotic. Comes from `aphotic theme list
    // --json`'s `core` field (cmd_theme.sh) rather than a second copy of
    // APHOTIC_CORE_THEMES kept here, so the two never drift.
    property var communityNames: []
    // "Available to download", kept separate from the locally-scanned
    // Themes.themes grid so an available entry is never
    // indistinguishable from an already-downloaded theme.
    property var communityAvailable: []
    readonly property var communityFiltered: root.communityAvailable.filter(t => !Themes.themes.some(th => th.name === t.name))

    function refreshCommunity(): void {
        installedCoreProc.running = true;
        communityRemoteProc.running = true;
    }

    function downloadTheme(name: string): void {
        downloadProc.command = ["aphotic", "theme", "download", name];
        downloadProc.running = true;
    }

    Process {
        id: installedCoreProc
        command: ["aphotic", "theme", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.communityNames = JSON.parse(text).filter(t => !t.core).map(t => t.name);
                } catch (e) {
                    root.communityNames = [];
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
                    root.communityAvailable = JSON.parse(text);
                } catch (e) {
                    root.communityAvailable = [];
                }
            }
        }
    }

    // No enable/disable, no category filter, no security-trust gate here
    // -- those are plugin-specific concepts (see PluginsPane.qml) that
    // don't apply to a directory of wallpapers. Downloading runs as a
    // tracked Process (not a detached terminal like `aphotic plugin
    // install`) since a `cp -r` never needs an interactive AUR prompt.
    Process {
        id: downloadProc
        onExited: {
            Themes.rescan();
            root.refreshCommunity();
        }
    }

    Component.onCompleted: root.refreshCommunity()

    Loader {
        id: loader

        anchors.fill: parent
        sourceComponent: root.showWallpaperPicker ? wallpaperPickerComp : root.showCommunityThemes ? communityThemesComp : landingComp
    }

    Component {
        id: wallpaperPickerComp

        WallpaperPicker {
            onBack: root.showWallpaperPicker = false
        }
    }

    Component {
        id: communityThemesComp

        CommunityThemes {
            available: root.communityFiltered
            onBack: root.showCommunityThemes = false
            onDownload: name => root.downloadTheme(name)
        }
    }

    Component {
        id: landingComp

        ColumnLayout {
            id: landing

            spacing: Tokens.spacing.largeIncreased

            StyledText {
                text: qsTr("Appearance")
                font: Tokens.font.headline.builders.medium.weight(Font.DemiBold).build()
            }

            StyledText {
                text: qsTr("Theme").toUpperCase()
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
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
                        readonly property bool community: root.communityNames.includes(themeCard.modelData.name)

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 92
                        radius: Tokens.rounding.medium
                        color: Colours.signalStyle.raised
                        border.width: themeCard.active ? 2 : 1
                        border.color: themeCard.active ? Colours.palette.m3primary : Colours.signalStyle.hairline

                        readonly property string preview: themeCard.modelData.defaultWallpaper ? WallpaperThumbs.thumbFor(`${Themes.awwwDir}/${themeCard.modelData.name}/${themeCard.modelData.defaultWallpaper}`) : ""

                        Behavior on color {
                            CAnim {}
                        }

                        // Signal: each card previews its theme's own wallpaper.
                        StyledClippingRect {
                            anchors.fill: parent
                            anchors.margins: themeCard.border.width
                            visible: themeCard.preview.length > 0
                            radius: themeCard.radius - themeCard.border.width
                            color: "transparent"

                            Image {
                                anchors.fill: parent
                                source: themeCard.preview
                                sourceSize.width: 360
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                opacity: themeCard.active ? 0.8 : 0.45

                                Behavior on opacity {
                                    Anim { type: Anim.DefaultEffects }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient {
                                    GradientStop {
                                        position: 0.35
                                        color: "transparent"
                                    }
                                    GradientStop {
                                        position: 1
                                        color: Qt.alpha(Colours.signalStyle.base, 0.9)
                                    }
                                }
                            }
                        }

                        MaterialIcon {
                            visible: themeCard.active
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.margins: Tokens.padding.small
                            text: "check_circle"
                            fill: 1
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: Tokens.padding.medium
                            elide: Text.ElideRight
                            text: themeCard.modelData.displayName
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                        }

                        StyledText {
                            visible: false
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

            Item {
                id: communityRow

                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                Layout.preferredHeight: communityRowContent.implicitHeight

                SettingsRow {
                    id: communityRowContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    icon: "public"
                    label: qsTr("Community themes")
                    description: root.communityFiltered.length > 0 ? qsTr("%n available to download", "", root.communityFiltered.length) : qsTr("Nothing new to download right now")

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
                    onClicked: root.showCommunityThemes = true
                }
            }

            StyledText {
                visible: Themes.wallpapersInActiveTheme.length > 1
                Layout.topMargin: Tokens.spacing.small
                text: qsTr("Wallpaper").toUpperCase()
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
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
                        color: (wallpaperPill.active ? Qt.alpha(Colours.palette.m3primary, 0.16) : Colours.signalStyle.raised)
                        border.width: 1
                        border.color: wallpaperPill.active ? Colours.palette.m3primary : Colours.signalStyle.hairline

                        StyledText {
                            id: wallpaperLabel
                            anchors.centerIn: parent
                            width: wallpaperPill.width - Tokens.padding.large * 2
                            elide: Text.ElideMiddle
                            text: wallpaperPill.modelData
                            color: (wallpaperPill.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant)
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
                text: qsTr("Wallpaper Picker")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
            }

            SettingsGroup {
                Layout.fillWidth: true

                SettingsRow {
                    icon: "view_carousel"
                    label: qsTr("Launcher layout")
                    description: qsTr("How SUPER+W presents your wallpapers")

                    RowLayout {
                        spacing: Tokens.spacing.small

                        Repeater {
                            model: [
                                { id: "coverflow", label: qsTr("Coverflow") },
                                { id: "grid", label: qsTr("Grid") },
                                { id: "dock", label: qsTr("Dock") }
                            ]

                            StyledRect {
                                id: layoutPill

                                required property var modelData
                                readonly property bool active: layoutPill.modelData.id === Settings.wallpaperPickerLayout

                                Layout.preferredHeight: 28
                                Layout.preferredWidth: layoutLabel.implicitWidth + Tokens.padding.medium * 2
                                radius: Tokens.rounding.full
                                color: (layoutPill.active ? Qt.alpha(Colours.palette.m3primary, 0.16) : Colours.signalStyle.raised)
                                border.width: 1
                                border.color: layoutPill.active ? Colours.palette.m3primary : Colours.signalStyle.hairline

                                StyledText {
                                    id: layoutLabel
                                    anchors.centerIn: parent
                                    text: layoutPill.modelData.label
                                    color: (layoutPill.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant)
                                    font: Tokens.font.label.small
                                }

                                StateLayer {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    showHoverBackground: !layoutPill.active
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Settings.wallpaperPickerLayout = layoutPill.modelData.id
                                }
                            }
                        }
                    }
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
                                color: (intervalPill.active ? Qt.alpha(Colours.palette.m3primary, 0.16) : Colours.signalStyle.raised)
                                border.width: 1
                                border.color: intervalPill.active ? Colours.palette.m3primary : Colours.signalStyle.hairline

                                StyledText {
                                    id: intervalLabel
                                    anchors.centerIn: parent
                                    text: qsTr("%1m").arg(intervalPill.modelData)
                                    color: (intervalPill.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant)
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
