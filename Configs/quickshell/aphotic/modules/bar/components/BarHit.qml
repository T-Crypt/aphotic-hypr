pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.services

// Shared along-axis hit-testing for the bar and everything docked in it.
//
// Contains-test FIRST, nearest-centre only as a gap fallback: a pure
// nearest-centre test (this function's original, and still-simplest,
// form) works fine when every candidate is roughly the same size --
// individual icons within one pill, workspace cells -- because the
// switch-over point between two similarly-sized neighbours naturally
// lands close to the real boundary between them. It breaks down hard
// when candidates vary wildly in size, which is exactly Bar.qml's own
// top-level entry list (childAlong): a compact ~40px "agent" entry
// sitting right above a ~300px+ "statusIcons" entry has its OWN centre
// close enough to its own edge that it stays the nearest centre for a
// long stretch INSIDE statusIcons' own bounds -- not just in the real
// gap between them. Confirmed live and instrumented: hovering the top
// of the statusIcons pill (where the network/bluetooth icons actually
// are) kept resolving to "agent" (no popout) for roughly the first
// third of statusIcons' own height, only correctly resolving to
// statusIcons once far enough down that ITS centre finally won -- which
// happened to land right around the VPN icon. Reported live as
// "network and bluetooth don't pop out, but VPN and host info do" and
// "doesn't trigger until reaching the VPN icon coming down" -- an exact
// match, not a guess; verified via added debug logging plus a scripted
// ydotool sweep before this fix, not assumed from the bug report alone.
//
// Fix: check every candidate's own bounds first (a real contains test).
// Only fall back to nearest-centre when pos genuinely isn't inside any
// candidate -- the real "gap between two adjacent icons" case this
// function was originally built for, which still needs the fallback
// since childAt()-style testing returns nothing there.
//
// Bar.qml, TaskbarBar.qml and StatusIcons.qml each carried their own copy
// of this; they now share one so the switch-over point -- half of what
// "the same hover feel" means -- can't drift between bar styles.
QtObject {
    // pos is along the bar's length, in `container`'s own coordinate space.
    function nearestAlong(container: Item, pos: real): var {
        if (!container)
            return null;

        let best = null;
        let bestDist = Infinity;
        for (const child of container.children) {
            const size = Settings.barHorizontal ? child.width : child.height;
            if (size <= 0 || !child.visible)
                continue;
            const start = Settings.barHorizontal ? child.x : child.y;
            // Real contains test wins outright, regardless of how close
            // some OTHER child's centre might be -- this is what stops a
            // small neighbour's centre from reaching into a much larger
            // entry's own bounds.
            if (pos >= start && pos < start + size)
                return child;
            const dist = Math.abs(start + size / 2 - pos);
            if (dist < bestDist) {
                bestDist = dist;
                best = child;
            }
        }
        return best;
    }

    // Same, but resolved from a point in `container`'s coordinates rather
    // than a bare along-axis offset.
    function nearestAt(container: Item, x: real, y: real): var {
        return nearestAlong(container, Settings.barHorizontal ? x : y);
    }
}
