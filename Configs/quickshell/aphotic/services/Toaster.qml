pragma Singleton
import QtQuick
import Quickshell

// Real toasts via notify-send, the same convention every other
// notification in this repo already uses (Pomodoro.qml, PkgSearch.qml,
// Wallpapers.qml's engine-mismatch warning, areapicker/Picker.qml's
// screenshot toast). Notifs.qml's NotificationServer is a *receiver* for
// standard freedesktop notifications -- the same DBus door notify-send
// itself knocks on -- not something a QML caller can push a local toast
// into directly, so this goes out that door too rather than trying to
// synthesize a NotifData bypassing the server contract.
QtObject {
    function toast(title: string, body: string, icon: string): void {
        const args = ["notify-send", "-a", "aphotic"];
        if (icon)
            args.push("-i", icon);
        args.push(title, body);
        Quickshell.execDetached(args);
    }
}
