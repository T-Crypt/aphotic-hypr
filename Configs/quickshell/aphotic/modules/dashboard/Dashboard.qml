// Dashboard.qml -- resource-monitoring cards (CPU/GPU/memory/storage/network/battery)
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.config
import qs.components
import qs.services

Item {
    id: root

    // Main dashboard container
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    // Dashboard content
    RowLayout {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.medium
        visible: !placeholder.visible

        // Main column for performance metrics
        ColumnLayout {
            id: mainColumn

            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            // CPU and GPU row
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium
                visible: cpuCard.active || gpuCard.active

                // CPU Card
                Loader {
                    id: cpuCard

                    Layout.fillWidth: true
                    active: Config.dashboard.performance.showCpu

                    sourceComponent: HeroCard {
                        icon: "memory"
                        title: SystemUsage.cpuName ? `CPU - ${root.shortHwName(SystemUsage.cpuName)}` : qsTr("CPU")
                        mainValue: `${Math.round(SystemUsage.cpuPerc * 100)}%`
                        mainLabel: qsTr("Usage")
                        secondaryValue: root.displayTemp(SystemUsage.cpuTemp)
                        secondaryLabel: qsTr("Temp")
                        usage: SystemUsage.cpuPerc
                        temperature: SystemUsage.cpuTemp
                        accentColor: Colours.palette.m3primary
                    }
                }

                // GPU Card -- always rendered when enabled, even with no
                // GPU detected or no vendor stats tool installed, so the
                // grid never reflows depending on what's available: shows
                // "N/A" for usage/temp instead of hiding the card.
                Loader {
                    id: gpuCard

                    Layout.fillWidth: true
                    active: Config.dashboard.performance.showGpu

                    sourceComponent: HeroCard {
                        icon: "desktop_windows"
                        title: SystemUsage.gpuDetected ? `GPU - ${root.shortHwName(SystemUsage.gpuName)}` : qsTr("GPU")
                        mainValue: SystemUsage.gpuStatsAvailable ? `${Math.round(SystemUsage.gpuPerc * 100)}%` : qsTr("N/A")
                        mainLabel: qsTr("Usage")
                        secondaryValue: SystemUsage.gpuStatsAvailable ? root.displayTemp(SystemUsage.gpuTemp) : qsTr("N/A")
                        secondaryLabel: qsTr("Temp")
                        usage: SystemUsage.gpuStatsAvailable ? SystemUsage.gpuPerc : 0
                        temperature: SystemUsage.gpuStatsAvailable ? SystemUsage.gpuTemp : 0
                        accentColor: Colours.palette.m3secondary
                    }
                }
            }

            // Memory, Storage and Network row
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium
                visible: memoryCard.active || storageCard.active || networkCard.active

                // Memory Card
                Loader {
                    id: memoryCard

                    Layout.fillWidth: true
                    active: Config.dashboard.performance.showMemory
                    sourceComponent: GaugeCard {
                        icon: "memory_alt"
                        title: qsTr("Memory")
                        percentage: SystemUsage.memPerc
                        subtitle: {
                            const usedFmt = SystemUsage.formatKib(SystemUsage.memUsed);
                            const totalFmt = SystemUsage.formatKib(SystemUsage.memTotal);
                            return `${usedFmt.value.toFixed(1)} / ${Math.floor(totalFmt.value)} ${totalFmt.unit}`;
                        }
                        accentColor: Colours.palette.m3tertiary
                    }
                }

                // Storage Card
                Loader {
                    id: storageCard

                    Layout.fillWidth: true
                    active: Config.dashboard.performance.showStorage
                    sourceComponent: StorageGaugeCard {}
                }

                // Network Card
                Loader {
                    id: networkCard

                    Layout.fillWidth: true
                    active: Config.dashboard.performance.showNetwork
                    sourceComponent: NetworkCard {}
                }
            }
        }

        // Battery Tank (if applicable)
        Loader {
            Layout.fillWidth: false
            active: UPower.displayDevice.isLaptopBattery && Config.dashboard.performance.showBattery
            sourceComponent: BatteryTank {}
        }
    }

    // Placeholder when no widgets are enabled
    StyledRect {
        id: placeholder

        anchors.centerIn: parent
        width: 400
        height: 350
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer
        visible: !Config.dashboard.performance.showCpu &&
                 !(Config.dashboard.performance.showGpu && SystemUsage.gpuType !== "NONE") &&
                 !Config.dashboard.performance.showMemory &&
                 !Config.dashboard.performance.showStorage &&
                 !Config.dashboard.performance.showNetwork &&
                 !(UPower.displayDevice.isLaptopBattery && Config.dashboard.performance.showBattery)

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Tokens.spacing.medium

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "tune"
                fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).build()
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("No widgets enabled")
                font.pointSize: Tokens.fontSize.large
                color: Colours.palette.m3onSurface
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Enable widgets in dashboard settings")
                font.pointSize: Tokens.fontSize.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }

    // Function to display temperature with proper unit conversion
    function displayTemp(temp: real): string {
        return `${Math.ceil(Config.services.useFahrenheitPerformance ? temp * 1.8 + 32 : temp)}°${Config.services.useFahrenheitPerformance ? "F" : "C"}`;
    }

    // /proc/cpuinfo's "model name" (and most GPU name strings) are far too
    // long for a compact card header -- e.g. "11th Gen Intel(R) Core(TM)
    // i7-1195G7 @ 2.90GHz". Strip the marketing cruft real monitors also
    // drop (register-mark suffixes, clock speed) rather than relying on
    // mid-word ellipsis to hide it.
    function shortHwName(name: string): string {
        return name.replace(/\(R\)|\(TM\)|\(C\)/g, "").replace(/\s*@\s*[\d.]+\s*[GM]Hz/i, "").replace(/\s+/g, " ").trim();
    }

    // Components for dashboard cards
    component BatteryTank: StyledClippingRect {
        id: batteryTank

        implicitWidth: 140
        implicitHeight: 264

        property real percentage: UPower.displayDevice.percentage
        property bool isCharging: UPower.displayDevice.state === UPowerDeviceState.Charging
        property color accentColor: Colours.palette.m3primary
        property real animatedPercentage: 0

        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large
        Component.onCompleted: animatedPercentage = percentage
        onPercentageChanged: animatedPercentage = percentage

        // Background Fill
        StyledRect {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * batteryTank.animatedPercentage
            color: Qt.alpha(batteryTank.accentColor, 0.15)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small

            // Header Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: {
                        if (!UPower.displayDevice.isLaptopBattery) {
                            if (PowerProfiles.profile === PowerProfile.PowerSaver)
                                return "energy_savings_leaf";

                            if (PowerProfiles.profile === PowerProfile.Performance)
                                return "rocket_launch";

                            return "balance";
                        }
                        if (UPower.displayDevice.state === UPowerDeviceState.FullyCharged)
                            return "battery_full";

                        const perc = UPower.displayDevice.percentage;
                        const charging = [UPowerDeviceState.Charging, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state);
                        if (perc >= 0.99)
                            return "battery_full";

                        let level = Math.floor(perc * 7);
                        if (charging && (level === 4 || level === 1))
                            level--;

                        return charging ? `battery_charging_${(level + 3) * 10}` : `battery_${level}_bar`;
                    }
                    font.pointSize: Tokens.fontSize.large
                    color: batteryTank.accentColor
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Battery")
                    font.pointSize: Tokens.fontSize.normal
                    color: Colours.palette.m3onSurface
                }
            }

            Item {
                Layout.fillHeight: true
            }

            // Bottom Info Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: -4

                StyledText {
                    Layout.alignment: Qt.AlignRight
                    text: `${Math.round(batteryTank.percentage * 100)}%`
                    font.pointSize: Tokens.fontSize.extraLarge
                    font.weight: Font.Medium
                    color: batteryTank.accentColor
                }

                StyledText {
                    Layout.alignment: Qt.AlignRight
                    text: {
                        if (UPower.displayDevice.state === UPowerDeviceState.FullyCharged)
                            return qsTr("Full");

                        if (batteryTank.isCharging)
                            return qsTr("Charging");

                        const s = UPower.displayDevice.timeToEmpty;
                        if (s === 0)
                            return qsTr("...");

                        const hr = Math.floor(s / 3600);
                        const min = Math.floor((s % 3600) / 60);
                        if (hr > 0)
                            return `${hr}h ${min}m`;

                        return `${min}m`;
                    }
                    font.pointSize: Tokens.fontSize.smaller
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        Behavior on animatedPercentage {
            Anim {
                duration: Tokens.anim.durations.large
            }
        }
    }

    component CardHeader: RowLayout {
        property string icon
        property string title
        property color accentColor: Colours.palette.m3primary

        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: parent.icon
            fill: 1
            color: parent.accentColor
            fontStyle: Tokens.font.icon.large
        }

        StyledText {
            Layout.fillWidth: true
            text: parent.title
            font.pointSize: Tokens.fontSize.normal
            elide: Text.ElideRight
        }
    }

    component ProgressBar: StyledRect {
        id: progressBar

        property real value: 0
        property color fgColor: Colours.palette.m3primary
        property color bgColor: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
        property real animatedValue: 0

        color: bgColor
        radius: Tokens.rounding.full
        Component.onCompleted: animatedValue = value
        onValueChanged: animatedValue = value

        StyledRect {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * progressBar.animatedValue
            color: progressBar.fgColor
            radius: Tokens.rounding.full
        }

        Behavior on animatedValue {
            Anim {
                duration: Tokens.anim.durations.large
            }
        }
    }

    component HeroCard: StyledClippingRect {
        id: heroCard

        implicitWidth: 280
        implicitHeight: 130

        property string icon
        property string title
        property string mainValue
        property string mainLabel
        property string secondaryValue
        property string secondaryLabel
        property real usage: 0
        property real temperature: 0
        property color accentColor: Colours.palette.m3primary
        readonly property real maxTemp: 100
        readonly property real tempProgress: Math.min(1, Math.max(0, temperature / maxTemp))
        property real animatedUsage: 0
        property real animatedTemp: 0

        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large
        Component.onCompleted: {
            animatedUsage = usage;
            animatedTemp = tempProgress;
        }
        onUsageChanged: animatedUsage = usage
        onTempProgressChanged: animatedTemp = tempProgress

        StyledRect {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * heroCard.animatedUsage
            color: Qt.alpha(heroCard.accentColor, 0.15)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large
            anchors.topMargin: Tokens.padding.medium
            anchors.bottomMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            CardHeader {
                icon: heroCard.icon
                title: heroCard.title
                accentColor: heroCard.accentColor
            }

            RowLayout {
                id: statRow

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacing.medium

                Column {
                    Layout.alignment: Qt.AlignBottom
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Row {
                        spacing: Tokens.spacing.small

                        StyledText {
                            text: heroCard.secondaryValue
                            font.pointSize: Tokens.fontSize.normal
                            font.weight: Font.Medium
                        }

                        StyledText {
                            text: heroCard.secondaryLabel
                            font.pointSize: Tokens.fontSize.small
                            color: Colours.palette.m3onSurfaceVariant
                            anchors.baseline: parent.children[0].baseline
                        }
                    }

                    ProgressBar {
                        width: parent.width * 0.5
                        height: 6
                        value: heroCard.tempProgress
                        fgColor: heroCard.accentColor
                        bgColor: Qt.alpha(heroCard.accentColor, 0.2)
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }

        Column {
            id: mainStatColumn

            anchors.right: parent.right
            anchors.rightMargin: 32
            y: statRow.mapToItem(heroCard, 0, statRow.height / 2).y - height / 2
            spacing: 0

            StyledText {
                anchors.right: parent.right
                text: heroCard.mainLabel
                font.pointSize: Tokens.fontSize.normal
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                anchors.right: parent.right
                text: heroCard.mainValue
                font.pointSize: Tokens.fontSize.extraLarge
                font.weight: Font.Medium
                color: heroCard.accentColor
            }
        }

        Behavior on animatedUsage {
            Anim {
                duration: Tokens.anim.durations.large
            }
        }

        Behavior on animatedTemp {
            Anim {
                duration: Tokens.anim.durations.large
            }
        }
    }

    component GaugeCard: StyledRect {
        id: gaugeCard

        implicitWidth: 200
        implicitHeight: 200

        property string icon
        property string title
        property real percentage: 0
        property string subtitle
        property color accentColor: Colours.palette.m3primary
        readonly property real arcStartAngle: 0.75 * Math.PI
        readonly property real arcSweep: 1.5 * Math.PI
        property real animatedPercentage: 0

        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large
        clip: true
        Component.onCompleted: animatedPercentage = percentage
        onPercentageChanged: animatedPercentage = percentage

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.extraSmall

            CardHeader {
                icon: gaugeCard.icon
                title: gaugeCard.title
                accentColor: gaugeCard.accentColor
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Canvas {
                    id: gaugeCanvas

                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height)
                    height: width
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const cx = width / 2;
                        const cy = height / 2;
                        const radius = (Math.min(width, height) - 12) / 2;
                        const lineWidth = 10;
                        ctx.beginPath();
                        ctx.arc(cx, cy, radius, gaugeCard.arcStartAngle, gaugeCard.arcStartAngle + gaugeCard.arcSweep);
                        ctx.lineWidth = lineWidth;
                        ctx.lineCap = "round";
                        ctx.strokeStyle = Colours.layer(Colours.palette.m3surfaceContainerHigh, 2);
                        ctx.stroke();
                        if (gaugeCard.animatedPercentage > 0) {
                            ctx.beginPath();
                            ctx.arc(cx, cy, radius, gaugeCard.arcStartAngle, gaugeCard.arcStartAngle + gaugeCard.arcSweep * gaugeCard.animatedPercentage);
                            ctx.lineWidth = lineWidth;
                            ctx.lineCap = "round";
                            ctx.strokeStyle = gaugeCard.accentColor;
                            ctx.stroke();
                        }
                    }
                    Component.onCompleted: requestPaint()

                    Connections {
                        function onAnimatedPercentageChanged() {
                            gaugeCanvas.requestPaint();
                        }

                        target: gaugeCard
                    }

                    Connections {
                        function onPaletteChanged() {
                            gaugeCanvas.requestPaint();
                        }

                        target: Colours
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    text: `${Math.round(gaugeCard.percentage * 100)}%`
                    font.pointSize: Tokens.fontSize.extraLarge
                    font.weight: Font.Medium
                    color: gaugeCard.accentColor
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: gaugeCard.subtitle
                font.pointSize: Tokens.fontSize.smaller
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        Behavior on animatedPercentage {
            Anim {
                duration: Tokens.anim.durations.large
            }
        }
    }

    component StorageGaugeCard: StyledRect {
        id: storageGaugeCard

        implicitWidth: 200
        implicitHeight: 200

        property int currentDiskIndex: 0
        readonly property var currentDisk: SystemUsage.disks.length > 0 ? SystemUsage.disks[currentDiskIndex] : null
        property int diskCount: 0
        readonly property real arcStartAngle: 0.75 * Math.PI
        readonly property real arcSweep: 1.5 * Math.PI
        property real animatedPercentage: 0
        property color accentColor: Colours.palette.m3secondary

        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large
        clip: true
        Component.onCompleted: {
            diskCount = SystemUsage.disks.length;
            if (currentDisk)
                animatedPercentage = currentDisk.perc;
        }
        onCurrentDiskChanged: {
            if (currentDisk)
                animatedPercentage = currentDisk.perc;
        }

        // Update diskCount and animatedPercentage when disks data changes
        Connections {
            function onDisksChanged() {
                if (SystemUsage.disks.length !== storageGaugeCard.diskCount)
                    storageGaugeCard.diskCount = SystemUsage.disks.length;

                if (storageGaugeCard.currentDisk)
                    storageGaugeCard.animatedPercentage = storageGaugeCard.currentDisk.perc;
            }

            target: SystemUsage
        }

        MouseArea {
            anchors.fill: parent
            onWheel: wheel => {
                if (storageGaugeCard.diskCount === 0)
                    return;
                if (wheel.angleDelta.y > 0)
                    storageGaugeCard.currentDiskIndex = (storageGaugeCard.currentDiskIndex - 1 + storageGaugeCard.diskCount) % storageGaugeCard.diskCount;
                else if (wheel.angleDelta.y < 0)
                    storageGaugeCard.currentDiskIndex = (storageGaugeCard.currentDiskIndex + 1) % storageGaugeCard.diskCount;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.extraSmall

            CardHeader {
                icon: "hard_disk"
                title: {
                    const base = qsTr("Storage");
                    if (!storageGaugeCard.currentDisk)
                        return base;

                    return `${base} - ${storageGaugeCard.currentDisk.mount}`;
                }
                accentColor: storageGaugeCard.accentColor

                // Scroll hint icon
                MaterialIcon {
                    text: "unfold_more"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                    visible: storageGaugeCard.diskCount > 1
                    opacity: 0.7
                    ToolTip.visible: hintHover.hovered
                    ToolTip.text: qsTr("Scroll to switch disks")
                    ToolTip.delay: 500

                    HoverHandler {
                        id: hintHover
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Canvas {
                    id: storageGaugeCanvas

                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height)
                    height: width
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const cx = width / 2;
                        const cy = height / 2;
                        const radius = (Math.min(width, height) - 12) / 2;
                        const lineWidth = 10;
                        ctx.beginPath();
                        ctx.arc(cx, cy, radius, storageGaugeCard.arcStartAngle, storageGaugeCard.arcStartAngle + storageGaugeCard.arcSweep);
                        ctx.lineWidth = lineWidth;
                        ctx.lineCap = "round";
                        ctx.strokeStyle = Colours.layer(Colours.palette.m3surfaceContainerHigh, 2);
                        ctx.stroke();
                        if (storageGaugeCard.animatedPercentage > 0) {
                            ctx.beginPath();
                            ctx.arc(cx, cy, radius, storageGaugeCard.arcStartAngle, storageGaugeCard.arcStartAngle + storageGaugeCard.arcSweep * storageGaugeCard.animatedPercentage);
                            ctx.lineWidth = lineWidth;
                            ctx.lineCap = "round";
                            ctx.strokeStyle = storageGaugeCard.accentColor;
                            ctx.stroke();
                        }
                    }
                    Component.onCompleted: requestPaint()

                    Connections {
                        function onAnimatedPercentageChanged() {
                            storageGaugeCanvas.requestPaint();
                        }

                        target: storageGaugeCard
                    }

                    Connections {
                        function onPaletteChanged() {
                            storageGaugeCanvas.requestPaint();
                        }

                        target: Colours
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    text: storageGaugeCard.currentDisk ? `${Math.round(storageGaugeCard.currentDisk.perc * 100)}%` : "—"
                    font.pointSize: Tokens.fontSize.extraLarge
                    font.weight: Font.Medium
                    color: storageGaugeCard.accentColor
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: {
                    if (!storageGaugeCard.currentDisk)
                        return "—";

                    const usedFmt = SystemUsage.formatKib(storageGaugeCard.currentDisk.used);
                    const totalFmt = SystemUsage.formatKib(storageGaugeCard.currentDisk.total);
                    return `${usedFmt.value.toFixed(1)} / ${Math.floor(totalFmt.value)} ${totalFmt.unit}`;
                }
                font.pointSize: Tokens.fontSize.smaller
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        Behavior on animatedPercentage {
            Anim {
                duration: Tokens.anim.durations.large
            }
        }
    }

    component NetworkCard: StyledRect {
        id: networkCard

        implicitWidth: 220
        implicitHeight: 200

        property color accentColor: Colours.palette.m3primary

        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small

            CardHeader {
                icon: "swap_vert"
                title: qsTr("Network")
                accentColor: networkCard.accentColor
            }

            // Sparkline graph
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Canvas {
                    id: sparklineCanvas

                    property var downHistory: NetworkUsage.downloadBuffer.values
                    property var upHistory: NetworkUsage.uploadBuffer.values
                    property real targetMax: 1024
                    property real smoothMax: targetMax
                    property real slideProgress: 0
                    property int _tickCount: 0
                    property int _lastTickCount: -1

                    function checkAndAnimate(): void {
                        const currentLength = (downHistory || []).length;
                        if (currentLength > 0 && _tickCount !== _lastTickCount) {
                            _lastTickCount = _tickCount;
                            updateMax();
                        }
                    }

                    function updateMax(): void {
                        const downHist = downHistory || [];
                        const upHist = upHistory || [];
                        const allValues = downHist.concat(upHist);
                        targetMax = Math.max(...allValues, 1024);
                        requestPaint();
                    }

                    anchors.fill: parent
                    onDownHistoryChanged: checkAndAnimate()
                    onUpHistoryChanged: checkAndAnimate()
                    onSmoothMaxChanged: requestPaint()
                    onSlideProgressChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const w = width;
                        const h = height;
                        const downHist = downHistory || [];
                        const upHist = upHistory || [];
                        if (downHist.length < 2 && upHist.length < 2)
                            return;

                        const maxVal = smoothMax;

                        const drawLine = (history, color, fillAlpha) => {
                            if (history.length < 2)
                                return;

                            const len = history.length;
                            const stepX = w / (NetworkUsage.historyLength - 1);
                            const startX = w - (len - 1) * stepX - stepX * slideProgress + stepX;
                            ctx.beginPath();
                            ctx.moveTo(startX, h - (history[0] / maxVal) * h);
                            for (let i = 1; i < len; i++) {
                                const x = startX + i * stepX;
                                const y = h - (history[i] / maxVal) * h;
                                ctx.lineTo(x, y);
                            }
                            ctx.strokeStyle = color;
                            ctx.lineWidth = 2;
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            ctx.stroke();
                            ctx.lineTo(startX + (len - 1) * stepX, h);
                            ctx.lineTo(startX, h);
                            ctx.closePath();
                            ctx.fillStyle = Qt.rgba(Qt.color(color).r, Qt.color(color).g, Qt.color(color).b, fillAlpha);
                            ctx.fill();
                        };

                        drawLine(upHist, Colours.palette.m3secondary.toString(), 0.15);
                        drawLine(downHist, Colours.palette.m3tertiary.toString(), 0.2);
                    }

                    Component.onCompleted: updateMax()

                    Connections {
                        function onPaletteChanged() {
                            sparklineCanvas.requestPaint();
                        }

                        target: Colours
                    }

                    Timer {
                        interval: Config.dashboard.resourceUpdateInterval
                        running: true
                        repeat: true
                        onTriggered: sparklineCanvas._tickCount++
                    }

                    NumberAnimation on slideProgress {
                        from: 0
                        to: 1
                        duration: Config.dashboard.resourceUpdateInterval
                        loops: Animation.Infinite
                        running: true
                    }

                    Behavior on smoothMax {
                        Anim {
                            duration: Tokens.anim.durations.large
                        }
                    }
                }

                // "No data" placeholder
                StyledText {
                    anchors.centerIn: parent
                    text: qsTr("Collecting data...")
                    font.pointSize: Tokens.fontSize.small
                    color: Colours.palette.m3onSurfaceVariant
                    visible: NetworkUsage.downloadBuffer.values.length < 2
                    opacity: 0.6
                }
            }

            // Download row
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "download"
                    color: Colours.palette.m3tertiary
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    text: qsTr("Download")
                    font.pointSize: Tokens.fontSize.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    Layout.maximumWidth: 90
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                    text: {
                        const fmt = NetworkUsage.formatBytes(NetworkUsage.downloadSpeed ?? 0);
                        return fmt ? `${fmt.value.toFixed(1)} ${fmt.unit}` : "0.0 B/s";
                    }
                    font.pointSize: Tokens.fontSize.normal
                    font.weight: Font.Medium
                    color: Colours.palette.m3tertiary
                }
            }

            // Upload row
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "upload"
                    color: Colours.palette.m3secondary
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    text: qsTr("Upload")
                    font.pointSize: Tokens.fontSize.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    Layout.maximumWidth: 90
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                    text: {
                        const fmt = NetworkUsage.formatBytes(NetworkUsage.uploadSpeed ?? 0);
                        return fmt ? `${fmt.value.toFixed(1)} ${fmt.unit}` : "0.0 B/s";
                    }
                    font.pointSize: Tokens.fontSize.normal
                    font.weight: Font.Medium
                    color: Colours.palette.m3secondary
                }
            }

            // Session totals
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "history"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    text: qsTr("Total")
                    font.pointSize: Tokens.fontSize.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    Layout.maximumWidth: 110
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                    text: {
                        const down = NetworkUsage.formatBytesTotal(NetworkUsage.downloadTotal ?? 0);
                        const up = NetworkUsage.formatBytesTotal(NetworkUsage.uploadTotal ?? 0);
                        return (down && up) ? `↓${down.value.toFixed(1)}${down.unit} ↑${up.value.toFixed(1)}${up.unit}` : "↓0.0B ↑0.0B";
                    }
                    font.pointSize: Tokens.fontSize.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
}
