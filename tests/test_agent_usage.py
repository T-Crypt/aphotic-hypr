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


def test_real_claude_transcript_shape_nests_model_and_usage_under_message():
    # Regression test for a real bug: this repo's own fixtures used a
    # flat {"model": ..., "usage": ...} shape that doesn't match what
    # Claude Code actually writes -- confirmed against a real machine's
    # live transcripts, model/usage are nested under "message". The
    # parser matched zero real entries ever, so todayTokens silently
    # stayed 0 regardless of actual usage.
    record = build_usage_record(NOW, {"claude": FIXTURES / "claude_real_nested.jsonl"})
    claude = record["providers"]["claude"]
    assert claude["availability"] == "available"
    assert claude["todayTokens"] == (2 + 844) + (3 + 151)
    assert claude["tokensByModel"] == [{"model": "claude-sonnet-5", "tokens": 1000}]


def test_multiple_transcripts_for_one_provider_are_summed_not_picked_one():
    # Regression test for a real bug: a machine with multiple Claude Code
    # project directories (each its own transcript file under
    # ~/.claude/projects/*/*.jsonl) was only ever looking at whichever one
    # file glob() happened to enumerate first, silently showing 0 tokens
    # for a genuinely active session sitting in any other file. A list of
    # sources for one provider must be summed across all of them, not
    # collapsed to one.
    record = build_usage_record(
        NOW,
        {"claude": [FIXTURES / "claude_valid.jsonl", FIXTURES / "claude_valid_2.jsonl"]},
    )
    claude = record["providers"]["claude"]
    assert claude["availability"] == "available"
    assert claude["todayTokens"] == (100 + 50 + 200 + 75) + (10 + 5 + 300 + 100)
    by_model = {m["model"]: m["tokens"] for m in claude["tokensByModel"]}
    assert by_model == {"claude-sonnet-5": 425 + 15, "claude-opus-5": 400}


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
