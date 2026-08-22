import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    readonly property string dotsDir: `${Quickshell.env("HOME")}/Aphotic-Hypr`

    property string doctorOutput: qsTr("Running aphotic doctor…")
    property string packageCheckOutput: ""
    property bool packageCheckRunning: false

    property string profileName: ""
    property string profileLayers: ""
    property string aurHelper: ""
    property string aphoticVersion: ""
    property string promptTool: ""

    function displayTemp(temp: real): string {
        return temp > 0 ? `${Math.ceil(Config.services.useFahrenheitPerformance ? temp * 1.8 + 32 : temp)}°${Config.services.useFahrenheitPerformance ? "F" : "C"}` : qsTr("N/A");
    }

    spacing: Tokens.spacing.largeIncreased

    Component.onCompleted: {
        doctorProc.running = true;
        tomlFile.reload();
        versionFile.reload();
        zshrcFile.reload();
    }

    // aphotic.toml is a small, fixed-shape file (see install.sh) -- plain
    // regexes on the raw text instead of a real TOML parser/dependency.
    FileView {
        id: tomlFile
        path: `${root.dotsDir}/aphotic.toml`
        onLoaded: {
            const t = text();
            root.profileName = (t.match(/profile\s*=\s*"([^"]*)"/) ?? [])[1] ?? qsTr("unknown");
            root.profileLayers = (t.match(/layers\s*=\s*\[([^\]]*)\]/) ?? [])[1]?.replace(/["\s]/g, "") ?? "";
            root.aurHelper = (t.match(/aur_helper\s*=\s*"([^"]*)"/) ?? [])[1] ?? qsTr("none");
        }
        onLoadFailed: {
            root.profileName = qsTr("unknown");
            root.aurHelper = qsTr("unknown");
        }
    }

    FileView {
        id: versionFile
        path: `${root.dotsDir}/VERSION`
        onLoaded: root.aphoticVersion = text().trim()
        onLoadFailed: root.aphoticVersion = qsTr("unknown")
    }

    // Detects which prompt tool the deployed .zshrc actually sources --
    // this repo ships both powerlevel10k and a starship package/config,
    // but only one is actually wired into .zshrc at a time.
    FileView {
        id: zshrcFile
        path: `${Quickshell.env("HOME")}/.zshrc`
        onLoaded: {
            const t = text();
            const p10kActive = /^\s*(source|\.)\s+.*powerlevel10k/m.test(t);
            const starshipActive = /^\s*eval\s+"\$\(starship init/m.test(t);
            root.promptTool = starshipActive ? "Starship" : p10kActive ? "Powerlevel10k" : qsTr("none detected");
        }
        onLoadFailed: root.promptTool = qsTr("unknown")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        StyledText {
            Layout.fillWidth: true
            text: qsTr("System")
            font: Tokens.font.title.large
        }

        StyledRect {
            Layout.preferredHeight: 28
            Layout.preferredWidth: refreshLabel.implicitWidth + Tokens.padding.medium * 2
            radius: Tokens.rounding.full
            color: Colours.tPalette.m3surfaceContainer

            StyledText {
                id: refreshLabel
                anchors.centerIn: parent
                text: qsTr("Refresh")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    doctorProc.running = true;
                    tomlFile.reload();
                    versionFile.reload();
                    zshrcFile.reload();
                }
            }
        }
    }

    StyledText {
        text: qsTr("Overview")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "palette"
            label: qsTr("Theme")
            description: Themes.activeWallpaper.length > 0 ? qsTr("%1 — %2").arg(Themes.activeThemeInfo?.displayName ?? Themes.activeTheme).arg(Themes.activeWallpaper) : (Themes.activeThemeInfo?.displayName ?? Themes.activeTheme)
        }

        SettingsRow {
            icon: "layers"
            label: qsTr("Install profile")
            description: root.profileLayers.length > 0 ? qsTr("%1 (layers: %2)").arg(root.profileName).arg(root.profileLayers) : root.profileName
        }

        SettingsRow {
            icon: "terminal"
            label: qsTr("Shell")
            description: qsTr("zsh — %1 prompt").arg(root.promptTool)
        }

        SettingsRow {
            icon: "dns"
            label: qsTr("Aphotic shell daemon")
            description: qsTr("Running — aphotic %1").arg(root.aphoticVersion)
        }

        SettingsRow {
            icon: "download"
            label: qsTr("AUR helper")
            description: root.aurHelper
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Hardware")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "memory"
            label: qsTr("CPU")
            description: SystemUsage.cpuName
            StyledText {
                text: qsTr("%1% · %2").arg(Math.round(SystemUsage.cpuPerc * 100)).arg(root.displayTemp(SystemUsage.cpuTemp))
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }

        SettingsRow {
            icon: "developer_board"
            label: qsTr("GPU")
            description: SystemUsage.gpuDetected ? SystemUsage.gpuName : qsTr("Not detected")
            StyledText {
                visible: SystemUsage.gpuDetected
                text: SystemUsage.gpuStatsAvailable ? qsTr("%1% · %2").arg(Math.round(SystemUsage.gpuPerc * 100)).arg(root.displayTemp(SystemUsage.gpuTemp)) : qsTr("N/A")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }

        SettingsRow {
            icon: "developer_board"
            label: qsTr("Memory")
            description: {
                const used = SystemUsage.formatKib(SystemUsage.memUsed);
                const total = SystemUsage.formatKib(SystemUsage.memTotal);
                return qsTr("%1 %2 / %3 %4").arg(used.value.toFixed(1)).arg(used.unit).arg(total.value.toFixed(1)).arg(total.unit);
            }
            StyledText {
                text: qsTr("%1%").arg(Math.round(SystemUsage.memPerc * 100))
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }

        Repeater {
            model: ScriptModel {
                values: SystemUsage.disks
            }

            SettingsRow {
                id: diskRow

                required property var modelData

                icon: "hard_drive"
                label: diskRow.modelData.mount
                description: {
                    const used = SystemUsage.formatKib(diskRow.modelData.used);
                    const total = SystemUsage.formatKib(diskRow.modelData.total);
                    return qsTr("%1 %2 / %3 %4").arg(used.value.toFixed(1)).arg(used.unit).arg(total.value.toFixed(1)).arg(total.unit);
                }

                StyledText {
                    text: qsTr("%1%").arg(Math.round(diskRow.modelData.perc * 100))
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Doctor")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    StyledRect {
        Layout.fillWidth: true
        // Sized to the text's own wrapped height (fixed height clipped
        // the bottom of longer doctor output instead of containing it) --
        // the outer pane already scrolls as a whole, so this just needs
        // to be exactly as tall as its content, not a guessed constant.
        Layout.preferredHeight: doctorText.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        StyledText {
            id: doctorText

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            font: Tokens.font.mono.small
            color: Colours.palette.m3onSurface
            text: root.doctorOutput
        }
    }

    Process {
        id: doctorProc
        command: ["aphotic", "doctor"]
        stdout: StdioCollector {
            onStreamFinished: root.doctorOutput = text.trim()
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    root.doctorOutput = text.trim();
            }
        }
    }

    RowLayout {
        Layout.topMargin: Tokens.spacing.small
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Package check")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        StyledText {
            visible: root.packageCheckRunning
            text: qsTr("Checking against Arch + AUR… this can take a minute or two")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        StyledRect {
            Layout.preferredHeight: 28
            Layout.preferredWidth: checkLabel.implicitWidth + Tokens.padding.medium * 2
            radius: Tokens.rounding.full
            color: Colours.tPalette.m3surfaceContainer
            opacity: root.packageCheckRunning ? 0.5 : 1

            StyledText {
                id: checkLabel
                anchors.centerIn: parent
                text: root.packageCheckRunning ? qsTr("Running…") : qsTr("Check packages")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                disabled: root.packageCheckRunning
            }

            MouseArea {
                anchors.fill: parent
                enabled: !root.packageCheckRunning
                onClicked: {
                    root.packageCheckRunning = true;
                    root.packageCheckOutput = "";
                    packageCheckProc.running = true;
                }
            }
        }
    }

    StyledText {
        visible: root.packageCheckOutput.length > 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        font: Tokens.font.mono.small
        color: Colours.palette.m3onSurface
        text: root.packageCheckOutput
    }

    // Every package referenced across profiles/*.toml gets two live HTTP
    // lookups (Arch repos + AUR) with a deliberate throttle between them
    // -- genuinely slow (a minute or more), which is exactly why this is
    // an explicit on-demand button rather than something that runs on
    // every pane open the way `aphotic doctor` does.
    Process {
        id: packageCheckProc
        command: ["python3", `${root.dotsDir}/scripts/check-packages.py`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.packageCheckOutput = text.trim();
                root.packageCheckRunning = false;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    root.packageCheckOutput = text.trim();
                root.packageCheckRunning = false;
            }
        }
    }
}
