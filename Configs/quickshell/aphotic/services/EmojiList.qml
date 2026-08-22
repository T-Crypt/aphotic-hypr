pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    readonly property list<var> entries: file.text().split("\n").filter(l => l.length > 0).map(l => {
        const sp = l.indexOf(" ");
        return sp >= 0 ? {
            emoji: l.slice(0, sp),
            name: l.slice(sp + 1)
        } : {
            emoji: l,
            name: l
        };
    })

    FileView {
        id: file
        path: Config.launcher.emojiListPath
    }
}
