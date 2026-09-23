#!/usr/bin/env bash
# tests/test_cmd_perf.sh
#
# Stubs nvidia-smi, pgrep, hyprctl and /proc (via APHOTIC_PROC_ROOT) on
# PATH/env, then exercises `aphotic perf snapshot|budget|history`: pmon
# parsing with "-" values and both C/G types, the no-NVIDIA path (gpu null,
# never fails), smaps_rollup heap parsing (missing file → null → SKIP),
# history append + the delta column, budget PASS/OVER/SKIP and
# exit codes, and the history table.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }
note() { echo "ok - $1"; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APHO="$ROOT/Configs/.local/bin/aphotic"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_BIN="$WORK/bin"; mkdir -p "$FAKE_BIN"
PROC="$WORK/proc"; mkdir -p "$PROC"

export XDG_STATE_HOME="$WORK/state"
export XDG_DATA_HOME="$WORK/data"
export XDG_CONFIG_HOME="$WORK/config"
export APHOTIC_DOTS_DIR="$ROOT"
export APHOTIC_PROC_ROOT="$PROC"
export APHOTIC_PERF_INTERVAL=0
PATH_BACKUP="$PATH"
export PATH="$FAKE_BIN:$PATH"

HIST="$XDG_STATE_HOME/aphotic/perf/history.jsonl"

# /proc stubs: pid 1000 is the qs -c aphotic shell, 1001 a qs that must be
# ignored, 2000 Hyprland. rss pages * 4096 / 1048576 = MiB: 50000 -> 195.3,
# 60000 -> 234.4.
write_stat() { # pid comm utime stime threads rss_pages
    mkdir -p "$PROC/$1"
    printf '%s (%s) S 999 1000 1000 0 -1 4194304 5 0 0 0 %s %s 0 0 20 0 %s 0 1234 100000 %s\n' \
        "$1" "$2" "$3" "$4" "$5" "$6" > "$PROC/$1/stat"
}
write_stat 1000 qs 500 300 8 50000
write_stat 1001 qs 100 50 2 1000
write_stat 2000 Hyprland 700 400 12 60000
printf 'qs\0-c\0aphotic\0' > "$PROC/1000/cmdline"
printf 'qs\0-c\0other\0' > "$PROC/1001/cmdline"
printf 'Hyprland\0--config\0x\0' > "$PROC/2000/cmdline"

# smaps_rollup stubs: Pss_Anon kB → heap MiB (354304 → 346.0, 512000 → 500.0).
write_smaps() { # pid pss_anon_kb
    mkdir -p "$PROC/$1"
    printf 'Rss: 600000 kB\nPss_Anon: %s kB\nPss_File: 4096 kB\n' "$2" > "$PROC/$1/smaps_rollup"
}
write_smaps 1000 354304
write_smaps 2000 512000

cat > "$FAKE_BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
name=""
[[ "${1:-}" == "-x" ]] && name="${2:-}"
case "$name" in
  qs|quickshell) printf '1000\n1001\n' ;;
  Hyprland) printf '2000\n' ;;
esac
EOF

cat > "$FAKE_BIN/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "pmon" ]]; then
  n=10
  while [[ $# -gt 0 ]]; do
    [[ "${1:-}" == "-c" ]] && n="${2:-10}"
    shift
  done
  printf '# gpu pid type sm mem enc dec jpg ofa fb ccpm command\n'
  for i in $(seq 1 "$n"); do
    printf '  0 1500 C 10 - - - - - 200 - qs\n'
    printf '  0 2100 G - - - - - - 120 - Hyprland\n'
    printf '  0 2200 G 2 - - - - - 30 - Xwayland\n'
  done
  exit 0
fi
if [[ "${1:-}" == --query-gpu* ]]; then
  printf '1800, 8192, 5\n'
  exit 0
fi
exit 1
EOF

cat > "$FAKE_BIN/hyprctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "monitors" && "${2:-}" == "-j" ]]; then
  printf '[{"name":"DP-1","width":2560,"height":1440,"refreshRate":144.00},{"name":"HDMI-A-1","width":1920,"height":1080,"refreshRate":60.00}]\n'
  exit 0
fi
exit 1
EOF

chmod +x "$FAKE_BIN/pgrep" "$FAKE_BIN/nvidia-smi" "$FAKE_BIN/hyprctl"

# ---- snapshot with stubbed NVIDIA: JSON, pmon "-"/C/G parsing, monitors ----
out="$(bash "$APHO" perf snapshot --samples 3 --label baseline 2>&1)"
[[ "$out" == *baseline* ]] || fail "snapshot output should carry the label: $out"
[[ "$out" == *"no previous snapshot"* ]] || fail "first snapshot should report no previous: $out"
[[ "$out" =~ 1500[[:space:]]+C[[:space:]]+10.0%[[:space:]]+200[[:space:]]+qs ]] \
    || fail "expected a C-type qs row (sm 10, fb 200): $out"
[[ "$out" =~ 2100[[:space:]]+G[[:space:]]+0.0%[[:space:]]+120[[:space:]]+Hyprland ]] \
    || fail "expected a G-type Hyprland row with '-' sm parsed as 0: $out"
[[ "$out" == *"2560x1440"* ]] || fail "monitor resolution missing: $out"
[[ "$out" == *"heap 346.0 MiB"* ]] || fail "shell line should print heap from smaps_rollup: $out"
[[ -s "$HIST" ]] || fail "history.jsonl was not written"
[[ "$(wc -l < "$HIST")" -eq 1 ]] || fail "expected 1 history line: $(cat "$HIST")"

python3 - "$HIST" <<'PY' || fail "history JSON does not match the snapshot"
import json, sys
d = json.loads(open(sys.argv[1]).readline())
g = d["gpu"]
assert g["card_used_mib"] == 1800 and g["card_total_mib"] == 8192 and g["card_util"] == 5, g
procs = {p["name"]: p for p in g["procs"]}
assert abs(procs["qs"]["fb_mib"] - 200) < 0.001 and procs["qs"]["sm_avg"] == 10.0, procs
assert procs["Hyprland"]["fb_mib"] == 120 and procs["Hyprland"]["sm_avg"] == 0.0, procs
assert procs["Xwayland"]["sm_avg"] == 2.0 and procs["Xwayland"]["fb_mib"] == 30, procs
sh = d["shell"]
assert abs(sh["rss_mib"] - 195.3) < 0.5 and sh["threads"] == 8, sh
assert abs(sh["heap_mib"] - 346.0) < 0.01, sh
assert abs(d["hyprland"]["rss_mib"] - 234.4) < 0.5, d["hyprland"]
assert abs(d["hyprland"]["heap_mib"] - 500.0) < 0.01, d["hyprland"]
assert d["label"] == "baseline"
assert len(d["monitors"]) == 2 and d["monitors"][0]["resolution"] == "2560x1440"
assert d["monitors"][1]["refresh"] == 60.0
PY
note "snapshot with GPU: JSON, pmon '-' parsing, C/G types, monitors"

# ---- second snapshot: history append + delta column ----
python3 - "$PROC/1000/stat" <<'PY' || fail "failed to bump fake stat rss"
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r" (\d+)$", r" 60000", s, count=1)
open(p, "w").write(s)
PY
write_smaps 1000 358400
out="$(bash "$APHO" perf snapshot --samples 2 --label second 2>&1)"
[[ "$out" == *"vs previous snapshot"* ]] || fail "second snapshot missing the delta block: $out"
[[ "$out" == *"+39.1 MiB"* || "$out" == *"+39.0 MiB"* ]] \
    || fail "shell RSS delta missing (rss 50000 -> 60000 pages): $out"
[[ "$out" =~ shell\ heap[[:space:]]+\+4\.0\ MiB ]] \
    || fail "shell heap delta missing (Pss_Anon 354304 -> 358400 kB): $out"
[[ "$(wc -l < "$HIST")" -eq 2 ]] || fail "expected 2 history lines after the second snapshot"
note "second snapshot: history append + delta column"

# ---- regression: real kernels append fields after rss (field 22) ----
cat > "$PROC/1000/stat" <<'EOF'
1000 (qs) S 999 1000 1000 0 -1 4194304 5 0 0 0 500 300 0 0 20 0 8 0 1234 100000 50000 0 4194304 4198400 4198400 4294959552 0 0 0 0 0 0 0 17 1 0 0 0 0 0 0 0 0 0 0 0 0
EOF
out="$(bash "$APHO" perf snapshot --samples 1 --label longstat 2>&1)"
[[ "$out" == *"rss 195.3 MiB"* && "$out" == *"8 threads"* ]] \
    || fail "stat with trailing kernel fields must still read rss/threads: $out"
note "long /proc stat: rss/threads read by field index"

# ---- smaps_rollup missing: heap null in JSON, budget SKIP ----
rm -f "$PROC/1000/smaps_rollup"
out="$(bash "$APHO" perf snapshot --samples 1 --label noheap 2>&1)"
[[ "$out" == *"heap n/a MiB"* ]] || fail "shell line should print n/a heap when smaps is gone: $out"
python3 - "$HIST" <<'PY' || fail "missing smaps_rollup should record heap_mib null"
import json, sys
d = json.loads([l for l in open(sys.argv[1]) if l.strip()][-1])
assert d["label"] == "noheap", d
assert d["shell"] is not None and d["shell"]["heap_mib"] is None, d["shell"]
assert d["shell"]["rss_mib"] is not None, d["shell"]
PY
out="$(bash "$APHO" perf budget --from-history 2>&1)" \
    || fail "budget with a null heap should SKIP, not OVER: $out"
grep -q 'shell_heap_mib.*no data.*SKIP' <<<"$out" \
    || fail "shell_heap_mib should read SKIP without smaps_rollup: $out"
if grep -q 'shell_rss_mib' <<<"$out"; then fail "RSS must not appear as a budget row: $out"; fi
write_smaps 1000 354304
note "missing smaps_rollup: heap null, budget SKIP"

# ---- no-NVIDIA path: nvidia-smi present but failing ----
cat > "$FAKE_BIN/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
echo 'no NVIDIA driver' >&2
exit 1
EOF
chmod +x "$FAKE_BIN/nvidia-smi"
out="$(bash "$APHO" perf snapshot --samples 1 --label nogpu 2>&1)"
[[ "$out" == *"no NVIDIA"* ]] || fail "should say no NVIDIA data: $out"
python3 - "$HIST" <<'PY' || fail "no-NVIDIA snapshot should record gpu null"
import json, sys
d = json.loads([l for l in open(sys.argv[1]) if l.strip()][-1])
assert d["gpu"] is None, d["gpu"]
assert d["shell"] is not None, d["shell"]
assert len(d["monitors"]) == 2 and d["monitors"][0]["name"] == "DP-1", d["monitors"]
PY
note "no-NVIDIA (failing nvidia-smi): gpu null, exit 0"

# ---- nvidia-smi genuinely absent from PATH ----
rm -f "$FAKE_BIN/nvidia-smi"
HIDE="$WORK/hide"; mkdir -p "$HIDE"
while IFS= read -r d; do
    [[ -d "$d" && "$d" != "$FAKE_BIN" ]] || continue
    for f in "$d"/*; do
        [[ -x "$f" && ! -d "$f" ]] || continue
        b="${f##*/}"
        [[ "$b" == "nvidia-smi" || "$b" == "hyprctl" ]] && continue
        [[ -e "$HIDE/$b" ]] || ln -s "$f" "$HIDE/$b"
    done
done <<< "$(printf '%s\n' "$PATH" | tr ':' '\n')"
out="$(PATH="$FAKE_BIN:$HIDE" bash "$APHO" perf snapshot --samples 1 --label nogpu2 2>&1)"
[[ "$out" == *"no NVIDIA"* ]] || fail "missing nvidia-smi should say no NVIDIA data: $out"
rm -f "$FAKE_BIN/hyprctl"
out="$(PATH="$FAKE_BIN:$HIDE" bash "$APHO" perf snapshot --samples 1 --label nomon 2>&1)"
[[ "$out" == *"no NVIDIA"* ]] || fail "still no NVIDIA data when hyprctl is gone too: $out"
[[ "$out" == *"hyprctl"* ]] || fail "should note hyprctl unavailable: $out"
python3 - "$HIST" <<'PY' || fail "no-hyprctl snapshot should record no monitors"
import json, sys
d = json.loads([l for l in open(sys.argv[1]) if l.strip()][-1])
assert d["monitors"] == [], d["monitors"]
assert d["gpu"] is None, d["gpu"]
PY
note "missing nvidia-smi + hyprctl: never fails, monitors skipped"

# ---- restore the good GPU stubs for the budget tests ----
cat > "$FAKE_BIN/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "pmon" ]]; then
  n=10
  while [[ $# -gt 0 ]]; do
    [[ "${1:-}" == "-c" ]] && n="${2:-10}"
    shift
  done
  printf '# gpu pid type sm mem enc dec jpg ofa fb ccpm command\n'
  for i in $(seq 1 "$n"); do
    printf '  0 1500 C 10 - - - - - 200 - qs\n'
    printf '  0 2100 G - - - - - - 120 - Hyprland\n'
    printf '  0 2200 G 2 - - - - - 30 - Xwayland\n'
  done
  exit 0
fi
if [[ "${1:-}" == --query-gpu* ]]; then
  printf '1800, 8192, 5\n'
  exit 0
fi
exit 1
EOF
cat > "$FAKE_BIN/hyprctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "monitors" && "${2:-}" == "-j" ]]; then
  printf '[{"name":"DP-1","width":2560,"height":1440,"refreshRate":144.00}]\n'
  exit 0
fi
exit 1
EOF
chmod +x "$FAKE_BIN/nvidia-smi" "$FAKE_BIN/hyprctl"

mkdir -p "$XDG_DATA_HOME/aphotic"
cat > "$XDG_DATA_HOME/aphotic/perf-budget.json" <<'EOF'
{"shell_vram_mib": 350, "shell_vram_inference_mib": 500, "idle_gpu_util_pct": 10, "shell_heap_mib": 350, "shell_cpu_pct": 2}
EOF

# ---- budget: all PASS against the latest snapshot ----
bash "$APHO" perf snapshot --samples 1 --label budgetbase >/dev/null 2>&1
out="$(bash "$APHO" perf budget --from-history 2>&1)" || fail "all-PASS budget should exit 0: $out"
[[ "$(grep -c 'PASS' <<<"$out")" -eq 5 ]] || fail "expected 5 PASS lines: $out"
[[ "$(grep -c 'OVER' <<<"$out")" -eq 0 ]] || fail "expected no OVER lines: $out"
grep -q 'shell_heap_mib.*346 MiB / 350 MiB.*PASS' <<<"$out" \
    || fail "shell_heap_mib should read 346 / 350 PASS: $out"
if grep -q 'shell_rss_mib' <<<"$out"; then fail "RSS must not be budgeted: $out"; fi
note "budget: 5 PASS on a good snapshot, exit 0"

# ---- budget: OVER and nonzero exit from a crafted snapshot ----
python3 - "$HIST" <<'PY' || fail "failed to append crafted OVER history line"
import json, sys
doc = {
    "ts": "2026-09-23T00:00:00+00:00", "label": "over",
    "gpu": {"card_used_mib": 4000, "card_total_mib": 8192, "card_util": 99,
            "procs": [{"name": "qs", "pid": 1500, "fb_mib": 400, "sm_avg": 80},
                      {"name": "Hyprland", "pid": 2100, "fb_mib": 500, "sm_avg": 90}]},
    "shell": {"rss_mib": 900, "heap_mib": 900, "cpu_avg": 50, "threads": 12},
    "hyprland": {"rss_mib": 500, "cpu_avg": 10, "threads": 20},
    "monitors": [],
}
open(sys.argv[1], "a").write(json.dumps(doc) + "\n")
PY
set +e
out="$(bash "$APHO" perf budget --from-history 2>&1)"
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "budget should exit 1 when any budget is OVER: $out"
[[ "$out" == *"OVER"* ]] || fail "expected OVER lines: $out"
[[ "$out" =~ shell_heap_mib.*OVER ]] || fail "shell_heap_mib should read OVER: $out"
if grep -q 'shell_rss_mib' <<<"$out"; then fail "RSS must not be budgeted even when huge: $out"; fi
[[ "$(grep -c 'OVER' <<<"$out")" -eq 5 ]] || fail "expected all 5 budgets OVER: $out"
note "budget: OVER rows and exit code 1"

# ---- budget: history row without heap_mib → SKIP for that budget only ----
python3 - "$HIST" <<'PY' || fail "failed to append crafted no-heap history line"
import json, sys
doc = {
    "ts": "2026-09-23T00:30:00+00:00", "label": "noheaprow",
    "gpu": {"card_used_mib": 1800, "card_total_mib": 8192, "card_util": 5,
            "procs": [{"name": "qs", "pid": 1500, "fb_mib": 200, "sm_avg": 10},
                      {"name": "Hyprland", "pid": 2100, "fb_mib": 120, "sm_avg": 5},
                      {"name": "Xwayland", "pid": 2200, "fb_mib": 30, "sm_avg": 2}]},
    "shell": {"rss_mib": 400, "cpu_avg": 1, "threads": 8},
    "hyprland": {"rss_mib": 500, "cpu_avg": 1, "threads": 20},
    "monitors": [],
}
open(sys.argv[1], "a").write(json.dumps(doc) + "\n")
PY
out="$(bash "$APHO" perf budget --from-history 2>&1)" || fail "no-heap-row budget should exit 0: $out"
grep -q 'shell_heap_mib.*no data.*SKIP' <<<"$out" \
    || fail "history row without heap_mib should SKIP shell_heap_mib: $out"
[[ "$(grep -c 'SKIP' <<<"$out")" -eq 1 ]] || fail "only shell_heap_mib should SKIP: $out"
[[ "$(grep -c 'PASS' <<<"$out")" -eq 4 ]] || fail "other 4 budgets should PASS: $out"
note "budget: history row without heap_mib → SKIP, rest PASS"

# ---- budget: SKIP when there is no data (gpu null, shell null) ----
python3 - "$HIST" <<'PY' || fail "failed to append crafted no-data history line"
import json, sys
doc = {"ts": "2026-09-23T01:00:00+00:00", "label": "skip", "gpu": None,
       "shell": None, "hyprland": None, "monitors": []}
open(sys.argv[1], "a").write(json.dumps(doc) + "\n")
PY
out="$(bash "$APHO" perf budget --from-history 2>&1)" || fail "all-SKIP budget should exit 0: $out"
[[ "$(grep -c 'SKIP' <<<"$out")" -eq 5 ]] || fail "expected 5 SKIP lines: $out"
note "budget: SKIP (no data) and exit 0"

# ---- budget without --from-history takes a fresh snapshot ----
out="$(bash "$APHO" perf budget 2>&1)" || fail "budget take-one should exit 0: $out"
[[ "$(grep -c 'PASS' <<<"$out")" -eq 5 ]] || fail "take-one budget expected 5 PASS: $out"
note "budget without --from-history takes a snapshot"

# ---- history table ----
out="$(bash "$APHO" perf history --last 4 2>&1)"
[[ "$(grep -c '2026-' <<<"$out")" -eq 4 ]] || fail "history --last 4 should show 4 rows: $out"
out="$(bash "$APHO" perf history 2>&1)"
[[ "$out" == *longstat* && "$out" == *over* && "$out" == *skip* ]] \
    || fail "history rows should carry labels: $out"
[[ "$(grep -c '2026-' <<<"$out")" -ge 9 ]] || fail "history default should show rows: $out"
note "history table: --last N and defaults"

# ---- help, registration, error handling ----
hout="$(bash "$APHO" --help 2>&1)"; [[ "$hout" == *perf* ]] || fail "perf not listed in aphotic --help"
hout="$(bash "$APHO" perf --help 2>&1)"; [[ "$hout" == *snapshot* ]] || fail "perf --help missing subcommands"
hout="$(bash "$APHO" perf snapshot --help 2>&1)"; [[ "$hout" == *--samples* ]] || fail "snapshot --help missing --samples"
set +e
bash "$APHO" perf bogus >/dev/null 2>&1
rc_bogus=$?
rm -f "$HIST"
bash "$APHO" perf budget --from-history >/dev/null 2>&1
rc_nohist=$?
set -e
[[ "$rc_bogus" -ne 0 ]] || fail "unknown perf subcommand should exit nonzero"
[[ "$rc_nohist" -ne 0 ]] || fail "budget --from-history with no history should exit nonzero"

echo "PASS: perf command (snapshot/budget/history)"