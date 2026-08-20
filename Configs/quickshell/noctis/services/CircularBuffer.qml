import QtQuick

// Hand-written stand-in for Caelestia's native CircularBuffer plugin type
// (sparkline history buffer). Not used by any Phase 1 bar component — only
// exists so NetworkUsage.qml's existing bindings/push() calls resolve.
QtObject {
    property int capacity: 0
    property var values: []

    function push(value: real): void {
        values.push(value);
        if (values.length > capacity)
            values.shift();
    }
}
