import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib" / "toml"))
from merge import merge_packages

ROOT = Path(__file__).resolve().parents[1]


def test_minimal_profile_excludes_extras():
    result = merge_packages(str(ROOT / "profiles/base/minimal.toml"), [])
    assert "waybar" in result["main"]
    assert "kitty" in result["main"]
    assert "firefox" not in result["main"]
    assert "gamemode" not in result["main"]
    assert "hyprland" not in result["main"], "hyprland is orchestrator-special-cased, not profile data"


def test_full_profile_has_expected_packages():
    result = merge_packages(str(ROOT / "profiles/base/full.toml"), [])
    for pkg in ["waybar", "firefox", "starship", "sddm", "wallust"]:
        assert pkg in result["main"], f"{pkg} missing from full profile"
    assert result["main"].count("firefox") == 1


def test_gaming_layer_adds_packages():
    result = merge_packages(
        str(ROOT / "profiles/base/full.toml"),
        [str(ROOT / "profiles/layers/gaming.toml")],
    )
    for pkg in ["gamemode", "mangohud", "steam"]:
        assert pkg in result["main"]


def test_multiple_layers_and_custom_apps_all_merge():
    result = merge_packages(
        str(ROOT / "profiles/base/full.toml"),
        [
            str(ROOT / "profiles/layers/gaming.toml"),
            str(ROOT / "profiles/layers/dev.toml"),
            str(ROOT / "profiles/layers/ai.toml"),
        ],
        custom_apps_path=str(ROOT / "profiles/custom_apps.lst"),
    )
    for pkg in ["gamemode", "neovim", "ollama", "spotify", "youtube-desktop"]:
        assert pkg in result["main"]


if __name__ == "__main__":
    test_minimal_profile_excludes_extras()
    test_full_profile_has_expected_packages()
    test_gaming_layer_adds_packages()
    test_multiple_layers_and_custom_apps_all_merge()
    print("PASS: real profile merge tests")
