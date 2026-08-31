#!/usr/bin/env python3
"""Aggregate local AI-CLI transcript token usage into a small JSON record.

Reads only aggregate counts (tokens, model names) from local transcript
files -- never prompts, responses, tool arguments, or credentials -- so
the QML shell can show "today's usage" without scanning transcripts (or
holding an API key) itself.
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_VERSION = 1
PROVIDER_IDS = ("claude", "codex", "opencode")


def _sum_transcript(path: Path, today: str) -> tuple[int, dict[str, int]]:
    """Sum token usage in a single transcript file for `today`.

    Reads a transcript file line-by-line where each line is JSON. The
    function is defensive about the JSON shape: real transcripts nest
    model/usage under a "message" object while test fixtures may use a
    flat top-level shape. Returns (total_tokens, tokens_by_model).
    """
    total = 0
    by_model: dict[str, int] = {}
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            ts = entry.get("timestamp")
            # Real Claude Code transcript lines nest model/usage under
            # "message" (confirmed against this machine's own live
            # transcripts -- entry["message"]["model"]/["usage"], never a
            # top-level "model"/"usage" key at all), not the flat
            # top-level shape this function originally assumed -- which
            # means it had never actually matched a single real entry;
            # todayTokens silently stayed 0 on every real machine
            # regardless of actual usage. Checking top-level first keeps
            # this function's own test fixtures (a deliberately simpler
            # flat shape) working unchanged.
            message = entry.get("message") or {}
            model = entry.get("model") or message.get("model")
            usage = entry.get("usage") or message.get("usage")
            if not ts or not model or not usage:
                continue
            if not ts.startswith(today):
                continue
            tokens = (usage.get("input_tokens") or 0) + (usage.get("output_tokens") or 0)
            if tokens <= 0:
                continue
            total += tokens
            by_model[model] = by_model.get(model, 0) + tokens
    return total, by_model


def build_usage_record(now: datetime, sources: dict[str, Path | list[Path]]) -> dict:
    """Build a compact usage record aggregating today's token counts.

    Parameters:
    - now: current datetime used to determine "today" (UTC-aware datetime
      is recommended to match transcript timestamps).
    - sources: mapping from provider id (keys from PROVIDER_IDS) to either a
      Path or an iterable of Paths pointing at transcript jsonl files.

    Returns a dict suitable for writing to disk which summarizes per-provider
    availability, today's token total, and a ranked tokens-by-model list.
    """
    today = now.strftime("%Y-%m-%d")
    providers: dict[str, dict] = {}
    for provider_id in PROVIDER_IDS:
        source = sources.get(provider_id)
        if source is None:
            providers[provider_id] = {"availability": "unavailable", "todayTokens": 0, "tokensByModel": []}
            continue
        # A single Path (every existing test, and any future caller with
        # just one transcript to check) is normalized to a one-element
        # list -- real usage (main() below) needs a *list*, because a
        # real machine has one transcript file per Claude Code session,
        # not one per provider. Picking only the first file glob happened
        # to enumerate (the previous shape here) silently showed 0 tokens
        # for a very real, very active session as soon as any other
        # project/session's transcript existed and sorted first -- summed
        # here across every matching transcript instead.
        transcripts = [source] if isinstance(source, Path) else list(source)
        existing = [p for p in transcripts if p.exists()]
        if not existing:
            providers[provider_id] = {"availability": "unavailable", "todayTokens": 0, "tokensByModel": []}
            continue
        total = 0
        by_model: dict[str, int] = {}
        try:
            for path in existing:
                t, bm = _sum_transcript(path, today)
                total += t
                for model, tokens in bm.items():
                    by_model[model] = by_model.get(model, 0) + tokens
        except OSError:
            providers[provider_id] = {"availability": "unavailable", "todayTokens": 0, "tokensByModel": []}
            continue
        ranked = sorted(by_model.items(), key=lambda kv: -kv[1])
        providers[provider_id] = {
            "availability": "available",
            "todayTokens": total,
            "tokensByModel": [{"model": k, "tokens": v} for k, v in ranked],
        }
    return {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": now.isoformat(),
        "providers": providers,
    }


def write_record_atomically(path: Path, record: dict) -> None:
    """Write `record` to `path` atomically as JSON.

    Creates parent directories if necessary, writes to a temporary file and
    then atomically replaces the destination. Indented JSON is used for
    readability when humans inspect the file.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_text(json.dumps(record, indent=2))
    os.replace(tmp_path, path)


def main(argv: list[str]) -> int:
    """CLI entrypoint.

    Expects a single argument: the directory where the generated
    `agent-usage.json` will be written. Scans well-known transcript paths in
    the user's home directory for supported providers and writes the
    aggregated record.
    """
    if len(argv) != 1:
        print("usage: agent_usage.py <state-dir>", file=sys.stderr)
        return 2
    state_dir = Path(argv[0])
    home = Path(os.environ.get("HOME", str(Path.home())))
    sources = {
        "claude": list(home.glob(".claude/projects/*/*.jsonl")),
        "codex": list(home.glob(".codex/sessions/*.jsonl")),
    }
    record = build_usage_record(datetime.now(timezone.utc), sources)
    write_record_atomically(state_dir / "agent-usage.json", record)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
