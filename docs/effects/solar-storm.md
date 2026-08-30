# Solar Storm

`solar_storm` — a coronagraph panel: an occulting disk with the star's limb ring
behind it, streams fanning out from the occultation, plasma loops on the limb, a
bright ejection front travelling outward, and a broad corona inside the
instrument's circular field of view. Carried by the fire spell of the same name
(radius 3, range 5, 7 damage, `CAN_TARGET_EMPTY`), which is the only spell that
selects it.

The contract and conventions it implements live in
[`../VFX_DESIGN.md`](../VFX_DESIGN.md).

Backfilled 2026-08-30 from the code and nine commits, after the effect had been
shipped for some time with its reasoning living only in commit bodies. Where a
claim here is a measurement, it was re-read from the source rather than copied
from a message.

## The ladder

Solar Storm's versions are **override sets on one effect**, not forked files —
which is why this page is organised by feature rather than one section per
version. Every rung shares a single field, and each earlier rung only switches a
later feature *off*. Forking six copies to compare six values would guarantee
they drift apart under exactly the tuning the comparison exists to inform.

The rungs are an authoring aid, not content: nothing in `data/spells.json`
points at them, and `PROFILE_ID` stays the gameplay entry point on the full
effect.

| rung | profile id | adds | catalog name |
| --- | --- | --- | --- |
| v1 | `solar_storm_v1` | the original lateral wave | Solar Storm v1 (wave) |
| v2 | `solar_storm_v2` | radial pulse, replacing the wave | Solar Storm v2 (pulse) |
| v2.1 | `solar_storm_v2_1` | prominence arches | Solar Storm v2.1 (+loops) |
| v2.2 | `solar_storm_v2_2` | heat wash on the board | Solar Storm v2.2 (+heat) |
| v2.3 | — | flare bloom, **tried and removed** | — |
| v2.4 | `solar_storm` | flame turbulence. The full effect | Solar Storm v2.4 (full) |
| v3 | `solar_storm_v3` | the melt and its falling drops | Solar Storm v3 (melt) |

The gap at v2.3 is deliberate and records that the rung existed. `VFXDebugController`
builds its roster from the catalog, so the rows appear in the dropdown and
resolve from `--effect=` with no harness change. Panel overrides win over a
variant's, so a rung stays tunable rather than frozen.

**One honest gap**, also recorded in the profile: v1 shipped with a sign error
that made the stream splay crawl back toward the occulter — the storm subtly
inhaled — and the v1 row does not restore it. Reproducing an acknowledged bug
would have cost another flag to make the comparison worse.

## A fork, and the first test of the rule that allows it

Forked from Aurora Veil, and the sibling relationship is structural rather than
convenient: identical Y-billboarded quad carrier, identical four-beat timeline
shape, identical pixel snap, wave displacement, radius response, and
depth-resolved model lighting. Only the field is new.

It was the first real test of `VFX_DESIGN.md` §4 after that rule was loosened
from "fork, don't abstract — until the third" to "fork siblings; author
everything else fresh". Aurora Veil, landing in the same commit, was the
author-fresh case; Solar Storm was the fork case.

**The two make opposite anchor choices, for a stated reason.** The veil pins its
anchor in *world units*, because a curtain is a local effect that has to stay
seated on the units it affects. The storm holds a *UV fraction*
(`STORM_ANCHOR` = 0.440, 0.400), because it is a backdrop-scale phenomenon whose
composition is the subject — occulter high, corona blooming down across the
board. A world-unit pin would drag the occulter toward the panel's base as the
panel grows and shear off the entire lower hemisphere.

The occulter is off-centre on purpose, left of the midline and high. A disk dead
centre reads as a targeting reticle rather than an instrument's occultation.

## Timeline

2.10 seconds, longer than the veil's: an ejection needs a visible launch, and
the front's travel is the main event rather than a grade change. Four beats,
with every envelope keyed on the same boundaries and interpolated between them.

| beat | ends at | visibility | front progress | prominence rise |
| --- | --- | --- | --- | --- |
| — | 0.00 | 0.00 | 0.05 | 0.10 |
| ignition | 0.14 | 0.88 | 0.16 | 0.72 |
| launch | 0.42 | 1.00 | 0.55 | 1.00 |
| expansion | 0.78 | 0.86 | 0.94 | 0.88 |
| dissipate | 1.00 | 0.00 | 1.12 | 0.35 |

The front starts **buried at the occulter** (0.05) and is **still climbing past
the panel** (1.12) when the corona begins to fade, so the storm reads as an
ejection leaving rather than a ring pulsing in place. Grain runs the other way —
it outlives the light, 0.60 at the last key, so instrument noise is the last
thing to go.

`SETTLE_NORMALIZED_TIME` is 0.90 and `ACTION_HOLD_FRACTION` 0.46.

## The field

**Streams** are built from summed octaves at incommensurate frequencies, not one
periodic spoke function. A single sine raised to a power can only produce
identical, evenly spaced rays; summing and thresholding gives streams of
genuinely different widths, brightnesses and spacings. `STREAMER_THRESHOLD` is
the parameter to move first — it changes stream width without dimming them,
which exponentiating cannot do.

**Prominences** are three plasma loops, each anchored at two limb points and
modelled as a semi-ellipse in polar space whose radius returns to the limb at
both footpoints. Each loop therefore attaches *by construction* rather than
needing its ends faded. Three at different scales read as a star with activity;
one reads as a decorative arc.

**The ejection front** is narrow and bright (`ARC_WIDTH` 0.028): the source's
loop is filamentary, and widening it turns the storm into a blown-out band.

**The corona** has a deliberately long falloff and a wide field-of-view feather.
The source's red does not stop — it thins across most of the frame before the
instrument's circular boundary takes it.

## Motion: a mirage became an invocation

The inherited lateral wave was replaced with an outward radial pulse. The
sibling's sine wobble is a mirage shimmer — the right motion for a
hallucination and the wrong one for an invocation. The pulse displaces and
brightens along the field's own radial axis with phase
`r * frequency - time * speed`, so fronts propagate from the occulter outward
the way a solar shock does.

Two details this depended on:

- **The polar frame is built from the undisplaced UV.** The displacement is
  defined along that frame's outward direction, so deriving polar afterwards
  would rotate the pulse into a swirl.
- **The brightness half is what reads as energy leaving the star.**
  Displacement alone only nudges geometry. The ejection front is excluded from
  the modulation, since it already travels on its own progress curve.

**Flame turbulence** is applied to the stream field's *angular coordinate only*,
never to the panel UV. UV is where the sibling's wobble lived, and displacing
there is exactly what made it read as a mirage. Confined to the streams, it
ripples their boundaries into fire tongues while the occulter, prominences and
front stay geometrically clean. The turbulence carries the radius as well as the
angle, which shears tongues along each stream's length instead of rocking the
whole fan together.

## Heat wash

Geometry standing under the storm takes its own warm glow, peaking as the
ejection front arrives rather than tracking overall brightness — the board
should feel the arrival, not the ambience. It rides the depth path that already
resolves occlusion, so it costs no extra draw and no extra pass.

Two choices worth keeping:

- **Bounded by the corona's falloff, not by the storm's intensity.** Keyed to
  intensity it appears only under the streams and the front, which scorches the
  board in stripes instead of heating it.
- **The occluded alpha takes the max of the boosted energy and the wash**,
  because the wash would otherwise be invisible wherever the storm's own field
  is faint — which is most of where the board actually is.

## v2.3: the flare bloom, tried and removed

A short whiteout at the launch beat, so the storm had a moment of release rather
than a steady glow. **Removed entirely rather than turned down**: it was too
strong at every setting that still read as a release, which makes it a wrong
idea rather than a mistuned one, and leaving dead machinery behind would only
invite it back.

It is worth recording *why the first attempt failed*, because the lesson
outlives the feature. Every other envelope here is keyed on the beat boundaries
and interpolated linearly between them — so a peak authored at LAUNCH climbs
from 0.14 and decays to 0.78, a swell across two thirds of the cast instead of a
flash. The captures showed the storm blown out at every sampled time. **A spike
needs a width shorter than the gap between beats, which a shared key set cannot
express at all**, so it had to be an analytic gaussian rather than another keyed
curve.

## v3: the melt, reworked into falling drops

v3 keeps the whole v2 feature set and lets the storm sag as it runs instead of
simply fading. `MELT_AMOUNT` is zero on every other rung, so v2.4 is untouched
by its presence.

Three parts make it read as melting rather than sliding: the sag scales with
depth below the occulter, so the field *stretches* instead of translating; it
varies per column (`MELT_COLUMNS` 6), so the underside breaks into drips instead
of a level hem; and the sagged material is biased down the heat ramp, so what
melts also cools and loses its white cores from the bottom up.

It was then reworked from a UV-space sag into **matter that leaves the storm**.
Three drops swell on the underside, pinch off, accelerate down, stretch with
speed, and flatten into a splash at the ground. The sag stays but is reduced to
a slump — the slouch that precedes a drop rather than the whole idea.

This works as fragment maths, at no extra draw call and with no loss of scrub
exactness, **because the panel's base already stands at the target's feet**: the
ground is the quad's own bottom edge and a fall is travel down its vertical
axis. Position, size and timing are hashed from the drop index against the seed,
so a cast drops in different places rather than replaying one arrangement.

Four things this needed that were not obvious:

- **Span is hashed first and start constrained** so `start + span` never exceeds
  one. Hashing them independently let a drop's life end long before the melt
  completed, leaving nothing on screen for the second half, or run past the end
  so it never landed.
- **Drops get their own border vanish that ignores the bottom edge.** The
  storm's protects it from a clipped quad; applied to a drop it erased it
  exactly at the moment it landed.
- **`DROP_RADIUS` has a floor set by the pixel grid, not by taste.** At 0.030 a
  drop was narrower than one cell of the snap and disappeared into it. Anything
  meant to read through the pixelation has to be wider than a cell.
- **Melt progress completes by the end of expansion**, not the last frame. Drops
  draw through `lifecycle_visibility` like everything else, so one still falling
  during dissipation faded out mid-air instead of landing.

## Determinism and budgets

Every value is a pure function of `playback_time` and position; nothing
integrates across frames. That is what lets the effect report exact normalized
seek and lets the debug harness scrub in either direction. **The grain is
animated but still seek-exact**: it hashes a *quantized frame index* derived
from `playback_time`, never a running counter. Adding any frame-accumulated term
to the shader silently breaks scrubbing — put state in the GDScript timeline
instead.

Depth testing is disabled and occlusion resolved in the fragment: where a model
stands in front of the panel the storm goes transparent and lights it rather
than covering it. The mix-blend albedo is solved so one pass is both a field
over the background and an additive light on geometry.

| budget | value |
| --- | --- |
| draw calls | 1 (`MAX_DRAW_CALLS` 1) |
| geometry instances | 1 |
| effect nodes | 2 |
| live instances | 1 — one panel per cast covers the whole footprint |

The panel is 11.0 × 6.0 world units at the reference radius (3 tiles, a 7-tile
diameter) and scales uniformly with the carrier's footprint.

## Corrections

- **The pixel snap is 64 cells across, not 56.** The shader declares
  `pixel_cells = 56.0` as its uniform default, but `SolarStormProfile.PIXEL_CELLS`
  is 64.0 and the effect pushes it every build, so 64 is what runs. The drops
  commit (`6fdfb90`) describes the grid as 56-cell; that figure is the shader
  default it never uses. The `DROP_RADIUS` finding itself stands — a drop
  narrower than one cell vanishes into the snap — only the cell count quoted
  alongside it is the wrong one.
