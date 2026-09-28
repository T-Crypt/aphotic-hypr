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
    // greetd ends a conversation itself when authentication fails; cancelling
    // it again would fail on the closed socket and bury the real message.
    property bool _sessionOpen: false
    // Consecutive automatic reopens. greetd rejecting the session over and
    // over used to shake the card on a 1.2s loop forever; after this many
    // the greeter stops and waits to be driven by hand again.
    property int _autoRetries: 0
    readonly property int _maxAutoRetries: 3

    signal shake

    function handleKey(event: var): void {
        // Typing is kept while greetd is busy; only submitting waits.
        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
            if (!root.waiting)
                root._submit();
        } else if (event.key === Qt.Key_Escape) {
            root._reset();
            root._autoRetries = 0;
        } else if (event.key === Qt.Key_Backspace) {
            if (event.modifiers & Qt.ControlModifier)
                root.buffer = "";
            else
                root.buffer = root.buffer.slice(0, -1);
        } else if (/^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text)) {
            // A keypress means someone is at the keyboard, so the automatic
            // reopening budget starts over.
            root._autoRetries = 0;
            root.errorText = "";
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
            root._sessionOpen = true;
            Greetd.createSession(root.username);
        } else if (root.phase === GreeterAuth.Phase.Authenticating) {
            root.waiting = true;
            Greetd.respond(root.buffer);
            root.buffer = "";
        }
    }

    function _reset(): void {
        if (Greetd.available && root._sessionOpen)
            Greetd.cancelSession();
        root._sessionOpen = false;
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
            if (error) {
                root.errorText = message;
                root.shake();
            }
        }

        function onAuthFailure(message: string): void {
            root._sessionOpen = false;
            root.errorText = qsTr("Incorrect password");
            root.shake();
            retryTimer.restart();
        }

        function onError(message: string): void {
            // A failed authentication is followed by a transport error from the
            // closed conversation; the failure message is the one that matters.
            if (retryTimer.running)
                return;
            root._sessionOpen = false;
            root.errorText = message;
            root.shake();
            retryTimer.restart();
        }

        function onReadyToLaunch(): void {
            root.phase = GreeterAuth.Phase.Launching;
            root.waiting = true;
            // `quit: true` hands the actual process teardown to Quickshell's
            // own greetd binding -- the wrapping throwaway Hyprland instance
            // (see Configs/greetd/hyprland-greeter.lua) exits right behind
            // it once this process exits, releasing the VT/DRM device
            // before greetd starts the real session's Hyprland fresh.
            Greetd.launch(["start-hyprland"], [], true);
        }
    }

    // After a failure greetd needs a brand-new conversation; this reopens
    // one for the same user once the error has had a moment on screen.
    Timer {
        id: retryTimer
        interval: 1200
        onTriggered: {
            if (root._autoRetries >= root._maxAutoRetries) {
                // greetd is refusing the session outright rather than asking
                // for another password. Stop reopening and let Enter drive it.
                root._reset();
                root.errorText = qsTr("The login was refused. Press Enter to try again.");
                return;
            }
            // Keep the name that was entered and open a fresh conversation,
            // so a mistyped password only needs the password again.
            const name = root.username;
            const typedAhead = root.buffer;
            root._reset();
            root.buffer = typedAhead;
            if (name.length > 0 && Greetd.available) {
                root._autoRetries += 1;
                root.username = name;
                root.waiting = true;
                root._sessionOpen = true;
                Greetd.createSession(name);
            }
        }
    }
}
