pragma ComponentBehavior: Bound

import qs.services
import Quickshell
import QtQuick

Scope {
    id: root

    readonly property var windows: overlayLoader.item?.instances ?? []

    Loader {
        id: overlayLoader

        active: Sonar.active
        sourceComponent: Variants {
            model: Quickshell.screens
            delegate: SonarWindow {}
        }
    }
}
