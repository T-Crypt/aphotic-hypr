import QtQuick

// Hand-written stand-in for Caelestia's native CavaProvider plugin type
// (audio visualiser bars). Not used by any Phase 1 bar component — see
// plan sub-phase 7, "caelestia's extra modules — dashboard/..." — only
// exists so Audio.qml's existing binding resolves.
QtObject {
    property int bars: 0
}
