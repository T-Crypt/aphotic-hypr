import json
from pathlib import Path

import pytest

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "harness-v2"
AGENT_EVENTS_QML = (
    Path(__file__).resolve().parents[1]
    / "Configs"
    / "quickshell"
    / "aphotic"
    / "services"
    / "ai"
    / "AgentEvents.qml"
)

STATUS_ENUM = {"running", "waiting", "compacting", "idle", "ended"}
EVENT_ENUM = {
    "session_start",
    "session_end",
    "turn",
    "tool_call",
    "usage",
    "quota",
    "error",
}
TOOL_STATUS_ENUM = {"running", "completed", "errored"}

# Mirrors the mapping implemented in AgentEvents.qml's normalize(): a
# (event, status, toolStatus) triple to the v1 event name it should
# produce. Kept here as plain data so the test can both check the
# mapping's own logic and confirm each v1 name still appears in the QML
# file (cheap sync check, not a QML interpreter).
V2_TO_V1_EVENT_NAME = {
    ("tool_call", "running"): "pre_tool_use",
    ("tool_call", "completed"): "post_tool_use",
    ("tool_call", "errored"): "post_tool_use_failure",
    ("turn", "running"): "user_prompt_submit",
    ("turn", "idle"): "stop",
    ("turn", "waiting"): "notification",
    ("*", "compacting"): "pre_compact",
}


def validate_common_fields(record: dict) -> list[str]:
    """Hand-written check of the v2 common fields.
    Returns a list of problems; empty means the record is well-formed."""
    problems = []

    if not isinstance(record, dict):
        return ["record is not a JSON object"]

    if record.get("v") != 2:
        problems.append("v must be 2")
    if not isinstance(record.get("harness"), str) or not record["harness"]:
        problems.append("harness must be a non-empty string")
    if not isinstance(record.get("sessionId"), str) or not record["sessionId"]:
        problems.append("sessionId must be a non-empty string")
    if record.get("event") not in EVENT_ENUM:
        problems.append(f"event must be one of {EVENT_ENUM}")
    if not isinstance(record.get("t"), int):
        problems.append("t must be an int (epoch ms)")
    if record.get("status") not in STATUS_ENUM:
        problems.append(f"status must be one of {STATUS_ENUM}")

    if "ts" in record and not isinstance(record["ts"], str):
        problems.append("ts must be a string when present")
    if "model" in record and not isinstance(record["model"], str):
        problems.append("model must be a string when present")
    if "provider" in record and not isinstance(record["provider"], str):
        problems.append("provider must be a string when present")
    if "cwd" in record and not isinstance(record["cwd"], str):
        problems.append("cwd must be a string when present")

    if record.get("event") == "tool_call":
        if "toolStatus" in record and record["toolStatus"] not in TOOL_STATUS_ENUM:
            problems.append(f"toolStatus must be one of {TOOL_STATUS_ENUM}")

    return problems


def load_lines(path: Path) -> list[tuple[str, dict | None]]:
    """Returns (raw_line, parsed_or_None) pairs, one per non-empty line."""
    out = []
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        try:
            out.append((line, json.loads(line)))
        except json.JSONDecodeError:
            out.append((line, None))
    return out


def is_v2(record: dict | None) -> bool:
    return isinstance(record, dict) and record.get("v") == 2


@pytest.mark.parametrize("fixture_name", ["claude.jsonl", "codex.jsonl"])
def test_every_v2_line_validates_and_malformed_lines_do_not(fixture_name):
    lines = load_lines(FIXTURES / fixture_name)

    saw_malformed = False
    saw_v1 = False
    saw_v2 = False

    for raw, record in lines:
        if record is None:
            saw_malformed = True
            continue
        if not isinstance(record, dict):
            continue
        if record.get("v") in (None, 1):
            saw_v1 = True
            continue
        if record.get("v") == 2:
            saw_v2 = True
            problems = validate_common_fields(record)
            assert not problems, f"{fixture_name}: {raw!r} failed: {problems}"

    assert saw_malformed, f"{fixture_name} must contain one malformed line"
    assert saw_v1, f"{fixture_name} must contain one v1 line"
    assert saw_v2, f"{fixture_name} must contain v2 lines"


@pytest.mark.parametrize("fixture_name", ["claude.jsonl", "codex.jsonl"])
def test_fixture_covers_all_seven_event_kinds(fixture_name):
    lines = load_lines(FIXTURES / fixture_name)
    kinds = {r["event"] for _, r in lines if is_v2(r)}
    assert kinds == EVENT_ENUM


@pytest.mark.parametrize("fixture_name", ["claude.jsonl", "codex.jsonl"])
def test_fixture_has_unknown_fields_line(fixture_name):
    lines = load_lines(FIXTURES / fixture_name)
    known_top_level = {
        "v", "harness", "sessionId", "event", "t", "ts", "status", "model",
        "provider", "cwd", "tool", "toolId", "toolStatus", "durationMs",
        "agentId", "agentType", "spawnedAgentId", "inputTokens",
        "outputTokens", "cacheReadTokens", "cacheWriteTokens", "cost",
        "quota", "error", "endReason",
    }
    assert any(
        is_v2(r) and (set(r.keys()) - known_top_level)
        for _, r in lines
    ), f"{fixture_name} must contain a line with unknown fields"


def normalize_v1_event_name(record: dict) -> str:
    """Pure-Python mirror of AgentEvents.qml's normalize()."""
    event = record["event"]
    status = record.get("status")

    if event in ("session_start", "session_end"):
        return event
    if status == "compacting":
        return "pre_compact"
    if event == "tool_call":
        tool_status = record.get("toolStatus")
        return {
            "running": "pre_tool_use",
            "completed": "post_tool_use",
            "errored": "post_tool_use_failure",
        }.get(tool_status, event)
    if event == "turn":
        if status == "running":
            return "user_prompt_submit"
        if status == "waiting":
            return "notification"
        if status == "idle":
            return "subagent_stop" if record.get("agentId") else "stop"
        return event
    return event


def test_normalizer_mapping_matches_design_doc():
    cases = [
        ({"event": "tool_call", "status": "running", "toolStatus": "running"}, "pre_tool_use"),
        ({"event": "tool_call", "status": "running", "toolStatus": "completed"}, "post_tool_use"),
        ({"event": "tool_call", "status": "running", "toolStatus": "errored"}, "post_tool_use_failure"),
        ({"event": "turn", "status": "running"}, "user_prompt_submit"),
        ({"event": "turn", "status": "idle"}, "stop"),
        ({"event": "turn", "status": "waiting"}, "notification"),
        ({"event": "turn", "status": "idle", "agentId": "a1"}, "subagent_stop"),
        ({"event": "turn", "status": "compacting"}, "pre_compact"),
        ({"event": "session_start", "status": "running"}, "session_start"),
        ({"event": "session_end", "status": "ended"}, "session_end"),
        ({"event": "usage", "status": "running"}, "usage"),
        ({"event": "quota", "status": "running"}, "quota"),
        ({"event": "error", "status": "idle"}, "error"),
    ]
    for record, expected in cases:
        assert normalize_v1_event_name(record) == expected


def test_agent_events_qml_contains_every_mapped_v1_name():
    text = AGENT_EVENTS_QML.read_text()
    v1_names = {
        "pre_tool_use", "post_tool_use", "post_tool_use_failure",
        "user_prompt_submit", "stop", "pre_compact", "notification", "subagent_stop",
        "session_start", "session_end",
    }
    for name in v1_names:
        assert f'"{name}"' in text, f"{name!r} not found in AgentEvents.qml"


def test_fixtures_replay_through_normalizer_without_status_regression():
    """The normalizer must not send usage/quota/error kinds through the
    v1 status-changing branch: applyTo() special-cases them so a running
    session doesn't get bounced to idle by an additive record."""
    for fixture_name in ("claude.jsonl", "codex.jsonl"):
        lines = load_lines(FIXTURES / fixture_name)
        status_neutral_kinds = {"usage", "quota", "error"}
        for _, record in lines:
            if is_v2(record) and record["event"] in status_neutral_kinds:
                mapped = normalize_v1_event_name(record)
                assert mapped in status_neutral_kinds
