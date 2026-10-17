#!/usr/bin/env python3
"""Merge harness descriptors into one validated record.

Sources, in precedence-defeating order (first plugin in registry order
wins on an id, a drop-in beats every plugin):

1. Every enabled harness-hook plugin's manifest, read live off disk,
   its ``[harness.<id>]`` subtables. The plugin set and its order come
   from plugins.json's ``installed`` map; the ``disabled`` array leaves
   a plugin out.
2. One file per harness under ``<config>/harnesses/*.toml``, id taken
   from the filename.

Validation happens here, once, at the boundary between untrusted TOML
and every consumer: a malformed descriptor is dropped with a warning
that names its source and the rest of the merge survives. The merged
record lands at ``<state>/harnesses.json`` (schemaVersion 1), written
atomically so a watching shell never reads a half-written file.
"""
from __future__ import annotations

import json
import os
import re
import sys
import tomllib
from datetime import datetime, timezone
from pathlib import Path

from agent_usage import write_record_atomically

SCHEMA_VERSION = 1
RECORD_NAME = "harnesses.json"
PLUGINS_STATE_NAME = "plugins.json"
DROPIN_DIR_NAME = "harnesses"
DROPIN_SUFFIX = ".toml"

_ID_RE = re.compile(r"^[a-z][a-z0-9_-]*$")
_USAGE_MODES = ("stream", "scan")
_CONTEXT_MODES = ("stream", "statusline")


def _warn_default(message: str) -> None:
    print(message, file=sys.stderr)


def _xdg_dir(env_var: str, xdg_var: str, leaf: str, home_leaf: str) -> Path:
    # The bash side derives APHOTIC_*_HOME from XDG_*_HOME; honouring both
    # here keeps a direct python3 invocation testable without sourcing
    # globalcontrol.sh first.
    home = Path(os.environ.get("HOME", str(Path.home())))
    value = os.environ.get(env_var)
    if value:
        return Path(value)
    value = os.environ.get(xdg_var)
    if value:
        return Path(value) / leaf
    return home / home_leaf / leaf


def config_dir() -> Path:
    return _xdg_dir("APHOTIC_CONFIG_HOME", "XDG_CONFIG_HOME", "aphotic", ".config")


def plugins_dir() -> Path:
    value = os.environ.get("APHOTIC_PLUGINS_DIR")
    if value:
        return Path(value)
    home = Path(os.environ.get("HOME", str(Path.home())))
    value = os.environ.get("XDG_DATA_HOME")
    if value:
        return Path(value) / "aphotic" / "plugins"
    return home / ".local" / "share" / "aphotic" / "plugins"


def state_dir() -> Path:
    return _xdg_dir("APHOTIC_STATE_HOME", "XDG_STATE_HOME", "aphotic", ".local/state")


def _enabled_harness_hook_plugins(
    plugins_state: Path, plugin_root: Path, emit
) -> list[tuple[str, dict]]:
    """(plugin name, parsed manifest) for every enabled harness-hook plugin,
    in plugins.json's installed-map order. A manifest is read live off
    disk, never from the registry snapshot, so no snapshot migration is
    needed when the manifest schema grows."""
    if not plugins_state.is_file():
        return []
    try:
        state = json.loads(plugins_state.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        emit(f"aphotic harness: {plugins_state} did not parse -- no plugin descriptors ({exc})")
        return []

    disabled = state.get("disabled") or []
    installed = state.get("installed") or {}
    found: list[tuple[str, dict]] = []
    for name in installed:
        if name in disabled:
            continue
        manifest = plugin_root / name / "plugin.toml"
        if not manifest.is_file():
            continue
        try:
            data = tomllib.loads(manifest.read_text(encoding="utf-8"))
        except (OSError, tomllib.TOMLDecodeError) as exc:
            emit(f"aphotic harness: plugin '{name}' manifest did not parse -- skipped ({exc})")
            continue
        capabilities = (data.get("plugin") or {}).get("capabilities") or []
        if "harness-hook" not in capabilities:
            continue
        found.append((name, data))
    return found


def _harness_tables(data: dict) -> dict[str, dict]:
    # [harness] itself carries wire/unwire strings; only the descriptor
    # subtables are dicts.
    harness = data.get("harness")
    if not isinstance(harness, dict):
        return {}
    return {k: v for k, v in harness.items() if isinstance(v, dict)}


def _match_ok(value: str) -> bool:
    if not value:
        return True
    if "/" in value or any(c.isspace() for c in value):
        return False
    return not any(c in value for c in "*?[]")


def _scan_ok(value: str) -> bool:
    return bool(value) and not value.startswith("/") and ".." not in value


def _normalize(raw: dict, source: str, hid: str, emit) -> dict | None:
    """Validate one raw descriptor; None means dropped."""
    if not isinstance(raw, dict):
        emit(f"aphotic harness: {source}: id '{hid}' is not a table -- dropped")
        return None
    if not _ID_RE.match(hid):
        emit(
            f"aphotic harness: {source}: id '{hid}' is not lowercase letters, "
            "digits, hyphens or underscores -- dropped"
        )
        return None

    label = raw.get("label")
    if not (isinstance(label, str) and label):
        label = hid
    icon = raw.get("icon")
    if not (isinstance(icon, str) and icon):
        icon = "terminal"

    match = raw.get("match", "")
    if not isinstance(match, str) or not _match_ok(match):
        emit(
            f"aphotic harness: {source}: '{hid}' match '{match}' is not a "
            "process name -- process reconcile off"
        )
        match = ""

    launch = raw.get("launch", [])
    if not (
        isinstance(launch, list)
        and all(isinstance(arg, str) for arg in launch)
        and (not launch or launch[0] != "")
    ):
        emit(
            f"aphotic harness: {source}: '{hid}' launch must be a list of "
            "strings -- launch hidden"
        )
        launch = []

    usage = raw.get("usage", "stream")
    if usage not in _USAGE_MODES:
        emit(
            f"aphotic harness: {source}: '{hid}' usage '{usage}' is not "
            "stream or scan -- using stream"
        )
        usage = "stream"

    scan = raw.get("scan", "")
    if usage == "scan":
        if not isinstance(scan, str) or not _scan_ok(scan):
            emit(
                f"aphotic harness: {source}: '{hid}' scan '{scan}' is not a "
                "home-relative glob -- using stream"
            )
            usage = "stream"

    context = raw.get("context", "stream")
    if context not in _CONTEXT_MODES:
        emit(
            f"aphotic harness: {source}: '{hid}' context '{context}' is not "
            "stream or statusline -- using stream"
        )
        context = "stream"

    chat = raw.get("chat", False)
    if not isinstance(chat, bool):
        emit(
            f"aphotic harness: {source}: '{hid}' chat must be true or false -- using false"
        )
        chat = False

    provider = raw.get("provider", "")
    if not isinstance(provider, str):
        provider = ""

    return {
        "id": hid,
        "source": source,
        "label": label,
        "icon": icon,
        "provider": provider,
        "match": match,
        "launch": list(launch),
        "usage": usage,
        "scan": scan if usage == "scan" else "",
        "context": context,
        "chat": chat,
    }


def _plugin_descriptors(plugins_state: Path, plugin_root: Path, emit) -> list[dict]:
    by_id: dict[str, dict] = {}
    for name, data in _enabled_harness_hook_plugins(plugins_state, plugin_root, emit):
        for hid, raw in _harness_tables(data).items():
            source = f"plugin:{name}"
            descriptor = _normalize(raw, source, hid, emit)
            if descriptor is None:
                continue
            if hid in by_id:
                emit(
                    f"aphotic harness: '{hid}' declared by both "
                    f"{by_id[hid]['source'].removeprefix('plugin:')} and {name} -- {name} dropped"
                )
                continue
            by_id[hid] = descriptor
    return list(by_id.values())


def _dropin_descriptors(config_root: Path, plugin_ids: dict[str, str], emit) -> list[dict]:
    """Drop-ins from <config_root>/harnesses/, sorted by filename. A drop-in
    whose id a plugin already claimed replaces it."""
    dropin_root = config_root / DROPIN_DIR_NAME
    if not dropin_root.is_dir():
        return []
    out: list[dict] = []
    for path in sorted(dropin_root.glob(f"*{DROPIN_SUFFIX}")):
        if not path.is_file():
            continue
        stem = path.name[: -len(DROPIN_SUFFIX)]
        try:
            data = tomllib.loads(path.read_text(encoding="utf-8"))
        except (OSError, tomllib.TOMLDecodeError):
            emit(f"aphotic harness: drop-in '{path.name}' did not parse -- skipped")
            continue
        tables = _harness_tables(data)
        if not tables:
            emit(
                f"aphotic harness: drop-in '{path.name}' declares no "
                "[harness.<id>] section -- skipped"
            )
            continue
        for hid, raw in tables.items():
            if hid != stem:
                emit(
                    f"aphotic harness: drop-in '{path.name}': [harness.{hid}] "
                    "does not match the filename -- dropped"
                )
                continue
            descriptor = _normalize(raw, f"drop-in:{path.name}", stem, emit)
            if descriptor is None:
                continue
            if stem in plugin_ids:
                emit(
                    f"aphotic harness: drop-in '{path.name}' overrides the "
                    f"descriptor from {plugin_ids[stem]}"
                )
            out.append(descriptor)
    return out


def merge(
    config_root: Path,
    plugin_root: Path,
    state_root: Path,
    now: datetime | None = None,
    emit=_warn_default,
) -> dict:
    """Merge every descriptor source into one record and write it.

    Returns the record that was written, so tests can assert on the
    exact shape instead of re-reading the file.
    """
    plugins = _plugin_descriptors(state_root / PLUGINS_STATE_NAME, plugin_root, emit)
    plugin_ids = {d["id"]: d["source"].removeprefix("plugin:") for d in plugins}
    dropins = _dropin_descriptors(config_root, plugin_ids, emit)
    # A drop-in replaces the plugin descriptor wholesale; the one that
    # wins keeps the drop-in's own source string.
    merged = [d for d in plugins if d["id"] not in {x["id"] for x in dropins}] + dropins
    record = {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": (now or datetime.now(timezone.utc)).isoformat(),
        "harnesses": merged,
    }
    write_record_atomically(state_root / RECORD_NAME, record)
    return record


def main(argv: list[str]) -> int:
    """CLI entrypoint: one optional argument, the state directory.

    Defaults to $APHOTIC_STATE_HOME, then $XDG_STATE_HOME/aphotic, then
    ~/.local/state/aphotic -- the same resolution order the bash side
    uses when it passes $APHOTIC_STATE_HOME explicitly.
    """
    if len(argv) > 1:
        print("usage: harnesses_merge.py [state-dir]", file=sys.stderr)
        return 2
    if argv:
        root = Path(argv[0])
    else:
        root = state_dir()
    merge(config_dir(), plugins_dir(), root)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
