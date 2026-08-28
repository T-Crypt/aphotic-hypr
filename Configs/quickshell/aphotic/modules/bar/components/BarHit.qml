pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.services

// Shared along-axis hit-testing for the bar and everything docked in it.
//
// Nearest-centre rather than an exact rect test: childAt()-style testing
// returns nothing the instant the cursor sits in the (small but real) gap
// between two adjacent icons, which is exactly where a cursor travelling
// along a tightly-packed row spends much of its time. A miss used to leave
// the previous highlight/popout stuck until the cursor cleared the gap,
// reading as a jump rather than a clean move. Picking whichever child's
// centre is closest guarantees a hit everywhere, with the switch-over
// landing exactly at each pair's midpoint instead of in a dead zone.
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
