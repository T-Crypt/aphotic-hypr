#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: Aphotic-Hypr contributors
"""Codex agent hook translator -- see codex_hook.sh for why this is one
short-lived process and why nothing in here is allowed to raise.

Codex's command hooks hand this process one JSON object on stdin whose
field names already match the contract agent_hook.py expects from Claude
Code (docs/AGENT_TRACKING.md, "Extending to another harness"): the
translation happens at the harness's own adapter boundary, never by
teaching agent_hook.py a second input shape. What needs changing:

  * tag the record harness = "codex" (agent_hook.py defaults to "claude"
    when the field is absent, which would mislabel every Codex session)
  * SessionEnd calls its reason "reason"; agent_hook.py reads
    "end_reason" (Claude Code's name)
  * known Codex tool-name aliases are normalized to the graph/bar
    vocabulary (`shell` arrives where Claude says `Bash`, `apply_patch`
    where Claude says `Edit`, `spawn_agent` where Claude says `Agent`).
    MCP and function names like `mcp__filesystem__read_file` or
    `update_plan` pass through untouched -- capitalizing them would only
    mangle display in the graph's icon/category lookups.

Everything else (session_id, tool_use_id, agent_id/agent_type on subagent
events, model, cwd, source on SessionStart, turn_id, ...) already carries
the right names and is passed through verbatim. agent_hook.py is then
spawned with the translated JSON on its stdin -- the same spawn-per-event
shape the OpenCode plugin (opencode_hook.js) already uses. Duration
tracking isn't done here: a per-event process has no state between
PreToolUse and PostToolUse, and Codex's payloads don't carry a duration.
"""
import json
import os
import subprocess
import sys

TOOL_NAMES = {
    "shell": "Bash",
    "apply_patch": "Edit",
    "spawn_agent": "Agent",
}


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    if not isinstance(payload, dict):
        return 0

    event = payload.get("hook_event_name") or ""
    if not event or not payload.get("session_id"):
        return 0

    record = dict(payload)
    record["harness"] = "codex"
    if event == "SessionEnd" and record.get("reason") and "end_reason" not in record:
        record["end_reason"] = record["reason"]
    tool = record.get("tool_name")
    if isinstance(tool, str) and tool in TOOL_NAMES:
        record["tool_name"] = TOOL_NAMES[tool]

    hook_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "agent_hook.py")
    try:
        proc = subprocess.Popen(
            [sys.executable, hook_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        proc.stdin.write(json.dumps(record, separators=(",", ":")).encode())
        proc.stdin.close()
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
