import QtQuick
import qs.services

// Mount this for as long as a surface reading NetworkUsage's live speeds
// is on screen. Object lifetime is the registration, same shape as
// SystemUsageWatch, so a surface behind a Loader cannot leak a watch by
// missing an unpaired call.
QtObject {
    Component.onCompleted: NetworkUsage.subscribe()
    Component.onDestruction: NetworkUsage.unsubscribe()
}
