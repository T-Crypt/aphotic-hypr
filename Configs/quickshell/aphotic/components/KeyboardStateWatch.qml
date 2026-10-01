import QtQuick
import qs.services

QtObject {
    Component.onCompleted: Hypr.subscribeKeyboardState()
    Component.onDestruction: Hypr.unsubscribeKeyboardState()
}
