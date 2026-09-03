import QtQuick
import qs.config
import qs.components
import qs.components.effects
import qs.services

Item {
    id: root

    required property ScreenState screenState
    property color colour: Colours.palette.m3secondaryOnSurface
    // Full/Taskbar want the same background-chip treatment every other
    // entry (Clock/Tray/OsIcon/...) already has, so the agent icon has
    // its own visual boundary instead of blending into whatever's next
    // to it. Minimal is icon-only with no chips anywhere, so it opts out.
    property bool showBackground: true

    // Fall back to a plain empty object, not undefined -- `providers` is
    // legitimately empty when zero harness-hook plugins are installed
    // (see `visible` below), and property bindings below still evaluate
    // even while this item is invisible.
    readonly property var provider: AgentProviders.providers[AgentProviders.selectedIndex] ?? AgentProviders.providers[0] ?? ({})
    readonly property var stat: AgentProviders.stats[AgentProviders.selectedIndex] ?? AgentProviders.stats[0] ?? ({})
    readonly property int badgeCount: root.stat.sessionCount ?? 0

    // Absent, not hidden, when the installer's `ai` layer is off, or when
    // the `ai` layer is on but zero harness-hook plugins are installed+
    // enabled (AgentProviders.providers empty -- see that file's own
    // header) -- the bar shouldn't leave a gap where a feature the user
    // declined would go, and `root.provider` below is undefined once
    // `providers` is empty, so this guard is load-bearing, not cosmetic.
    visible: InstallProfile.aiEnabled && AgentProviders.providers.length > 0
    implicitWidth: !root.visible ? 0 : root.showBackground ? Settings.barInnerWidth : icon.implicitWidth
    implicitHeight: !root.visible ? 0 : root.showBackground ? Settings.barInnerWidth : icon.implicitHeight

    StyledRect {
        id: background

        visible: root.showBackground
        anchors.fill: parent
        radius: Tokens.rounding.full
        color: Colours.palette.m3surfaceContainerHigh
    }

    // Was targeting `background` (the full pill), declared BEFORE it in
    // z-order per BioluminescentGlow's normal "target hides the solid
    // core" contract -- on Minimal (showBackground: false), root's own
    // implicitWidth/Height collapse to icon.implicitWidth/Height, so
    // `background`'s anchors.fill: parent happened to end up icon-sized
    // there too, and the glow looked like a tight halo around the icon
    // purely by that coincidence. On Full/Taskbar, `background` is the
    // much bigger Settings.barInnerWidth pill every other bar entry uses,
    // so the exact same glow wrapped that instead -- and sat BELOW the
    // pill's own opaque fill in z-order, which hid all but a barely-
    // visible sliver of it regardless (confirmed live: still nearly
    // invisible even with intensity forced to 1). Targeting `icon`
    // directly and moving this above `background` (but still below
    // `icon`, so the glyph stays crisp on top of its own halo) makes the
    // glow consistently "a halo around the icon" on every bar style, and
    // actually visible against the background chip instead of hidden by
    // it.
    BioluminescentGlow {
        target: icon
        intensity: root.badgeCount > 0 ? DepthFx.glowIntensity : 0
        glowBlur: 20
        glowSpread: 0.3
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        animate: true
        text: root.provider.icon ?? ""
        color: root.colour
        fill: root.badgeCount > 0 ? 1 : 0
    }

    StyledRect {
        visible: root.badgeCount > 1

        anchors.top: icon.top
        anchors.right: icon.right
        anchors.topMargin: -Tokens.spacing.extraSmall / 2
        anchors.rightMargin: -Tokens.spacing.extraSmall / 2

        implicitWidth: Math.max(count.implicitWidth + Tokens.padding.extraSmall, Tokens.spacing.medium)
        implicitHeight: Tokens.spacing.medium
        radius: Tokens.rounding.full
        color: Colours.palette.m3primary

        StyledText {
            id: count

            anchors.centerIn: parent
            text: root.badgeCount > 9 ? "9+" : String(root.badgeCount)
            font: Tokens.font.label.small
            color: Colours.palette.m3onPrimary
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -Tokens.padding.small
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                root.screenState.agentPanel = !root.screenState.agentPanel;
            else if (mouse.button === Qt.RightButton)
                AgentProviders.launchSelected();
            else if (mouse.button === Qt.MiddleButton)
                AgentProviders.cycle();
        }
    }
}
