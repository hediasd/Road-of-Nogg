# Spell VFX Overhaul — Delegation Plan

**Written 2026-08-02.** This is a standalone plan file, separate from
`implementation_plan.md`. It exists because the spell-cast effect needs a
multi-session rebuild and the user asked for the whole design captured up front.

**Relationship to `implementation_plan.md`:** this file does not replace it.
When execution starts, copy the item being worked into `implementation_plan.md`
per the normal one-plan-at-a-time lifecycle, or adopt this file wholesale as the
current cycle's plan and delete it on completion. Do not run both as active
plans simultaneously. The `VFX-n` labels below are transitory: **no file outside
this plan may cite them** — not `docs/`, not the backlogs, not source comments,
not commit messages. Describe the work instead.

**Pre-existing uncommitted work.** At the time of writing, `git status` showed
modifications to `src/presentation/BattleCameraController.gd`,
`src/presentation/GodotVisualAdapter.gd`, and
`src/systems/BattlePresentationController.gd` that this plan does not own.
`VFX-2` and `VFX-6` touch two of those files. The first executing session must
resolve those changes with the user — commit, stash, or confirm they are
disposable — before starting. Do not clean or overwrite them.

---

## 1. Goal

The current spell-cast effect is a flat two-layer aura that reads as a
grey-blue smudge regardless of element. The target is the visual language of
Ragnarok Online's spell effects — specifically the two references the user
supplied:

- **Storm Gust** (classic and modernized): an expanding ground ring, a dense
  field of small bright particles rising inside it, chunky ice shards flung
  outward, and a soft cloud mass hovering above the impact point. The
  "modernized" version differs from "classic" mainly in particle *count* and
  *softness* — many more, much smaller, softer sparkles instead of a few large
  hard shards.
- **Heal aura**: a green ground ring at a unit's feet with a continuous upward
  stream of soft motes, parented to the unit so it follows them, looping for a
  fixed duration rather than firing once.

Scope for this plan: **one shared cast effect, tinted by element** — the user
confirmed that is acceptable for now. `VFX-7` optionally adds per-element shape
variation and is explicitly droppable.

The deliverable the user verifies is `scenes/debug/VFXDebugScene.tscn`. Every
implementation item must be visible and inspectable there.

---

## 2. Established facts (verified 2026-08-02 — do not re-derive)

### Render pipeline

- Godot **4.4**. Main scene `res://scenes/Battle25D.tscn`.
- The battle world renders into a **`SubViewport` at 640×480** with
  `own_world_3d = true`, `msaa_3d = MSAA_DISABLED`,
  `screen_space_aa = SCREEN_SPACE_AA_DISABLED`
  (`src/presentation/RetroRenderController.gd:41`, `:50`, `:82`–`:88`).
  That viewport's texture is then drawn through a CRT shader
  (`assets/shaders/crt_display.gdshader`).
- Battle camera is **orthogonal**, `size = 14.0`, at `Vector3(6, 15, 14)`
  (`src/systems/BattlePresentationController.gd:103`–`:108`).
- The battle `Environment`
  (`src/systems/BattlePresentationController.gd:90`–`:100`) uses
  `BG_CANVAS`, ambient colour `0.8`, SSAO/SSIL off, `TONE_MAPPER_LINEAR`, and
  **glow is not enabled**.
- `scenes/debug/VFXDebugScene.tscn` is a **plain full-resolution perspective
  scene** — `Camera3D` at `(0, 2.8, 3.2)` with `fov = 55`, its own
  `Environment` (ambient `0.1`, energy `0.5`), a 20×20 `PlaneMesh` ground, a
  `SpawnAnchor` node, and a `HUD/PanelContainer/Label`. It does **not** go
  through `RetroRenderController`. What you see there is not what ships.

### Current effect

- `src/presentation/effects/SpellCastAura.gd` — static entry point
  `spawn(parent: Node3D, world_pos: Vector3, element_color: Color) -> void`.
  Two layers: a 2×2 `PlaneMesh` ground decal at `y = 0.025` using
  `spell_aura.gdshader`, and **7** `GPUParticles3D` wisps. Container self-frees
  after `_CLEANUP_DELAY = 1.4` seconds. Shared statics `_noise_tex`
  (`NoiseTexture2D` 128², seamless simplex FBM) and `_wisp_tex`
  (`GradientTexture2D` 32×64 radial).
- `assets/shaders/spell_aura.gdshader` — `shader_type spatial`,
  `render_mode unshaded, blend_add, depth_draw_never, cull_disabled`. Uniforms:
  `aura_color`, `noise_tex`, `lifetime_progress` (0→1), `intensity` (6.0),
  `ring_width` (0.13), `edge_distortion` (0.07), `scroll_speed` (0.4). Polar
  noise sampling; ring centre expands `0.04 → 0.42`; centre glow decays by
  progress `0.45`; global fade `smoothstep(0.65, 1.0, progress)`.
- **Single call site**: `src/presentation/GodotVisualAdapter.gd:737`–`:738`,
  inside `_start_bump_animation`, spawning at the **caster's** position
  (`originalPos`) with `BattleMeshFactoryScript.elementColor(action.element)`.
  Nothing spawns at the target.
- The bump tween holds the visual queue for **0.25 s**
  (`_queue.activate(tween, action, 0.25)`) while the aura lives **1.4 s**. The
  effect already outlives its queue slot; see the `VFX-6` timing decision.
- `BattleMeshFactory.elementColor` (`src/presentation/BattleMeshFactory.gd:41`)
  maps 11 element strings to colours; unknown → grey `(0.5, 0.5, 0.5)`.
  Elements: `fire water ice wind earth wood thunder darkness light steel` plus
  the `none`/default fallback.
- `data/spells.json` is a flat JSON list. Keys observed: `NAME`, `ELEMENT`,
  `DAMAGE`, `RANGE`, `RADIUS`, `RANGE`, `MAX_HEIGHT_DELTA`, `CAN_TARGET_EMPTY`,
  `TARGET_TYPE`, `HEALS`, `INFLICTS_STATUS`, `BYPASS_LOS`, `DESC`.
  **This plan does not modify `data/spells.json`.**

### Why the current effect looks flat — root causes

1. **No glow.** The shader writes `EMISSION = color * intensity` with
   `intensity = 6.0`, but with glow disabled that just clips to white. Every
   bright pass in every layer is wasted. This is the single largest contributor.
2. **Two layers, seven particles.** RO effects are 4–6 simultaneous layers with
   hundreds of small particles. Seven wisps cannot read as an effect.
3. **No phase structure.** One monotonic `lifetime_progress` tween means no
   anticipation, no impact accent, no settle. Everything happens at once, softly.
4. **No bright core.** RO effects blow out to white at the centre on impact.
   The current centre glow decays before it ever reads as a flash.
5. **Tuned in a scene that does not match the game.** See `VFX-1`.

---

## 3. Execution rules

Per `AGENTS.md`:

- **One item per session, starting from a clean `git status`.**
- **Check the model before starting.** Compare the item's `Model` field to the
  model actually running. If the running model is more capable than the item
  needs, say so and stop.
- Commit at every item boundary. Item state lives in the Resolution notes and
  `git log`, not in conversation history.
- Implementation items resolve to **implemented; pending end-of-plan
  validation**. Only `VFX-8` marks items done.
- **Do not launch the game after each implementation item.** A narrow
  compile/load probe is allowed only where a later item cannot safely build on
  potentially unusable code; record it as a smoke check, not acceptance.
  Exception: `VFX-1`, `VFX-3`, `VFX-4`, `VFX-5`, and `VFX-6` may run
  `VFXDebugScene` directly (F6 / `--path . scenes/debug/VFXDebugScene.tscn`),
  because that scene *is* the item's deliverable surface and running it does not
  require the battle. Record those as smoke checks.
- At each item boundary: inspect the focused diff, run `git diff --check`, stage
  only task-owned files.
- Windows: run from the repository root, pass `--path .`, use bounded waited
  processes, force LF line endings on generated text. See
  `docs/DEVELOPMENT.md` §"Windows execution safeguards".
- **New `.gd` and `.gdshader` files generate `.uid` sidecars in Godot 4.4.**
  Commit them alongside their source file.
- Update `BACKLOG_CRITICAL.md` / `BACKLOG_LONGTERM.md` as work reveals
  genuinely out-of-scope follow-ups.

---

## 4. Items

### VFX-1 — Render the debug scene through the real retro pipeline

**Model:** Opus 5 / GPT Sol
**Depends on:** nothing
**Files:** `scenes/debug/VFXDebugScene.tscn`,
`src/presentation/debug/VFXDebugController.gd`, possibly
`src/presentation/RetroRenderController.gd`

Every later item is tuned by eye in this scene. Today it renders at native
resolution through a perspective camera with a different environment, so an
effect tuned there will look materially different in battle — different pixel
density, no CRT scanlines, no colour crush, different camera angle and
projection. Fix the harness before authoring against it.

**End state:**

- `VFXDebugController` instantiates `RetroRenderController` the same way
  `BattlePresentationController` does, and parents the ground, spawn anchor,
  lighting, and camera into `retro_renderer.world_root`.
- The debug camera matches battle framing: `PROJECTION_ORTHOGONAL`,
  `size = 14.0`, positioned to frame the spawn anchor from the same relative
  angle as `Vector3(6, 15, 14)` looking at the board. Compute the offset from
  the anchor rather than hardcoding `(6, 15, 14)` — the anchor is at origin, the
  battle camera is not.
- The debug `Environment` is built from the **same code path** as the battle
  environment, so a change to one cannot silently diverge from the other. If
  that requires extracting the environment construction out of
  `BattlePresentationController._setup_environment` (or whatever the enclosing
  function is named) into a small shared builder, do that extraction as
  composition — a static factory returning a configured `Environment`. Do not
  make the debug scene depend on `BattlePresentationController` or on anything
  in `src/battle_sim/`.
- A **retro-pipeline toggle** key flips between the retro path and a plain
  full-res view, so the user can inspect fine particle detail and then confirm
  how it survives 640×480 + CRT. Default to **retro on**.
- The HUD label reports which mode is active.

**Decision to make in-item:** whether `RetroRenderController` can be
instantiated standalone or is entangled with battle setup. If extraction is
needed, keep it minimal and name it plainly; do not restructure the renderer.

**Risk:** `RetroRenderController` may assume a host node, a UI layer, or a
`size_changed` signal wiring that only `BattlePresentationController` provides
(it connects `host.get_viewport().size_changed` at `:134`). If standalone
instantiation proves invasive, fall back to matching the battle *camera and
environment* exactly in the debug scene and driving a 640×480 `SubViewport`
manually, and record why in Resolution. Do not force an extraction that
destabilises battle rendering.

**Adds to final validation coverage:** debug scene renders at 640×480 through
the CRT path with orthogonal battle-matched framing; the retro toggle switches
modes without error; battle rendering is unchanged.

---

### VFX-2 — Enable glow so emissive VFX can actually bloom

**Model:** Opus 5 / GPT Sol
**Depends on:** VFX-1 (so the effect of the change is judged in a truthful scene)
**Files:** `src/systems/BattlePresentationController.gd` (or the shared
environment builder from `VFX-1`)

**This item changes the look of the whole game and needs the user's eye.** It is
not blocking — proceed with the conservative default below — but say plainly in
the Resolution that the user should confirm the result, and show it in the debug
scene before the battle.

Without glow, every additive layer in every later item is throwing away its
brightness. With glow configured so only super-white pixels bloom, VFX gains
enormous perceived quality while ordinary retro-shaded surfaces stay untouched.

**End state — conservative default:**

```
environment.glow_enabled = true
environment.glow_intensity = 0.55
environment.glow_strength = 1.0
environment.glow_bloom = 0.0
environment.glow_hdr_threshold = 1.0     # only >1.0 emission blooms
environment.glow_hdr_scale = 2.0
environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
```

The `glow_hdr_threshold = 1.0` is the load-bearing value: it confines bloom to
emissive VFX and leaves `retro_surface.gdshader` output alone. Verify that
claim visually rather than assuming it — the retro materials accept an
`emission_strength` parameter (`BattleMeshFactory.createMaterial`) and some
callers may pass a value above zero.

**Verify, do not assume:**

- Glow must work inside a `SubViewport` with `own_world_3d = true`. Confirm it
  renders; if it does not, find out whether the viewport needs an HDR-capable
  render target and record the finding.
- Glow at 640×480 will be **chunky**, with visibly quantised glow levels. That
  may read as authentically retro or as broken. Judge it in the debug scene with
  the retro toggle and tune `glow_intensity` / `glow_hdr_scale` accordingly.
- `TONE_MAPPER_LINEAR` clips hard above 1.0. If bloom looks like flat white
  blobs rather than a soft falloff, evaluate `TONE_MAPPER_FILMIC` or
  `TONE_MAPPER_ACES` — but treat a tonemap change as a whole-game art decision
  and surface it to the user rather than deciding unilaterally.

**This item legitimately changes how existing visuals are reported to look.**
Any prior screenshot or "looks correct" note about battle brightness is
superseded. Do not try to restore the previous appearance.

**Risk:** glow applies to the entire scene, not just VFX. If existing monster
materials emit above the threshold, they will bloom unexpectedly. Mitigation:
audit `emission_strength` call sites before committing; if a broad bloom appears,
raise the threshold rather than reworking materials.

**Adds to final validation coverage:** emissive spell layers bloom in battle and
in the debug scene; monsters, terrain, and UI show no unintended bloom; the CRT
pass composites the glow without artefacts.

---

### VFX-3 — Debug harness controls for authoring and verification

**Model:** Sonnet 5 / GPT Terra
**Depends on:** VFX-1
**Files:** `src/presentation/debug/VFXDebugController.gd`,
`scenes/debug/VFXDebugScene.tscn`

The user's acceptance path is "look at it in the test scene". Give that scene
the controls needed to actually judge an effect, and to catch problems the
1.4-second real-time playback hides.

**End state — controls (existing left/right element cycling and Space retrigger
are preserved):**

| Key | Behaviour |
| --- | --- |
| `←` / `→` | cycle element (existing) |
| `Space` | retrigger effect (existing) |
| `R` | toggle retro pipeline (from `VFX-1`) |
| `S` | cycle time scale: 1.0 → 0.5 → 0.25 → 0.1 → 1.0 |
| `P` | pause/resume the effect |
| `,` / `.` | when paused, scrub `lifetime_progress` by ∓0.02 and step particle preview |
| `D` | toggle a **dummy unit** at the spawn anchor — a capsule at monster scale, so the effect is judged against a body, not empty ground |
| `L` | toggle a looping auto-retrigger every 2 s, for watching timing without pressing keys |
| `F12` | write a screenshot PNG to the scratch/temp directory and print the path |

**Key-collision constraint:** a recent fix moved a dev-canvas toggle off the
game's accept key precisely because dev controls were stealing gameplay input.
`VFXDebugScene` is standalone so the risk is lower, but do not bind `Enter`,
`Escape`, or any key bound in the project's input map. Read the input map before
choosing bindings and adjust the table above if a conflict exists.

**Also required:**

- The HUD label reports, at minimum: element name and index, time scale, paused
  state, current `lifetime_progress`, retro on/off, and a live **particle count
  and draw-call count** read from `Performance.get_monitor(...)`. The particle
  count is how `VFX-6` proves it stayed inside budget.
- Scrubbing must drive the same `lifetime_progress` uniform the runtime tween
  drives, so a paused frame is a real frame of the effect and not an
  approximation.

**Risk:** `Engine.time_scale` affects `GPUParticles3D` simulation and `Tween`
playback differently from `AnimationPlayer`; slow-motion may desynchronise the
shader tween from the particles. If they drift, drive the shader uniform from a
manual `_process` accumulator scaled by `Engine.time_scale` rather than a
`Tween`, and note the change so `VFX-6` builds on the same mechanism.

**Adds to final validation coverage:** every debug control responds; scrubbing
produces stable frames; the HUD readout is accurate; screenshots write
successfully.

---

### VFX-4 — Procedural texture library and reusable layer builders

**Model:** Sonnet 5 / GPT Terra
**Depends on:** nothing (can run in parallel with VFX-1..3; ordering here is for
a single-threaded session sequence)
**Files:** new `src/presentation/effects/VfxTextures.gd`, new
`src/presentation/effects/VfxLayers.gd`

This is the mechanical foundation `VFX-6` composes from. It is deliberately
plain GDScript static builders rather than `.tscn` effect scenes, to match the
existing idiom in `SpellCastAura.gd` and `BattleMeshFactory.gd` and to keep
element tinting a parameter rather than a per-instance override. The cost is the
loss of Godot's inspector live-preview; `VFX-3`'s scrub and slow-motion controls
are the compensating tuning loop.

**`VfxTextures.gd` — cached procedural textures, one static getter each,
built on first use and reused thereafter (extend the `_ensure_shared_resources`
pattern already in `SpellCastAura.gd`, and move that file's `_noise_tex` and
`_wisp_tex` here):**

| Getter | Shape | Purpose |
| --- | --- | --- |
| `soft_dot()` | 32² radial gradient, opaque centre → transparent edge | sparkles, motes |
| `hard_spark()` | 16² radial with a tight falloff (alpha 1.0 to ~0.75 radius) | bright pinpoint sparkles |
| `streak()` | 16×64 vertical gradient, soft both ends | rising wisps, wind streaks |
| `cloud_puff()` | 64² FBM-noise-masked radial | the cloud mass above the burst |
| `ring_gradient()` | 64×4 1-D ramp, transparent → white → transparent | shockwave ring |
| `swirl_noise()` | 128² seamless simplex FBM (the existing `_noise_tex`) | shader distortion |

Keep every texture procedural. This project ships no VFX art assets and this
plan does not introduce any.

**`VfxLayers.gd` — static builders. Each returns a configured, unparented node;
the caller adds it to the tree and sets `emitting`. Each takes an explicit
duration so `VFX-6` owns all timing:**

```gdscript
static func ground_ring(color: Color, radius: float, duration: float) -> MeshInstance3D
static func sparkle_field(color: Color, radius: float, height: float, count: int, duration: float) -> GPUParticles3D
static func rising_motes(color: Color, radius: float, height: float, count: int, duration: float) -> GPUParticles3D
static func converging_motes(color: Color, from_radius: float, count: int, duration: float) -> GPUParticles3D
static func shard_burst(color: Color, count: int, speed: float, duration: float) -> GPUParticles3D
static func shockwave(color: Color, max_radius: float, duration: float) -> MeshInstance3D
static func core_flash(color: Color, size: float, duration: float) -> MeshInstance3D
static func cloud_mass(color: Color, size: float, height: float, duration: float) -> GPUParticles3D
static func impact_light(color: Color, energy: float, duration: float) -> OmniLight3D
```

**Shared material conventions for every additive layer** — get these right once
here so `VFX-6` cannot get them wrong:

- `transparency = TRANSPARENCY_ALPHA`, `blend_mode = BLEND_MODE_ADD`,
  `shading_mode = SHADING_MODE_UNSHADED`, `billboard_mode = BILLBOARD_ENABLED`
  for particle quads.
- `vertex_color_use_as_albedo = true` so `color_ramp` drives fade.
- `emission_enabled = true` with `emission_energy_multiplier` **above 1.0** —
  this is what `VFX-2`'s glow threshold keys on. Values around `2.0`–`4.0`.
- `texture_filter = TEXTURE_FILTER_NEAREST` on particle draw materials, to match
  the project's pixel aesthetic. 3D materials do **not** inherit the project's
  canvas texture filter setting, so this must be set explicitly. Verify at
  640×480 whether nearest or linear reads better and record the choice.
- `disable_receive_shadows = true`; VFX should never be shadowed.

**Notes on specific builders:**

- `converging_motes` runs particles *inward*. `ParticleProcessMaterial` has no
  native "move toward origin" mode; use `EMISSION_SHAPE_RING` at `from_radius`
  with `direction` pointing inward is not expressible per-particle either. Use
  `radial_accel_min/max` **negative** with an emission ring — negative radial
  acceleration pulls toward the emitter origin. Verify this reads as convergence
  at the durations used.
- `shard_burst` uses a small `BoxMesh` fragment draw pass, not a quad — the
  classic Storm Gust shards are opaque geometry, not billboards. Reuse the
  approach already in `GodotVisualAdapter._spawn_capsule_shatter`
  (`src/presentation/GodotVisualAdapter.gd:690`) as the reference for
  fragment sizing and gravity.
- `impact_light` may have no visible effect if the retro surface shaders ignore
  scene lights. Verify against a dummy unit before investing in it; if retro
  materials are unlit, record that and let `VFX-6` drop the layer.
- `core_flash` and `shockwave` are camera-facing quads for the flash and a
  ground-plane quad for the wave respectively — do not billboard the shockwave.

**Risk:** low individually, but this file becomes load-bearing. Keep each
builder independently previewable so `VFX-6` can bisect a bad-looking
composition. Consider a debug key in `VFX-3`'s harness to spawn one isolated
layer at a time; add it if it costs little.

**Adds to final validation coverage:** each layer builder produces a visible,
correctly-tinted, self-terminating effect; no layer leaks nodes; texture cache
builds once and is reused.

---

### VFX-5 — Rebuild the ground ring shader for the RO disc look

**Model:** Sonnet 5 / GPT Terra
**Depends on:** VFX-2 (brightness is judged with glow on)
**Files:** `assets/shaders/spell_aura.gdshader`

The current shader draws one soft expanding ring with a centre glow. The RO
reference ground element is a **flat bright disc with a hard rim**, layered
concentric rings moving at different rates, and faint radial streaks reading as
energy flowing inward or outward.

**End state — keep the existing uniform names and the single
`lifetime_progress` (0→1) contract** so the call site and `VFX-3`'s scrub keep
working. Add:

```glsl
uniform int   ring_count       : hint_range(1, 3)     = 2;
uniform float inner_ring_scale : hint_range(0.2, 1.0) = 0.55;
uniform float rim_sharpness    : hint_range(0.0, 1.0) = 0.7;
uniform float streak_strength  : hint_range(0.0, 1.0) = 0.35;
uniform float streak_count     : hint_range(4.0, 48.0)= 18.0;
uniform float haze_strength    : hint_range(0.0, 1.0) = 0.25;
uniform float core_flash_boost : hint_range(0.0, 4.0) = 2.5;
```

Behaviour:

- **Concentric rings.** Emit `ring_count` rings; the inner ring sits at
  `inner_ring_scale` of the outer ring's radius and expands on a slightly
  different curve, so the rings separate over the lifetime instead of moving as
  one band.
- **Sharper rim.** `rim_sharpness` narrows the outer edge of the ring falloff
  relative to the inner edge, giving a defined leading edge with a soft trailing
  wash — the current symmetric `smoothstep` pair reads as a blur.
- **Radial streaks.** Modulate brightness by
  `sin(angle * streak_count + TIME * scroll_speed * k)` masked to the disc
  interior, scaled by `streak_strength`. Keep it subtle; this is texture, not a
  second effect.
- **Interior haze.** A dim wash filling the disc inside the outer ring at
  `haze_strength`, so the ground reads as *lit* rather than as a bare outline.
  Fades faster than the ring.
- **Real core flash.** At `lifetime_progress` near 0, blow the centre to white
  with `core_flash_boost`, decaying within roughly the first 12% of life. This
  is the accent that makes the cast read as an impact. The current
  `center_glow` decays over 45% of life, which is too slow to register as a
  flash.
- Keep `render_mode unshaded, blend_add, depth_draw_never, cull_disabled` — all
  four are correct for a ground decal that must not z-fight or occlude.

**Risk:** GDShader compile errors surface at load and can leave the material
silently unrendered rather than erroring loudly. After editing, run
`VFXDebugScene` and confirm the ring renders before committing — record it as a
smoke check. Also, `ring_count` as an `int` uniform driving a loop must use a
compile-time-bounded loop; if the driver rejects a dynamic loop bound, unroll to
a fixed two-ring form and drop the uniform.

**Adds to final validation coverage:** ground ring shows two separating
concentric rings with a sharp rim, visible streaks, interior haze, and a
sub-0.2 s white core flash, correctly tinted per element.

---

### VFX-6 — Compose the layered, phased cast effect

**Model:** Opus 5 / GPT Sol
**Depends on:** VFX-3, VFX-4, VFX-5 (and benefits from VFX-2)
**Files:** `src/presentation/effects/SpellCastAura.gd`, possibly
`src/presentation/GodotVisualAdapter.gd`

This is the item that makes the effect good. It is a composition and timing
exercise, not a mechanical one.

**Hard constraint — do not change the public signature:**
`SpellCastAura.spawn(parent: Node3D, world_pos: Vector3, element_color: Color)`
stays exactly as-is, so `GodotVisualAdapter.gd:738` needs no change and the
debug controller keeps working.

**Phase structure** (times are for a total life of ~1.5 s; tune by eye):

**Phase A — Charge, 0.00–0.30 s.** Anticipation. The ground ring fades in dim
and small. `converging_motes` pull inward from radius ~1.2 to the centre. No
brightness yet. This phase is what the current effect completely lacks, and it
is why the current version has no sense of a spell being *cast*.

**Phase B — Burst, 0.30–0.55 s.** The accent.
- `core_flash` blows to white, scaling ~0.2 → 1.4 with alpha 1 → 0 over ~0.18 s.
- `shockwave` expands ~0.2 → 2.2 world units, fading.
- `shard_burst` throws 12–18 fragments outward and up under gravity.
- `sparkle_field` ignites: **80–140** small additive points in a disc, drifting
  up with twinkle driven by `color_ramp`. This density is what separates the
  reference images from the current seven wisps.
- `impact_light` pulses, if `VFX-4` found lights affect retro surfaces.
- The shader's `core_flash_boost` fires here via `lifetime_progress`.

**Phase C — Settle, 0.55–1.50 s.** The tail. Sparkles keep drifting and fading,
the ground ring expands and dims, a few embers linger, and `cloud_mass` drifts
slowly above the centre and dissolves — the soft mass visible at the top of both
Storm Gust reference images.

**Timing decision — surface this to the user in the Resolution.** The bump tween
holds the visual queue for **0.25 s** (`_queue.activate(tween, action, 0.25)`)
while the effect now runs ~1.5 s. Three options:

1. **Leave it.** Effects overlap into subsequent actions. Cheapest; may look
   chaotic in a fast AI turn with several casts in a row.
2. **Extend the queue slot** for element-carrying actions to roughly Phase B's
   end (~0.6 s), so the next action starts after the accent but while the tail
   is still visible. **Recommended default** — it reads deliberately without
   stalling the turn.
3. **Full gate** on the whole 1.5 s. Safest visually, noticeably slower turns.

Implement option 2, state plainly that it is a pacing change the user should
judge, and note that this changes observed turn pacing so a later session does
not "fix" it back.

**Budget.** Total simultaneous particles from one cast must stay under **~250**,
verified with `VFX-3`'s HUD counter. At 640×480 the fill cost of large additive
quads matters more than the particle count; prefer many small quads over few
large ones.

**Risk:** the highest-risk item in the plan. Overlapping additive layers can
saturate to a white blob — exactly the failure mode the current effect already
has, at higher cost. Mitigations: build the phases in order and inspect each
with the scrub control before adding the next; keep per-layer
`emission_energy_multiplier` modest and let glow do the work; if it saturates,
reduce layer count before reducing brightness. Also ensure the container's
self-free delay covers the longest layer — the existing `_CLEANUP_DELAY = 1.4`
must be raised in step with the new total, or the tail gets cut.

**Adds to final validation coverage:** cast effect shows distinct charge, burst,
and settle phases; particle count stays under budget; no node leaks across
repeated casts; effect is correctly tinted per element; turn pacing with the
extended queue slot is acceptable.

---

### VFX-7 — *(Optional, droppable)* Per-element shape profiles

**Model:** Opus 5 / GPT Sol
**Depends on:** VFX-6
**Files:** `src/presentation/effects/SpellCastAura.gd`, possibly a new
`src/presentation/effects/VfxElementProfiles.gd`

**This item is outside the confirmed scope** — the user said one shared
animation is fine for now. It is included because the user supplied *two*
reference images with fundamentally different silhouettes (an offensive burst
and a sustained heal aura), which the single burst composition cannot serve.
**Dropping this item does not affect `VFX-1` through `VFX-6` or the final
validation.** Confirm with the user before executing it.

If executed: a small data table mapping element → layer emphasis, keeping the
same phase structure and the same public signature.

| Element | Emphasis |
| --- | --- |
| `ice` | heavy `shard_burst`, cold sharp ring, low haze |
| `fire` | dense `rising_motes` as embers, turbulent ring, high haze |
| `thunder` | high `streak_strength`, very short flash, minimal tail |
| `darkness` | strong `converging_motes`, dim ring, inverted brightness curve |
| `light` | sustained `rising_motes` column, soft ring, no `shard_burst` |
| others | the `VFX-6` default composition |

The `light` row is the closest approach to the heal-aura reference. A true heal
effect additionally needs to **parent to the unit and follow it** rather than
spawn at a world position — `SpellCastAura.spawn` already accepts a `parent:
Node3D`, so the change is at the call site
(`GodotVisualAdapter.gd:738` passes `visual_parent`; passing the monster's
visual node instead would make it follow). **That call-site change is not in
this plan's scope** — record it in `BACKLOG_CRITICAL.md` as a described
follow-up, not as a citation of this item.

**Risk:** scope creep into per-spell effects, which the user explicitly deferred.
Keep the table small and data-driven; do not add per-spell branching.

**Adds to final validation coverage:** if executed, each element's profile is
visibly distinct in the debug scene while retaining the shared phase structure.

---

### VFX-8 — Final validation

**Model:** Opus 5 / GPT Sol
**Depends on:** VFX-1, VFX-2, VFX-3, VFX-4, VFX-5, VFX-6 (and VFX-7 if executed)
**Files:** this plan; fixes as needed

The only item that performs full manual gameplay and integration validation, and
the only item that marks covered items done.

**Preconditions:** every implementation item committed; working tree clean.

**Consolidated checks — run once, using integrated flows:**

1. **Debug scene pass.** Launch `scenes/debug/VFXDebugScene.tscn` bounded and
   waited. Cycle all 11 elements. For each, confirm correct tint and that the
   effect self-terminates. Exercise every `VFX-3` control: retro toggle, time
   scale cycle, pause, scrub both directions, dummy unit, loop, screenshot.
   Confirm the HUD particle count stays under 250 during a cast.
2. **Phase inspection.** With the retro pipeline **on**, pause and scrub through
   one full effect. Confirm charge, burst, and settle are individually legible
   and that Phase B's core flash is present and brief.
3. **Battle integration.** Launch `Battle25D` bounded and waited. Cast spells of
   several different elements. Confirm: the effect appears at the caster, is
   correctly tinted, blooms without saturating, composites cleanly through the
   CRT pass, and does not occlude or z-fight with terrain or units.
4. **Pacing.** With the extended queue slot from `VFX-6`, play through an AI turn
   containing multiple consecutive casts. Confirm the pacing is acceptable and
   that overlapping effects do not stack into a white-out.
5. **No regressions.** Confirm monsters, terrain, UI, status billboards, and the
   selection aura are unaffected by the glow change. Confirm no unintended bloom.
6. **Leak check.** Cast repeatedly (20+ times) and confirm node count returns to
   baseline — the effect containers must all self-free.
7. `git diff --check`; confirm only task-owned files are staged.

**Capture screenshots** from steps 1 and 3 via the `VFX-3` screenshot key and
reference their paths in the Resolution, so the user can review the result
without relaunching.

**If validation finds a defect:** fix it in this session, rerun only the relevant
consolidated checks, and record the fix and evidence here. Do not reopen prior
items to repeat the same validation.

**On success:** mark all covered items done, state that the plan is complete,
move any genuinely open work to the appropriate backlog file naming it
explicitly to the user, and delete this file's contents — its history is
recoverable with `git show <ref>:vfx_plan.md`.

---

## 5. Resolution notes

*(Executing sessions append here. One entry per item: what was done, what was
decided, what was verified, and any finding a later item depends on.)*

- **VFX-1** — not started
- **VFX-2** — not started
- **VFX-3** — not started
- **VFX-4** — not started
- **VFX-5** — not started
- **VFX-6** — not started
- **VFX-7** — not started (optional; confirm with user before executing)
- **VFX-8** — not started
