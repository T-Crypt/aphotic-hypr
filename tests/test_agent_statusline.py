import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Configs" / ".local" / "lib" / "aphotic"))
from agent_statusline import build_record, format_line, merge, window

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
