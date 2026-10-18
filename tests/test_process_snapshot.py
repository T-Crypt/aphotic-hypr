"""Process snapshots keep proportional memory and PID identity separate."""

import importlib.util
import json
from pathlib import Path


SOURCE = (Path(__file__).resolve().parent.parent / "Configs" / "quickshell" /
          "aphotic" / "services" / "ai" / "ProcessSnapshot.py")
SPEC = importlib.util.spec_from_file_location("process_snapshot", SOURCE)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def fake_proc(root, pid, ppid=1, pss=1024, ticks=100, threads=1, start=1):
    proc = root / str(pid)
    proc.mkdir()
    fields = ["S", str(ppid)] + ["0"] * 49
    fields[11] = str(ticks)
    fields[12] = "0"
    fields[17] = str(threads)
    fields[19] = str(start)
    (proc / "stat").write_text(f"{pid} (fake) " + " ".join(fields))
    (proc / "smaps_rollup").write_text(f"Pss: {pss} kB\n")


def test_snapshot_reads_pss_and_stat(tmp_path):
    proc = tmp_path / "42"
    proc.mkdir()
    fields = ["S"] + ["0"] * 50
    fields[11] = "300"
    fields[12] = "50"
    fields[17] = "7"
    fields[19] = "1234"
    (proc / "stat").write_text("42 (engine worker) " + " ".join(fields))
    (proc / "smaps_rollup").write_text("Rss: 8192 kB\nPss: 4096 kB\n")
    assert MODULE.snapshot(42, tmp_path) == {
        "pid": 42, "startTicks": 1234, "cpuTicks": 350,
        "threads": 7, "pssKiB": 4096,
    }


def test_snapshot_does_not_substitute_rss_for_missing_pss(tmp_path):
    proc = tmp_path / "42"
    proc.mkdir()
    (proc / "stat").write_text("42 (engine) " + " ".join(["S"] + ["0"] * 50))
    (proc / "smaps_rollup").write_text("Rss: 8192 kB\n")
    assert MODULE.snapshot(42, tmp_path) is None


def test_exited_pid_gives_no_reading(tmp_path):
    assert MODULE.snapshot(4242, tmp_path) is None


def test_main_reports_each_pid_of_a_tree_and_skips_exited(tmp_path, monkeypatch,
                                                         capsys):
    fake_proc(tmp_path, 100, ppid=1, pss=1024, threads=6)
    fake_proc(tmp_path, 101, ppid=100, pss=512, threads=3)
    monkeypatch.setenv("APHOTIC_PROC_ROOT", str(tmp_path))
    monkeypatch.setattr("sys.argv", ["ProcessSnapshot.py", "100", "101", "102"])
    MODULE.main()
    sample = json.loads(capsys.readouterr().out)
    assert sample["clockTicks"] > 0
    assert [row["pid"] for row in sample["rows"]] == [100, 101]
    assert [row["pssKiB"] for row in sample["rows"]] == [1024, 512]
    assert [row["threads"] for row in sample["rows"]] == [6, 3]
