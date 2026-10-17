"""Components first-party plugins instantiate must stay registered.

The list below was derived once by scanning the plugins repo for types used
from `import qs.components`, then hardcoded here. This test reads only this
repo, so deleting a component file fails CI here instead of failing plugins
at compile time on every machine that syncs it. Drop a name from the list
only after the plugins have moved off it.
"""
import re
from pathlib import Path

import pytest

COMPONENTS_DIR = (
    Path(__file__).resolve().parent.parent
    / "Configs" / "quickshell" / "aphotic" / "components"
)

# Sorted. One name per plugin-facing component type.
PLUGIN_COMPONENT_TYPES = (
    "Anim",
    "CAnim",
    "ColorPickerField",
    "MaterialIcon",
    "SettingsGroup",
    "SettingsPresetRow",
    "SettingsRow",
    "SettingsToggleRow",
    "SignalText",
    "StateLayer",
    "StyledRect",
    "StyledText",
)


def registrations():
    """Component type name -> file named for it in components/qmldir."""
    text = (COMPONENTS_DIR / "qmldir").read_text(encoding="utf-8")
    return dict(re.findall(r"^(\w+)\s+[\d.]+\s+(\S+\.qml)\s*$", text, re.M))


def test_qmldir_parses():
    # A format change would make every lookup below fail with the wrong
    # message, so name the real cause here.
    found = registrations()
    assert len(found) > 20, (
        f"components/qmldir parsed to {len(found)} registrations; the format "
        "changed and this test needs its parser updated"
    )


@pytest.mark.parametrize("name", PLUGIN_COMPONENT_TYPES)
def test_plugin_component_type_is_registered(name):
    found = registrations()
    assert name in found, (
        f"{name} is not registered in components/qmldir, so first-party "
        "plugins that instantiate it fail to compile. Remove it from "
        "PLUGIN_COMPONENT_TYPES only after the plugins have moved off it."
    )
    assert (COMPONENTS_DIR / found[name]).is_file(), (
        f"{name} registers {found[name]}, which does not exist"
    )