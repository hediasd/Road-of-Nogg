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

The user's supplied reference frame is the visual language: a flared cup of
light standing on the floor, whose individual rays are hard-edged vertical
striations running up its wall, whose top edge breaks into short irregular
points, which is hot and near-white where it meets the ground and
colour-deepened toward its rim, and which sits over glowing fissures spreading
several tiles across the floor. The lightning bolt descending from the top of
that frame is explicitly **not** part of this effect.

The finished effect must:

- read as **rays** — countable, hard-edged striations with visible dark
  between them, pointed where they end — carried on a filled wall rather than
  floating as separate objects or dissolving into fog;
- **erupt from the ground upward**, with the floor layer and the wall of light
  belonging to one event rather than two stacked layers;
- stay **translucent**: the far wall shows through the near one and builds
  toward white-hot where they overlap, while the caster stays visible inside;
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

### Scale, density, and ground treatment — resolved 2026-08-12

After comparing the first complete blade implementation against the supplied
reference frame, the user set the remaining visual direction:

- the crown is **big and dense** — a flared cup of light roughly two tiles
  across and several times the caster's height, not a bouquet of separate
  spikes standing under head height;
- individual rays stay legible *inside* that filled silhouette rather than
  being replaced by it;
- the core stays **bright but short of full white clipping**. The reference's
  blown-out core was explicitly not adopted, since this branch has been
  reducing exactly that elsewhere;
- the ground layer becomes **fissures radiating outward from the seat**, not a
  compact rupture and not the inherited expanding ring.

These are confirmed visual decisions, not open questions. The reference's
lightning bolt remains out of scope.

## 3. Established facts and design decisions

### The rays are striations on a shell, not separate objects

Discrete blades were built first and **retired**. Two rounds of scaling them up
established that the gap to the reference was structural rather than a matter
of tuning: the reference's rays are stripes *on* a filled wall of light, and
its points are that wall's ragged top edge, so a crowd of free-standing spikes
converges on a bristle no matter how large or numerous it gets.

The primary form is therefore one double-sided cone shell, drawn additively so
the far wall shows through the near one and the interior builds toward white.
Its stripes, its ragged rim, its vertical colour ramp, and its per-stripe
eruption timing are all shader work over a single mesh — which also means the
whole crown costs one draw call and one instance instead of twenty-eight.

`docs/VFX_DESIGN.md` §4's rule still applies to why none of this is a sprite:
a radial mask stretched onto a long quad puts its opaque centre in the middle
of the streak. The stripes are procedural, hard-edged, and owned by the effect's
own shader.

### World-vertical geometry is the sharp case, not the soft one

§4's camera-plane rule exists because a quad rotated to an arbitrary world angle
sits on no pixel grid. Geometry standing on the world's up axis is the
exception, and this was confirmed rather than assumed: both cameras are
orthographic and re-derive their transform with `look_at(focus, Vector3.UP)`
every frame, so world up maps to screen up and a vertical edge is a vertical
raster line at any yaw or pitch.

The shell inherits that: its wall is vertical enough that the striations stay
crisp, and it needs no camera-plane construction, so it keeps the spatial
grounding that construction gives up. The finding is recorded durably in
`docs/VFX_DESIGN.md`.

### Additive, with the brightness taken out of alpha

The inherited aura was `blend_add` at high emission over a full disc, which is
why it blew out. Additive is nonetheless the right mode here, for two reasons
the alternative cannot supply: it is order-independent, so a double-sided shell
cannot produce a sorting error, and overlapping surfaces accumulate on their
own, which is exactly how the near and far walls fill the cup's interior.

The blowout is controlled by keeping per-surface alpha low rather than by
lowering emission, which would flatten the palette instead. `depth_draw_never`
and an explicit render priority keep the shell from cutting the layer it grows
out of.

### The floor layer and the shell share one origin and one clock

The fissures open from the shell's own seat on the same normalized timeline, so
the floor reads as the fracture the light is escaping through rather than as a
decal that happens to sit underneath it. The old expanding noise ring is
removed rather than kept below.

### Ownership and reuse

The effect owns its profile constants, its shader, and its mesh
construction. `VfxTextures` and every other shared material stay untouched, so
Ice Storm, Fire Storm, Magenta Reduction, and Ice Target Encasement cannot
regress through a shared primitive. `assets/shaders/spell_aura.gdshader` has
exactly one referencing file (`SpellCastAura.gd`) and is deleted with its `.uid`
once the rewrite lands.

### Budgets, asserted at build time and owned by the profile

- one shell mesh, one instance, one draw call, carrying 20–28 striations set
  as a shader parameter rather than as geometry;
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
| Composite hierarchy | Ground-only and mote-only sheets beside the full composite. The shell remains the dominant read. | Supporting-layer item |
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

### AURA-2B — Scale the crown into a flared cup

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-2 and the resolved scale direction.

**Files:** `src/presentation/effects/SpellCastAuraProfile.gd`,
`src/presentation/effects/SpellCastAura.gd`, `docs/VFX_DESIGN.md` only if a
durable rule changes, and the relevant backlog files.

**End state:**

- Blade population is authored as two named rings — a short, wide, lightly
  leaned inner wall and a tall, narrow, strongly leaned outer rim — whose
  proportions live in the profile as data, with one placement routine serving
  both.
- The crown reaches roughly two tiles across and several times the standard
  body's height, and the outer rim's tips splay far wider than their seats, so
  the silhouette is a cup rather than a bundle of parallel spears.
- Per-blade alpha comes down as population rises: the same value that read as
  translucent in a sparse bouquet must not stack into an opaque white mass.
  Single blades stay see-through and the core stays short of clipping.
- The eruption still travels seat-outward across both rings, and blade
  placement stays a pure function of the seed.
- Build assertions cover the new bounds, and the ring counts are asserted
  against the authored total.

**Risk:** raising both size and population multiplies additive overlap, and the
easy response — lowering emission — would flatten the palette instead of the
blowout. Take it out of per-blade alpha, and judge the middle of the cup rather
than its rim, since that is where the stacking happens.

**Proof checkpoint:** front and side captures of the completed crown at the new
scale, plus one at 320x240, showing a flared cup with countable rays and no
white blob at the centre.

**Adds to final validation coverage:** crown scale against a real monster, cup
silhouette from several yaws, overlap brightness at the new population, and
instance budget.

**Resolution target:** implemented; pending end-of-plan validation. Debug
capture and cheap integrity checks only. Do not launch a battle.

### AURA-2C — Rebuild the primary form as a striated shell

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-2B and the user's decision to retire the blades.

**Files:** new `assets/shaders/effects/spell_cast_ray_shell.gdshader`,
`src/presentation/effects/SpellCastAuraProfile.gd`,
`src/presentation/effects/SpellCastAura.gd`, deletion of
`assets/shaders/effects/spell_cast_ray_burst.gdshader` and its `.uid`,
`docs/VFX_DESIGN.md`, and the relevant backlog files.

**End state:**

- The blade MultiMesh and its shader are gone. The effect's primary layer is a
  single double-sided cone shell, additive, whose base radius, rim radius, and
  height are shader uniforms over a unit cylinder mesh, so the silhouette is
  retunable without rebuilding geometry.
- The rays are procedural striations around the shell: each owns its width,
  brightness, top height, and eruption delay, all derived by hash from its
  index and the effect's seed. Band edges stay hard; a dimmer wash between them
  keeps the wall a wall rather than a picket fence.
- The top edge is ragged, because each stripe stops at its own height. That
  ragged edge is where the effect's pointed ends now come from.
- Colour is a three-stop vertical ramp seeded from the element tint: near-white
  at the seat, the hue lightened through the body, deepened at the rim.
- The shell's edge-on flanks are brighter than the wall facing the camera,
  which is most of what makes it read as a volume rather than a decal.
- Per-stripe timing preserves the staggered eruption, and every frame remains a
  pure function of normalized time and the seed. No placement pass and no
  random call survive at playback time.
- Node and draw ceilings come down to match what the shell actually costs.

**Risk:** a single additive shell can flatten into a cone of fog if the wash
between stripes is raised to fill the wall. Fill it with overlap between the
near and far walls instead, and check that the caster stays visible inside the
cup.

**Proof checkpoint:** front captures of the completed shell at native and
320x240, plus one non-cyan element, showing a filled cup with countable
striations, a ragged top edge, and a hot seat.

**Adds to final validation coverage:** shell silhouette, striation legibility,
ramp behaviour across elements, interior translucency, and the reduced budget.

**Resolution target:** implemented; pending end-of-plan validation. Debug
capture and cheap integrity checks only. Do not launch a battle.

### AURA-3 — Rebuild the ground rupture and the subordinate motes

**Model:** Sonnet 5 / GPT Terra

**Depends on:** AURA-2C.

**Files:** `src/presentation/effects/SpellCastAura.gd`,
`src/presentation/effects/SpellCastAuraProfile.gd`, its shader,
`src/presentation/effects/SpellVfxCatalog.gd` (generic entry metadata only),
deletion of `assets/shaders/spell_aura.gdshader` and its `.uid`,
`docs/VFX_DESIGN.md`, `docs/MODULE_MAP.md` if its effect list changes, relevant
backlog files.

**End state:**

- The expanding noise ring and the seven rising wisp billboards are gone. The
  ground layer is a set of **fissures radiating outward from the seat**,
  reaching several tiles, bright along the fracture lines and dark between
  them. They open with the charge, race outward as the blades erupt, and cool
  as the crown fades. A compact rupture was explicitly rejected in favour of
  this: the cracks are much of why the reference reads as something escaping
  from below.
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

**Depends on:** AURA-1, AURA-2, AURA-2B, AURA-2C, AURA-3.

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
through `AURA-4`, including `AURA-2B` and `AURA-2C`, rewrite any accidental persistent reference as a durable
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

### Striated shell replaces the blades

Implemented 2026-08-12; pending end-of-plan validation.

- The user compared the scaled crown against the reference again and asked
  whether blades were needed at all. They were not. The reference's rays are
  striations on a filled wall and its points are that wall's ragged top edge,
  so the blade approach was structurally wrong rather than under-tuned. The
  MultiMesh, its layout pass, and `spell_cast_ray_burst.gdshader` were removed;
  they remain recoverable from Git if a future silhouette wants hero spikes.
- The primary layer is now one double-sided additive cone. The mesh is a unit
  cylinder; base radius, rim radius, and height are uniforms, so the first two
  silhouette revisions cost a constant change rather than a mesh rebuild.
- Stripe width, brightness, top height, and eruption delay are hashed from the
  stripe index and a `shell_seed` uniform. A new seed reshuffles the whole
  crown without a placement pass, and no random call happens at playback time.
- The first shell read as a fountain: a thin-walled cone converging to a point.
  Raising the base radius from 0.50 to 0.78 while lowering the rim from 1.45 to
  1.28 turned it into a bucket, and raising the between-stripe wash from 0.09
  to 0.24 filled the wall without erasing the striations.
- Measured through the HUD: 4 nodes, **1 instance**, ~3 draw calls, against
  new ceilings of 8 nodes and 6 draws. The 28-instance blade population is
  gone; the striations cost nothing but shader arithmetic.
- Captures at native, at 320x240, and on the fire tint all hold the cup
  silhouette, the countable striations, the ragged rim, and the hot seat. The
  caster stays visible through the wall, which the reference's blown-out
  interior does not allow and which is better for reading the board.
- Godot 4.4's import/parse gate and `git diff --check` passed. No battle was
  launched, as required for this item.

### Flared-cup scale pass

Implemented 2026-08-12; pending end-of-plan validation.

- The user compared the completed blade implementation against the reference
  and judged it far too small and too sparse: the right primitive at the wrong
  scale. The population is now two authored rings — a twelve-blade inner wall
  and a sixteen-blade rim with five heroes — living in the profile as data,
  placed by one routine that runs over both.
- The crown now reaches about 5.6 u at its tallest against a 1.6 u body proxy,
  and roughly two tiles across at the rim. The outer ring's lean rose from a
  maximum of 0.34 u to 1.85 u, which is what turns a bundle of parallel spears
  into a cup: the tips splay far wider than the seats.
- Per-blade peak alpha came down from 0.68 to 0.46 and the inner ring carries
  an additional 0.72 multiplier. Twenty-eight overlapping blades at the old
  value stacked into an opaque white mass at the centre; the reduction was
  taken from alpha rather than emission so the palette stayed intact. The core
  is bright but does not clip, per the user's confirmed direction.
- The golden angle advances across the ring boundary rather than restarting, so
  the wall and the rim interleave instead of forming spokes. Eruption delay is
  normalized against the crown's full radial span, which keeps the whole inner
  wall ahead of the whole rim.
- Proof: front and side captures of the completed crown, plus a 320x240 retro
  frame. The flare, the countable rays inside it, and the bright seat all
  survive the harshest resolution, and the middle of the cup stays translucent
  rather than filling in.
- The blade-count bounds moved to 20–32 in both the profile and the plan's
  budget section; ring counts are asserted against the authored total. Nodes
  and draw calls are unchanged, since every blade shares one MultiMesh.
- Godot 4.4's import/parse gate and `git diff --check` passed. No battle was
  launched, as required for this item.

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
