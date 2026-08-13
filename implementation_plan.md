# Spell Cast Aura Reference-Locked Rebuild

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

Rebuild the generic spell-cast aura from the **eleven consecutive 2026-08-12
source frames**, which supersede every earlier still-image interpretation. The
effect is an evolving inner aperture/boundary surrounded by a broad asymmetric
blue-cyan plume crown. It is not three concentric ground rings, a tapered core
column, a set of individual lance rays, or a particle mist.

The current committed aura remains useful only as playback/catalog/debug
infrastructure. Its four visual carriers are rejected reference experiments and
must be removed or replaced by the dependency-ordered items below.

The finished effect must:

- present as two coupled visual systems — one evolving footprint aperture/rim
  and one continuous broad plume crown — each doing one evidenced job;
- reproduce the source's primary crest, first trough, secondary swell, and
  terminal recession rather than a single monotonic grow/hold/fade;
- keep the caster crisp above the aura from a moving camera, with only subtle
  light touching the feet and no translucent column washing across the body;
- keep most visible energy wide and below the shoulders while allowing only
  faint plume tips above the head;
- carry the **element tint** every caller already supplies
  (`BattleMeshFactory.elementColor`), from ice cyan through fire red, thunder
  yellow, darkness violet, and the neutral grey fallback, without inventing a
  white-hot core absent from the source;
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

### Reference decomposition pivot #3 — resolved 2026-08-12

After the user asked for a technical decomposition of the isolated aura, they
explicitly directed Road of Nogg to follow that decomposition. The clean torus,
faceted crown, and floor fissure/starburst direction is therefore superseded
before commit. The partial uncommitted experiment is task-owned input to the
replacement, not a result to preserve as the current look.

The accepted vocabulary is now: a dark irregular ground vortex with broken
element-tinted rims; a soft upward-tapered core; a broad fan of feathered ray
shafts with independently seeded angle, length, width, and pulse; and rising
mist with only a few brighter motes. No scene-wide bloom or shared texture is
retuned. Softness comes from owned alpha masks and the existing neutral puff
used without mutation.

### Eleven-frame authority pivot #4 — resolved 2026-08-12

The user rejected the resulting ground-ring capture and supplied eleven
consecutive source frames. Those frames are now the sole visual authority and
supersede the vocabulary above. Pixel-level inspection masked the static speech
UI and character, compared consecutive differences, measured colour/spatial
envelopes, and tested whether opacity scaling alone explains the animation.

Verified evidence:

- the 340x340 source frames contain one evolving inner aperture/boundary and a
  continuous broad plume crown, not three separated ground rings;
- the strongest lower boundary lies around a 37-46 pixel radius and its early
  close striations simplify as the opening grows;
- the energy-weighted envelope is typically about 170 pixels wide and 110
  pixels tall, concentrated from the shoulders downward, while only faint
  tips extend high;
- outer-field energy relative to the first supplied frame is approximately
  `1.00, 1.13, 1.11, 0.96, 0.79, 0.64, 0.61, 0.76, 0.82, 0.85, 0.70`, proving
  a primary crest, trough, secondary swell, and recession rather than one
  grow/hold/fade scalar;
- best opacity-only fits leave 20-32% normalized residual between consecutive
  frames, so plume structure itself changes;
- no frame contains discrete puffs or motes, a narrow central flame/column, or
  individually legible lance rods;
- the source background is black and has no alpha, so it cannot prove whether
  the inner black region is painted darkness or transparent negative space.

Consequences:

- the current ground annuli, six core cards, eighteen crossed ribbons, and
  twelve puffs are all scheduled for removal;
- playback, deterministic seek, catalog integration, and the debug capture
  harness remain valid infrastructure;
- the centre treatment requires a blocking transparent-versus-darkened A/B on
  light and dark terrain before integration is accepted;
- large layers remain world-space because the battle camera moves. A continuous
  flared plume shell with its near hemisphere culled replaces both hero
  billboards and independent flat ray shards.

## 3. Established facts and design decisions

### Two evidenced systems, not four invented motifs

The accepted decomposition is one footprint aperture/rim plus one broad plume
crown. The current ground rings, soft-card core, crossed ray ribbons, and puffs
are not retained as hidden support layers; their silhouettes are absent from
the source and they must be removed.

### The footprint has one evolving boundary

The ground carrier remains world-horizontal so camera pitch supplies its
ellipse. It draws one aperture boundary with tightly clustered internal
striations early in the animation. Those strokes simplify as the aperture
grows. Widely separated rings, pointed fragments, and repeated wavefronts are
forbidden. The required transparent/darkened terrain A/B was resolved in favor
of the approved low-alpha navy centre, with transparent retained as a debug
comparison mode.

### The crown is a continuous world-space plume curtain

The source's wide light tongues form one related flow field, not independent
rods. One or two flared ring shells carry original seamless angular-by-height
plume artwork. Front-face culling removes the near hemisphere, leaving the far
plumes behind the character from any yaw without billboarding or
camera-relative position offsets. A project-owned 11-state atlas changes the
plume grouping over time; it is not a copy of supplied pixels.

### Animation follows the measured two-swell sequence

Normalized seek remains the clock, but separate source-keyed curves drive plume
energy, plume state, aperture radius, rim thickness, striation visibility, and
global recession. `TIME`, GPU particle scheduling, and one monotonic
eruption/hold/decay scalar cannot own the visual result. Seed may rotate or
gently perturb the plume phase, but may not replace the reference silhouette.

### Palette and compositing preserve a clean character

The source uses deep blue-cyan with no persistent white core. Element hue still
comes from the catalog, but saturation/brightness hierarchy follows the source.
The plume is soft unshaded alpha/additive light; alpha mixing supplies the
approved low-alpha navy centre darkening. The character remains opaque and
crisp above the far-side plume shell.

### Ownership and reuse

The effect owns its profile constants, shaders, shell geometry, and new plume
atlas. `VfxTextures`, `IceChunkMeshFactory`, and every resource belonging to
another effect stay untouched. The generic aura stops consuming
`neutralSoftPuff()` and `lanceStreak()` without changing either shared factory.
Caller searches precede deletion of every rejected effect-owned shader.

### Budgets, asserted at build time and owned by the profile

Target, pending implementation proof:

- one footprint aperture carrier, one draw call;
- one inner plume shell, one draw call;
- one outer plume shell, one draw call;
- zero particles and zero hero-scale billboards;
- ≤ 8 effect-owned nodes;
- ≤ 3 effect draw calls;
- unlimited live count preserved (`max_live` stays 0 — the generic profile is
  the fallback for every unprofiled spell and must never evict itself).

## 4. Proof checkpoints

VFX work is shown while it is still cheap to change. These are required item
outputs, not deferred final-validation evidence.

**Every visual row below is a literal side-by-side placement against the full
eleven-frame source sequence**, not an isolated capture or comparison against
an earlier Road of Nogg attempt.

| Checkpoint | Required proof | Owner |
| --- | --- | --- |
| Reference forensics | Contact sheet, consecutive differences, spatial/colour envelope, temporal-energy measurements, and explicit current-layer keep/remove audit. | AURA-2H |
| Aperture ambiguity | Transparent-centre and darkened-centre footprint captures on light and dark terrain, with one user-approved result before integration. | AURA-2I |
| Plume carrier | Inner-shell-only, outer-shell-only, and combined captures at 0, 90, and 180 degree yaw; the character stays clean and no card/rod silhouette appears. | AURA-2J |
| Matched sequence | Eleven Road of Nogg phases beside the eleven supplied frames at comparable character scale, including the two crests, trough, expanding aperture, and terminal recession. | AURA-2K |
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

**Superseded 2026-08-12 before commit by AURA-2E.** The reference-decomposition
pivot rejected the clean torus and solid crown. The uncommitted experiment is
reworked in place; it is not an implementation boundary and must not be
committed separately.

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

**Resolution:** superseded before commit; no implementation boundary exists.

### AURA-2E — Build the spiritual vortex, tapered core, ray fan, and rising mist

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-2C and the resolved reference-decomposition pivot. It
absorbs the visual work formerly assigned to AURA-2D and AURA-3.

**Files:** `src/presentation/effects/SpellCastAura.gd`,
`src/presentation/effects/SpellCastAuraProfile.gd`, effect-owned ground-vortex,
core-glow, and ray-fan shaders under `assets/shaders/effects/`, deletion of the
retired ray-shell and inherited aura shaders with their `.uid` files,
`docs/VFX_DESIGN.md`, this plan, and relevant backlog reconciliation.

**End state:**

- An irregular dark navy/black vortex lies at the caster's feet. Broken
  element-coloured ring and spiral accents give it motion without turning it
  into a clean donut.
- A soft camera-facing teardrop core rises from the vortex, wide and bright low
  down and narrow/faint above the caster.
- A separate camera-facing fan draws many feathered shafts with seeded angle,
  length, width, brightness, and deterministic pulse. Broad cones and thin
  streaks coexist; the fan never rotates as one rigid sunburst.
- Rising puff particles drift upward from the vortex with low alpha and only a
  few brighter motes. The shared neutral puff is consumed without mutation.
- Every authored shader layer is a pure function of normalized progress and
  seed. The particle layer reports its known tolerance-based seek limitation
  honestly.
- Four draw calls and no more than eight owned nodes are asserted at build time.

**Risk:** the dark pass can read as a terrain stain, while additive core/rays
can clip into one cyan rectangle through the retro path. Feather every boundary,
keep the vortex's angular breakup visible, and verify the caster remains readable
in both retro and native captures.

**Proof checkpoint:** one isolated-layer sheet and one composite phase sheet at
the default fixed seed, visually compared against the supplied isolated aura.

**Adds to final validation coverage:** dark/light compositing, camera-facing
anchoring, seeded ray variation, particle seek disclosure, layer isolation,
timeline hierarchy, and corrected budgets.

**Resolution — implemented 2026-08-12; pending end-of-plan validation.** The
retired shell and inherited aura shaders are deleted. The generic effect now
constructs exactly four owned layers: one alpha-mixed irregular ground vortex,
one additive camera-facing tapered core, one additive seeded ray fan, and one
additive rising-puff particle system. Core and rays are shifted behind the
caster in view space; the particle seek limitation is reported as non-exact.

The Godot 4.4 import gate and a bounded `VFXDebugScene` load completed without
script or shader errors. Fixed-seed layer isolates exposed and corrected a
collapsed/over-bright core, an overly regular ray fan, and a pale clean-ring
ground read. The accepted native and retro phase sheets cover 0.10 / 0.28 /
0.50 / 0.78, and a literal side-by-side against the supplied isolated frame
confirmed the final hierarchy. The build owns five nodes total (playback plus
four children), three non-particle geometry instances, twelve particles, and
four draw calls, within the asserted ceilings. No battle was launched, per the
implementation-item boundary.

`BACKLOG_LONGTERM.md`'s generic-footprint item remains genuinely open and
unchanged; the parked Ice Statue validation in `BACKLOG_CRITICAL.md` is also
unaffected. No new unresolved work was found.

### AURA-2F — Remove hero billboards; rebuild the vertical aura in world space

**Model:** Opus 5 / GPT Sol (GPT-family VFX authorship required by project
policy).

**Depends on:** AURA-2E and the user's 2026-08-12 review that the aura rises too
high behind the model and must remain spatially credible while the camera moves.
The unrelated working-tree edits in `AGENTS.md` and `docs/POLICIES.md` are
user-owned and must remain unstaged and untouched.

**Files:** `src/presentation/effects/SpellCastAura.gd`,
`src/presentation/effects/SpellCastAuraProfile.gd`, the effect-owned core and
ray shaders, `docs/VFX_DESIGN.md`, `docs/LEARNINGS.md` only if the multi-yaw
captures verify a reusable rule, this plan, and relevant backlog reconciliation.

**End state:**

- Remove every `INV_VIEW_MATRIX`/`MODELVIEW_MATRIX` billboard override and the
  camera-relative offset from the large core and ray layers.
- Replace the single core quad with six short radial world-space soft cards
  around world up. Replace the single screen fan with seeded radial world-space
  crossed-ribbon instances that lean outward from the vortex. Camera yaw
  changes which faces are seen; it does not rotate the effect itself.
- Calibrate maximum vertical reach against the supplied frame: the brightest
  mass stays below the head and only the faintest rays reach slightly above the
  standard body proxy, rather than extending another body height behind it.
- Preserve the alpha-mixed ground vortex and small particle puffs. No shared
  texture is modified and no proprietary reference asset is imported.
- Keep four draw calls; update the honest geometry-instance ceiling from three
  hero nodes to one vortex plus every core card and ribbon instance. This is an
  intentional reported-number change, not a regression to restore.

**Risk:** crossed cards can brighten at intersections or disappear near an
edge-on yaw, while radial ribbons can become a spiky cage instead of soft
shafts. Use low per-card alpha, at least three orientations, wide feathering,
and uneven seeded height/width/lean.

**Proof checkpoint:** fixed-seed layer isolates and composites at 0°, 90°, and
180° camera yaw, plus a literal comparison with the supplied frame. The same
world-space layout must remain planted at the caster from every yaw.

**Adds to final validation coverage:** moving-camera spatial ownership,
multi-yaw silhouette, reduced vertical reach, honest MultiMesh counts, and
unchanged ground/particle layers.

**Resolution (2026-08-12):** Implemented; pending end-of-plan validation. The
full-screen core and fan were removed along with their `INV_VIEW_MATRIX`,
`MODELVIEW_MATRIX`, normal-matrix, and camera-forward origin overrides. The
replacement is six short alpha-mixed radial texture cards plus eighteen seeded
crossed-ribbon instances in one `MultiMesh`; maximum ray height is 1.44 units,
and the brightest core is capped at 1.12 units. The crossed two-face primitive
keeps a feathered ray legible at arbitrary yaw without making it a billboard.
Only the twelve small puff particles retain ordinary sprite billboarding; their
positions and travel remain effect-local.

The effect still reports four draw calls and an honest ceiling of twenty-five
non-particle geometry instances: one vortex, six core cards, and eighteen ray
instances. It reuses `neutralSoftPuff()` and `lanceStreak()` without changing
either shared texture, and no external or proprietary reference asset was
imported.

Fixed-seed phase sheets at 0, 90, and 180 degrees verified that the same layout
stays planted at the target and keeps a comparable body-height envelope from
each yaw. A literal supplied-reference/current-output plate confirmed the
remaining adaptation is the expected 2D-to-3D translation: independent dark
vortex, dense low cyan bloom, broken rays, and sparse motes rather than one
screen sheet. Godot's editor/import parse and a bounded debug-scene load both
exited 0; `git diff --check` passed. No battle was launched at this
implementation-item boundary.

`docs/VFX_DESIGN.md` now records the world-space stack, and
`docs/LEARNINGS.md` records the verified orbit-camera billboard failure and its
multi-yaw review trigger. The unrelated working-tree edits in `AGENTS.md` and
`docs/POLICIES.md` remain user-owned and unstaged. Existing backlog entries are
unchanged; no new unresolved work was found.

### AURA-3 — Rework the ground layer into a starburst, and restyle the motes

**Superseded 2026-08-12 by AURA-2E.** Its ground and particle scope is absorbed
by the spiritual-vortex implementation; do not execute this item separately.

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

**Resolution:** superseded before execution; validation coverage moved into
AURA-2E and AURA-4.

### AURA-2G — Replace pointed ground spirals with emanating aura rings

**Model:** Opus 5 / GPT Sol (GPT-family VFX authorship required by project
policy).

**Depends on:** AURA-2F and the user's 2026-08-12 correction that the cyan
ground contours in the reference are aura rings viewed obliquely from above,
not flat shards or pointed spiral brush marks. The unrelated working-tree edits
in `AGENTS.md` and `docs/POLICIES.md` remain user-owned and unstaged.

**Files:** `assets/shaders/effects/spell_cast_ground_vortex.gdshader`,
`src/presentation/effects/SpellCastAuraProfile.gd`, `docs/VFX_DESIGN.md`, this
plan, and relevant backlog reconciliation only if new unresolved work appears.

**End state:**

- Keep the existing world-horizontal `PlaneMesh`; the camera pitch, rather than
  view-baked geometry, supplies the apparent ellipse.
- Remove the angle-fractured spiral and the high-contrast angular breakup that
  terminate cyan marks as pointed blades. Draw two or three independently
  expanding annular waves around the caster instead.
- Give each wave a broad feathered body, gentle low-frequency radial wobble,
  mild continuous opacity variation, and a radius-dependent fade. Gaps may be
  soft and cloudy, never tapered shard silhouettes.
- Keep the ink-dark central pool as a separate mask below the rings. Preserve
  the effect's one ground draw call, deterministic seed/progress behavior, and
  shared-resource compatibility; import no external asset.

**Risk:** mathematically perfect rings can read as a targeting reticle, while
excessive angular noise recreates broken shards. Use different wave radii,
widths, alpha, and distortion phases, but keep opacity continuity around most
of every circumference.

**Proof checkpoint:** ground-only and full-composite phase sheets at a fixed
seed, followed by 0, 90, and 180 degree ground-only captures. Compare the
ground-only hold frame directly with the user's crop and the original supplied
reference: it must read as waves emanating from the caster, not blades lying on
the floor.

**Adds to final validation coverage:** concentric-wave semantics, soft ring
endpoints, dark-pool separation, multi-yaw ground projection, and unchanged
draw-call/resource budgets.

**Resolution (2026-08-12):** Implemented; pending end-of-plan validation. The
ground shader no longer wraps radius through `fract(angle)` or thresholds an
angular breakup mask. It now composes three staggered `soft_ring()` annuli whose
radii travel outward independently, with broad feathering, low-frequency radial
wobble, and continuous seeded opacity variation that never drops a
circumference into pointed fragments. The ink-dark centre remains an independent
mask below the cyan waves. Ring alpha, crest alpha, and emission were reduced
after the first capture pass so the result reads as cloudy energy rather than a
bright targeting reticle.

Fixed-seed ground-only and composite phase sheets verified charge through decay.
Ground-only hold captures at 0, 90, and 180 degrees remained centred on the
same world point and projected naturally as camera-dependent ellipses without
any view-facing geometry. Forward+ rendered every capture without shader error;
the Godot editor/import parse exited 0 and `git diff --check` passed. The layer
still uses its existing horizontal plane and one draw call; no shared resource
or external asset changed. No battle was launched at this implementation-item
boundary.

`docs/VFX_DESIGN.md` now records the corrected dark-pool-plus-annuli semantics.
The unrelated `AGENTS.md` and `docs/POLICIES.md` edits remain user-owned and
unstaged. Existing backlog entries are unchanged; no new unresolved work was
found.

**Post-resolution review:** rejected by the user's eleven-frame source sequence.
The implementation remains committed history but is superseded by the
reference-locked rebuild below. Do not tune or preserve its three-annulus look.

### AURA-2H — Forensic frame decomposition and rebuild contract

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-2G and the user's eleven consecutive 2026-08-12 source
frames. This is an analysis/plan item only; it does not alter the runtime aura.

**Files:** `implementation_plan.md` only. Generated contact/difference sheets
and the expanded forensic note live outside the repository; all execution-
critical measurements are transcribed into this plan so later items have no
external-file dependency.

**End state:**

- Measure the source's colour, energy, bounds, lower-rim radius, and consecutive
  structural change after masking static UI/character pixels.
- Describe the supported visual systems, frame-by-frame motion, and unresolved
  black-background/alpha ambiguity without inventing inaccessible engine facts.
- Audit every current aura layer as keep, remove, or replace.
- Define a camera-mobile reconstruction and dependency-ordered implementation
  items with source-backed acceptance criteria.

**Risk:** treating the screenshots as alpha-bearing source art, or interpreting
static black background as proof of an opaque dark disc, would lock a false
material decision into implementation. Keep that ambiguity explicit and gated.

**Adds to final validation coverage:** exact eleven-frame comparison, measured
two-swell timing, spatial/colour envelope, unsupported-layer removal, and the
transparent-versus-darkened centre decision.

**Resolution (2026-08-12):** Completed. The resolved gate and established facts
above contain the measured evidence. The current three annuli, six core cards,
eighteen crossed ribbons, twelve puffs, and monotonic visual envelope are all
rejected. Playback/catalog/debug infrastructure is retained. No runtime or
asset file changed, and no battle was launched.

### AURA-2I — Retire rejected carriers; build the footprint aperture A/B

**Model:** Opus 5 / GPT Sol (GPT-family VFX authorship required by project
policy).

**Depends on:** AURA-2H. Starts from a task-owned clean boundary. The unrelated
`AGENTS.md`, `docs/POLICIES.md`, `vfx_debug_scene_rework_plan.md`,
`src/presentation/RetroRenderController.gd`, and
`src/presentation/debug/VfxDebugArguments.gd` changes are user-owned and must
remain unstaged and untouched.

**Files:** `src/presentation/effects/SpellCastAura.gd`,
`src/presentation/effects/SpellCastAuraProfile.gd`, replace or rename the owned
ground shader, remove the owned core/ray shaders and `.uid` files after caller
searches, `docs/VFX_DESIGN.md`, this plan, and relevant backlog reconciliation.

**End state:**

- Remove the six core cards, eighteen crossed ray instances, twelve wisps, their
  build/update/isolation paths, and their effect-owned shader resources. Stop
  consuming `neutralSoftPuff()` and `lanceStreak()` without modifying either
  shared factory.
- Preserve `VfxPlayback`, normalized seek/replay/skip/disposal, catalog creation,
  and the debug scene's generic layer-isolation contract.
- Replace the three annuli with one world-horizontal footprint carrier. It has
  one evolving aperture boundary and two or three tightly clustered internal
  striations only in the early states; the strokes simplify as the aperture
  grows. No separated wave rings or pointed fragments are allowed.
- Implement a debug-selectable transparent-centre versus low-alpha navy-
  darkened-centre variant. Both share identical rim geometry and timing.
- Report the honest interim budget: one visual draw call, zero particles, zero
  hero billboards, with room reserved for two plume-shell calls.

**Blocking user decision:** capture both centre variants on representative light
and dark terrain. Record which interpretation is accepted before AURA-2K; the
black-background source frames cannot decide it. AURA-2J may proceed because its
plume work is independent of this choice.

**Risk:** a perfect ring reads as a targeting reticle, while too many displaced
strokes recreate the rejected concentric-wave design. Keep all striations close
to one boundary and source-key their visibility.

**Proof checkpoint:** footprint-only eleven-phase sheets for both centre modes
on light and dark terrain, plus 0/90/180 yaw. Place the matched hold/recession
states beside source frames 1, 8, 10, and 11.

**Adds to final validation coverage:** removal of unsupported layers/resources,
single-boundary semantics, centre-material A/B, early-to-late rim simplification,
multi-yaw projection, zero-particle budget, and unchanged playback contract.

**Resolution (2026-08-12):** Implemented; pending end-of-plan validation and the
explicit centre-mode decision. `SpellCastAura` now owns one horizontal
`FootprintAperture` plane and no cards, ribbon instances, particles, or shared
procedural textures. Its shader renders one contracting-then-expanding boundary
with two close early striations, and `set_center_darkening()` plus
`--spell-aura-transparent-center` switches off only the approved navy centre fill. Playback,
seek, settle, disposal, catalog construction, and layer isolation remain on the
existing contract; the reported interim budget is one geometry instance, one
draw call, zero particles, and exact seek.

The controlled proof set is stored outside the repository in the task's
visualization directory: light-terrain and dark-terrain eleven-state sheets for
both centre modes, unobstructed light/dark A/B plates, 0/90/180-degree yaw
captures, and `aura_source_vs_footprint_checkpoint.png` pairing source frames 1,
8, 10, and 11 with the corresponding footprint states. The yaw plates preserve
the same world-horizontal projection, confirming that no hero billboard
remains. The darkened centre is visually closer to the source's negative-space
well on both terrain values, but runtime deliberately remains transparent until
the user accepts that interpretation. The three rejected owned shaders and
their UIDs were removed after caller search; the neutral shared texture factory
was not changed. No battle was launched, and the unrelated user-owned working
tree changes listed above remain unstaged and untouched.

### AURA-2J — Author the plume-flow atlas and world-space curtain

**Model:** Opus 5 / GPT Sol (GPT-family VFX authorship required by project
policy).

**Depends on:** committed AURA-2I implementation. The centre-mode decision may
remain open because the plume carrier does not depend on it.

**Files:** new project-owned plume atlas under
`assets/vfx/spell_cast_aura/`, its import metadata and retained deterministic
generator/source if one is used, a new owned plume-curtain shader,
`src/presentation/effects/SpellCastAura.gd`,
`src/presentation/effects/SpellCastAuraProfile.gd`, `docs/VFX_DESIGN.md`, this
plan, and relevant backlog reconciliation.

**End state:**

- Author an original seamless eleven-state alpha atlas in angular-U by height-V
  space. Its frames encode four or five broad feathered plume groups, asymmetric
  lateral/upward emphasis, soft roots, and changing group widths. Do not copy
  pixels from the supplied screenshots and do not import proprietary game art.
- Build two continuous flared ring shells as owned `ArrayMesh` geometry. Their
  outward-facing winding and front-face culling render only the far hemisphere
  from an external camera, keeping the character clean without a billboard,
  view-facing matrix override, or camera-relative origin shift.
- Map the atlas seamlessly around each shell. Give the inner and outer shells
  different radius/height/UV phase and low opacity so overlap builds the broad
  plume crown without a hard cone silhouette or individual card edges.
- Provide deterministic current/next atlas-state sampling with a tunable stepped
  versus cross-faded transition. Use normalized playback progress, never `TIME`.
- Preserve the total target budget of three visual draw calls including the
  footprint, zero particles, and zero hero-scale billboards.

**Risk:** a visible U seam, wrong triangle winding, or insufficient near-side
culling can turn the curtain into a solid cylinder or wash cyan over the model.
An over-regular atlas can become a printed sunburst. Validate layer isolates and
camera yaws before integrated timing work.

**Proof checkpoint:** atlas contact sheet, inner-only/outer-only/combined plume
captures, character-occlusion inspection, and 0/90/180 yaw on both bright and
dark terrain. Compare the combined silhouette with source frames 2, 3, 7, 8,
and 10 at matched character scale.

**Adds to final validation coverage:** original-atlas provenance, seamless flow,
far-hemisphere occlusion, broad-plume silhouette, moving-camera stability,
stepped/cross-fade capability, and the three-call budget.

**Resolution (2026-08-13):** Implemented; pending end-of-plan validation. The
effect now owns an original, deterministic 11x1 alpha atlas plus its retained
Python/Pillow generator. Every 64x64 cell is authored in angular-U by height-V
space from four changing broad plume groups, offset shoulders, and a continuous
soft root; the generator verifies identical first/last U texels per frame and
contains no pixels from the supplied screenshots.

Two phase-offset flared `ArrayMesh` shells sample current/next cells from
normalized progress and expose either cross-faded playback or deterministic
stepping through `set_plume_state_crossfade()`; the later source-matching item
selected stepping as the default and retained `--spell-aura-crossfade-plume`
for comparison. Their corrected Godot winding plus shader
`cull_front` renders only the far hemisphere. Standalone 0/90/180-degree plates
on light and dark terrain confirm the plume remains planted behind the opaque
character proxy with no body wash, billboard matrix, camera-relative origin,
particle, or `TIME` dependency. Inner-only, outer-only, combined, stepped,
atlas-contact, and source-checkpoint plates are stored in the task's external
visualization directory. The budget is exactly three visual instances/draw
calls including the footprint and zero particles.

The concurrently developed debug-scene refactor changed its capture contract,
so verification used a temporary standalone plate that was removed after
capture. Once that independent work committed and released its overlapping
documentation surface, the persistent aura design section was reconciled here.
Its live-authoring additions to `SpellCastAura.gd` remain as a separate unstaged
working-tree layer and are not part of this item. No battle was launched.

### AURA-2K — Match the eleven-state motion, colour, scale, and composite

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-2I, AURA-2J, and the blocking centre-mode decision recorded
from AURA-2I's terrain A/B.

**Files:** `src/presentation/effects/SpellCastAura.gd`,
`src/presentation/effects/SpellCastAuraProfile.gd`, owned footprint/plume shaders
and atlas only as tuning requires, `docs/VFX_DESIGN.md`, `docs/MODULE_MAP.md` only
if layer/resource inventory changes, this plan, and relevant backlog
reconciliation.

**End state:**

- Map the eleven source states across the existing brief visible duration and
  encode separate deterministic curves for plume energy, atlas state,
  aperture radius, rim thickness, striation visibility, and terminal fade.
- Match the measured relative plume-energy sequence
  `1.00, 1.13, 1.11, 0.96, 0.79, 0.64, 0.61, 0.76, 0.82, 0.85, 0.70` within
  visual tolerance, including the secondary swell instead of smoothing it into
  one decay.
- At the source-matched angle, keep the energy-dense field approximately 2.3
  character widths across, concentrated from the shoulders downward, with only
  faint tips above the head. Match deep saturated blue-cyan without a white
  core; preserve catalog element tint hierarchy for non-ice colours.
- Choose stepped or cross-faded atlas playback from literal comparison, not
  preference. Seed may rotate/subtly perturb plume phase but must preserve the
  reference grouping and all deterministic seek guarantees.
- Update honest node/geometry/draw/particle assertions and owning documentation.

**Risk:** exact scalar matching can still miss silhouette if the atlas states
are wrong; conversely, aggressive cross-fading can blur the frame-specific flow
into generic haze. Judge each matched state, not only the contact sheet average.

**Proof checkpoint:** eleven Road of Nogg captures beside all eleven supplied
frames at comparable character scale, plus footprint-only and plume-only rows.
Repeat the full composite at 0/90/180 yaw, retro on/off, and at least ice, fire,
thunder, darkness, and neutral tints. Any visible clean rings, rods, puffs,
central column, body wash, or monotonic-only fade fails the checkpoint.

**Adds to final validation coverage:** reference-state timing, two-swell energy,
aperture growth/simplification, colour/scale envelope, seed invariance, layer
hierarchy, retro readability, five element colours, and final resource budgets.

**Resolution:** implemented; pending end-of-plan validation. The playback now
maps normalized seek onto eleven explicit source positions and independently
samples the measured plume-energy, aperture-radius, rim-width, and striation
curves. A separate visibility tail preserves the last matched state at `0.82`
and clears all layers by `0.90`. Literal comparison selected stepped atlas
playback as the default; the retained `--spell-aura-crossfade-plume` path shows
that cross-fading softens away the frame-specific plume groups. Seed affects
only a small angular phase offset. The user approved the low-alpha navy centre
as the runtime default; `--spell-aura-transparent-center` retains the A/B path.

Proof was captured in the VFX debug scene as an eleven-state ice composite,
footprint-only and plume-only eleven-state rows, 0/90/180-degree yaw grids with
retro both off and on, five element plates (ice, fire, thunder, darkness, and
neutral), seeds 7 and 42, and a `0.82/0.86/0.90/1.00` terminal-fade row. The yaw
grid confirms world-space occlusion without billboarding; the isolated rows
confirm that the broad forms are continuous plume-shell emission rather than
flat shards or separate ground rings. The effect still reports three
instances/draw calls and zero particles. Godot import/parse and focused diff
integrity checks complete this item; no battle was launched.

### AURA-2L — Restore the body-enclosing rotating spike crown

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-2K and the user's post-validation comparison against the
eleven supplied animation frames.

**Files:** `src/presentation/effects/SpellCastAura.gd`,
`src/presentation/effects/SpellCastAuraProfile.gd`, the owned plume and
footprint shaders, the project-authored plume atlas and its retained generator,
this plan, and relevant backlog reconciliation.

**End state:**

- Replace the timid far-side-only composition with a strong world-space crown
  that visibly surrounds the caster. The inner shell may wash lightly across
  the camera-side body so the model reads as inside the aura; the outer shell
  remains ghostlier and preserves character readability.
- Turn the atlas field into smooth, sharp-tipped upward tongues rather than
  broad puffs, literal flat shards, or clean concentric rings. Keep a narrow
  dark aperture and close irregular rim only as the ground anchor; it must not
  dominate as a slow cyan puddle.
- Drive coherent angular spin and independently phased vertical tip
  oscillation from normalized playback progress. Do not use `TIME`, particles,
  billboards, camera-relative placement, or a camera-facing transform.
- Preserve the eleven source checkpoints and two-swell energy curve while
  increasing the crown's height, brightness, and body overlap to the user's
  approved direction in attachment 1.
- Retain the three-instance/draw-call ceiling and project-owned deterministic
  atlas source.

**Risk:** front-side additive coverage can bleach the character; excessive
vertex motion can expose the shell's geometry as hard shards; and overly
regular tongues can resemble a printed sunburst. Judge enclosure, softness,
and irregularity together from multiple camera yaws.

**Proof checkpoint:** focused native-retro captures of all eleven source states,
plus isolated inner/outer/footprint layers and 0/90/180-degree yaw composites.
Compare the composite directly with the supplied source frames and attachment
1; fail any result dominated by broad ground rings, lacking body overlap, or
showing billboard/card behavior. Record a narrow load/parse probe only; battle
and full integration remain consolidated in AURA-4.

**Adds to final validation coverage:** body enclosure, rotating flow, independent
ghost-tip oscillation, sharp upward silhouette, restrained ground anchor,
multi-yaw stability, deterministic seek, and unchanged visual budgets.

**Resolution:** implemented; pending end-of-plan validation. The footprint is
now a smaller, lower-energy dark anchor rather than the dominant cyan carrier.
The retained deterministic atlas was regenerated with seven irregular
Gaussian tongue groups whose local height narrows toward feathered pointed
tips. The two world-space shells are taller, wider, and brighter: the outer
shell discards its camera-side faces, while the inner shell retains only a
normal-facing low-opacity body wash. The explicit source-state position now
drives 0.72 angular turns plus two independently phased vertex-height waves;
there is still no `TIME`, billboard, particle, or camera-relative transform.

Focused native-retro evidence covers all eleven source checkpoints, isolated
inner/outer/footprint carriers, and 0/90/180-degree camera yaws at seed 7. The
sequence shows plume groups rotating around the caster while their tips rise
and fall, and the yaw plates show a planted world-space crown. Isolated
footprint capture contains no broad travelling rings. Godot 4.4 imported and
parsed the modified shader and deterministic atlas; no battle was launched.

### Replica gap assessment after AURA-2L

The user's latest comparison accepts the direction but restores the eleven
source frames as the final authority. AURA-2L solved timidity and world-space
enclosure, but its result is still a bright flame crown rather than a replica:

- the source's energy-dense mass is low and wide, from the aperture through the
  waist, while the current result concentrates a few opaque tongues above the
  head;
- the source has a continuous smoky blue fan between its rays; the current
  atlas exposes isolated lobes and the flared shell's side edges as cyan wings;
- the source stays deep blue-cyan with no large white areas; the current single
  additive material clips toward pale cyan/white on overlap and bright terrain;
- the source aperture is a readable dark oval with close irregular hairlines;
  the current reduced footprint is nearly absent behind the debug pedestal;
- the source reorganizes and pulses with modest directional drift; the current
  `0.72`-turn angular offset reads as a carousel and its large vertex lift reads
  as tall flame animation;
- the source's longest spikes are faint ghost rays, whereas the current longest
  shapes are also its most opaque shapes.

The next work therefore changes the decomposition and authored source masks;
it is not another scalar-tuning pass on the shared additive curtain.

**Blocking execution prerequisite:** the worktree currently contains concurrent
unstaged debug-scene, live-tuning, profile, and policy edits. Each item below
starts only after those edits have been committed or otherwise resolved by
their owner. Do not stash, stage, overwrite, or absorb them into an aura commit.

### AURA-2M — Measure the source and make comparison reproducible

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-2L and a clean worktree after the blocking prerequisite.

**Files:** a retained source-measurement table beside
`assets/vfx/spell_cast_aura/generate_plume_atlas.py`, narrowly scoped additions
to the VFX debug world/controller and capture documentation if the current
authoring work has released those surfaces, this plan, and relevant backlog
reconciliation.

**End state:**

- Record all eleven frames as normalized measurements relative to the visible
  character bounds, not absolute screenshot pixels: aperture width/height,
  occupied aura width, dense-field height, faint-tip height, vertical energy
  centroid, outer-ray count, and per-ray angle/width/height/strength.
- Record palette stops and relative luminance for the dark outer haze, blue
  body field, cyan ray crests, and black/navy aperture. Keep the screenshots as
  non-shipping reference inputs; do not copy third-party pixels into runtime
  assets or derive a texture by extracting them.
- Add a reproducible comparison view with a black isolation backdrop, neutral
  proxy/pedestal-off presentation, fixed reference yaw/pitch, and matching
  character scale. Retain normal terrain capture as a separate truth surface.
- Produce paired eleven-state sheets plus vertical-band occupancy and luminance
  summaries so a visually larger flame cannot pass merely because total energy
  is similar.

**Risk:** measuring against the screenshot's black background can overfit alpha
and make the result disappear on real terrain; character/UI pixels can also
pollute masks. Measure the aura outside an explicit character exclusion region
and require both isolation and terrain plates.

**Proof checkpoint:** one source-measurement report, one source/current paired
sheet at matched character scale, one black-backdrop capture, and one normal
terrain capture. The report must make the six replica gaps above numerically or
visually testable before any carrier is rebuilt.

**Adds to final validation coverage:** reference framing, normalized silhouette
width/height, vertical energy distribution, palette/luminance bands, aperture
visibility, and black-versus-terrain transfer.

**Resolution:** implemented; pending end-of-plan validation. The retained JSON
table records all eleven frames relative to a fixed character box at faint,
dense, and crest chroma thresholds, including occupied widths, vertical extent,
energy centroids, aperture dimensions, outer-ray counts, palette percentiles,
and explicit acceptance tolerances. Measurements contain no copied source
pixels. The debug world now accepts `--comparison-isolation`, which hides both
terrain islands, the ground, bases, markers, guides, and the caster proxy while
leaving the neutral target body and world-space effect on a true black
environment. A native-retro eleven-state baseline and focused black frame prove
the old crown's tall/white/winged failure in the same reproducible framing.
Godot 4.4 imports and parses the new comparison path. No battle was launched.

### AURA-2N — Split the low haze from the additive ghost rays

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-2M.

**Files:** `src/presentation/effects/SpellCastAura.gd`,
`src/presentation/effects/SpellCastAuraProfile.gd`, replacement owned plume
shaders, the owned shell mesh builder, atlas generator/output only as required
for channel routing, `docs/VFX_DESIGN.md`, `docs/MODULE_MAP.md` only if the
resource inventory changes, this plan, and relevant backlog reconciliation.

**End state:**

- Retire the one-shader/two-role coupling that infers inner versus outer
  behavior from `uv_phase`. Give the compact inner haze and outer ghost rays
  explicit owned materials/shaders and explicit parameters.
- Render the inner body field with alpha-mixed deep blue translucency, peaking
  around the feet/legs and fading by the shoulders. Its controlled camera-side
  contribution encloses the model without additive whitening.
- Render only the sparse outer rays additively. Use a far-side world-space
  carrier and a softer grazing fade so no camera yaw reveals a continuous cup,
  skirt, shoulder wing, flat card, or hard cone boundary.
- Replace the linear flare with separate measured radial profiles for the haze
  and ray shells. Preserve world-up geometry, deterministic seek, and zero
  billboard/camera-relative transforms.
- Keep exactly three carriers/draw calls — aperture, haze, rays — and zero
  particles. Do not import an external effect pack; the source can be recreated
  with project-owned masks and materials.

**Risk:** alpha-mixed haze can sort incorrectly against the caster or terrain,
while separating materials can introduce a visible seam or double-energy band.
The shell profiles can also remain geometrically legible if their alpha roots
are not independently controlled.

**Proof checkpoint:** isolated aperture/haze/ray plates plus their composite on
black and bright terrain at 0/90/180-degree yaws. Fail visible cup edges,
front-side wings, body bleaching, white clipping, or any budget above three
draw calls. Record only a narrow Godot load/parse probe; no battle launch.

**Adds to final validation coverage:** blend-mode separation, body enclosure,
terrain transfer, transparent sorting, world-space camera orbit, carrier seams,
and unchanged budgets.

**Resolution:** implemented; pending end-of-plan validation. The former
phase-switched additive curtain and its shader were removed. `SpellCastAura`
now builds three explicit roles: the existing aperture, an alpha-mixed haze
shader on a compact early-broadening profile, and a far-side-only additive ray
shader on a taller gradual profile. The haze performs five angular samples to
bind the current atlas into a continuous deep-blue lower field, extinguishes
grazing geometry, and admits only a restricted camera-side body contribution.
The ray shader high-passes the atlas, fades its root and top, and discards all
camera-side faces. Black and terrain plates at 0/90/180 degrees plus isolated
aperture/haze/ray captures confirm the roles remain world-space, avoid white
body clipping, and hold the three-instance/zero-particle budget. The temporary
structural masks remain deliberately bland; the measured eleven-state artwork
and final edge breakup belong to AURA-2O. Godot 4.4 imports and parses both new
owned shaders. No battle was launched.

### AURA-2O — Author the eleven-state replica masks and restrained motion

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-2N.

**Files:** the retained source-measurement table, deterministic atlas generator
and generated project-owned multi-channel atlas/masks,
`SpellCastAuraProfile.gd`, the owned haze/ray/footprint shaders,
`SpellCastAura.gd` only where explicit normalized motion parameters are needed,
`docs/VFX_DESIGN.md`, this plan, and relevant backlog reconciliation.

**End state:**

- Generate separate haze, ray, and root-detail fields from the eleven measured
  states. Haze must be continuous and low/wide; ray tips must be narrow and
  ghostly; the most elevated pixels must never also form the most opaque mass.
- Raise atlas resolution or use an equivalent analytic feather so native-retro
  tips stay smooth instead of becoming jagged flame caps. Preserve periodic U
  seams and deterministic regeneration.
- Replace the current `0.72`-turn carousel with source-consistent directional
  drift while retaining the user's requested sense of spin. Cap provisional
  continuous rotation near a quarter turn unless the measurements support
  more; encode larger reorganization in the eleven authored masks rather than
  rotating the whole crown.
- Restrict outer tip oscillation to a ghost-ray amplitude measured in a small
  fraction of character height. Keep independent phases, but remove the large
  vertex lift that changes the carrier into licking flames.
- Restore the readable dark aperture and two or three close irregular
  hairlines without travelling or expanding puddle rings. Keep the lower-body
  field dominant, faint tips near head height, and deep blue-cyan colour without
  a white core.
- Preserve the source's two-swell energy curve, exact seek, pause/scrub,
  terminal fade, seed stability, element tint hierarchy, and three-call budget.

**Risk:** literal per-state masks can pop when stepped, while cross-fading can
blur the source's distinct groupings. Excessive fidelity at the reference yaw
can also fail when the camera orbits. Select stepping, short keyed transitions,
or channel-specific interpolation from paired evidence rather than applying one
transition policy to every field.

**Proof checkpoint:** all eleven source frames paired with the result at matched
character scale, plus difference/occupancy summaries, isolated channel rows,
and a real-time capture demonstrating subtle spin and independent ghost-tip
motion between checkpoints. Repeat the composite at 0/90/180-degree yaws,
retro on/off, black/bright terrain, and seeds 7/42. No battle launch.

**Adds to final validation coverage:** eleven-state silhouette replica,
low-versus-high energy hierarchy, smooth feathering, source-consistent spin,
ghost-tip oscillation, aperture hairlines, palette match, transition policy,
determinism, and orbit stability.

**Resolution:** implemented; pending end-of-plan validation. The deterministic
atlas now uses eleven measured 256x256 RGB cells: continuous low haze, sparse
ghost rays, and root hairlines, with a validated periodic seam and no copied
source pixels. A full 360-degree carrier authors twice the measured visible ray
population so every camera hemisphere retains the reference grouping density.
The haze and ray shaders use distinct channel-specific transitions, less than a
quarter-turn of normalized drift, and a `0.045`-unit ray-tip oscillation; neither
uses `TIME`, a billboard, or camera-facing transforms. Far-side-only compositing
removes the former front/back seam, while luminance is concentrated in
low-alpha additive rays instead of opaque flame caps. The aperture remains one
dark evolving boundary with close non-travelling hairlines. Black-backdrop
captures at matched source scale, four timeline checkpoints, and isolated
haze/ray plates were recorded in the external evidence directory. Godot 4.4
regenerated imports and parsed the revised atlas and shaders. No battle was
launched in this implementation item.

### AURA-4 — Consolidated final visual, lifecycle, and battle validation

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-1, AURA-2, AURA-2B, AURA-2C, AURA-2H, AURA-2I, AURA-2J,
AURA-2K, AURA-2L, AURA-2M, AURA-2N, and AURA-2O. AURA-2D and AURA-3 were superseded before execution; AURA-2E,
AURA-2F, and AURA-2G were implemented but their visual results were superseded
by the eleven-frame authority pivot.

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
2. At one fixed seed, capture the empty/charge lead-in, all eleven matched
   aperture/plume states, and clear. Judge them at native retro resolution, not
   only enlarged, and place every matched state beside its supplied source
   frame at comparable character scale. Re-run the normalized silhouette,
   vertical-energy, aperture, and palette measurements established by
   AURA-2M; every state must meet its recorded tolerance rather than passing on
   a subjective average. Include one real-time duration capture proving that
   the between-state drift reads as casting flow rather than a carousel or
   licking fire.
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
validation result. Then, in the same session, grep the repository for every
`AURA-` identifier from this cycle, rewrite any accidental persistent reference
as a durable description, and clear
`implementation_plan.md` completely in a follow-up lifecycle-cleanup commit.

**Validation result (2026-08-13): blocked at project shutdown.** The aura's
own visual, lifecycle, budget, regression, and live-battle coverage passed, but
this plan cannot yet be closed because `Battle25D` exits with Windows access
violation `-1073741819` and 46 retained resources even from the untouched setup
screen. A detached pre-aura comparison at `b678bf2` reproduces the identical
failure, proving it is pre-existing rather than introduced by this cycle; it is
now recorded in the critical backlog and requires a broader script/resource
ownership fix outside the aura plan.

The later body-enclosing spike-crown revision supersedes the aura imagery from
that pass. Its focused implementation evidence is recorded above, but its live
battle, CRT, lifecycle, and shared-effect regression coverage must be repeated
inside this final item once the shutdown blocker is resolved.

Completed evidence: the native-retro lead-in, eleven matched states, and clear;
320x240 retro/non-retro composites for five element colours at 0/90/180-degree
yaws; isolated footprint/plume yaw matrices; seeds 7 and 42; pause/resume,
0.5x/2x speed, forward/backward scrub, skip-to-settle, retrigger, four
simultaneous auras, three instances, zero particles, and clean aura disposal.
The live Meadow battle completed with six generic spells across darkness, fire,
light, thunder, and wood, including 28 multi-target area casts and 36 casts
touching uneven terrain; gameplay resolved Team 2 as winner and the queue did
not watchdog. A real CRT battle frame confirms event-time placement and caster
occlusion. Fresh 320x240 retro captures of Ice Storm, Fire Storm, Magenta
Reduction, and Ice Target Encasement show no shared-resource regression.

Validation also found and fixed a separate integration defect: damage-number
safety timers strongly captured billboards already freed by their normal tween,
causing repeated freed-lambda errors during long battles. The timer now binds a
`WeakRef` into a named cleanup callback; a focused delayed-cleanup probe and the
full battle rerun contain no freed-capture, locked-object, or watchdog error.

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
- No further parameter-tuning pass on a rejected silhouette. Every new carrier
  and atlas state is re-checked against the complete eleven-frame sequence.
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
