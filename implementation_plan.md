# Fire Storm Cycle

**Opened 2026-08-04.** The previous contents were the ice-storm correction
cycle, opened and executed the same day. Disposition of its items:

- Three implementation items — the area-footprint diamond fix, the
  unused-calibration-constant resolution, and the shard-lifetime/skip-lifecycle
  name corrections — are **committed and implemented** (`f882e59`, `3498d06`,
  `3babe05`). Their code is live; this cycle builds directly on it.
- Its optional profile-as-a-`Resource` refactor was **never executed and is
  deliberately dropped**. See §2 — it is reconsidered at a third elemental
  effect, not now.
- Its final validation item **never ran**. Rather than launching the game twice,
  that outstanding validation is folded into this cycle's `FIRE-3`, which now
  covers both effects in one session: steps 5–6 there carry the ice cycle's
  regression and lifecycle checks explicitly.

Nothing from the ice cycle is left open elsewhere, so nothing was moved to a
backlog at this reset. Recover its full text with
`git show 432dd5b:implementation_plan.md`.

---

## 1. Goal

A fire-element area effect that reuses the ice storm's engine wholesale: same
`VfxPlayback` contract, same catalog registration, same adapter path, same
deterministic-seek guarantee. Only the motion model, palette, and layer roster
change.

**The look:** embers rise from the ground in a slow spiral, dense and near-white
at the base, thinning and cooling through orange to deep red as they climb,
shrinking to nothing under a drifting smoke crown. The column twists faster at
its base than at its crown, so the spiral visibly *winds* rather than rotating
as a rigid body.

**Explicit cost constraint.** The ice storm cost more than it should have. This
cycle is scoped at **two implementation items and one validation item**, against
the ice cycle's eight. §5 lists what is deliberately not being done.

---

## 2. Established facts (verified 2026-08-04 — do not re-derive)

### What is reusable without modification

- **`VfxPlayback.gd`** — the lifecycle contract (`play`, `seek_normalized`,
  `set_playback_scale`, `skip_to_settle`, `dispose`, `get_layer_names`,
  `set_layer_visible`, `get_live_particle_count`, `is_particle_seek_exact`).
- **`SpellVfxCatalog.gd`** — registration is one row in `entries()`; nothing
  else in the codebase needs to learn the new profile exists.
- **`GodotVisualAdapter._start_cast_area_animation`** (`:1047`) — already fully
  profile-driven. Resolves the profile, enforces the live cap, calls
  `setFootprint(radius, groundSpan, areaShape)`, plays, and holds the queue for
  `duration × action_hold_fraction`. **Zero changes needed.**
- **`VisualAction.vfx_area_shape`** — already plumbed from `AREA_SHAPE` through
  to `setFootprint` by the ice cycle.
- **`VfxTextures`** shape generators are alpha masks with no colour baked into
  geometry: `softFlake()` (works as an ember dot unchanged), `canopyPuff()`
  (works as a smoke puff unchanged), `groundWash(diamond: bool)`. Tint is
  applied by the effect to its own `.duplicate()`d material every frame, so the
  same masks serve any element.
- **Debug harness** — `--effect=<profile id>`, `--hide-hud`, `--capture-at=`,
  and the `H` toggle all landed 2026-08-04. One-command iteration:
  `--effect=fire_area_storm --hide-hud --capture-at=0.4`.

### What must be forked, and why

`IceStormEffect.gd` reads `IceStormProfile.SOME_CONSTANT` directly at roughly
forty sites. The `SpellVfxProfile`-as-a-`Resource` refactor that would have made
profiles injectable was **proposed and not executed** in the ice cycle (its
Resolution records it as dropped). Without that indirection there is no seam to
subclass against, so copy-and-retune is cheaper than inventing one now.

**This is the second copy, and that is the correct time to duplicate.**
Extracting a shared base for two effects costs more than it saves. If a *third*
elemental storm is ever wanted, that is the point to do the resource refactor —
at three copies the shared shape is proven, and a fourth element then becomes
"author a `.tres`" rather than "fork a file."

### Budget headroom

`IceStormEffect._buildLayers()` asserts node count ≤ 12 and draw calls ≤ 14,
with actuals of **11 and 10** — nearly full. Fire drops the four
`MultiMeshInstance3D` hero-shard nodes (ice chunks have no ember equivalent),
freeing enough room for a second particle layer. Projected fire actuals:
**6 nodes, 5 draw calls**. `MAX_LIVE_PARTICLES = 220` became a build-time assert
in the ice cycle; the fork inherits it and stays at 180 total.

### The carrier situation

`Smoke Tower` is the **only** fire spell with `TARGET_TYPE: "area"`:
`RADIUS: 1`, `AREA_SHAPE: "cross"`, described as *"A cross-shaped pillar of
smoke and fire that inflicts burn."* Two consequences:

1. That description is already a rising column — the effect this plan builds is
   what the spell text has been claiming all along.
2. `cross` is the shape the ice cycle explicitly left unhandled (recorded in
   `BACKLOG_LONGTERM.md`): `_isDiamondShape()` returns false for it and the
   ground wash falls back to a radial disc over a plus-shaped area.

Other area spells for reference: radius 2–3, mostly default (diamond) shape;
`Holy Cross` is the only other `cross` carrier.

---

## 3. Design decisions

### The vortex is radial; the ground wash carries the shape

A spiral is inherently radial. Forcing an ember column into a plus-shaped
silhouette would look wrong and cost far more than it returns. So:

- **The column** is radially symmetric, clamped to the footprint boundary.
- **The ground wash** carries the exact gameplay shape, and gains a `cross`
  texture variant — which closes the ground-wash half of the backlog gap for
  every `cross` carrier, not just this one.

### The diamond boundary has an exact polar form

For a diamond footprint `|x| + |z| ≤ R`, the boundary in polar coordinates is
exactly:

```
r_max(θ) = R / (|cos θ| + |sin θ|)
```

At θ = 0 this gives `R` (the diamond's vertex); at θ = 45° it gives `R/√2` (the
edge midpoint). Clamping the spiral to this makes the column **breathe in and
out as it rotates**, tracing the real gameplay footprint. This is both the
correct behaviour and the more beautiful one — it is the single nicest thing in
this plan and should not be simplified away to a circle.

For `cross` and `line` carriers, fall back to the inscribed circle `R/√2`.

### What "poetic" means here, concretely

Stated as acceptance criteria so it survives delegation:

- **Density gradient.** Dense at the base, sparse at the crown. Achieved by
  ember alpha dying at `h ≈ 0.52–1.0`, not by varying spawn count.
- **Colour gradient with height.** Hot near-white at the base → orange → deep
  red at the crown. An ember that reaches the top has visibly cooled.
- **Differential rotation.** Angular speed is higher at the base than the crown,
  so the spiral winds rather than spinning rigidly.
- **Taper.** Radius narrows with height — a funnel, not a cylinder.
- **Shrink.** Embers get smaller as they rise, reading as burning out.
- **Per-ember flicker.** A hash-phased sine on alpha so the column shimmers
  instead of reading as uniform dots.
- **A slight lean.** A small quadratic x-offset with height. Perfectly vertical
  reads as mechanical.

A version missing the colour gradient, the differential rotation, or the
flicker has failed the brief even if it renders embers going upward.

---

## 4. Items

### FIRE-1 — The vortex shader, profile, and effect class

**Model:** Sonnet 5 / GPT Terra *(the shader math is fully specified below;
this is transcription and retuning, not derivation)*
**Depends on:** nothing
**Files:** new `assets/shaders/effects/fire_storm_vortex.gdshader`, new
`src/presentation/effects/FireStormProfile.gd`, new
`src/presentation/effects/FireStormEffect.gd`, plus `.uid` sidecars

**Fork procedure.** Copy `IceStormProfile.gd` → `FireStormProfile.gd` and
`IceStormEffect.gd` → `FireStormEffect.gd`, rename the classes and the profile
references, then change only what §3 requires. Most constants — phase
fractions, action hold, live-storm cap, node/draw-call/particle budgets, canopy
drift and breath — carry over unchanged and should not be re-derived.

**Layer roster** (ice's seven → fire's six):

| Fire layer | Origin |
| --- | --- |
| `ground_wash` | ice `ground_wash`, recoloured, `cross` texture variant added |
| `ember_column` | new: dense vortex, 140 particles |
| `ember_motes` | new: sparse/larger/slower vortex, 40 particles |
| `smoke_crown` | ice `canopy`, recoloured to warm grey, 2 quads |
| `swirl` | uniform toggle (replaces ice `gust`) |
| `flicker` | uniform toggle (replaces ice `pulse_accents`) |
| *(dropped)* | ice `frost_veins`, ice `hero_shards` |

**The shader.** `shader_type particles`, `render_mode disable_force,
disable_velocity` — same contract as the ice flurry. Every value is a pure
function of `INDEX` and `playback_time`; **nothing integrates across frames**,
which is what keeps `is_particle_seek_exact()` truthful and scrubbing frame-
exact. Any change that makes ember state depend on accumulated frames breaks
the debug harness's scrub and is a defect.

```glsl
const float SQRT1_2 = 0.70710678;
const float TAU_C   = 6.28318531;

float hash_value(float value) {
    return fract(sin(value * 127.1 + vfx_seed * 17.17) * 43758.5453);
}

void process() {
    float index      = float(INDEX);
    float a0         = hash_value(index +   1.0) * TAU_C;
    // sqrt() gives uniform density per unit AREA; without it embers bunch
    // visibly at the column's axis.
    float rNorm      = sqrt(hash_value(index +  41.0));
    float phase      = hash_value(index +  83.0);
    float riseSpeed  = mix(min_rise_speed, max_rise_speed, hash_value(index + 127.0));
    float baseScale  = mix(min_scale, max_scale, hash_value(index + 173.0));
    float flickPhase = hash_value(index + 211.0) * TAU_C;

    // Vertical cycle: 0 at the floor, 1 at the crown, wrapping.
    float h = fract(phase + playback_time * riseSpeed / max(column_height, 0.001));
    float y = h * column_height;

    // Funnel: radius narrows toward the crown.
    float taper = mix(1.0, crown_taper, smoothstep(0.0, 1.0, h));

    // Differential rotation: the base winds faster than the crown.
    float omega = mix(swirl_base, swirl_crown, h) * swirl_speed * swirl_enabled;
    float a     = a0 + playback_time * omega;

    // Exact diamond boundary in polar form; inscribed circle for cross/line.
    float diamondLimit = footprint_radius_u / max(abs(cos(a)) + abs(sin(a)), 0.001);
    float rMax = mix(footprint_radius_u * SQRT1_2, diamondLimit, diamond_shape);
    float r    = min(rNorm * footprint_radius_u * base_radius_fraction, rMax) * taper;

    float lean = lean_offset * h * h;
    vec3  pos  = vec3(r * cos(a) + lean, y, r * sin(a));

    // Cooling with height.
    vec3 col = mix(ember_hot_color.rgb, ember_mid_color.rgb, smoothstep(0.0, 0.45, h));
    col      = mix(col, ember_cool_color.rgb, smoothstep(0.45, 1.0, h));

    float flicker = 1.0 - flicker_depth * flicker_enabled
        * (0.5 + 0.5 * sin(playback_time * flicker_rate + flickPhase));
    float birth = smoothstep(0.0, 0.09, h);
    float death = 1.0 - smoothstep(0.52, 1.0, h);

    float normalized_time = clamp(playback_time / max(total_duration, 0.001), 0.0, 1.0);
    float onset  = smoothstep(0.0, onset_fraction, normalized_time);
    float settle = 1.0 - smoothstep(0.80, 0.96, normalized_time);

    float scale = baseScale * mix(1.0, ember_shrink, h);
    TRANSFORM[0].xyz = vec3(scale, 0.0, 0.0);
    TRANSFORM[1].xyz = vec3(0.0, scale, 0.0);
    TRANSFORM[2].xyz = vec3(0.0, 0.0, scale);
    TRANSFORM[3].xyz = pos;
    VELOCITY = vec3(-sin(a) * r * omega, riseSpeed, cos(a) * r * omega);

    COLOR    = vec4(col, ember_hot_color.a);
    COLOR.a *= clamp(birth * death * flicker * onset * settle * intensity_scale, 0.0, 1.0);
}
```

**Uniforms** mirror the ice flurry's set, with these replacing the falling-snow
ones: `footprint_radius_u`, `column_height`, `base_radius_fraction`,
`crown_taper`, `swirl_base`, `swirl_crown`, `swirl_speed`, `min_rise_speed`,
`max_rise_speed`, `ember_shrink`, `flicker_rate`, `flicker_depth`,
`lean_offset`, `swirl_enabled`, `flicker_enabled`, `diamond_shape`,
`ember_hot_color`, `ember_mid_color`, `ember_cool_color`. Retain unchanged:
`playback_time`, `total_duration`, `onset_fraction`, `intensity_scale`,
`min_scale`, `max_scale`, `vfx_seed`.

**`footprint_radius_u` is `float(radius) + 0.5`**, matching the ground wash
cylinder's own `diameter * 0.5`, so the column's boundary and the wash's edge
agree.

**Suggested starting palette** (retune by eye; these are authored, not measured):
`ember_hot` ≈ `(1.0, 0.94, 0.72)`, `ember_mid` ≈ `(1.0, 0.55, 0.16)`,
`ember_cool` ≈ `(0.72, 0.16, 0.09)`, smoke crown ≈ `(0.26, 0.22, 0.21)` at low
alpha, ground wash ≈ `(1.0, 0.48, 0.20)` at ~0.20 alpha.

**Provenance.** Mark every new constant `AUTHORED` or
`DERIVED from ice_area_storm`, with a one-line reason. **Do not run a
reference-footage measurement pass** — see §5.

**Risk:** `smoothstep`/`fract` sign errors produce embers that pop at the wrap
boundary or sink instead of rising; both are immediately visible in the debug
scene. The likelier subtle failure is losing determinism by introducing any
frame-accumulated term — check `flurry: exact` still reads *exact* in the HUD
after the shader lands.

**Adds to final validation coverage:** embers rise and spiral; colour cools with
height; the column tapers, leans, flickers, and shrinks; density thins toward
the crown; scrub stays frame-exact; node/draw-call/particle asserts hold.

---

### FIRE-2 — Register the profile, add the cross ground wash, wire the carrier

**Model:** Sonnet 5 / GPT Terra
**Depends on:** FIRE-1
**Files:** `src/presentation/effects/SpellVfxCatalog.gd`,
`src/presentation/effects/VfxTextures.gd`, `data/spells.json`,
`BACKLOG_LONGTERM.md`

**End state:**

- One new row in `SpellVfxCatalog.entries()`: `profile_id`
  `"fire_area_storm"`, display name `"Fire Area Storm"`, factory
  `Callable(FireStormEffectScript, "createPlayback")`, hold fraction and
  `max_live` from `FireStormProfile`.
- `VfxTextures.groundWash()` takes a shape selector rather than a bool, gaining
  a **cross** variant alongside disc and diamond, cached per shape like the
  existing two. Cross mask over normalized `[-1, 1]` UVs, arm half-width
  `0.5 / (radius + 0.5)`:
  ```
  d = min( max(|v| / armHalf, |u|), max(|u| / armHalf, |v|) )
  alpha = pow(1 - clamp(d, 0, 1), 2) * 0.24
  ```
  Update `IceStormEffect`'s call site for the changed signature — a mechanical
  edit, no behaviour change for ice.
- `Smoke Tower` in `data/spells.json` gains `"VFX_PROFILE": "fire_area_storm"`.
  **This is the only gameplay-data file this plan touches, and it adds a key
  with no gameplay effect** (`SPELL_CATALOG_SCHEMA.md` §`VFX_PROFILE`).
- Trim the `BACKLOG_LONGTERM.md` footprint-shape entry to reflect that the
  ground-wash half of the `cross` gap is now closed, leaving the particle-field
  half recorded. Describe the work; do not cite an item label.

**Risk:** low. The `groundWash()` signature change is the only cross-effect
edit; confirm the ice storm still renders its diamond wash afterward.

**Adds to final validation coverage:** the profile resolves and is selectable in
the debug harness; `Smoke Tower` plays the fire storm in battle; the cross
ground wash matches the plus-shaped area; ice is unaffected.

---

### FIRE-3 — Final validation

**Model:** Opus 5 / GPT Sol
**Depends on:** FIRE-1, FIRE-2

The only item performing full manual gameplay and integration validation, and
the only one marking covered items done.

1. **Debug scene.** `--effect=fire_area_storm`. Sweep radius 1–5; confirm the
   column stays inside the footprint and the diamond boundary visibly breathes
   as it rotates. Exercise every layer toggle, seed pin, scrub in both
   directions, overlap, mode switch, playback scale.
2. **The poetic criteria.** Walk §3's seven bullets explicitly and confirm each
   one reads on screen. Name any that do not.
3. **Determinism.** Confirm the HUD still reports `flurry: exact`; scrub
   backward and forward to the same `t` and confirm an identical frame.
4. **Battle integration.** Cast `Smoke Tower` on flat ground, on uneven ground,
   at a board edge, and on an empty tile. Confirm the effect covers the cross
   area, composites through the CRT pass, and does not z-fight terrain or units.
5. **Ice cycle validation, carried over.** This step and the next discharge the
   ice cycle's own unrun final validation — they are not optional regression
   spot-checks. Cast `Ice Plow` and confirm: the storm covers exactly the
   diamond of tiles that take damage, at several radii, on flat and uneven
   ground and clipped at a board edge; no flakes fall outside the footprint;
   the canopy shows the core-to-edge falloff the constant-resolution item wired
   in (this was judged only by eye in the debug scene and never confirmed in
   battle); and the shared `groundWash()` signature change did not disturb it.
6. **Overlap, cap, skip, pause, speed, leak.** Two live storms halve intensity
   and restore on expiry; a third disposes the oldest; pause and speed reach the
   effect. **Skip specifically:** the ice cycle moved `_active_cast_effect`
   clearing into `_on_live_effect_exiting`, and that behaviour change was never
   exercised — confirm skipping during an effect's trailing damage numbers now
   settles the storm rather than leaving it playing. 20+ casts return node count
   to baseline.
7. `git diff --check`; only task-owned files staged.

Capture screenshots from steps 1 and 4 and reference their paths in the
Resolution.

---

## 5. Deliberately not doing

Recorded so a later session does not read these as oversights:

- **No reference-footage measurement pass.** The ice storm's `MEASURED`/
  `ESTIMATED` provenance came from real footage decomposition — the single most
  expensive part of that cycle. Fire's constants are authored or derived, and
  labelled as such. If fire ever needs reference fidelity, that is its own
  scoped task with its own authorization.
- **No `SpellVfxProfile` resource refactor.** Deferred again, deliberately —
  see §2. Revisit at a third elemental effect.
- **No shared base class between the two storm effects.** Same reason.
- **No cross-shaped particle field.** The column is radial by design; only the
  ground wash carries the cross. The remaining gap stays in the backlog.
- **No new fire spell.** `Smoke Tower` is the carrier. A larger fire area spell
  is a content decision, not a presentation one.
- **No change to `elementColor`.** Like the ice storm, `createPlayback` ignores
  its `_elementColor` argument and owns its palette. Consistent with the
  existing pattern.

---

## 6. Resolution notes

- **FIRE-1** — implemented; pending end-of-plan validation.
  Three new files: `fire_storm_vortex.gdshader`, `FireStormProfile.gd`,
  `FireStormEffect.gd`, with `.uid` sidecars.

  **Built as specified.** The shader is the plan's math verbatim, including the
  exact diamond polar form. Layer roster is the planned six; frost veins and
  hero shards are gone. Actuals: **6 nodes, 5 draw calls, 180 particles**
  (140 column + 40 motes) against budgets of 12 / 14 / 220.

  **Two decisions made in-item:**
  1. The ember draw material neutralises albedo and emission to white before
     use. `VfxTextures.flurryMaterial()` is built ice-tinted and sets
     `vertex_color_use_as_albedo`, so its albedo would have multiplied against
     the per-ember colour the shader writes to `COLOR` and skewed the whole
     hot-to-cool gradient blue. Without this the palette work is invisible.
  2. The smoke crown fades in on `smoothstep(0.10, 0.34)` rather than tracking
     `onset` like every ice layer, and lingers past the ember die-off — smoke
     that appears simultaneously with its own fire reads wrong.

  **Smoke check, and what it does not cover.** `--import --headless` generated
  both `.uid` sidecars and registered `FireStormEffect`/`FireStormProfile` in
  the global class cache, which confirms both scripts parse. The progress-dialog
  errors that run printed are the known import-harness noise documented in
  `docs/DEVELOPMENT.md`, not project errors.

  **An earlier probe was inconclusive and is recorded so it is not repeated:**
  launching `VFXDebugScene` directly does *not* rescan the filesystem, so
  nothing referenced the new files and they were never parsed — it printed clean
  while proving nothing. A new `class_name` script needs the import pass, not a
  scene launch. **The shader has still never been compiled by the GPU** (that
  needs a live instance, which requires the catalog row in FIRE-2) and nothing
  has been seen on screen.
- **FIRE-2** — implemented; pending end-of-plan validation.
  Catalog row added, ground-wash shape selector generalized, `Smoke Tower`
  wired. First frames of the fire storm rendered.

  **Ground wash went further than "add a cross variant."** The `groundWash()`
  bool became a `GroundWashShape` enum with a `groundWashShapeFor(areaShape)`
  mapper, and the three near-identical generator functions collapsed into one
  that computes a normalized distance per shape and shares a single falloff and
  opacity — so the shapes cannot drift apart in visual weight as they are
  tuned. Cross arms are one tile wide regardless of reach, so unlike the
  diamond and disc that mask is *not* self-similar across radii and is cached
  per `(shape, radius)`.

  **`line` deliberately has no mask.** Its footprint depends on cast direction,
  which the ground wash never receives, so it falls back to the disc. Recorded
  in the mapper's own comment.

  **Tuning discovered in-item — the column is not a field.** Two values had to
  move a long way off their ice-derived starting points, both for the same
  reason: a vortex concentrates its particles into a fraction of the volume a
  flat storm field spreads them across, so per-pixel additive overlap is far
  higher at equal counts.
  - Ember alpha at ice's 0.62 clipped the core to flat white and made the
    entire hot-to-cool gradient invisible. Now `EMBER_ALPHA = 0.34`, promoted
    to its own uniform: it had been read from `ember_hot_color.a`, which
    silently ignored the mid/cool alphas and would have wasted a later tuning
    session.
  - Particle count at ice's 180 was a continuous haze with no individual ember
    and therefore no legible spiral. Now **80 + 24 = 104**. Density here is a
    *readability* constraint, not a performance one — worth knowing before
    anyone "restores" it toward the budget.
  - Ground wash dropped to alpha 0.13, below even the ice storm's 0.18: the
    column already spills its own glow downward and a stronger wash flattened
    the footprint into one orange sheet.

  **Verified:** shader compiles and runs; build-time node/draw-call/particle
  asserts hold; `--effect=fire_area_storm` resolves through the catalog;
  `spells.json` parses (59 spells) with `Smoke Tower` carrying the profile;
  **ice storm renders unchanged** after the shared-signature change.

  **Not yet verified — left to FIRE-3:** the spiral has only been judged from
  single static frames, and winding/differential rotation is inherently a
  multi-frame reading. Nothing has been seen in battle, at 640×480 through the
  CRT pass, at the `cross` footprint its real carrier uses (the debug harness
  always passes `"circle"`), or at radii other than 2.
- **FIRE-3** — not started
