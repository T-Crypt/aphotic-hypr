"""The chat provider list only offers providers AgentRoles says can chat.

Codex sat in AiProviders' base list and relied on servesChat() to hide it,
so an `[agents.codex] chat = true` override or a CLI `ai profile codex`
could still select a harness that has no conversational mode. servesChat
now fails closed off the descriptor record, and the harness half of the
codex assertions moved to tests/test_harness_gate.py with the gate.
"""
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AI = ROOT / "Configs/quickshell/aphotic/services/ai"
APHOTIC = ROOT / "Configs/.local/bin/aphotic"


def _base_provider_ids() -> list[str]:
    text = (AI / "AiProviders.qml").read_text()
    block = re.search(r"_baseProviders:\s*\[(.*?)\n\s*\]", text, re.S).group(1)
    return re.findall(r'\{\s*id:\s*"([^"]+)"', block)


def _roles() -> dict[str, dict[str, str]]:
    text = (AI / "AgentRoles.qml").read_text()
    block = re.search(r"_defaults:\s*\[(.*?)\n\s*\]", text, re.S).group(1)
    roles = {}
    for entry in re.findall(r"\{[^{}]*\}", block):
        rid = re.search(r'id:\s*"([^"]+)"', entry).group(1)
        roles[rid] = {
            "role": re.search(r'role:\s*"([^"]+)"', entry).group(1),
            "chat": re.search(r"chat:\s*(true|false)", entry).group(1),
        }
    return roles


def test_base_providers_all_serve_chat():
    roles = _roles()
    for pid in _base_provider_ids():
        assert roles.get(pid, {}).get("chat", "true") == "true", (
            f"{pid} is in the chat provider list but AgentRoles marks it chat: false")


def test_codex_is_not_a_chat_provider():
    assert "codex" not in _base_provider_ids()
    text = (AI / "AiProviders.qml").read_text()
    assert '"codex", "exec"' not in text
    assert 'case "codex"' not in text


def test_codex_chat_axis_stays():
    # The harness half of codex moved to the descriptor record (see
    # tests/test_harness_gate.py): its role and chat flag now come from
    # the descriptor, and AgentProviders' process table leaves with the
    # bar in the next slice. What this file still pins is the chat axis:
    # the login probe stays in AiProviders, and AgentRoles no longer
    # reads it.
    ai = (AI / "AiProviders.qml").read_text()
    assert "codexAvailable" in ai
    roles = (AI / "AgentRoles.qml").read_text()
    assert "AiProviders.codexAvailable" not in roles


def _ai_profile(tmp_path: Path, provider: str) -> subprocess.CompletedProcess:
    env = dict(os.environ, HOME=str(tmp_path),
               XDG_CONFIG_HOME=str(tmp_path / ".config"),
               XDG_STATE_HOME=str(tmp_path / ".local/state"),
               XDG_DATA_HOME=str(tmp_path / ".local/share"),
               APHOTIC_DOTS_DIR=str(ROOT))
    return subprocess.run(["bash", str(APHOTIC), "ai", "profile", provider],
                          env=env, capture_output=True, text=True)


def test_cli_rejects_codex(tmp_path):
    result = _ai_profile(tmp_path, "codex")
    assert result.returncode != 0
    assert "unknown provider" in result.stdout + result.stderr
    assert not list(tmp_path.rglob("ai-config.json"))


def test_cli_accepts_claude(tmp_path):
    result = _ai_profile(tmp_path, "claude")
    assert result.returncode == 0, result.stdout + result.stderr
    [conf] = list(tmp_path.rglob("ai-config.json"))
    assert '"activeProvider": "claude"' in conf.read_text()
