#!/usr/bin/env python3
"""Read one snapshot of the given processes from procfs."""

import json
import os
import sys
from pathlib import Path


def snapshot(pid: int, root: Path = Path("/proc")) -> dict | None:
    if pid <= 0:
        return None
    try:
        stat = (root / str(pid) / "stat").read_text()
        fields = stat[stat.rfind(")") + 2 :].split()
        ticks = int(fields[11]) + int(fields[12])
        start = int(fields[19])
        threads = int(fields[17])
        rollup = (root / str(pid) / "smaps_rollup").read_text()
        pss = next(int(line.split()[1]) for line in rollup.splitlines()
                   if line.startswith("Pss:"))
    except (OSError, ValueError, IndexError, StopIteration):
        return None
    return {"pid": pid, "startTicks": start, "cpuTicks": ticks,
            "threads": threads, "pssKiB": pss}


def main() -> None:
    root = Path(os.environ.get("APHOTIC_PROC_ROOT", "/proc"))
    pids = set()
    for arg in sys.argv[1:]:
        if arg.isdecimal():
            pids.add(int(arg))
    rows = [row for pid in sorted(pids) if (row := snapshot(pid, root))]
    print(json.dumps({"clockTicks": os.sysconf("SC_CLK_TCK"), "rows": rows}))


if __name__ == "__main__":
    main()
