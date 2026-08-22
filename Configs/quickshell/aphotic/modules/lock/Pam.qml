pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import Quickshell.Services.Pam

Item {
    id: root

    enum State {
        None,
        Error,
        MaxTries,
        Failed
    }

    required property WlSessionLock lock

    property string buffer
    property int state

    signal flashMsg

    function handleKey(event: var): void {
        if (passwd.active)
            return;

        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
            if (buffer.length > 0)
                passwd.start();
        } else if (event.key === Qt.Key_Backspace) {
            if (event.modifiers & Qt.ControlModifier)
                buffer = "";
            else
                buffer = buffer.slice(0, -1);
        } else if (/^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text)) {
            buffer += event.text;
        }
    }

    // Reuses the system's own swaylock PAM service (/etc/pam.d/swaylock,
    // which chains into login's real faillock-protected auth stack) —
    // deliberately not authoring a new PAM config for this.
    PamContext {
        id: passwd

        config: "swaylock"
        configDirectory: "/etc/pam.d"

        onResponseRequiredChanged: {
            if (!responseRequired)
                return;
            respond(root.buffer);
            root.buffer = "";
        }

        onCompleted: res => {
            if (res === PamResult.Success) {
                root.lock.locked = false;
                return;
            }

            if (res === PamResult.Error)
                root.state = Pam.Error;
            else if (res === PamResult.MaxTries)
                root.state = Pam.MaxTries;
            else
                root.state = Pam.Failed;

            root.flashMsg();
            stateReset.restart();
        }
    }

    Timer {
        id: stateReset
        interval: 4000
        onTriggered: {
            if (root.state !== Pam.MaxTries)
                root.state = Pam.None;
        }
    }

    Connections {
        function onSecureChanged(): void {
            if (root.lock.secure) {
                root.buffer = "";
                root.state = Pam.None;
            }
        }

        function onLockStateChanged(): void {
            if (!root.lock.locked)
                passwd.abort();
        }

        target: root.lock
    }
}
