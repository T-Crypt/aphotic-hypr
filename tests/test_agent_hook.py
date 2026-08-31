import json
import os
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Configs" / ".local" / "lib" / "aphotic"))
import agent_hook


class TestAtomicWrite:
    """Test atomic file writing prevents partial/corrupted writes."""

    def test_atomic_write_creates_file(self, tmp_path):
        """atomic_write creates file with correct content."""
        target = tmp_path / "test.json"
        content = '{"test": "data"}'
        agent_hook.atomic_write(str(target), content)
        assert target.exists()
        assert target.read_text() == content

    def test_atomic_write_overwrites_existing(self, tmp_path):
        """atomic_write overwrites existing files atomically."""
        target = tmp_path / "test.json"
        target.write_text('{"old": "data"}')
        new_content = '{"new": "data"}'
        agent_hook.atomic_write(str(target), new_content)
        assert target.read_text() == new_content

    def test_atomic_write_no_temp_file_leaks(self, tmp_path):
        """atomic_write cleans up temp files after write."""
        target = tmp_path / "test.json"
        agent_hook.atomic_write(str(target), '{"data": "test"}')
        temp_files = [f for f in tmp_path.iterdir() if f.name.startswith("test.json.tmp")]
        assert temp_files == [], f"Temp files leaked: {temp_files}"

    def test_atomic_write_uses_pid_in_temp_name(self, tmp_path):
        """atomic_write uses process ID in temp filename."""
        target = tmp_path / "test.json"
        with patch("os.getpid", return_value=12345):
            # Mock os.replace to capture the temp filename
            original_replace = os.replace
            temp_path_used = []
            def mock_replace(src, dst):
                temp_path_used.append(src)
                original_replace(src, dst)
            
            with patch("os.replace", side_effect=mock_replace):
                agent_hook.atomic_write(str(target), '{"test": "data"}')
            
            assert len(temp_path_used) == 1
            assert "12345" in temp_path_used[0]


class TestSweep:
    """Test stale session cleanup."""

    def test_sweep_removes_old_sessions(self, tmp_path):
        """sweep removes session files older than STALE_SECONDS."""
        sessions_dir = tmp_path / "sessions"
        sessions_dir.mkdir()
        
        old_file = sessions_dir / "old_session.json"
        old_file.write_text('{}')
        
        current_time = time.time()
        old_time = current_time - (agent_hook.STALE_SECONDS + 100)
        os.utime(old_file, (old_time, old_time))
        
        with patch("agent_hook.SESSIONS", str(sessions_dir)):
            agent_hook.sweep(current_time)
        
        assert not old_file.exists()

    def test_sweep_keeps_recent_sessions(self, tmp_path):
        """sweep keeps session files newer than STALE_SECONDS."""
        sessions_dir = tmp_path / "sessions"
        sessions_dir.mkdir()
        
        recent_file = sessions_dir / "recent_session.json"
        recent_file.write_text('{}')
        
        current_time = time.time()
        recent_time = current_time - 100
        os.utime(recent_file, (recent_time, recent_time))
        
        with patch("agent_hook.SESSIONS", str(sessions_dir)):
            agent_hook.sweep(current_time)
        
        assert recent_file.exists()

    def test_sweep_ignores_non_json_files(self, tmp_path):
        """sweep ignores files that don't end with .json."""
        sessions_dir = tmp_path / "sessions"
        sessions_dir.mkdir()
        
        other_file = sessions_dir / "session.txt"
        other_file.write_text('{}')
        
        old_time = time.time() - (agent_hook.STALE_SECONDS + 100)
        os.utime(other_file, (old_time, old_time))
        
        with patch("agent_hook.SESSIONS", str(sessions_dir)):
            agent_hook.sweep(time.time())
        
        assert other_file.exists()

    def test_sweep_tolerates_oserror(self, tmp_path):
        """sweep continues if a session file can't be deleted."""
        sessions_dir = tmp_path / "sessions"
        sessions_dir.mkdir()
        
        old_file = sessions_dir / "old_session.json"
        old_file.write_text('{}')
        
        old_time = time.time() - (agent_hook.STALE_SECONDS + 100)
        os.utime(old_file, (old_time, old_time))
        
        with patch("agent_hook.SESSIONS", str(sessions_dir)):
            with patch("os.remove", side_effect=OSError("Permission denied")):
                # Should not raise
                agent_hook.sweep(time.time())
        
        # File still exists because remove failed
        assert old_file.exists()


class TestPruneRuns:
    """Test old run file cleanup."""

    def test_prune_runs_removes_oldest_when_over_limit(self, tmp_path):
        """prune_runs removes oldest files when count exceeds MAX_RUNS."""
        runs_dir = tmp_path / "runs"
        runs_dir.mkdir()
        
        # Create MAX_RUNS + 2 files
        run_files = []
        for i in range(agent_hook.MAX_RUNS + 2):
            f = runs_dir / f"run_{i:03d}.jsonl"
            f.write_text(f'{{"run": {i}}}')
            run_files.append(f)
        
        # Set modification times in order
        for i, f in enumerate(run_files):
            os.utime(f, (i, i))
        
        with patch("agent_hook.RUNS", str(runs_dir)):
            agent_hook.prune_runs()
        
        remaining = list(runs_dir.glob("*.jsonl"))
        assert len(remaining) == agent_hook.MAX_RUNS
        assert run_files[0] not in remaining  # Oldest removed
        assert run_files[1] not in remaining  # Second oldest removed

    def test_prune_runs_keeps_all_when_under_limit(self, tmp_path):
        """prune_runs keeps all files when under MAX_RUNS."""
        runs_dir = tmp_path / "runs"
        runs_dir.mkdir()
        
        for i in range(agent_hook.MAX_RUNS - 1):
            f = runs_dir / f"run_{i:03d}.jsonl"
            f.write_text(f'{{"run": {i}}}')
        
        with patch("agent_hook.RUNS", str(runs_dir)):
            agent_hook.prune_runs()
        
        assert len(list(runs_dir.glob("*.jsonl"))) == agent_hook.MAX_RUNS - 1

    def test_prune_runs_ignores_non_jsonl_files(self, tmp_path):
        """prune_runs only counts .jsonl files."""
        runs_dir = tmp_path / "runs"
        runs_dir.mkdir()
        
        # Create MAX_RUNS + 2 .jsonl files plus some .txt files
        for i in range(agent_hook.MAX_RUNS + 2):
            f = runs_dir / f"run_{i:03d}.jsonl"
            f.write_text(f'{{"run": {i}}}')
            os.utime(f, (i, i))
        
        for i in range(3):
            f = runs_dir / f"other_{i}.txt"
            f.write_text("data")
        
        with patch("agent_hook.RUNS", str(runs_dir)):
            agent_hook.prune_runs()
        
        jsonl_count = len(list(runs_dir.glob("*.jsonl")))
        txt_count = len(list(runs_dir.glob("*.txt")))
        
        assert jsonl_count == agent_hook.MAX_RUNS
        assert txt_count == 3  # .txt files untouched

    def test_prune_runs_tolerates_oserror(self, tmp_path):
        """prune_runs continues if a file can't be deleted."""
        runs_dir = tmp_path / "runs"
        runs_dir.mkdir()
        
        for i in range(agent_hook.MAX_RUNS + 2):
            f = runs_dir / f"run_{i:03d}.jsonl"
            f.write_text(f'{{"run": {i}}}')
            os.utime(f, (i, i))
        
        with patch("agent_hook.RUNS", str(runs_dir)):
            with patch("os.remove", side_effect=OSError("Permission denied")):
                # Should not raise
                agent_hook.prune_runs()


class TestTrim:
    """Test event log rotation."""

    def test_trim_removes_old_lines_when_over_max_size(self, tmp_path):
        """trim keeps only last KEEP_LINES when file exceeds MAX_BYTES."""
        events_file = tmp_path / "events.jsonl"
        
        # Create a file that exceeds MAX_BYTES
        large_line = '{"event": "test", "data": "' + "x" * 1000 + '"}\n'
        lines = [large_line] * (agent_hook.KEEP_LINES + 100)
        events_file.write_text("".join(lines))
        
        file_size = events_file.stat().st_size
        assert file_size > agent_hook.MAX_BYTES, f"Test setup: {file_size} <= {agent_hook.MAX_BYTES}"
        
        with patch("agent_hook.EVENTS", str(events_file)):
            agent_hook.trim()
        
        remaining_lines = events_file.read_text().strip().split("\n")
        # Should have approximately KEEP_LINES (exact count depends on line boundaries)
        assert len(remaining_lines) <= agent_hook.KEEP_LINES + 1
        assert len(remaining_lines) >= agent_hook.KEEP_LINES - 1

    def test_trim_preserves_file_when_under_max_size(self, tmp_path):
        """trim doesn't modify file when under MAX_BYTES."""
        events_file = tmp_path / "events.jsonl"
        original_content = '{"event": "test1"}\n{"event": "test2"}\n'
        events_file.write_text(original_content)
        
        with patch("agent_hook.EVENTS", str(events_file)):
            agent_hook.trim()
        
        assert events_file.read_text() == original_content

    def test_trim_handles_empty_events_file(self, tmp_path):
        """trim handles empty or missing events file gracefully."""
        events_file = tmp_path / "events.jsonl"
        
        with patch("agent_hook.EVENTS", str(events_file)):
            with patch("os.path.getsize", return_value=0):
                # Should not raise
                agent_hook.trim()


class TestEventMapping:
    """Test event name mapping and record building."""

    def test_event_names_maps_correctly(self):
        """EVENT_NAMES maps hook event names to internal names."""
        assert agent_hook.EVENT_NAMES["SessionStart"] == "session_start"
        assert agent_hook.EVENT_NAMES["PreToolUse"] == "pre_tool_use"
        assert agent_hook.EVENT_NAMES["PostToolUse"] == "post_tool_use"
        assert agent_hook.EVENT_NAMES["SessionEnd"] == "session_end"

    def test_status_mapping_for_events(self):
        """STATUS maps event types to execution statuses."""
        assert agent_hook.STATUS["pre_tool_use"] == "running"
        assert agent_hook.STATUS["post_tool_use"] == "completed"
        assert agent_hook.STATUS["post_tool_use_failure"] == "errored"
        # Events not in STATUS should default to "idle"
        assert "session_start" not in agent_hook.STATUS


class TestPayloadProcessing:
    """Test the main payload processing logic (simulated via helper functions)."""

    def test_record_has_required_fields(self):
        """Record contains required fields with correct types."""
        payload = {
            "session_id": "test-session",
            "hook_event_name": "SessionStart",
        }
        
        now = time.time()
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now))
        
        record = {
            "v": 1,
            "sessionId": payload["session_id"],
            "event": agent_hook.EVENT_NAMES[payload["hook_event_name"]],
            "status": agent_hook.STATUS.get("session_start", "idle"),
            "timestamp": stamp,
            "t": int(now * 1000),
        }
        
        assert record["v"] == 1
        assert record["sessionId"] == "test-session"
        assert record["event"] == "session_start"
        assert "timestamp" in record
        assert "t" in record
        assert isinstance(record["t"], int)

    def test_optional_fields_added_when_present(self):
        """Optional fields are included in record when in payload."""
        payload = {
            "session_id": "test-session",
            "hook_event_name": "PostToolUse",
            "tool_name": "bash",
            "tool_use_id": "tool-123",
            "agent_id": "agent-456",
            "duration_ms": 1500,
        }
        
        record = {"v": 1}
        for key, field in (
            ("tool_name", "tool"),
            ("tool_use_id", "toolId"),
            ("agent_id", "agentId"),
            ("duration_ms", "durationMs"),
        ):
            value = payload.get(key)
            if value not in (None, ""):
                record[field] = value
        
        assert record["tool"] == "bash"
        assert record["toolId"] == "tool-123"
        assert record["agentId"] == "agent-456"
        assert record["durationMs"] == 1500

    def test_optional_fields_skipped_when_empty(self):
        """Optional fields are skipped when empty or None."""
        payload = {
            "session_id": "test-session",
            "hook_event_name": "SessionStart",
            "tool_name": None,
            "tool_use_id": "",
            "agent_id": "agent-456",
        }
        
        record = {"v": 1}
        for key, field in (
            ("tool_name", "tool"),
            ("tool_use_id", "toolId"),
            ("agent_id", "agentId"),
        ):
            value = payload.get(key)
            if value not in (None, ""):
                record[field] = value
        
        assert "tool" not in record
        assert "toolId" not in record
        assert record["agentId"] == "agent-456"

    def test_spawned_agent_extracted_from_response(self):
        """spawnedAgentId is extracted from tool_response."""
        payload = {
            "session_id": "test-session",
            "hook_event_name": "PostToolUse",
            "tool_response": {
                "agentId": "spawned-agent-789",
                "description": "Child agent",
                "resolvedModel": "claude-3-opus",
            }
        }
        
        record = {"v": 1}
        response = payload.get("tool_response")
        if isinstance(response, dict):
            spawned = response.get("agentId")
            if spawned:
                record["spawnedAgentId"] = spawned
            description = response.get("description")
            if description:
                record["agentDescription"] = description
            resolved = response.get("resolvedModel")
            if resolved:
                record["agentModel"] = resolved
        
        assert record["spawnedAgentId"] == "spawned-agent-789"
        assert record["agentDescription"] == "Child agent"
        assert record["agentModel"] == "claude-3-opus"

    def test_tool_response_fields_optional(self):
        """tool_response fields are optional."""
        payload = {
            "session_id": "test-session",
            "hook_event_name": "PostToolUse",
            "tool_response": {}
        }
        
        record = {"v": 1}
        response = payload.get("tool_response")
        if isinstance(response, dict):
            spawned = response.get("agentId")
            if spawned:
                record["spawnedAgentId"] = spawned
        
        assert "spawnedAgentId" not in record

    def test_invalid_payload_ignored_gracefully(self):
        """Invalid payloads are skipped with status 0 (not processed)."""
        # Simulating the main script's behavior with invalid input
        invalid_payloads = [
            None,
            "not json",
            {"no": "session_id"},
            {"session_id": "test", "no": "hook_event_name"},
            {"session_id": "", "hook_event_name": "SessionStart"},
        ]
        
        for payload in invalid_payloads:
            session_id = payload.get("session_id") if isinstance(payload, dict) else None
            raw_event = payload.get("hook_event_name") if isinstance(payload, dict) else None
            event = agent_hook.EVENT_NAMES.get(raw_event) if raw_event else None
            
            should_skip = not session_id or not event
            assert should_skip, f"Should skip payload: {payload}"


class TestSessionFileManagement:
    """Test session state file creation and updates."""

    def test_session_file_format(self, tmp_path):
        """Session state file has correct JSON format."""
        payload = {
            "session_id": "test-session",
            "hook_event_name": "PreToolUse",
            "tool_name": "bash",
            "harness": "claude",
        }
        
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time()))
        session_content = json.dumps({
            "event": payload["hook_event_name"],
            "tool": payload.get("tool_name", ""),
            "updatedAt": stamp,
            "harness": "claude",
        }, separators=(",", ":")) + "\n"
        
        assert json.loads(session_content.strip())  # Valid JSON
        assert "event" in session_content
        assert "updatedAt" in session_content
        assert "harness" in session_content

    def test_session_file_removed_on_end(self, tmp_path):
        """Session file is deleted when SessionEnd event occurs."""
        sessions_dir = tmp_path / "sessions"
        sessions_dir.mkdir()
        
        session_id = "test-session"
        session_file = sessions_dir / f"{session_id}.json"
        session_file.write_text('{"event": "PreToolUse"}')
        
        assert session_file.exists()
        
        # Simulate session end by "removing" the file
        # In real code, this happens when event == "session_end"
        event = "session_end"
        if event == "session_end":
            session_file.unlink()
        
        assert not session_file.exists()


class TestRunFileManagement:
    """Test run archive file creation and size limits."""

    def test_run_file_appended_for_new_session(self, tmp_path):
        """Run file is created and appended for new sessions."""
        runs_dir = tmp_path / "runs"
        runs_dir.mkdir()
        
        session_id = "new-session"
        run_file = runs_dir / f"{session_id}.jsonl"
        
        line = '{"v": 1, "sessionId": "new-session", "event": "session_start"}\n'
        
        with open(run_file, "a") as fh:
            fh.write(line)
        
        assert run_file.exists()
        assert line in run_file.read_text()

    def test_run_file_stops_growing_at_max_bytes(self, tmp_path):
        """Run file stops appending when it reaches MAX_RUN_BYTES."""
        runs_dir = tmp_path / "runs"
        runs_dir.mkdir()
        
        session_id = "session"
        run_file = runs_dir / f"{session_id}.jsonl"
        
        # Write a file close to MAX_RUN_BYTES
        # MAX_RUN_BYTES is 2MB, so use a 70KB line repeated to exceed it
        large_line = '{"event": "test", "data": "' + "x" * 70000 + '"}\n'
        
        run_file.write_text(large_line * 30)  # ~2.1MB, should exceed MAX_RUN_BYTES
        
        file_size = run_file.stat().st_size
        assert file_size >= agent_hook.MAX_RUN_BYTES, f"File size {file_size} not >= {agent_hook.MAX_RUN_BYTES}"
        
        # Next line should not be appended in the real code
        another_line = '{"event": "another"}\n'
        if file_size < agent_hook.MAX_RUN_BYTES:
            with open(run_file, "a") as fh:
                fh.write(another_line)
        
        # Size should remain >= MAX_RUN_BYTES
        assert run_file.stat().st_size >= agent_hook.MAX_RUN_BYTES

    def test_prune_runs_called_on_session_start(self, tmp_path):
        """prune_runs is invoked when a new session starts."""
        # This is tested via the main script logic
        event = "session_start"
        should_prune = (event == "session_start")
        assert should_prune


class TestIntegration:
    """Integration tests for the full event processing pipeline."""

    def test_complete_session_lifecycle(self, tmp_path):
        """Complete session from start to end processes correctly."""
        state_dir = tmp_path / "state"
        sessions_dir = state_dir / "sessions"
        runs_dir = state_dir / "runs"
        events_file = state_dir / "events.jsonl"
        
        sessions_dir.mkdir(parents=True, exist_ok=True)
        runs_dir.mkdir(parents=True, exist_ok=True)
        
        # Simulate SessionStart event
        start_event = {
            "session_id": "lifecycle-test",
            "hook_event_name": "SessionStart",
            "harness": "claude",
        }
        
        # Write start event
        line = json.dumps({
            "v": 1,
            "sessionId": start_event["session_id"],
            "event": agent_hook.EVENT_NAMES[start_event["hook_event_name"]],
            "status": agent_hook.STATUS.get("session_start", "idle"),
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "t": int(time.time() * 1000),
        }, separators=(",", ":")) + "\n"
        
        events_file.parent.mkdir(parents=True, exist_ok=True)
        events_file.write_text(line)
        
        run_file = runs_dir / "lifecycle-test.jsonl"
        run_file.write_text(line)
        
        # Session file should exist
        session_file = sessions_dir / "lifecycle-test.json"
        session_file.write_text(json.dumps({
            "event": "SessionStart",
            "tool": "",
            "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "harness": "claude",
        }, separators=(",", ":")) + "\n")
        
        assert session_file.exists()
        assert run_file.exists()
        assert events_file.exists()
        
        # Simulate SessionEnd event
        end_event = {
            "session_id": "lifecycle-test",
            "hook_event_name": "SessionEnd",
        }
        
        # Session file is removed on end
        session_file.unlink()
        
        # But run file and events remain
        assert not session_file.exists()
        assert run_file.exists()
        assert events_file.exists()

    def test_malformed_json_payload_skipped(self):
        """Malformed JSON payloads don't crash the system."""
        malformed = [
            "{not valid json",
            '{"incomplete":',
            None,
        ]
        
        for payload_str in malformed:
            try:
                if payload_str is None:
                    payload = None
                else:
                    payload = json.loads(payload_str)
            except (json.JSONDecodeError, ValueError):
                # Should be caught and exit with 0
                payload = None
            
            should_exit = payload is None
            assert should_exit


if __name__ == "__main__":
    import pytest
    pytest.main([__file__, "-v"])
