import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOLVER = ROOT / "tools/canary/resolve_release_tag.sh"


def commit(repo: Path, message: str) -> None:
    marker = repo / "marker"
    marker.write_text(f"{message}\n")
    subprocess.run(["git", "add", "marker"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-m", message], cwd=repo, check=True)


def make_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "Canary Test"], cwd=repo, check=True)
    subprocess.run(
        ["git", "config", "user.email", "canary@example.invalid"],
        cwd=repo,
        check=True,
    )
    return repo


def resolve(repo: Path) -> dict[str, str]:
    result = subprocess.run(
        ["bash", str(RESOLVER), str(repo)],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    return dict(line.split("=", 1) for line in result.stdout.splitlines())


def test_canary_release_resolver_uses_version_order(tmp_path: Path):
    repo = make_repo(tmp_path)
    commit(repo, "first")
    subprocess.run(["git", "tag", "v2.9.0"], cwd=repo, check=True)
    commit(repo, "second")
    subprocess.run(["git", "tag", "v2.10.0"], cwd=repo, check=True)

    assert resolve(repo)["tag"] == "v2.10.0"


def test_canary_release_resolver_skips_only_tagged_head(tmp_path: Path):
    repo = make_repo(tmp_path)
    commit(repo, "release")
    subprocess.run(["git", "tag", "v2.10.0"], cwd=repo, check=True)

    assert resolve(repo)["run"] == "false"

    commit(repo, "main change")

    assert resolve(repo)["run"] == "true"
