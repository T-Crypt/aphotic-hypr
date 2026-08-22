import QtQuick
import QtQuick.Layouts

// Wraps a static list of SettingsRow-family children (SettingsToggleRow,
// SettingsPresetRow, plain SettingsRow) and stamps first/last on each one
// automatically based on position, so they render as one connected card
// (see SettingsRow's own doc comment) without every call site having to
// compute that by hand.
ColumnLayout {
    id: root

    spacing: 0

    function _updatePositions(): void {
        const rows = root.children.filter(c => "first" in c && "last" in c);
        for (let i = 0; i < rows.length; i++) {
            rows[i].first = i === 0;
            rows[i].last = i === rows.length - 1;
        }
    }

    onChildrenChanged: root._updatePositions()
    Component.onCompleted: root._updatePositions()
}
