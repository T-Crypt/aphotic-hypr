import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Configs" / ".local" / "lib" / "aphotic"))
from agent_usage import build_usage_record, write_record_atomically

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "agent_usage"
NOW = datetime(2026, 8, 24, 12, 0, 0, tzinfo=timezone.utc)


def test_valid_claude_transcript_sums_todays_tokens_only():
    record = build_usage_record(NOW, {"claude": FIXTURES / "claude_valid.jsonl"})
    claude = record["providers"]["claude"]
    assert claude["availability"] == "available"
    assert claude["todayTokens"] == 100 + 50 + 200 + 75
    assert claude["tokensByModel"] == [{"model": "claude-sonnet-5", "tokens": 425}]


def test_valid_codex_transcript():
    record = build_usage_record(NOW, {"codex": FIXTURES / "codex_valid.jsonl"})
    codex = record["providers"]["codex"]
    assert codex["availability"] == "available"
    assert codex["todayTokens"] == 420


def test_malformed_lines_are_skipped_not_fatal():
    record = build_usage_record(NOW, {"claude": FIXTURES / "malformed.jsonl"})
    claude = record["providers"]["claude"]
    assert claude["availability"] == "available"
    assert claude["todayTokens"] == 0
    assert claude["tokensByModel"] == []


def test_missing_source_marked_unavailable():
    record = build_usage_record(NOW, {"claude": FIXTURES / "does_not_exist.jsonl"})
    assert record["providers"]["claude"]["availability"] == "unavailable"


def test_record_has_schema_version_and_timestamp():
    record = build_usage_record(NOW, {})
    assert record["schemaVersion"] == 1
    assert record["generatedAt"] == "2026-08-24T12:00:00+00:00"


def test_write_record_atomically_creates_file(tmp_path):
    target = tmp_path / "state" / "agent-usage.json"
    write_record_atomically(target, {"schemaVersion": 1})
    assert target.exists()
    assert json.loads(target.read_text())["schemaVersion"] == 1


def test_write_record_atomically_leaves_no_temp_file(tmp_path):
    target = tmp_path / "agent-usage.json"
    write_record_atomically(target, {"schemaVersion": 1})
    leftovers = [p for p in tmp_path.iterdir() if p != target]
    assert leftovers == []
