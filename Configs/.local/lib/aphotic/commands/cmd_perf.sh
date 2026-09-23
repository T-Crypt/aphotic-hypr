#!/usr/bin/env bash
# aphotic perf — sample GPU, the Quickshell daemon and Hyprland once a
# second, append one JSON line to perf/history.jsonl, print a table with a
# delta vs the previous snapshot, and PASS/OVER check the shell against
# perf-budget.json. GPU data is NVIDIA-only (nvidia-smi pmon); when
# nvidia-smi is missing or the query fails the snapshot records
# "gpu": null and never errors.
# @cmd: perf
# @cmd.desc: Performance snapshot and budget check (GPU, shell, Hyprland)
# @cmd.group: CORE
# @cmd.opt: snapshot [--samples N=10] [--label TEXT] | Append an N-sample snapshot to history.jsonl
# @cmd.opt: budget [--from-history] | PASS/OVER check against perf-budget.json; exit 1 when any OVER
# @cmd.opt: history [--last N=10] | Table of recent snapshots

_aphotic_perf_hist() { printf '%s/perf/history.jsonl\n' "$APHOTIC_STATE_HOME"; }

_aphotic_perf_budget_file() {
    [[ -f "${APHOTIC_DATA_HOME}/perf-budget.json" ]] && { printf '%s\n' "${APHOTIC_DATA_HOME}/perf-budget.json"; return 0; }
    [[ -n "${BIN_DIR:-}" && -f "${BIN_DIR}/../share/aphotic/perf-budget.json" ]] \
        && printf '%s\n' "${BIN_DIR}/../share/aphotic/perf-budget.json"
}

# The running Quickshell daemon: comm qs or quickshell, started with -c aphotic.
_aphotic_perf_shell_pid() {
    local root="${APHOTIC_PROC_ROOT:-/proc}" name pid cmd
    for name in qs quickshell; do
        while read -r pid; do
            [[ -n "$pid" ]] || continue
            cmd="$(tr '\0' ' ' < "${root}/${pid}/cmdline" 2>/dev/null)"
            if [[ "$cmd" == *"-c aphotic"* ]]; then
                printf '%s\n' "$pid"
                return 0
            fi
        done < <(pgrep -x "$name" 2>/dev/null || true)
    done
    return 1
}

# /proc/<pid>/stat → "rss_pages utime stime threads". After the comm paren,
# the first 22 fields are stable across kernel versions; later ones are not,
# so split by index instead of bash read (which would fold the tail into the
# last variable).
_aphotic_perf_read_stat() {
    local pid="$1"
    awk '
        {
            rest = substr($0, index($0, ")") + 1)
            n = split(rest, f, " ")
            if (n < 22) exit 0
            printf "%s %s %s %s\n", f[22] + 0, f[12] + 0, f[13] + 0, f[18] + 0
        }
    ' "${APHOTIC_PROC_ROOT:-/proc}/${pid}/stat" 2>/dev/null || true
}

# smaps_rollup "Pss_Anon:" (kB) → MiB, one decimal; null when the file or
# the field is missing.
_aphotic_perf_read_heap() {
    local kb
    kb="$(awk '/^Pss_Anon:/ { print $2; exit }' "${APHOTIC_PROC_ROOT:-/proc}/${1}/smaps_rollup" 2>/dev/null)" || true
    [[ "$kb" =~ ^[0-9]+$ ]] || { printf 'null\n'; return 0; }
    awk -v kb="$kb" 'BEGIN { printf "%.1f", kb / 1024 }'
}

# nvidia-smi pmon output → "name<TAB>pid<TAB>type<TAB>fb<TAB>sm" lines,
# sm averaged over the samples for a pid, fb from the last sample ("-" = 0).
_aphotic_perf_parse_pmon() {
    awk '
        /^#/ {
            if (!hdr) {
                base = ($1 == "#") ? 2 : 1
                for (i = base; i <= NF; i++) col[tolower($i)] = i - base + 1
                hdr = 1
            }
            next
        }
        hdr && NF {
            pid = $(col["pid"]); tp = $(col["type"])
            if (pid == "" || tp == "") next
            sm = $(col["sm"]); fb = $(col["fb"])
            sm = (sm == "-" || sm == "") ? 0 : (sm + 0)
            fb = (fb == "-" || fb == "") ? 0 : (fb + 0)
            cmd = ""; for (i = col["command"]; i <= NF; i++) cmd = cmd (i > col["command"] ? " " : "") $i
            cnt[pid]++; ssum[pid] += sm; fbv[pid] = fb; tpv[pid] = tp; cmv[pid] = cmd
        }
        END {
            for (p in cnt) printf "%s\t%s\t%s\t%.0f\t%.1f\n", cmv[p], p, tpv[p], fbv[p], ssum[p] / cnt[p]
        }
    ' "$1" | sort -t$'\t' -k2,2n
}

# NVIDIA card totals → "used total util", nothing when the query fails.
_aphotic_perf_card() {
    local line
    line="$(nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1 || true)"
    [[ -n "$line" ]] || return 1
    line="$(tr -d ' ' <<<"$line")"
    IFS=, read -r used total util <<<"$line" || return 1
    printf '%s %s %s\n' "$used" "$total" "$util"
}

# hyprctl monitors -j → "name<TAB>w<TAB>h<TAB>rate" lines, nothing if hyprctl is missing.
_aphotic_perf_monitors() {
    command -v hyprctl >/dev/null 2>&1 || return 0
    hyprctl monitors -j 2>/dev/null | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for m in data:
    print("{}\t{}\t{}\t{}".format(m.get("name", "?"), m.get("width", 0), m.get("height", 0), m.get("refreshRate", "")))
' || true
}

# CPU % from two /proc/<pid>/stat tick samples over wall seconds.
_aphotic_perf_cpu() {
    local pid="$1" u0="$2" s0="$3" u1="$4" s1="$5" wall="$6" hz
    [[ -n "$pid" ]] || { printf 'null\n'; return 0; }
    [[ "$wall" -gt 0 ]] || { printf '0\n'; return 0; }
    hz="$(getconf CLK_TCK 2>/dev/null || echo 100)"
    [[ "$hz" =~ ^[0-9]+$ ]] || hz=100
    awk -v u0="$u0" -v s0="$s0" -v u1="$u1" -v s1="$s1" -v w="$wall" -v hz="$hz" '
        BEGIN { d = (u1 + s1) - (u0 + s0); if (d < 0) d = 0; printf "%.1f", 100 * d / hz / w }
    '
}

# Signed delta "cur vs prev" with a unit; n/a when either side has no data.
_aphotic_perf_delta() {
    local cur="$1" prev="$2" unit="$3"
    if [[ "$cur" == "na" || "$cur" == "null" || "$prev" == "na" || "$prev" == "null" ]]; then
        printf 'n/a\n'; return 0
    fi
    awk -v a="$cur" -v b="$prev" -v u="$unit" 'BEGIN { d = a - b; if (d >= 0) printf "+%.1f%s", d, u; else printf "%.1f%s", d, u }'
}

# Last history line → "s_vram<TAB>card_used<TAB>hypr_sm<TAB>s_rss<TAB>s_heap<TAB>s_cpu"; na when absent.
_aphotic_perf_prev() { python3 - "$1" <<'PY'
import sys, json
path = sys.argv[1]
try:
    lines = [l for l in open(path) if l.strip()]
except Exception:
    lines = []
doc = None
for l in reversed(lines):
    try:
        doc = json.loads(l); break
    except Exception:
        pass
if doc is None:
    print("\t".join(["na"] * 6)); sys.exit(0)
def num(v):
    if v is None: return "na"
    try: return float(v)
    except Exception: return "na"
g = doc.get("gpu")
def procs_fb(names):
    if not isinstance(g, dict): return "na"
    tot = 0.0
    for p in g.get("procs", []):
        if p.get("name") in names:
            tot += float(p.get("fb_mib", 0) or 0)
    return tot
def proc_sm(names):
    if not isinstance(g, dict): return "na"
    best = None
    for p in g.get("procs", []):
        if p.get("name") in names and p.get("sm_avg") is not None:
            v = float(p["sm_avg"])
            best = v if best is None or v > best else best
    return best if best is not None else "na"
card = g.get("card_used_mib") if isinstance(g, dict) else None
sh = doc.get("shell")
out = [procs_fb({"qs", "quickshell"}), card, proc_sm({"Hyprland"}),
       num(sh.get("rss_mib")) if isinstance(sh, dict) else "na",
       num(sh.get("heap_mib")) if isinstance(sh, dict) else "na",
       num(sh.get("cpu_avg")) if isinstance(sh, dict) else "na"]
print("\t".join(str(x) for x in out))
PY
}

# Assemble the history JSON line. argv carries ts, label, shell, hyprland,
# GPU scalars (numbers or "null") and the payload file path; the payload
# holds procs rows, a blank line, then monitor rows.
_aphotic_perf_emit() { python3 - "$@" <<'PY'
import sys, json
def num(v):
    try: return float(v)
    except Exception: return None
args = sys.argv[1:]
payload = open(args[-1]).read()
args = args[:-1]
ts, label = args[0], args[1]
def obj(rss, heap, cpu, threads):
    if rss == "null": return None
    return {"rss_mib": num(rss), "heap_mib": num(heap), "cpu_avg": num(cpu) or 0.0, "threads": int(threads)}
shell = obj(*args[2:6])
hyprland = obj(*args[6:10])
used, total, util = num(args[10]), num(args[11]), num(args[12])
procs, monitors = [], []
mode = 0
for line in payload.splitlines():
    if not line.strip():
        mode = 1; continue
    if mode == 0:
        n, p, _tp, fb, sm = line.split("\t")
        procs.append({"name": n, "pid": int(p), "fb_mib": num(fb), "sm_avg": num(sm)})
    else:
        n, w, h, r = line.split("\t")
        monitors.append({"name": n, "resolution": "%sx%s" % (int(w), int(h)),
                         "refresh": num(r) if r else None})
gpu = None
if used is not None:
    gpu = {"card_used_mib": used, "card_total_mib": total, "card_util": util, "procs": procs}
print(json.dumps({"ts": ts, "label": label, "gpu": gpu, "shell": shell,
                  "hyprland": hyprland, "monitors": monitors}, separators=(",", ":")))
PY
}

# Budget file + snapshot doc file → "name<TAB>value<TAB>limit<TAB>status" rows.
_aphotic_perf_budget_rows() { python3 - "$1" "$2" <<'PY'
import sys, json
bud = json.load(open(sys.argv[1]))
doc = json.load(open(sys.argv[2]))
g = doc.get("gpu")
def fb(names):
    if not isinstance(g, dict): return None
    return sum(float(p.get("fb_mib", 0) or 0) for p in g.get("procs", []) if p.get("name") in names)
sh = doc.get("shell")
vals = {"shell_vram_mib": fb({"qs", "quickshell"}),
        "shell_vram_inference_mib": fb({"qs", "quickshell", "Hyprland", "Xwayland"}),
        "idle_gpu_util_pct": g.get("card_util") if isinstance(g, dict) else None,
        "shell_heap_mib": sh.get("heap_mib") if isinstance(sh, dict) else None,
        "shell_cpu_pct": sh.get("cpu_avg") if isinstance(sh, dict) else None}
for name in ("shell_vram_mib", "shell_vram_inference_mib", "idle_gpu_util_pct",
             "shell_heap_mib", "shell_cpu_pct"):
    v = vals[name]
    if v is None or name not in bud:
        print("%s\tna\t%s\tSKIP" % (name, bud.get(name, "?"))); continue
    try:
        limit = float(bud[name])
    except Exception:
        print("%s\tna\t%s\tSKIP" % (name, bud.get(name, "?"))); continue
    status = "PASS" if float(v) <= limit else "OVER"
    print("%s\t%s\t%s\t%s" % (name, v, limit, status))
PY
}

_aphotic_perf_print() {
    local samples="$1" label="$2" d_svram d_card d_hsm d_srss d_sheap d_scpu
    d_svram="$(_aphotic_perf_delta "$_aphotic_perf_s_vram" "$_aphotic_perf_prev_svram" " MiB")"
    d_card="$(_aphotic_perf_delta "${_aphotic_perf_gpu_used:-na}" "$_aphotic_perf_prev_card" " MiB")"
    d_hsm="$(_aphotic_perf_delta "$_aphotic_perf_hypr_sm" "$_aphotic_perf_prev_hsm" "%")"
    d_srss="$(_aphotic_perf_delta "$_aphotic_perf_s_rss" "$_aphotic_perf_prev_srss" " MiB")"
    d_sheap="$(_aphotic_perf_delta "$_aphotic_perf_s_heap" "$_aphotic_perf_prev_sheap" " MiB")"
    d_scpu="$(_aphotic_perf_delta "$_aphotic_perf_s_cpu" "$_aphotic_perf_prev_scpu" "%")"

    printf 'Aphotic perf snapshot %s  (%s samples)\n' "$_aphotic_perf_ts" "$samples"
    [[ -n "$label" ]] && printf '  label: %s\n' "$label"

    local name pid type fb sm s_heap_disp="n/a"
    if [[ -n "$_aphotic_perf_gpu_used" ]]; then
        printf '  GPU: %s MiB used / %s MiB total, util %s%%\n' "$_aphotic_perf_gpu_used" "$_aphotic_perf_gpu_total" "$_aphotic_perf_gpu_util"
        if [[ -n "$_aphotic_perf_procs" ]]; then
            printf '    %-8s %-4s %7s %8s  process\n' "pid" "type" "SM%" "fb MiB"
            while IFS=$'\t' read -r name pid type fb sm; do
                printf '    %-8s %-4s %7s %8s  %s\n' "$pid" "$type" "${sm}%" "$fb" "$name"
            done <<< "$_aphotic_perf_procs"
        else
            printf '    (no GPU processes)\n'
        fi
    else
        printf '  GPU: no NVIDIA data (nvidia-smi missing or no NVIDIA GPU)\n'
    fi

    if [[ -n "$_aphotic_perf_s_pid" ]]; then
        [[ "$_aphotic_perf_s_heap" != "null" && -n "$_aphotic_perf_s_heap" ]] && s_heap_disp="$_aphotic_perf_s_heap"
        printf '  shell qs (pid %s): rss %s MiB, heap %s MiB, cpu %s%%, %s threads\n' \
            "$_aphotic_perf_s_pid" "$_aphotic_perf_s_rss" "$s_heap_disp" "$_aphotic_perf_s_cpu" "$_aphotic_perf_s_threads"
    else
        printf '  shell qs: not running\n'
    fi
    if [[ -n "$_aphotic_perf_h_pid" ]]; then
        printf '  Hyprland (pid %s): rss %s MiB, cpu %s%%\n' \
            "$_aphotic_perf_h_pid" "$_aphotic_perf_h_rss" "$_aphotic_perf_h_cpu"
    else
        printf '  Hyprland: not running\n'
    fi

    local mname mw mh mrate
    if [[ -n "$_aphotic_perf_monitors" ]]; then
        printf '  monitors:'
        while IFS=$'\t' read -r mname mw mh mrate; do
            printf ' %s %sx%s@%s' "$mname" "$mw" "$mh" "$mrate"
        done <<< "$_aphotic_perf_monitors"
        printf '\n'
    else
        printf '  monitors: none (hyprctl unavailable)\n'
    fi

    printf '  vs previous snapshot:\n'
    if [[ "$_aphotic_perf_has_prev" == "1" ]]; then
        printf '    shell VRAM     %s\n' "$d_svram"
        printf '    card VRAM      %s\n' "$d_card"
        printf '    Hyprland SM%%  %s\n' "$d_hsm"
        printf '    shell RSS      %s\n' "$d_srss"
        printf '    shell heap     %s\n' "$d_sheap"
        printf '    shell CPU      %s\n' "$d_scpu"
    else
        printf '    (no previous snapshot)\n'
    fi
}

_aphotic_perf_collect() {
    local samples="$1" label="$2" quiet="${3:-0}"
    local ts shell_pid hypr_pid pmon_file pmon_pid=""
    ts="$(date -Iseconds)"
    shell_pid="$(_aphotic_perf_shell_pid)" || true
    hypr_pid="$(pgrep -x Hyprland 2>/dev/null | head -n1 || true)"

    # pmon runs its own per-second iterations; sample /proc in step with it.
    pmon_file="$(mktemp)"
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi pmon -c "$samples" -s um > "$pmon_file" 2>/dev/null &
        pmon_pid=$!
    fi

    local i s_rss=0 s_ut=0 s_st=0 s_threads=0 fs_ut=0 fs_st=0
    local h_rss=0 h_ut=0 h_st=0 h_threads=0 fh_ut=0 fh_st=0
    local t0 t1 wall hz page
    t0="$(date +%s)"
    hz="$(getconf CLK_TCK 2>/dev/null || echo 100)"; [[ "$hz" =~ ^[0-9]+$ ]] || hz=100
    page="$(getconf PAGE_SIZE 2>/dev/null || echo 4096)"; [[ "$page" =~ ^[0-9]+$ ]] || page=4096

    for ((i = 0; i < samples; i++)); do
        if [[ -n "$shell_pid" ]]; then
            read -r s_rss s_ut s_st s_threads < <(_aphotic_perf_read_stat "$shell_pid") || true
            ((i == 0)) && { fs_ut="$s_ut"; fs_st="$s_st"; }
        fi
        if [[ -n "$hypr_pid" ]]; then
            read -r h_rss h_ut h_st h_threads < <(_aphotic_perf_read_stat "$hypr_pid") || true
            ((i == 0)) && { fh_ut="$h_ut"; fh_st="$h_st"; }
        fi
        ((i < samples - 1)) && sleep "${APHOTIC_PERF_INTERVAL:-1}"
    done
    t1="$(date +%s)"; wall=$((t1 - t0))

    local s_cpu h_cpu s_rss_mib h_rss_mib s_heap="null" h_heap="null"
    s_cpu="$(_aphotic_perf_cpu "$shell_pid" "$fs_ut" "$fs_st" "$s_ut" "$s_st" "$wall")"
    h_cpu="$(_aphotic_perf_cpu "$hypr_pid" "$fh_ut" "$fh_st" "$h_ut" "$h_st" "$wall")"
    s_rss_mib="$(awk -v p="$s_rss" -v sz="$page" 'BEGIN { printf "%.1f", p * sz / 1048576 }')"
    h_rss_mib="$(awk -v p="$h_rss" -v sz="$page" 'BEGIN { printf "%.1f", p * sz / 1048576 }')"
    [[ -n "$shell_pid" ]] && s_heap="$(_aphotic_perf_read_heap "$shell_pid")"
    [[ -n "$hypr_pid" ]] && h_heap="$(_aphotic_perf_read_heap "$hypr_pid")"

    local gpu_used="" gpu_total="" gpu_util="" proc_rows="" card
    if [[ -n "$pmon_pid" ]]; then
        wait "$pmon_pid" 2>/dev/null || true
        proc_rows="$(_aphotic_perf_parse_pmon "$pmon_file")"
        if card="$(_aphotic_perf_card)"; then
            read -r gpu_used gpu_total gpu_util <<<"$card" || true
        fi
    fi
    rm -f "$pmon_file"

    local monitors
    monitors="$(_aphotic_perf_monitors)"

    local s_vram hypr_sm
    if [[ -n "$gpu_used" ]]; then
        s_vram="$(awk -F'\t' '{ if ($1 == "qs" || $1 == "quickshell") s += $4 } END { printf "%.1f", s + 0 }' <<<"$proc_rows")"
        hypr_sm="$(awk -F'\t' '{ if ($1 == "Hyprland" && $5 > m) m = $5 } END { printf "%.1f", m + 0 }' <<<"$proc_rows")"
    else
        s_vram="na"; hypr_sm="na"
    fi

    # Previous snapshot values, read before appending this one.
    local hist p_svram="na" p_card="na" p_hsm="na" p_srss="na" p_sheap="na" p_scpu="na" has_prev=0
    hist="$(_aphotic_perf_hist)"
    if [[ -s "$hist" ]]; then
        IFS=$'\t' read -r p_svram p_card p_hsm p_srss p_sheap p_scpu < <(_aphotic_perf_prev "$hist")
        [[ "$p_svram" != "na" || "$p_srss" != "na" ]] && has_prev=1
    fi

    local pay
    pay="$(mktemp)"
    {
        printf '%s\n' "$proc_rows"
        printf '\n'
        printf '%s\n' "$monitors"
    } > "$pay"

    mkdir -p "$(dirname "$hist")"
    _aphotic_perf_emit "$ts" "${label:-}" \
        "$([ -n "$shell_pid" ] && echo "$s_rss_mib" || echo null)" \
        "$s_heap" \
        "$([ -n "$shell_pid" ] && echo "$s_cpu" || echo null)" \
        "$([ -n "$shell_pid" ] && echo "$s_threads" || echo null)" \
        "$([ -n "$hypr_pid" ] && echo "$h_rss_mib" || echo null)" \
        "$h_heap" \
        "$([ -n "$hypr_pid" ] && echo "$h_cpu" || echo null)" \
        "$([ -n "$hypr_pid" ] && echo "$h_threads" || echo null)" \
        "${gpu_used:-null}" "${gpu_total:-null}" "${gpu_util:-null}" "$pay" >> "$hist"
    rm -f "$pay"

    _aphotic_perf_ts="$ts"
    _aphotic_perf_gpu_used="$gpu_used"
    _aphotic_perf_gpu_total="$gpu_total"
    _aphotic_perf_gpu_util="$gpu_util"
    _aphotic_perf_procs="$proc_rows"
    _aphotic_perf_monitors="$monitors"
    _aphotic_perf_s_vram="$s_vram"
    _aphotic_perf_hypr_sm="$hypr_sm"
    _aphotic_perf_s_rss="$s_rss_mib"
    _aphotic_perf_s_heap="$s_heap"
    _aphotic_perf_s_cpu="$s_cpu"
    _aphotic_perf_s_threads="$s_threads"
    _aphotic_perf_s_pid="${shell_pid:-}"
    _aphotic_perf_h_rss="$h_rss_mib"
    _aphotic_perf_h_cpu="$h_cpu"
    _aphotic_perf_h_pid="${hypr_pid:-}"
    _aphotic_perf_prev_svram="$p_svram"
    _aphotic_perf_prev_card="$p_card"
    _aphotic_perf_prev_hsm="$p_hsm"
    _aphotic_perf_prev_srss="$p_srss"
    _aphotic_perf_prev_sheap="$p_sheap"
    _aphotic_perf_prev_scpu="$p_scpu"
    _aphotic_perf_has_prev="$has_prev"

    [[ "$quiet" -eq 0 ]] && _aphotic_perf_print "$samples" "$label"
    return 0
}

_aphotic_perf_cmd_snapshot() {
    local samples=10 label=""
    while (($#)); do
        case "$1" in
            --samples)
                [[ $# -ge 2 ]] || { aphotic_err "--samples needs a value"; return 1; }
                samples="$2"; shift 2
                ;;
            --label)
                shift; label="${1:-}"; shift || true
                ;;
            -h|--help)
                cat <<'HELP'
Usage: aphotic perf snapshot [--samples N=10] [--label TEXT]

Collect N one-second samples of GPU (nvidia-smi pmon, NVIDIA only), the
Quickshell daemon (qs -c aphotic) and Hyprland, append one JSON line to
$XDG_STATE_HOME/aphotic/perf/history.jsonl and print a table with a delta
vs the previous snapshot. Without a working NVIDIA GPU the snapshot records
"gpu": null and the command still succeeds.
HELP
                return 0
                ;;
            *)
                aphotic_err "unknown snapshot option: $1"
                return 1
                ;;
        esac
    done
    [[ "$samples" =~ ^[0-9]+$ && "$samples" -ge 1 ]] || { aphotic_err "--samples must be a positive integer"; return 1; }
    _aphotic_perf_collect "$samples" "$label"
}

_aphotic_perf_cmd_budget() {
    local from_history=0 arg
    for arg in "$@"; do
        case "$arg" in
            --from-history) from_history=1 ;;
            -h|--help)
                cat <<'HELP'
Usage: aphotic perf budget [--from-history]

Check the shell against Configs/.local/share/aphotic/perf-budget.json (or
the same path under XDG_DATA_HOME). With --from-history the latest snapshot
in history.jsonl is compared; otherwise a fresh snapshot is taken first.
Each budget prints PASS, OVER or SKIP (no data, e.g. no GPU). Exits 1 when
any budget reads OVER.
HELP
                return 0
                ;;
            *)
                aphotic_err "unknown budget option: $arg"
                return 1
                ;;
        esac
    done

    local bfile
    bfile="$(_aphotic_perf_budget_file)"
    if [[ -z "$bfile" ]]; then
        aphotic_err "no perf-budget.json found under \${XDG_DATA_HOME:-~/.local/share}/aphotic/ or \${BIN_DIR}/../share/aphotic/"
        return 1
    fi

    local hist doc ts rows over=0 name val limit status disp docf
    hist="$(_aphotic_perf_hist)"
    if [[ "$from_history" -eq 1 ]]; then
        [[ -s "$hist" ]] || { aphotic_err "no snapshots in ${hist} — run 'aphotic perf snapshot' first"; return 1; }
    else
        _aphotic_perf_collect 10 "" 1
    fi
    doc="$(tail -n 1 "$hist" 2>/dev/null || true)"
    ts="$(printf '%s' "$doc" | python3 -c '
import sys, json
try:
    print(json.load(sys.stdin).get("ts", "-"))
except Exception:
    print("-")
')"
    docf="$(mktemp)"
    printf '%s\n' "$doc" > "$docf"
    rows="$(_aphotic_perf_budget_rows "$bfile" "$docf")"
    rm -f "$docf"

    printf 'Aphotic perf budget check (%s)\n' "$ts"
    while IFS=$'\t' read -r name val limit status; do
        if [[ "$status" == "SKIP" ]]; then
            disp="no data"
        else
            case "$name" in
                shell_vram_mib|shell_vram_inference_mib) disp="$(awk -v v="$val" -v l="$limit" 'BEGIN { printf "%.0f MiB / %.0f MiB", v, l }')" ;;
                idle_gpu_util_pct) disp="$(awk -v v="$val" -v l="$limit" 'BEGIN { printf "%.0f%% / %.0f%%", v, l }')" ;;
                shell_heap_mib) disp="$(awk -v v="$val" -v l="$limit" 'BEGIN { printf "%.0f MiB / %.0f MiB", v, l }')" ;;
                shell_cpu_pct) disp="$(awk -v v="$val" -v l="$limit" 'BEGIN { printf "%.1f%% / %.1f%%", v, l }')" ;;
            esac
        fi
        printf '  %-26s %-22s %s\n' "$name" "$disp" "$status"
        [[ "$status" == "OVER" ]] && over=1
    done <<< "$rows"

    if [[ "$over" -eq 1 ]]; then
        aphotic_err "at least one budget over limit"
        return 1
    fi
    aphotic_ok "all budgets within limits"
    return 0
}

_aphotic_perf_cmd_history() {
    local last=10
    while (($#)); do
        case "$1" in
            --last)
                [[ $# -ge 2 ]] || { aphotic_err "--last needs a value"; return 1; }
                last="$2"; shift 2
                ;;
            -h|--help)
                cat <<'HELP'
Usage: aphotic perf history [--last N=10]

Print a table of the N most recent snapshots from history.jsonl.
HELP
                return 0
                ;;
            *)
                aphotic_err "unknown history option: $1"
                return 1
                ;;
        esac
    done
    [[ "$last" =~ ^[0-9]+$ && "$last" -ge 1 ]] || { aphotic_err "--last must be a positive integer"; return 1; }

    local hist
    hist="$(_aphotic_perf_hist)"
    [[ -s "$hist" ]] || { aphotic_log "no history yet — run 'aphotic perf snapshot' first"; return 0; }
    printf '  %-26s %-14s %9s %8s %12s %9s\n' "ts" "label" "card used" "gpu util" "shell rss" "shell cpu"
    tail -n "$last" "$hist" | python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    g = d.get("gpu")
    used = "%.0f MiB" % g["card_used_mib"] if isinstance(g, dict) and g.get("card_used_mib") is not None else "-"
    util = "%.0f%%" % g["card_util"] if isinstance(g, dict) and g.get("card_util") is not None else "-"
    sh = d.get("shell")
    rss = "%.1f MiB" % sh["rss_mib"] if isinstance(sh, dict) and sh.get("rss_mib") is not None else "-"
    cpu = "%.1f%%" % sh["cpu_avg"] if isinstance(sh, dict) and sh.get("cpu_avg") is not None else "-"
    print("%s\t%s\t%s\t%s\t%s\t%s" % (d.get("ts", "?"), d.get("label") or "-", used, util, rss, cpu))
' | while IFS=$'\t' read -r ts label used util rss cpu; do
        printf '  %-26s %-14s %9s %8s %12s %9s\n' "$ts" "$label" "$used" "$util" "$rss" "$cpu"
    done
}

aphotic_cmd_perf() {
    local sub="${1:-}"
    shift || true
    case "$sub" in
        snapshot) _aphotic_perf_cmd_snapshot "$@" ;;
        budget)   _aphotic_perf_cmd_budget "$@" ;;
        history)  _aphotic_perf_cmd_history "$@" ;;
        ""|-h|--help)
            cat <<'HELP'
Usage: aphotic perf <snapshot|budget|history> [args]

  snapshot [--samples N=10] [--label TEXT]
    Collect N one-second samples of GPU (nvidia-smi pmon, NVIDIA only),
    the Quickshell daemon and Hyprland, append one JSON line to
    perf/history.jsonl under $XDG_STATE_HOME and print a table with a
    delta vs the previous snapshot.

  budget [--from-history]
    PASS/OVER check of the latest snapshot (or take a fresh one) against
    perf-budget.json. Budgets with no data print SKIP. Exits 1 when any
    budget is over the limit.

  history [--last N=10]
    Table of the most recent snapshots.

GPU data is best-effort: without a working NVIDIA card or nvidia-smi the
snapshot records "gpu": null and never fails.
HELP
            ;;
        *)
            aphotic_err "unknown perf subcommand: $sub"
            echo "Run 'aphotic perf --help' for usage." >&2
            return 1
            ;;
    esac
}