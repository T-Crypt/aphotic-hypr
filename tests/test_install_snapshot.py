import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "lib/install/snapshot.sh"
REPORT = ROOT / "lib/install/report.sh"
PACKAGES = ROOT / "lib/install/packages.sh"
DOCTOR = ROOT / "Configs/.local/lib/aphotic/commands/cmd_doctor.sh"


def run_snapshot(command: str, *args: Path | str, env: dict[str, str] | None = None):
    test_env = os.environ.copy()
    if env:
        test_env.update(env)
    return subprocess.run(
        ["bash", "-c", f'source "$1"; shift; {command}', "bash", str(SNAPSHOT), *map(str, args)],
        cwd=ROOT,
        env=test_env,
        text=True,
        capture_output=True,
        check=False,
    )


def make_repo_tools(tmp_path: Path) -> tuple[Path, Path]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    calls = tmp_path / "calls"
    pacman = bin_dir / "pacman"
    pacman.write_text(
        "#!/usr/bin/env bash\n"
        "if [[ \"$1\" == \"-Si\" && \"$2\" == \"sample\" ]]; then\n"
        "  printf 'Repository      : extra\\nName            : sample\\n'\n"
        "  exit 0\n"
        "fi\n"
        "exit 1\n"
    )
    pacman.chmod(0o755)
    sudo = bin_dir / "sudo"
    sudo.write_text(f"#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> {calls}\nexit 99\n")
    sudo.chmod(0o755)
    return bin_dir, calls


def test_rewrites_only_enabled_official_repositories(tmp_path: Path):
    source = tmp_path / "pacman.conf"
    output = tmp_path / "snapshot.conf"
    source.write_text(
        "# pacman sample\n"
        "[options]\n"
        "HoldPkg = pacman glibc\n"
        "SigLevel = Required DatabaseOptional\n"
        "# [core-testing]\n"
        "# Include = /etc/pacman.d/mirrorlist\n"
        "\n"
        "[core]\n"
        "Include = /etc/pacman.d/mirrorlist\n"
        "SigLevel = PackageRequired\n"
        "\n"
        "[extra]\n"
        "Server = https://mirror.invalid/$repo/os/$arch\n"
        "\n"
        "[multilib]\n"
        "Include = /etc/pacman.d/mirrorlist\n"
        "\n"
        "[blackarch]\n"
        "Include = /etc/pacman.d/blackarch-mirrorlist\n"
        "\n"
        "[chaotic-aur]\n"
        "Server = https://chaotic.invalid/$arch\n"
    )

    result = run_snapshot('_snapshot_write_pacman_config "$1" "$2" 2026-09-22', source, output)

    assert result.returncode == 0, result.stderr
    rewritten = output.read_text()
    assert "[options]" in rewritten
    assert "HoldPkg = pacman glibc" in rewritten
    assert "SigLevel = Required DatabaseOptional" in rewritten
    assert "SigLevel = PackageRequired" in rewritten
    assert "# [core-testing]" in rewritten
    for repo in ("core", "extra", "multilib"):
        assert f"[{repo}]" in rewritten
    assert rewritten.count(
        "Server = https://archive.archlinux.org/repos/2026/09/22/$repo/os/$arch"
    ) == 3
    assert "[blackarch]" not in rewritten
    assert "[chaotic-aur]" not in rewritten
    assert "mirror.invalid" not in rewritten


def test_last_green_uses_test_override():
    result = run_snapshot(
        "snapshot_last_green",
        env={"APHOTIC_SNAPSHOT_DATE": "2026-09-21"},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout == "2026-09-21\n"


def test_offer_does_not_prompt_or_install_without_tty(tmp_path: Path):
    bin_dir, calls = make_repo_tools(tmp_path)
    result = run_snapshot(
        "snapshot_offer sample",
        env={
            "APHOTIC_SNAPSHOT_DATE": "2026-09-21",
            "APHOTIC_SNAPSHOT_FALLBACK": "0",
            "DRY_RUN": "0",
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
        },
    )

    assert result.returncode != 0
    assert "last day every Aphotic package installed cleanly" in result.stdout
    assert "[y/N]" not in result.stdout + result.stderr
    assert not calls.exists()


def test_dry_run_prints_without_installing_or_writing_state(tmp_path: Path):
    bin_dir, calls = make_repo_tools(tmp_path)
    home = tmp_path / "home"
    home.mkdir()
    result = run_snapshot(
        "snapshot_offer sample",
        env={
            "APHOTIC_SNAPSHOT_DATE": "2026-09-21",
            "APHOTIC_SNAPSHOT_FALLBACK": "1",
            "DRY_RUN": "1",
            "HOME": str(home),
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
        },
    )

    assert result.returncode == 0, result.stderr
    assert "[dry-run]" in result.stdout
    assert "2026-09-21" in result.stdout
    assert "[y/N]" not in result.stdout + result.stderr
    assert not calls.exists()
    assert not (home / ".local/state/aphotic/snapshot").exists()


def test_forced_repo_failure_recovers_through_snapshot(tmp_path: Path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    installed = tmp_path / "installed"
    calls = tmp_path / "calls"
    pacman_conf = tmp_path / "pacman.conf"
    pacman_conf.write_text(
        "[options]\nSigLevel = Required DatabaseOptional\n"
        "[core]\nInclude = /etc/pacman.d/mirrorlist\n"
        "[extra]\nInclude = /etc/pacman.d/mirrorlist\n"
    )
    pacman = bin_dir / "pacman"
    pacman.write_text(
        "#!/usr/bin/env bash\n"
        f"installed={installed}\n"
        f"calls={calls}\n"
        "case \"$1\" in\n"
        "  -T) grep -qxF \"$2\" \"$installed\" 2>/dev/null ;;\n"
        "  -Si)\n"
        "    [[ \"$2\" == \"aur-pkg\" ]] && exit 1\n"
        "    printf 'Repository      : extra\\nName            : %s\\n' \"$2\"\n"
        "    ;;\n"
        "  --config)\n"
        "    printf 'snapshot guard=%s %s\\n' \"${OMARCHY_ALLOW_DIRECT_PACMAN:-}\" \"$*\" >> \"$calls\"\n"
        "    [[ \" $* \" == *\" second \"* ]] && printf 'second\\n' >> \"$installed\" || printf 'sample\\n' >> \"$installed\"\n"
        "    ;;\n"
        "  -S) printf 'normal %s\\n' \"$*\" >> \"$calls\"; printf 'sample\\n' >> \"$installed\" ;;\n"
        "esac\n"
    )
    pacman.chmod(0o755)
    sudo = bin_dir / "sudo"
    sudo.write_text("#!/usr/bin/env bash\nexec \"$@\"\n")
    sudo.chmod(0o755)
    curl = bin_dir / "curl"
    curl.write_text("#!/usr/bin/env bash\nprintf '{\"resultcount\":1}'\n")
    curl.chmod(0o755)
    home = tmp_path / "home"
    home.mkdir()
    install_log = tmp_path / "install.log"
    command = (
        'source "$1"; source "$2"; source "$3"; set +e; '
        'CNT="[NOTE]" COK="[OK]" CER="[ERROR]" CWR="[WARNING]" AUR_HELPER="" DETECTED_OMARCHY=1; '
        'install_software sample && install_software second && install_software aur-pkg optional'
    )
    result = subprocess.run(
        ["bash", "-c", command, "bash", str(REPORT), str(SNAPSHOT), str(PACKAGES)],
        cwd=ROOT,
        env={
            **os.environ,
            "APHOTIC_FORCE_FAIL": "sample",
            "APHOTIC_SNAPSHOT_DATE": "2026-09-21",
            "APHOTIC_SNAPSHOT_FALLBACK": "1",
            "APHOTIC_PACMAN_CONF": str(pacman_conf),
            "DRY_RUN": "0",
            "HOME": str(home),
            "INSTLOG": str(install_log),
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
        },
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "normal " not in calls.read_text()
    assert calls.read_text().count("snapshot ") == 2
    assert "snapshot guard=1" in calls.read_text()
    assert "cannot install it from the archive" in result.stdout
    state = (home / ".local/state/aphotic/snapshot").read_text()
    assert "snapshot=2026-09-21" in state
    assert "snapshot_packages=sample second" in state


def test_optional_repo_failures_get_one_snapshot_offer(tmp_path: Path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    pacman = bin_dir / "pacman"
    pacman.write_text(
        "#!/usr/bin/env bash\n"
        "if [[ \"$1\" == \"-Si\" ]]; then\n"
        "  printf 'Repository      : extra\\nName            : %s\\n' \"$2\"\n"
        "  exit 0\n"
        "fi\n"
        "exit 1\n"
    )
    pacman.chmod(0o755)
    install_log = tmp_path / "install.log"
    install_log.write_text("error: target not found\n")
    command = (
        'source "$1"; source "$2"; source "$3"; set +e; '
        'CNT="[NOTE]" COK="[OK]" CER="[ERROR]" CWR="[WARNING]"; '
        'FAILED_OPTIONAL_PACKAGES=(one two); FAILED_OPTIONAL_REPO_PACKAGES=(one two); '
        'report_failed_optional_packages'
    )
    result = subprocess.run(
        ["bash", "-c", command, "bash", str(REPORT), str(SNAPSHOT), str(PACKAGES)],
        cwd=ROOT,
        env={
            **os.environ,
            "APHOTIC_SNAPSHOT_DATE": "2026-09-21",
            "APHOTIC_SNAPSHOT_FALLBACK": "1",
            "APHOTIC_NO_REPORT": "1",
            "DRY_RUN": "1",
            "INSTLOG": str(install_log),
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
        },
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.count("[dry-run]") == 1
    assert "one two" in result.stdout


def test_doctor_reports_green_canary_and_upgrade_path(tmp_path: Path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    curl = bin_dir / "curl"
    curl.write_text(
        "#!/usr/bin/env bash\n"
        "printf '%s\\n' '{\"date\":\"2026-09-23\",\"green\":true,\"last_green\":\"2026-09-23\",\"broken\":[]}'\n"
    )
    curl.chmod(0o755)
    state_home = tmp_path / "state"
    state_dir = state_home / "aphotic"
    state_dir.mkdir(parents=True)
    state_file = state_dir / "snapshot"
    state_file.write_text("snapshot=2026-09-21\nsnapshot_packages=sample\n")
    command = 'source "$1"; _aphotic_doctor_snapshot'
    result = subprocess.run(
        ["bash", "-c", command, "bash", str(DOCTOR)],
        cwd=ROOT,
        env={
            **os.environ,
            "APHOTIC_DOTS_DIR": str(ROOT),
            "XDG_STATE_HOME": str(state_home),
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
        },
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "2026-09-21" in result.stdout
    assert "canary is green again" in result.stdout
    assert "sudo pacman -Syu" in result.stdout
    assert state_file.exists()


def test_doctor_reports_canary_still_broken(tmp_path: Path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    curl = bin_dir / "curl"
    curl.write_text(
        "#!/usr/bin/env bash\n"
        "printf '%s\\n' '{\"date\":\"2026-09-23\",\"green\":false,\"last_green\":\"2026-09-21\",\"broken\":[{\"package\":\"sample\"}]}'\n"
    )
    curl.chmod(0o755)
    state_home = tmp_path / "state"
    state_dir = state_home / "aphotic"
    state_dir.mkdir(parents=True)
    (state_dir / "snapshot").write_text("snapshot=2026-09-21\nsnapshot_packages=sample\n")
    result = subprocess.run(
        ["bash", "-c", 'source "$1"; _aphotic_doctor_snapshot', "bash", str(DOCTOR)],
        cwd=ROOT,
        env={
            **os.environ,
            "APHOTIC_DOTS_DIR": str(ROOT),
            "XDG_STATE_HOME": str(state_home),
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
        },
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "canary is still failing" in result.stdout
    assert "sudo pacman -Syu" not in result.stdout
