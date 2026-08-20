pragma Singleton
import QtQuick

QtObject {
    readonly property QtObject padding: QtObject {
        readonly property int small: 4
        readonly property int medium: 8
        readonly property int large: 12
        readonly property int extraLarge: 16
        readonly property int extraLargeIncreased: 20
    }

    readonly property QtObject spacing: QtObject {
        readonly property int small: 4
        readonly property int medium: 8
        readonly property int large: 12
    }

    readonly property QtObject radius: QtObject {
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 20
        readonly property int full: 9999
    }

    readonly property QtObject sizes: QtObject {
        readonly property QtObject bar: QtObject {
            readonly property int innerWidth: 48
        }
    }

    readonly property QtObject anim: QtObject {
        readonly property QtObject durations: QtObject {
            readonly property int small: 150
            readonly property int medium: 250
            readonly property int large: 350
        }
    }
}
