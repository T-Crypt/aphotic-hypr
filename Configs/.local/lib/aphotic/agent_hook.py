#!/usr/bin/env python3
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
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w") as fh:
        fh.write(text)
    os.replace(tmp, path)


def sweep(now):
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
                   ("model", "model")):
    value = payload.get(key)
    if value not in (None, ""):
        record[field] = value

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
        }) + "\n")
except OSError:
    pass

try:
    sweep(now)
except OSError:
    pass
