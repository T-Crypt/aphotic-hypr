import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
LIB = REPO / "Configs" / ".local" / "lib" / "aphotic"
EMIT = LIB / "agent_emit.py"


def run_emit(state_home, *args, emit_path=EMIT):
    env = dict(os.environ)
    env["APHOTIC_STATE_HOME"] = str(state_home)
    return subprocess.run(
        [sys.executable, str(emit_path), *args],
        env=env,
        capture_output=True,
        text=True,
    )


def read_events(state_home):
    path = Path(state_home) / "agent-events.jsonl"
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def test_usage_event_lands_in_all_three_sinks(tmp_path):
    proc = run_emit(
        tmp_path,
        "usage",
        "--session", "s1",
        "--harness", "myagent",
        "--model", "qwen3.8",
        "--provider", "ollama",
        "--cwd", "/tmp/work",
        "--tokens-in", "425",
        "--tokens-out", "1180",
        "--cache-read", "900",
        "--cache-write", "12",
        "--reasoning-tokens", "3",
    )
    assert proc.returncode == 0, proc.stderr

    events = read_events(tmp_path)
    assert len(events) == 1
    record = events[0]
    assert record["v"] == 2
    assert record["harness"] == "myagent"
    assert record["sessionId"] == "s1"
    assert record["event"] == "usage"
    assert record["status"] == "running"
    assert isinstance(record["t"], int) and record["t"] > 0
    assert record["model"] == "qwen3.8"
    assert record["provider"] == "ollama"
    assert record["cwd"] == "/tmp/work"
    assert record["inputTokens"] == 425
    assert record["outputTokens"] == 1180
    assert record["cacheReadTokens"] == 900
    assert record["cacheWriteTokens"] == 12
    assert record["reasoningTokens"] == 3

    # The writer's other two sinks: the per-session state file and the
    # per-run archive, so a wrapped harness behaves exactly like a hook.
    session_file = Path(tmp_path) / "agent-sessions" / "s1.json"
    assert session_file.exists()
    state = json.loads(session_file.read_text())
    assert state["harness"] == "myagent"
    assert (Path(tmp_path) / "agent-runs" / "s1.jsonl").exists()


def test_default_status_per_event_kind(tmp_path):
    assert run_emit(tmp_path, "session_start", "--session", "s", "--harness", "h").returncode == 0
    assert run_emit(tmp_path, "session_end", "--session", "s", "--harness", "h").returncode == 0
    events = read_events(tmp_path)
    assert events[0]["event"] == "session_start"
    assert events[0]["status"] == "running"
    assert events[1]["event"] == "session_end"
    assert events[1]["status"] == "ended"
    assert "endReason" not in events[1]


def test_explicit_status_and_end_reason(tmp_path):
    run_emit(tmp_path, "session_end", "--session", "s", "--harness", "h",
             "--end-reason", "clear")
    record = read_events(tmp_path)[0]
    assert record["status"] == "ended"
    assert record["endReason"] == "clear"


def test_session_file_removed_on_end(tmp_path):
    run_emit(tmp_path, "session_start", "--session", "s", "--harness", "h")
    assert (Path(tmp_path) / "agent-sessions" / "s.json").exists()
    run_emit(tmp_path, "session_end", "--session", "s", "--harness", "h")
    assert not (Path(tmp_path) / "agent-sessions" / "s.json").exists()


def test_rejects_unknown_event_kind(tmp_path):
    proc = run_emit(tmp_path, "bogus", "--session", "s", "--harness", "h")
    assert proc.returncode != 0
    assert read_events(tmp_path) == []


def test_rejects_missing_session_and_harness(tmp_path):
    assert run_emit(tmp_path, "turn", "--harness", "h").returncode != 0
    assert run_emit(tmp_path, "turn", "--session", "s").returncode != 0
    assert read_events(tmp_path) == []


def test_rejects_non_numeric_token_count(tmp_path):
    proc = run_emit(tmp_path, "usage", "--session", "s", "--harness", "h",
                    "--tokens-in", "lots")
    assert proc.returncode != 0
    assert read_events(tmp_path) == []


def test_rejects_negative_token_count(tmp_path):
    proc = run_emit(tmp_path, "usage", "--session", "s", "--harness", "h",
                    "--tokens-out", "-5")
    assert proc.returncode != 0
    assert read_events(tmp_path) == []


def test_missing_writer_is_an_error(tmp_path):
    isolated = tmp_path / "isolated"
    isolated.mkdir()
    lone = isolated / "agent_emit.py"
    shutil.copy(EMIT, lone)
    proc = run_emit(tmp_path, "turn", "--session", "s", "--harness", "h",
                    emit_path=lone)
    assert proc.returncode == 1
    assert "writer not found" in proc.stderr
    assert read_events(tmp_path) == []


def test_emitted_record_passes_contract_checks(tmp_path):
    run_emit(tmp_path, "tool_call", "--session", "s", "--harness", "h",
             "--status", "running")
    record = read_events(tmp_path)[0]
    # Same invariants test_harness_hooks_v2.validate_common_fields asserts
    # over the declared fixtures.
    assert record["v"] == 2
    assert isinstance(record["harness"], str) and record["harness"]
    assert isinstance(record["sessionId"], str) and record["sessionId"]
    assert record["event"] in {"session_start", "session_end", "turn",
                               "tool_call", "usage", "quota", "error"}
    assert isinstance(record["t"], int) and not isinstance(record["t"], bool)
    assert record["status"] in {"running", "waiting", "compacting", "idle", "ended"}
