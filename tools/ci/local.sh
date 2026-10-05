#!/usr/bin/env bash
# tools/ci/local.sh
# Run the required CI checks the way GitHub runs them: in a fresh shallow,
# detached checkout with no origin/* refs, no gitignored files, a throwaway
# HOME and no desktop session. Prints one line per check and only the failing
# output; the full log path is printed at the end.
#
#   tools/ci/local.sh                 every check, CI-shaped checkout
#   tools/ci/local.sh --here          run in this working tree (faster, less faithful)
#   tools/ci/local.sh --only sh       syntax | sh | py | shellcheck | packages
#   tools/ci/local.sh --test tests/test_docs_tools.sh
#   tools/ci/local.sh --test tests/test_merge.py
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REMOTE="https://github.com/T-Crypt/aphotic-hypr.git"
MAX_LINES=40

here=0
only=""
single=""
while (($#)); do
  case "$1" in
    --here) here=1 ;;
    --only) only="${2:?--only needs syntax|sh|py|shellcheck|packages}"; shift ;;
    --test) single="${2:?--test needs a file under tests/}"; shift ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aphotic-ci.XXXXXX")"
LOG="$WORK/ci.log"
: > "$LOG"
# Keep only the log once the run ends.
trap 'rm -rf "$WORK/checkout" "$WORK/home" "$WORK/index"' EXIT

if ((here)); then
  TREE="$ROOT"
else
  # Snapshot the working tree, including uncommitted and untracked
  # (non-ignored) files, without touching the real index or the stash.
  # A failed snapshot must stop the run: fetching an empty sha falls back to
  # the old HEAD and reports green for code that never ran.
  export GIT_INDEX_FILE="$WORK/index"
  sha=""
  if git -C "$ROOT" read-tree HEAD 2>>"$LOG" && git -C "$ROOT" add -A 2>>"$LOG" \
      && tree="$(git -C "$ROOT" write-tree 2>>"$LOG")"; then
    sha="$(git -C "$ROOT" -c user.name=ci -c user.email=ci@localhost \
      commit-tree "$tree" -p HEAD -m "ci-local snapshot" 2>>"$LOG")"
  fi
  unset GIT_INDEX_FILE
  if [[ -z "$sha" ]]; then
    echo "could not snapshot the working tree; see $LOG" >&2
    exit 2
  fi

  TREE="$WORK/checkout"
  git init -q "$TREE"
  git -C "$TREE" remote add origin "$REMOTE"
  if ! git -C "$TREE" fetch -q --no-tags --depth=1 "file://$ROOT" "$sha" 2>>"$LOG" \
      || ! git -C "$TREE" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD 2>>"$LOG"; then
    echo "could not build the CI checkout; see $LOG" >&2
    exit 2
  fi
fi

HOME_DIR="$WORK/home"
mkdir -p "$HOME_DIR"
# The runner has no desktop session, a clean HOME and no git identity.
# git network access is blocked:
# a fetch on the runner can time out, so a test that only passes when one
# succeeds fails there at random.
in_ci() {
  (cd "$TREE" && env -i \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/bin:/bin" \
    HOME="$HOME_DIR" LANG=C.UTF-8 CI=true GITHUB_ACTIONS=true \
    GIT_ALLOW_PROTOCOL=file GIT_CONFIG_NOSYSTEM=1 \
    ${GH_TOKEN:+GH_TOKEN="$GH_TOKEN"} \
    "$@")
}

failed=0
report() {  # report NAME STATUS [required|advisory]
  local kind="${3:-required}"
  if [[ "$2" == 0 ]]; then
    printf 'PASS  %s\n' "$1"
  elif [[ "$kind" == advisory ]]; then
    printf 'WARN  %s (advisory, does not block merge)\n' "$1"
  else
    printf 'FAIL  %s\n' "$1"
    failed=1
  fi
}

# Print one failing block, capped so a model reads the error and not the noise.
show() {
  local text="$1" n
  n="$(wc -l <<<"$text")"
  if ((n > MAX_LINES)); then
    printf '      ... %d earlier lines in %s\n' "$((n - MAX_LINES))" "$LOG"
    tail -n "$MAX_LINES" <<<"$text" | sed 's/^/      /'
  else
    sed 's/^/      /' <<<"$text"
  fi
}

run_syntax() {
  local out status=0
  out="$(in_ci bash -c '
    fail=0
    while IFS= read -r -d "" f; do
      bash -n "$f" 2>&1 || { echo "SYNTAX ERROR: $f"; fail=1; }
    done < <(find . -name "*.sh" -not -path "./.git/*" -print0)
    bash -n Configs/.local/bin/aphotic 2>&1 || { echo "SYNTAX ERROR: Configs/.local/bin/aphotic"; fail=1; }
    exit "$fail"')" || status=$?
  printf '=== bash-syntax\n%s\n' "$out" >>"$LOG"
  report "bash-syntax" "$status"
  ((status)) && show "$out"
}

run_sh_one() {  # prints nothing on success, the test's own output on failure
  local f="$1" out status=0
  out="$(in_ci bash "$f" 2>&1)" || status=$?
  printf '=== %s (exit %d)\n%s\n' "$f" "$status" "$out" >>"$LOG"
  if ((status)); then
    printf 'FAIL  test: %s\n' "$f"
    show "$out"
    printf '      rerun: tools/ci/local.sh --test %s\n' "$f"
    return 1
  fi
}

run_sh() {
  local f status=0 count=0
  for f in "$TREE"/tests/test_*.sh; do
    f="tests/${f##*/}"
    count=$((count + 1))
    run_sh_one "$f" || status=1
  done
  ((status)) && failed=1
  ((status)) || printf 'PASS  test: %d bash test files\n' "$count"
}

# CI runs pytest on Python 3.12. With uv, build a cached 3.12 venv once and
# use it; without uv, fall back to the system python and say so.
CI_PY="3.12"
pick_python() {
  local venv="${XDG_CACHE_HOME:-$HOME/.cache}/aphotic-ci/py$CI_PY"
  if [[ -x "$venv/bin/python" ]] && "$venv/bin/python" -c 'import pytest' 2>/dev/null; then
    echo "$venv/bin/python"; return
  fi
  if command -v uv >/dev/null \
      && uv venv -q --python "$CI_PY" "$venv" >>"$LOG" 2>&1 \
      && uv pip install -q --python "$venv/bin/python" pytest >>"$LOG" 2>&1; then
    echo "$venv/bin/python"; return
  fi
  echo python3
}

run_py() {  # run_py [pytest target]
  local out status=0 py version
  py="$(pick_python)"
  version="$("$py" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
  [[ "$version" == "$CI_PY" ]] \
    || echo "NOTE  pytest runs on Python $version here; CI uses $CI_PY (install uv to match it)"
  out="$(in_ci "$py" -m pytest "${1:-tests/}" -q -rf --tb=short -p no:cacheprovider 2>&1)" || status=$?
  printf '=== pytest %s (exit %d)\n%s\n' "${1:-tests/}" "$status" "$out" >>"$LOG"
  if ((status)); then
    report "test: pytest ${1:-tests/}" "$status"
    show "$out"
    printf '      rerun: tools/ci/local.sh --test <file from the FAILED lines>\n'
  else
    printf 'PASS  test: pytest %s (%s)\n' "${1:-tests/}" "$(tail -n 1 <<<"$out" | tr -d '=' | sed 's/^ *//;s/ *$//')"
  fi
}

run_shellcheck() {
  if ! command -v shellcheck >/dev/null; then
    echo "SKIP  shellcheck (not installed; advisory in CI)"
    return
  fi
  local out status=0
  out="$(in_ci bash -c 'find . -name "*.sh" -not -path "./.git/*" -print0 | xargs -0 shellcheck --severity=warning --format=gcc' 2>&1)" || status=$?
  printf '=== shellcheck\n%s\n' "$out" >>"$LOG"
  report "shellcheck: $(grep -c ': warning:\|: error:' <<<"$out") findings" "$status" advisory
}

run_packages() {
  if ! command -v pacman >/dev/null; then
    echo "SKIP  profile packages (needs pacman)"
    return
  fi
  local out status=0
  out="$(cd "$TREE" && bash tools/check_profile_packages.sh 2>&1)" || status=$?
  printf '=== check_profile_packages\n%s\n' "$out" >>"$LOG"
  report "install-dry-run: profile packages resolve" "$status"
  ((status)) && show "$out"
}

install_paths_touched() {
  git -C "$ROOT" diff --name-only origin/dev...HEAD 2>/dev/null \
    | grep -qE '^(install\.sh|lib/|profiles/|tools/check_profile_packages\.sh)'
}

if [[ -n "$single" ]]; then
  single="${single#./}"
  [[ -f "$TREE/$single" ]] || { echo "no such test in the checkout: $single" >&2; exit 2; }
  case "$single" in
    *.sh) run_sh_one "$single" && echo "PASS  test: $single" || failed=1 ;;
    *.py) run_py "$single" ;;
    *) echo "--test takes a tests/*.sh or tests/*.py file" >&2; exit 2 ;;
  esac
else
  case "$only" in
    "") run_syntax; run_sh; run_py; run_shellcheck
        if install_paths_touched; then
          run_packages
          echo "NOTE  install paths changed: CI also runs install-dry-run in an Arch container,"
          echo "      and the change needs a run on the dev VM before merge."
        fi ;;
    syntax) run_syntax ;;
    sh) run_sh ;;
    py) run_py ;;
    shellcheck) run_shellcheck ;;
    packages) run_packages ;;
    *) echo "--only takes syntax|sh|py|shellcheck|packages" >&2; exit 2 ;;
  esac
fi

((here)) || echo "      (CI-shaped checkout: shallow, detached, no origin/* refs, no gitignored files)"
echo "log: $LOG"
exit "$failed"
