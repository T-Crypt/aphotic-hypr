// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton

import QtQuick
import Quickshell

// Fixed, and deliberately not the user's theme. Applying a theme
// rewrites the shell's own Colours.qml from a wallust/matugen template,
// so the palette is one of the things that can be broken when this
// screen is needed. Reading it here would put the recovery surface
// behind the same failure it exists to recover from.
//
// Properties avoid a bare `onXxx` shape (textColor, not onSurface): QML
// reserves any property identifier starting with "on" plus an uppercase
// letter for signal handlers.
Singleton {
    readonly property color background: "#101015"
    readonly property color surface: "#1b1b22"
    readonly property color surfaceRaised: "#24242d"
    readonly property color outline: "#3a3a46"
    readonly property color textColor: "#e8e5ed"
    readonly property color mutedTextColor: "#a5a2b0"
    readonly property color primary: "#a9c7ff"
    readonly property color primaryTextColor: "#00325a"
    readonly property color warningColor: "#ffd98a"
}
