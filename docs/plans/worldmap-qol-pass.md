# World map QoL pass

2026-09-04. A small quality-of-life pass over the world map's clouds, cast
shadows, and standing structures, raised after looking at the current
render: clouds read as a mechanical grid, cast shadows are effectively
invisible in normal use, and standing structures anchor at their painted
foot rather than their tile. This is not a new subsystem -- clouds, cast
shadows, and standing structures all already exist and are individually
correct by their own probes; this cycle changes defaults, distribution, and
one anchor point, not the mechanisms underneath them.

**Single-session cycle.** Every item below touches `docs/WORLDMAP_DESIGN.md`,
in different sections of the same file, so parallel waves would collide on
that one path for no real concurrency gain. Items run in order, one commit
each, in one session. See `docs/plans/README.md`, "Single-session cycles".

## Outcome

- Clouds scatter without a visible rectangular pattern and drift as
  independent bodies rather than one rigid sheet.
- A structure's cast shadow is visible the moment it stands up, with no
  second slider hunt, and a house's shadow is as legible as a tower's.
- A standing structure renders centered on its own map tile, not anchored to
  the bottom edge of whatever pixel box the extractor found.

## Present-state facts an executing agent must not "fix"

- The cast-shadow mask mechanism is already correct: `probe_shadows.gd`
  passes (feet planted at every hour checked, mask values binary, no
  double-darkening on crossing shadows). QOL-2 and QOL-4 change a default and
  a legibility floor, not this mechanism.
- The cloud lattice's coverage guarantee -- "any window of roughly one cell
  contains a cloud," so the sky never reads as covered while nothing is on
  screen -- is a property to preserve under a new distribution, not a
  justification to keep the grid. QOL-1 replaces the distribution; the
  guarantee still has to hold.
- Only two cloud shapes exist in `WorldMapCloudCatalog` (`temp2`'s two
  pieces). That is an art-asset limit. Do not invent a third shape or treat
  the two-shape repetition at high counts as this cycle's bug.
- `face` and `gain` billboard modes agree to 0.00 px by construction (same
  base, same width, same forced h/w -- see `WORLDMAP_DESIGN.md` §9). QOL-3
  changes the model origin; this agreement must survive that change.

## Items

### QOL-1 -- Golden-ratio cloud scatter, independent drift

**Model:** Opus 5 / GPT Sol

**Model rationale:** Revises a measured, documented placement algorithm
(the jittered lattice in `WorldMapCloudField`) and must preserve its
no-empty-sky coverage guarantee under a genuinely different distribution --
a judgment call on the formulation and on where it could regress, not a
mechanical substitution.

**Touches:**
- `src/presentation/worldmap/WorldMapCloudField.gd`
- `debug/worldmap/probe_cloud_field.gd`
- `docs/WORLDMAP_DESIGN.md` §12

**End state:** Cloud positions show no rectangular or grid-aligned pattern
at any tested seed or count. Each cloud carries its own drift phase and a
speed multiplier (roughly 0.85x-1.15x) so the field does not move as one
rigid sheet. Piece shape is chosen per cloud from the seed rather than by
alternating cell parity. The field still never leaves the visible sky
measurably empty at the shipped count.

**Implementation:** Replace `_lattice()` + per-cell jitter with the golden
ratio's 2D low-discrepancy generalization -- the R2 (Roberts) sequence, built
from the plastic number -- for cloud placement within the field extent. Its
prefixes are well-distributed for any N, which also replaces the separate
shuffled reveal order used today for the count slider. Use the literal golden
ratio conjugate (0.6180339887) as the 1D additive-recurrence step for each
cloud's per-cloud phase, speed multiplier, and piece selection, keyed off the
existing seed so placement stays deterministic and reproducible.

**Risk:** Low-discrepancy is a long-run guarantee, not a hard minimum-spacing
one for small N -- a low shipped count (6) or the field's wrap margin could
clump worse than the lattice's cell-sizing prevented. Check specifically at
count 6 and near capacity (15 for temp2).

**Validation:**
- Self-contained: extend `probe_cloud_field.gd` with a grid-detection check
  (e.g. nearest-neighbour offset variance across a seed sweep) that fails
  against the old lattice and passes against the new scatter; re-run the
  existing parallax/shadow-linearity/continuity checks to confirm they still
  hold against the new positions.
- Deferred: look at the field at count 6 and count 15 at Tile-Exact and
  Curved Close -- confirm no rectangular pattern and no overlap regression
  from the lattice's spacing guarantee.

### QOL-2 -- Fix the shadow-strength default-off trap

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A single default-value change with a stated end state
and no new mechanism -- mechanical, single-file work.

**Touches:**
- `src/presentation/worldmap/WorldMapGroundUniforms.gd`
- `docs/WORLDMAP_DESIGN.md` §10

**End state:** `K_SHADOW_STRENGTH` in `WorldMapGroundUniforms.DEFAULTS` ships
at a non-zero value (0.5, matching the value already validated by
`probe_shadows.gd`), so a structure casts a visible shadow as soon as it
stands up, without a second, unrelated slider needing to be found first.

**Implementation:** One constant change, the same fix already applied once
in this file to `light_tint` for the identical failure mode (a control that
silently depends on another control the user has no reason to know about).

**Risk:** None of substance -- a non-zero shadow strength against an empty
mask (no structures standing, or the sun down) still renders nothing, so
every framing with `billboard: off` is visually unaffected.

**Validation:**
- Self-contained: confirm via `probe_shadows.gd` (already exercises the
  mask at a chosen strength) that the new default produces the same
  passing result it does today at 0.55, adjusted for 0.5.

### QOL-3 -- Center standing structures on their tile cell

**Model:** Opus 5 / GPT Sol

**Model rationale:** Reverses a documented, deliberate design decision (the
foot-anchor in `WorldMapProps._buildSprites()`, kept specifically so the
`gain`/`face` billboard math pivots from a planted base) and must confirm the
`face`/`gain` 0.00 px agreement survives feeding the billboard math a
different origin -- a boundary judgment, not a mechanical move of a position
line. Confirmed with the user: "centered" means the structure's render
position snaps to the center of its own map tile, on both axes, not merely
to the center of its own detected pixel footprint.

**Touches:**
- `src/presentation/worldmap/WorldMapProps.gd`
- `debug/worldmap/probe_props.gd`
- `docs/WORLDMAP_DESIGN.md` §9

**End state:** A structure's rendered position is the center of the map
tile its footprint's centroid falls in -- computed from the region's own
`tile_pixels`, not the raw detected bounding box -- on both the across and
depth axes. `probe_props.gd`'s existing aspect-error results (`gain`/`face`
at 1.2% worst, agreeing to each other) are unchanged.

**Implementation:** From the structure's footprint centroid in map pixels,
floor by the region's `tile_pixels` to get a tile index on each axis, then
re-center the sprite's world position at `(index + 0.5) * tile_pixels`
(converted to world units the way `_buildSprites()` already does). Rewrite
§9's "Anchored at its FOOT" note to record the new anchor and why -- the
reasoning that motivated the foot-anchor (keeping billboard math pivoting
from a planted base) still has to hold; state how the tile-center origin
satisfies it.

**Risk:** A structure wider than one tile (some `temp2` houses are close to
1.4 tiles) will center on the tile its centroid falls in rather than its own
full extent, which can read as a small lateral shift from where it was
painted. Confirm this reads as an improvement rather than a new artifact
before calling the item done.

**Validation:**
- Self-contained: extend `probe_props.gd` with a centering assertion
  (rendered position equals the expected tile-center for every structure)
  alongside its existing aspect-error check.
- Deferred: visual check that towers and houses read as standing on their
  own plot rather than floating off it, at Tile-Exact and Curved Close.

### QOL-4 -- Give short structures' shadows a legibility floor

**Model:** Opus 5 / GPT Sol

**Model rationale:** A tuning judgment that trades physical accuracy (a
short building casts a short shadow) for legibility at the shipped render
scale -- the same category of measured tradeoff `shadow_spread` and
`sun_low`'s flattening already made in this file, not a mechanical change.

**Depends on:** QOL-2 (both touch `docs/WORLDMAP_DESIGN.md` §10; QOL-4 runs
after so its doc edit lands against QOL-2's, not in conflict with it).

**Touches:**
- `src/presentation/worldmap/WorldMapShadowMask.gd`
- `debug/worldmap/probe_shadow_look.gd`
- `docs/WORLDMAP_DESIGN.md` §10

**End state:** A house's cast shadow is legible at the shipped render scale
and render presets, not only a tower's -- measured, not merely asserted by
eye.

**Implementation:** To be settled by measurement during the item, in the
same spirit as `shadow_spread`'s derivation: likely a minimum shadow length
independent of caster height, or a per-kind spread floor keyed off
`s["kind"]`. Keep the "measured, not chosen by eye" discipline the rest of
this file already uses -- record the comparison that decided it.

**Risk:** Overcorrecting makes a short shadow look pasted on rather than
cast, the same failure mode `shadow_spread` was tuned to avoid on the other
side.

**Validation:**
- Deferred: compare house vs. tower shadow legibility before and after, at
  08:00 / 12:00 / 16:00, at the render scale the shipped presets use.

## Validation

Folded into QOL-4's session -- it is the last item, and it already owns the
render path (structures, their shadows, at the shipped render scale) every
deferred check above looks at. That session renders the combined result
once, exercises the union of QOL-1 through QOL-4's deferred checks in one
pass, fixes anything the combination surfaces, and records it in QOL-4's
commit.

## Deliberately excluded

- **The close-framing cloud-occlusion issue** (`WORLDMAP_DESIGN.md` §13: a
  native-scale cloud can partly hide a structure at Curved Close rather than
  just shadow it). Still open, and explicitly left to whoever next tunes the
  presets -- not reopened here.
- **A "populated" reference preset** shipping with `billboard` and shadows
  on by default. Worth doing once this cycle lands, but it is a curation
  choice (which preset, which values) rather than a QoL fix, and belongs to
  whoever picks the numbers.
- **A third cloud shape.** Art-asset work, not in scope here.
- **Wiring the world map into actual gameplay.** It remains a debug-scene
  prototype with no caller from game code; this cycle polishes what is
  already there and does not change that.
