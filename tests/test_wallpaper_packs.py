"""Wallpaper packs fetch verified files into theme folders and nothing else.

The network is replaced by a dict of URL to bytes, so each case states
exactly what the server would hand back.
"""
import hashlib
import io
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Configs" / ".local" / "lib" / "aphotic"))
import wallpaper_packs as wp


def png(width: int, height: int, colour=(10, 20, 30)) -> bytes:
    import struct
    import zlib

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    raw = b"".join(b"\x00" + bytes(colour) * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


@pytest.fixture
def home(tmp_path, monkeypatch):
    for name, sub in (("APHOTIC_STATE_HOME", "state"), ("APHOTIC_CONFIG_HOME", "config"),
                      ("APHOTIC_PLUGINS_DIR", "plugins"), ("APHOTIC_AWWW_DIR", "awww")):
        (tmp_path / sub).mkdir()
        monkeypatch.setenv(name, str(tmp_path / sub))
    (tmp_path / "awww" / "nordic").mkdir()
    return tmp_path


@pytest.fixture
def server(monkeypatch):
    files: dict[str, bytes] = {}

    def urlopen(request, timeout=0):
        url = request.full_url
        if url not in files:
            raise OSError(f"404 {url}")
        return io.BytesIO(files[url])

    monkeypatch.setattr(wp.urllib.request, "urlopen", urlopen)
    return files


def dropin(home: Path, rows: list[dict], base="https://example.test/p/", pack_id="test") -> None:
    lines = [f'[pack]\nid = "{pack_id}"\nbase_url = "{base}"\n']
    for r in rows:
        lines.append("[[wallpaper]]\n" + "".join(
            f'{k} = "{v}"\n' if isinstance(v, str) else f"{k} = {v}\n" for k, v in r.items()))
    (home / "config" / "wallpapers").mkdir(exist_ok=True)
    (home / "config" / "wallpapers" / f"{pack_id}.toml").write_text("\n".join(lines))


def test_fetch_lands_verified_files_and_reruns_download_nothing(home, server):
    data = png(3440, 1440)
    server["https://example.test/p/wide.png"] = data
    dropin(home, [{"theme": "nordic", "path": "wide.png", "sha256": sha(data), "width": 3440, "height": 1440}])

    assert wp.fetch(["nordic"]) == 0
    assert (home / "awww/nordic/wide.png").read_bytes() == data

    del server["https://example.test/p/wide.png"]
    assert wp.fetch(["nordic"]) == 0

    sizes = json.loads((home / "awww/nordic/.wallpapers.json").read_text())["sizes"]
    assert sizes == {"wide.png": [3440, 1440]}


def test_a_hash_mismatch_leaves_no_file_and_fails(home, server):
    server["https://example.test/p/bad.png"] = png(1920, 1080)
    dropin(home, [{"theme": "nordic", "path": "bad.png", "sha256": "0" * 64}])

    assert wp.fetch(["nordic"]) == 1
    assert sorted(p.name for p in (home / "awww/nordic").iterdir()) == [".wallpapers.json"]


def test_a_taken_name_gets_the_pack_prefix_instead_of_overwriting(home, server):
    mine = png(1920, 1080, (200, 0, 0))
    (home / "awww/nordic/sea.png").write_bytes(mine)
    theirs = png(1920, 1080, (0, 0, 200))
    server["https://example.test/p/sea.png"] = theirs
    dropin(home, [{"theme": "nordic", "path": "sea.png", "sha256": sha(theirs)}], pack_id="blue")

    assert wp.fetch(["nordic"]) == 0
    assert (home / "awww/nordic/sea.png").read_bytes() == mine
    assert (home / "awww/nordic/blue-sea.png").read_bytes() == theirs


def test_unsafe_rows_and_plain_http_packs_are_refused(home):
    good = "a" * 64
    dropin(home, [
        {"theme": "nordic", "path": "../escape.png", "sha256": good},
        {"theme": "nordic", "path": "short.png", "sha256": "abc"},
        {"theme": "nordic", "path": "fine.png", "sha256": good},
    ])
    dropin(home, [{"theme": "nordic", "path": "x.png", "sha256": good}], base="http://example.test/", pack_id="plain")

    assert [(r.pack, r.name) for r in wp.all_wallpapers()] == [("test", "fine.png")]


def test_a_disabled_plugin_contributes_no_pack(home):
    plugin = home / "plugins" / "packs"
    (plugin / "packs").mkdir(parents=True)
    (plugin / "plugin.toml").write_text('[plugin]\nname = "packs"\ncapabilities = ["wallpaper-pack"]\n\n[wallpapers]\npacks = ["packs/a.toml"]\n')
    (plugin / "packs" / "a.toml").write_text(f'[pack]\nid = "a"\nbase_url = "https://example.test/"\n\n[[wallpaper]]\ntheme = "nordic"\npath = "a.png"\nsha256 = "{"b" * 64}"\n')
    state = home / "state" / "plugins.json"

    state.write_text(json.dumps({"installed": {"packs": {}}, "disabled": []}))
    assert [r.name for r in wp.all_wallpapers()] == ["a.png"]
    assert wp.check_plugin(plugin) == 0

    state.write_text(json.dumps({"installed": {"packs": {}}, "disabled": ["packs"]}))
    assert wp.all_wallpapers() == []


def test_check_fails_a_plugin_whose_pack_file_is_missing(home):
    plugin = home / "plugins" / "broken"
    plugin.mkdir()
    (plugin / "plugin.toml").write_text('[plugin]\nname = "broken"\ncapabilities = ["wallpaper-pack"]\n\n[wallpapers]\npacks = ["packs/gone.toml"]\n')

    assert wp.check_plugin(plugin) == 1
