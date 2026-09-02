pragma Singleton
import QtQuick
import qs.services

// Single source of truth for "Aphotic Depth" tier behaviour -- every
// BioluminescentGlow/DepthLayer instance reads its intensity/particle count
// from here instead of re-deriving Settings.depthEffects itself, so the
// three tiers (off/subtle/full) and the one shared breathing cadence stay
// consistent across every surface that uses them.
QtObject {
    id: root

    readonly property bool enabled: Settings.depthEffects !== "off"
    readonly property bool full: Settings.depthEffects === "full"

    readonly property real glowIntensity: Settings.depthEffects === "full" ? 1 : Settings.depthEffects === "subtle" ? 0.5 : 0

    // The one "alive" cadence every breathing/pulsing element in the shell
    // shares -- ms for a single rise or fall half-cycle.
    readonly property int pulsePeriod: 2600

    readonly property int particleCount: Settings.depthEffects === "full" ? 26 : Settings.depthEffects === "subtle" ? 12 : 0

    // One clock for every breathing element, deliberately far below the
    // display's refresh rate.
    //
    // Each glow used to run its own infinite NumberAnimation on `opacity`,
    // and a QML animation ticks once per frame -- so any window holding
    // one repainted at the display rate forever, whether or not anything
    // had actually changed. Measured on an RTX 4090 with two 60 Hz
    // monitors, idle desktop: 2406 renders per 10 s across the shell's
    // four windows with those animations running, 276 with them stopped,
    // and they accounted for ~9 of the shell's ~18 points of idle GPU
    // (36.4% shipped, 27.3% with breathing off, 18.3% with no shell).
    //
    // Stepping one shared value instead caps the repaint rate at
    // `pulseRate` rather than the refresh rate. At 13 Hz the 2600 ms
    // half-cycle still gets ~34 steps, each moving a blurred glow's
    // opacity by about 0.016 -- below what reads as a step on a soft
    // shape, and the cosine ramp keeps the same ease-in-out shape the
    // two chained InOutSine animations had.
    readonly property int pulseRate: 13

    // 0..1..0 over a full rise+fall. Consumers map it onto their own
    // range rather than being driven directly, so a one-shot effect can
    // still ignore it entirely.
    property real pulse: 1

    property real _pulsePhase: 0

    readonly property Timer _pulseClock: Timer {
        interval: Math.round(1000 / root.pulseRate)
        running: root.glowIntensity > 0
        repeat: true
        onTriggered: {
            root._pulsePhase = (root._pulsePhase + interval / (root.pulsePeriod * 2)) % 1;
            root.pulse = 0.5 - Math.cos(root._pulsePhase * 2 * Math.PI) / 2;
        }
    }
}
