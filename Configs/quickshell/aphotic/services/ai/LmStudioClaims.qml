pragma ComponentBehavior: Bound

import QtQuick

BackendClaims {
    id: root

    property var runningModels: []

    owner: "lm-studio"
    label: qsTr("LM Studio")
    models: root.runningModels ?? []
}
