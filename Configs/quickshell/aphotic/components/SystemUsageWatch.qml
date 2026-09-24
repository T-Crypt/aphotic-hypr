import QtQuick
import qs.services

// Mount this for as long as a surface reads SystemUsage. Set detailed false
// when it only needs CPU and memory usage.
QtObject {
    id: root

    // Set at construction and never read live again: the registration is
    // latched at completion so a later write cannot leave an unpaired
    // end call behind, which is the whole reason this is an object
    // lifetime rather than a pair of calls in the first place.
    property bool detailed: true
    property bool fast: false

    property bool _detailedLatched: false
    property bool _fastLatched: false

    Component.onCompleted: {
        SystemUsage.subscribe();
        root._detailedLatched = root.detailed;
        if (root._detailedLatched) {
            SystemUsage.beginDetailedMonitoring();
            root._fastLatched = root.fast;
            if (root._fastLatched)
                SystemUsage.beginFastMonitoring();
        }
    }

    Component.onDestruction: {
        SystemUsage.unsubscribe();
        if (root._detailedLatched) {
            SystemUsage.endDetailedMonitoring();
            if (root._fastLatched)
                SystemUsage.endFastMonitoring();
        }
    }
}
