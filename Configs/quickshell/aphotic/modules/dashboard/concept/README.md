# Dashboard concept (ticket QJX858H)

The recommended concept, "Signal Spine", lives here as a working prototype:

- `ConceptPulse.qml` -- the surface: clock resolving out of noise, the
  machine's terrain above the spine, the day's leaves below it.
- `PulseTerrain.qml` -- the canvas that draws CPU history as a ridge,
  memory as a rising fill and network as a thin bright line.
- `ConceptProbe.qml` -- the offscreen render probe. It copies to the
  config root at run time because `qs -p` resolves `qs.*` imports only
  from the config root.

Nothing here is wired into the live dashboard. The leaves
(`DashMedia`, `DashPomodoro`, `DashQuickToggles`, `DashCalendar`) are the
existing dashboard widgets, reused unmodified, so this concept rides
along with any token or copy pass made to those files.

## Running the probe

From `Configs/quickshell/aphotic/`:

```sh
cp modules/dashboard/concept/ConceptProbe.qml ConceptProbeRun.qml
QT_QPA_PLATFORM=offscreen \
  HOME=/tmp/opencode/concept-home \
  CONCEPT_W=1920 CONCEPT_H=1080 CONCEPT_MS=14000 \
  CONCEPT_OUT=/tmp/opencode/concept-1920x1080.png \
  qs -p ConceptProbeRun.qml
rm ConceptProbeRun.qml
```

`HOME` points at a throwaway directory holding copies of
`~/.local/state/aphotic/palette.json`, `settings.json` and
`~/.config/awww/current-wallpaper`, so the probe renders the operator's
real dark palette over their wallpaper (plus the 0.35 dim layer, the
same composition the dashboard window uses) without touching the real
files. `CONCEPT_OPEN_DELAY=500 CONCEPT_MOTION_MS=150` grabs a frame
mid-entrance instead. The staged files are copies made at run time and
the originals are only ever read.

Run it a second time with `CONCEPT_W=3440 CONCEPT_H=1440` for the
ultrawide render. The CPU ridge grows one sample per service poll while
the surface is open, so a longer `CONCEPT_MS` draws more terrain; the
grab happens once, then the probe quits.

The signal-text clock needs `shaders/signal.frag.qsb`, which installs
build from `shaders/signal.frag`. On a checkout without it the clock
falls back to plain text by design. To preview the real effect locally,
build the shader (same command `lib/install/config_deploy.sh` uses) and
do not commit the result:

```sh
/usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 \
  -o shaders/signal.frag.qsb shaders/signal.frag
```

The probe renders with real service data. With no network fetch or no
players running, the weather leaf and the media leaf show their honest
empty states rather than invented numbers.
