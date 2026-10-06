#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors
"""Write one validated v2 agent event through the shared hook writer.

`aphotic agent emit` (and the session framing `aphotic agent run` builds)
serves harnesses that have no hook system of their own: a shell-script
agent loop, dsh, a custom CLI. The record is contract-shaped
(docs/HARNESS_HOOKS_V2.md) and is handed to agent_hook.py on stdin --
the same writer, validation and sinks as every hook adapter -- so the
event lands in the same stream, session file and per-run archive a
native hook would have produced, and every surface that reads the
stream sees it.

Argparse validates what it can before the writer is spawned: event kind,
status, and the token counters. Everything else (sessionId presence,
field types) is the writer's to reject, exactly as for a malformed
adapter payload.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time

EVENTS = ("session_start", "session_end", "turn", "tool_call", "usage", "quota", "error")
STATUSES = ("running", "waiting", "compacting", "idle", "ended")
DEFAULT_STATUS = {"session_start": "running", "session_end": "ended"}
TOKEN_FIELDS = {
    "tokens_in": "inputTokens",
    "tokens_out": "outputTokens",
    "cache_read": "cacheReadTokens",
    "cache_write": "cacheWriteTokens",
    "reasoning_tokens": "reasoningTokens",
}


def non_negative_int(value: str) -> int:
    try:
        number = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"not a non-negative integer: {value!r}") from None
    if number < 0:
        raise argparse.ArgumentTypeError(f"must be >= 0: {value!r}")
    return number


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="aphotic agent emit",
        description="Write one validated v2 agent event through the hook writer.",
    )
    parser.add_argument("event", choices=EVENTS, help="v2 event kind")
    parser.add_argument("--session", required=True, help="the harness's own session id")
    parser.add_argument("--harness", required=True, help="harness id, e.g. codex or your own name")
    parser.add_argument("--model", help="model id the harness reports")
    parser.add_argument("--provider", help="inference provider id, e.g. ollama")
    parser.add_argument("--cwd", help="session working directory")
    parser.add_argument(
        "--status",
        choices=STATUSES,
        help="session status (default: running, or ended for session_end)",
    )
    parser.add_argument("--end-reason", help="why the session ended (session_end only)")
    parser.add_argument("--tokens-in", type=non_negative_int, dest="tokens_in",
                        help="input tokens for a usage event")
    parser.add_argument("--tokens-out", type=non_negative_int, dest="tokens_out",
                        help="output tokens for a usage event")
    parser.add_argument("--cache-read", type=non_negative_int, dest="cache_read",
                        help="cache-read tokens for a usage event")
    parser.add_argument("--cache-write", type=non_negative_int, dest="cache_write",
                        help="cache-write tokens for a usage event")
    parser.add_argument("--reasoning-tokens", type=non_negative_int, dest="reasoning_tokens",
                        help="reasoning tokens for a usage event")
    return parser.parse_args(argv)


def build_record(args: argparse.Namespace) -> dict:
    now = time.time()
    record = {
        "v": 2,
        "harness": args.harness,
        "sessionId": args.session,
        "event": args.event,
        "status": args.status or DEFAULT_STATUS.get(args.event, "running"),
        "t": int(now * 1000),
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
    }
    for flag, field in TOKEN_FIELDS.items():
        value = getattr(args, flag)
        if value is not None:
            record[field] = value
    for name in ("model", "provider", "cwd"):
        value = getattr(args, name)
        if value:
            record[name] = value
    if args.end_reason:
        record["endReason"] = args.end_reason
    return record


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)

    writer = os.path.join(os.path.dirname(os.path.abspath(__file__)), "agent_hook.py")
    if not os.path.isfile(writer):
        print(f"aphotic agent emit: writer not found: {writer}", file=sys.stderr)
        return 1

    payload = json.dumps(build_record(args), separators=(",", ":"))
    proc = subprocess.run(
        [sys.executable, writer],
        input=payload.encode(),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return proc.returncode


if __name__ == "__main__":
    sys.exit(main())
