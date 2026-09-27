"""Nothing repeats forever unless someone has said why.

Aphotic's rule is that a feature nobody is using costs nothing. The two
ways QML quietly breaks it are a repeating Timer with `running: true` and
an infinite animation with `running: true`: both keep waking the shell
whether or not anything that reads them is on screen. This fails on any
new one that is not listed below with the reason it has to run at rest,
so an always-on cost is a reviewed decision instead of an accident.

Conditional `running:` bindings are not flagged -- gating on a consumer
being present is exactly the fix. Neither are timers started imperatively
(`start()`/`restart()`), which run when something asks for them.
"""
import re
from pathlib import Path

QML = Path(__file__).resolve().parent.parent / "Configs" / "quickshell" / "aphotic"

# "relative/path.qml:<Type>:<interval or duration>" -> why it runs at rest.
ALWAYS_ON: dict[str, str] = {
    "modules/lock/Lock.qml:Timer:5000": "5 s reconcile for lock paths the shell does not own (WlSessionLock change quirk)",
    "services/Colours.qml:Timer:5000": "5 s safety reload if an external palette write is missed by the file watch",
    "services/Themes.qml:Timer:5000": "5 s safety reload if an external theme-state write is missed by the file watch",
    "services/Hypr.qml:Timer:2000": "lock-key state from keyboard LED sysfs; no event source for LED changes",
    "services/HostInfo.qml:Timer:300000": "5 min host facts refresh",
    "services/SystemUsage.qml:Timer:Config.dashboard.resourceUpdateInterval": "the one shared CPU/memory base poll every bar and notch gauge reads",
    "services/Weather.qml:Timer:20 * 60 * 1000": "20 min forecast refresh; the singleton exists only while a weather widget references it",
}

BLOCK = re.compile(r"\b(Timer|\w*Animation)\s*(?:on\s+\w+\s*)?\{")


def _blocks(text: str):
    for m in BLOCK.finditer(text):
        i, depth = m.end(), 1
        while depth and i < len(text):
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        yield m.group(1), text[m.start():i]


def _prop(block: str, name: str) -> str:
    m = re.search(rf"^\s*{name}:\s*(.+?)\s*$", block, re.M)
    return m.group(1) if m else ""


def _always_on() -> dict[str, str]:
    found = {}
    for path in sorted(QML.rglob("*.qml")):
        text = path.read_text(encoding="utf-8", errors="ignore")
        for kind, block in _blocks(text):
            if _prop(block, "running") != "true":
                continue
            if kind == "Timer":
                if _prop(block, "repeat") != "true":
                    continue
                key = f"{path.relative_to(QML)}:Timer:{_prop(block, 'interval')}"
            else:
                if "Animation.Infinite" not in _prop(block, "loops"):
                    continue
                key = f"{path.relative_to(QML)}:{kind}:{_prop(block, 'duration')}"
            found[key] = str(path.relative_to(QML))
    return found


def test_scan_sees_timers():
    # A parser that matched nothing would pass forever.
    assert len(_always_on()) >= 3


def test_no_unreviewed_always_on_work():
    unreviewed = sorted(set(_always_on()) - set(ALWAYS_ON))
    assert not unreviewed, (
        "repeating work with `running: true` and no stated reason -- gate it on "
        f"whatever reads it, or add it to ALWAYS_ON with the reason: {unreviewed}")


def test_allowlist_has_no_stale_entries():
    stale = sorted(set(ALWAYS_ON) - set(_always_on()))
    assert not stale, f"ALWAYS_ON names work that no longer runs at rest; drop it: {stale}"
