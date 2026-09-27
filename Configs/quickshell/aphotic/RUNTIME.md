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
        bar · notch · launcher · dashboard · negotiation · plugins
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
| transient | `agentPanel` | other transients |
| workspace | `workspace` | transients, primaries, modals |
| primary | launcher, dashboard, settings, intelligence, notificationCenter, pkgInstall, wallpaperPicker, keybindsCheatsheet | transients, other primaries, modals |
| modal | `session` | transients, primaries |

The workspace plane survives a primary: a launcher opens over it and
closes back to it.

Per screen, `ScreenState` exposes:

- `surfaceStack`: open surfaces, oldest first
- `surface`: `{stack, focusOwner, mode, blocking}`, where `mode` is
  `ambient | transient | workspace | primary | modal | blocked`
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

**Plugin surfaces.** `Surfaces.declare(name, role)` gives a plugin-owned
surface a role. It has no `ScreenState` flag, so the plugin reports its
own opens and closes with `Surfaces.track(screenState, name, open)` and
closes itself on `Surfaces.closeRequested(screenState, name)`. An
undeclared name in the stack is inert: it closes nothing and nothing
closes it.

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

Current consumers: the bar's `resources` status icon, the notch idle
strip (the CPU and memory gauges give way to the pressured resource), and
the `resources.inspect` action, which opens the Command Center on Flow.

## Runtime context (`services/RuntimeContext.qml`, `services/ContextPolicy.js`)

What the user is doing right now. This is separate from install profiles
(which layers are installed) and ProfileEngine phases (what a domain
workload is doing). A context installs nothing, starts nothing, and
writes no user settings, so switching back to `default` undoes all of it.
Contexts are switched by hand only and are not persisted across shell
restarts.

| Context | Popups | Motion | Resources surfaced from |
| :-- | :-- | :-- | :-- |
| `default` | all | full | pressure |
| `focus` | critical only | reduced | contention |
| `dev` | normal and critical | full | pressure |
| `game` | critical only | reduced | pressure |
| `present` | none | reduced | negotiating |

- **Popups**: `Notifs.popupAllowed(urgency)`. DND still holds back
  everything, and held-back notifications still land in history.
- **Motion**: `RenderGate.decorative` goes false. Every self-running
  animation already gated on it stops.
- **Resources**: `ResourcePosture.surfaced`.

Switch contexts with `aphotic context list|current|set <name>|revert`,
through the `context` IPC target, or with the `context.<name>` actions in
the notch palette.

Plugins read `RuntimeContext.current` and `.policy`, and connect to
`RuntimeContext.switched(from, to)`.

## Inspecting it

`aphotic runtime` prints each screen's surfaces, the context, the
posture, whether decorative motion is gated, and the last answered
negotiations. `aphotic runtime --json` is the same data for scripts.

## Idle cost

`tests/test_idle_cost.py` fails on any repeating `Timer` or infinite
animation whose `running:` is a literal `true`, unless it is listed with
the reason it has to run at rest. Gate new periodic work on whatever
reads it.
