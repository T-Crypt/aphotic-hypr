"""A QML singleton nothing references is never constructed, so it never runs.

Quickshell builds a singleton on first use. A `pragma Singleton` that no
other QML file names therefore never reaches Component.onCompleted, never
starts its timers and never wires its Connections -- silently, with no
error anywhere. The feature simply does nothing.

This has now bitten three times:
  - SecurityProfile, caught before it shipped (PR #114)
  - WallpaperCycle, shipped with a working Settings toggle and interval
    picker in front of a Timer that never ran
  - DevDrift, shipped and presented as working in two docs

Comments are stripped before matching, because both of the shipped cases
WERE mentioned by name in other files -- only ever in prose explaining
what they do.
"""
import re
from pathlib import Path

QML_ROOT = Path(__file__).resolve().parent.parent / "Configs" / "quickshell" / "aphotic"

# A singleton reachable only from outside this repo (a plugin in the
# aphotic-plugins repo, say) belongs here with the reason. Empty on
# purpose: nothing qualifies today, and an entry is a claim someone has
# to justify.
ALLOWED_UNREFERENCED: dict[str, str] = {}


def _code(path: Path) -> str:
    """File contents with // comments removed."""
    return "\n".join(re.sub(r"//.*$", "", line) for line in path.read_text(
        encoding="utf-8", errors="ignore").splitlines())


def _qml_files() -> list[Path]:
    return sorted(QML_ROOT.rglob("*.qml"))


def _singletons() -> list[Path]:
    return [p for p in _qml_files()
            if re.search(r"^\s*pragma\s+Singleton", p.read_text(
                encoding="utf-8", errors="ignore"), re.M)]


def test_qml_root_exists():
    assert QML_ROOT.is_dir(), f"expected the shell at {QML_ROOT}"


def test_finds_singletons():
    # A scan that silently matches nothing would pass forever.
    assert len(_singletons()) > 10, "singleton scan found suspiciously few files"


def test_every_singleton_is_referenced():
    files = _qml_files()
    unreferenced = []

    for singleton in _singletons():
        name = singleton.stem
        if name in ALLOWED_UNREFERENCED:
            continue
        referenced = any(
            other != singleton and re.search(rf"\b{re.escape(name)}\b", _code(other))
            for other in files
        )
        if not referenced:
            unreferenced.append(name)

    assert not unreferenced, (
        "these singletons are never constructed, so their timers, "
        f"Connections and Component.onCompleted never run: {unreferenced}. "
        "Give each one a construction site (shell.qml's _residentSingletons "
        "is where a self-driving service goes) or delete it."
    )
