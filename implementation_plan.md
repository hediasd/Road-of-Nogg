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
energy erupting out of the ground**, read as liberation from the elemental
plane at the moment of the cast.

Two reference images anchor this. The first (a dungeon battle screenshot) gave
the effect's rough vocabulary but is hard to read against its background. The
second, supplied 2026-08-12, is an isolated render on black and is the sharper
reference: a **blazing white ring standing flat on the ground**, a **crown of
chunky faceted crystal shards** above it, a **horizontal starburst of straight
rays radiating outward along the floor**, and a **couple of small drifting
spark motes**. These are four separate, simple composited elements, not one
continuous gradient surface — see the second resolved gate below for why that
distinction now drives every remaining item.

The finished effect must:

- present as those four legible parts — a hot ring, a faceted crystal crown,
  a flat ground starburst, and a few motes — each doing one job, rather than
  one shape trying to be all of them;
- **erupt from the ground upward**, with the ring, the starburst, and the crown
  reading as one continuous event rather than independently timed layers;
- keep the crown **translucent and faceted**: individual crystal faces read as
  distinct planes catching light differently, and the caster stays visible
  through it. The ring is the deliberate exception — both references agree it
  is the hottest, most blown-out point, and it is small and contained rather
  than the whole silhouette, so its core is allowed to clip toward white;
- carry the **element tint** every caller already supplies
  (`BattleMeshFactory.elementColor`), from ice cyan through fire red, thunder
  yellow, darkness violet, and the neutral grey fallback everywhere except the
  ring's white core;
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

### Primary form pivot #2 — resolved 2026-08-12

The striated cone shell (AURA-2C, committed) was itself judged against the
sharper second reference image and **retired**, one cycle after the discrete
blades it replaced were retired for the same reason: it was one continuous
shape trying to simultaneously be a ring, a wall, and a set of points, and
neither reference is built that way. The user asked directly whether a
different approach was needed and asked for research into how AI-assisted VFX
work is actually done well; both pushed toward the same conclusion.

**What the research surfaced** (see the session's research summary for
sources): published vision-critique loops for code and shader generation
(rendering an iteration, having a vision-capable model diff it explicitly
against the target, then refining) consistently outperform iterating on
production output alone, and unanchored iterative generation measurably drifts
toward generic, safe motifs without that explicit external check — which is
exactly what happened here twice: each pass was judged against the previous
render rather than re-checked against the reference itself. Separately,
professional game-VFX practice composites several simple layers (rotated
copies of one ray emitter, a ring, a particle system, a mesh) rather than
authoring one clever unified shader.

**Two rules now apply for the rest of this cycle:**

- **Decompose into simple composited layers.** The remaining items build a
  ring, a crystal crown, and a ground starburst as three independent,
  individually simple primitives — not one shape asked to do three jobs.
- **Every proof checkpoint is a literal side-by-side comparison against both
  reference images**, not an isolated capture judged from memory. A checkpoint
  that only shows the new render is incomplete.

The blade MultiMesh (AURA-1/2B) and the cone shell (AURA-2C) remain committed,
recoverable history; nothing about their determinism, timeline, or camera-roll
findings is invalidated — only their geometry is retired. AURA-2C's item and
resolution note stay in this file as the delegation contract that produced
what shipped in commit `3db98cf`, marked superseded rather than deleted.

## 3. Established facts and design decisions

### Four composited layers, not one shader

Both the blade crowd and the striated shell tried to fake a ring, a wall, and
a set of points with one continuous form, and both were retired for it. The
current design has no single hero shape: a ring mesh, a faceted crystal-crown
mesh set, a ground starburst, and a small mote system are each built and
proven independently before being judged together. Each is simple enough to
get right on its own, which was never true of the unified attempts.

### Faceted geometry needs real facets, not a gradient

A smooth cone with a colour ramp cannot produce what a low-poly crystal
produces: distinct flat faces that catch the scene's single directional light
at different angles. `IceChunkMeshFactory._spikeMesh()`
(`src/presentation/effects/IceChunkMeshFactory.gd:80`) is proven, shipped
precedent for this technique in this repository — a broad-seated pointed
form built from named triangles with duplicated vertices per face so each face
gets its own flat normal. Per `docs/VFX_DESIGN.md` §4's "fork, don't abstract"
rule this effect owns a sibling mesh factory rather than importing that file,
since `IceChunkMeshFactory` is explicitly scoped to the target-encasement
shell.

### World-vertical geometry is the sharp case, not the soft one

`docs/VFX_DESIGN.md` §4's camera-plane rule exists because a quad rotated to
an arbitrary world angle sits on no pixel grid. Geometry standing on the
world's up axis is the exception, confirmed rather than assumed: both cameras
are orthographic and re-derive their transform with
`look_at(focus, Vector3.UP)` every frame, so world up maps to screen up and a
vertical edge is a vertical raster line at any yaw or pitch. The ring and the
crystal crown both stand on world up and inherit this; the ground starburst
lies flat in the world's horizontal plane and needs no camera-facing
construction at all, since it is ordinary geometry on the terrain.

### Additive, with the brightness taken out of alpha

The inherited aura was `blend_add` at high emission over a full disc, which is
why it blew out. Additive stays the right mode for every layer here — it is
order-independent, so overlapping crystal faces or crossing starburst rays
cannot produce a sorting error, and genuine overlap is what builds the ring's
core toward white on its own. The blowout stays controlled by keeping
per-surface alpha low rather than by lowering emission, which would flatten
the palette instead.

### The ring, crown, and starburst share one origin and one clock

All three erupt from the same seat on the same normalized timeline established
in AURA-2 (charge / eruption / hold / decay / clear), so they read as one
event breaking through the ground rather than three independently timed
layers that happen to overlap in space.

### Ownership and reuse

The effect owns its profile constants, its shaders, and its mesh construction.
`VfxTextures`, `IceChunkMeshFactory`, and every other shared or effect-owned
resource belonging to another effect stay untouched, so Ice Storm, Fire Storm,
Magenta Reduction, and Ice Target Encasement cannot regress through a shared
primitive. `assets/shaders/spell_aura.gdshader` had exactly one referencing
file and has been deleted with its `.uid`; a repository-wide search must
confirm this stays true as the ground layer is rebuilt.

### Budgets, asserted at build time and owned by the profile

Provisional, pending the real figures AURA-2D and AURA-3 measure:

- one ring mesh, one draw call;
- one crystal-crown mesh set (five to six pieces, a single MultiMesh where
  possible), one draw call;
- one ground-starburst mesh or MultiMesh, one draw call;
- a small mote particle system, one draw call;
- ≤ 12 effect-owned nodes;
- ≤ 10 estimated peak draw calls;
- unlimited live count preserved (`max_live` stays 0 — the generic profile is
  the fallback for every unprofiled spell and must never evict itself).

## 4. Proof checkpoints

VFX work is shown while it is still cheap to change. These are required item
outputs, not deferred final-validation evidence.

**Every row below is a literal side-by-side placement against both reference
images**, not an isolated capture judged from memory — the second resolved
gate names this as the specific process failure that cost two prior rebuilds.

| Checkpoint | Required proof | Owner |
| --- | --- | --- |
| Ring and crown silhouette | Ring-only and crown-only captures at front-quarter, side, and rear-quarter yaws, beside both references. The ring reads as a hot O-shape with a dark centre at every angle; the crown's individual facets are visibly distinct planes. | AURA-2D |
| Starburst and motes | Starburst-only and motes-only captures beside both references. Rays are straight, sharp, and radiate flat along the ground; motes read as a handful of sparks, not a field. | AURA-3 |
| Eruption timeline | One tight sheet from empty ground through the ring lighting, the starburst racing outward, the crown punching up, hold, decay, and clear. | AURA-3 |
| Composite hierarchy | The full composite beside both references at the same angle and scale. All four parts are individually identifiable; none has silently become the whole effect. | AURA-3 |
| Final look | Live battle casts across several spells and elements, retro on and off, plus re-captures of the four specific profiles. | AURA-4 |

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

**Superseded 2026-08-12 by AURA-2D.** Kept here as the delegation contract its
resolution note fulfilled, and because the timeline/determinism/ownership work
it produced remains load-bearing even though its geometry does not. Do not
execute this item again; see the second resolved gate and AURA-2D.

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

### AURA-2D — Retire the shell; build the ring and the faceted crystal crown

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-2C and the second resolved pivot.

**Files:** new `src/presentation/effects/SpellCastAuraMeshFactory.gd` (a sibling
to `IceChunkMeshFactory.gd`, forked rather than shared, per §3), one or two new
effect-owned shaders under `assets/shaders/effects/` for the ring and the
crystal crown, `src/presentation/effects/SpellCastAuraProfile.gd`,
`src/presentation/effects/SpellCastAura.gd`, deletion of
`assets/shaders/effects/spell_cast_ray_shell.gdshader` and its `.uid`,
`docs/VFX_DESIGN.md`, and the relevant backlog files.

**End state:**

- The cone shell and its shader are gone; recoverable from Git at commit
  `3db98cf` if a future silhouette wants it back.
- A ring mesh stands at the seat — a flattened torus or an equivalent short
  ring cross-section — additive, its core pushed to near-white regardless of
  element tint. This is the one deliberate exception to the "restrained core"
  rule elsewhere in this effect, per the Goal section's reasoning: both
  references agree the ring itself is the hottest point, and it is small and
  contained rather than the whole silhouette.
- A crown of five to six low-poly faceted meshes stands above the ring, built
  the same way as `IceChunkMeshFactory._spikeMesh()`: named triangles with
  duplicated vertices per face, so each face gets its own flat normal and reads
  as a distinct plane under the scene's fixed directional light rather than a
  smooth gradient. Translucent and element-tinted.
- Crown placement is seeded and deterministic — varied height, width, rotation,
  and outward lean, distributed by the golden-angle vocabulary already used
  elsewhere in this file so it reads as deliberately asymmetric rather than
  evenly spaced.
- Ring brightness ramps in during the charge window; crown pieces punch up
  during the eruption window, both driven by the timeline AURA-2 established.
- Node, instance, and draw-call budgets are measured through the harness HUD
  and §3's provisional ceilings are corrected to the real figures.

**Risk:** a ring viewed near edge-on can thin to an unreadable line, and a
faceted low-poly crystal lit only by one directional light can go uniformly
dark on faces angled away from it. Confirm the ring reads at front, side, and
rear-quarter yaws, and give the crown material a modest unshaded/emissive floor
so no facet goes fully black regardless of its normal.

**Proof checkpoint:** ring-only and crown-only captures at three yaws, placed
directly beside both reference images — not judged from an isolated capture.

**Adds to final validation coverage:** ring/crown silhouette against both
references, facet legibility under the scene's lighting, seeded determinism,
and the corrected budget.

**Resolution target:** implemented; pending end-of-plan validation. Debug
capture and cheap integrity checks only. Do not launch a battle.

### AURA-3 — Rework the ground layer into a starburst, and restyle the motes

**Model:** Sonnet 5 / GPT Terra

**Depends on:** AURA-2D.

**Files:** `src/presentation/effects/SpellCastAura.gd`,
`src/presentation/effects/SpellCastAuraProfile.gd`, its shader (renamed from
`spell_cast_ground_fissures.gdshader` if the rebuild changes its shape enough
to earn a new name), `src/presentation/effects/SpellVfxCatalog.gd` (generic
entry metadata only, if not already fully sourced from the profile),
confirmation that `assets/shaders/spell_aura.gdshader` and its `.uid` stay
deleted, `docs/VFX_DESIGN.md`, `docs/MODULE_MAP.md` if its effect list changes,
relevant backlog files.

**End state:**

- The ground layer is a horizontal starburst: six to eight straight, sharp,
  tapered rays radiating outward along the floor from the seat, matching the
  second reference's asterisk pattern. An earlier attempt this session built a
  jagged, branching-crack shader
  (`assets/shaders/effects/spell_cast_ground_fissures.gdshader`, uncommitted)
  before the second reference image made clear the floor rays are straight,
  not lightning-like; its per-ray seed, growth, and timeline plumbing is still
  correct and may be simplified into the straight-ray shape rather than
  rewritten from nothing.
- Rays share the ring and crown's eruption timeline, so the floor visibly opens
  at the same moment the ring lights and the crown punches up.
- The seven rising wisp billboards are restyled into five or six sparkle-style
  motes drifting from around the ring's radius rather than the effect's old,
  much smaller one.
- The catalog's generic entry sources `action_hold_fraction` and `max_live`
  entirely from the profile (already true as of AURA-2; confirm unchanged).
- `spell_aura.gdshader` stays deleted; a repository-wide search confirms no
  remaining reference.

**Risk:** straight rays that are too uniform in length and spacing read as a
printed asterisk rather than an organic burst, and the easy fix — adding jag
back in — is the branching-crack shape this session already rejected once.
Keep enough per-ray seeded variance in length and delay to avoid a printed
look while staying visibly straight and star-shaped.

**Proof checkpoint:** starburst-only and motes-only captures, plus the full
composite, all placed beside both reference images.

**Adds to final validation coverage:** ground/crown integration, layer
hierarchy, catalog metadata sourcing, dead-resource removal, combined budget.

**Resolution target:** implemented; pending end-of-plan validation. Debug
capture and cheap integrity checks only. Do not launch a battle.

### AURA-4 — Consolidated final visual, lifecycle, and battle validation

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-1, AURA-2, AURA-2B, AURA-2C, AURA-2D, AURA-3.

**Files:** fixes to task-owned files if validation finds defects,
`implementation_plan.md` resolution notes during validation, owning docs and
backlogs if verified truth changes, followed by the required plan-file cleanup.

This is the only item that performs full gameplay and integration validation.
Consolidate the following rather than replaying them after each implementation
item:

1. Godot 4.4 headless editor import/parse gate over every changed `.gd`,
   `.gdshader`, and `.uid`, then clean loads of `VFXDebugScene` and `Battle25D`.
   Confirm `project.godot` is untouched by the gate itself — see the
   `docs/LEARNINGS.md` entry recorded this session.
2. At one fixed seed, capture the matched phase sequence — empty ground,
   charge, starburst and crown eruption, hold, decay, clear — judged at native
   retro resolution, not only in enlarged frames, and placed beside both
   reference images.
3. Layer-isolated and composite sheets at front-quarter, side, and rear-quarter
   yaws, retro on and off, for at least five element colours including the
   neutral fallback.
4. Lifecycle: play, pause, resume, 0.5x and 2x speed, forward and backward
   scrub, skip from charge / hold / decay, several simultaneous auras,
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
catalogue currently points. Only the live multi-spell battle pass closes that.

**Completion rule:** record the actual visual and manual evidence, mark every
covered implementation item done, reconcile both backlogs, and commit the final
validation result. Then, in the same session, grep the repository for `AURA-1`
through `AURA-4`, including `AURA-2B`, `AURA-2C`, and `AURA-2D`, rewrite any
accidental persistent reference as a durable description, and clear
`implementation_plan.md` completely in a follow-up lifecycle-cleanup commit.

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
- No screen-space distortion, refraction, global bloom pass, or other
  post-processing change to sell the flash — brightness comes from each
  layer's own additive overlap, not from a scene-wide effect.
- No further parameter-tuning pass on a rejected silhouette without first
  re-checking both reference images explicitly, per the second resolved gate.
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
