#!/usr/bin/env python3
"""Wallpaper packs: themed collections fetched on request, never vendored.

A pack is a TOML file. Its ``[pack]`` table names a pinned ``base_url``;
each ``[[wallpaper]]`` row names a theme, a ``path`` under that URL, the
file's sha256 and its pixel size. Packs come from two places: enabled
plugins with the ``wallpaper-pack`` capability list them under
``[wallpapers] packs``, and users drop them in
``<config>/wallpapers/*.toml``.

``fetch`` downloads a theme's rows into that theme's awww folder, the
same folder the picker, the cycle and ``aphotic wallpaper -f`` already
read, so nothing downstream learns a new location. A file lands only
after its hash matches. A file already present with the right hash is
left alone, so a rerun converges instead of downloading again.

``index`` records every image's size in ``<theme>/.wallpapers.json`` so
the shell can prefer ultrawide images on an ultrawide screen without
decoding anything itself.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
import tomllib
import urllib.request
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harnesses_merge import PLUGINS_STATE_NAME, config_dir, plugins_dir, state_dir  # noqa: E402

CAPABILITY = "wallpaper-pack"
DROPIN_DIR_NAME = "wallpapers"
SIDECAR_NAME = ".wallpapers.json"
IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp", ".gif"}
ULTRAWIDE_RATIO = 2.2
TIMEOUT_SECONDS = 60


@dataclass(frozen=True)
class Wallpaper:
    pack: str
    theme: str
    url: str
    name: str
    sha256: str
    width: int
    height: int


def awww_dir() -> Path:
    value = os.environ.get("APHOTIC_AWWW_DIR")
    if value:
        return Path(value)
    home = Path(os.environ.get("HOME", str(Path.home())))
    return Path(os.environ.get("XDG_CONFIG_HOME", str(home / ".config"))) / "awww"


def _warn(message: str) -> None:
    print(message, file=sys.stderr)


def _plugin_pack_files() -> list[Path]:
    state = state_dir() / PLUGINS_STATE_NAME
    if not state.is_file():
        return []
    try:
        data = json.loads(state.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    disabled = data.get("disabled") or []
    found = []
    for name in data.get("installed") or {}:
        if name in disabled:
            continue
        root = plugins_dir() / name
        try:
            manifest = tomllib.loads((root / "plugin.toml").read_text(encoding="utf-8"))
        except (OSError, tomllib.TOMLDecodeError):
            continue
        if CAPABILITY not in ((manifest.get("plugin") or {}).get("capabilities") or []):
            continue
        for rel in (manifest.get("wallpapers") or {}).get("packs") or []:
            path = (root / rel).resolve()
            if root.resolve() in path.parents and path.is_file():
                found.append(path)
            else:
                _warn(f"aphotic wallpaper: plugin '{name}' lists '{rel}', which is not a file inside the plugin")
    return found


def pack_files() -> list[Path]:
    dropins = sorted((config_dir() / DROPIN_DIR_NAME).glob("*.toml"))
    return _plugin_pack_files() + dropins


def load_pack(path: Path) -> list[Wallpaper]:
    """Rows of one pack file. A malformed row is dropped with a warning,
    never fatal: one bad entry should not cost the user the whole pack."""
    try:
        data = tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as exc:
        _warn(f"aphotic wallpaper: {path} did not parse ({exc})")
        return []
    pack = data.get("pack") or {}
    pack_id = str(pack.get("id") or path.stem)
    base = str(pack.get("base_url") or "")
    if not base.startswith("https://"):
        _warn(f"aphotic wallpaper: {path} needs an https base_url")
        return []
    base = base if base.endswith("/") else base + "/"
    rows = []
    for raw in data.get("wallpaper") or []:
        try:
            rel = str(raw["path"])
            digest = str(raw["sha256"]).lower()
            row = Wallpaper(pack_id, str(raw["theme"]), base + rel, Path(rel).name, digest,
                            int(raw.get("width", 0)), int(raw.get("height", 0)))
        except (KeyError, TypeError, ValueError):
            _warn(f"aphotic wallpaper: {path}: a row is missing theme, path or sha256, skipped")
            continue
        if ".." in Path(rel).parts or len(digest) != 64 or "/" in row.theme:
            _warn(f"aphotic wallpaper: {path}: '{rel}' is not a safe row, skipped")
            continue
        rows.append(row)
    return rows


def check_plugin(root: Path) -> int:
    """Exit 0 when every pack a plugin lists loads with at least one row."""
    try:
        manifest = tomllib.loads((root / "plugin.toml").read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as exc:
        print(f"plugin.toml did not parse ({exc})")
        return 1
    packs = (manifest.get("wallpapers") or {}).get("packs") or []
    if not packs:
        print("the 'wallpaper-pack' capability has no [wallpapers] packs list")
        return 1
    bad = []
    for rel in packs:
        path = (root / rel).resolve()
        if root.resolve() not in path.parents or not path.is_file():
            bad.append(f"{rel} is not a file inside the plugin")
        elif not load_pack(path):
            bad.append(f"{rel} has no usable rows")
    if bad:
        print("; ".join(bad))
        return 1
    return 0


def all_wallpapers() -> list[Wallpaper]:
    rows = []
    for path in pack_files():
        rows.extend(load_pack(path))
    return rows


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def _destination(theme_dir: Path, row: Wallpaper) -> Path:
    """Where a row lands. A name already taken by a different file gets the
    pack id in front, so a pack never overwrites a wallpaper it did not
    bring."""
    plain = theme_dir / row.name
    if not plain.exists() or _sha256(plain) == row.sha256:
        return plain
    return theme_dir / f"{row.pack}-{row.name}"


def _download(row: Wallpaper, dest: Path) -> None:
    request = urllib.request.Request(row.url, headers={"User-Agent": "aphotic-wallpaper"})
    fd, tmp = tempfile.mkstemp(prefix=".fetch-", dir=dest.parent)
    try:
        h = hashlib.sha256()
        with os.fdopen(fd, "wb") as out, urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as resp:
            for block in iter(lambda: resp.read(1 << 16), b""):
                h.update(block)
                out.write(block)
        if h.hexdigest() != row.sha256:
            raise ValueError("sha256 does not match the pack")
        os.chmod(tmp, 0o644)
        os.replace(tmp, dest)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def fetch(themes: list[str], dry_run: bool = False) -> int:
    root = awww_dir()
    rows = [r for r in all_wallpapers() if r.theme in themes]
    if not rows:
        print(f"No pack lists wallpapers for: {', '.join(themes)}")
        return 0
    got = kept = failed = 0
    for row in rows:
        theme_dir = root / row.theme
        if not theme_dir.is_dir():
            continue
        dest = _destination(theme_dir, row)
        if dest.exists():
            kept += 1
            continue
        if dry_run:
            print(f"would fetch {row.theme}/{dest.name} from {row.url}")
            got += 1
            continue
        try:
            _download(row, dest)
            got += 1
            print(f"fetched {row.theme}/{dest.name}")
        except (OSError, ValueError) as exc:
            failed += 1
            _warn(f"aphotic wallpaper: {row.url}: {exc}")
    if not dry_run:
        for theme in themes:
            if (root / theme).is_dir():
                index(root / theme)
    verb = "would fetch" if dry_run else "fetched"
    print(f"{verb} {got}, already present {kept}, failed {failed}")
    return 1 if failed else 0


def index(theme_dir: Path) -> dict:
    """Write <theme>/.wallpapers.json with every image's size, on one line
    so the shell's theme scan can pass it through whole. Reads image
    headers only. Without Pillow the sidecar keeps whatever sizes the
    packs declared."""
    sizes: dict[str, list[int]] = {}
    declared = {r.name: (r.width, r.height) for r in all_wallpapers() if r.theme == theme_dir.name}
    try:
        from PIL import Image
    except ImportError:
        Image = None
    for path in sorted(theme_dir.iterdir()):
        if path.suffix.lower() not in IMAGE_EXT or path.name.startswith("."):
            continue
        size = None
        if Image is not None:
            try:
                with Image.open(path) as im:
                    size = list(im.size)
            except OSError:
                size = None
        if size is None and declared.get(path.name, (0, 0))[0]:
            size = list(declared[path.name])
        if size:
            sizes[path.name] = size
    record = {"schemaVersion": 1, "ultrawideRatio": ULTRAWIDE_RATIO, "sizes": sizes}
    fd, tmp = tempfile.mkstemp(prefix=".index-", dir=theme_dir)
    with os.fdopen(fd, "w", encoding="utf-8") as out:
        json.dump(record, out, sort_keys=True, separators=(",", ":"))
    os.chmod(tmp, 0o644)
    os.replace(tmp, theme_dir / SIDECAR_NAME)
    return record


def active_theme() -> str:
    try:
        return json.loads((state_dir() / "theme.json").read_text(encoding="utf-8")).get("theme", "")
    except (OSError, ValueError):
        return ""


def installed_themes() -> list[str]:
    root = awww_dir()
    return sorted(p.name for p in root.iterdir() if p.is_dir()) if root.is_dir() else []


def list_packs() -> int:
    installed = set(installed_themes())
    counts: dict[tuple[str, str], int] = {}
    for row in all_wallpapers():
        counts[(row.pack, row.theme)] = counts.get((row.pack, row.theme), 0) + 1
    if not counts:
        print("No wallpaper packs installed. Install a plugin that ships one, or drop a pack in "
              f"{config_dir() / DROPIN_DIR_NAME}/.")
        return 0
    for (pack, theme), n in sorted(counts.items()):
        note = "" if theme in installed else "  (theme not installed)"
        print(f"{pack:<24} {theme:<16} {n:>4}{note}")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="aphotic wallpaper")
    sub = parser.add_subparsers(dest="command", required=True)
    f = sub.add_parser("fetch")
    f.add_argument("themes", nargs="*")
    f.add_argument("--all", action="store_true")
    f.add_argument("--dry-run", action="store_true")
    sub.add_parser("packs")
    i = sub.add_parser("index")
    i.add_argument("themes", nargs="*")
    c = sub.add_parser("check")
    c.add_argument("plugin_dir", type=Path)
    args = parser.parse_args(argv)

    if args.command == "check":
        return check_plugin(args.plugin_dir)

    if args.command == "packs":
        return list_packs()
    if args.command == "index":
        for theme in args.themes or installed_themes():
            if (awww_dir() / theme).is_dir():
                index(awww_dir() / theme)
        return 0
    themes = installed_themes() if args.all else (args.themes or [active_theme()])
    themes = [t for t in themes if t]
    if not themes:
        _warn("aphotic wallpaper: no active theme; name one, or pass --all")
        return 1
    return fetch(themes, dry_run=args.dry_run)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
