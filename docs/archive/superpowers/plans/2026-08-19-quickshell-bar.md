> **Archived 2026-08-30.** Implementation plan for the now-shipped Quickshell bar. Noted in [`docs/APHOTIC_UNIFIED_VISION.md`](../../../APHOTIC_UNIFIED_VISION.md)'s Historical/Superseded section. Kept here as the historical plan.

# Quickshell Left Bar (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Waybar with a vendored, hand-adapted Quickshell left bar visually cloned from caelestia-dots/shell, themed by the existing wallust pipeline.

**Architecture:** Vendor caelestia-dots/shell's bar-module QML (pinned to a fixed commit) into `.configs/quickshell/noctis/`, mechanically swapping their C++-plugin-backed `Caelestia.Config`/`Tokens` imports for two hand-written QML singletons. Caelestia's own window host and popout system are NOT vendored (both pull in unrelated modules/native plugins) — we write minimal replacements. Colors come from a new wallust template, not caelestia's own color engine.

**Tech Stack:** Quickshell (QML/Qt6), Hyprland, wallust, Proxmox VM (id 115, "noctis") for live verification via `qm guest exec` + `grim`.

**Spec:** `docs/superpowers/specs/2026-08-19-quickshell-bar-design.md`

## Global Constraints

- Vendor, don't depend: no `caelestia-shell` package/AUR dependency — QML is copied into this repo.
- No native C++ plugin: do not vendor `plugin/` (Config/Tokens C++, `Caelestia.Internal`, `Caelestia.Blobs`). All config/tokens are plain QML singletons we author.
- Vendor source is pinned to commit `27faa5cf95299c2eaa31848ccd78e746d6eef4ed` of `caelestia-dots/shell` — every fetch command in this plan uses that exact SHA so vendoring is reproducible.
- Every vendored file gets the same mechanical edit: replace `import Caelestia.Config` with `import qs.config`. No other text changes unless a task says otherwise.
- Colors: wallust remains the single theming source. Do not adopt caelestia's own `Colours.qml`/Material-You engine.
- Popouts and the window host are hand-authored for Phase 1, not vendored (see Task 6 and Task 7 rationale) — caelestia's versions pull in the `nexus`/`windowinfo` modules and the `Caelestia.Blobs` native plugin, both out of scope.
- Verification is manual/visual on the Proxmox test VM (VM 115) — there is no automated test suite for this repo's config/QML.
- `.configs/waybar/` is deleted only in the task that lands a verified-working replacement (Task 10), not before.

---

### Task 1: Verify Quickshell packaging and scaffold a minimal launchable shell

**Files:**
- Create: `.configs/quickshell/noctis/shell.qml`
- Modify: `profiles/base/full.toml` (add `quickshell` package)

**Interfaces:**
- Produces: a `qs -c noctis` entrypoint later tasks extend. No QML types exported yet.

- [ ] **Step 1: Verify the Quickshell package name**

Run:
```bash
curl -s "https://archlinux.org/packages/search/json/?name=quickshell" | grep -o '"pkgname":"[^"]*"'
curl -s "https://aur.archlinux.org/rpc/v5/info/quickshell-git" | grep -o '"Name":"[^"]*"'
```
Expected: confirms whether `quickshell` is official-repo or AUR-only, and whether `quickshell-git` exists. Use whichever is the actual current package name in the edit below — do not assume.

- [ ] **Step 2: Add the verified package to the base profile**

Open `profiles/base/full.toml`, find the line listing `waybar`, and add the verified Quickshell package name on its own line in the same package list (do not remove `waybar` yet — Task 10 does that).

- [ ] **Step 3: Write a minimal shell entrypoint**

Create `.configs/quickshell/noctis/shell.qml`:

```qml
import QtQuick
import Quickshell

ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            anchors.top: true
            anchors.bottom: true
            anchors.left: true

            implicitWidth: 48
            color: "#202020"

            Text {
                anchors.centerIn: parent
                text: "noctis"
                color: "white"
            }
        }
    }
}
```

- [ ] **Step 4: Sync to the VM and verify it launches**

Run (adjust paths to match this session's established VM sync pattern):
```bash
tar -czf /tmp/noctis-quickshell.tar.gz -C .configs/quickshell .
qm guest exec 115 -- bash -c 'mkdir -p ~/.config/quickshell'
# copy the tarball to the VM via the same base64 transfer pattern used earlier this session, then:
qm guest exec 115 -- bash -c 'tar -xzf /tmp/noctis-quickshell.tar.gz -C ~/.config/quickshell'
qm guest exec 115 -- bash -c 'qs -c noctis > /tmp/qs.log 2>&1 & sleep 3; cat /tmp/qs.log'
```
Expected: no QML import/parse errors in the log. Take a `grim` screenshot (same workflow as prior VM verification this session) and confirm a plain dark strip with the text "noctis" renders on the left edge of the screen.

- [ ] **Step 5: Commit**

```bash
git add .configs/quickshell/noctis/shell.qml profiles/base/full.toml
git commit -m "Scaffold minimal Quickshell entrypoint, verify it launches on the VM"
```

---

### Task 2: Author the Tokens and Config singletons

**Files:**
- Create: `.configs/quickshell/noctis/config/Tokens.qml`
- Create: `.configs/quickshell/noctis/config/Config.qml`
- Create: `.configs/quickshell/noctis/config/GlobalConfig.qml`
- Create: `.configs/quickshell/noctis/config/qmldir`

**Interfaces:**
- Produces: `Tokens` singleton with `.padding.{small,medium,large,extraLarge,extraLargeIncreased}`, `.spacing.{small,medium,large}`, `.radius.{small,medium,large,full}`, `.sizes.bar.innerWidth`, `.anim.durations.{small,medium,large}`. `Config` singleton with `.bar.*` (see below), `.border.{thickness,minThickness,rounding}`. `GlobalConfig` singleton with `.bar.workspaces.perMonitorWorkspaces` (bool) and `.services.brightnessIncrement` (int) — every later task that reads these exact paths depends on this shape.
- Consumes: nothing (leaf singletons).

- [ ] **Step 1: Write the qmldir so `qs.config` resolves as a module**

Create `.configs/quickshell/noctis/config/qmldir`:

```
module qs.config
singleton Tokens 1.0 Tokens.qml
singleton Config 1.0 Config.qml
singleton GlobalConfig 1.0 GlobalConfig.qml
```

- [ ] **Step 2: Write Tokens.qml**

Create `.configs/quickshell/noctis/config/Tokens.qml`:

```qml
pragma Singleton
import QtQuick

QtObject {
    readonly property QtObject padding: QtObject {
        readonly property int small: 4
        readonly property int medium: 8
        readonly property int large: 12
        readonly property int extraLarge: 16
        readonly property int extraLargeIncreased: 20
    }

    readonly property QtObject spacing: QtObject {
        readonly property int small: 4
        readonly property int medium: 8
        readonly property int large: 12
    }

    readonly property QtObject radius: QtObject {
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 20
        readonly property int full: 9999
    }

    readonly property QtObject sizes: QtObject {
        readonly property QtObject bar: QtObject {
            readonly property int innerWidth: 48
        }
    }

    readonly property QtObject anim: QtObject {
        readonly property QtObject durations: QtObject {
            readonly property int small: 150
            readonly property int medium: 250
            readonly property int large: 350
        }
    }
}
```

- [ ] **Step 3: Write Config.qml**

Create `.configs/quickshell/noctis/config/Config.qml`:

```qml
pragma Singleton
import QtQuick

QtObject {
    readonly property QtObject border: QtObject {
        readonly property int thickness: 2
        readonly property int minThickness: 1
        readonly property int rounding: 12
    }

    readonly property QtObject bar: QtObject {
        readonly property bool persistent: true
        readonly property var excludedScreens: []

        readonly property QtObject tray: QtObject {
            readonly property bool compact: true
        }

        readonly property QtObject popouts: QtObject {
            readonly property bool statusIcons: true
            readonly property bool tray: true
            readonly property bool activeWindow: false
        }

        readonly property QtObject activeWindow: QtObject {
            readonly property bool showOnHover: false
        }

        readonly property QtObject scrollActions: QtObject {
            readonly property bool workspaces: true
            readonly property bool volume: true
            readonly property bool brightness: true
        }

        readonly property QtObject entries: QtObject {
            readonly property var values: [
                { id: "logo", enabled: true },
                { id: "workspaces", enabled: true },
                { id: "spacer", enabled: true },
                { id: "activeWindow", enabled: true },
                { id: "tray", enabled: true },
                { id: "clock", enabled: true },
                { id: "statusIcons", enabled: true },
                { id: "power", enabled: true }
            ]
        }
    }
}
```

- [ ] **Step 4: Write GlobalConfig.qml**

Create `.configs/quickshell/noctis/config/GlobalConfig.qml`:

```qml
pragma Singleton
import QtQuick

QtObject {
    readonly property QtObject bar: QtObject {
        readonly property QtObject workspaces: QtObject {
            readonly property bool perMonitorWorkspaces: false
        }
    }

    readonly property QtObject services: QtObject {
        readonly property int brightnessIncrement: 5
    }
}
```

- [ ] **Step 5: Verify the module resolves**

Add a temporary line to `shell.qml`'s `PanelWindow` (`import qs.config` at the top of the file, and change the `Text` block's `text:` to `` `noctis w=${Tokens.sizes.bar.innerWidth}` ``), sync to the VM per Task 1 Step 4's commands, and confirm the screenshot shows "noctis w=48" with no QML errors in the log. Revert that temporary text-property change afterward (keep the `import qs.config` line — later tasks need it).

- [ ] **Step 6: Commit**

```bash
git add .configs/quickshell/noctis/config/ .configs/quickshell/noctis/shell.qml
git commit -m "Add hand-written Tokens/Config/GlobalConfig singletons"
```

---

### Task 3: Vendor shared UI primitives

**Files:**
- Create: `.configs/quickshell/noctis/components/{Anim,AnchorAnim,CAnim,AnimLoader,Logo,MaterialIcon,ScreenState,StateLayer,StyledClippingRect,StyledRect,StyledText}.qml`
- Create: `.configs/quickshell/noctis/components/effects/{ColouredIcon,Colouriser,Elevation,Mask}.qml`
- Create: `.configs/quickshell/noctis/components/qmldir`
- Create: `.configs/quickshell/noctis/components/effects/qmldir`

**Interfaces:**
- Produces: `qs.components` module (StyledRect, StyledText, MaterialIcon, Anim family, Logo, ScreenState, StateLayer, StyledClippingRect) and `qs.components.effects` module (ColouredIcon, Colouriser, Elevation, Mask) — Task 4 and Task 5 both import these.
- Consumes: `qs.config` (Task 2).

- [ ] **Step 1: Fetch the vendored files at the pinned commit**

```bash
SHA=27faa5cf95299c2eaa31848ccd78e746d6eef4ed
BASE="https://raw.githubusercontent.com/caelestia-dots/shell/$SHA"
mkdir -p .configs/quickshell/noctis/components/effects
for f in Anim AnchorAnim CAnim AnimLoader Logo MaterialIcon ScreenState StateLayer StyledClippingRect StyledRect StyledText; do
  curl -sL "$BASE/components/$f.qml" -o ".configs/quickshell/noctis/components/$f.qml"
done
for f in ColouredIcon Colouriser Elevation Mask; do
  curl -sL "$BASE/components/effects/$f.qml" -o ".configs/quickshell/noctis/components/effects/$f.qml"
done
```

- [ ] **Step 2: Apply the mechanical import edit**

```bash
grep -rl "import Caelestia.Config" .configs/quickshell/noctis/components/ | \
  xargs sed -i 's/^import Caelestia\.Config$/import qs.config/'
```

- [ ] **Step 3: Write qmldir files**

Create `.configs/quickshell/noctis/components/qmldir` listing every `.qml` file fetched in Step 1, one `singleton <Name> 1.0 <Name>.qml` line each if the file has `pragma Singleton`, otherwise `<Name> 1.0 <Name>.qml`. Check each file for `pragma Singleton` before writing its line:

```bash
for f in .configs/quickshell/noctis/components/*.qml; do
  name=$(basename "$f" .qml)
  if grep -q "pragma Singleton" "$f"; then
    echo "singleton $name 1.0 $name.qml"
  else
    echo "$name 1.0 $name.qml"
  fi
done > .configs/quickshell/noctis/components/qmldir
sed -i '1i module qs.components' .configs/quickshell/noctis/components/qmldir
```

Do the same for the effects subfolder:

```bash
for f in .configs/quickshell/noctis/components/effects/*.qml; do
  name=$(basename "$f" .qml)
  if grep -q "pragma Singleton" "$f"; then
    echo "singleton $name 1.0 $name.qml"
  else
    echo "$name 1.0 $name.qml"
  fi
done > .configs/quickshell/noctis/components/effects/qmldir
sed -i '1i module qs.components.effects' .configs/quickshell/noctis/components/effects/qmldir
```

- [ ] **Step 4: Verify with a smoke import**

Temporarily add `import qs.components` and a `StyledText { text: "primitives ok" }` inside `shell.qml`'s `PanelWindow`, sync to the VM, screenshot, confirm it renders with no QML errors, then revert the temporary addition.

- [ ] **Step 5: Commit**

```bash
git add .configs/quickshell/noctis/components/
git commit -m "Vendor shared UI primitives from caelestia-dots/shell (pinned commit)"
```

---

### Task 4: Vendor supporting services

**Files:**
- Create: `.configs/quickshell/noctis/services/{Hypr,Audio,Brightness,Time,Nmcli,NetworkUsage,Players}.qml`
- Create: `.configs/quickshell/noctis/services/qmldir`
- Create: `.configs/quickshell/noctis/utils/{Strings,Icons}.qml`
- Create: `.configs/quickshell/noctis/utils/qmldir`

**Interfaces:**
- Produces: `qs.services` module exposing `Hypr` (workspaces/monitors/active window via Quickshell's built-in `Quickshell.Hyprland`, keyboard-state properties removed), `Audio`, `Brightness`, `Time`, `Nmcli`, `NetworkUsage`, `Players`. `qs.utils` module exposing `Strings.testRegexList(list, value)` and `Icons`. Task 5's bar components consume these by the same names.
- Consumes: `qs.config` (Task 2), `qs.components` (Task 3).

- [ ] **Step 1: Fetch the service and util files**

```bash
SHA=27faa5cf95299c2eaa31848ccd78e746d6eef4ed
BASE="https://raw.githubusercontent.com/caelestia-dots/shell/$SHA"
mkdir -p .configs/quickshell/noctis/services .configs/quickshell/noctis/utils
for f in Hypr Audio Brightness Time Nmcli NetworkUsage Players; do
  curl -sL "$BASE/services/$f.qml" -o ".configs/quickshell/noctis/services/$f.qml"
done
for f in Strings Icons; do
  curl -sL "$BASE/utils/$f.qml" -o ".configs/quickshell/noctis/utils/$f.qml"
done
```

- [ ] **Step 2: Apply the mechanical import edit**

```bash
grep -rl "import Caelestia.Config" .configs/quickshell/noctis/services/ .configs/quickshell/noctis/utils/ | \
  xargs sed -i 's/^import Caelestia\.Config$/import qs.config/'
```

- [ ] **Step 3: Strip the native-plugin-only keyboard block from Hypr.qml**

Open `.configs/quickshell/noctis/services/Hypr.qml`. Remove the `import Caelestia.Internal` line and every property that reads from it: `keyboard`, `capsLock`, `numLock`, `defaultKbLayout`, `kbLayoutFull`, `kbLayout`, `kbMap`, and the `extras`/`options`/`devices` aliases and `hadKeyboard` property. Also remove the `import Caelestia` line if nothing else in the file uses the plain `Caelestia` namespace after the keyboard block is gone (check with `grep -n "Caelestia\." services/Hypr.qml` after the removal — if no matches remain, the import is safe to delete). Leave `toplevels`, `workspaces`, `monitors`, `activeToplevel`, `focusedWorkspace`, `focusedMonitor`, `activeWsId`, `dispatch()`, and the special-workspace cycling logic intact — those only depend on Quickshell's own built-in `Quickshell.Hyprland` module.

- [ ] **Step 4: Write the qmldir files**

```bash
for f in .configs/quickshell/noctis/services/*.qml; do
  name=$(basename "$f" .qml)
  if grep -q "pragma Singleton" "$f"; then
    echo "singleton $name 1.0 $name.qml"
  else
    echo "$name 1.0 $name.qml"
  fi
done > .configs/quickshell/noctis/services/qmldir
sed -i '1i module qs.services' .configs/quickshell/noctis/services/qmldir

for f in .configs/quickshell/noctis/utils/*.qml; do
  name=$(basename "$f" .qml)
  if grep -q "pragma Singleton" "$f"; then
    echo "singleton $name 1.0 $name.qml"
  else
    echo "$name 1.0 $name.qml"
  fi
done > .configs/quickshell/noctis/utils/qmldir
sed -i '1i module qs.utils' .configs/quickshell/noctis/utils/qmldir
```

- [ ] **Step 5: Verify Hypr resolves without native-plugin errors**

Temporarily add `import qs.services` and a `StyledText { text: "ws " + Hypr.activeWsId }` to `shell.qml`, sync to the VM, screenshot, confirm it shows a workspace number with no errors referencing `Caelestia.Internal` or `Caelestia.Blobs`, then revert.

- [ ] **Step 6: Commit**

```bash
git add .configs/quickshell/noctis/services/ .configs/quickshell/noctis/utils/
git commit -m "Vendor services/utils, strip native-plugin-only keyboard state from Hypr"
```

---

### Task 5: Vendor the bar module itself

**Files:**
- Create: `.configs/quickshell/noctis/modules/bar/Bar.qml`
- Create: `.configs/quickshell/noctis/modules/bar/BarWrapper.qml`
- Create: `.configs/quickshell/noctis/modules/bar/components/{OsIcon,Clock,Power,StatusIcons,Tray,TrayItem,ActiveWindow}.qml`
- Create: `.configs/quickshell/noctis/modules/bar/components/workspaces/{ActiveIndicator,OccupiedBg,SpecialWorkspaces,Workspace,Workspaces}.qml`
- Create: `.configs/quickshell/noctis/modules/bar/components/status/{BatteryStatus,BluetoothStatus,LockStatus}.qml`
- Create: qmldir files for `modules/bar`, `modules/bar/components`, `modules/bar/components/workspaces`, `modules/bar/components/status`

**Interfaces:**
- Produces: `Bar` component (`ColumnLayout`) requiring `screen: ShellScreen`, `screenState`, `popouts`, `fullscreen: bool`; exposes `closeTray()`, `checkPopout(y)`, `handleWheel(y, angleDelta)`. `BarWrapper` component requiring the same props, exposing `contentWidth` (int) — Task 7's window host instantiates `BarWrapper` directly.
- Consumes: `qs.config`, `qs.components`, `qs.components.effects`, `qs.services`, `qs.utils` (Tasks 2-4).

- [ ] **Step 1: Fetch the bar module files**

```bash
SHA=27faa5cf95299c2eaa31848ccd78e746d6eef4ed
BASE="https://raw.githubusercontent.com/caelestia-dots/shell/$SHA/modules/bar"
D=.configs/quickshell/noctis/modules/bar
mkdir -p "$D/components/workspaces" "$D/components/status"

curl -sL "$BASE/Bar.qml" -o "$D/Bar.qml"
curl -sL "$BASE/BarWrapper.qml" -o "$D/BarWrapper.qml"

for f in OsIcon Clock Power StatusIcons Tray TrayItem ActiveWindow; do
  curl -sL "$BASE/components/$f.qml" -o "$D/components/$f.qml"
done
for f in ActiveIndicator OccupiedBg SpecialWorkspaces Workspace Workspaces; do
  curl -sL "$BASE/components/workspaces/$f.qml" -o "$D/components/workspaces/$f.qml"
done
for f in BatteryStatus BluetoothStatus LockStatus; do
  curl -sL "$BASE/components/status/$f.qml" -o "$D/components/status/$f.qml"
done
```

- [ ] **Step 2: Apply the mechanical import edit across the whole bar tree**

```bash
grep -rl "import Caelestia.Config" .configs/quickshell/noctis/modules/bar/ | \
  xargs sed -i 's/^import Caelestia\.Config$/import qs.config/'
```

- [ ] **Step 3: Remove the excluded-screens check in BarWrapper.qml**

Open `.configs/quickshell/noctis/modules/bar/BarWrapper.qml`. The `disabled` property calls `Strings.testRegexList(Config.bar.excludedScreens, screen.name)` — leave this as-is (it's vendored `Strings.qml` from Task 4, and `Config.bar.excludedScreens` is `[]` from Task 2, so `disabled` will always evaluate `false`). No edit needed here; this step just confirms that chain resolves rather than assuming it — check `.configs/quickshell/noctis/utils/Strings.qml` contains a `testRegexList` function after Task 4; if it doesn't (naming differs at the pinned commit), add this to the bottom of `Config.qml`'s `bar` object instead: change `excludedScreens` handling isn't needed since an empty list passed to any reasonable regex-list-test implementation returns false for "no match" — verify by reading the fetched `Strings.qml` before deciding whether an edit is required.

- [ ] **Step 4: Verify the bar module resolves standalone**

Write the qmldir files (same generation pattern as Task 3/4, adjusted paths, with `module qs.modules.bar`, `module qs.modules.bar.components`, `module qs.modules.bar.components.workspaces`, `module qs.modules.bar.components.status`). Temporarily wire `Bar` into `shell.qml`'s `PanelWindow` with dummy `screenState`/`popouts`/`fullscreen: false` values (a plain `QtObject` stand-in for `screenState` is fine for this smoke test — Task 7 wires the real one), sync to the VM, screenshot, and confirm the bar renders (workspaces, clock, tray, power button visible) with no QML errors. This is the first task where the actual visual result becomes visible — compare the screenshot against caelestia's published screenshots/README media informally; exact tuning happens in Task 10.

- [ ] **Step 5: Commit**

```bash
git add .configs/quickshell/noctis/modules/bar/
git commit -m "Vendor caelestia bar module components (pinned commit)"
```

---

### Task 6: Author a minimal popout flyout (hand-written, not vendored)

**Files:**
- Create: `.configs/quickshell/noctis/modules/bar/popouts/Wrapper.qml`
- Create: `.configs/quickshell/noctis/modules/bar/popouts/qmldir`

**Interfaces:**
- Produces: `Wrapper` component with `property bool hasCurrent`, `property string currentName`, `property real currentCenter` — these are the exact property names `Bar.qml` (vendored in Task 5) already reads/writes via `popouts.hasCurrent`, `popouts.currentName`, `popouts.currentCenter`, so no edits to `Bar.qml` are needed to consume this.
- Consumes: `qs.components`, `qs.config`.

This intentionally does NOT reproduce caelestia's popout system — their `Wrapper.qml` imports `qs.modules.nexus` and `qs.modules.windowinfo`, both out of scope for Phase 1 (see plan header and spec). This is a small self-contained flyout showing plain text content instead.

- [ ] **Step 1: Write the popout Wrapper**

Create `.configs/quickshell/noctis/modules/bar/popouts/Wrapper.qml`:

```qml
import QtQuick
import qs.components
import qs.config

Item {
    id: root

    required property var screen
    property bool hasCurrent: false
    property string currentName: ""
    property real currentCenter: 0

    readonly property string content: {
        switch (currentName) {
        case "statusIcons": return "Status";
        case "tray": return "Tray";
        case "activeWindow": return "Window";
        default: return currentName.startsWith("traymenu") ? "Tray item" : "";
        }
    }

    StyledRect {
        id: flyout
        visible: root.hasCurrent
        x: -width - Tokens.spacing.small
        y: Math.max(0, root.currentCenter - height / 2)
        width: 160
        implicitHeight: label.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.radius.medium
        color: "#2a2a2a"

        StyledText {
            id: label
            anchors.centerIn: parent
            text: root.content
            color: "white"
        }
    }
}
```

- [ ] **Step 2: Write the qmldir**

Create `.configs/quickshell/noctis/modules/bar/popouts/qmldir`:

```
module qs.modules.bar.popouts
Wrapper 1.0 Wrapper.qml
```

- [ ] **Step 3: Verify the popout renders on click**

Wire `BarPopouts.Wrapper` (`import qs.modules.bar.popouts as BarPopouts`) into the temporary test harness in `shell.qml` alongside `Bar` from Task 5, pass it as `Bar`'s `popouts` property, sync to the VM, click the tray icon via a test input event or `wtype`/manual VM interaction, screenshot, and confirm a small flyout box appears to the left of the bar with placeholder text. If clicking isn't practically testable headlessly on the VM, instead temporarily hardcode `hasCurrent: true, currentName: "tray"` directly in the `Wrapper` instantiation for this verification screenshot, then revert the hardcode.

- [ ] **Step 4: Commit**

```bash
git add .configs/quickshell/noctis/modules/bar/popouts/
git commit -m "Add minimal hand-written popout flyout for the bar"
```

---

### Task 7: Author the window host and wire the real shell.qml

**Files:**
- Create: `.configs/quickshell/noctis/modules/bar/BarWindow.qml`
- Modify: `.configs/quickshell/noctis/shell.qml` (replace the Task 1 scaffold content entirely)

**Interfaces:**
- Consumes: `BarWrapper` (Task 5), `Wrapper` popouts (Task 6), `Hypr` (Task 4).
- Produces: the real `shell.qml` entrypoint — nothing later depends on further exports from this task; it's the top of the tree.

- [ ] **Step 1: Write BarWindow.qml**

Create `.configs/quickshell/noctis/modules/bar/BarWindow.qml`:

```qml
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.modules.bar.popouts as BarPopouts

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    readonly property QtObject screenState: QtObject {
        property bool bar: true
    }
    readonly property BarPopouts.Wrapper popouts: popouts

    WlrLayershell.namespace: "noctis-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Auto
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true

    implicitWidth: Tokens.sizes.bar.innerWidth + Config.border.thickness * 2

    BarPopouts.Wrapper {
        id: popouts
        screen: root.screen
    }

    BarWrapper {
        anchors.fill: parent
        screen: root.screen
        screenState: root.screenState
        popouts: root.popouts
        fullscreen: false
    }
}
```

Note: `screenState` here is a plain `QtObject` stand-in (`bar: true` always) rather than caelestia's reactive `ShellState.forScreen(screen)` — Phase 1's bar is always persistent (matching Waybar's always-visible behavior), so no per-screen hover/auto-hide state is needed yet. `BarWrapper`'s `shouldBeVisible` check already reads `Config.bar.persistent` (`true` from Task 2), so this is enough to keep the bar always shown regardless of `screenState.bar`.

- [ ] **Step 2: Add the qmldir entry**

Append to `.configs/quickshell/noctis/modules/bar/qmldir` (created in Task 5): `BarWindow 1.0 BarWindow.qml`.

- [ ] **Step 3: Replace shell.qml with the real entrypoint**

Replace the entire contents of `.configs/quickshell/noctis/shell.qml`:

```qml
import QtQuick
import Quickshell
import qs.modules.bar

ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens

        BarWindow {}
    }
}
```

- [ ] **Step 4: Full end-to-end verification on the VM**

Sync the full `.configs/quickshell/noctis/` tree, run `qs -c noctis`, screenshot. Confirm: bar renders on the left edge, spans full screen height, no QML errors in the log, workspace switching (`hyprctl dispatch workspace 2` via `qm guest exec`) updates the workspace indicator live, and clicking/hovering tray or status icons triggers the Task 6 popout flyout.

- [ ] **Step 5: Commit**

```bash
git add .configs/quickshell/noctis/modules/bar/BarWindow.qml .configs/quickshell/noctis/shell.qml
git commit -m "Wire real shell.qml entrypoint with per-screen bar window"
```

---

### Task 8: Wallust color template for the shell

**Files:**
- Create: `.configs/wallust/templates/colors-quickshell.qml`
- Modify: `.configs/wallust/wallust.toml`
- Create: `.configs/quickshell/noctis/config/qmldir` entry for the generated `Colours` singleton (target path, not a repo file)

**Interfaces:**
- Produces: `Colours` singleton (generated at `~/.config/quickshell/noctis/config/Colours.qml` by wallust, not checked into the repo) with `.background`, `.foreground`, `.color0`-`.color15` string properties. Task 5's vendored components reference a `Colours` service by this name in caelestia's original source — confirm via `grep -rn "Colours\." .configs/quickshell/noctis/modules .configs/quickshell/noctis/services` which exact property names are actually used before finalizing this template, and match them.

- [ ] **Step 1: Check which Colours properties the vendored code actually reads**

```bash
grep -rhoE "Colours\.[a-zA-Z0-9_.]+" .configs/quickshell/noctis/modules .configs/quickshell/noctis/services .configs/quickshell/noctis/components | sort -u
```

Expected output is a list like `Colours.background`, `Colours.tPalette.m3primary`, etc. Caelestia's real `Colours` service exposes a much richer Material-You token palette (`tPalette.*`) that our simple wallust-generated singleton won't have. For every `Colours.tPalette.*` reference found, replace it in the vendored file with the nearest plain wallust color (e.g. `Colours.tPalette.m3primary` → `Colours.color4`, `Colours.tPalette.m3surface` → `Colours.background`) — record the exact substitutions made as a comment at the top of this task's commit so Task 10's visual tuning pass can revisit the mapping.

- [ ] **Step 2: Write the wallust template**

Create `.configs/wallust/templates/colors-quickshell.qml` (native Jinja2 double-brace syntax — this file is a QML object literal with real braces, same reasoning as `gtk.css`/`colors-hyprland.lua` earlier this session):

```qml
pragma Singleton
import QtQuick

QtObject {
    readonly property string background: "{{ background }}"
    readonly property string foreground: "{{ foreground }}"
    readonly property string color0: "{{ color0 }}"
    readonly property string color1: "{{ color1 }}"
    readonly property string color2: "{{ color2 }}"
    readonly property string color3: "{{ color3 }}"
    readonly property string color4: "{{ color4 }}"
    readonly property string color5: "{{ color5 }}"
    readonly property string color6: "{{ color6 }}"
    readonly property string color7: "{{ color7 }}"
    readonly property string color8: "{{ color8 }}"
    readonly property string color9: "{{ color9 }}"
    readonly property string color10: "{{ color10 }}"
    readonly property string color11: "{{ color11 }}"
    readonly property string color12: "{{ color12 }}"
    readonly property string color13: "{{ color13 }}"
    readonly property string color14: "{{ color14 }}"
}
```

- [ ] **Step 3: Register the template in wallust.toml**

Open `.configs/wallust/wallust.toml`, add under the native-Jinja2 templates section (alongside `hyprland`/`gtk`/`gtk4`):

```toml
quickshell = { template = "colors-quickshell.qml", target = "~/.config/quickshell/noctis/config/Colours.qml" }
```

- [ ] **Step 4: Add Colours to the config qmldir**

Open `.configs/quickshell/noctis/config/qmldir` (from Task 2) and add: `singleton Colours 1.0 Colours.qml` — note this file is generated by wallust at runtime, not present in the repo; document this with a comment-style README note if the repo has a convention for that (check `.gitignore` for how other wallust-generated targets like `colors-waybar.css` are excluded, and add the same exclusion pattern for `Colours.qml` if one exists for generated theme files).

- [ ] **Step 5: Verify wallust generates the file correctly on the VM**

```bash
qm guest exec 115 -- bash -c 'wallust run ~/Pictures/wallpapers/<any-existing-wallpaper> 2>&1'
qm guest exec 115 -- bash -c 'cat ~/.config/quickshell/noctis/config/Colours.qml'
```
Expected: a valid QML file with real hex colors substituted in (not literal `{{ background }}` text), no wallust template errors. Then re-run `qs -c noctis` and confirm the bar renders using the wallpaper's palette instead of the Task 2 hardcoded gray, and re-verify a second wallpaper switch re-themes it live.

- [ ] **Step 6: Commit**

```bash
git add .configs/wallust/templates/colors-quickshell.qml .configs/wallust/wallust.toml .configs/quickshell/noctis/config/qmldir
git commit -m "Add wallust-generated Colours singleton for the Quickshell bar"
```

---

### Task 9: System integration — startup, packages, retire Waybar

**Files:**
- Modify: `.configs/hypr/startup.lua`
- Modify: `profiles/base/full.toml`
- Modify: `profiles/base/minimal.toml` (if Waybar/Quickshell is expected there too — check current `waybar` presence in this file first)
- Delete: `.configs/waybar/`

**Interfaces:** None — this is pure system wiring, no QML interfaces.

- [ ] **Step 1: Check where waybar currently appears in profiles**

```bash
grep -rn "waybar" profiles/ .configs/hypr/
```

- [ ] **Step 2: Swap the startup exec-once**

Open `.configs/hypr/startup.lua`, find the line launching `waybar` (likely `hl.env(...)`/`exec-once`-equivalent Lua call — match the existing pattern used for other exec-once entries in this file), and replace the command with `qs -c noctis`. Keep the same invocation style (background `&`, restart-on-crash wrapper, etc.) as whatever pattern the file already uses for other autostart entries.

- [ ] **Step 3: Update package profiles**

In every `profiles/*.toml` file where `grep` (Step 1) found `waybar`, remove that line. Confirm the `quickshell` package line added in Task 1 Step 2 is present in each of those same files (add it to any file that had `waybar` but is missing `quickshell`).

- [ ] **Step 4: Verify no other file references the retiring Waybar config**

```bash
grep -rln "waybar" --include="*.lua" --include="*.sh" --include="*.toml" --include="*.md" . | grep -v "docs/superpowers"
```
Review each hit; update or leave as historical (e.g. CLAUDE_ROADMAP.md changelog entries can stay, since they're historical record, not live config).

- [ ] **Step 5: Delete the Waybar config directory**

```bash
git rm -r .configs/waybar/
```

- [ ] **Step 6: Full reinstall smoke test on the VM**

Run the VM's install flow (or the relevant subset — package install + config sync) fresh, confirm Quickshell autostarts on Hyprland login with no Waybar process running, screenshot the resulting desktop.

- [ ] **Step 7: Commit**

```bash
git add -A -- .configs/hypr/startup.lua profiles/ .configs/waybar
git commit -m "Retire Waybar: launch Quickshell bar on Hyprland startup"
```

---

### Task 10: Visual tuning pass and final verification

**Files:**
- Modify: `.configs/quickshell/noctis/config/Tokens.qml` (values only)
- Modify: `.configs/quickshell/noctis/config/Config.qml` (values only)
- Modify: `.configs/quickshell/noctis/modules/bar/popouts/Wrapper.qml` (if the placeholder popout content needs adjusting)

**Interfaces:** None — value-only tuning, no shape changes.

- [ ] **Step 1: Side-by-side screenshot comparison**

On the VM, capture a screenshot of the running Quickshell bar. Compare against caelestia-dots/shell's published screenshot (linked from their README) and against this repo's own pre-migration Waybar screenshots (`assets/swappy-20260819_162846.png`). Note concrete deltas: spacing, icon sizes, colors, corner radius.

- [ ] **Step 2: Adjust Tokens.qml/Config.qml values to close the gaps**

Make targeted numeric edits only (no structural changes) based on Step 1's notes. Re-sync and re-screenshot after each adjustment round.

- [ ] **Step 3: Functional smoke test checklist**

On the VM, verify each: workspace switching updates the indicator; active window title updates on focus change; tray shows at least one real icon (e.g. network manager applet) and expands on click; clock displays correct time; battery/bluetooth status icons reflect real VM state (or gracefully show a default if the VM lacks that hardware); power button click triggers its bound action; wallpaper switch re-themes the bar within a few seconds.

- [ ] **Step 4: Final commit**

```bash
git add .configs/quickshell/noctis/
git commit -m "Tune Quickshell bar tokens/config after live VM testing"
```

## Self-Review Notes

- **Spec coverage:** every Phase 1 bar sub-component (logo, workspaces, activeWindow, tray, clock, statusIcons, power, popouts) has a task. Colors (Task 8), system integration/retirement (Task 9), and VM verification (every task's final step, plus Task 10) are all covered. The "not vendoring the native plugin" and "not vendoring nexus/windowinfo-coupled popouts" constraints from the spec are reflected in Tasks 2 and 6 respectively.
- **Deviation from spec surfaced to user:** the spec's phrase "popout panels" implied vendoring caelestia's popout system; investigation during planning found that system requires the out-of-scope `nexus`/`windowinfo` modules, so Task 6 hand-authors a minimal stand-in instead. Flagged to the user when the plan was presented.
- **Placeholder scan:** all singleton/config files have real, concrete values (Task 2); all fetch commands use exact pinned-commit URLs; no "TBD"/"similar to Task N" patterns.
- **Type consistency:** `Config.bar.entries.values` (Task 2) matches `Bar.qml`'s `root.Config.bar.entries.values.filter(...)` (Task 5, vendored unchanged). `popouts.hasCurrent`/`currentName`/`currentCenter` (Task 6) match what vendored `Bar.qml` (Task 5) already reads/writes. `BarWrapper`'s required props (`screen`, `screenState`, `popouts`, `fullscreen`) match exactly what `BarWindow.qml` (Task 7) passes in.
