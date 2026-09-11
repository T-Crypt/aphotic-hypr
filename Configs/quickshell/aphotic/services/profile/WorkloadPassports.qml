pragma Singleton

import QtQuick
import Quickshell
import "Passports.js" as Passports

// The registry plane owners announce their work into. Flow reads it; it
// never writes to it.
//
// Nothing here touches ResourceEngine. A passport says what is running,
// a claim says what is held, and only the owner may end either one.
Singleton {
    id: root

    readonly property var live: root._live
    readonly property var closed: root._closed
    readonly property int liveCount: root._live.length
    readonly property int staleCount: root._live.filter(p => p.stale).length
    readonly property var stats: Passports.stats(root._state)

    // How long a source can go quiet before its work is marked stale. Long
    // enough that a slow adapter poll is not mistaken for a dead one.
    property int staleAfterMs: 90000

    signal opened(passport: var)
    signal changed(passport: var)
    signal staled(passport: var)
    signal ended(passport: var)

    property var _state: Passports.newState()
    property var _live: []
    property var _closed: []

    function open(payload: var): string {
        const result = Passports.open(root._state, payload, Date.now());
        if (!result.ok)
            return "";
        root._refresh();
        if (result.created)
            root.opened(result.passport);
        else if (result.changed)
            root.changed(result.passport);
        return result.token;
    }

    function heartbeat(token: string, claims: var): bool {
        const result = Passports.heartbeat(root._state, token, Date.now(), claims);
        if (!result.ok)
            return false;
        root._refresh();
        if (result.revived)
            root.changed(result.passport);
        return true;
    }

    function close(token: string, reason: string): bool {
        const result = Passports.close(root._state, token, reason, Date.now());
        if (!result.ok)
            return false;
        root._refresh();
        root.ended(result.passport);
        return true;
    }

    function closeOwner(owner: string, reason: string): int {
        const gone = Passports.closeOwner(root._state, owner, reason, Date.now());
        if (gone.length === 0)
            return 0;
        root._refresh();
        gone.forEach(passport => root.ended(passport));
        return gone.length;
    }

    // Staleness is discovered when a reader looks, not on a clock. The
    // substrate owns no timer: a source that went quiet while nothing was
    // watching is still quiet when something starts watching, and until
    // then nobody needed to know.
    function refresh(): int {
        const marked = Passports.sweep(root._state, Date.now(), root.staleAfterMs);
        if (marked.length === 0)
            return 0;
        root._refresh();
        marked.forEach(passport => root.staled(passport));
        return marked.length;
    }

    function ofOwner(owner: string): var {
        return Passports.ofOwner(root._state, owner);
    }

    function ofPlane(plane: string): var {
        return Passports.ofPlane(root._state, plane);
    }

    function reset(): void {
        root._state = Passports.newState();
        root._refresh();
    }

    function _refresh(): void {
        root._live = Passports.list(root._state);
        root._closed = Passports.history(root._state);
    }
}
