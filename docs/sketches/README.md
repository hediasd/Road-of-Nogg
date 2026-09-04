# Sketches

Kept design sketches — the small number of debug and exploration artifacts that
stayed useful after the work they were made for shipped.

This is **not** `debug/`. That directory is gitignored, disposable, and holds
whatever a proof harness happened to emit. This one is curated: a file earns a
place here only if someone looking back in six months would learn something
from it that the code and the design notes do not already carry.

## What belongs

- A **motion or timing sketch** that shows *why* an effect moves the way it
  does — an interactive curve, a scrubbable comparison against the version it
  replaced, an annotated beat breakdown.
- A **before/after** that captures a judgement call, where the rejected option
  is as informative as the chosen one.
- A **measurement** that was expensive to produce and is unlikely to be redone.

## What does not

- Proof-harness output. Sheets, yaw sweeps, and determinism captures prove a
  thing once; the commit body records the result.
- Anything a design note already explains in prose. Link the note instead.
- Work-in-progress frames, scratch renders, every iteration of a look. Keep the
  one that settled the question.

The bar is deliberately high. A folder of forty sketches is another `debug/`.

## Conventions

- `YYYY-MM-DD-<subject>-<what-it-shows>.html`, dated the day it settled the
  question rather than the day it was started.
- Self-contained: inline the CSS and JS so the file opens from disk years later
  with no build step and no network. Google Fonts may be linked; everything else
  is embedded.
- Open with one paragraph saying what was being decided and what was decided.
  A sketch nobody can date or attribute is noise.
- Add it here as part of closing a cycle, alongside the merge and the branch
  sweep — see "Plan lifecycle" in `AGENTS.md`.

## Index

| Sketch | Subject | Settled |
| --- | --- | --- |
| [2026-08-28-charge-aura-v1-motion.html](./2026-08-28-charge-aura-v1-motion.html) | Technique charge aura v1 | The bounce/breath/ring-phase motion model, scrubbable against the single wall it replaced. The layered-oscillator house style in `VFX_DESIGN.md` generalises from this; the effect itself is documented in `docs/effects/`. |
| [2026-08-29-charge-aura-v2-spin-and-release.html](./2026-08-29-charge-aura-v2-spin-and-release.html) | Technique charge aura v2 | Spin, per-blade churn, and the three candidate release shapes, with the reasoning behind choosing expand-and-flatten at 1.00s. Also the release-time study, and the correction it produced: measuring the entrance against v2's own churn rather than v1's threshold shows nothing needs to speed up to pay for an early release. |
| [2026-08-29-battle-camera-behaviour-and-opening-framing.html](./2026-08-29-battle-camera-behaviour-and-opening-framing.html) | Battle camera | That yaw 0 is the only resting angle that both faces the enemy and lands on an aiming quadrant, so "behind player 1, facing player 2" needs no new angle invented — only the accidental -11.3 degrees removed. Carries the live angle explorer the opening pitch and zoom get chosen in, the per-moment behaviour tables the camera had no written contract for, and the finding that `BattleCameraDirector.set_enabled()` has no caller, so every documented director behaviour is dead code. Extended with the setup-screen board preview: what an orbiting map behind the menu would cost, and why it is also the cheapest harness for judging the opening angle under the real renderer. |
| [2026-08-31-worldmap-framing-and-tile-scale.html](./2026-08-31-worldmap-framing-and-tile-scale.html) | World map ground rig | That the reference has **no horizon** at all -- the map leaves the top of the frame and the fog never completes -- which ruled out every framing with a fogged horizon line. Carries the live explorer pitch 60 / FOV 25 was derived in, from the ~3:1 near-to-far depth ratio, and the tile count that fixed the scale at ~53 tiles across at ~7.5 buffer px each. Also the finding that outgrew the camera: a region must be `tiles_across x ratio` wide, so the reference framing needs a ~155-tile region and anything smaller shows its plane edges. Pre-stretching the art is rejected here, and the rejected shallow-pitch framings are kept because the argument for pre-stretching died with them. |
| [2026-09-01-worldmap-2p5d-options-rejected.html](./2026-09-01-worldmap-2p5d-options-rejected.html) | World map 2.5D | That the world map stays **flat**. Eleven ways of giving it depth, rendered against the real region art and all rejected: tile extrusion turns organic mountain blobs into a staircase of cubes; tile-grid billboards slice through sprites that are 10-40 px and do not align to 16 px tiles; parallax offset shears rather than lifts and scores below plain contact shadows at a shallow pitch. Also carries the two that came closest and still lost -- normal-map relief from a mask-derived height field, and Pokemon-decomp-style connected-component sprites stood upright -- so the bar they failed to clear is on record. The rejected options are the point of this page. |
| [2026-09-02-worldmap-standing-structures-and-daylight.html](./2026-09-02-worldmap-standing-structures-and-daylight.html) | World map props and daylight | That a squash correction has to be solved PER SPRITE from `f / D`, not from `cos(pitch)` -- the sketch that caught the difference, at 0.33 near vs 0.76 far against a single global factor that would have shipped a wrong 0.931/1.291 aspect at the frame's two ends. Carries the billboard mode comparison (`gain` and `face` converge to 0.00 px of difference), the day/night sun with its narrow northward shadow arc, the map-space hard-edged shadow mask that made procedural shadows look painted, and the subtractive lamp model -- a lamp withholds the night rather than adding light, so it cannot produce a colour the region's art does not contain. Extended with the setup-screen board preview from the camera sketch. |
| [2026-09-04-worldmap-clouds.html](./2026-09-04-worldmap-clouds.html) | World map clouds | That a cloud is a horizontal sprite at altitude riding the ground's own mode-7 pass, so perspective and parallax come for free, and that a cloud shadow is a mask in map-pixel space like the buildings' own. Carries the two art findings that changed the plan: the sheet's 8 px block grid pins the display scale at native (the `Size` slider does not survive it), and each shadow is hand-drawn with its own foreshortening rather than scaled from its cloud (`Spread` does not survive it either). The palette sweep that found the artist's own shadow colours at shade 0.25-0.50 is here, alongside the open finding a sketch could not have shown: at a close framing a single cloud spans 30-50% of the frame. |
