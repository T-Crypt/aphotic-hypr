import QtQuick
import qs.services

// Mount this for as long as a surface showing per-process usage is on
// screen. Object lifetime is the registration, so a surface behind a
// Loader cannot leak a watch by missing an unpaired call.
QtObject {
    Component.onCompleted: ProcessUsage.beginSampling()
    Component.onDestruction: ProcessUsage.endSampling()
}
