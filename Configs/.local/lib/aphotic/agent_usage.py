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
PROVIDER_IDS = ("claude", "codex", "ollama")


def _sum_transcript(path: Path, today: str) -> tuple[int, dict[str, int]]:
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
            model = entry.get("model")
            usage = entry.get("usage")
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


def build_usage_record(now: datetime, sources: dict[str, Path]) -> dict:
    today = now.strftime("%Y-%m-%d")
    providers: dict[str, dict] = {}
    for provider_id in PROVIDER_IDS:
        source = sources.get(provider_id)
        if source is None:
            providers[provider_id] = {"availability": "unavailable", "todayTokens": 0, "tokensByModel": []}
            continue
        if not source.exists():
            providers[provider_id] = {"availability": "unavailable", "todayTokens": 0, "tokensByModel": []}
            continue
        try:
            total, by_model = _sum_transcript(source, today)
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
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_text(json.dumps(record, indent=2))
    os.replace(tmp_path, path)


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: agent_usage.py <state-dir>", file=sys.stderr)
        return 2
    state_dir = Path(argv[0])
    home = Path(os.environ.get("HOME", str(Path.home())))
    sources = {
        "claude": next(iter(home.glob(".claude/projects/*/*.jsonl")), home / ".claude" / "projects" / "none.jsonl"),
        "codex": next(iter(home.glob(".codex/sessions/*.jsonl")), home / ".codex" / "sessions" / "none.jsonl"),
    }
    record = build_usage_record(datetime.now(timezone.utc), sources)
    write_record_atomically(state_dir / "agent-usage.json", record)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
