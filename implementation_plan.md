# Spell Cast Aura Ray-Burst Rework

**Opened 2026-08-12.** The previous contents were the Ice Target Encasement
cycle, opened 2026-08-10, which built the `Ice Statue` carrier and its
target-bound ice encasement across ten implementation items. Every one of those
items is committed and was recorded as *implemented; pending end-of-plan
validation*; its consolidated final validation item never ran. At the user's
explicit direction on 2026-08-12 that cycle was **parked rather than completed**
so this aura rework could start: the unrun validation — battle integration,
adapter lifecycle, cross-effect regression captures, and live budget
confirmation — now lives as a durable description in `BACKLOG_CRITICAL.md`.
Nothing else from that cycle remained open. Its full resolution log is
recoverable with `git show bff195f:implementation_plan.md`.

Before this reset the repository was searched for the previous cycle's item
identifiers; they appeared only inside the plan file itself, so no persistent
file needed rewriting.

---

## 1. Goal

Replace the generic spell-cast aura — today a scrolling noise ring on a flat
2×2 ground plane plus seven rising wisp billboards — with **a brief flash of
pointy translucent rays erupting out of the ground**, read as energy liberated
from the elemental plane at the moment of the cast.

The user's supplied reference frame is the visual language: a crown of tall,
hard-edged, translucent light blades standing on the ground, flaring slightly
outward, white-hot where they overlap near the base, colour-fringed toward
their pointed tips, over a bright ground rupture. The lightning bolt descending
from the top of that frame is explicitly **not** part of this effect.

The finished effect must:

- read as **rays**, not as a ring, dome, cone, column, or fog — pointed,
  straight-edged, countable blades with visible negative space between them;
- **erupt from the ground upward**, with the ground rupture and the blades
  belonging to one event rather than two stacked layers;
- stay **translucent**: overlapping blades build toward white-hot, single
  blades stay see-through against terrain behind them;
- carry the **element tint** every caller already supplies
  (`BattleMeshFactory.elementColor`), from ice cyan through fire red, thunder
  yellow, darkness violet, and the neutral grey fallback, with a near-white
  base that does not erase the tint;
- be **fast** — a flash, subordinate to whatever spell-specific profile or
  damage read follows, and not an animation the player waits through;
- preserve the full `VfxPlayback` contract: pause, speed scale, exact forward
  and backward `seek_normalized()`, `skip_to_settle()`, overlap, replay at a
  fixed seed, and safe disposal;
- remain presentation-only, with no gameplay, timing, or spell-data change.

This is the **generic** profile (`profile_id == ""`), so it plays for every
spell that does not select a specific VFX profile. The user has confirmed the
current spell catalogue is placeholder, so the *number* of spells falling back
to it is not a design input; what matters is that the effect has no single
carrier to design against. Its validation scope is therefore "several elements
and several casts", not one carrier's radius and shape.

## 2. Resolved gates

### Plan file occupancy — resolved 2026-08-12

The user chose to park the Ice Target Encasement cycle rather than validate it
first. Its unrun consolidated validation is now a durable critical-backlog
description, and this plan is the repository's only delegation contract. Its
first implementation item starts from a clean `git status` as `AGENTS.md`
requires.

### Footprint scaling stays out of scope — resolved 2026-08-12

`BACKLOG_LONGTERM.md` carries an open item to make the generic aura implement
`setFootprint()` instead of staying fixed-size. The user confirmed it stays out
of this cycle, so the aura remains caster-scaled and radius-agnostic exactly as
today and the shape change is judged on its own. That backlog entry stays open
and unmodified. No item here may add radius response.

## 3. Established facts and design decisions

### The blades are geometry, not a stretched sprite

`docs/VFX_DESIGN.md` §4 already records that a radial sprite cannot be stretched
into a streak: scaling `neutralSoftDisc()` onto a long quad puts the opaque
centre in the middle and fades both ends. A pointed ray therefore comes from
authored geometry with a pointed silhouette — a narrow tapered quad or a thin
three-face wedge — with the alpha ramp across its width owned by the effect's
own shader, not from stretching an existing shared mask.

### World-vertical blades are the sharp case, not the soft one

§4's camera-plane rule exists because a quad rotated to an arbitrary world angle
sits on no pixel grid. A blade standing on the world's up axis is the exception:
under the battle camera's fixed pitch and zero roll, world up projects to screen
up, so a vertical edge stays a vertical raster line. The first item must
**confirm zero camera roll** in `Battle25D` and the debug harness before relying
on this; if roll exists, the blades fall back to the camera-plane construction
the magenta discharge already uses. Blade width is fixed in world units either
way, never as a fraction of anything.

### Translucency is authored alpha, not additive glow everywhere

The current aura is `blend_add` end to end, which is why it blows out to white.
The rays want the opposite: mostly-transparent bodies with hard edges, so that
crossing blades accumulate into the white-hot base while a lone blade stays
see-through. Expect an alpha-blended body with a small additive core, explicit
render priority, and `depth_draw_never`, with ordering proven at three camera
yaws before any extra brightness is added.

### The rupture and the blades share one origin

Each blade grows from a point on a small ground rupture footprint, on the same
normalized clock, so the ground layer reads as the fracture the light escapes
through. The old expanding noise ring is removed rather than kept underneath.

### Ownership and reuse

The effect owns its profile constants, its shader, and its blade mesh
construction. `VfxTextures` and every other shared material stay untouched, so
Ice Storm, Fire Storm, Magenta Reduction, and Ice Target Encasement cannot
regress through a shared primitive. `assets/shaders/spell_aura.gdshader` has
exactly one referencing file (`SpellCastAura.gd`) and is deleted with its `.uid`
once the rewrite lands.

### Budgets, asserted at build time and owned by the profile

- 12–18 ray blades in a single MultiMesh;
- ≤ 10 supporting instances (ground rupture, base flare, motes);
- ≤ 10 effect-owned nodes;
- ≤ 8 estimated peak draw calls;
- unlimited live count preserved (`max_live` stays 0 — the generic profile is
  the fallback for every unprofiled spell and must never evict itself).

## 4. Proof checkpoints

VFX work is shown while it is still cheap to change. These are required item
outputs, not deferred final-validation evidence.

| Checkpoint | Required proof | Owner |
| --- | --- | --- |
| Blade silhouette | `ray_burst`-only mid-flash captures at front-quarter, side, and rear-quarter yaws, through the retro path and at native. Blades are countable, pointed, and translucent; nothing reads as a ring or a solid cone. | Geometry/material item |
| Element sweep | The same frame for ice, fire, thunder, darkness, and the neutral fallback. Tint is legible in all five; none blows out to white. | Geometry/material item |
| Eruption timeline | One tight sheet from empty ground through rupture, first blades, full flash, decay, and clear. Rays visibly leave the ground rather than fading in at full height. | Choreography item |
| Composite hierarchy | Ground-only and mote-only sheets beside the full composite. The blades remain the dominant read. | Supporting-layer item |
| Final look | Live battle casts across several spells and elements, retro on and off, plus re-captures of the four specific profiles. | Final validation item |

A session whose checkpoint fails visually stops and reports the sheet to the
user. It does not layer more work over a rejected silhouette.

## 5. Items

### AURA-1 — Author the ray-burst profile, blade geometry, and translucent material

**Model:** Opus 5 / GPT Sol

**Depends on:** both resolved gates.

**Files:** new `src/presentation/effects/SpellCastAuraProfile.gd`, new
`assets/shaders/effects/spell_cast_ray_burst.gdshader`,
`src/presentation/effects/SpellCastAura.gd` (build path only), generated `.uid`
sidecars, `docs/VFX_DESIGN.md`, relevant backlog files.

**End state:**

- 12–18 blades in one MultiMesh, each a low-poly tapered form with a broad seat
  and a single pointed apex, standing on world up with a small outward tilt that
  grows with the blade's height.
- Seeded per-blade azimuth, height, width, tilt, and apex offset produce
  deliberate asymmetry — no evenly spaced picket fence, no mirrored halves.
- The effect-owned shader gives each blade a hard-edged translucent body, a
  brighter base, and a tip that fades before the apex. Overlapping blades
  accumulate toward white-hot; a single blade stays see-through.
- Element tint arrives from the existing `element_color` constructor argument;
  the palette derives base, body, and fringe from it rather than hard-coding a
  hue. The neutral grey fallback still reads as energy, not as smoke.
- Camera roll is confirmed zero before relying on screen-vertical sharpness, and
  the finding is recorded in `docs/VFX_DESIGN.md` beside the existing
  camera-plane guidance.
- Every count, dimension, alpha, palette entry, and timing constant lives in
  `SpellCastAuraProfile.gd` with `AUTHORED` / `DERIVED` / `MEASURED` labels.
  Build assertions enforce the §3 ceilings.
- `VfxTextures` and all other shared materials are unchanged.

**Risk:** alpha-blended crossing geometry is the classic sorting-error case, and
an additive fix would return the effect to the white blowout this rework exists
to remove. Solve ordering with explicit render priority and `depth_draw_never`
first, and judge at the retro viewport's native resolution before adding
brightness.

**Proof checkpoint:** blade silhouette and element sweep. Stop here if the
blades do not read as countable translucent rays.

**Adds to final validation coverage:** ray silhouette, translucency, sorting
stability across yaws, element tinting across the full palette,
owned-resource isolation, budget compliance.

**Resolution target:** implemented; pending end-of-plan validation. Run the
debug capture checkpoint, focused diff inspection, `git diff --check`, and only
the narrow import/parse probe needed to hand a usable shader forward. Do not
launch a battle.

### AURA-2 — Choreograph the ground eruption and fix the disposal lock

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-1.

**Files:** `src/presentation/effects/SpellCastAura.gd`,
`src/presentation/effects/SpellCastAuraProfile.gd`, its shader,
`docs/VFX_DESIGN.md`, `BACKLOG_LONGTERM.md`.

**End state:**

- Named authored windows cover ground charge, blade eruption, flash hold,
  decay, and clear. Every transform and every shader input is a pure function of
  normalized time and the fixed seed; nothing samples RNG or global `TIME` after
  construction.
- Blades punch up from zero height at staggered per-blade delays derived from
  their spatial role, overshoot slightly, and settle before decaying. They do
  not fade in at full height.
- Total duration stays in the current fast band (≈0.9–1.1 s) and the profile
  publishes its own `ACTION_HOLD_FRACTION`, replacing the catalog's hard-coded
  `GENERIC_ACTION_HOLD_FRACTION` so the queue's hold matches the new shape.
  This legitimately changes the reported hold value; do not restore 0.6 unless
  the new shape actually wants it.
- `seek_normalized()` reproduces every phase forward and backward;
  `skip_to_settle()` lands in a safe late-decay state rather than cutting a
  full-height flash off screen.
- Layer names cover at minimum `ray_burst`, `ground_rupture`, and `motes`, each
  independently toggleable in the harness.
- The long-standing `Object is locked and can't be freed` error on disposal at
  process/scene teardown is fixed while this file is open — the long-term
  backlog names this rewrite as its trigger — and that backlog entry is removed
  once the fix is verified.

**Risk:** a per-blade stagger implemented as accumulated state breaks backward
seek, and the old fixed-size ring hid ordering problems that a staggered growth
sequence will expose at phase boundaries. Derive all growth analytically and
prove boundary frames at tight normalized-time spacing.

**Proof checkpoint:** eruption timeline, plus two standalone timestamps captured
out of order at one seed and compared by hash.

**Adds to final validation coverage:** eruption ordering, phase continuity,
exact out-of-order seek, safe skip, queue hold fraction, clean disposal at
teardown.

**Resolution target:** implemented; pending end-of-plan validation. Debug
capture and cheap integrity checks only. Do not launch a battle.

### AURA-3 — Rebuild the ground rupture and the subordinate motes

**Model:** Sonnet 5 / GPT Terra

**Depends on:** AURA-2.

**Files:** `src/presentation/effects/SpellCastAura.gd`,
`src/presentation/effects/SpellCastAuraProfile.gd`, its shader,
`src/presentation/effects/SpellVfxCatalog.gd` (generic entry metadata only),
deletion of `assets/shaders/spell_aura.gdshader` and its `.uid`,
`docs/VFX_DESIGN.md`, `docs/MODULE_MAP.md` if its effect list changes, relevant
backlog files.

**End state:**

- The expanding noise ring and the seven rising wisp billboards are gone. The
  ground layer is a compact rupture at the blade seats — bright at the fracture
  lines, dark between them — that appears with the charge and clears with the
  decay.
- A small number of rising motes punctuate the flash without becoming a particle
  field; combined supporting instances stay under the §3 cap.
- The catalog's generic entry reads its hold fraction and max-live from
  `SpellCastAuraProfile`; `GENERIC_ACTION_HOLD_FRACTION` no longer holds a loose
  literal. `max_live` stays 0.
- `spell_aura.gdshader` is deleted after a repository-wide search confirms no
  remaining reference, and the deletion is reflected wherever the old shader is
  documented.
- Documentation describes the generic aura's new shape once, without citing any
  transitory plan item label.

**Risk:** the easy-to-author ground glow and mote field can quietly become the
effect again, reproducing the blown-out blob this rework removes. Judge the
layer-isolated sheets before the composite, and reject any composite in which
the blades are not the dominant silhouette.

**Adds to final validation coverage:** layer hierarchy, ground/blade
integration, catalog metadata sourcing, dead-resource removal, combined budget.

**Resolution target:** implemented; pending end-of-plan validation. Debug
capture and cheap integrity checks only. Do not launch a battle.

### AURA-4 — Consolidated final visual, lifecycle, and battle validation

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-1, AURA-2, AURA-3.

**Files:** fixes to task-owned files if validation finds defects,
`implementation_plan.md` resolution notes during validation, owning docs and
backlogs if verified truth changes, followed by the required plan-file cleanup.

This is the only item that performs full gameplay and integration validation.
Consolidate the following rather than replaying them after each implementation
item:

1. Godot 4.4 headless editor import/parse gate over every changed `.gd`,
   `.gdshader`, and `.uid`, then clean loads of `VFXDebugScene` and `Battle25D`.
2. At one fixed seed, capture the matched phase sequence — empty ground,
   rupture, first blades, full flash, decay, clear — judged at native retro
   resolution, not only in enlarged frames.
3. Layer-isolated and composite sheets at front-quarter, side, and rear-quarter
   yaws, retro on and off, for at least five element colours including the
   neutral fallback.
4. Lifecycle: play, pause, resume, 0.5x and 2x speed, forward and backward
   scrub, skip from charge / flash / decay, several simultaneous auras,
   retrigger, repeated seeded playback, and scene/app exit with no locked-object
   error.
5. Live battle: cast several different unprofiled spells across at least four
   elements, at least one multi-target area spell, and at least one cast on
   uneven terrain. Confirm event-time placement, readability through CRT, queue
   pacing, damage-number separation, and unchanged gameplay results.
6. Re-run the Ice Storm, Fire Storm, Magenta Reduction, and Ice Target
   Encasement debug captures to prove no shared-resource regression.
7. Read live node, instance, and draw-call figures from the harness HUD and
   confirm every asserted ceiling. Reconcile both backlogs, inspect the final
   focused diff, run `git diff --check`, and stage only task-owned files.

If validation finds a defect, fix it in this session and rerun the smallest
consolidated subset that covers the fix; do not reopen prior items merely to
repeat the same checks.

**Risk:** a harness-perfect translucent effect can vanish against bright terrain
or blow out through the CRT path, and the generic profile is what every
unprofiled spell plays, so a regression here is a regression everywhere the
catalogue currently points. Only the
live multi-spell battle pass closes that.

**Completion rule:** record the actual visual and manual evidence, mark every
covered implementation item done, reconcile both backlogs, and commit the final
validation result. Then, in the same session, grep the repository for `AURA-1`
through `AURA-4`, rewrite any accidental persistent reference as a durable
description, and clear `implementation_plan.md` completely in a follow-up
lifecycle-cleanup commit.

## 6. Deliberately not doing

- No lightning bolt, no descending strike, and no sky-side layer: the
  reference's bolt is out of scope.
- No radius or footprint response for the generic aura; that long-term backlog
  entry stays open.
- No change to any spell-specific profile (Ice Storm, Fire Storm, Magenta
  Reduction, Ice Target Encasement) and no change to shared `VfxTextures`
  primitives or materials.
- No spell data, element, damage, timing, or targeting change.
- No new shared abstraction extracted from this effect; the `SpellVfxProfile`
  resource extraction stays deliberately declined.
- No screen-space distortion, refraction, bloom pass, or post-processing change
  to sell the flash.
- No resumption of the parked ice encasement validation inside this cycle; it is
  critical-backlog work with its own session.

## 7. Resolution notes

### Ground eruption choreography and disposal fix

Implemented 2026-08-12; pending end-of-plan validation.

- Five named windows now own the timeline: charge (0.00–0.07), eruption
  (0.03–0.35), hold (0.35–0.44), decay (0.44–0.88), and clear (0.88–1.00). The
  eruption deliberately overlaps the charge so the rupture and the first blade
  read as one event rather than a cue followed by a payoff.
- Every blade value is a pure function of normalized time and the fixed seed.
  The per-blade delay lives in the MultiMesh's custom data and the growth,
  overshoot, and fade are evaluated in the vertex stage, so nothing accumulates
  between frames and no RNG is sampled after layout.
- Stagger comes from spatial role, not from a shuffle: most of a blade's delay
  is how far out it is seated, so the eruption travels outward from the seat.
  A jitter term keeps the wave from arriving as a clean expanding ring.
- Blades punch up from zero height, overshoot by 16% near the middle of their
  own growth window, and return to exactly their authored height by the end of
  it — the overshoot term is zero at both ends, so there is no endpoint drift.
  During decay they keep climbing as they fade, which reads as energy escaping
  rather than a light being switched off.
- Duration is now 1.0 s and the profile publishes `ACTION_HOLD_FRACTION` 0.45,
  which the catalog's generic entry reads along with its live cap. The old
  hard-coded 0.6 is gone. **This legitimately changes the queue's reported hold
  for every unprofiled spell**; the new shape reaches its full read much earlier
  than the old expanding ring did, so do not restore 0.6.
- The inherited ground layer is remapped onto the new windows so its ring opens
  while the blades erupt and clears while they fade. Its own rebuild is the
  next item's work.
- Layers are now `ray_burst`, `ground_rupture`, and `motes`, each independently
  toggleable; the HUD confirms all three.
- The `Object is locked and can't be freed` error is fixed. `dispose()` reached
  `free()` whenever the node was already out of the tree, which is exactly the
  teardown state, and the engine had the object locked for the notification
  that triggered the disposal. It now returns early when already queued, uses
  `queue_free()` inside the tree, and defers the free outside it. No run since
  the fix has printed the error; the long-term backlog entry was removed and
  the finding recorded in `docs/LEARNINGS.md`.
- Proof: an eight-frame sheet across the whole timeline plus a tight
  0.05–0.30 sheet at 0.03 spacing show blades growing from zero in a
  seat-outward wave, a full crown, then a fade to nothing. Normalized times
  0.18 and 0.34 were captured in one process and again in the opposite order in
  another; both pairs are byte-identical by SHA-256, proving exact seek
  independent of playback history.
- Measured through the HUD at the new duration: 4 nodes, 17 instances,
  ~3 draw calls, all inside the asserted ceilings. Godot 4.4's import/parse
  gate and `git diff --check` passed. No battle was launched, as required for
  this item.

### Ray-burst blade geometry and translucent material

Implemented 2026-08-12; pending end-of-plan validation.

- Camera roll was confirmed zero before any geometry was authored. Both
  cameras are `PROJECTION_ORTHOGONAL` and both call
  `look_at(focus, Vector3.UP)` every frame, so world up maps to screen up
  exactly and a world-vertical edge is a vertical raster line at any yaw or
  pitch. The blades stand on world up, and the finding now sits beside the
  existing camera-plane guidance in `docs/VFX_DESIGN.md`. No fallback to the
  camera-plane construction was needed.
- `ray_burst` is 17 blades in one MultiMesh. Each blade is an authored
  five-vertex silhouette — broad seat, shoulders at 0.62, single sharp apex —
  whose orientation the shader rebuilds per instance: a Y-axis billboard that
  faces the camera while never tilting off vertical. The instance transform
  carries only scalars and a world-space lean vector; UV2 carries the authored
  local geometry and UV the shading coordinates, normalized across the blade's
  width so the alpha profile follows the taper rather than the bounding box.
- The material is additive with a quantized three-step cross-width alpha ramp
  and a solid spine. Additive was chosen over alpha blending deliberately:
  crossing blades pile into the white-hot seat on their own, and the layer
  becomes order-independent, so the sorting failure the item's risk names
  cannot occur. Per-blade peak alpha stays low; brightness is bought with
  overlap rather than emission energy.
- Four hero blades are spread around the ring by index before jitter, so the
  size hierarchy survives any seed. Azimuths use the golden angle with 22%
  jitter, matching the storm profiles' distribution vocabulary.
- Tuning was driven by frames, not by guesswork. The first build's blades read
  as thin curved whiskers; width, height, and peak alpha went up and the lean
  exponent came down from 2.0 to 1.35, which straightened them into rays that
  splay as a cone. Peak alpha and emission were raised a second time after the
  side view showed them washing out against the bright green island.
- Element sweep passed at one seed for ice, fire, thunder, darkness, and the
  neutral fallback: each tint is legible, none blows out to white, and the
  neutral grey still reads as energy. Front, side, and rear-quarter yaws are
  stable, and a 320x240 retro capture keeps the blades countable and pointed.
- The harness gained `--element=`, `--camera-size=`, and `--camera-focus=`.
  The element sweep and the close framing this item's proof required were not
  reachable from the command line, and `docs/VFX_DESIGN.md` §5 makes CLI parity
  a hard rule rather than a convenience. This is the one file touched outside
  the item's stated list.
- Measured through the harness HUD: 4 nodes, 17 instances, ~3 draw calls,
  against ceilings of 10, 10 supporting instances, and 8 draws. Build
  assertions enforce the blade count and the node ceiling.
- `VfxTextures` and every other shared material are untouched. The old ground
  ring and wisp layers still render; removing them is the supporting-layer
  item's work.
- Godot 4.4's headless editor import and parse gate passed, and
  `git diff --check` passed. The `Object is locked and can't be freed` error
  still prints at scene teardown — it is the pre-existing backlog bug the
  choreography item owns, and it reproduces identically against the prior
  code. No battle was launched, as required for this item.
