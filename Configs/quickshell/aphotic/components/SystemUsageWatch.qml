import QtQuick
import qs.services

// Mount this for as long as a surface showing SystemUsage's detailed
// stats (CPU temperature, GPU utilisation/temperature) is on screen.
// Object lifetime is the registration, so a surface behind a Loader
// cannot leak a watch by missing an unpaired call.
QtObject {
    id: root

    // Set at construction and never read live again: the registration is
    // latched at completion so a later write cannot leave an unpaired
    // end call behind, which is the whole reason this is an object
    // lifetime rather than a pair of calls in the first place.
    property bool fast: false

    property bool _fastLatched: false

    Component.onCompleted: {
        SystemUsage.beginDetailedMonitoring();
        root._fastLatched = root.fast;
        if (root._fastLatched)
            SystemUsage.beginFastMonitoring();
    }

    Component.onDestruction: {
        SystemUsage.endDetailedMonitoring();
        if (root._fastLatched)
            SystemUsage.endFastMonitoring();
    }
}
