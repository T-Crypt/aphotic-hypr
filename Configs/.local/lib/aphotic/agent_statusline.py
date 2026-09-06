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


def build_record(payload: dict, now: float) -> dict:
    """Build the quota record for one statusline invocation."""
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


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    if not isinstance(payload, dict):
        return 0

    record = build_record(payload, time.time())

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

    line = format_line(record)
    if line:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
