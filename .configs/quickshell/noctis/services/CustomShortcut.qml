import QtQuick
import Quickshell.Hyprland

// Hand-written thin wrapper around Quickshell's own built-in Hyprland
// GlobalShortcut, replacing Caelestia's native-plugin-backed CustomShortcut
// (originally qs.components.misc). Same name/description/onPressed surface,
// so Brightness.qml/Players.qml need no changes beyond dropping that import
// (same-directory types resolve without one).
GlobalShortcut {
}
