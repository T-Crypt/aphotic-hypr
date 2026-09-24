#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors
"""aphotic agent statusline worker -- see agent_statusline.sh for why
this is one process and why nothing in here is allowed to raise.

Claude Code hands its statusLine command a JSON payload on stdin and
prints whatever the command writes to stdout. That payload is the only
place a harness states its own remaining quota: `rate_limits` carries the
five-hour and seven-day windows as a used percentage plus the epoch the
window resets at, and the context block carries how full the session's
own context window is. Nothing else on this machine knows those numbers
-- transcripts record tokens spent, never the share of an allowance --
so this dumps them for the shell to read and prints a line back.

Aggregate counters only. No prompt text, no tool arguments, no
credentials, and no network.
"""
from __future__ import annotations

import json
import os
import sys
import time

SCHEMA_VERSION = 1
STATE = os.environ.get("APHOTIC_STATE_HOME", os.path.expanduser("~/.local/state/aphotic"))
QUOTA = os.path.join(STATE, "agent-quota.json")

# The statusLine slot also feeds the shared event stream, as a `quota`
# line. Same file and rotation policy as agent_hook.py's EVENTS.
EVENTS = os.path.join(STATE, "agent-events.jsonl")
EVENTS_MAX_BYTES = 512 * 1024
EVENTS_KEEP_LINES = 1000
QUOTA_THROTTLE = os.path.join(STATE, "agent-quota-throttle.json")
QUOTA_THROTTLE_SECONDS = 60
# Only Claude Code's statusLine slot writes here.
PROVIDER_BY_HARNESS = {"claude": "anthropic"}


def atomic_write(path: str, text: str) -> None:
    """Write `text` to `path` via a same-directory temp file and rename."""
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)


def window(block: object) -> dict | None:
    """Normalise one rate-limit window, or None when it says nothing.

    `used_percentage` arrives 0-100 and is clamped, because a value the
    shell renders as a bar has to be in range even if the payload is not.
    `resets_at` is epoch seconds; 0 means the payload omitted it.
    """
    if not isinstance(block, dict):
        return None
    used = block.get("used_percentage")
    if used is None:
        return None
    try:
        percent = max(0.0, min(100.0, float(used)))
    except (TypeError, ValueError):
        return None
    try:
        resets = int(block.get("resets_at") or 0)
    except (TypeError, ValueError):
        resets = 0
    return {"usedPercent": percent, "resetsAt": max(0, resets)}


def context_window(payload: dict) -> dict | None:
    """The session's own context fill, which is a quota like any other."""
    block = payload.get("context_window")
    if not isinstance(block, dict):
        return None
    used = block.get("used_percentage")
    if used is None:
        return None
    try:
        percent = max(0.0, min(100.0, float(used)))
    except (TypeError, ValueError):
        return None
    record = {"usedPercent": percent, "resetsAt": 0}
    size = block.get("context_window_size")
    if isinstance(size, (int, float)) and size > 0:
        record["size"] = int(size)
    return record


def collect_windows(payload: dict) -> dict:
    """Every named quota window the payload reports, keyed by field name.

    Shared by the local record and the v2 `quota` event line.
    """
    limits = payload.get("rate_limits")
    limits = limits if isinstance(limits, dict) else {}
    windows = {}
    for key, field in (("five_hour", "fiveHour"), ("seven_day", "sevenDay"), ("spend_limit", "spendLimit")):
        parsed = window(limits.get(key))
        if parsed:
            windows[field] = parsed
    parsed = context_window(payload)
    if parsed:
        windows["context"] = parsed
    return windows


def build_record(payload: dict, now: float) -> dict:
    """Build the quota record for one statusline invocation."""
    windows = collect_windows(payload)

    model = payload.get("model")
    model = model if isinstance(model, dict) else {}

    return {
        "schemaVersion": SCHEMA_VERSION,
        "capturedAt": int(now),
        "providers": {
            "claude": {
                "model": model.get("display_name") or model.get("id") or "",
                "windows": windows,
            }
        },
    }


def merge(existing: object, record: dict) -> dict:
    """Keep other providers' entries when writing this one.

    The file is per-provider, and a second harness writing its own
    section must not erase Claude's, or two live sessions would take
    turns blanking each other's bars.
    """
    if not isinstance(existing, dict) or existing.get("schemaVersion") != SCHEMA_VERSION:
        return record
    providers = existing.get("providers")
    if not isinstance(providers, dict):
        return record
    merged = dict(providers)
    merged.update(record["providers"])
    out = dict(record)
    out["providers"] = merged
    return out


def format_line(record: dict) -> str:
    """The line Claude Code prints in place of its default status line.

    Aphotic claims this slot, so the line has to earn it: the model, then
    whichever windows the payload actually reported. A window the harness
    said nothing about is left out rather than shown as zero.
    """
    provider = record["providers"]["claude"]
    parts = []
    if provider["model"]:
        parts.append(provider["model"])
    windows = provider["windows"]
    for field, label in (("fiveHour", "5h"), ("sevenDay", "7d"), ("context", "ctx")):
        block = windows.get(field)
        if block:
            parts.append("%s %d%%" % (label, round(block["usedPercent"])))
    return " · ".join(parts)


def bare_windows(windows: dict) -> dict:
    """`windows` stripped to the quota schema's usedPercent/resetsAt.

    The local record also carries a `size` that the event line drops.
    """
    return {name: {"usedPercent": w["usedPercent"], "resetsAt": w["resetsAt"]} for name, w in windows.items()}


def build_quota_event(payload: dict, windows: dict, now: float) -> dict:
    """A `quota` line for the event stream."""
    harness = payload.get("harness") or "claude"
    record = {
        "v": 2,
        "harness": harness,
        "sessionId": payload.get("session_id") or "",
        "event": "quota",
        "status": "running",
        "t": int(now * 1000),
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
        "quota": bare_windows(windows),
    }
    provider = PROVIDER_BY_HARNESS.get(harness)
    if provider:
        record["provider"] = provider
    return record


def append_event_line(record: dict) -> None:
    """Append one line to the shared events stream, then trim it.

    The trim threshold matches agent_hook.py's so the file rotates the same way.
    """
    line = json.dumps(record, separators=(",", ":")) + "\n"
    with open(EVENTS, "a", encoding="utf-8") as fh:
        fh.write(line)
    if os.path.getsize(EVENTS) > EVENTS_MAX_BYTES:
        with open(EVENTS, "r", encoding="utf-8") as fh:
            lines = fh.readlines()[-EVENTS_KEEP_LINES:]
        atomic_write(EVENTS, "".join(lines))


def load_throttle() -> dict:
    try:
        with open(QUOTA_THROTTLE, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def should_emit_quota(state: dict, session_id: str, windows: dict, now: float) -> bool:
    """The statusLine runs on every turn, but a `quota` line need not.

    At most one per session per QUOTA_THROTTLE_SECONDS, unless windows changed.
    """
    prev = state.get(session_id)
    if not isinstance(prev, dict):
        return True
    try:
        elapsed = now - float(prev.get("t", 0))
    except (TypeError, ValueError):
        elapsed = QUOTA_THROTTLE_SECONDS + 1
    if elapsed >= QUOTA_THROTTLE_SECONDS:
        return True
    return prev.get("windows") != windows


def maybe_emit_quota_event(payload: dict, windows: dict, now: float) -> None:
    """Append a `quota` line, throttled per session (see should_emit_quota).

    A payload with no window writes nothing.
    """
    if not windows:
        return
    session_id = payload.get("session_id") or ""
    state = load_throttle()
    if not should_emit_quota(state, session_id, windows, now):
        return

    os.makedirs(STATE, exist_ok=True)
    append_event_line(build_quota_event(payload, windows, now))

    state[session_id] = {"t": now, "windows": windows}
    atomic_write(QUOTA_THROTTLE, json.dumps(state, separators=(",", ":")))


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    if not isinstance(payload, dict):
        return 0

    now = time.time()
    record = build_record(payload, now)

    try:
        os.makedirs(STATE, exist_ok=True)
        existing = None
        try:
            with open(QUOTA, "r", encoding="utf-8") as fh:
                existing = json.load(fh)
        except (OSError, ValueError):
            pass
        atomic_write(QUOTA, json.dumps(merge(existing, record), separators=(",", ":")))
    except OSError:
        pass

    try:
        maybe_emit_quota_event(payload, collect_windows(payload), now)
    except OSError:
        pass

    line = format_line(record)
    if line:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
