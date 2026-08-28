#!/usr/bin/env bash
# Shared stat persistence for `aphotic play <game>` -- one small JSON
# file (~/.local/state/aphotic/game-scores.json), one top-level object
# per game, arbitrary keys underneath. Sourced once by cmd_play.sh before
# dispatching to any individual game, so every game shares the same file
# and I/O logic instead of each reinventing it.
#
# Two generic primitives (_aphotic_play_stat_get/_set) cover any game's
# needs -- a numeric high score (snake), fewest attempts (guess), a
# win/loss tally (hangman) -- without baking in "higher is better" or
# any other single game's semantics. _aphotic_play_best_score/
# _aphotic_play_record_score are a thin "higher wins" convenience layer
# on top, since that's the single most common case (snake).

APHOTIC_PLAY_SCORES_FILE="${APHOTIC_STATE_HOME}/game-scores.json"

# Prints the raw value at .<game>.<key>, or $3 (default) if unset/missing
# jq/malformed file. Numbers only -- every stat this file tracks is one.
_aphotic_play_stat_get() {
    # ${3-0}, not ${3:-0} -- callers (like _aphotic_play_record_low) pass
    # "" on purpose to mean "no default, tell me if nothing's recorded
    # yet". :- treats an explicitly-empty $3 the same as a missing one
    # and silently substitutes 0 anyway, which broke exactly that check.
    local game="$1" key="$2" default="${3-0}"
    command -v jq >/dev/null 2>&1 || { echo "$default"; return 0; }
    [[ -f "$APHOTIC_PLAY_SCORES_FILE" ]] || { echo "$default"; return 0; }
    jq -r --arg g "$game" --arg k "$key" --arg d "$default" \
        '(.[$g][$k] // ($d | tonumber))' "$APHOTIC_PLAY_SCORES_FILE" 2>/dev/null || echo "$default"
}

# Sets .<game>.<key> = $3. Best-effort -- silently no-ops without jq
# rather than blocking play on a missing dependency.
_aphotic_play_stat_set() {
    local game="$1" key="$2" value="$3" tmp
    command -v jq >/dev/null 2>&1 || return 0
    mkdir -p "$(dirname "$APHOTIC_PLAY_SCORES_FILE")"
    tmp="$(mktemp)"
    if [[ -f "$APHOTIC_PLAY_SCORES_FILE" ]]; then
        jq --arg g "$game" --arg k "$key" --argjson v "$value" '.[$g][$k] = $v' \
            "$APHOTIC_PLAY_SCORES_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$APHOTIC_PLAY_SCORES_FILE"
    else
        jq -n --arg g "$game" --arg k "$key" --argjson v "$value" '{($g): {($k): $v}}' > "$tmp" && mv "$tmp" "$APHOTIC_PLAY_SCORES_FILE"
    fi
}

# Best (highest) score recorded for $1, default 0.
_aphotic_play_best_score() {
    _aphotic_play_stat_get "$1" "bestScore" 0
}

# Records $2 as $1's best score if it beats the current one. Exit 0 =
# new best just recorded, exit 1 = it wasn't (or jq is missing) -- callers
# use the exit status to decide whether to print "New best!".
_aphotic_play_record_score() {
    local game="$1" score="$2" current
    [[ "$score" =~ ^[0-9]+$ ]] || return 1
    current="$(_aphotic_play_best_score "$game")"
    (( score <= current )) && return 1
    _aphotic_play_stat_set "$game" "bestScore" "$score"
}

# Increments $1's "played" count, and "wins" too if $2 is truthy (any of
# true/1/yes/win). Used by games with no real numeric score, just a
# win/loss outcome (hangman).
_aphotic_play_record_result() {
    local game="$1" won="$2" played wins
    played="$(_aphotic_play_stat_get "$game" "played" 0)"
    wins="$(_aphotic_play_stat_get "$game" "wins" 0)"
    _aphotic_play_stat_set "$game" "played" "$((played + 1))"
    case "$won" in
        true|1|yes|win) _aphotic_play_stat_set "$game" "wins" "$((wins + 1))" ;;
    esac
}

# Records $2 attempts as $1's best (fewest) if it beats the current
# record (or none is set yet). Exit 0 = new best just recorded. Used by
# games where lower is better (guess).
_aphotic_play_record_low() {
    local game="$1" key="$2" value="$3" current
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    current="$(_aphotic_play_stat_get "$game" "$key" "")"
    if [[ -n "$current" ]] && (( value >= current )); then
        return 1
    fi
    _aphotic_play_stat_set "$game" "$key" "$value"
}
