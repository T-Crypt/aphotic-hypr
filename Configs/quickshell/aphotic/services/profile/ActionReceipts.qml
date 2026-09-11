pragma Singleton

import QtQuick
import Quickshell
import "Receipts.js" as Receipts

// Owner-confirmed record of what an action did. An owner files a request
// before it starts work and settles the same id when the operation
// returns, so a view can tell "asked for" apart from "happened".
Singleton {
    id: root

    readonly property var all: root._all
    readonly property var pending: root._all.filter(r => r.status === "requested")
    readonly property int pendingCount: root.pending.length
    readonly property var kinds: Receipts.KINDS
    readonly property var stats: Receipts.stats(root._state)

    signal filed(receipt: var)
    signal settled(receipt: var)

    property var _state: Receipts.newState()
    property var _all: []

    function request(input: var): string {
        const result = Receipts.request(root._state, input, Date.now());
        if (!result.ok)
            return "";
        root._refresh();
        root.filed(result.receipt);
        return result.id;
    }

    function applied(id: string, after: var): bool {
        return root._settle(Receipts.applied(root._state, id, after, Date.now()));
    }

    function failed(id: string, error: string): bool {
        return root._settle(Receipts.failed(root._state, id, error, Date.now()));
    }

    // `current` is what the value reads right now. If it is not what
    // Aphotic applied, the receipt records that the user's value was left
    // alone and the caller must not write over it.
    function restore(id: string, current: var): string {
        const result = Receipts.restore(root._state, id, current, Date.now());
        if (!result.ok)
            return "";
        root._refresh();
        root.settled(result.receipt);
        return result.action;
    }

    function restoreFailed(id: string, error: string): bool {
        return root._settle(Receipts.restoreFailed(root._state, id, error, Date.now()));
    }

    function byId(id: string): var {
        return Receipts.byId(root._state, id);
    }

    function forProfile(profileId: string): var {
        return Receipts.forProfile(root._state, profileId);
    }

    function forWorkload(workloadId: string): var {
        return Receipts.forWorkload(root._state, workloadId);
    }

    function label(receipt: var): string {
        return Receipts.label(receipt);
    }

    function exportText(): string {
        return Receipts.exportText(root._state);
    }

    function reset(): void {
        root._state = Receipts.newState();
        root._refresh();
    }

    function _settle(result: var): bool {
        if (!result.ok)
            return false;
        root._refresh();
        root.settled(result.receipt);
        return true;
    }

    function _refresh(): void {
        root._all = root._state.items.slice();
    }
}
