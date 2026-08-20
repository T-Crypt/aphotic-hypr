import QtQuick
import Quickshell
import qs.modules.bar

ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens

        BarWindow {}
    }
}
