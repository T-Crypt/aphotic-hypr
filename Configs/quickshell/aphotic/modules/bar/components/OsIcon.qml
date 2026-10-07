import QtQuick
import qs.config
import qs.components
import qs.services

StyledRect {
    id: root

    property QtObject _sonarTarget: Loader {
        active: Settings.sonarEnabled
        sourceComponent: EchoTarget {
            target: root
            targetId: "core:bar/osicon"
            label: qsTr("App launcher")
            action: "launcher"
            bindDescription: "Toggle app launcher"
            plugin: ""
            eligible: true
        }
    }

    implicitWidth: Settings.barInnerWidth
    implicitHeight: Settings.barInnerWidth

    color: "transparent"
    radius: Tokens.rounding.full

    AphoticMark {
        anchors.centerIn: parent
        width: root.implicitWidth - Tokens.padding.extraSmall * 2
        height: width
    }
}
