pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.services

Singleton {
    id: root

    property list<NotifData> list: []
    readonly property list<NotifData> popups: list.filter(n => n.popup)

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        imageSupported: true

        onNotification: notif => {
            notif.tracked = true;
            const comp = notifComp.createObject(root, {
                popup: !DoNotDisturb.enabled,
                notification: notif
            });
            root.list = [comp, ...root.list];
        }
    }

    // A notification the shell raises itself rather than one that arrived
    // over the bus. NotifData only reads from `notification` when it has
    // one, so the properties set here survive, and the popup cannot tell
    // the two apart -- which is the point: one notification kind, one
    // place it is drawn.
    //
    // `actions` take the shape NotifData builds for a real notification,
    // `{identifier, text, invoke}`, plus an optional `icon` that only
    // these carry. `invoke` is a plain callable here instead of a D-Bus
    // round trip, so an action can run something in this process without
    // a client sitting on the other end waiting to be called back.
    function notify(summary: string, body: string, actions: var): void {
        const comp = notifComp.createObject(root, {
            popup: !DoNotDisturb.enabled,
            summary: summary,
            body: body,
            appName: "Aphotic",
            actions: actions ?? []
        });
        root.list = [comp, ...root.list];
    }

    IpcHandler {
        target: "notifs"

        function clear(): void {
            for (const notif of root.list.slice())
                notif.close();
        }
    }

    Component {
        id: notifComp

        NotifData {}
    }
}
