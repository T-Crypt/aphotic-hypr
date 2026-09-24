import json
import shutil
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
RANKER = ROOT / "Configs/quickshell/aphotic/services/PkgSearchRank.js"
SAMPLE = ROOT / "tests/fixtures/yay_ss_remmina.txt"


@pytest.mark.skipif(shutil.which("node") is None, reason="needs node")
def test_exact_official_package_ranks_first_and_groups_stay_ordered():
    script = f"""
const fs = require("fs");
const vm = require("vm");
const context = {{}};
vm.createContext(context);
vm.runInContext(fs.readFileSync({json.dumps(str(RANKER))}, "utf8"), context);

function parse(output) {{
    const lines = output.split("\\n");
    const results = [];
    for (let i = 0; i < lines.length; i++) {{
        const line = lines[i];
        if (line.length === 0 || /^[ \\t]/.test(line))
            continue;
        const slash = line.indexOf("/");
        if (slash === -1)
            continue;
        const repo = line.slice(0, slash);
        const rest = line.slice(slash + 1);
        const nameEnd = rest.indexOf(" ");
        results.push({{
            repo,
            name: nameEnd === -1 ? rest : rest.slice(0, nameEnd),
            description: i + 1 < lines.length && /^[ \\t]/.test(lines[i + 1])
                ? lines[i + 1].trim() : ""
        }});
    }}
    return results;
}}

const sample = fs.readFileSync({json.dumps(str(SAMPLE))}, "utf8");
const ranked = context.rankResults(parse(sample), "ReMmInA");
process.stdout.write(JSON.stringify(ranked));
"""
    result = subprocess.run(
        ["node", "-e", script],
        check=True,
        capture_output=True,
        text=True,
    )
    ranked = json.loads(result.stdout)

    assert [item["name"] for item in ranked] == [
        "remmina",
        "remmina-plugins",
        "xremmina-tools",
        "desktop-integration",
        "remmina-git",
        "remmina-plugin-legacy",
        "remmina-plugin-url",
        "xremmina-theme",
        "remote-desktop-helper",
    ]
    assert [item["repo"] for item in ranked[1:]] == [
        "extra",
        "extra",
        "extra",
        "aur",
        "aur",
        "aur",
        "aur",
        "aur",
    ]
