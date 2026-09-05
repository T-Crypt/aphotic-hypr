import QtQuick
import Quickshell.Services.Greetd

// The greetd analogue of qs.modules.lock/Pam.qml, but wired to greetd's own
// IPC/PAM relay (Quickshell.Services.Greetd's native binding) instead of a
// direct PamContext conversation -- greetd owns the whole PAM exchange
// itself under greetd's PAM service, and this process is not privileged to
// talk to PAM directly here (see docs/archive/BACKLOG.md's DM-02 entry).
// Same buffer/state/handleKey shape as Pam.qml on purpose, so GreeterContent
// mirrors LockContent's structure.
Item {
    id: root

    enum Phase {
        Username,
        Authenticating,
        Launching
    }

    property string username: ""
    property string buffer: ""
    property int phase: GreeterAuth.Phase.Username
    property string prompt: qsTr("Username")
    property bool maskInput: false
    property bool waiting: false
    property string errorText: ""

    signal shake

    function handleKey(event: var): void {
        if (root.waiting)
            return;

        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
            root._submit();
        } else if (event.key === Qt.Key_Escape) {
            root._reset();
        } else if (event.key === Qt.Key_Backspace) {
            if (event.modifiers & Qt.ControlModifier)
                root.buffer = "";
            else
                root.buffer = root.buffer.slice(0, -1);
        } else if (/^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text)) {
            root.buffer += event.text;
        }
    }

    function _submit(): void {
        if (!Greetd.available) {
            root.errorText = qsTr("greetd session not detected");
            root.shake();
            return;
        }

        if (root.phase === GreeterAuth.Phase.Username) {
            if (root.buffer.length === 0)
                return;
            root.username = root.buffer;
            root.buffer = "";
            root.waiting = true;
            root.errorText = "";
            Greetd.createSession(root.username);
        } else if (root.phase === GreeterAuth.Phase.Authenticating) {
            root.waiting = true;
            Greetd.respond(root.buffer);
            root.buffer = "";
        }
    }

    function _reset(): void {
        if (Greetd.available)
            Greetd.cancelSession();
        root.phase = GreeterAuth.Phase.Username;
        root.prompt = qsTr("Username");
        root.maskInput = false;
        root.buffer = "";
        root.waiting = false;
    }

    Connections {
        target: Greetd

        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            root.phase = GreeterAuth.Phase.Authenticating;
            root.prompt = message || qsTr("Password");
            root.maskInput = !echoResponse;
            root.waiting = !responseRequired;
            root.buffer = "";
            if (error) {
                root.errorText = message;
                root.shake();
            }
        }

        function onAuthFailure(message: string): void {
            root.errorText = message || qsTr("Authentication failed");
            root.shake();
            retryTimer.restart();
        }

        function onError(message: string): void {
            root.errorText = message;
            root.shake();
            retryTimer.restart();
        }

        function onReadyToLaunch(): void {
            root.phase = GreeterAuth.Phase.Launching;
            root.waiting = true;
            // `quit: true` hands the actual process teardown to Quickshell's
            // own greetd binding -- the wrapping throwaway Hyprland instance
            // (see Configs/greetd/hyprland-greeter.conf) exits right behind
            // it once this process exits, releasing the VT/DRM device
            // before greetd starts the real session's Hyprland fresh.
            Greetd.launch(["start-hyprland"], [], true);
        }
    }

    // Same 2.5s-then-retry shape as Pam.qml's stateReset, except a failure
    // here must also start a brand-new session (cancelSession + a fresh
    // createSession on next submit) -- greetd does not let a failed
    // conversation be resumed.
    Timer {
        id: retryTimer
        interval: 2500
        onTriggered: root._reset()
    }
}
