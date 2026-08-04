# Ice Storm Correction Cycle

**Opened 2026-08-04.** The previous contents of this file were the ice-storm
build cycle, executed across `b189ad8`…`b92ac4e` and emptied at `b92ac4e` when
its final validation item passed. No items were left open, so nothing was moved
to a backlog at that reset. This cycle corrects defects found by reading the
shipped result; it does not revisit settled decisions from that cycle.

**Blocking precondition — resolve with the user before the first item.**
`git status` is not clean:

- `scenes/debug/VFXDebugScene.tscn` is modified. The diff is Godot 4.4
  re-serialization noise (`position` rewritten as `Transform3D`, defaulted
  properties dropped, `2147483647.0` → `2.14748e+09`), not authored work. It
  appears to be an incidental save from opening the scene in the editor.
- `vfx_plan.md` is **untracked**, dated 2026-08-02, and lists every item as "not
  started" while the work it describes shipped under this file. It is a
  superseded draft that was never committed.

Neither is owned by this plan. Do not clean, commit, or delete either without
the user saying which they want. The first executing session asks and then
starts from clean.

---

## 1. Goal

The area ice storm works and is well structured, but four things it claims are
not true:

1. It renders a **square/circular** footprint over a **diamond** gameplay area,
   so it claims tiles Ice Plow does not hit.
2. Its calibration file — the artifact whose whole value is being an auditable
   record — carries eleven constants the code never reads, two of which
   contradict the code and one of which describes a feature that is not rendered.
3. Two names state units they do not have.
4. The debug harness cannot exercise the footprint at all, so defect 1 was
   invisible in the scene built to catch exactly this.

This cycle fixes those and converts the calibration constants into per-instance
data, which is what makes a second area effect possible without copying a file.

**Explicitly not in scope:** per-element storm tinting, generic layer builders,
and any change to `data/spells.json` gameplay fields. See §5.

---

## 2. Established facts (verified 2026-08-04 — do not re-derive)

### The chain, end to end

- `data/spells.json` — Ice Plow: `ELEMENT: ice`, `RADIUS: 2`,
  `TARGET_TYPE: "area"`, `CAN_TARGET_EMPTY: true`,
  `VFX_PROFILE: "ice_area_storm"`. `VFX_PROFILE` is presentation-only
  (`docs/SPELL_CATALOG_SCHEMA.md:33`).
- `CombatResolver.gd:486` emits `spell_cast_started` for **every** cast, before
  effects apply. `SpellEffectResolver.gd:96` then emits `monster_cast_spell` per
  affected target, which the adapter turns into `BUMP` actions carrying the
  damage numbers. A cast therefore produces one `CAST_AREA` action followed by N
  `BUMP` actions.
- `GodotVisualAdapter.gd:841`–`:870` builds the `CAST_AREA` action: copies
  `VFX_PROFILE` and `RADIUS` off the catalog reference, derives `vfx_seed` from
  `hash(spellName) ^ casterID*73856093 ^ x*19349663 ^ y*83492791`, and computes
  `vfx_ground_span` via `_footprint_ground_span()` (`:144`–`:158`).
- `GodotVisualAdapter.gd:1047`–`:1073` resolves the profile through
  `SpellVfxCatalog`, enforces the live cap, spawns, calls `setFootprint`, plays,
  and holds the queue for `duration × action_hold_fraction`
  (`2.2 × 0.45 ≈ 0.99 s`, against a 2.2 s effect).
- `SpellCastAura` is **no longer spawned from the bump path**. The catalog is the
  only spawn route for both effects.

### The footprint mismatch

- Gameplay area is a **Manhattan diamond**: `ShapeCaster.getCircle` is
  `abs(x) + abs(y) <= radius` (`src/algorithms/ShapeCaster.gd:10`), reached via
  `CombatResolver._spellAffectedPositions` (`:434`–`:452`).
- `IceStormEffect._updateFootprintGeometry` (`:361`–`:378`) sets the ground wash
  to a `CylinderMesh` of radius `(2*2+1)/2 = 2.5` — a disc covering the diagonal
  corners at `(±2, ±2)`, which the spell does not hit.
- `ice_storm_flurry.gdshader:38`–`:39` spawns `base_x`/`base_z` uniformly across
  a **5×5 square**, same over-claim.
- `_footprint_ground_span` already applies the correct diamond mask
  (`abs(offset_x) + abs(offset_y) > footprint_radius: continue`). The right
  shape is derived in one place and ignored in two others.
- **`AREA_SHAPE` is already available.** `SpellReferences.gd:27` normalizes it
  into every reference dict with default `"circle"` — the same dict
  `_on_spell_cast_started` already reads `RADIUS` and `VFX_PROFILE` from. No
  signal change is needed. (The `spell_cast_started` signal carries a spell
  *name*, not spell-set indices, which is why presentation cannot call
  `CombatResolver.getSpellAffectedPositionsFrom` despite that query documenting
  itself as shared with presentation.)

### The debug harness gap

- `VFXDebugController` **never calls `setFootprint`**. The storm always previews
  at its constructor default (radius 2, span 0).
- The radius spinbox (`:486`–`:488`) only resizes `_footprintRing`, a decorative
  `TorusMesh` guide (`:606`–`:612`) — which is a **circle**, so even the guide
  draws the wrong shape.
- Everything else in the harness is wired correctly: seed pinning, scrub, layer
  toggles, overlap spawn, mode switch, playback scale.

### Budgets, already asserted

- `IceStormEffect._buildLayers` (`:270`–`:271`) asserts node count ≤ 12 and draw
  calls ≤ 14. **Actuals are 11 and 10.** One added node trips the assert; plan
  accordingly.
- `MAX_LIVE_PARTICLES = 220` is **never read**. `FLURRY_PARTICLE_AMOUNT = 180`
  is under it by coincidence. Two live storms put 360 particles on screen;
  `_rebalance_live_effect_intensity` scales alpha, not count.

### Unused calibration constants (verified by reference count)

Zero references: `CANOPY_EDGE_COLOR`, `COMPARISON_CHECKPOINTS`,
`HERO_SHARD_MAX_VISIBLE`, `HERO_SHARD_SPAWN_RATE_PER_SECOND`,
`MAX_FULLY_OBSCURED_FRACTION`, `MAX_LIVE_PARTICLES`,
`REFERENCE_FOOTPRINT_DIAMETER_U`, `REFERENCE_UNIT_HEIGHT_U`, `SETTLE_FRACTION`,
`SUSTAIN_FRACTION`, `TARGET_FILLED_FRACTION`, `VEIN_LAYER_COUNT`.

- `CANOPY_EDGE_COLOR` unused means the documented core/edge canopy relationship
  **does not exist in the render** — every canopy quad uses `CANOPY_CORE_COLOR`.
- `HERO_SHARD_SPAWN_RATE_PER_SECOND` and `HERO_SHARD_MAX_VISIBLE` are
  contradicted by the hardcoded schedule `0.05 + index * 0.075`
  (`IceStormEffect.gd:400`) over a fixed `_SHARD_COUNT = 8`.

### Other verified details

- `_shardLife` (`:481`–`:488`) divides `HERO_SHARD_LIFETIME_SECONDS` (1.25) by
  `REFERENCE_DURATION_SECONDS` (4.5) **unconditionally**, so the constant only
  ever means a fraction of the whole timeline and resolves to ≈0.61 s in battle.
- `_active_cast_effect` is cleared in `_finalize_animation` (`:434`) when the
  ~0.99 s hold expires, but the storm runs 2.2 s, so `skipCurrentAnimation()`
  cannot reach it during the trailing damage-number actions.
- `VfxTextures` bakes `IceStormProfile` colours into **statically cached**
  materials, then `IceStormEffect` `.duplicate()`s each and overwrites
  `albedo_color` every frame — so the baked colour is only ever a default.
- Determinism is genuine: the flurry shader is `disable_force, disable_velocity`
  and computes every transform from `INDEX`, a seed hash, and the
  `playback_time` uniform. Nothing integrates, which is why
  `is_particle_seek_exact()` truthfully returns `true`. **Preserve this
  property**; any change that makes particle state depend on accumulated frames
  breaks scrubbing.
- `IceStormEffect.createPlayback` accepts `_elementColor` and discards it.

---

## 3. Execution rules

Per `AGENTS.md` — this section does not restate it, only what is easy to miss:

- **One item per session, from a clean `git status`.** Note the item's **Model**
  against the running model before starting; if the running model is more
  capable than the item needs, say so and continue (advisory, not blocking —
  see `AGENTS.md`).
- Implementation items resolve to **implemented; pending end-of-plan
  validation**. Only `ICE-5` marks items done.
- Do not launch the game after each implementation item. `ICE-1`, `ICE-3`, and
  `ICE-4` may run `VFXDebugScene` (`--path . scenes/debug/VFXDebugScene.tscn`)
  because that scene is their deliverable surface; record it as a smoke check,
  not acceptance.
- New `.gd` and `.gdshader` files generate `.uid` sidecars in Godot 4.4. Commit
  them with their source. A `class_name` rename orphans the old `.uid`.
- Windows: run from the repo root, pass `--path .`, use bounded waited
  processes, force LF on generated text. See `docs/DEVELOPMENT.md`.
- The `ICE-n` labels are transitory. **No file outside this one may cite them** —
  not `docs/`, not the backlogs, not source comments, not commit messages.
  Describe the work instead.

---

## 4. Items

### ICE-1 — Match the storm footprint to the spell's real area shape

**Model:** Sonnet 5 / GPT Terra
**Depends on:** nothing
**Files:** `src/presentation/VisualAction.gd`,
`src/presentation/GodotVisualAdapter.gd`,
`src/presentation/effects/IceStormEffect.gd`,
`assets/shaders/effects/ice_storm_flurry.gdshader`,
`src/presentation/effects/VfxTextures.gd`,
`src/presentation/debug/VFXDebugController.gd`

The one player-visible defect in the cycle, plus the harness gap that hid it.
Both halves are required: without the harness change there is no way to judge
the fix in the scene built for judging it.

**End state:**

- `VisualAction` gains `vfx_area_shape: String`, copied in `duplicate()`
  alongside the existing `vfx_*` fields.
- `_on_spell_cast_started` reads `AREA_SHAPE` from the reference dict it already
  holds, next to `RADIUS`.
- `setFootprint(radius: int, groundSpan: float, areaShape: String)`. The
  adapter's `has_method("setFootprint")` guard at `:1060` passes three args.
- **Flurry field, diamond case.** Spawn `base_x`/`base_z` uniformly in a square
  of half-extent `R / sqrt(2.0)` where `R = footprint_width * 0.5`, then rotate
  45° into local space as the final step:
  `x = (sx - sz) * SQRT1_2`, `z = (sx + sz) * SQRT1_2`. A square rotated 45° is
  exactly the diamond `|x| + |z| <= R`, so density stays uniform and **no
  particle is rejected** — do not mask by alpha, which would throw away roughly
  half the field. Perform the gust drift and `wrap_span` in the pre-rotation
  frame so wrapping stays axis-aligned; rotate `gust_direction` by −45° on the
  CPU in `_updateFlurryUniforms` so the visible drift direction is unchanged.
- **Ground wash.** Keep the `CylinderMesh`: extruding it by `groundSpan` is the
  existing trick that lets the wash meet terrain at every elevation in the
  footprint, and it must be preserved. Put the shape in the *texture* instead —
  `_createGroundWash` gains a shape parameter and generates a diamond falloff
  (`1 - (|u| + |v|)`) for the diamond case, cached per shape.
- **Non-diamond shapes** (`cross`, `line`) keep the current square field and
  disc wash. Ice Plow is the only carrier today and it is `circle`. Record the
  gap in `BACKLOG_LONGTERM.md` as described work, not as a citation of this item.
- **Debug harness.** The radius spinbox calls `setFootprint` on the active
  playback. The guide replaces the `TorusMesh` with an outline of the actual
  shape (an `ImmediateMesh` line loop is sufficient) so the guide and the effect
  agree. Add a shape selector only if it costs little; radius is the load-bearing
  control.

**Risk:** frame errors in the rotation — flakes drifting outside the diamond, or
a visible seam where `wrap_span` folds. Both are immediately obvious in the
debug scene against the corrected guide, which is why the harness half is in
this item rather than a later one. Second risk: the rotation must not introduce
any per-frame accumulation, or `is_particle_seek_exact()` becomes a lie.

**Adds to final validation coverage:** the storm covers exactly the tiles Ice
Plow damages, at radius 1–5, on flat and uneven ground and clipped at board
edges; no flakes fall outside the footprint; the debug guide matches the render;
the radius control drives the effect; scrubbing is still frame-exact.

---

### ICE-2 — Move storm calibration into a Resource; stop the texture module claiming to be generic

**Model:** Opus 5 / GPT Sol
**Depends on:** ICE-1
**Files:** new `src/presentation/effects/SpellVfxProfile.gd`, new
`data/vfx/ice_area_storm.tres`, `src/presentation/effects/IceStormProfile.gd`
(removed), `src/presentation/effects/IceStormEffect.gd`,
`src/presentation/effects/SpellVfxCatalog.gd`,
`src/presentation/effects/VfxTextures.gd` (renamed), plus `.uid` sidecars.

**This is the only item that is not a defect fix, and it is droppable.** It is
what converts a hardcoded effect into one whose numbers are data — the
prerequisite for any second area effect. If dropped, `ICE-3` and `ICE-4` edit
`IceStormProfile.gd` in place instead and the rest of the plan is unaffected.
Confirm with the user before executing.

**End state:**

- `SpellVfxProfile` is a `Resource` with `@export var` for every current
  constant. **The provenance annotations are the most valuable thing in that
  file and must survive verbatim** — GDScript keeps `##` doc comments on
  exported properties and surfaces them as inspector tooltips, so each
  `MEASURED` / `ESTIMATED` line moves onto its property. A conversion that drops
  them has failed even if the storm renders identically.
- `data/vfx/ice_area_storm.tres` holds today's values **exactly**. This item is
  a pure refactor: no value is retuned while being moved. If the storm looks
  different afterwards, a value was dropped.
- The catalog row carries the profile resource; `createPlayback` takes it and
  the effect reads instance state rather than class constants.
- `VfxTextures` stops baking profile colours into its static material cache
  (albedo and emission become white). Tint comes from the per-instance
  `.duplicate()` the effect already performs every frame, so the shared cache
  stays correct once values are per-instance rather than global. **This is the
  load-bearing part** — leaving colours baked in a static cache while making
  them per-instance is how two storms end up cross-tinted.
- Ice-specific material getters move to `IceVfxTextures.gd`; the generic image
  helpers (`_fbm`, `_valueNoise`, `_distanceToSegment`, `_normalizedPoint`) stay
  in a genuinely generic module. The current file's own doc comment already says
  "for ice VFX layers" — the class name is what lies.
- **Before starting, capture a reference screenshot** of the storm at several
  scrub checkpoints via the debug harness, and record the paths here. `ICE-5`
  compares against it to prove no visual change.

**Risk:** the highest in the plan. Roughly forty constant references move, and a
missed one silently reads a stale global instead of erroring. Removing
`IceStormProfile` entirely (rather than leaving it as a shim) is what makes a
missed reference a load-time error instead of a silent wrong value — do it that
way. Second risk: the static material cache is shared across live storms; verify
two overlapping storms tint independently rather than assuming it.

**Adds to final validation coverage:** the storm renders identically to the
pre-item screenshots at every checkpoint; two overlapping storms tint
independently; the profile resource opens in the inspector with provenance
tooltips intact; no reference to the removed constants file remains.

---

### ICE-3 — Resolve the unused calibration constants and render the canopy edge

**Model:** Sonnet 5 / GPT Terra
**Depends on:** ICE-2 (edit the resource; if ICE-2 was dropped, edit
`IceStormProfile.gd` instead)
**Files:** `data/vfx/ice_area_storm.tres` and
`src/presentation/effects/SpellVfxProfile.gd` (or `IceStormProfile.gd`),
`src/presentation/effects/IceStormEffect.gd`, possibly `docs/`

Twelve constants are unread. They are not uniformly dead — sort them into three
outcomes rather than deleting the list:

- **Wire it.** `CANOPY_EDGE_COLOR`: canopy quads lerp core → edge by index, with
  index 0 taking `CANOPY_CORE_COLOR` and the highest index taking
  `CANOPY_EDGE_COLOR`, matching the existing size ramp where larger index means
  larger quad. Implement as material colour on the existing quads — **the node
  budget is at 11 of 12, so adding quads trips the build assert.**
- **Pick one.** `HERO_SHARD_SPAWN_RATE_PER_SECOND` and `HERO_SHARD_MAX_VISIBLE`
  contradict the hardcoded schedule. Either derive the schedule from them or
  delete both and document the hardcoded schedule as authoritative. Do not leave
  both forms in the file.
- **Enforce it.** `MAX_LIVE_PARTICLES` becomes an assert on the flurry amount at
  build time, next to the existing node and draw-call asserts.
- **Move it to prose.** `COMPARISON_CHECKPOINTS`, `MAX_FULLY_OBSCURED_FRACTION`,
  and `TARGET_FILLED_FRACTION` read as acceptance criteria for the original
  reference-match validation, not runtime values. They belong in `docs/` as
  prose, if anywhere.
- **Delete.** `SUSTAIN_FRACTION`, `SETTLE_FRACTION`, `VEIN_LAYER_COUNT`,
  `REFERENCE_UNIT_HEIGHT_U`, `REFERENCE_FOOTPRINT_DIAMETER_U`.

**Risk:** the canopy edge tint is **the one intended visual change in this
plan** — the storm's upper mass will read differently afterwards, and that is
correct, not a regression. Any prior screenshot or "looks right" note about the
canopy is superseded; do not restore the flat-core appearance. The user should
judge the result. Everything else in this item is inert.

**Adds to final validation coverage:** the canopy shows a core-to-edge falloff
rather than a flat tint; the particle-count assert holds during a cast; the
calibration file contains no constant the code does not read.

---

### ICE-4 — Make two names and one lifetime tell the truth

**Model:** Sonnet 5 / GPT Terra
**Depends on:** ICE-2 (touches the same fields)
**Files:** `data/vfx/ice_area_storm.tres` and `SpellVfxProfile.gd` (or
`IceStormProfile.gd`), `src/presentation/effects/IceStormEffect.gd`,
`src/presentation/GodotVisualAdapter.gd`

Two small corrections, grouped because both are cases of the code stating
something it does not mean, and neither justifies its own session.

**End state:**

- `HERO_SHARD_LIFETIME_SECONDS` → `HERO_SHARD_LIFETIME_FRACTION`, value
  `1.25 / 4.5 ≈ 0.2778`, with a doc line recording that it is a fraction of the
  whole timeline and resolves to ≈0.61 s in battle mode and 1.25 s in reference
  mode. `_shardLife` uses it directly and stops dividing. **No behaviour change**
  — the arithmetic is identical, only the name and the division site move.
- `_active_cast_effect` is no longer cleared in `_finalize_animation`. It is
  cleared in `_on_live_effect_exiting` when the exiting instance matches, so the
  reference lives as long as the effect does and `skipCurrentAnimation()` reaches
  a storm still playing past its ~0.99 s queue hold. Verify no dangling
  reference survives `dispose()`.

**Risk:** low. The skip change **alters observed behaviour**: skipping during
the trailing damage-number actions now settles the storm, where previously it
kept playing. That is the intent — a later session must not "fix" it back.

**Adds to final validation coverage:** skipping during the damage-number tail
settles the storm; skipping mid-storm settles it; no dangling effect reference
after disposal; shard timing is visually unchanged.

---

### ICE-5 — Final validation

**Model:** Opus 5 / GPT Sol
**Depends on:** ICE-1, ICE-2 (if executed), ICE-3, ICE-4
**Files:** this plan; fixes as needed

The only item that performs full manual gameplay and integration validation and
the only item that marks covered items done.

**Preconditions:** every implementation item committed; working tree clean.

**Consolidated checks — run once, using integrated flows:**

1. **Debug scene pass.** Launch `VFXDebugScene` bounded and waited. Sweep radius
   1–5 and confirm the effect resizes, the guide matches the render, and no
   flake falls outside the diamond. Exercise seed pinning, scrub in both
   directions, layer toggles, overlap spawn, mode switch, and playback scale.
   Confirm the node, draw-call, and particle asserts do not fire.
2. **Visual-parity pass.** Compare against the screenshots `ICE-2` captured
   before refactoring. Everything except the canopy edge tint must match; the
   canopy difference is expected and is `ICE-3`'s intended change.
3. **Battle integration.** Launch `Battle25D` bounded and waited. Cast Ice Plow
   on flat ground, on uneven ground, at a board edge where the footprint clips,
   and on an empty tile. Confirm the storm covers exactly the tiles that take
   damage, composites through the CRT pass, and does not z-fight terrain or
   units.
4. **Overlap and cap.** Two live storms: intensity halves and restores on
   expiry. A third cast disposes the oldest.
5. **Skip, pause, speed.** Skip mid-storm and during the trailing damage
   numbers; pause and resume; change speed scale mid-storm.
6. **Leak check.** 20+ casts; node count returns to baseline.
7. `git diff --check`; only task-owned files staged.

**Capture screenshots** from steps 1 and 3 and reference their paths in the
Resolution so the user can review without relaunching.

**If validation finds a defect:** fix it in this session, rerun only the
relevant consolidated checks, and record the fix and evidence here. Do not
reopen prior items to repeat the same validation.

**On success:** mark all covered items done, state the plan is complete, move
genuinely open work to the appropriate backlog file — **described, never citing
an `ICE-n` label** — naming those items explicitly to the user, then delete this
file's contents. Recover with `git show <ref>:implementation_plan.md`.

---

## 5. Deferred, with reasons

Recorded here so a later session does not read these as oversights:

- **Non-diamond area shapes** (`cross`, `line`) keep the square flurry field.
  No spell carries them with an area VFX profile today. `ICE-1` records this in
  `BACKLOG_LONGTERM.md` as described work.
- **Per-element storm profiles.** `createPlayback` will keep discarding
  `_elementColor`. Making the ice storm tintable produces a blue-shaped fire
  spell; if per-element storms are wanted, they are new `.tres` files against
  `ICE-2`'s resource, not a colour parameter.
- **Generic layer builders (`VfxLayers.gd`).** Proposed by the previous cycle's
  draft, never built. The storm's layers turned out highly specific — breathing
  canopy quads, a branching vein backdrop, multimesh shards on a pure time
  function. Generalizing from a sample size of one produces an abstraction the
  second effect fights. `VfxPlayback` is already carrying the reuse burden and
  carrying it well. Revisit when a second effect actually needs a shared layer.
- **The 0.99 s queue hold against a 2.2 s effect.** Deliberate pacing from the
  previous cycle; the storm tail overlapping the damage numbers is the intended
  look. Not a defect.

---

## 6. Resolution notes

*(Executing sessions append here. One entry per item: what was done, what was
decided, what was verified, and any finding a later item depends on.)*

- **ICE-1** — implemented; pending end-of-plan validation. `AREA_SHAPE` now
  flows `SpellReferences` → `VisualAction.vfx_area_shape` →
  `IceStormEffect.setFootprint`'s third parameter. The flurry shader samples a
  square rotated -45°, drifts/wraps in that pre-rotation frame, then rotates
  the result back +45° — a square rotated 45° is exactly the
  `ShapeCaster.getCircle` diamond, so every particle lands inside it with none
  rejected; `diamond_shape = 0.0` collapses the whole path back to the original
  square field unchanged (verified algebraically, not just by inspection).
  Ground wash gained a Manhattan-falloff texture variant, swapped in by
  `_updateFootprintGeometry` based on the same shape classification
  (`IceStormEffect._isDiamondShape`, mirroring `CombatResolver`'s own
  `cross`/`line`/else match). `cross`/`line` carriers keep the legacy square
  field/disc — none ship today, recorded in `BACKLOG_LONGTERM.md`.
  `VFXDebugController`'s radius spinbox now calls `setFootprint` on the active
  and overlap playbacks (it never did before), and the guide mesh is a diamond
  outline instead of a `TorusMesh` circle.
  **Also fixed, discovered while capturing verification screenshots:** the HUD
  panel covered ~80% of the window at every resolution tried, because an
  unwrapped `HintLabel` was silently forcing the panel's minimum width — the
  literal cause was invisible without dumping `get_combined_minimum_size()` per
  row, since panel width visually appeared driven by unrelated wide rows.
  Fixed with `autowrap_mode = 3` (matching `StatusLabel`'s existing
  convention), the panel converted to a full-height left-anchored sidebar, and
  `LayerToggles` changed from a one-row `HBoxContainer` to a single-column
  `GridContainer` so it doesn't reintroduce an overflow as more layers are
  added. User-requested mid-item; not in the original item text.
  **Smoke-checked, not accepted:** `VFXDebugScene` launched clean via
  `--capture-at=` at several scrub points and radii 2 and 4, generic aura and
  ice storm, no shader/script errors, `particles 180` / `flurry: exact` /
  `nodes 11` all match pre-existing budgets. Full radius sweep, guide-vs-render
  agreement across the whole 1–5 range, and battle-integration verification are
  `ICE-5`'s job, not this item's.
  **Found, not fixed here (owned by other work):** (1) the automated
  `--capture-at` path always exercises the catalog's first entry (the generic
  aura, index 0) — there is no CLI way to select `Ice Area Storm` for an
  unattended capture; verification screenshots for this item were taken with a
  temporary, reverted `_effectOption.select(1)` edit, never committed. (2)
  Quitting the debug scene while the generic aura (`SpellCastAura`) is the
  active playback throws `Object is locked and can't be freed` from
  `SpellCastAura.dispose`; reproduces on the pre-ICE-1 commit too, so it
  predates this plan — recorded in `BACKLOG_LONGTERM.md`, not fixed here. (3)
  `git add` on the two tracked files under `src/presentation/debug/` and
  `scenes/debug/` prints a `paths are ignored by one of your .gitignore files`
  warning and a nonzero exit even though both are already tracked and the add
  succeeds — `.gitignore:23`'s bare `debug/` rule predates these files being
  committed. Harmless (confirmed via `git diff --cached --stat` after), but
  worth knowing before assuming the warning means the files were dropped.
- **ICE-2** — not started (droppable; confirm with user before executing)
- **ICE-3** — implemented; pending end-of-plan validation. `ICE-2` was not
  executed (user only requested `ICE-1`, `ICE-3`, `ICE-4`), so this edited
  `IceStormProfile.gd`'s const class directly, per the item's documented
  fallback. Wired `CANOPY_EDGE_COLOR` as a per-quad core→edge lerp keyed to
  canopy index (matching the existing size ramp); also extended
  `_setMaterialOpacity` to update `material.emission` (previously frozen at
  construction time from the material's original color, so the lerp would
  otherwise only ever show in unlit albedo, not the additive glow that
  actually reads as brightness on screen) — no-op for every other caller,
  which all pass one constant color every frame. Verified visually with all
  other layers hidden: a genuine bright-core-to-dim-cool-rim falloff, not the
  previous flat tint. This is the plan's one intended visual change; it is not
  a regression.
  Deleted `HERO_SHARD_SPAWN_RATE_PER_SECOND`/`HERO_SHARD_MAX_VISIBLE` (chose
  "delete, document the hardcoded schedule as authoritative" over "derive from
  them" — deriving would have changed shard spawn timing, a second unplanned
  visual change the plan's risk note explicitly scoped out). Carried the
  acceptance-cap provenance note over to `_SHARD_COUNT` in `IceStormEffect.gd`
  so it isn't lost. Enforced `MAX_LIVE_PARTICLES` as a build-time assert next
  to the existing node/draw-call asserts (180 ≤ 220, passes cleanly).
  **Decision:** `COMPARISON_CHECKPOINTS`, `MAX_FULLY_OBSCURED_FRACTION`, and
  `TARGET_FILLED_FRACTION` were deleted outright rather than relocated to
  `docs/` prose, which the item allowed ("if anywhere"). They are acceptance
  criteria for the original reference-match validation, which already
  happened and already shipped — not durable forward-looking guidance in the
  sense `docs/LEARNINGS.md`'s own stated purpose requires, and forcing them
  into that file's "Verified observation / Reusable rule / Review when" format
  would misrepresent settled history as live guidance. Deleted
  `SUSTAIN_FRACTION`, `SETTLE_FRACTION`, `VEIN_LAYER_COUNT`,
  `REFERENCE_UNIT_HEIGHT_U`, `REFERENCE_FOOTPRINT_DIAMETER_U` outright per the
  item text. Confirmed zero references to any of the ten removed constants
  before committing.
  **Smoke-checked, not accepted:** `VFXDebugScene` launched clean via
  `--capture-at=`, generic aura and ice storm, no shader/script/assert errors
  beyond the pre-existing `SpellCastAura` dispose issue noted under `ICE-1`
  (unrelated, reproduces identically). Canopy tint judged only by eye in the
  debug scene with layers isolated — the user should confirm the new look in
  `ICE-5`.
- **ICE-4** — implemented; pending end-of-plan validation. `ICE-2` not
  executed, so edited `IceStormProfile.gd`/`IceStormEffect.gd` directly, same
  as `ICE-3`. `HERO_SHARD_LIFETIME_SECONDS` → `HERO_SHARD_LIFETIME_FRACTION`
  (`0.27778`, matching `1.25 / 4.5` to five decimal places — negligible
  rounding, not a tuning change); `_shardLife()` uses it directly and no
  longer divides. `_active_cast_effect` is now cleared in
  `_on_live_effect_exiting` (when the effect it actually points at exits the
  tree) instead of in `_finalize_animation` (when the action's queue hold
  expires, which is shorter than some effects' full runtime) — so
  `skipCurrentAnimation()` can reach a storm still playing past its action's
  hold. Confirmed via re-read that `_dispose_live_effects()`'s own
  `_active_cast_effect = null` (full adapter teardown) is unaffected and still
  correct.
  **Smoke-checked, not accepted:** the shard-lifetime half was verified in
  `VFXDebugScene` (visually unchanged, as expected). The
  `_active_cast_effect`/skip half touches only `GodotVisualAdapter.gd`, which
  `VFXDebugScene` never loads — a normal capture would not have caught a
  syntax error in it. Forced a compile-check via a temporary `preload()` in
  the debug controller (reverted before commit, confirmed absent via `grep
  TEMP-ICE` returning nothing): no parse/compile error. The actual skip
  behavior change is only exercisable through the battle scene and is
  explicitly `ICE-5`'s job ("Skip, pause, speed" in its consolidated checks) —
  not exercised here.
- **ICE-5** — not started
