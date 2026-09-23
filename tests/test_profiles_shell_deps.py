"""Hard rule 8: whatever the shell launches ships in both base profiles.

A fresh minimal install drew every icon as its ligature name because the
icon font was missing, and later audits found dead volume keys, a Super+M
bound to a program no profile installed, and bar buttons that opened
nothing. Each case was a binary or asset used on one machine and never
added to a profile. These tests fail the moment that happens again.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib" / "toml"))
from merge import merge_packages

ROOT = Path(__file__).resolve().parents[1]

# Binary the shell or its Hyprland config runs -> the package that ships it.
# The QML entries (awww, lspci, nmcli, notify-send, sensors) were found by
# scanning Configs/quickshell/aphotic for command arrays; every one has
# been verified with `pacman -Qo $(command -v bin)`.
SHELL_BINARIES = {
    "pamixer": "pamixer",
    "brightnessctl": "brightnessctl",
    "awww": "awww",
    "awww-daemon": "awww",
    "kitty": "kitty",
    "nm-applet": "network-manager-applet",
    "nm-connection-editor": "network-manager-applet",
    "blueman-applet": "blueman",
    "blueman-manager": "blueman",
    "papirus-folders": "papirus-folders",
    "gsettings": "glib2",
    "matugen": "matugen",
    "lspci": "pciutils",
    "nmcli": "networkmanager",
    "notify-send": "libnotify",
    "sensors": "lm_sensors",
    "cliphist": "cliphist",
    "wl-copy": "wl-clipboard",
    "swappy": "swappy",
    "swaylock": "swaylock-effects",
}

# Base-system binaries the QML shells out to: every Arch install has
# these, so no profile lists them. Known by one word: the package or role
# that provides them. aphotic is the shell's own CLI, installed by
# install.sh, not a profile package.
BASE_SYSTEM = {
    "aphotic": "own-cli",
    "awk": "gawk",
    "basename": "coreutils",
    "command": "shell",
    "systemctl": "systemd",
    "cat": "coreutils",
    "chmod": "coreutils",
    "cp": "coreutils",
    "curl": "curl",
    "cut": "coreutils",
    "df": "coreutils",
    "du": "coreutils",
    "echo": "coreutils",
    "find": "findutils",
    "getconf": "glibc",
    "grep": "grep",
    "head": "coreutils",
    "hyprctl": "hyprland",
    "ip": "iproute2",
    "jq": "jq",
    "mkdir": "coreutils",
    "nproc": "coreutils",
    "pacman": "pacman",
    "pgrep": "procps-ng",
    "pkill": "procps-ng",
    "printf": "coreutils",
    "python3": "python",
    "qs": "quickshell",
    "quickshell": "quickshell",
    "readlink": "coreutils",
    "rm": "coreutils",
    "sed": "sed",
    "sh": "shell",
    "sort": "coreutils",
    "sudo": "sudo",
    "tail": "coreutils",
    "uname": "coreutils",
}

# Optional by design, one-word reason each: the AI layer, hardware that
# only some machines have, AUR helpers, and wallust, which no Arch repo
# carries (profiles/base/full.toml explains install.sh provides it).
OPTIONAL = {
    "asdbctl": "apple-display",
    "claude": "ai-agent",
    "codex": "ai-agent",
    "ddcutil": "ddc-hardware",
    "intel_gpu_top": "intel-gpu",
    "nvidia-smi": "nvidia-gpu",
    "ollama": "ai-runtime",
    "paru": "aur-helper",
    "radeontop": "amd-gpu",
    "wallust": "installer-provided",
    "yay": "aur-helper",
}

# Apps a keybind launches that only the full profile promises. Minimal
# tells the user to install their own programs.
FULL_ONLY_APPS = {"firefox", "thunar", "code"}

# Launchers and system tools that are not profile packages.
NOT_PACKAGES = {"qs", "aphotic", "systemctl", "dbus-update-activation-environment"}

# Settings.qml default -> package that provides it.
DEFAULT_THEMES = {
    "iconTheme": ("Papirus-Dark", "papirus-icon-theme"),
    "cursorTheme": ("Bibata-Modern-Ice", "bibata-cursor-theme"),
    "gtkTheme": ("adw-gtk3-dark", "adw-gtk-theme"),
}


def _packages(profile):
    merged = merge_packages(str(ROOT / f"profiles/base/{profile}.toml"), [])
    return set(merged["main"]) | set(merged.get("prep", []))


def _hypr_commands():
    words = set()
    for name in ("keybinds.lua", "startup.lua"):
        text = (ROOT / "Configs/hypr" / name).read_text()
        for cmd in re.findall(r'exec_cmd\(\s*"([^"]+)"', text):
            # A program behind a `command -v` check is optional by design.
            guarded = set(re.findall(r"command -v ([\w.+-]+)", cmd))
            for part in re.split(r"&&|\|\||;|\|", cmd):
                w = part.strip().split()
                while w and (w[0] in ("sleep", "command", "-v") or re.fullmatch(r"[0-9.]+", w[0])):
                    w = w[1:]
                if w and not w[0].startswith(("/", "~")) and w[0] not in guarded:
                    words.add(w[0])
    return words


def test_shell_binaries_ship_in_both_profiles():
    for profile in ("full", "minimal"):
        packages = _packages(profile)
        for binary, package in SHELL_BINARIES.items():
            assert package in packages, f"{binary} needs {package}, missing from {profile}"


def test_hypr_config_launches_only_shipped_programs():
    unknown = _hypr_commands() - set(SHELL_BINARIES) - FULL_ONLY_APPS - NOT_PACKAGES
    assert not unknown, f"Hyprland config launches {sorted(unknown)}; map each to a profile package"


def test_full_only_apps_ship_in_full():
    full = _packages("full")
    for app in FULL_ONLY_APPS:
        package = "visual-studio-code-bin" if app == "code" else app
        assert package in full, f"{app} is bound to a key but missing from full"


def test_settings_default_themes_ship_in_both_profiles():
    settings = (ROOT / "Configs/quickshell/aphotic/services/Settings.qml").read_text()
    for prop, (value, package) in DEFAULT_THEMES.items():
        match = re.search(rf'property string {prop}: "([^"]*)"', settings)
        assert match, f"Settings.qml no longer declares {prop}"
        assert match.group(1) == value, f"{prop} default changed to {match.group(1)}; update DEFAULT_THEMES and the profiles"
        for profile in ("full", "minimal"):
            assert package in _packages(profile), f"default {prop} {value} needs {package}, missing from {profile}"


def test_gtk_monospace_font_ships_in_both_profiles():
    startup = (ROOT / "Configs/hypr/startup.lua").read_text()
    match = re.search(r"monospace-font-name '([^']+?) \d+'", startup)
    assert match and match.group(1) == "JetBrainsMono Nerd Font Mono"
    for profile in ("full", "minimal"):
        assert "ttf-jetbrains-mono-nerd" in _packages(profile)


# -- QML command arrays (hard rule 8 for the Quickshell side) ---------------
#
# Scans every *.qml under Configs/quickshell/aphotic except modules/ and
# plugins/, which ship their own plugs. Extracts the first executable of
# command arrays (`command: ["x", ...]`, `.exec([...])`,
# `execDetached([...])`), and of `sh -c`/`bash -c` scripts the first word
# of each `&&`/`||`/`;`/`|`-separated segment. Line comments are stripped
# first; dynamic first elements (template strings, variables) are ignored.

QML_ROOT = ROOT / "Configs/quickshell/aphotic"

# Shell structures that never head an installed binary.
_LOOP_WORDS = {"if", "for", "while", "until", "case", "select", "function", "time", "{", "("}
_SKIP_WORDS = {
    "sudo": 1, "timeout": 1, "nohup": 0, "setsid": 0, "exec": 0, "env": 0,
    "nice": 1, "!": 0, "else": 0, "then": 0, "do": 0, "done": 0, "fi": 0,
    "esac": 0, "elif": 0, "in": 0, "local": 0, "export": 0, "readonly": 0,
    "break": 0, "continue": 0, "cd": 0, "exit": 0, "return": 0, "shift": 0,
    "source": 0, ".": 0, "read": 0, "trap": 0, "wait": 0, "unset": 0,
    "set": 0, "umask": 0,
}
_TEST_WORDS = {"[", "[[", "test"}
_WORD_RE = re.compile(r"[A-Za-z0-9._+-]+")
_ASSIGN_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=.*")


def _strip_comments(text):
    """Drop `//` line comments, keeping `//` inside quoted strings."""
    out = []
    i, n, quote = 0, len(text), None
    while i < n:
        c = text[i]
        if quote:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c in "'\"`":
            quote = c
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _shell_segments(script):
    """Split a -c script on && || ; | &, respecting quotes and redirections."""
    segs, cur, quote, escaped = [], [], None, False
    i, n = 0, len(script)
    while i < n:
        c = script[i]
        if quote:
            cur.append(c)
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == quote:
                quote = None
            i += 1
            continue
        if c in "'\"`":
            quote = c
            cur.append(c)
            i += 1
            continue
        if c in "&|;":
            # `&` in `>&` / `2>&1` dup-fd redirections is not a separator.
            before = script[i - 1] if i > 0 else ""
            after = script[i + 1] if i + 1 < n else ""
            if c == "&" and (before in "><" or after == ">"):
                cur.append(c)
                i += 1
                continue
            segs.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    segs.append("".join(cur))
    return [s for s in segs if s.strip()]


def _segment_binary(seg):
    """First executable of one shell segment -> binary, or guard target."""
    toks = seg.split()
    while toks and _ASSIGN_RE.fullmatch(toks[0]):
        toks = toks[1:]
    if not toks:
        return None
    if toks[0] == "command" and len(toks) >= 3 and toks[1] == "-v":
        return toks[2]
    if toks[0] in _TEST_WORDS:
        return None
    while toks:
        w = toks[0]
        if w in _LOOP_WORDS or w in _TEST_WORDS:
            return None
        if w in _SKIP_WORDS:
            toks = toks[1 + _SKIP_WORDS[w]:]
            continue
        break
    if toks and _WORD_RE.fullmatch(toks[0]):
        return toks[0]
    return None


def _qml_binaries():
    """{binary: {files}} the QML runs unconditionally (guards subtracted)."""
    required, guarded = {}, {}
    _array_re = re.compile(r'(?:command\s*:\s*|\.exec\(\s*|execDetached\(\s*)\["([^"]*)"')
    _script_re = re.compile(r'\["(?:sh|bash)"\s*,\s*"-c"\s*,\s*("(?:[^"\\]|\\.)*"|`(?:[^`\\]|\\.)*`)')
    for path in sorted(QML_ROOT.rglob("*.qml")):
        rel = "/" + str(path.relative_to(QML_ROOT)) + "/"
        if "/modules/plugins/" in rel:
            continue
        text = _strip_comments(path.read_text())
        file_required, file_guarded = set(), set()
        for m in _array_re.finditer(text):
            first = m.group(1)
            if first and _WORD_RE.fullmatch(first):
                file_required.add(first)
        for m in _script_re.finditer(text):
            script = m.group(1)
            script = re.sub(r"\\(.)", r"\1", script[1:-1]) if script[0] == '"' else script[1:-1]
            for seg in _shell_segments(script):
                word = _segment_binary(seg)
                if word is None:
                    continue
                if seg.lstrip().startswith("command -v"):
                    file_guarded.add(word)
                else:
                    file_required.add(word)
        # A binary this file only runs behind its own `command -v X` guard
        # is optional by design (skip the guard, X stays optional).
        for binary in file_guarded:
            if binary in file_required:
                file_required.discard(binary)
            guarded.setdefault(binary, set()).add(path.name)
        for binary in file_required:
            required.setdefault(binary, set()).add(path.name)
    return required, guarded


def test_qml_launches_only_shipped_programs():
    required, _guarded = _qml_binaries()
    unknown = {
        binary: sorted(files)
        for binary, files in sorted(required.items())
        if binary not in SHELL_BINARIES and binary not in BASE_SYSTEM and binary not in OPTIONAL
        and binary not in FULL_ONLY_APPS
    }
    assert not unknown, (
        "QML command arrays call unmapped binaries: "
        + ", ".join(f"{b} ({', '.join(fs)})" for b, fs in unknown.items())
        + "; map each to a profile package or allowlist it"
    )
