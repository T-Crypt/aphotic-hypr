import QtQuick

// Fixed-capacity record-the-last-N primitive, built once here because
// Gaming, Dev and Security all want the same "keep the last N of {stream},
// dump on {trigger}" shape (docs/APHOTIC_UNIFIED_VISION.md section 3.5).
// Not a singleton: a consumer instantiates one per stream it records.
//
// Preallocated slots plus a moving head, so push() is O(1) with no
// allocation and no array shift at capacity -- the difference matters
// because the intended consumers push on every frame/event of a stream,
// not once a second like a sparkline.
//
// Kept deliberately behind a narrow surface (push/dump/clear/at) so the
// decision to keep it in QML rather than a compiled core component stays
// reversible -- see the PR for this branch.
QtObject {
    id: root

    property int capacity: 256

    readonly property int count: root._count
    readonly property int dropped: root._dropped
    readonly property bool full: root._count >= root.capacity
    readonly property var newest: root._count > 0 ? root._slots[(root._head - 1 + root.capacity) % root.capacity] : null
    readonly property var oldest: root._count > 0 ? root._slots[(root._head - root._count + root.capacity) % root.capacity] : null

    property var _slots: new Array(root.capacity)
    property int _head: 0
    property int _count: 0
    property int _dropped: 0

    onCapacityChanged: root.clear()

    function push(value: var): void {
        if (root.capacity <= 0)
            return;
        root._slots[root._head] = value;
        root._head = (root._head + 1) % root.capacity;
        if (root._count < root.capacity)
            root._count = root._count + 1;
        else
            root._dropped = root._dropped + 1;
    }

    // Oldest to newest. Allocates -- a dump is the trigger-time operation,
    // not the hot path.
    function dump(): var {
        const out = [];
        const start = (root._head - root._count + root.capacity) % root.capacity;
        for (let i = 0; i < root._count; i++)
            out.push(root._slots[(start + i) % root.capacity]);
        return out;
    }

    // 0 is the oldest retained entry.
    function at(index: int): var {
        if (index < 0 || index >= root._count)
            return null;
        const start = (root._head - root._count + root.capacity) % root.capacity;
        return root._slots[(start + index) % root.capacity];
    }

    function clear(): void {
        root._slots = new Array(root.capacity);
        root._head = 0;
        root._count = 0;
        root._dropped = 0;
    }
}
