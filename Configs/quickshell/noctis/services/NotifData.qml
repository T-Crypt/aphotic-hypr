pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.config

QtObject {
    id: notif

    property bool popup
    property bool closed

    property Notification notification
    property string summary
    property string body
    property string appIcon
    property string appName
    property string image
    property real expireTimeout: GlobalConfig.notifs.defaultExpireTimeout
    property int urgency: NotificationUrgency.Normal
    property list<var> actions

    readonly property Timer timer: Timer {
        running: true
        interval: notif.expireTimeout > 0 ? notif.expireTimeout : GlobalConfig.notifs.defaultExpireTimeout
        onTriggered: notif.close()
    }

    readonly property Connections conn: Connections {
        function onClosed(): void {
            notif.close();
        }

        target: notif.notification
    }

    function close(): void {
        if (closed)
            return;
        closed = true;
        popup = false;
        Notifs.list = Notifs.list.filter(n => n !== notif);
        notif.notification?.dismiss();
        notif.destroy();
    }

    Component.onCompleted: {
        if (!notification)
            return;

        summary = notification.summary;
        body = notification.body;
        appIcon = notification.appIcon;
        appName = notification.appName;
        image = notification.image;
        expireTimeout = notification.expireTimeout;
        urgency = notification.urgency;
        actions = notification.actions.map(a => ({
                    identifier: a.identifier,
                    text: a.text,
                    invoke: () => a.invoke()
                }));
    }
}
