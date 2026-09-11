#!/usr/bin/env bash
# tests/test_plugin_index_scale.sh
# The catalogue path has to cost the same whether the index holds nine
# plugins or two thousand. It used to fork _aphotic_plugin_entry_verdict
# plus a rewriting jq per entry -- four processes each -- so the work grew
# linearly with the catalogue and Settings -> Plugins waited on all of it
# before it could draw anything.
#
# Three things this guards:
#   - annotation is one jq pass, whatever the index size
#   - the jq verdict rule still agrees with _aphotic_plugin_host_verdict,
#     which remains the single answer for an on-disk manifest
#   - a real-sized index does not blow ARG_MAX. Passing the catalogue as a
#     --argjson value did, and only at size: it worked fine on nine.
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

source "$ROOT/Configs/.local/lib/aphotic/globalcontrol.sh"
source "$ROOT/Configs/.local/lib/aphotic/commands/cmd_plugin.sh"

# --- the jq rule agrees with the bash rule, case for case ---------------
#
# Each case is an entry plus the verdict _aphotic_plugin_host_verdict
# gives it. Kept explicit rather than generated: the interesting part is
# the boundaries (ui-surface never counts toward "working", an unhosted
# surface next to a hosted one is partial not inert, capabilities are
# reported before surfaces, surfaces are deduplicated and sorted).
check() {
    local entry="$1" got want
    want="$(_aphotic_plugin_host_verdict \
        "$(jq -r '(.capabilities // [])[]' <<<"$entry")" \
        "$(jq -r '((.ui.surfaces // [])[].surface) // empty' <<<"$entry" | sort -u)")"
    got="$(_aphotic_plugin_annotate_remote_json "{\"plugins\":[$entry]}" \
        | jq -r '.[0].host_support | if .verdict == "ok" then "ok" else .verdict + ":" + .unhosted end')"
    [[ "$want" == "$got" ]] || fail "verdict mismatch for $entry -- bash said '$want', jq said '$got'"
}

check '{"name":"a","capabilities":["theme-hook"]}'
check '{"name":"b","capabilities":["ui-surface"],"ui":{"surfaces":[{"surface":"dashboard"}]}}'
check '{"name":"c","capabilities":["agent-event-hook"]}'
check '{"name":"d","capabilities":["theme-hook","profile-hook","agent-event-hook"]}'
check '{"name":"e","capabilities":["ui-surface"],"ui":{"surfaces":[{"surface":"quantum"},{"surface":"dashboard"},{"surface":"quantum"}]}}'
check '{"name":"f","capabilities":[]}'
check '{"name":"g"}'
check '{"name":"h","capabilities":["ui-surface"],"ui":{"surfaces":[{"surface":"zeta"},{"surface":"alpha"}]}}'
check '{"name":"i","capabilities":["profile","cli"],"ui":{"surfaces":[{"surface":"notch"}]}}'
check '{"name":"j","capabilities":["ui-surface","bogus"],"ui":{"surfaces":[{"surface":"dashboard"}]}}'

# --- a 2000-entry index annotates in one pass --------------------------

BIG="$TESTHOME/big-index.json"
jq -n '{plugins: [range(2000) | {
    name: "p\(.)",
    display_name: "Plugin \(.)",
    version: "1.0.0",
    category: (["dev","ai","gaming","security","theming"][. % 5]),
    description: "synthetic entry \(.)",
    capabilities: (if . % 3 == 0 then ["ui-surface"] else ["theme-hook"] end),
    ui: (if . % 3 == 0 then {surfaces: [{surface: (if . % 6 == 0 then "dashboard" else "quantum" end)}]} else null end)
}]}' > "$BIG"

annotated="$(_aphotic_plugin_annotate_remote_json "$(cat "$BIG")")"
[[ "$(jq 'length' <<<"$annotated")" -eq 2000 ]] \
    || fail "expected all 2000 entries back from one annotation pass, got $(jq 'length' <<<"$annotated")"
[[ "$(jq '[.[] | select(.host_support == null)] | length' <<<"$annotated")" -eq 0 ]] \
    || fail "every entry must carry a host_support verdict"
[[ "$(jq '[.[] | select(.host_support.verdict == "inert")] | length' <<<"$annotated")" -gt 0 ]] \
    || fail "expected the unhosted-surface entries to come back inert"

# One jq for the annotation itself. Counted by tracing the function with a
# stub on PATH rather than timing it, so this stays a statement about the
# shape of the code and not about how fast the machine is.
STUBS="$TESTHOME/stubs"
mkdir -p "$STUBS"
cat > "$STUBS/jq" <<EOF
#!/usr/bin/env bash
echo call >> "$TESTHOME/jq-calls"
exec /usr/bin/env -i PATH=/usr/bin:/bin $(command -v jq) "\$@"
EOF
chmod +x "$STUBS/jq"
: > "$TESTHOME/jq-calls"
PATH="$STUBS:$PATH" _aphotic_plugin_annotate_remote_json "$(cat "$BIG")" >/dev/null
calls="$(wc -l < "$TESTHOME/jq-calls")"
[[ "$calls" -le 2 ]] \
    || fail "expected annotation to be one jq pass regardless of index size, saw $calls calls for 2000 entries"

# --- the whole catalogue survives being handed around ------------------
#
# The ARG_MAX regression: this fetches, annotates and writes the cache,
# and every step has to move the catalogue through a pipe or a file rather
# than argv.
export APHOTIC_PLUGINS_INDEX_URL="file://$BIG"
export APHOTIC_PLUGINS_SECURITY_INDEX_URL="file://$BIG"
out="$(_aphotic_plugin_index_cached true 2>"$TESTHOME/err")"
[[ -s "$TESTHOME/err" ]] && fail "index fetch wrote to stderr: $(cat "$TESTHOME/err")"
[[ "$(jq 'length' <<<"$out")" -eq 2000 ]] \
    || fail "expected 2000 entries through the caching path, got $(jq 'length' <<<"$out")"

cache="$(_aphotic_plugin_index_cache_file)"
[[ -s "$cache" ]] || fail "expected the catalogue to be cached to disk"
[[ "$(jq -r '.plugins | length' "$cache")" -eq 2000 ]] \
    || fail "expected the cache file to hold the whole catalogue"
[[ "$(jq -r 'has("trusted")' "$cache")" == "true" ]] \
    || fail "expected the cache file to carry the security-index trust flag"

# A second call inside the TTL is served from the file, not refetched.
rm -f "$BIG"
out2="$(_aphotic_plugin_index_cached false)"
[[ "$(jq 'length' <<<"$out2")" -eq 2000 ]] \
    || fail "expected a cached catalogue to be served without refetching"

echo "PASS: the plugin catalogue annotates in one pass and scales to a 2000-entry index"
