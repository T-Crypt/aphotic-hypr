#!/usr/bin/env bash
# tests/test_plugin_host_gate.sh
# The catalogue repo ships on its own cadence, so it can offer a plugin
# whose only surface this shell has no host for. Before this gate that
# install succeeded and rendered nothing. Covers the verdict rule, the
# manifest section scan, and the install refusal.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TESTHOME=$(mktemp -d)
trap 'rm -rf "$TESTHOME"' EXIT

export HOME="$TESTHOME"
export XDG_CONFIG_HOME="$TESTHOME/.config"
export XDG_STATE_HOME="$TESTHOME/.local/state"
export XDG_DATA_HOME="$TESTHOME/.local/share"
export APHOTIC_DOTS_DIR="$ROOT"

COMMANDS_DIR="$ROOT/Configs/.local/lib/aphotic/commands"
source "$ROOT/Configs/.local/lib/aphotic/globalcontrol.sh"
source "$COMMANDS_DIR/cmd_plugin.sh"

# --- _aphotic_plugin_in_list: the grep -w trap ------------------------
# `grep -w profile` matches "profile-hook", which would have read an
# unhosted capability as hosted. This is the regression that check exists
# for, so it is asserted directly rather than only through a verdict.
_aphotic_plugin_in_list "theme-hook" "$APHOTIC_PLUGIN_HOSTED_CAPABILITIES" \
    || fail "expected theme-hook to be hosted"
_aphotic_plugin_in_list "profile" "profile-hook agent-event-hook" \
    && fail "expected 'profile' NOT to match inside 'profile-hook'"

# --- verdicts ---------------------------------------------------------

v="$(_aphotic_plugin_host_verdict "harness-hook" "")"
[[ "$v" == "ok" ]] || fail "hook-only plugin should be ok, got '$v'"

# Every surface kind and capability this build hosts, asserted positively.
# The gate's whole failure mode is a host that exists while its token was
# never added to the list, so each one is checked rather than inferred.
for s in dashboard notch settings; do
    v="$(_aphotic_plugin_host_verdict "ui-surface" "$s")"
    [[ "$v" == "ok" ]] || fail "'$s' is hosted by this build but the gate says '$v'"
done
for c in profile cli theme-hook project-hook workspace-hook harness-hook; do
    v="$(_aphotic_plugin_host_verdict "$c" "")"
    [[ "$v" == "ok" ]] || fail "'$c' is hosted by this build but the gate says '$v'"
done

# ui-surface alone never counts as working -- the surfaces decide. `bar`
# stands in for the next surface kind to be added: unknown tokens are the
# permanent case this gate exists for, so the test uses one rather than a
# kind that stops being unhosted the moment its host lands.
v="$(_aphotic_plugin_host_verdict "ui-surface" "bar")"
[[ "$v" == inert:* ]] || fail "bar-only plugin should be inert, got '$v'"
[[ "$v" == *"bar surface"* ]] || fail "verdict should name the bar surface, got '$v'"

# The case a blanket hide would get wrong: a dashboard tab that works
# alongside a surface kind that does not exist here.
v="$(_aphotic_plugin_host_verdict "ui-surface" "bar
dashboard")"
[[ "$v" == partial:* ]] || fail "dashboard+bar plugin should be partial, got '$v'"
[[ "$v" != *"dashboard"* ]] || fail "partial verdict should not name the hosted dashboard surface, got '$v'"

v="$(_aphotic_plugin_host_verdict "agent-event-hook" "")"
[[ "$v" == inert:* ]] || fail "agent-event-hook plugin should be inert, got '$v'"

# openrgb's real shape: one hosted hook, two that no branch fires yet.
v="$(_aphotic_plugin_host_verdict "theme-hook
profile-hook
agent-event-hook" "")"
[[ "$v" == partial:* ]] || fail "openrgb-shaped plugin should be partial, got '$v'"

# --- manifest section scan -------------------------------------------

MANIFEST="$TESTHOME/plugin.toml"
cat > "$MANIFEST" <<'EOF'
[plugin]
name = "scratch"
capabilities = ["ui-surface"]

[ui.dashboard_tab]
id = "a"

[ui.settings_pane]
id = "b"
parent = "ai"

[ui.notch_tile]
id = "c"
EOF

got="$(_aphotic_plugin_manifest_surfaces "$MANIFEST" | tr '\n' ' ')"
[[ "$got" == "dashboard notch settings " ]] \
    || fail "expected normalized 'dashboard notch settings ', got '$got'"

# A v1 manifest with no [ui] sections at all must scan clean, not error.
printf '[plugin]\nname = "old"\n' > "$TESTHOME/old.toml"
[[ -z "$(_aphotic_plugin_manifest_surfaces "$TESTHOME/old.toml")" ]] \
    || fail "expected no surfaces from a manifest with no [ui] sections"

# --- install refusal --------------------------------------------------

export APHOTIC_PLUGINS_REPO="$TESTHOME/repo"
mkdir -p "$APHOTIC_PLUGINS_REPO/inert-plug/qml"
cat > "$APHOTIC_PLUGINS_REPO/inert-plug/plugin.toml" <<'EOF'
[plugin]
name = "inert-plug"
display_name = "Inert"
version = "1.0.0"
capabilities = ["ui-surface"]

[ui.bar]
id = "inert"
component = "qml/Bar.qml"
EOF
echo "// placeholder" > "$APHOTIC_PLUGINS_REPO/inert-plug/qml/Bar.qml"

# _aphotic_plugin_sync_repo would try to git-pull a directory that is not
# a checkout; the gate under test runs after it, so stub it out.
_aphotic_plugin_sync_repo() { return 0; }

if _aphotic_plugin_install "inert-plug" "false" >/dev/null 2>&1; then
    fail "expected install of a fully-unhosted plugin to be refused"
fi
[[ -e "$(_aphotic_plugin_dir inert-plug)" ]] \
    && fail "a refused install must not leave the plugin on disk"

# The partial case still installs -- refusing it would remove a working
# dashboard tab.
mkdir -p "$APHOTIC_PLUGINS_REPO/partial-plug/qml"
cat > "$APHOTIC_PLUGINS_REPO/partial-plug/plugin.toml" <<'EOF'
[plugin]
name = "partial-plug"
display_name = "Partial"
version = "1.0.0"
capabilities = ["ui-surface"]

[ui.dashboard_tab]
id = "partial"
component = "qml/Tab.qml"

[ui.bar]
id = "partial"
component = "qml/Bar.qml"
EOF
echo "// placeholder" > "$APHOTIC_PLUGINS_REPO/partial-plug/qml/Tab.qml"
echo "// placeholder" > "$APHOTIC_PLUGINS_REPO/partial-plug/qml/Bar.qml"

_aphotic_plugin_install "partial-plug" "false" >/dev/null 2>&1 \
    || fail "expected a partially-hosted plugin to still install"
[[ -d "$(_aphotic_plugin_dir partial-plug)" ]] \
    || fail "expected partial-plug on disk after install"

# --- catalogue annotation --------------------------------------------

# The shapes the published catalogue actually ships. Every one of the
# first three was inert against the pre-merge gate, which is what this
# build adding notch/settings/profile/cli hosts is for; the last two are
# the cases that must still be caught.
annotated="$(_aphotic_plugin_annotate_remote_json '{"plugins":[
  {"name":"tab-and-pane","capabilities":["ui-surface"],
   "ui":{"surfaces":[{"surface":"dashboard"},{"surface":"settings"}]}},
  {"name":"pane-only","capabilities":["ui-surface"],
   "ui":{"surfaces":[{"surface":"settings"}]}},
  {"name":"profile-only","capabilities":["profile"],"ui":{"surfaces":[]}},
  {"name":"unfired-hooks","capabilities":["theme-hook","agent-event-hook"],
   "ui":{"surfaces":[]}},
  {"name":"future-kind","capabilities":["ui-surface"],
   "ui":{"surfaces":[{"surface":"bar"}]}},
  {"name":"hook-only","capabilities":["harness-hook"],"ui":{"surfaces":[]}}
]}')"

check_verdict() {
    local n="$1" want="$2" got
    got="$(jq -r --arg n "$n" '.[] | select(.name == $n) | .host_support.verdict' <<<"$annotated")"
    [[ "$got" == "$want" ]] || fail "catalogue verdict for ${n}: expected ${want}, got '${got}'"
}
check_verdict tab-and-pane  ok
check_verdict pane-only     ok
check_verdict profile-only  ok
check_verdict unfired-hooks partial
check_verdict future-kind   inert
check_verdict hook-only     ok

echo "PASS: plugin host gate (verdict rule, manifest surface scan, install refusal, catalogue annotation)"
