import QtQuick
import qs.services

// Declares one piece of repeating work to Activity, next to the work
// itself. Hand it the Timer and it reports that timer's own `running`
// and `interval`, so what `aphotic runtime` shows is the real state, not
// a description of it. A host that is never constructed never reports,
// which is the honest answer for a module that is not loaded.
//
// tests/test_idle_cost.py fails any repeating Timer without one.
QtObject {
    id: root

    required property string name

    // What each wakeup does: poll (in-process work), file, process,
    // network or render. Display only.
    property string kind: "poll"

    property Timer timer: null
    property bool active: root.timer ? root.timer.running : false
    property int interval: root.timer ? root.timer.interval : 0

    Component.onCompleted: Activity.report(root)
    Component.onDestruction: Activity.forget(root)
}
