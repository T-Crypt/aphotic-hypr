pragma Singleton
import QtQuick
import qs.config

QtObject {
    id: root

    // No settings key yet: a later PR binds the config surface to these.
    property bool enabled: true
    property real speed: 1.0

    readonly property bool reducedMotion: !root.enabled || root.speed <= 0.25

    // The one place a duration is scaled and gated. Callers pass a raw token.
    function duration(base) {
        if (!root.enabled)
            return 1;

        // A token that did not resolve still has to return a duration: Qt stores a NaN
        // duration as 0 and logs nothing, so the animation would just disappear.
        let token = base;
        if (!Number.isFinite(token)) {
            console.warn(`aphotic motion: duration(${base}) is not a number, using the normal token`);
            token = Tokens.anim.durations.normal;
        }

        // A dial that is not a number cannot be clamped, so hold today's speed.
        const dial = Number(root.speed);
        const scale = Number.isNaN(dial) ? 1.0 : Math.max(0.05, Math.min(4.0, dial));
        return Math.max(1, Math.round(token * scale));
    }

    function snapOff() {
        root.enabled = false;
    }
}
