import io
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Configs" / ".local" / "lib" / "aphotic"))
import agent_statusline
from agent_statusline import (
    bare_windows,
    build_quota_event,
    build_record,
    collect_windows,
    format_line,
    main,
    maybe_emit_quota_event,
    merge,
    should_emit_quota,
    window,
)

NOW = 1788700000.0

# The field names below are Claude Code's, not ours: the statusLine
# command's stdin payload nests the windows under `rate_limits` with a
# 0-100 `used_percentage` and an epoch-seconds `resets_at`, and reports
# context fill under `context_window`. Verified against the installed
# binary, so a rename upstream should break these tests loudly rather
# than quietly zero the bars.
PAYLOAD = {
    "model": {"id": "claude-opus-5", "display_name": "Opus 5"},
    "context_window": {
        "total_input_tokens": 120000,
        "context_window_size": 1000000,
        "used_percentage": 12.4,
        "remaining_percentage": 87.6,
    },
    "rate_limits": {
        "five_hour": {"used_percentage": 54.2, "resets_at": 1788710000},
        "seven_day": {"used_percentage": 46, "resets_at": 1789026800},
    },
}


def test_real_payload_shape_yields_both_windows_and_context():
    record = build_record(PAYLOAD, NOW)
    windows = record["providers"]["claude"]["windows"]
    assert windows["fiveHour"] == {"usedPercent": 54.2, "resetsAt": 1788710000}
    assert windows["sevenDay"] == {"usedPercent": 46.0, "resetsAt": 1789026800}
    assert windows["context"]["usedPercent"] == 12.4
    assert windows["context"]["size"] == 1000000
    assert record["providers"]["claude"]["model"] == "Opus 5"
    assert record["capturedAt"] == int(NOW)


def test_missing_rate_limits_is_empty_not_zero():
    # Claude Code omits `rate_limits` entirely when it has no window to
    # report. Zeroed windows would render as empty bars, which reads as
    # "you have used nothing" -- the opposite of "we don't know".
    record = build_record({"model": {"id": "claude-opus-5"}}, NOW)
    assert record["providers"]["claude"]["windows"] == {}
    assert record["providers"]["claude"]["model"] == "claude-opus-5"


def test_spend_limit_window_is_carried_when_present():
    payload = dict(PAYLOAD)
    payload["rate_limits"] = dict(PAYLOAD["rate_limits"])
    payload["rate_limits"]["spend_limit"] = {"used_percentage": 5, "resets_at": 1789000000}
    windows = build_record(payload, NOW)["providers"]["claude"]["windows"]
    assert windows["spendLimit"] == {"usedPercent": 5.0, "resetsAt": 1789000000}


def test_percentages_are_clamped_and_bad_input_drops_the_window():
    assert window({"used_percentage": 140})["usedPercent"] == 100.0
    assert window({"used_percentage": -3})["usedPercent"] == 0.0
    assert window({"used_percentage": "nope"}) is None
    assert window({"resets_at": 123}) is None
    assert window("not a dict") is None


def test_unparseable_reset_falls_back_to_zero():
    assert window({"used_percentage": 10, "resets_at": "soon"})["resetsAt"] == 0
    assert window({"used_percentage": 10})["resetsAt"] == 0


def test_merge_keeps_another_providers_section():
    existing = {
        "schemaVersion": 1,
        "capturedAt": 1,
        "providers": {"codex": {"model": "gpt", "windows": {"fiveHour": {"usedPercent": 3.0, "resetsAt": 0}}}},
    }
    merged = merge(existing, build_record(PAYLOAD, NOW))
    assert set(merged["providers"]) == {"claude", "codex"}
    assert merged["providers"]["codex"]["model"] == "gpt"


def test_merge_discards_a_record_from_a_different_schema():
    existing = {"schemaVersion": 99, "providers": {"codex": {}}}
    merged = merge(existing, build_record(PAYLOAD, NOW))
    assert set(merged["providers"]) == {"claude"}


def test_status_line_names_the_model_and_every_reported_window():
    assert format_line(build_record(PAYLOAD, NOW)) == "Opus 5 · 5h 54% · 7d 46% · ctx 12%"


def test_status_line_omits_what_was_not_reported():
    assert format_line(build_record({"model": {"display_name": "Opus 5"}}, NOW)) == "Opus 5"
    assert format_line(build_record({}, NOW)) == ""


def test_record_is_json_serialisable():
    json.dumps(build_record(PAYLOAD, NOW))


def _isolate_state(tmp_path, monkeypatch):
    """Point every module-level state path at a temp dir, never the real
    ~/.local/state/aphotic."""
    state = tmp_path / "state"
    state.mkdir(parents=True, exist_ok=True)
    monkeypatch.setattr(agent_statusline, "STATE", str(state))
    monkeypatch.setattr(agent_statusline, "QUOTA", str(state / "agent-quota.json"))
    monkeypatch.setattr(agent_statusline, "EVENTS", str(state / "agent-events.jsonl"))
    monkeypatch.setattr(agent_statusline, "QUOTA_THROTTLE", str(state / "agent-quota-throttle.json"))
    return state


def _events(state):
    path = Path(agent_statusline.EVENTS)
    if not path.exists():
        return []
    return [json.loads(l) for l in path.read_text().splitlines() if l]


class TestBareWindows:

    def test_strips_size_but_keeps_used_percent_and_resets_at(self):
        windows = {"context": {"usedPercent": 12.4, "resetsAt": 0, "size": 1000000}}
        assert bare_windows(windows) == {"context": {"usedPercent": 12.4, "resetsAt": 0}}

    def test_empty_windows_yields_empty(self):
        assert bare_windows({}) == {}


class TestBuildQuotaEvent:

    def test_matches_the_v2_quota_schema(self):
        windows = collect_windows(PAYLOAD)
        event = build_quota_event({"session_id": "s1", **PAYLOAD}, windows, NOW)
        assert event["v"] == 2
        assert event["harness"] == "claude"
        assert event["sessionId"] == "s1"
        assert event["event"] == "quota"
        assert event["status"] == "running"
        assert event["provider"] == "anthropic"
        assert event["quota"]["fiveHour"] == {"usedPercent": 54.2, "resetsAt": 1788710000}
        assert "size" not in event["quota"]["context"]
        assert event["t"] == int(NOW * 1000)
        json.dumps(event)

    def test_missing_session_id_is_empty_string_not_a_crash(self):
        event = build_quota_event(PAYLOAD, collect_windows(PAYLOAD), NOW)
        assert event["sessionId"] == ""


class TestShouldEmitQuota:

    def test_first_time_for_a_session_always_emits(self):
        assert should_emit_quota({}, "s1", {"fiveHour": {"usedPercent": 1, "resetsAt": 0}}, NOW)

    def test_within_throttle_window_and_unchanged_is_suppressed(self):
        windows = {"fiveHour": {"usedPercent": 1, "resetsAt": 0}}
        state = {"s1": {"t": NOW, "windows": windows}}
        assert not should_emit_quota(state, "s1", windows, NOW + 30)

    def test_within_throttle_window_but_changed_still_emits(self):
        state = {"s1": {"t": NOW, "windows": {"fiveHour": {"usedPercent": 1, "resetsAt": 0}}}}
        changed = {"fiveHour": {"usedPercent": 2, "resetsAt": 0}}
        assert should_emit_quota(state, "s1", changed, NOW + 30)

    def test_past_throttle_window_emits_even_when_unchanged(self):
        windows = {"fiveHour": {"usedPercent": 1, "resetsAt": 0}}
        state = {"s1": {"t": NOW, "windows": windows}}
        assert should_emit_quota(state, "s1", windows, NOW + 61)


class TestMaybeEmitQuotaEvent:

    def test_no_windows_writes_nothing(self, tmp_path, monkeypatch):
        state = _isolate_state(tmp_path, monkeypatch)
        maybe_emit_quota_event({"session_id": "s1"}, {}, NOW)
        assert _events(state) == []

    def test_first_call_appends_a_quota_line(self, tmp_path, monkeypatch):
        state = _isolate_state(tmp_path, monkeypatch)
        payload = {"session_id": "s1", **PAYLOAD}
        maybe_emit_quota_event(payload, collect_windows(payload), NOW)
        events = _events(state)
        assert len(events) == 1
        assert events[0]["event"] == "quota"

    def test_second_call_within_throttle_and_unchanged_appends_nothing(self, tmp_path, monkeypatch):
        state = _isolate_state(tmp_path, monkeypatch)
        payload = {"session_id": "s1", **PAYLOAD}
        windows = collect_windows(payload)
        maybe_emit_quota_event(payload, windows, NOW)
        maybe_emit_quota_event(payload, windows, NOW + 5)
        assert len(_events(state)) == 1

    def test_changed_values_within_throttle_appends_a_second_line(self, tmp_path, monkeypatch):
        state = _isolate_state(tmp_path, monkeypatch)
        payload = {"session_id": "s1", **PAYLOAD}
        maybe_emit_quota_event(payload, collect_windows(payload), NOW)

        changed = dict(PAYLOAD)
        changed["rate_limits"] = dict(PAYLOAD["rate_limits"])
        changed["rate_limits"]["five_hour"] = {"used_percentage": 90, "resets_at": 1788710000}
        payload2 = {"session_id": "s1", **changed}
        maybe_emit_quota_event(payload2, collect_windows(payload2), NOW + 5)

        events = _events(state)
        assert len(events) == 2
        assert events[1]["quota"]["fiveHour"]["usedPercent"] == 90.0

    def test_two_sessions_throttle_independently(self, tmp_path, monkeypatch):
        state = _isolate_state(tmp_path, monkeypatch)
        windows = collect_windows(PAYLOAD)
        maybe_emit_quota_event({"session_id": "s1", **PAYLOAD}, windows, NOW)
        maybe_emit_quota_event({"session_id": "s2", **PAYLOAD}, windows, NOW)
        events = _events(state)
        assert {e["sessionId"] for e in events} == {"s1", "s2"}


class TestStatuslineNeverRaises:
    """agent_statusline.sh execs into main() and never checks its exit
    status -- a raised exception here surfaces as a broken status line in
    the user's terminal, so main() must swallow everything."""

    def _run(self, tmp_path, monkeypatch, raw):
        _isolate_state(tmp_path, monkeypatch)
        monkeypatch.setattr(sys, "stdin", io.StringIO(raw))
        return main()

    @pytest.mark.parametrize("raw", [
        "",
        "not json",
        "null",
        "42",
        '"a string"',
        "[1, 2, 3]",
        '{"rate_limits": "not a dict"}',
        '{"rate_limits": {"five_hour": "nope"}}',
        '{"context_window": {"used_percentage": "nope"}}',
        '{"model": "not a dict either"}',
        "\x00garbage\x01",
    ])
    def test_garbage_stdin_returns_zero(self, tmp_path, monkeypatch, raw):
        assert self._run(tmp_path, monkeypatch, raw) == 0

    def test_real_payload_writes_quota_and_local_file(self, tmp_path, monkeypatch):
        state = _isolate_state(tmp_path, monkeypatch)
        monkeypatch.setattr(sys, "stdin", io.StringIO(json.dumps({"session_id": "s1", **PAYLOAD})))
        assert main() == 0
        assert (state / "agent-quota.json").exists()
        events = _events(state)
        assert len(events) == 1
        assert events[0]["event"] == "quota"
