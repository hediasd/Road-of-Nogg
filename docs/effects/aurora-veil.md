# Aurora Veil

`aurora_veil` — an iridescent curtain on a single upright panel: vertical
filaments whose folds shear with height, over a wide veil envelope, pixel-
snapped and wave-displaced. Carried by the darkness spell of the same name
(radius 2, range 4, 4 damage, `CAN_TARGET_EMPTY`), which is the only spell that
selects it.

The contract and conventions it implements live in
[`../VFX_DESIGN.md`](../VFX_DESIGN.md). [Solar Storm](./solar-storm.md) is its
fork, and the two make several deliberately opposite choices — noted below and
on that page.

Backfilled 2026-08-30 from the source and its single commit, after the effect
had shipped with its reasoning living in code comments. Every numeric claim was
re-read from `AuroraVeilProfile.gd`. Two defects found while reading are
recorded at the end.

## The author-fresh case

Aurora Veil is the effect that `VFX_DESIGN.md` §4's fork-vs-fresh rule was
loosened *around*. It landed in the same commit as the rule change and as Solar
Storm, and the two are the rule's worked pair: the veil is the author-fresh
case, the storm is the fork case.

Nothing existing was a structural sibling. The storms are a ground wash plus a
particle field plus a crown on one continuous arc; the implosion runs a
four-beat inward timeline; the encasement wraps a body in solid geometry. This
is a single continuous field on one quad. What it keeps is not code but the
`VfxPlayback` contract: seeded, exactly seekable, budget-asserted.

**It has no particles and no second layer, on purpose.** The reference is a
single continuous field, and splitting it across carriers would only invent
seams the source does not have.

## The carrier

One **Y-axis billboarded** quad standing at the impact centre: the panel keeps
world up and yaws to face the camera. A full billboard would tilt the curtain
with the camera pitch and its filaments would stop hanging — and in the design
that still had the reflection, it would have tilted the waterline seam and
stopped the mirror reading as a reflection at all.

One panel covers the whole footprint from its centre rather than one per body. A
radius-2 area holds several targets, and overlapping additive panels would
compound their grade instead of reading as several auras.

**The panel scales uniformly with the footprint, and non-uniform scaling is
tempting here and wrong.** The field is aspect-corrected, which makes its world
width a product of `ENVELOPE_RADIUS.x` and the panel's *height*, not its width —
so holding height back while widening the quad grows the carrier without growing
the curtain on it. Uniform scale keeps the tuned proportions exactly and makes
the aspect constant at every radius.

**The anchor is pinned in world units, not as a UV fraction** (`ANCHOR_HEIGHT_U`
0.93, `CORE_HEIGHT_U` 0.99, both converted to UV against the live panel height).
Held as fractions they ride the panel upward as it scales, and by radius 5 the
curtain floats clear above the units it is supposed to be affecting.

This is the **exact opposite of [Solar Storm](./solar-storm.md)'s choice**, and
both are right. The veil is a local effect that has to stay seated on the units
it affects; the storm is backdrop-scale, and a world-unit pin would drag its
occulter toward the panel's base and shear off its lower hemisphere. Same
carrier, same fork lineage, opposite decision, because the two are different
kinds of thing.

## Timeline

1.60 seconds over four beats, named for what the veil is doing rather than a
generic onset/decay split. **The hold in `BREATHE` is the phase that reads as
hallucination rather than as a flash** — it is the reason the timeline has four
beats instead of three.

| beat | ends at | visibility | grain |
| --- | --- | --- | --- |
| — | 0.00 | 0.00 | 0.35 |
| intrusion | 0.15 | 0.62 | 1.00 |
| bloom | 0.45 | 1.00 | 1.00 |
| breathe | 0.70 | 0.94 | 1.00 |
| dissolve | 1.00 | 0.00 | 0.55 |

The grain outlives the colour by a short tail (0.55 at the last key) so the veil
leaves an artifact behind rather than simply switching off. `SETTLE_NORMALIZED_TIME`
is 0.92 and `ACTION_HOLD_FRACTION` 0.50.

Curves are sampled at the beat boundaries and interpolated under exact
normalized seek, so the shader receives one scalar rather than four overlapping
envelopes.

## The field

**The colour sweep and the brightness envelope are separate ellipses.**
Collapsing them into one is what makes the field read as a glowing ball instead
of a veil. `BAND_RADIUS` is 0.420 × 0.300, `ENVELOPE_RADIUS` 0.460 × 0.245 —
the latter a deliberate departure from the reference's near-circular envelope,
because a curtain is wider than it is tall.

`ENVELOPE_RADIUS.x` is capped by the panel: the field dies at the quad edge once
it reaches 0.54, so 0.460 leaves margin for `EDGE_FADE`. A clipped edge is the
one failure that announces a panel instantly, which is also why `FIELD_SCALE`
(0.72) shrinks both ellipses together — it buys margin rather than coverage.

**The curtain** is 20 filaments across the panel, cutting into the field at
`CURTAIN_STRENGTH` 0.88, with a fold pair controlling the sheet's lateral
waviness and how much it shears with height. Drift is slow (0.35 turns/sec) so
the curtain breathes rather than scrolls; band drift across the whole cast is
`BAND_DRIFT_TURNS` 0.22 — under one full period, so it never visibly cycles.

**The wave is applied to the sampling coordinate *before* the cell snap**, so
the grid stays locked to the panel and the colour flows through it rather than
the whole grid sliding.

## The colour ramp is authored in sRGB and converted once

Nine stops measured by eye from the reference — pale core, warm midrange,
magenta and violet run, deep blue outer field — held as parallel arrays because
a const array of structs is not portable across Godot's shader backends.

`ALBEDO` is consumed as **linear**. Feeding the sRGB values straight through
lightens and desaturates every stop, which is precisely the pale, washed field
the shader produced before the conversion was added. The conversion happens
once, at the end, *after* grain and black lift have been applied in the space
they were authored in.

## Blending is mix, not add, and only because the veil left the black frame

Over black the two are identical. Added over lit terrain, every hue climbs
toward white and the iridescence turns grey — which is exactly the information
the effect exists to carry. Mixing keeps the ramp's colour on any background.

Depth testing is **disabled** and occlusion resolved in the fragment: where a
model stands in front of the panel the curtain goes transparent and lights it
rather than covering it. That trade is deliberate and it has a cost — it gives
up the reference's composition of a dark silhouette in front of the aura, and
buys the curtain passing over the board as light.

Grain samples `FRAGCOORD` whenever the field is not snapped to cells. On mesh UV
it would magnify as the camera closes and read as painted texture; on FRAGCOORD
it stays pinned to screen pixels and keeps reading as film grain. Once
`pixel_cells` is active that argument inverts and the grain moves onto the cell
grid.

## The reflection, built and then switched off

The reference's lower lobe is a waterline reflection — slightly compressed,
slightly dimmer, horizontally smeared, carrying ripple striations the upper lobe
does not have. All of that is implemented: `LOWER_COMPRESS`, `LOWER_DIM`,
`LOWER_SMEAR`, `SEAM_WIDTH`, `RIPPLE_FREQUENCY`, `RIPPLE_DEPTH`.

**`MIRROR_STRENGTH` is 0.0.** The reference's mirror needs empty space below the
waterline, and a body standing on the ground has none. The compression required
to keep the lower lobe off the floor reduced it to a smear that read as a stray
second blob rather than a reflection.

The machinery is intact rather than deleted, and that is the right call here
precisely because the failure is a property of the *framing*, not of the idea —
raising the constant restores the full reflection for any framing that has room
for it. (Contrast Solar Storm's flare bloom, which was deleted outright because
it was wrong at every setting that still read as a release. A feature that fails
in one context is worth keeping switched off; a feature that fails in all of
them is machinery inviting its own return.)

## Determinism and budgets

Every value is a pure function of `playback_time` and position; nothing
integrates across frames. **The grain is animated but still seek-exact**: it
hashes a *quantized frame index* derived from `playback_time` (`GRAIN_HZ` 12),
never a running counter. Adding any frame-accumulated term to the shader
silently breaks scrubbing — put state in the GDScript timeline instead.

| budget | value |
| --- | --- |
| draw calls | 1 (`MAX_DRAW_CALLS` 1) |
| geometry instances | 1 |
| effect nodes | 2 |
| live instances | 1 — a second copy on the same centre would only double the additive grade |

The panel is 7.0 × 5.8 world units at the reference radius (2 tiles, a 5-tile
diameter), snapped to `PIXEL_CELLS` 56 across, with the vertical count derived
from the panel aspect so cells stay square in world units.

## Defects found while backfilling

Neither is behavioural; both are comments that would mislead a reader.

- **The shader header contradicts itself about depth testing.** Its second
  paragraph says depth is *"written never but still tested, which is deliberate:
  bodies standing in front of the panel occlude it"*, describing the reference's
  silhouette-in-front composition. Three paragraphs later it says depth testing
  is *disabled* and explains the trade that replaced exactly that. The
  `render_mode` line is `depth_test_disabled`, so the later paragraph is the
  true one and the earlier is stale — it survived the change it describes being
  reversed. Fixed in the same commit as this page.
- **`PIXEL_CELLS` is 56 here but the shader's uniform default is 72.** The
  profile value is what runs. This matters beyond the veil: Solar Storm forked
  this shader and its default carries 56 — the veil's *profile* value, not its
  shader default — which is where [that page's](./solar-storm.md) 56-versus-64
  correction originates.
