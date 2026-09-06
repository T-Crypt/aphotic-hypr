#!/usr/bin/env bash
# aphotic sync — pull the dots repo, re-deploy the shell config, refresh
# plugins. What Settings -> About's update button runs.
#
# This is the config-only half of an update and nothing else. It never
# installs a package, because installing packages needs sudo and a
# resolved profile, which is install.sh's job. What it does instead is
# say when packages are missing, so a release that added one to a profile
# stops being an invisible half-update: the shell config lands, the
# feature needing the new package does not, and until now nothing said
# so.
# @cmd: sync
# @cmd.desc: Config-only update: re-deploy config, refresh plugins, report missing packages
# @cmd.group: LIFECYCLE
# @cmd.opt: --check           | Report only. Nothing is pulled, deployed or restarted
# @cmd.opt: --json            | Machine-readable report, for Settings -> About
# @cmd.opt: --no-pull         | Skip the git pull, sync whatever is checked out

# Which packages the installed profile and layers say should be present,
# minus what pacman actually has. tomllib rather than the awk reader in
# globalcontrol.sh: that one takes a single-line array, and a layer
# bundle's members have to be followed, which is a second parse either
# way.
_aphotic_sync_missing_packages() {
    local dots="$1"
    local cfg="${dots}/aphotic.toml"

    [[ -f "$cfg" ]] || return 0
    command -v pacman >/dev/null 2>&1 || return 0

    "${PYTHON_BIN:-python3}" - "$dots" "$cfg" <<'PY'
import sys, tomllib, os, subprocess

dots, cfg = sys.argv[1], sys.argv[2]

try:
    out = subprocess.run(["pacman", "-Qq"], capture_output=True, text=True, timeout=30)
    installed = {line.strip() for line in out.stdout.splitlines() if line.strip()}
except Exception:
    sys.exit(0)
if not installed:
    sys.exit(0)

def load(path):
    try:
        with open(path, "rb") as fh:
            return tomllib.load(fh)
    except Exception:
        return {}

conf = load(cfg).get("install", {})
profile = conf.get("profile") or "full"
layers = list(conf.get("layers") or [])

want = []
files = [os.path.join(dots, "profiles", "base", f"{profile}.toml")]

# A layer may be a bundle naming other layers; follow one level, which is
# as deep as profiles/layers goes.
seen, queue = set(), list(layers)
while queue:
    name = queue.pop(0)
    if name in seen:
        continue
    seen.add(name)
    path = os.path.join(dots, "profiles", "layers", f"{name}.toml")
    if not os.path.isfile(path):
        continue
    files.append(path)
    queue.extend(load(path).get("meta", {}).get("bundles", []) or [])

for path in files:
    for value in (load(path).get("packages") or {}).values():
        if isinstance(value, list):
            want.extend(v for v in value if isinstance(v, str))

# A package can be present under a different name (a -git variant, a
# provider), and pacman -Qq lists real names only. Anything not matched
# exactly is reported, and the wording downstream stays advisory.
missing = sorted({p for p in want if p not in installed})
for p in missing:
    print(p)
PY
}

_aphotic_sync_outdated_plugins() {
    local repo="${APHOTIC_PLUGINS_REPO:-$HOME/aphotic-plugins}"
    [[ -f "${repo}/index.json" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    source "${COMMANDS_DIR}/cmd_plugin.sh"
    local installed
    installed="$(aphotic_cmd_plugin list --json 2>/dev/null)" || return 0
    [[ -n "$installed" ]] || return 0

    jq -rn --argjson have "$installed" --slurpfile want "${repo}/index.json" '
        (($want[0] // {}) .plugins // []) as $remote
        | $have[]
        | . as $p
        | first($remote[] | select(.name == $p.name) | .version) as $rv
        | select($rv != null and $rv != $p.version)
        | "\($p.name) \($p.version) \($rv)"
    ' 2>/dev/null
}

aphotic_cmd_sync() {
    local check=0 json=0 pull=1
    for arg in "$@"; do
        case "$arg" in
            --check) check=1 ;;
            --json) json=1 ;;
            --no-pull) pull=0 ;;
            -h|--help)
                cat <<'HELP'
Usage: aphotic sync [--check] [--json] [--no-pull]

Config-only update. Pulls the dots repo, re-deploys the shell config
through install.sh --config-only, then refreshes every installed plugin.
It installs no packages: that needs sudo and a resolved profile, which is
install.sh's job.

  --check      Report only. Nothing is pulled, deployed or restarted
  --json       Machine-readable report, for Settings -> About
  --no-pull    Sync whatever is checked out, without pulling first

Deploying the config restarts the shell.
HELP
                return 0
                ;;
            *) aphotic_warn "sync: ignoring unknown flag '$arg'" ;;
        esac
    done

    local dots="${APHOTIC_DOTS_DIR}"
    if [[ ! -d "${dots}/.git" ]]; then
        aphotic_err "${dots} is not a git repo"
        return 1
    fi

    if [[ "$check" -eq 1 ]]; then
        local missing outdated
        missing="$(_aphotic_sync_missing_packages "$dots")"
        outdated="$(_aphotic_sync_outdated_plugins)"

        if [[ "$json" -eq 1 ]]; then
            local pkg_json="[]" plug_json="[]"
            if [[ -n "$missing" ]]; then
                pkg_json="$(printf '%s\n' "$missing" | jq -R . | jq -sc .)"
            fi
            if [[ -n "$outdated" ]]; then
                plug_json="$(printf '%s\n' "$outdated" | jq -Rc 'split(" ") | {name: .[0], from: .[1], to: .[2]}' | jq -sc .)"
            fi
            jq -nc \
                --arg version "$APHOTIC_VERSION" \
                --argjson packages "$pkg_json" \
                --argjson plugins "$plug_json" \
                '{version: $version, missingPackages: $packages, outdatedPlugins: $plugins}'
            return 0
        fi

        if [[ -n "$missing" ]]; then
            local count
            count="$(printf '%s\n' "$missing" | wc -l)"
            aphotic_warn "${count} package(s) your profile asks for are not installed: $(printf '%s' "$missing" | tr '\n' ' ')"
            aphotic_log "run ./install.sh from ${dots} to add them"
        else
            aphotic_ok "every package your profile asks for is installed"
        fi
        [[ -n "$outdated" ]] && aphotic_log "plugin updates available:
${outdated}"
        return 0
    fi

    # Deploying restarts the shell, which is the process the Settings pane
    # asking for this runs in -- so the pane cannot watch this to the end
    # and read the result off a pipe. Everything below is written to a log
    # and a small status file instead, and About reads those back once the
    # shell is up again. That is also why the status file is written on
    # every exit path: a run that dies half way still has to leave
    # something the pane can report rather than a stale success.
    mkdir -p "$APHOTIC_STATE_HOME"
    local log="${APHOTIC_STATE_HOME}/last-sync.log"
    local status="${APHOTIC_STATE_HOME}/last-sync.json"

    : > "$log"
    _aphotic_sync_run "$dots" "$pull" 2>&1 | tee -a "$log"
    local rc="${PIPESTATUS[0]}"

    local missing result="ok"
    missing="$(_aphotic_sync_missing_packages "$dots")"
    [[ "$rc" -eq 0 ]] || result="failed"
    _aphotic_sync_write_status "$status" "$result" "$missing"

    return "$rc"
}

# What About reads back after the restart. Written on every exit path, so
# a run that failed half way leaves a failure rather than a stale success.
_aphotic_sync_write_status() {
    local path="$1" result="$2" missing_list="$3"
    local pkg_json="[]"
    [[ -n "$missing_list" ]] && pkg_json="$(printf '%s\n' "$missing_list" | jq -R . | jq -sc .)"
    jq -nc \
        --arg at "$(date -Is)" \
        --arg result "$result" \
        --arg version "$APHOTIC_VERSION" \
        --argjson packages "$pkg_json" \
        '{at: $at, result: $result, version: $version, missingPackages: $packages}' \
        > "$path" 2>/dev/null || true
}

# The body of an apply, split out so the caller can tee it whole.
_aphotic_sync_run() {
    local dots="$1" pull="$2"

    if [[ "$pull" -eq 1 ]]; then
        aphotic_log "pulling ${dots}..."
        git -C "$dots" pull --ff-only || {
            aphotic_err "pull failed, nothing deployed"
            return 1
        }
    fi

    # Packages are read after the pull, so the answer describes the
    # release being deployed rather than the one that was running.
    local missing
    missing="$(_aphotic_sync_missing_packages "$dots")"

    aphotic_log "deploying config (install.sh --config-only)..."
    if ! (cd "$dots" && ./install.sh --config-only); then
        aphotic_err "config sync failed"
        return 1
    fi

    aphotic_log "refreshing plugins..."
    source "${COMMANDS_DIR}/cmd_plugin.sh"
    aphotic_cmd_plugin update --all || aphotic_warn "one or more plugins did not update"

    if [[ -n "$missing" ]]; then
        aphotic_warn "this release wants packages you do not have:"
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] && printf '  %s\n' "$pkg"
        done <<<"$missing"
        aphotic_warn "the config is deployed, but anything needing those stays dark until you run ./install.sh from ${dots}"
    fi

    aphotic_ok "sync complete"
}
