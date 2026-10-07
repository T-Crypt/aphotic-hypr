#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
TRIAGE="$ROOT/tools/ci/triage.py"
FIXTURES="$ROOT/tests/fixtures/ci"

# triage: a bash suite failure comes out as the test's own lines.
status=0
out="$(python3 "$TRIAGE" --log "$FIXTURES/bash_suite_failed.log")" || status=$?
[[ $status -eq 1 ]] || fail "triage exits $status on a failing log, want 1"
grep -q '^  FAILED tests/test_docs_tools.sh$' <<<"$out" || fail "triage misses the failing bash test"
grep -q "ambiguous argument 'origin/main'" <<<"$out" || fail "triage drops the error line"
grep -q 'reproduce: tools/ci/local.sh --test tests/test_docs_tools.sh' <<<"$out" || fail "triage gives no rerun command"
grep -q 'pythonLocation\|##\[group\]' <<<"$out" && fail "triage keeps runner env noise"
grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z|'$'\x1b' <<<"$out" && fail "triage keeps timestamps or ANSI codes"
grep -q 'PASS: display manager' <<<"$out" && fail "triage prints passing tests"

# triage: pytest failures and bash -n errors.
out="$(python3 "$TRIAGE" --log "$FIXTURES/pytest_and_syntax_failed.log")" || true
grep -q 'E   assert 300 == 255' <<<"$out" || fail "triage misses the pytest assertion"
grep -q 'reproduce: tools/ci/local.sh --test tests/test_palette_clamp.py' <<<"$out" || fail "triage gives no pytest rerun command"
grep -q "syntax error near unexpected token" <<<"$out" || fail "triage misses the bash -n error"

# triage: a log with no recognisable failure falls back to its tail.
printf 'job\tstep\t2026-10-05T00:00:00.0000000Z something broke\n' > "$WORKDIR/plain.log"
out="$(python3 "$TRIAGE" --log "$WORKDIR/plain.log")" || true
grep -q 'no test failure blocks found' <<<"$out" || fail "triage has no fallback"
grep -q 'something broke' <<<"$out" || fail "triage fallback drops the last lines"

# local.sh: build a small repo and check the checkout it runs tests in.
REPO="$WORKDIR/repo"
mkdir -p "$REPO/tools/ci" "$REPO/tests" "$REPO/docs"
cp "$ROOT/tools/ci/local.sh" "$REPO/tools/ci/local.sh"
printf 'docs/\n' > "$REPO/.gitignore"
echo "ignored" > "$REPO/docs/NOTES.md"
cat > "$REPO/tests/test_shape.sh" <<'EOF'
#!/usr/bin/env bash
[[ ! -e docs ]] || { echo "gitignored docs/ leaked into the checkout"; exit 1; }
! git rev-parse -q --verify refs/remotes/origin/main >/dev/null || { echo "origin/main exists"; exit 1; }
[[ -z "${WAYLAND_DISPLAY:-}${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || { echo "desktop session leaked"; exit 1; }
[[ "$HOME" == */home ]] || { echo "real HOME leaked: $HOME"; exit 1; }
! git fetch -q origin main 2>/dev/null || { echo "network fetch was allowed"; exit 1; }
echo "PASS: shape"
EOF
git -C "$REPO" init -q
git -C "$REPO" remote add origin "https://github.com/T-Crypt/aphotic-hypr.git"
git -C "$REPO" add -A
git -C "$REPO" -c user.name=t -c user.email=t@localhost commit -qm init
git -C "$REPO" update-ref refs/remotes/origin/main HEAD

# No git identity, as on the runner.
run_local() {
  env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 "$REPO/tools/ci/local.sh" "$@"
}

out="$(run_local --only sh 2>&1)" || fail "CI-shaped checkout is not CI-shaped: $out"
grep -q '^PASS  test: 1 bash test files$' <<<"$out" || fail "local.sh does not report the passing suite: $out"

# local.sh: uncommitted, untracked tests are part of the run, and a failure
# prints the test's own output plus a rerun command.
printf '#!/usr/bin/env bash\necho "boom from the new test"\nexit 1\n' > "$REPO/tests/test_new.sh"
status=0
out="$(run_local --only sh 2>&1)" || status=$?
[[ $status -eq 1 ]] || fail "local.sh exits $status on a failing test, want 1"
grep -q '^FAIL  test: tests/test_new.sh$' <<<"$out" || fail "local.sh skips untracked tests: $out"
grep -q 'boom from the new test' <<<"$out" || fail "local.sh hides the failing output"
grep -q 'rerun: tools/ci/local.sh --test tests/test_new.sh' <<<"$out" || fail "local.sh gives no rerun command"
grep -q 'PASS: shape' <<<"$out" && fail "local.sh prints passing tests"

out="$(run_local --test tests/test_shape.sh 2>&1)" || fail "--test fails on a passing test: $out"
[[ -z "$(git -C "$REPO" stash list)" ]] || fail "local.sh touched the stash"

echo "PASS: CI tools (triage parsing, CI-shaped checkout, failure output)"
