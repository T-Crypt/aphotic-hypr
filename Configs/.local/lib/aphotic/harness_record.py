#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors
"""The merged harness record's file name, schema, and its one reader.

harnesses_merge.py writes the record; the Python consumers read it
through load(). The merge already validated every descriptor, so load()
only guards against the file being absent, torn, or from another schema.
"""
from __future__ import annotations

import json
from pathlib import Path

SCHEMA_VERSION = 1
RECORD_NAME = "harnesses.json"


def load(state_dir: str | Path) -> list[dict]:
    """Every merged descriptor, or [] when the record can't be read.

    Never raises: the hook worker calls this on every event and must not
    fail a harness's hook over a missing or half-written file.
    """
    try:
        data = json.loads((Path(state_dir) / RECORD_NAME).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    if not isinstance(data, dict) or data.get("schemaVersion") != SCHEMA_VERSION:
        return []
    harnesses = data.get("harnesses")
    if not isinstance(harnesses, list):
        return []
    return [h for h in harnesses if isinstance(h, dict) and isinstance(h.get("id"), str)]


def provider_of(harnesses: list[dict], harness_id: str) -> str:
    """The descriptor's inference provider for `harness_id`, "" if none."""
    for h in harnesses:
        if h["id"] == harness_id:
            return h.get("provider") or ""
    return ""
