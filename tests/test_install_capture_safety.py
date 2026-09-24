import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INSTALLER_PATHS = [ROOT / "install.sh", *sorted((ROOT / "lib/install").glob("*.sh"))]
FUNCTION_RE = re.compile(
    r"(?ms)^([A-Za-z_][A-Za-z0-9_]*)\(\) \{\n(.*?)^\}"
)
CAPTURE_RE = re.compile(
    r'(?m)^\s*(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)="?\$\(\s*([A-Za-z_][A-Za-z0-9_]*)\b'
)
INSTALL_COMMAND_RE = re.compile(
    r"\b(?:makepkg|pacman\s+-S|install_software|sudo\s+install)\b"
)


def _installer_source() -> str:
    return "\n".join(path.read_text() for path in INSTALLER_PATHS)


def _installing_functions(source: str) -> set[str]:
    functions = dict(FUNCTION_RE.findall(source))
    installing = {
        name for name, body in functions.items() if INSTALL_COMMAND_RE.search(body)
    }

    changed = True
    while changed:
        changed = False
        for name, body in functions.items():
            if name in installing:
                continue
            if any(
                re.search(rf"(?m)^\s*(?:if\s+|!\s+)?{re.escape(callee)}\b", body)
                or re.search(rf"\$\(\s*{re.escape(callee)}\b", body)
                for callee in installing
            ):
                installing.add(name)
                changed = True
    return installing


def test_captured_install_function_results_are_resolvable_commands():
    source = _installer_source()
    installing = _installing_functions(source)
    captures = [
        match
        for match in CAPTURE_RE.finditer(source)
        if match.group(2) in installing
    ]

    assert captures, "expected at least one captured install-function result"
    for match in captures:
        variable, function = match.groups()
        guard = re.compile(rf'command\s+-v\s+"\${re.escape(variable)}"')
        assert guard.search(source[match.end() : match.end() + 500]), (
            f"{variable} captures {function}; verify it resolves on PATH before using it"
        )
