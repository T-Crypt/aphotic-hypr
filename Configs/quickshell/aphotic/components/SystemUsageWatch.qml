import QtQuick
import qs.services

// Mount this for as long as a surface showing SystemUsage's detailed
// stats (CPU temperature, GPU utilisation/temperature) is on screen.
// Object lifetime is the registration, so a surface behind a Loader
// cannot leak a watch by missing an unpaired call.
QtObject {
    Component.onCompleted: SystemUsage.beginDetailedMonitoring()
    Component.onDestruction: SystemUsage.endDetailedMonitoring()
}
