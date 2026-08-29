## What this changes

<!-- One or two sentences: what does this PR do, and why? -->

## Scope

- [ ] This is scoped to one module/command/fix, not a multi-surface change
- [ ] Related `README.md` Roadmap item (if any): <!-- e.g. "Bar orientation" -->
- [ ] If this touches `install.sh` or a systemd unit file: validated on the dev VM (not just CI) -- note the result below

## Verification

This project verifies live, not just "it parses" (see `CONTRIBUTING.md`):

- [ ] `pkill -x qs` then a fresh `qs -c aphotic` restart (not relying on hot-reload alone)
- [ ] Checked logs for `Configuration Loaded` and zero new errors
- [ ] Confirmed the shell is still running afterward (`pgrep -f "qs -c aphotic"`)
- [ ] For visual changes: screenshot attached below
- [ ] `bash -n` on any shell script touched
- [ ] Added/updated a test under `tests/` for install/uninstall/CLI behavior changes
- [ ] No debug residue left behind (`git diff` reviewed)

## Screenshot / recording

<!-- Required for anything visual. Drag an image in, or delete this section if not applicable. -->

## Anything the reviewer should know

<!-- Deliberate scope cuts, known follow-up work, assumptions made where something was ambiguous. -->
