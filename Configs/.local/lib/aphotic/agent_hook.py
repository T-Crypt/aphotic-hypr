#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: Aphotic-Hypr contributors
"""aphotic agent hook worker -- see agent_hook.sh for why this is one
process and why nothing in here is allowed to raise."""
import json, os, sys, time

STATE = os.environ.get("APHOTIC_STATE_HOME", os.path.expanduser("~/.local/state/aphotic"))
SESSIONS = os.path.join(STATE, "agent-sessions")
EVENTS = os.path.join(STATE, "agent-events.jsonl")
RUNS = os.path.join(STATE, "agent-runs")
MAX_BYTES = 512 * 1024
KEEP_LINES = 1000
STALE_SECONDS = 12 * 60 * 60
MAX_RUNS = 25
MAX_RUN_BYTES = 2 * 1024 * 1024

EVENT_NAMES = {
    "SessionStart": "session_start",
    "PreToolUse": "pre_tool_use",
    "PostToolUse": "post_tool_use",
    "PostToolUseFailure": "post_tool_use_failure",
    "Notification": "notification",
    "Stop": "stop",
    "SubagentStop": "subagent_stop",
    "SessionEnd": "session_end",
}
STATUS = {
    "pre_tool_use": "running",
    "post_tool_use": "completed",
    "post_tool_use_failure": "errored",
}


def atomic_write(path, text):
    """Write `text` to `path` atomically.

    The function writes to a temporary file in the same directory and then
    atomically replaces the destination with os.replace. This avoids leaving a
    partially-written file if the process is interrupted.
    """
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w") as fh:
        fh.write(text)
    os.replace(tmp, path)


def sweep(now):
    """Remove stale per-session JSON files from the sessions directory.

    Any session file whose modification time is older than STALE_SECONDS
    is removed. Fail silently on filesystem errors to avoid crashing the
    hook worker: this script must never raise in normal operation.
    """
    for name in os.listdir(SESSIONS):
        if not name.endswith(".json"):
            continue
        path = os.path.join(SESSIONS, name)
        try:
            if now - os.path.getmtime(path) > STALE_SECONDS:
                os.remove(path)
        except OSError:
            pass


def prune_runs():
    """Prune old per-session run archive files to limit disk usage.

    Keeps at most MAX_RUNS recent run files (sorted by modification time) and
    deletes older ones. Any filesystem error is ignored to keep the worker
    robust against transient IO failures.
    """
    runs = [os.path.join(RUNS, n) for n in os.listdir(RUNS) if n.endswith(".jsonl")]
    if len(runs) <= MAX_RUNS:
        return
    runs.sort(key=os.path.getmtime)
    for path in runs[:len(runs) - MAX_RUNS]:
        try:
            os.remove(path)
        except OSError:
            pass


def trim():
    """Trim the live events file to a bounded tail.

    If the EVENTS file grows larger than MAX_BYTES, keep only the last
    KEEP_LINES lines and rewrite the file atomically. This keeps the
    live in-repo tail small while longer archives are preserved per-run.
    """
    if os.path.getsize(EVENTS) <= MAX_BYTES:
        return
    with open(EVENTS) as fh:
        lines = fh.readlines()[-KEEP_LINES:]
    atomic_write(EVENTS, "".join(lines))


try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

session_id = payload.get("session_id") or ""
raw_event = payload.get("hook_event_name") or ""
event = EVENT_NAMES.get(raw_event)
if not session_id or not event:
    sys.exit(0)

now = time.time()
stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now))

record = {
    "v": 1,
    "sessionId": session_id,
    "event": event,
    "status": STATUS.get(event, "idle"),
    "timestamp": stamp,
    "t": int(now * 1000),
}
for key, field in (("tool_name", "tool"), ("tool_use_id", "toolId"),
                   ("agent_id", "agentId"), ("agent_type", "agentType"),
                   ("duration_ms", "durationMs"), ("notification_type", "notificationType"),
                   ("source", "source"), ("end_reason", "endReason"),
                   ("model", "model"), ("cwd", "cwd"), ("harness", "harness")):
    value = payload.get(key)
    if value not in (None, ""):
        record[field] = value

harness = payload.get("harness") or "claude"

# The Agent tool's own PostToolUse response is the only place Claude Code
# states which agent id a Task/Agent call spawned. Capturing it here is what
# turns subagent parentage from a guess into an exact link: this record's
# toolId is the parent of every later event carrying agent_id == spawnedAgentId.
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

try:
    os.makedirs(SESSIONS, exist_ok=True)
    os.makedirs(RUNS, exist_ok=True)
except OSError:
    sys.exit(0)

line = json.dumps(record, separators=(",", ":")) + "\n"

try:
    with open(EVENTS, "a") as fh:
        fh.write(line)
    trim()
except OSError:
    pass

# The live log above is a small rotating tail -- replaying a finished run
# needs its own durable copy, so every event is also appended to a
# per-session archive, capped by run count and per-run size so a runaway
# session can't fill the disk.
run_file = os.path.join(RUNS, "%s.jsonl" % session_id)
try:
    if not os.path.exists(run_file) or os.path.getsize(run_file) < MAX_RUN_BYTES:
        with open(run_file, "a") as fh:
            fh.write(line)
    if event == "session_start":
        prune_runs()
except OSError:
    pass

session_file = os.path.join(SESSIONS, "%s.json" % session_id)
try:
    if event == "session_end":
        os.remove(session_file)
    else:
        atomic_write(session_file, json.dumps({
            "event": raw_event,
            "tool": record.get("tool", ""),
            "updatedAt": stamp,
            "harness": harness,
        }, separators=(",", ":")) + "\n")
except OSError:
    pass

try:
    sweep(now)
except OSError:
    pass
