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
}
