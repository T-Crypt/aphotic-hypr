import QtQuick
import qs.config
import qs.components

Item {
    id: root

    implicitWidth: Math.round(Tokens.font.body.large.pointSize * 1.2)
    implicitHeight: Math.round(Tokens.font.body.large.pointSize * 1.2)

    Logo {
        anchors.centerIn: parent
        implicitWidth: Math.round(Tokens.font.body.large.pointSize * 1.6)
        implicitHeight: Math.round(Tokens.font.body.large.pointSize * 1.6)
    }
}
