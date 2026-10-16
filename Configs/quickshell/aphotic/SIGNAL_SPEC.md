line states and tones
idle, active, warn; hairline halves, gap, hover segment, accent segment.

spacing scale
use Tokens.spacing.* and Tokens.padding.*; no new literal spacing.

type scale
use Tokens.font.label/body/title/headline; no new literal sizes.

corners
Tokens.rounding.* and BarLayout.cornerRadius; pill and square stay a preference.

interaction
hover brightens the edge or raises the surface, press is a short inset, keyboard focus shows the signal line. State that Interact is the component that will own this behaviour.

icon weight
thin-stroke, no filled weight except selected or active.

motion budget
finite effects only, Motion.duration for durations, RenderGate.decorative and Motion.reducedMotion gate decorative motion, SignalLine changes stay at or below 12 Hz.

reference surface
Configs/quickshell/aphotic/modules/bar/BarWrapper.qml as the full bar, and Configs/quickshell/aphotic/modules/bar/popouts/AudioPopout.qml as the paired popout. Name the exact properties the popout demonstrates: signal hairline, signal hover, accentLine, Tokens.spacing.medium, Tokens.rounding.medium.