import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib" / "toml"))
from merge import merge_packages

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "toml"


def test_base_only():
    result = merge_packages(str(FIXTURES / "base.toml"), [])
    assert result == {"prep": ["alpha", "beta"], "main": ["hyprland", "waybar"]}


def test_base_plus_one_layer():
    result = merge_packages(str(FIXTURES / "base.toml"), [str(FIXTURES / "layer_a.toml")])
    assert result["prep"] == ["alpha", "beta", "gamma"]
    assert result["main"] == ["hyprland", "waybar", "gamemode"]


def test_base_plus_multiple_layers_dedup():
    result = merge_packages(
        str(FIXTURES / "base.toml"),
        [str(FIXTURES / "layer_a.toml"), str(FIXTURES / "layer_b.toml")],
    )
    assert result["main"] == ["hyprland", "waybar", "gamemode", "neovim"]


def test_custom_apps_appended_and_deduped():
    result = merge_packages(
        str(FIXTURES / "base.toml"),
        [str(FIXTURES / "layer_a.toml")],
        custom_apps_path=str(FIXTURES / "custom_apps.lst"),
    )
    assert result["main"] == ["hyprland", "waybar", "gamemode", "spotify", "neovim"]


if __name__ == "__main__":
    test_base_only()
    test_base_plus_one_layer()
    test_base_plus_multiple_layers_dedup()
    test_custom_apps_appended_and_deduped()
    print("PASS: all merge tests")
