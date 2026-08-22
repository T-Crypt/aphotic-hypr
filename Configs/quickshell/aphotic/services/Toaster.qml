pragma Singleton
import QtQuick

// Hand-written no-op stand-in for Caelestia's native Toaster plugin type.
// Notifications aren't vendored in Phase 1 (see plan sub-phase 3, "Notifications
// — replaces Mako", not yet started) — this just keeps Audio.qml/Players.qml's
// existing toast() calls from being a hard QML resolution error until then.
QtObject {
    function toast(title: string, body: string, icon: string): void {}
}
