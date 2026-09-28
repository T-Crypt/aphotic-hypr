import QtQuick
import qs.config

// Shared open/close motion for shell surfaces. Bind the window's `visible`
// to `active`, not to the open flag, so the close animation plays before the
// surface unmaps.
Item {
    id: root

    property bool shown: false
    // "none", "top", "bottom", "left" or "right": the edge content travels in from.
    property string edge: "none"
    property real travel: Tokens.spacing.largeIncreased
    property real hiddenScale: 0.96

    property real progress: 0
    readonly property bool active: shown || progress > 0
    readonly property real visibleProgress: Math.max(0, Math.min(1, progress))

    // Entrance progress for the index-th child of a list, so rows cascade in
    // off the one shared animation instead of one timer per row.
    function staggered(index: int): real {
        const step = 0.06;
        const i = Math.min(Math.max(index, 0), 8);
        return Math.max(0, Math.min(1, (visibleProgress - i * step) / (1 - 8 * step)));
    }

    default property alias content: host.data

    implicitWidth: host.childrenRect.width
    implicitHeight: host.childrenRect.height

    Item {
        id: host

        anchors.fill: parent
        opacity: root.visibleProgress
        scale: root.hiddenScale + (1 - root.hiddenScale) * root.progress
        transform: Translate {
            readonly property real off: (1 - root.visibleProgress) * root.travel
            x: root.edge === "left" ? -off : root.edge === "right" ? off : 0
            y: root.edge === "top" ? -off : root.edge === "bottom" ? off : 0
        }
    }

    states: State {
        name: "shown"
        when: root.shown
        PropertyChanges {
            root.progress: 1
        }
    }

    transitions: [
        Transition {
            to: "shown"
            Anim {
                target: root
                property: "progress"
                type: Anim.FastSpatial
            }
        },
        Transition {
            from: "shown"
            Anim {
                target: root
                property: "progress"
                type: Anim.FastEffects
            }
        }
    ]
}
