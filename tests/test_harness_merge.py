import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Configs" / ".local" / "lib" / "aphotic"))
import harnesses_merge

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "harnesses"
NOW = datetime(2026, 10, 16, 9, 30, 0, tzinfo=timezone.utc)


def setup_env(tmp_path, plugin_names=(), dropins=(), disabled=()):
    """Lay out a config/plugins/state tree the way a real machine has one."""
    config = tmp_path / "config"
    plugins = tmp_path / "plugins"
    state = tmp_path / "state"
    (config / harnesses_merge.DROPIN_DIR_NAME).mkdir(parents=True)
    for name in plugin_names:
        source = FIXTURES / "plugins" / name
        (plugins / name).mkdir(parents=True)
        (plugins / name / "plugin.toml").write_text(
            (source / "plugin.toml").read_text(encoding="utf-8"), encoding="utf-8"
        )
    for name in dropins:
        source = FIXTURES / "dropins" / name
        (config / harnesses_merge.DROPIN_DIR_NAME / name).write_text(
            source.read_text(encoding="utf-8"), encoding="utf-8"
        )
    installed = {name: {} for name in plugin_names}
    state.mkdir(parents=True)
    (state / harnesses_merge.PLUGINS_STATE_NAME).write_text(
        json.dumps({"installed": installed, "disabled": list(disabled)}), encoding="utf-8"
    )
    return config, plugins, state


def run_merge(config, plugins, state, now=NOW):
    warnings = []
    record = harnesses_merge.merge(config, plugins, state, now=now, emit=warnings.append)
    return record, warnings


def ids_of(record):
    return [h["id"] for h in record["harnesses"]]


def test_shipped_manifest_shapes_parse(tmp_path):
    config, plugins, state = setup_env(
        tmp_path,
        plugin_names=("claude-hooks", "codex-hooks", "opencode-hooks", "pi-hooks"),
        dropins=("amp.toml",),
    )
    record, warnings = run_merge(config, plugins, state)
    assert warnings == []
    assert record["schemaVersion"] == 1
    assert ids_of(record) == ["claude", "codex", "opencode", "pi", "omp", "amp"]
    claude = record["harnesses"][0]
    assert claude == {
        "id": "claude",
        "source": "plugin:claude-hooks",
        "label": "Claude Code",
        "icon": "smart_toy",
        "provider": "anthropic",
        "match": "claude",
        "launch": ["claude"],
        "usage": "scan",
        "scan": ".claude/projects/*/*.jsonl",
        "context": "statusline",
        "chat": True,
    }
    codex = record["harnesses"][1]
    # label and icon were never declared: they fall back silently.
    assert codex["label"] == "codex"
    assert codex["icon"] == "terminal"
    assert codex["provider"] == "openai"
    assert codex["usage"] == "scan"
    # Pi and OMP ship no match: no process reconcile, event tail only.
    pi = record["harnesses"][3]
    omp = record["harnesses"][4]
    assert pi["match"] == "" and pi["usage"] == "stream"
    assert omp["match"] == "" and omp["usage"] == "stream"
    amp = record["harnesses"][5]
    assert amp == {
        "id": "amp",
        "source": "drop-in:amp.toml",
        "label": "Amp",
        "icon": "terminal",
        "provider": "",
        "match": "amp",
        "launch": ["amp"],
        "usage": "stream",
        "scan": "",
        "context": "stream",
        "chat": False,
    }


def test_merge_writes_the_record_atomically(tmp_path):
    config, plugins, state = setup_env(tmp_path, plugin_names=("claude-hooks",))
    run_merge(config, plugins, state)
    record_file = state / harnesses_merge.RECORD_NAME
    leftovers = [
        p for p in record_file.parent.iterdir()
        if p.suffix == ".tmp" and p.name != record_file.name
    ]
    assert record_file.is_file()
    assert leftovers == []


def test_dropin_overrides_plugin_wholesale(tmp_path):
    config, plugins, state = setup_env(
        tmp_path, plugin_names=("claude-hooks",), dropins=("claude.toml",)
    )
    record, warnings = run_merge(config, plugins, state)
    assert ids_of(record) == ["claude"]
    # Wholesale: the fields the drop-in leaves out fall back to defaults,
    # they are not inherited from the plugin descriptor.
    assert record["harnesses"][0] == {
        "id": "claude",
        "source": "drop-in:claude.toml",
        "label": "Claude",
        "icon": "terminal",
        "provider": "",
        "match": "",
        "launch": [],
        "usage": "stream",
        "scan": "",
        "context": "stream",
        "chat": False,
    }
    assert warnings == [
        "aphotic harness: drop-in 'claude.toml' overrides the descriptor from claude-hooks"
    ]


def test_first_plugin_in_registry_order_wins_on_collision(tmp_path):
    config, plugins, state = setup_env(
        tmp_path, plugin_names=("beta-hooks", "alpha-hooks")
    )
    record, warnings = run_merge(config, plugins, state)
    assert ids_of(record) == ["dup"]
    assert record["harnesses"][0]["label"] == "Beta"
    assert warnings == [
        "aphotic harness: 'dup' declared by both beta-hooks and alpha-hooks -- alpha-hooks dropped"
    ]


def test_plugin_without_harness_hook_capability_is_ignored(tmp_path):
    config, plugins, state = setup_env(tmp_path, plugin_names=("no-cap-hooks",))
    record, warnings = run_merge(config, plugins, state)
    assert record["harnesses"] == []
    assert warnings == []


def test_disabled_plugin_is_ignored(tmp_path):
    config, plugins, state = setup_env(
        tmp_path, plugin_names=("claude-hooks",), disabled=("claude-hooks",)
    )
    record, warnings = run_merge(config, plugins, state)
    assert record["harnesses"] == []
    assert warnings == []


def test_zero_descriptors_writes_an_empty_list(tmp_path):
    config, plugins, state = setup_env(tmp_path)
    record, warnings = run_merge(config, plugins, state)
    assert record == {
        "schemaVersion": 1,
        "generatedAt": NOW.isoformat(),
        "harnesses": [],
    }
    written = json.loads((state / harnesses_merge.RECORD_NAME).read_text(encoding="utf-8"))
    assert written == record


def test_bad_id_is_dropped_with_exact_warning(tmp_path):
    config, plugins, state = setup_env(tmp_path, dropins=("Bad_ID.toml",))
    record, warnings = run_merge(config, plugins, state)
    assert record["harnesses"] == []
    assert warnings == [
        "aphotic harness: drop-in:Bad_ID.toml: id 'Bad_ID' is not lowercase letters, "
        "digits, hyphens or underscores -- dropped"
    ]


def test_dropin_subtable_mismatch_is_dropped_with_exact_warning(tmp_path):
    config, plugins, state = setup_env(tmp_path, dropins=("mismatched.toml",))
    record, warnings = run_merge(config, plugins, state)
    assert record["harnesses"] == []
    assert warnings == [
        "aphotic harness: drop-in 'mismatched.toml': [harness.other] does not match "
        "the filename -- dropped"
    ]


def test_field_validation_warnings_fire_with_exact_text(tmp_path):
    config, plugins, state = setup_env(tmp_path, dropins=("sloppy.toml", "noscan.toml"))
    record, warnings = run_merge(config, plugins, state)
    # label falls back to the id and icon to "terminal" with no warning;
    # the other fields each emit theirs and fall back. Drop-ins are
    # sorted by filename, so noscan lands first.
    assert ids_of(record) == ["noscan", "sloppy"]
    sloppy = record["harnesses"][1]
    assert sloppy["label"] == "sloppy"
    assert sloppy["icon"] == "terminal"
    assert sloppy["match"] == ""
    assert sloppy["launch"] == []
    assert sloppy["usage"] == "stream"
    assert sloppy["context"] == "stream"
    assert sloppy["chat"] is False
    assert warnings == [
        "aphotic harness: drop-in:noscan.toml: 'noscan' scan '/etc/*' is not a "
        "home-relative glob -- using stream",
        "aphotic harness: drop-in:sloppy.toml: 'sloppy' match 'bad match' is not a "
        "process name -- process reconcile off",
        "aphotic harness: drop-in:sloppy.toml: 'sloppy' launch must be a list of "
        "strings -- launch hidden",
        "aphotic harness: drop-in:sloppy.toml: 'sloppy' usage 'turbo' is not stream "
        "or scan -- using stream",
        "aphotic harness: drop-in:sloppy.toml: 'sloppy' context 'nope' is not stream "
        "or statusline -- using stream",
        "aphotic harness: drop-in:sloppy.toml: 'sloppy' chat must be true or false -- "
        "using false",
    ]


def test_one_bad_dropin_leaves_the_rest_intact(tmp_path):
    config, plugins, state = setup_env(
        tmp_path, plugin_names=("claude-hooks",), dropins=("unparsable.toml", "amp.toml")
    )
    record, warnings = run_merge(config, plugins, state)
    assert ids_of(record) == ["claude", "amp"]
    assert warnings == [
        "aphotic harness: drop-in 'unparsable.toml' did not parse -- skipped"
    ]


def test_merge_is_idempotent_apart_from_generated_at(tmp_path):
    config, plugins, state = setup_env(
        tmp_path,
        plugin_names=("claude-hooks", "pi-hooks"),
        dropins=("amp.toml", "sloppy.toml"),
    )
    first, first_warnings = run_merge(config, plugins, state, now=NOW)
    second, second_warnings = run_merge(
        config, plugins, state, now=NOW + timedelta(hours=1)
    )
    assert first_warnings == second_warnings
    on_disk = json.loads((state / harnesses_merge.RECORD_NAME).read_text(encoding="utf-8"))
    assert on_disk == second
    assert second["generatedAt"] == (NOW + timedelta(hours=1)).isoformat()
    del first["generatedAt"], second["generatedAt"]
    assert first == second


def test_cli_main_uses_xdg_paths(tmp_path):
    config, plugins, state = setup_env(tmp_path, plugin_names=("claude-hooks",))
    env = {
        **os.environ,
        "APHOTIC_CONFIG_HOME": str(config),
        "APHOTIC_PLUGINS_DIR": str(plugins),
        "APHOTIC_STATE_HOME": str(state),
    }
    script = (
        Path(__file__).resolve().parents[1]
        / "Configs" / ".local" / "lib" / "aphotic" / "harnesses_merge.py"
    )
    result = subprocess.run(
        [sys.executable, str(script)], env=env, capture_output=True, text=True
    )
    assert result.returncode == 0, result.stderr
    record_file = state / harnesses_merge.RECORD_NAME
    assert record_file.is_file()
    written = json.loads(record_file.read_text(encoding="utf-8"))
    assert ids_of(written) == ["claude"]
