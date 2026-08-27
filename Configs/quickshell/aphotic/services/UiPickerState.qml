pragma Singleton

import QtQuick

// Transient (never persisted) flag: true while Settings' Appearance pane
// or Theme Creator pane is the active category, so the wallpaper
// auto-cycle timer (services/WallpaperCycle.qml) can pause rather than
// fight the user mid-pick. Set/cleared by those panes' own
// Component.onCompleted/onDestruction, not owned by either one.
QtObject {
    property bool active: false
}
