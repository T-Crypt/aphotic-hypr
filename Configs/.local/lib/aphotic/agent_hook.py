#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors
"""aphotic agent hook worker -- see agent_hook.sh for why this is one
process and why nothing in here is allowed to raise."""
import json, os, re, sys, time

STATE = os.environ.get("APHOTIC_STATE_HOME", os.path.expanduser("~/.local/state/aphotic"))
SESSIONS = os.path.join(STATE, "agent-sessions")
EVENTS = os.path.join(STATE, "agent-events.jsonl")
RUNS = os.path.join(STATE, "agent-runs")
MAX_BYTES = 512 * 1024
KEEP_LINES = 1000
STALE_SECONDS = 12 * 60 * 60
MAX_RUNS = 25
MAX_RUN_BYTES = 2 * 1024 * 1024
MODEL_TAIL_BYTES = 64 * 1024

# Keyed by the raw Claude Code hook name, because several raw events
# fold into the same kind ("turn") with different statuses.
V2_KIND = {
    "SessionStart": "session_start",
    "SessionEnd": "session_end",
    "UserPromptSubmit": "turn",
    "PreToolUse": "tool_call",
    "PostToolUse": "tool_call",
    "PostToolUseFailure": "tool_call",
    "Notification": "turn",
    "PreCompact": "turn",
    "PostCompact": "turn",
    "Stop": "turn",
    "SubagentStop": "turn",
}
V2_STATUS = {
    "SessionStart": "running",
    "SessionEnd": "ended",
    "UserPromptSubmit": "running",
    "PreToolUse": "running",
    "PostToolUse": "running",
    "PostToolUseFailure": "running",
    "Notification": "waiting",
    "PreCompact": "compacting",
    "PostCompact": "running",
    "Stop": "idle",
    "SubagentStop": "idle",
}
TOOL_STATUS = {
    "PreToolUse": "running",
    "PostToolUse": "completed",
    "PostToolUseFailure": "errored",
}
# Only Claude Code runs through this script, but a harness override
# can still name a harness this hook has no provider for.
PROVIDER_BY_HARNESS = {"claude": "anthropic"}
CACHE_READ_KEYS = ("cache_read_input_tokens", "cache_read_tokens")
CACHE_WRITE_KEYS = ("cache_creation_input_tokens", "cache_write_tokens")


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


def model_from_transcript(path):
    """Last model named in the harness transcript, or "" if there is none.

    SessionStart states `model` only when the session started fresh. A
    session that began with /clear reports no model on any event, so the
    only local record of what is answering is the transcript the payload
    points at. Reads the tail rather than the file: transcripts reach
    hundreds of KB and this runs inside a hook on every tool call.
    """
    if not path:
        return ""
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as fh:
            if size > MODEL_TAIL_BYTES:
                fh.seek(size - MODEL_TAIL_BYTES)
            chunk = fh.read().decode("utf-8", "replace")
    except OSError:
        return ""
    seen = re.findall(r'"model"\s*:\s*"([^"]+)"', chunk)
    return seen[-1] if seen else ""


def cached_session(path):
    """The last session file written for this session, or {}."""
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def first_present(mapping, keys):
    """The first numeric value found under any of `keys`.

    None if no key is present or every match is non-numeric.
    """
    for key in keys:
        value = mapping.get(key)
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return value
    return None


def usage_record_from_response(response, common):
    """A `usage` line from a tool_response's usage block.

    Every lookup is guarded, so a missing or malformed block yields no line.
    """
    if not isinstance(response, dict):
        return None
    usage = response.get("usage")
    if not isinstance(usage, dict):
        return None

    record = dict(common)
    record["event"] = "usage"
    found = False
    for src, field in (("input_tokens", "inputTokens"), ("output_tokens", "outputTokens")):
        value = usage.get(src)
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            record[field] = value
            found = True
    read = first_present(usage, CACHE_READ_KEYS)
    if read is not None:
        record["cacheReadTokens"] = read
        found = True
    written = first_present(usage, CACHE_WRITE_KEYS)
    if written is not None:
        record["cacheWriteTokens"] = written
        found = True
    return record if found else None


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    if not isinstance(payload, dict):
        sys.exit(0)

    session_id = payload.get("session_id") or ""
    raw_event = payload.get("hook_event_name") or ""
    event = V2_KIND.get(raw_event)
    if not session_id or not event:
        sys.exit(0)

    now = time.time()
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now))

    record = {
        "v": 2,
        "sessionId": session_id,
        "event": event,
        "status": V2_STATUS.get(raw_event, "idle"),
        "ts": stamp,
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

    tool_status = TOOL_STATUS.get(raw_event)
    if tool_status:
        record["toolStatus"] = tool_status

    harness = payload.get("harness") or "claude"

    # The default has to reach the record, not just the session file below.
    # Claude Code sends no `harness` of its own (the adapters for other
    # harnesses do), so without this every Claude event is untagged and a
    # reader cannot tell "this is Claude" from "nobody said".
    record["harness"] = harness

    provider = PROVIDER_BY_HARNESS.get(harness)
    if provider:
        record["provider"] = provider

    session_file = os.path.join(SESSIONS, "%s.json" % session_id)
    known = cached_session(session_file)

    # Model identity has to outlive the one event that states it: a graph
    # labels a session node by its model for the session's whole life, and
    # only SessionStart-from-startup ever carries it. Resolve it once, then
    # re-state it in the log only when it is new or has changed, so a
    # long session does not repeat it on every tool call.
    model = (record.get("model") or known.get("model")
             or model_from_transcript(payload.get("transcript_path")))
    if model and model != known.get("model"):
        record["model"] = model
    elif "model" in record:
        del record["model"]

    # The Agent tool's own PostToolUse response is the only place Claude Code
    # states which agent id a Task/Agent call spawned. Capturing it here is what
    # turns subagent parentage from a guess into an exact link: this record's
    # toolId is the parent of every later event carrying agent_id == spawnedAgentId.
    response = payload.get("tool_response")
    usage_line = None
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

        if raw_event == "PostToolUse":
            common = {
                "v": 2,
                "sessionId": session_id,
                "status": record["status"],
                "ts": stamp,
                "t": record["t"],
                "harness": harness,
            }
            if provider:
                common["provider"] = provider
            usage_line = usage_record_from_response(response, common)

    try:
        os.makedirs(SESSIONS, exist_ok=True)
        os.makedirs(RUNS, exist_ok=True)
    except OSError:
        sys.exit(0)

    lines = [json.dumps(record, separators=(",", ":")) + "\n"]
    if usage_line:
        lines.append(json.dumps(usage_line, separators=(",", ":")) + "\n")
    blob = "".join(lines)

    try:
        with open(EVENTS, "a") as fh:
            fh.write(blob)
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
                fh.write(blob)
        if event == "session_start":
            prune_runs()
    except OSError:
        pass

    try:
        if event == "session_end":
            os.remove(session_file)
        else:
            atomic_write(session_file, json.dumps({
                "event": raw_event,
                "tool": record.get("tool", ""),
                "updatedAt": stamp,
                "harness": harness,
                "model": model,
            }, separators=(",", ":")) + "\n")
    except OSError:
        pass

    try:
        sweep(now)
    except OSError:
        pass


if __name__ == "__main__":
    main()
