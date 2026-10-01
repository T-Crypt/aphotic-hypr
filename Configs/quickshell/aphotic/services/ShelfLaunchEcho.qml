pragma Singleton
import QtQuick
import Quickshell
import qs.services
import "ShelfEchoPolicy.js" as Echo

// The launch echo. A shelf icon that launched an app answers once, when a
// window for that app actually appears -- not when the click was made, and
// never on a timer. A request expires on its own, so a launcher that
// fails silently produces no echo at all.
//
// The rule lives in ShelfEchoPolicy.js; this file holds the requests, the
// one key currently echoing, and the single timer that takes the echo back
// down. The timer exists only while an echo is on screen.
Singleton {
    id: root

    // Long enough for a cold start, short enough that a request from
    // minutes ago cannot echo into an unrelated window opening.
    readonly property int windowMs: 6000

    property var _requests: ({})

    // The key an edge should be drawing the answer for, empty when none.
    readonly property string echoing: root._echoing
    property string _echoing: ""

    Timer {
        id: clear
        interval: 800
        onTriggered: root._echoing = ""
    }

    // Called by the dock icon that launched something.
    function request(key: string): void {
        if (!Settings.shelfLaunchEcho)
            return;
        root._requests = Echo.record(root._requests,key,Date.now(),root.windowMs);
    }

    // Called once per window that appeared. Answers at most one request,
    // and consumes it, so a second window for the same app stays quiet.
    function observe(key: string): bool {
        if (!Settings.shelfLaunchEcho || !Echo.answerable(root._requests,key,Date.now(),root.windowMs))
            return false;
        root._requests = Echo.consume(root._requests,key);
        root._echoing = key;
        clear.restart();
        return true;
    }

    // Test/diagnostic hook.
    function pending(): var { return root._requests; }
}