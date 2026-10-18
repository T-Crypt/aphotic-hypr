"""Settings search index integrity.

The rail search and the launcher's "?" mode read one index built from
config/SettingsCategories.qml, and a row hit addresses a row through the
`searchId` the row component carries in its pane. That pairing is data,
not code, so this test holds both ends together: an index entry with no
row, a row with no entry, a duplicate anchor, or a label that no longer
appears in its pane fails here instead of shipping a search hit that
opens the right pane and then finds nothing.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "Configs/quickshell/aphotic/config/SettingsCategories.qml"
PANES = ROOT / "Configs/quickshell/aphotic/modules/settings/panes"

# Category id -> every file that may carry its rows. A category added
# without its files listed here fails the coverage test on purpose: a new
# pane has to be indexed, not silently left out of search. Sub-pages that
# generate their rows from data (WallpaperPicker's tiles, CommunityThemes'
# grid) are absent on purpose, since they have no static row to anchor.
CATEGORY_FILES = {
    "appearance": ["AppearancePane.qml"],
    "themeCreator": ["ThemeCreatorPane.qml"],
    "personalization": ["PersonalizationPane.qml", "PaletteSection.qml"],
    "bar": ["BarPane.qml", "BarWidgetsSection.qml"],
    "launcher": ["LauncherPane.qml"],
    "clock": ["ClockPane.qml"],
    "osd": ["OsdPane.qml"],
    "displays": ["DisplaysPane.qml"],
    "sonar": ["SonarPane.qml"],
    "language": ["LanguagePane.qml"],
    "workspaceProfiles": ["WorkspaceProfilesPane.qml"],
    "ai": ["AiPane.qml"],
    "network": ["NetworkPane.qml"],
    "power": ["PowerSecurityPane.qml"],
    "plugins": ["PluginsPane.qml"],
    "system": ["SystemPane.qml"],
    "about": ["AboutPane.qml"],
}

ENTRY = re.compile(
    r'\{\s*category:\s*"(?P<category>[a-zA-Z]+)",\s*anchor:\s*"(?P<anchor>[a-zA-Z]+)",\s*'
    r'icon:\s*"(?P<icon>[a-z0-9_]+)",\s*label:\s*qsTr\("(?P<label>(?:[^"\\]|\\.)*)"\),\s*'
    r'keywords:\s*"(?P<keywords>[^"]*)"\s*\}'
)
CORE_ID = re.compile(r'\{\s*id:\s*"([a-zA-Z]+)"')
SEARCH_ID = re.compile(r'searchId:\s*"([a-zA-Z]+)"')
ENTRY_LINE = re.compile(r"^\s*\{ category:", re.MULTILINE)


def _config_text():
    return CONFIG.read_text(encoding="utf-8")


def _entries():
    text = _config_text()
    rows = text.split("readonly property var _rows:")[1].split("\n    ]")[0]
    found = [m.groupdict() for m in ENTRY.finditer(rows)]
    assert found, "no row entries parsed; the _rows block shape changed"
    assert len(found) == len(ENTRY_LINE.findall(rows)), (
        "an entry line did not parse; keep one entry per line in the exact shape"
    )
    return found


def test_category_panes_cover_every_category():
    core = _config_text().split("readonly property var _core:")[1]
    ids = set(CORE_ID.findall(core))
    assert ids == set(CATEGORY_FILES), "category file map is out of date"


def _file_texts(category):
    return {name: (PANES / name).read_text(encoding="utf-8") for name in CATEGORY_FILES[category]}


def test_entries_match_their_pane_rows():
    seen = set()
    for entry in _entries():
        texts = _file_texts(entry["category"])
        anchor = f'searchId: "{entry["anchor"]}"'
        label = f'qsTr("{entry["label"]}")'
        carriers = [name for name, text in texts.items() if anchor in text]
        assert carriers, f"{entry['category']}: no row carries searchId {entry['anchor']}"
        assert any(label in texts[name] for name in carriers), (
            f"{entry['category']}: no row carries the label {entry['label']!r}"
        )
        key = (entry["category"], entry["anchor"])
        assert key not in seen, f"duplicate anchor {key}"
        seen.add(key)


def test_pane_rows_are_all_indexed():
    indexed = {}
    for entry in _entries():
        indexed.setdefault(entry["category"], set()).add(entry["anchor"])
    for category, names in sorted(CATEGORY_FILES.items()):
        for name in names:
            text = (PANES / name).read_text(encoding="utf-8")
            for anchor in SEARCH_ID.findall(text):
                assert anchor in indexed.get(category, set()), (
                    f"{name}: searchId {anchor} has no index entry in SettingsCategories.qml"
                )
