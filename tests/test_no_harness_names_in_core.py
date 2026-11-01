"""No core file names a harness.

Harnesses come from descriptors (plugin manifests and drop-ins merged into
harnesses.json). A harness id written into the shell or the agent workers
is a second source of truth that a drop-in harness can't reach, so this
counts the ids left in core code, comments and docstrings stripped first.

Each allowance below says why that file keeps its names. The counts must
match exactly: when a name goes away, lower the number so it can't come back.
"""
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
QML_ROOT = REPO / "Configs" / "quickshell"
LIB = REPO / "Configs" / ".local" / "lib" / "aphotic"

HARNESS_ID = re.compile(r"\b(claude|codex|opencode|omp|pi)\b")

ALLOWED: dict[str, tuple[int, str]] = {
    "Configs/quickshell/aphotic/services/ai/AiProviders.qml": (
        10,
        "Chat providers, a separate axis from harnesses: the Claude CLI as a "
        "chat backend and its login checks. Out of scope for descriptors.",
    ),
    "Configs/quickshell/aphotic/config/SettingsCategories.qml": (
        2,
        "Search keywords for the chat provider API key and model rows.",
    ),
    "Configs/quickshell/aphotic/services/ai/AgentRoles.qml": (
        6,
        "Model id parsing: claude-* is a model family and codex a GPT tier "
        "suffix, not harness ids.",
    ),
    "Configs/.local/lib/aphotic/agent_hook.py": (
        1,
        "RAW_HOOK_HARNESS: a raw payload in Claude Code's own hook format "
        "with no harness field can only come from Claude Code.",
    ),
    "Configs/.local/lib/aphotic/agent_statusline.py": (
        1,
        "FALLBACK_HARNESS: the statusLine slot is Claude Code's, used when "
        "harnesses.json is missing.",
    ),
}


def _strip_qml(text: str) -> str:
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def _strip_py(text: str) -> str:
    text = re.sub(r'"""[\s\S]*?"""', "", text)
    return "\n".join(re.sub(r"#.*$", "", line) for line in text.splitlines())


def _core_files() -> list[tuple[Path, str]]:
    files = [(p, _strip_qml(p.read_text(encoding="utf-8", errors="ignore")))
             for p in sorted(QML_ROOT.rglob("*")) if p.suffix in (".qml", ".js")]
    for pattern in ("agent_*.py", "harness*.py"):
        files += [(p, _strip_py(p.read_text(encoding="utf-8")))
                  for p in sorted(LIB.glob(pattern))]
    return files


def _counts() -> dict[str, int]:
    counts = {}
    for path, code in _core_files():
        n = len(HARNESS_ID.findall(code))
        if n:
            counts[str(path.relative_to(REPO))] = n
    return counts


def test_scan_covers_the_shell_and_the_agent_workers():
    names = {p.name for p, _ in _core_files()}
    assert {"shell.qml", "agent_hook.py", "agent_usage.py", "harness_record.py"} <= names


def test_the_pattern_matches_an_id_and_skips_math_pi():
    assert HARNESS_ID.findall('["kitty", "-e", "claude"] + Math.PI') == ["claude"]


def test_no_unallowed_harness_names_in_core():
    counts = _counts()
    unexpected = {f: n for f, n in counts.items() if f not in ALLOWED}
    assert not unexpected, (
        f"harness ids in core: {unexpected}. Read the id from a descriptor "
        "(Harnesses.qml or harness_record.py) instead."
    )


def test_allowances_match_exactly():
    counts = _counts()
    drift = {f: (counts.get(f, 0), allowed) for f, (allowed, _) in ALLOWED.items()
             if counts.get(f, 0) != allowed}
    assert not drift, (
        f"(found, allowed) per file: {drift}. More than allowed: read the id "
        "from a descriptor. Fewer: lower the allowance to the new count."
    )
