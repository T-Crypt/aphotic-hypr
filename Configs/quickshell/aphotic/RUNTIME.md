# Shell runtime state

Three small layers sit between the services and the surfaces. Each is
one reactive QML singleton over a plain `.js` rules file, so the rules
run under node in CI (`tests/test_*.cjs`) exactly as QML runs them.

```
             user (keybind, CLI, palette)
                        │
                        ▼
                 RuntimeContext ─────────────┐
            (what the user is doing)         │ thresholds, popup floor,
                        │                    │ motion
        ┌───────────────┴──────────┐         │
        ▼                          ▼         ▼
    Surfaces                ResourcePosture ◄── ResourceEngine
 (who owns each screen)     (how much the machine needs attention)
        │                          │
        └────────────┬─────────────┘
                     ▼
        bar · notch · launcher · dashboard · negotiation
                     │
                     ▼
            PluginApi.handle(name)  ── only what [api].uses declares
                     │
                     ▼
                  plugins
```

None of them polls. Every change is a flag flip, a claim, a hold or a
context switch. The only timer is ResourcePosture's settle window, and it
runs once per answered negotiation.

## Surfaces (`services/Surfaces.qml`, `services/SurfacePolicy.js`)

Every window still opens and closes through its own flag on its screen's
`ScreenState`. `ScreenState` reports each flag change to `Surfaces`, which
applies the role table and closes whatever the change displaces through
the same flags.

| Role | Surfaces | Opening it closes |
| :-- | :-- | :-- |
| transient | `agentPanel` | other transients, shelves, Sonar |
| shelf | declared `shelf:<output>:<edge>` | transients, Sonar; other shelves stay open |
| workspace | `workspace` | transients, shelves, primaries, modals, Sonar |
| primary | launcher, dashboard, settings, intelligence, notificationCenter, pkgInstall, wallpaperPicker, keybindsCheatsheet | transients, shelves, other primaries, modals, Sonar |
| modal | `session` | transients, shelves, primaries, Sonar |
| sonar | `sonar` | nothing -- it displaces no role and closes when any ordinary surface opens |

The workspace plane survives a primary: a launcher opens over it and
closes back to it. Sonar leaves those surfaces open during its two-second
ping and takes dismissal input. It yields to blocking prompts and new
surface openings. The Sonar role adds no hold and does not set `engaged`,
so it preserves the bar's popouts and notch.

Per screen, `ScreenState` exposes:

- `surfaceStack`: open surfaces, oldest first
- `surface`: `{stack, focusOwner, mode, blocking}`, where `mode` is
  `ambient | transient | workspace | primary | modal | sonar | blocked`
- `engaged`: something owns the keyboard. The bar's hover popouts and the
  notch's expanded tile settle when this goes true.

**Blocking modals.** A surface that must own the keyboard on every screen
calls `Surfaces.hold(owner)` for its lifetime and `Surfaces.release(owner)`
on destruction. While any hold exists, `Surfaces.suppressed` is true and
every keyboard-taking window hides without losing its flag, so it comes
back as it was. The negotiation prompt is the only holder today.
`tests/test_surface_wiring.py` fails any keyboard-taking window whose
`visible` ignores `Surfaces.suppressed`.

**Back.** `Surfaces.back(screenState)` closes the focus owner. It never
backs out of a blocking modal, because backing out of a negotiation would
be a decision. The CLI is `aphotic runtime back`, and the IPC call is
`qs -c aphotic ipc call aphotic back`.

**Plugin surfaces.** A plugin gives its surfaces roles through its API
handle (`surface.declare`, below), not by calling Surfaces directly. The
handle namespaces the name as `plugin:<plugin>/<local>`, so a plugin can
never shadow or close a core surface or another plugin's. The plugin
reports its own opens and closes, because it has no `ScreenState` flag,
and closes itself when asked. Undeclaring a surface also removes it from
every screen's stack. An unknown name in a stack is inert: it closes
nothing and nothing closes it.

**Adding a core surface.** Add the flag to `ScreenState`, its
`on<Flag>Changed: Surfaces.track(...)` line, and its role in
`SurfacePolicy.SURFACES`. The wiring test fails if any of the three is
missing.

## Resource posture (`services/ResourcePosture.qml`, `services/Posture.js`)

The Resource Engine's state reduced to one level, for the whole shell to
read. Flow remains the deep inspection surface.

| Level | Meaning |
| :-- | :-- |
| `quiet` | nothing worth showing |
| `settling` | a negotiation was just answered (4 s) |
| `pressure` | a declared resource at ≥ 85% of its budget, by claims or by measured use |
| `contention` | a declared resource over budget with more than one holder, a second holder on an exclusive resource, or the engine's `overBudget` |
| `negotiating` | the engine is asking the user to decide |

Only declared resources are judged, the same rule the engine arbitrates
by. Contention agrees with Flow's `contended` flag, and
`tests/test_resource_posture.cjs` checks the two against each other.

Properties: `level`, `resource` (`{key, label, unit, ratio, owners, ...}`),
`headline`, `surfaced`, `history` (answered negotiations, newest first,
20 kept).

`surfaced` is the one the ambient shell reads. It is true when the level
reaches the runtime context's `resources` threshold. A negotiation always
opens its prompt, whatever the context.

Colour comes from `Colours.posture(level, rest)`. Pressure uses the
palette's tertiary role and contention/negotiating use error, so
wallpaper-driven palettes stay in charge of the hue.

Current consumers:

- The bar's `resources` status icon.
- The notch idle strip: the CPU and memory gauges give way to the
  resource that needs attention.
- The notch Processes tile: a banner with the headline and a **Flow**
  button. Clicking the collapsed notch opens this tile first.
- The `resources.inspect` action, which opens the Command Center on Flow.
- One notification per contention episode that nobody will be asked
  about: over budget, and nothing on the resource can be suspended. It
  exists because a fullscreen game hides the bar and notch. It lands in
  history whatever the context allows on screen, and carries an
  **Inspect in Flow** action. A negotiation never notifies; it opens its
  prompt. `ResourcePosture.contentionStarted(resource)` is the signal, and
  shell.qml is the host that turns it into a notification.

## Runtime context (`services/RuntimeContext.qml`, `services/ContextPolicy.js`)

What the user is doing right now. This is separate from install profiles
(which layers are installed) and ProfileEngine phases (what a domain
workload is doing). A context installs nothing, starts nothing, and
writes no user settings, so switching back to `default` undoes all of it.
Contexts are switched by hand only and are not persisted across shell
restarts.

| Context | Popups | Motion | Resources surfaced from | Plugin overlays |
| :-- | :-- | :-- | :-- | :-- |
| `default` | all | full | pressure | shown |
| `focus` | critical only | reduced | contention | shown |
| `dev` | normal and critical | full | pressure | shown |
| `game` | critical only | reduced | pressure | unmounted |
| `present` | none | reduced | negotiating | unmounted |

- **Popups**: `Notifs.popupAllowed(urgency)`. DND still holds back
  everything, and held-back notifications still land in history.
- **Motion**: `RenderGate.decorative` goes false. Every self-running
  animation already gated on it stops.
- **Resources**: `ResourcePosture.surfaced`.
- **Plugin overlays**: shell.qml empties the `overlay` surface model, so
  pets and visualisers are destroyed rather than hidden, and cost nothing
  until the context ends.

Any context other than `default` shows its icon in the notch's collapsed
strip. That is the one ambient sign that popups, motion or overlays are
being held back on purpose.

Switch contexts with `aphotic context list|current|set <name>|revert`,
through the `context` IPC target, or with the `context.<name>` actions in
the notch palette.

Plugins read `RuntimeContext.current` and `.policy`, and connect to
`RuntimeContext.switched(from, to)`.

## Plugin API (`services/PluginApi.qml`, `services/PluginApiCore.js`)

The supported way for a plugin to reach the running shell. Surfaces and
hooks say where a plugin mounts; `[api]` says what it may ask the shell
for once it is there.

```toml
[api]
version = 1
uses = ["context.observe", "resource.observe"]
```

```qml
readonly property var api: PluginApi.handle("my-plugin")
// api.context.current(), api.resources.level() ... read in bindings, reactive
```

| `uses` | Handle | What it does |
| :-- | :-- | :-- |
| `context.observe` | `context.current()`, `.policy()`, `.contexts()` | read the runtime context |
| `context.request` | `context.request(name, reason)` | suggest a switch. The user gets a notification naming the plugin and its reason, and switches from its action or doesn't. At most one suggestion per plugin per minute. |
| `resource.observe` | `resources.level()`, `.surfaced()`, `.resource()`, `.headline()` | read the resource posture |
| `surface.declare` | `surfaces.declare(local, role)`, `.track(screenState, local, open)`, `.onCloseRequested(fn)` | give a plugin surface a role in the surface policy |
| `notifications.publish` | `notify(summary, body)` | notify under the plugin's display name, subject to DND and the context popup floor |

The rules the handle follows:

- **Only what was declared.** The handle carries only the calls named in
  `uses`. An undeclared call is absent, and `api.has(use)` asks without
  touching it.
- **Checked at call time.** Every call re-checks the grant, so disabling
  or removing the plugin revokes the handle it already holds. Its
  declared surfaces and close handlers are dropped the same tick.
  `handle()` returns null while the plugin is disabled, including in safe
  mode.
- **Versioned.** `aphotic plugin install` refuses a plugin whose
  `[api].version` is newer than the shell's, because its first call
  would fail. `aphotic plugin validate` reports that as an error and an
  unknown `uses` entry as a warning. `aphotic plugin api` lists the
  version and every call.
- **Part of the contract.** The `[api]` block is stored in the registry,
  and editing it in place reads as drift in `aphotic plugin list`.
- **Plugins without `[api]` work exactly as before.** They get no handle
  calls.

QML cannot sandbox imports, so a plugin can still reach services
directly. That is not a supported contract and can break between
releases. The handle is supported, and it is versioned. `api.uses` in
`cmd_plugin.sh` and `USES` in `PluginApiCore.js` are held equal by
`tests/test_plugin_api.sh`.

## Inspecting it

`aphotic runtime` prints:

- each screen's surfaces
- the context and the posture
- whether decorative motion is gated
- every piece of repeating work the shell has loaded, and whether it is
  live
- the enabled plugins
- the last answered negotiations

`aphotic runtime --json` is the same data for scripts.

## Activity (`services/Activity.qml`, `services/ActivityProbe.qml`)

Every repeating `Timer` carries an `ActivityProbe` beside it:

```qml
Timer {
    id: weatherRefresh
    interval: 20 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
}

ActivityProbe {
    name: "weather"
    kind: "network"   // poll | file | process | network | render
    timer: weatherRefresh
}
```

The probe reads the timer's own `running` and `interval`, so the report
is the real state rather than a description of it. A module that was
never constructed never reports, so absence from the list means not
loaded. Wakeups are scheduled wakeups: 60 s over each live timer's
interval. They say how often the shell asked to be woken, which is the
number a regression moves.

`aphotic perf snapshot` asks the running shell for the same report and
records the context, posture, live probes and wakeups/min in each
`history.jsonl` row, so a slower snapshot can be tied to what was
running. Add `"shell_wakeups_per_min": <n>` to `perf-budget.json` to have
`aphotic perf budget` judge it. No default ships, because the right
number depends on the bar style and plugins a machine runs.

## Idle cost

`tests/test_idle_cost.py` enforces three rules:

- A repeating `Timer` or infinite animation whose `running:` is a
  literal `true` fails unless it is listed with the reason it has to run
  at rest. Gate new periodic work on whatever reads it.
- Every repeating `Timer` must have an `ActivityProbe`.
- Probe names must be well-formed and unique.

## Sonar and shelves

Settings → Sonar & Shelves keeps these features off by default. Sonar snapshots
live control bounds once per two-second ping. Core adapters revoke hidden targets;
plugin descriptors require API v2 and the `sonar.register` grant. Disabled-feature
ghosts read installed metadata and recheck eligibility before Open/Enable/Settings.
They do not construct disabled QML. Sonar dismisses before opening the destination.

Shelves persist configuration by connector name, with independent left/right
flags, pins, tabs and handles. New outputs start disabled. Output removal closes
live surfaces while retaining saved configuration. WindowList shares its grouping
with the released dock and uses existing toplevel monitor metadata for output scope.

A full-output PanelWindow gives each output a fixed window budget. The content
reveals and closes inside it; app count and magnification never resize the window.
Tab panels have a bounded width and scroll overflow. Closing destroys each edge's
content after SurfaceReveal ends; without visible handles the host unmounts too.
Handle-only input masks cover the visible handles. Closed handles do not take
keyboard focus. No pointer-leave dismissal, hidden sensor or polling runs.

The bracket shortcuts check ownership before registration/removal; conflict and
failure text appears in Settings. IPC provides focused-output `toggle`, `close`
and `openTab`, plus explicit-output `toggleOn`, `closeOn` and `openTabOn` methods.
Runtime JSON reports `shelves.open` and `shelves.mountedHosts`.

ShelfTabs resolves core media/agents/quick controls and eligible plugin edge tabs.
Plugin content receives output/screen connector strings, edge and active before
construction. Registry revocation destroys shown content. Notch hosting requires
plugin compatibility and the user's separate opt-in. Agent views hold the shared
feed with one owner per output/edge and release it on destruction.

Launch echo and tab acknowledgement each default off. Launch requests match new
window events on the requesting edge; expiry checks need no repeating timer.
Acknowledgement fires after the selected panel loads. Motion is finite; reduced
motion holds a static outline. Neither effect keeps hidden content mounted.

The public [Sonar and Shelves](https://github.com/T-Crypt/aphotic-hypr/wiki/Sonar-and-Shelves)
page documents controls. [Plugin System](https://github.com/T-Crypt/aphotic-hypr/wiki/Plugin-System#shelf-tabs-and-sonar)
documents `[ui.edge_tab]`, placement/gates, required host properties and API v2
registration. V1 plugin behavior remains compatible.
