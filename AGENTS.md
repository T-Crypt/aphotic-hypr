# Aphotic-Hypr: rules for coding agents

Aphotic is a Linux desktop shell: Quickshell (QML) + Hyprland, a Bash installer, an `aphotic`
CLI, and plugins (separate repo `T-Crypt/aphotic-plugins`). Public repo. Read only what the
task needs. `CONTRIBUTING.md` holds the full conventions.

This file is the one tracked set of agent rules. If your tool reads a different file and that
file does not exist yet, copy this into it (`cp -n AGENTS.md CLAUDE.md`, `GEMINI.md`, and so
on). Never overwrite one that exists: it may hold the machine owner's own rules, and those win
on that machine. The copies are gitignored; never commit them. Change the rules here.

## Where things are
- Shell: `Configs/quickshell/aphotic/` (`shell.qml`, `services/` singletons, `modules/` surfaces,
  `components/` shared parts).
- CLI: `Configs/.local/bin/aphotic` dispatches to `Configs/.local/lib/aphotic/commands/cmd_*.sh`.
- Installer: `install.sh` + `lib/install/`. Package lists: `profiles/base/{full,minimal}.toml`.
- Tests: `tests/test_*.sh` (each one a script) and `tests/test_*.py` (pytest). CI helpers:
  `tools/ci/`. Workflows: `.github/workflows/`.
- `docs/` is gitignored maintainer notes. It may be absent; never depend on it.

## Reference
The public docs are the project wiki. Fetch a page as raw markdown (4 to 20 KB each) instead of
reading the tree to learn a subsystem:
`https://raw.githubusercontent.com/wiki/T-Crypt/aphotic-hypr/<Page>.md`

| Task | Page |
|---|---|
| Start contributing, or test in a VM | `Developer-SDK` (the hub), `Dev-VM`, `Contributor-Workflow` |
| How the shell fits together | `Architecture`, `Design-Principles` |
| Write or change a plugin | `Plugin-System`, `Build-a-Plugin`, and the plugin SDK guide: `https://raw.githubusercontent.com/T-Crypt/aphotic-plugins/main/WRITING-PLUGINS.md` |
| The `aphotic` CLI | `CLI-Reference` |
| Installer, profiles, layers | `Installation`, `Profiles-and-Layers`, `Compatibility` |
| Themes and colours | `Theming` |
| Resource Engine | `Resource-Engine` |
| Something broke on a user's machine | `Troubleshooting` |

## Installing Aphotic for a user
Follow the `Installation` page. On Arch, from a clone: `./install.sh --help` lists every flag.
Run the installer with `--profile full` (or `minimal`) and `--no-assistant` to skip the guided
setup. On a machine that already has an NVIDIA driver, also pass `--nvidia-driver keep` or
`reinstall`. Add `--dry-run` to preview first. `aphotic doctor` checks the result.

## Branches
- `dev` is the default branch and collects work. `main` only moves on a release.
- Start from fresh `dev`: `git fetch origin && git worktree add ../aphotic-<name> -b fix/<name> origin/dev`
  (`feature/<name>` for features). Work in that worktree, never in the main checkout.
- One ticket = one branch = one PR into `dev`. Never stack on another open PR's branch.
- Never push `dev` or `main` (both protected). Pushing your own `fix/`/`feature/` branch is fine.
- Never merge. A maintainer merges after the required checks pass.
- On a machine running Aphotic, check `readlink -f ~/.config/hypr/keybinds.lua` before removing a
  worktree. If it points into that worktree, run `aphotic sync` from the main checkout first, or
  Hyprland breaks.

## Tickets
The project tracks work on a public epiq board in the `__epiq_state__` branch. Browse it with
`epiq gui` or the `epiq` TUI, or use GitHub issues if you don't run epiq.
- Every commit subject starts with the ticket ref, read from the board (never invent one):
  `Q68MZ2B launcher: build the panel only while it is open`. No ticket: no ref.
- With the `epiq_*` MCP tools: `epiq_sync` before reading and after writing. Find work with
  `epiq_issue_list` (`brief: true`), read one with `epiq_issue_get <ref>`. Taking a ticket: move
  it to `In progress`, assign yourself (`self: true`), add tag `agent:<your-name>`.
- New tickets go in `Todo`: small, one outcome, plain title. Never cite gitignored files such as
  `docs/` in one, because readers can't see them.
- Progress, blockers and the PR link go in ticket comments. Close only after merge.
- Never edit the `__epiq_state__` branch or `~/.epiq-global` by hand.

## Commits and PRs
- No AI attribution: no "Generated with", no Co-Authored-By, no session links.
- Never name another project or person in code, comments, commits or PRs.
- Plain writing: no em dashes, no adverbs, active voice. Commits: a few casual lines.
- PR body: `## Problem`, `## Plan`, `## Resolution`. State what you verified and what you
  could not.
- Open with `gh pr create --base dev`.

## Code rules
1. Comments minimal: a non-obvious workaround or a safety warning only.
2. State lives in a singleton in `Configs/quickshell/aphotic/services/`; components read it.
3. A `pragma Singleton` that acts on its own needs a construction site in `shell.qml`'s
   `_residentSingletons`, or it never runs.
4. Every binary the shell runs goes in both `profiles/base/full.toml` and `minimal.toml`.
5. No core file contains a plugin id.
6. No destructive automatic action. No cloud requirement. No polling when an event exists.
7. Static `PanelWindow` geometry; animate content, not window size.
8. Match the surrounding code. Target Qt 6.11 and Quickshell 0.3.1. If `~/docs-local` exists,
   check APIs there first.

## Structure over features
Add a capability through the extension point that already exists: a plugin, a manifest block,
a drop-in file under `~/.config/aphotic/`, or an `aphotic` subcommand. Never name an inference
engine, agent harness, model or outside project in core code, and never add a second way to do
something one way already does. If the task seems to need either, stop and propose the
extension point instead.

## CI
- Before every push, run `tools/ci/local.sh`. It runs the CI checks in a checkout shaped like
  GitHub's and prints only what failed, with a `rerun:` command for each failure. It exits
  non-zero on any failure; if you pipe its output, check the exit code too.
  Green there means green for `test` and `bash-syntax`.
- One test: `tools/ci/local.sh --test tests/test_x.sh`. Fast loop in your own tree: `--here`.
  One suite: `--only syntax|sh|py`.
- A red PR: run `tools/ci/triage.py <pr-number>`. It names the failing test and its error lines.
  Fix that, run the `reproduce:` command it prints, then push. Don't read raw CI logs, don't
  audit the runner by hand, and don't wait on CI in a loop.
- Required checks: `test`, `shellcheck`, `bash-syntax`, `Analyze (python)`, `Analyze (actions)`.
  A run named "Code scanning AI findings" never blocks a merge, so ignore it. shellcheck
  warnings are advisory.
- What the runner lacks. Code that needs any of these needs a fallback, and a test that passes
  on your machine but fails in CI hits one of them:
  - Ubuntu with Python 3.12 (`local.sh` uses 3.12 when `uv` is installed). Avoid 3.13+ features.
  - A shallow, detached checkout: no `origin/main`, no `docs/`, no gitignored files.
  - No git identity: a test that commits must pass `-c user.name=... -c user.email=...`.
  - No `~/.config`, no desktop session, no `qs`, `hyprctl` or `nvidia-smi`.
  - Network calls can time out.
- Changes to `install.sh`, `lib/` or `profiles/` also run `install-dry-run` in an Arch container.

## Verify before you claim
- QML: `qmllint` is not reliable here. Use a windowless `qs -p` probe
  (`QT_QPA_PLATFORM=offscreen`). Never run `qs -p .` on a live desktop: it maps a second bar.
- The maintainer checks visual changes. Do not screenshot to prove a fix.
- Changes to `install.sh`, `lib/install/` or systemd units need a run on a disposable Arch VM
  before merge. Say so in the PR if you could not do it.
