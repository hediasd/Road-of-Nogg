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
| [2026-08-28-charge-aura-v1-motion.html](./2026-08-28-charge-aura-v1-motion.html) | Technique charge aura v1 | The bounce/breath/ring-phase motion model, scrubbable against the single wall it replaced. The layered-oscillator house style in `VFX_DESIGN.md` generalises from this. |
| [2026-08-29-charge-aura-v2-spin-and-release.html](./2026-08-29-charge-aura-v2-spin-and-release.html) | Technique charge aura v2 | Spin, per-blade churn, and the three candidate release shapes, with the reasoning behind choosing expand-and-flatten at 1.00s. Also the release-time study, and the correction it produced: measuring the entrance against v2's own churn rather than v1's threshold shows nothing needs to speed up to pay for an early release. |
| [2026-08-29-battle-camera-behaviour-and-opening-framing.html](./2026-08-29-battle-camera-behaviour-and-opening-framing.html) | Battle camera | That yaw 0 is the only resting angle that both faces the enemy and lands on an aiming quadrant, so "behind player 1, facing player 2" needs no new angle invented — only the accidental -11.3 degrees removed. Carries the live angle explorer the opening pitch and zoom get chosen in, the per-moment behaviour tables the camera had no written contract for, and the finding that `BattleCameraDirector.set_enabled()` has no caller, so every documented director behaviour is dead code. |
