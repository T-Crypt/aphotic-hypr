"""Plugin API v3's overlay.present: a plugin presents its own manual
fullscreen overlay, and only its own.

A surface id is unique only within its plugin, so two plugins may both
declare an overlay called "deck". Presenting one must not present the
other, and a plugin without the grant gets no overlays handle at all.
"""
import json
import shutil

import pytest
from test_sonar_session import run_probe


def _plugin(api=None):
    entry = {
        "capabilities": ["ui-surface"],
        "ui": {"surfaces": [{"surface": "fullscreen-overlay", "id": "deck",
                             "component": "qml/Deck.qml", "trigger": "manual"}]},
    }
    if api is not None:
        entry["api"] = api
    return entry


def _seed(tmp_path):
    state = tmp_path / "home/.local/state/aphotic"
    state.mkdir(parents=True, exist_ok=True)
    installed = {
        "alpha": _plugin({"version": 3, "uses": ["overlay.present"]}),
        "beta": _plugin(),
        "gamma": _plugin({"version": 2, "uses": ["overlay.present"]}),
    }
    (state / "plugins.json").write_text(json.dumps({"installed": installed, "disabled": []}))


PROBE = """import QtQuick
import Quickshell
import qs.services
ShellRoot {
    id: root
    Timer {
        interval: 100; running: true; repeat: true
        property int ticks: 0
        onTriggered: {
            ticks++;
            if (!PluginRegistry.isInstalled("alpha") && ticks < 60) return;
            const overlays = PluginRegistry.surfacesFor("fullscreen-overlay");
            const of = p => overlays.find(s => s.plugin === p);
            const alpha = PluginApi.handle("alpha");
            const out = {
                alphaHasOverlays: !!(alpha && alpha.overlays),
                betaHasOverlays: !!(PluginApi.handle("beta") && PluginApi.handle("beta").overlays),
                gammaHasOverlays: !!(PluginApi.handle("gamma") && PluginApi.handle("gamma").overlays),
                unknownLocal: alpha && alpha.overlays ? alpha.overlays.present("nope") : null,
                presented: alpha && alpha.overlays ? alpha.overlays.present("deck") : null
            };
            out.alphaShown = FullscreenOverlays.presented(of("alpha"));
            out.betaShown = FullscreenOverlays.presented(of("beta"));
            FullscreenOverlays.dismiss(of("alpha"));
            out.alphaAfterDismiss = FullscreenOverlays.presented(of("alpha"));
            console.log("OVERLAY_PRESENT " + JSON.stringify(out));
            Qt.quit();
        }
    }
}
"""


@pytest.mark.skipif(shutil.which("qs") is None, reason="needs Quickshell (qs) to run the shell probe")
def test_overlay_present_is_scoped_to_the_owning_plugin(tmp_path):
    _seed(tmp_path)
    out = run_probe(tmp_path, PROBE, marker="OVERLAY_PRESENT", prefix="_overlay_present_")
    assert out["alphaHasOverlays"] is True
    assert out["betaHasOverlays"] is False, "a plugin without the grant must get no overlays handle"
    assert out["gammaHasOverlays"] is False, "overlay.present needs API v3"
    assert out["unknownLocal"] is False, "presenting an overlay the plugin does not own must fail"
    assert out["presented"] is True
    assert out["alphaShown"] is True
    assert out["betaShown"] is False, "another plugin's overlay with the same id must stay hidden"
    assert out["alphaAfterDismiss"] is False
