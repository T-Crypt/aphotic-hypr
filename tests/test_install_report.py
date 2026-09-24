import os
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "lib/install/report.sh"


def run_report(command: str, *args: Path, env: dict[str, str] | None = None):
    report_env = os.environ.copy()
    if env:
        report_env.update(env)
    return subprocess.run(
        ["bash", "-c", f'source "$1"; shift; {command}', "bash", str(REPORT), *map(str, args)],
        cwd=ROOT,
        env=report_env,
        text=True,
        capture_output=True,
        check=False,
    )


def test_report_bundle_redacts_private_values(tmp_path: Path):
    log_file = tmp_path / "install.log"
    bundle = tmp_path / "bundle.txt"
    log_file.write_text(
        "path=/home/alice/.cache name=alice host=aphotic-test "
        "ipv4=192.168.1.5 ipv6=2001:db8::5 "
        "mac=aa:bb:cc:dd:ee:ff email=bob@example.com token=secret-value\n"
    )

    result = run_report(
        '_install_report_write_bundle sample "$1" "$2"',
        log_file,
        bundle,
        env={"HOME": "/home/alice", "USER": "alice", "HOSTNAME": "aphotic-test"},
    )

    assert result.returncode == 0, result.stderr
    report = bundle.read_text()
    for private_value in (
        "/home/alice",
        "alice",
        "aphotic-test",
        "192.168.1.5",
        "2001:db8::5",
        "aa:bb:cc:dd:ee:ff",
        "bob@example.com",
        "secret-value",
    ):
        assert private_value not in report
    for marker in ("~/.cache", "<user>", "<host>", "<ip>", "<mac>", "<email>", "<redacted>"):
        assert marker in report


@pytest.mark.parametrize(
    ("log_tail", "expected"),
    [
        (
            "error: required key missing from keyring\n",
            "Your package keyring is out of date; run 'sudo pacman -Sy archlinux-keyring' and try again.",
        ),
        (
            "error: failed retrieving file: Could not resolve host: mirror.example\n",
            "A mirror or network connection failed while downloading the package",
        ),
        (
            ":: sample and old-package are in conflict\n",
            "conflicts with the installed package old-package",
        ),
        (
            "error: target not found: sample\n",
            "not in the repositories right now because an upstream package changed",
        ),
    ],
)
def test_install_failure_classification(tmp_path: Path, log_tail: str, expected: str):
    log_file = tmp_path / "install.log"
    log_file.write_text(log_tail)

    result = run_report('install_failure_explain sample "$1"', log_file)

    assert result.returncode == 0, result.stderr
    assert "sample failed" in result.stdout
    assert expected in result.stdout


def test_install_offer_report_does_not_prompt_without_tty(tmp_path: Path):
    log_file = tmp_path / "install.log"
    log_file.write_text("error: target not found: sample\n")

    result = run_report(
        'DRY_RUN=0 APHOTIC_NO_REPORT=0 install_offer_report sample "$1"',
        log_file,
    )

    assert result.returncode == 0, result.stderr
    assert "Send this as a GitHub issue?" not in result.stdout + result.stderr
    assert "Report this at" in result.stdout
