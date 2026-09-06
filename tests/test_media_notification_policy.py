import json
import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "Configs/quickshell/aphotic/utils/MediaNotifications.js"


def run_policy(expression: str):
    script = f"""
const fs = require("fs");
const vm = require("vm");
const context = {{}};
vm.createContext(context);
vm.runInContext(fs.readFileSync({json.dumps(str(POLICY))}, "utf8"), context);
process.stdout.write(JSON.stringify({expression}));
"""
    result = subprocess.run(
        ["node", "-e", script],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def player(*, playing=True, title="Track", artist="Artist", url=""):
    return {
        "isPlaying": playing,
        "uniqueId": 7,
        "trackTitle": title,
        "trackArtist": artist,
        "desktopEntry": "firefox",
        "identity": "Firefox",
        "metadata": {"xesam:url": url},
    }


def test_metadata_without_audible_output_cannot_notify():
    value = json.dumps(player(url="https://www.youtube.com/watch?v=abcdefghijk"))

    assert run_policy(f"context.shouldNotify({value}, false, '', 'Firefox')") is False


def test_paused_player_cannot_notify_even_with_audible_output():
    value = json.dumps(player(playing=False))

    assert run_policy(f"context.shouldNotify({value}, true, '', 'Firefox')") is False


def test_audible_playing_track_notifies_once():
    value = json.dumps(player())
    key = run_policy(f"context.trackKey({value}, 'Firefox')")

    assert run_policy(f"context.shouldNotify({value}, true, '', 'Firefox')") is True
    assert run_policy(f"context.shouldNotify({value}, true, {json.dumps(key)}, 'Firefox')") is False


def test_stream_must_be_ready_unmuted_and_match_the_player():
    firefox = {
        "ready": True,
        "audio": {"muted": False, "volume": 0.8},
        "properties": {
            "application.name": "Firefox",
            "application.process.binary": "firefox",
        },
    }
    muted = {**firefox, "audio": {"muted": True, "volume": 0.8}}
    chromium = {
        **firefox,
        "properties": {
            "application.name": "Chromium",
            "application.process.binary": "chromium",
        },
    }
    pvalue = json.dumps(player())

    assert run_policy(f"context.streamIsAudible({json.dumps(firefox)}, 0.02, 0.001)") is True
    assert run_policy(f"context.streamIsAudible({json.dumps(muted)}, 0.02, 0.001)") is False
    assert run_policy(f"context.streamMatchesPlayer({json.dumps(firefox)}, {pvalue}, 'Firefox')") is True
    assert run_policy(f"context.streamMatchesPlayer({json.dumps(chromium)}, {pvalue}, 'Firefox')") is False


def test_similarly_named_app_cannot_satisfy_player_match():
    chromium_game = {
        "ready": True,
        "type": 21,
        "audio": {"muted": False, "volume": 0.8},
        "properties": {
            "application.name": "Chromium B.S.U.",
            "application.process.binary": "chromium-bsu",
        },
    }
    value = json.dumps({**player(), "identity": "Chromium", "desktopEntry": "chromium"})

    assert run_policy(f"context.streamMatchesPlayer({json.dumps(chromium_game)}, {value}, 'Chromium')") is False


def test_audible_output_selection_rejects_inactive_and_input_streams():
    base = {
        "ready": True,
        "type": 21,
        "audio": {"muted": False, "volume": 0.8},
        "properties": {"application.name": "Firefox"},
    }
    cases = [
        [{"modelData": {**base, "ready": False}, "peak": 0.02}, False],
        [{"modelData": {**base, "audio": {"muted": False, "volume": 0}}, "peak": 0.02}, False],
        [{"modelData": base, "peak": 0}, False],
        [{"modelData": {**base, "type": 5}, "peak": 0.02}, False],
        [{"modelData": {**base, "type": 13}, "peak": 0.02}, False],
        [{"modelData": base, "peak": 0.02}, True],
    ]
    pvalue = json.dumps(player())

    for monitor, expected in cases:
        assert run_policy(
            f"context.hasAudibleOutput({pvalue}, [{json.dumps(monitor)}], 0.001, 'Firefox', 21)"
        ) is expected


def test_youtube_urls_prefer_the_youtube_identity():
    for url in (
        "https://www.youtube.com/watch?v=abcdefghijk",
        "https://music.youtube.com/watch?v=abcdefghijk",
        "https://youtu.be/abcdefghijk",
    ):
        value = json.dumps(player(url=url))
        source = run_policy(f"context.sourceFor({value}, 'Firefox')")

        assert source == {
            "name": "YouTube",
            "iconCandidates": ["youtube", "youtube-app", "firefox", "Firefox"],
        }


def test_other_browser_sites_use_hostname_then_player_fallbacks():
    value = json.dumps(player(url="https://open.spotify.com/track/example"))

    assert run_policy(f"context.sourceFor({value}, 'Firefox')") == {
        "name": "Spotify",
        "iconCandidates": ["spotify", "firefox", "Firefox"],
    }


def test_compound_public_suffix_uses_the_site_name():
    value = json.dumps(player(url="https://www.bbc.co.uk/sounds/play/example"))

    assert run_policy(f"context.sourceFor({value}, 'Firefox')") == {
        "name": "Bbc",
        "iconCandidates": ["bbc", "firefox", "Firefox"],
    }


def test_icon_selection_uses_the_first_available_fallback():
    assert run_policy(
        "context.firstAvailableIcon(['unknown-site', 'firefox', 'Firefox'], value => value === 'firefox', 'music_note')"
    ) == "firefox"


def test_source_identity_reaches_notify_send(tmp_path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    log = tmp_path / "notify-args"
    notify_send = fake_bin / "notify-send"
    notify_send.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$TOAST_LOG"\n')
    notify_send.chmod(0o755)

    qml_root = ROOT / "Configs/quickshell/aphotic"
    runtime_dir = tmp_path / "runtime"
    runtime_dir.mkdir(mode=0o700)
    probe = tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".qml",
        prefix="_media_notification_",
        dir=qml_root,
        delete=False,
    )
    try:
        probe.write(
            """import QtQuick
import Quickshell
import qs.services

ShellRoot {
    Component.onCompleted: Toaster.toastFrom("YouTube", "Now Playing", "Artist - Track", "youtube")
}
"""
        )
        probe.close()
        env = os.environ.copy()
        env["PATH"] = f"{fake_bin}:{env['PATH']}"
        env["QT_QPA_PLATFORM"] = "offscreen"
        env["XDG_RUNTIME_DIR"] = str(runtime_dir)
        env["TOAST_LOG"] = str(log)
        subprocess.run(
            ["timeout", "2", "qs", "-p", Path(probe.name).name],
            cwd=qml_root,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
    finally:
        Path(probe.name).unlink(missing_ok=True)

    assert log.read_text().splitlines() == [
        "-a",
        "YouTube",
        "-i",
        "youtube",
        "Now Playing",
        "Artist - Track",
    ]
