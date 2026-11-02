"""Every tests/*.cjs suite runs under pytest, so CI runs it.

The JS cores are tested by plain node scripts. Only the two a pytest file
wrapped by hand ever ran in CI; the rest passed or failed unseen.
"""
import shutil
import subprocess
from pathlib import Path

import pytest

SUITES = sorted((Path(__file__).resolve().parent).glob("test_*.cjs"))


@pytest.mark.skipif(shutil.which("node") is None, reason="node unavailable")
@pytest.mark.parametrize("suite", SUITES, ids=[s.name for s in SUITES])
def test_node_suite(suite):
    result = subprocess.run(["node", str(suite)], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
