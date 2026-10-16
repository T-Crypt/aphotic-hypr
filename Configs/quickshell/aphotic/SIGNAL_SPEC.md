# Signal spec

## Line states and tones

- Use idle, active and warn to set the signal line tone from `Colours.signalStyle`.
- Draw the base hairline as two 1px halves that open around a centered gap.
- Draw the hover segment as a separate highlight along the same edge.
- Draw the accent segment as the active indicator for the selected or engaged entry.
- Set the accent to 2px and round its ends.
- Let `SignalLine` own the geometry for the hairline halves, the gap, the hover segment and the accent segment.

## Spacing scale

- Use `Tokens.spacing.*` and `Tokens.padding.*` for every margin, gap and inner padding.
- The current steps are extraSmall, small, medium, large, largeIncreased, extraLarge, extraLargeIncreased and extraExtraLarge.
- Do not add inline spacing or padding values in QML.

## Type scale

- Use `Tokens.font.label`, `Tokens.font.body`, `Tokens.font.title` and `Tokens.font.headline` for text roles.
- Use `Tokens.font.mono` only for code and command output.
- Do not add inline font sizes.

## Corners

- Use `Tokens.rounding.*` for component corners and `BarLayout.cornerRadius` for the bar strip.
- `Tokens.rounding.full` carries the pill shape.
- Keep pill, soft and sharp as a global bar setting through `Settings.barCorners`, not a per-surface choice.

## Interaction

- Let `Interact` own hover, press and keyboard focus on signal surfaces.
- Hover brightens the edge or raises the surface.
- Press is a short inset that returns to the resting state on release.
- Keyboard focus shows the signal line as the focus indicator.
- A disabled surface takes no hover, press or focus treatment.

## Icon weight

- Use a thin stroke for icons on signal surfaces.
- Do not use a filled weight except for the selected or active state.
- `MaterialIcon` stays in place until the icon ticket lands. The icon set that replaces it must meet this stroke rule.

## Motion

- Use finite effects only.
- Use `Motion.duration` for every duration.
- Gate decorative motion on `RenderGate.decorative` and `Motion.reducedMotion`.
- Keep signal line changes at or below 12 Hz.

## Reference surface

- `Configs/quickshell/aphotic/modules/bar/BarWrapper.qml` is the full-bar reference. It uses `SignalSurface` with `tone: Colours.signalStyle.bar`, and `SignalLine` with the existing `gapLength`, `activeStart`, `activeLength`, `hoverStart`, `hoverLength` and `hoverVisible` bindings.
- `Configs/quickshell/aphotic/modules/bar/popouts/AudioPopout.qml` is the paired popout reference. It demonstrates the row hover treatment through `Colours.signalStyle.hover`, the active accent through `Colours.signalStyle.accentLine`, and surface spacing through `Tokens.spacing.medium` and `Tokens.rounding.medium`.

The spec still needs operator sign-off on a live desktop.
