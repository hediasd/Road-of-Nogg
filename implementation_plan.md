# Ice Target Encasement VFX Cycle

**Opened 2026-08-10.** The previous contents were the Pixel-Exact UI cycle,
opened 2026-08-09, followed by the direct adoption of Nogg Terminal as the
battle UI face. Its final validation passed and every implementation item was
complete. Its only deliberately open findings already live durably in the
backlogs: the prompt window can collide with the developer HUD
(`BACKLOG_CRITICAL.md`), and the footer/body hierarchy under the fixed-size
bitmap face still needs a design decision (`BACKLOG_LONGTERM.md`). Nothing else
from that cycle remains open or was moved during this reset. That completed
cycle existed only in the current uncommitted working tree rather than in Git;
its durable conclusions are in `docs/UI_DESIGN.md`, but its full resolution log
cannot be recovered with `git show`.

Before this reset, every `PX-1` through `PX-6` reference outside the transitory
plan was rewritten as a durable description. No persistent file now depends on
those expired identifiers.

---

## 1. Goal

Build a target-bound ice attack inspired by the supplied Digimon World 1
reference. The central behavior is a **literal three-dimensional shell of
large transparent-cyan ice blocks and shards that erupts around the target,
holds as an enclosing mass, and then breaks apart using those same visible
pieces**.

The caster-to-target trail and blue square contact accents are supporting
layers. They must never become the effect's dominant read. Damage numbers stay
owned by the existing damage-number presentation, and the yellow rings in the
reference are explicitly out of scope.

The finished effect must:

- propagate from the caster to the impact point as a sequential trail of
  terrain-anchored ice spikes, never as a thrown projectile or dotted lance;
- make the final trail spike trigger a bottom-up eruption of the enclosing
  cocoon so delivery and formation read as one continuous event;
- envelope the target from behind, both sides, in front, and above with real
  low-poly geometry that has visible depth, parallax, deliberate asymmetry, and
  a few large screen-readable hero slabs rather than a regular faceted egg;
- render the ice as transparent cyan with bright overlapping cores and darker
  blue faces, preserving PS1 readability without modern refractive glass;
- close the visual gaps with a restrained bright internal ice core without
  using that core to fake the shell;
- hold long enough for the completed enclosure to read;
- move the same shell pieces through deterministic ballistic breakup
  trajectories with varied velocity, gravity, angular motion, size-dependent
  weight, and four to six readable hero fragments;
- preserve pause, speed scaling, backward/forward scrub, skip, replay, overlap,
  and disposal behavior under the existing `VfxPlayback` contract;
- remain presentation-only: no gameplay stun, damage, targeting, or state
  mutation is added by this cycle.

The working profile id is `ice_target_encasement`. That is presentation
metadata, not a new spell or lore name.

## 2. Blocking gates

### Existing working tree — resolved 2026-08-11

The user authorized committing all pending work and removing the obsolete
untracked `vfx_plan.md`. The prior tree was audited into focused commits before
this cycle began:

- `971396a` — pixel-exact scalable battle UI and Nogg Terminal adoption;
- `8a61c64` — resolved live spell-footprint transport;
- `d8650f8` — Ice Plow and Smoke Tower footprint balance changes;
- `cccef2f` — scalable Ice Storm remodel and owned/shared VFX primitives;
- `cb2c4c5` — presentation learnings and backlog reconciliation;
- `c225a76` — preserved Magenta Reduction VFX brief.

`vfx_plan.md` was removed exactly as authorized. The active encasement plan is
now the repository's only delegation contract, and its first implementation
item starts from a clean `git status` as required by `AGENTS.md`.

### Carrier spell — resolved 2026-08-11

The user explicitly commissioned `Ice Statue` as a new single-target copy of
Ice Punch, with minimum range 1, maximum range 5, and
`VFX_PROFILE: "ice_target_encasement"`. Ice Punch remains unchanged, and Ice
Plow retains its area-storm profile. This authorization resolves the carrier
content/design gate without inferring a spell from its name.

The user subsequently chose Snowzilla as the owner. Ice Statue is appended to
Snowzilla's existing Ice spell set after Ice Punch, resolving the live-battle
availability gate without changing another monster or element.

### Fidelity direction — resolved 2026-08-11

After reviewing the first complete implementation against the supplied
Digimon World 1 frames, the user set the visual direction for the fidelity
pass:

- ice is transparent and cyan rather than predominantly opaque white-blue;
- the opening is a ground-propagating trail of growing ice spikes, not an
  object thrown through the air;
- the trail culminates in an eruptive cocoon around the target;
- the cocoon uses larger, less regular overlapping blocks and slabs;
- breakup motion must feel natural rather than like a uniformly lifted radial
  crown.

These are confirmed visual decisions, not blocking questions. Damage numbers
remain externally owned and the reference's yellow rings remain out of scope.

## 3. Established facts and design decisions

### The shell is geometry, not a collection of blue lances

The reference frames show large faceted blocks occupying different depths
around the victim. The Road of Nogg version therefore uses real low-poly meshes
with thickness for the enclosing pieces. Camera-facing cards are allowed only
for the travel streak, internal flash, and small contact accents.

The shell must still read when the trail, contact accents, and internal core
are hidden in the debug harness. This is the acceptance test that prevents a
bright billboard from doing the work the ice blocks are supposed to do.

### Formation and breakup share instance identity

Every large piece receives one deterministic intact transform and one
deterministic broken transform. Formation interpolates into the intact
transform; breakup interpolates that same instance outward. The implementation
must not delete the statue and spawn an unrelated shard burst at the break.

No rigid-body simulation or runtime fracture is needed. Fixed seeded
initial velocities, gravity, angular velocities, and optional analytic drag
give the pieces natural ballistic arcs while preserving exact scrub/replay
behavior. The effect computes each transform directly from normalized time; it
does not integrate frame-by-frame physics state.

### Fit the creature body, not the tile or model base

`GodotVisualAdapter` already accumulates mesh bounds for picking and status
placement. The new context path reuses that capability but measures the creature
body only: model bases, selection collision, status icons, and other
presentation helpers do not enlarge the shell. The effect receives a body-local
bounding box plus event-time source and impact positions.

Placement is normalized against that box so one authored layout can surround a
short/wide, standard, or tall/narrow body without inventing per-monster branches.

### Transparent cyan ice, not modern glass

The main ice read is transparent cyan. Large slabs retain enough opacity or
dithered coverage to preserve their silhouettes at the retro viewport's native
resolution, while selected faces and the internal overlap region build toward
bright white-cyan. Darker blue faces and edges separate adjacent chunks.
Front/rear render groups remain explicit so transparency sorting cannot place
the back of the statue over its front.

Nearest-filtered authored masks, stepped time, quantized transforms, and the
existing low-resolution/CRT path provide the PS1 character. Refraction,
screen-space distortion, physically based glass, and smooth particle fog are
out of scope.

### One generic cast-context path

The current factory gives effects an impact position and element color, with an
optional area footprint. The new transport must remain profile-driven:

- headless combat emits stable gameplay identities and resolved target data;
- `GodotVisualAdapter` converts those identities into event-time world
  positions and presentation-only body bounds;
- every `VfxPlayback` receives the same typed cast context through one standard
  method; effects that do not need it ignore it;
- no adapter branch names this effect or its carrier spell.

The simulation layer never imports a presentation context or a visual node.

### Target treatment is supporting, reversible presentation

If the live target visual has animation playback, the adapter may hold its pose
during the completed-shell window. A restrained cold tint may be applied only
through a generic presentation lease that records and restores prior visual
state. Completion, backward seek, skip, disposal, battle exit, and overlapping
effects must all release the lease safely.

The shell must remain readable without the tint. Neither pose hold nor tint
changes battle state or claims that the spell inflicts a gameplay status.

### Budgets

The profile owns and asserts its limits. Fidelity-pass ceilings for one effect
are:

- 18 enclosing pieces, with 9–12 expected to carry the completed silhouette
  and four to six designated as breakup hero fragments;
- 24 combined ground-spike and contact instances;
- 18 estimated peak draw calls;
- 28 effect-owned nodes;
- at most two simultaneous live encasement effects, with the existing adapter
  cap disposing the oldest before a third is admitted.

Counts, alpha, phase fractions, dimensions, quantization, and palette values are
named in `IceTargetEncasementProfile.gd` and labelled `AUTHORED`, `DERIVED`, or
`MEASURED` per `docs/VFX_DESIGN.md`. No tuning literal stays buried in the
effect or shader.

## 4. Proof checkpoints

VFX work is shown while it is still cheap to change. These are required item
outputs, not deferred final-validation evidence:

| Checkpoint | Required proof | Owner |
| --- | --- | --- |
| Context harness | Source marker, target body bounds, and three target proportions render through the shipping retro path. | Target-bound harness item |
| Shell skeleton | Mid-hold captures with **shell only** at front-quarter, side, and rear-quarter views. Visible depth, thickness, and enclosure; no trail/core/contact layers. | Shell-geometry item |
| Formation and fracture | One contact sheet spanning empty target, first blocks, closed statue, hold, initial break, wide break, and settle. Piece continuity is visually traceable. | Choreography item |
| Supporting layers | Trail-only and contact-only sheets, followed by a full composite. The full shell remains the dominant silhouette. | Delivery/contact item |
| Cyan material and silhouette | Matched hold frames with opaque core disabled, at three angles and three body presets. Ice remains visibly transparent cyan, overlapping faces approach white-cyan, and 9–12 asymmetric hero shapes remain countable at retro resolution. | Fidelity shell/material item |
| Ground-spike delivery and eruption | A tight sheet from empty ground through every spike advance into the first, middle, and completed cocoon frames. No geometry travels through the air; the last ground spike and first target slab form one continuous wave. | Ground-spike/eruption item |
| Natural fracture | A tight 0.02–0.04 normalized-time cadence across fracture plus a wider breakup sheet. Four to six hero chunks follow distinct ballistic arcs, rotate at size-appropriate rates, and avoid a uniform upward crown. | Ballistic-fracture item |
| Final look | Standard, wide, and tall targets through retro on/off, plus existing Ice Storm, Fire Storm, Magenta Reduction, and generic aura captures. | Final validation item |

An executing session stops at a checkpoint that fails visually and reports the
sheet to the user. It does not continue layering more work over a rejected
silhouette.

## 5. Items

### STATUE-1 — Carry generic source/target context to profile-driven VFX

**Model:** Opus 5 / GPT Sol

**Depends on:** clean-working-tree gate.

**Files:** `src/battle_sim/BattleEvents.gd`,
`src/battle_sim/CombatResolver.gd`,
`src/battle_sim/IBattleVisualAdapter.gd`,
`src/presentation/ConsoleVisualAdapter.gd`,
`src/presentation/VisualAction.gd`,
`src/presentation/GodotVisualAdapter.gd`,
`src/presentation/effects/VfxPlayback.gd`, a small typed context under
`src/presentation/effects/`, `docs/ARCHITECTURE.md`, `docs/VFX_DESIGN.md`, and
the relevant backlog files.

**End state:**

- `spell_cast_started` carries the ordered resolved target `uniqueID` values in
  addition to its existing resolved radius and shape. The event contains no
  node, mesh, material, or presentation type.
- `VisualAction` clones source/impact coordinates and target identities at
  enqueue time so delayed playback cannot read a later gameplay position.
- `GodotVisualAdapter` produces a typed presentation context containing source
  world position, impact world position, body-only local bounds for each
  resolved target, and stable target IDs.
- `VfxPlayback.configure_cast_context(context)` is a concrete default no-op;
  the adapter calls it uniformly before `play()` for every profile.
- Existing area effects continue receiving their live footprint through
  `setFootprint`; the new context complements rather than replaces that path.
- Missing or defeated visuals degrade to an authored standard body box at the
  event's impact point rather than causing the visual queue to wedge.
- Architecture and VFX documentation describe the ownership boundary once.

**Risk:** expanding an observational event can desynchronize console and Godot
adapters, while measuring a live node at playback time can violate the queue's
event-time snapshot rule. Keep gameplay identities in the event, snapshot
positions when enqueuing, and keep visual-bound lookup presentation-only.

**Adds to final validation coverage:** source and target positions remain
correct after queued movement; target IDs survive multi-target event transport;
existing generic and area profiles still play without reading presentation from
simulation.

**Resolution target:** implemented; pending end-of-plan validation. Run only
focused diff inspection, `git diff --check`, and the narrow import/load probe
needed to prove changed interfaces parse. Do not launch a battle.

### STATUE-2 — Give the VFX harness a truthful source, target, and body bounds

**Model:** Sonnet 5 / GPT Terra

**Depends on:** STATUE-1.

**Files:** `scenes/debug/VFXDebugScene.tscn`,
`src/presentation/debug/VFXDebugController.gd`, and the relevant backlog files.

**End state:**

- The harness builds an explicit caster anchor and target anchor and passes the
  same typed context used by battle playback.
- Target-body presets cover standard, short/wide, and tall/narrow bounds. They
  are selectable interactively and through CLI arguments.
- Source-to-target distance and camera yaw are controllable through both UI and
  CLI so a three-dimensional shell can be inspected from at least
  front-quarter, side, and rear-quarter views.
- The HUD reports the selected target bounds, separation, view angle, profile,
  seed, normalized time, node count, particle/instance count, and draw-call
  estimate.
- Capture mode preserves the existing phase-sheet and golden behavior while
  framing both the delivery path and the target.

**Risk:** a harness-only context or camera path can make an effect look correct
in a scene battle playback cannot reproduce. Construct context through the same
presentation helper used by `GodotVisualAdapter`, and keep retro rendering on by
default.

**Proof checkpoint:** capture the three target proportions and source/target
markers through the shipping retro path. No encasement look is claimed yet.

**Adds to final validation coverage:** every geometry/timeline observation the
plan asks for can be produced non-interactively before full battle validation.

**Resolution target:** implemented; pending end-of-plan validation. A narrow
debug-scene launch is allowed because the harness is the item's deliverable;
record it as a smoke/proof checkpoint, not integrated acceptance.

### STATUE-3 — Author the enclosing low-poly shell and faceted ice materials

**Model:** Opus 5 / GPT Sol

**Depends on:** STATUE-2.

**Files:** new `src/presentation/effects/IceTargetEncasementEffect.gd`, new
`src/presentation/effects/IceTargetEncasementProfile.gd`, new effect shader(s)
under `assets/shaders/effects/`, `src/presentation/effects/VfxTextures.gd` or a
small ice-chunk mesh factory if ownership is clearer there,
`src/presentation/effects/SpellVfxCatalog.gd` for debug registration only,
generated `.uid` sidecars, `docs/VFX_DESIGN.md`, and relevant backlog files.

**End state:**

- Two or three reusable meshes provide actual thickness: a block, a wedge, and
  an irregular crystal/slab. They are low-poly geometry, not billboard masks.
- Seeded placement distributes large instances into named rear, side, front,
  and cap groups around the supplied body bounds. Pieces overlap enough to read
  as one enclosing mass without becoming an undifferentiated opaque box.
- Each instance stores stable intact and broken transform data at creation;
  later items animate those transforms but do not replace the instances.
- Mostly opaque flat/faceted faces carry a small blue-white palette. Explicit
  rear/front grouping and render priority make ordering stable. A restrained
  internal core is a separate named layer and may be disabled.
- Layer names expose at minimum `shell_rear`, `shell_sides`, `shell_front`,
  `shell_cap`, and `ice_core`.
- Build-time assertions enforce chunk, node, and draw-call ceilings.
- The profile is registered so the debug harness can select it; no spell data
  changes in this item.

**Risk:** transparency can flatten the shell into a blue screen overlay, while
one normalized layout can leave gaps around extreme body proportions. Establish
solid geometry and parallax first, retune placement/count second, and add only
the minimum translucent overlay needed for ice character.

**Proof checkpoint:** show shell-only mid-hold captures at three camera angles
for the standard target, plus front-quarter captures for wide and tall targets.
The shell must visibly surround the body with the core, trail, and contact
layers hidden. If it does not, stop here.

**Adds to final validation coverage:** literal volumetric enclosure, stable
front/rear ordering, body-bound scaling, material readability through the retro
path, and hard budget compliance.

**Resolution target:** implemented; pending end-of-plan validation. Import and
run the debug capture needed for the checkpoint, but do not launch the game.

### STATUE-4 — Choreograph growth, completed-statue hold, and same-piece breakup

**Model:** Opus 5 / GPT Sol

**Depends on:** STATUE-3.

**Files:** `IceTargetEncasementEffect.gd`,
`IceTargetEncasementProfile.gd`, its shader(s), `VfxPlayback.gd` and
`GodotVisualAdapter.gd` only if the generic reversible target-treatment lease
requires them, `docs/VFX_DESIGN.md`, and relevant backlog files.

**End state:**

- The timeline has named authored windows for arrival, lower/side formation,
  front/cap closure, completed hold, fracture impulse, outward tumble, and
  settle. No frame relies on global `TIME`, accumulated physics, or random calls
  after seed configuration.
- Blocks enter in readable groups and grow from compressed positions near the
  body into their intact transforms. The cap arrives late enough to complete
  the statue rather than hiding the target from the first frame.
- The completed shell holds as a recognizable volume before breaking.
- Breakup interpolates every existing chunk toward its stored broken transform
  with stepped rotation and outward/upward motion derived from the target
  center. Large pieces remain countable; small debris cannot replace them.
- `seek_normalized()` reproduces formation, hold, and breakup both forward and
  backward. `skip_to_settle()` enters a safe late-break state rather than
  cutting a closed statue from the screen.
- If supported by the current visual type, a generic adapter-owned lease holds
  the target pose and applies a restrained cold tint only during the closed
  shell window. Every lifecycle exit restores prior presentation state. The
  effect remains acceptable with that layer disabled.

**Risk:** discontinuities at phase boundaries can make blocks pop, and an
external target tint/pose can leak after skip or disposal. Derive all transforms
as pure functions of normalized time, and centralize reversible target state in
the adapter rather than letting the effect mutate arbitrary materials.

**Proof checkpoint:** show one sheet spanning empty target, first lower blocks,
side closure, full statue, hold, initial separation, wide breakup, and settle.
Show a second shell-only sheet tight around the break so the same large pieces
can be followed across frames.

**Adds to final validation coverage:** formation order, readable hold, instance
continuity through fracture, exact seek, safe skip, and complete target-state
restoration.

**Resolution target:** implemented; pending end-of-plan validation. Debug
capture is allowed for the proof checkpoint; no full battle.

### STATUE-5 — Add the subordinate delivery trail and blue contact accents

**Model:** Opus 5 / GPT Sol

**Depends on:** STATUE-4.

**Files:** `IceTargetEncasementEffect.gd`,
`IceTargetEncasementProfile.gd`, its shader(s),
`src/presentation/effects/VfxTextures.gd` only for genuinely reusable masks,
`docs/VFX_DESIGN.md`, and relevant backlog files.

**End state:**

- A short sequence of directional cards or deterministic MultiMesh instances
  travels from the context's caster position to the target. It has a clear head
  and taper, reaches the target once, and disappears as shell formation takes
  over.
- Blue square contact accents appear briefly around the impact volume as a
  separately toggleable `contact_accents` layer. They signify contact but do
  not masquerade as large ice blocks.
- The internal flash is synchronized with first shell growth and remains
  subordinate to the opaque/faceted enclosure.
- Trail, contact, and any small debris stay under their combined instance cap.
  The shell occupies most of the timeline and remains the largest silhouette in
  the composite.
- The implementation is local to this effect. Do not extract a general hit
  marker until a second effect proves the same structure is reusable.

**Risk:** the easy-to-author bright trail can dominate attention and regress the
effect into “blue lances plus a flash.” Judge layer-isolated sheets first and
reject any full composite in which the completed shell is not the primary read.

**Proof checkpoint:** show trail-only, contact-only, and full-composite sheets.
Include the shell-only hold frame beside the composite hold frame to prove the
supporting layers did not replace the enclosure.

**Adds to final validation coverage:** correct caster-to-target direction,
contact timing, layer isolation, visual hierarchy, and combined budgets.

**Resolution target:** implemented; pending end-of-plan validation. Debug
capture is allowed for the proof checkpoint; no full battle.

### STATUE-6 — Register the confirmed single-target carrier and document runtime behavior

**Model:** Sonnet 5 / GPT Terra

**Depends on:** STATUE-1, STATUE-4, STATUE-5, and the recorded Ice Statue
carrier decision.

**Files:** `data/spells.json`,
`src/presentation/effects/SpellVfxCatalog.gd` if its debug registration still
needs production metadata, `docs/VFX_DESIGN.md`,
`docs/SPELL_CATALOG_SCHEMA.md` only if the schema truth changes, and relevant
backlog files.

**End state:**

- Exactly one user-confirmed single-target carrier selects
  `ice_target_encasement` through `VFX_PROFILE`.
- No damage, radius, range, status, element, cost, targeting, or description is
  changed merely to accommodate the visual.
- The catalog declares action-hold fraction and maximum live count from the
  profile. The queue holds through the completed-statue read and initial break,
  while the tail may safely outlive the queue slot.
- Missing target visuals, zero-hit casts, and target defeat before delayed
  playback remain safe and visually understandable.
- Documentation distinguishes target-bound encasement from area storms and
  records how future target-bound profiles consume cast context without adapter
  branches.
- Backlogs are reconciled: remove work completed by this cycle, add only durable
  unresolved issues discovered during implementation, and do not cite this
  plan's transitory item labels.

**Risk:** attaching the profile to an area or multi-target carrier would multiply
shell budgets and change the intended visual language; changing gameplay data
to make a candidate fit would silently expand scope. Refuse both and stop if the
confirmed carrier is not truly single-target under the live resolver.

**Adds to final validation coverage:** the real spell selects the correct
profile with unchanged gameplay semantics, queue pacing reaches the shell hold,
and fallback paths do not wedge presentation.

**Resolution target:** implemented; pending end-of-plan validation. Use only
integrity checks and any narrow catalog/load probe necessary for safe handoff.
Do not launch the battle.

### STATUE-7 — Recompose the shell and author transparent-cyan PS1 ice

**Model:** Opus 5 / GPT Sol

**Depends on:** STATUE-3 through STATUE-6 and the resolved fidelity direction.

**Files:** `src/presentation/effects/IceTargetEncasementEffect.gd`,
`src/presentation/effects/IceTargetEncasementProfile.gd`,
`src/presentation/effects/IceChunkMeshFactory.gd`,
`assets/shaders/effects/ice_target_encasement.gdshader`, an effect-owned second
pass shader only if one material cannot preserve both sorting and bright
overlap, `docs/VFX_DESIGN.md`, and the relevant backlog files.

**End state:**

- The held statue is deliberately asymmetric and built around 9–12
  screen-readable forms with clear size hierarchy: broad lower/front slabs,
  uneven side blocks, a diagonal caster-facing plate, rear silhouette masses,
  and an irregular cap. Small pieces support those forms rather than creating a
  regular 2×2 cage.
- The central target silhouette is substantially obscured during the hold while
  recognizable extremities may remain visible. The enclosure reads as a heavy
  pile-up of ice, not a crown, flower, collar, or tidy faceted egg.
- Main faces are transparent cyan. Overlapping central faces approach
  white-cyan, and darker blue faces/edges keep adjacent pieces countable. The
  look uses authored alpha or retro dithering rather than refraction, smooth
  physically based glass, or full-screen distortion.
- Transparency remains stable through front-quarter, side, and rear-quarter
  views. Explicit depth/render groups or a restrained solid underlayer prevent
  rear faces from incorrectly drawing over front faces.
- The internal core remains optional and cannot be required for the shell to
  read. With the core hidden, the material still looks icy, cyan, translucent,
  and volumetric.
- All palette, opacity, dither, emission, chunk-count, placement, and size-class
  values live as labelled profile parameters. Existing shared VFX materials and
  textures remain unchanged.

**Risk:** ordinary alpha blending can collapse overlapping geometry into a
sorting-error cloud, while excessive transparency makes the enclosure vanish
against bright terrain. Solve silhouette and ordering at the retro viewport's
native resolution, using an effect-owned underlayer or dither only when the
proof frames demonstrate the need.

**Proof checkpoint:** capture core-disabled hold frames for standard, wide, and
tall bodies at front-quarter, side, and rear-quarter angles, plus matched retro
on/off frames. At retro resolution the effect must retain a transparent cyan
read, stable front/rear ordering, substantial target enclosure, and 9–12
countable dominant shapes.

**Adds to final validation coverage:** transparent-cyan material fidelity,
asymmetric PS1-scale silhouette, body-bound fit, overlap brightness, sorting
stability, core independence, and owned-resource isolation.

**Resolution target:** implemented; pending end-of-plan validation. Run the
debug capture checkpoint, focused diff inspection, and `git diff --check`; use
only the narrow import/load probe necessary to hand usable shaders to the next
item. Do not launch a battle.

### STATUE-8 — Replace the thrown trail with terrain-anchored ice propagation

**Model:** Opus 5 / GPT Sol

**Depends on:** STATUE-7.

**Files:** `IceTargetEncasementEffect.gd`,
`IceTargetEncasementProfile.gd`, `IceChunkMeshFactory.gd` if a dedicated spike
mesh is needed, the effect-owned shader set,
`src/presentation/effects/VfxCastContext.gd`,
`src/presentation/GodotVisualAdapter.gd`, `src/presentation/VisualAction.gd`
only as needed to snapshot an optional generic presentation-surface path,
`docs/ARCHITECTURE.md`, `docs/VFX_DESIGN.md`, and the relevant backlog files.

**End state:**

- The former airborne/dotted delivery segments are removed. Eight to twelve
  irregular ice spikes occupy fixed terrain positions from caster to target;
  no spike translates through the air.
- Spikes emerge sequentially by deterministic height/width growth so the wave
  visibly advances along the ground. Older spikes shrink, dim, or recede behind
  the head without making the path disappear before its direction reads.
- The path derives from event-time caster and target positions, adapts its
  spacing/count within the asserted cap, and remains truthful at the spell's
  range 1–5. Spike bases follow the presentation terrain surface when the path
  crosses elevation changes; the effect must define and document the fallback
  for a missing surface sample rather than floating or tunnelling silently.
- If intermediate terrain heights are not already available at playback, the
  adapter snapshots an optional generic world-space surface path into the typed
  presentation context before the action is queued. Simulation events remain
  free of meshes, physics queries, and VFX-specific data; no adapter branch may
  name Ice Statue or `ice_target_encasement`.
- The final spike reaches the target's caster-facing lower bound and triggers
  the first cocoon slab. A short overlapping frost bed or joined spike bases may
  visually connect the wave, but no projectile head, floating lance, or dotted
  targeting line remains.
- `delivery_trail` remains independently isolatable, deterministic under seed
  and normalized time, and subordinate in node/instance/draw budget.

**Risk:** a line sampled only between two world positions can cut through steps
or float over terrain, while querying the scene lazily at playback can violate
the event-time snapshot contract. Snapshot any required presentation surface
path generically before queueing, and use fewer overlapping wide spike bases so
the retro image does not become another dotted line.

**Proof checkpoint:** capture a tight trail-only sheet at the harness's minimum,
middle, and maximum supported source separations, including an elevated route,
with enough frames to see every advance. Do not violate the confirmed opposing
islands or their empty middle corridor merely to imitate grid range numerically.
Every visible spike must stay planted; the sequence must read as ice travelling
through the ground rather than geometry being thrown.

**Adds to final validation coverage:** source-to-target direction, range-scaled
spacing, event-time surface-path ownership, terrain anchoring, elevation
behavior, deterministic sequential growth, removal of the old projectile read,
and supporting-instance budgets.

**Resolution target:** implemented; pending end-of-plan validation. Run the
debug capture checkpoint and cheap integrity checks only. Do not launch a
battle.

### STATUE-9 — Erupt the cocoon from the arriving ground wave

**Model:** Opus 5 / GPT Sol

**Depends on:** STATUE-7 and STATUE-8.

**Files:** `IceTargetEncasementEffect.gd`,
`IceTargetEncasementProfile.gd`, its effect-owned shader(s),
`docs/VFX_DESIGN.md`, and the relevant backlog files.

**End state:**

- The target enclosure begins at the last ground spike's contact point. A broad
  caster-facing lower slab erupts first, uneven lateral blocks climb next, and
  rear/top pieces close last. Pieces no longer scale outward independently from
  a common target-centre origin.
- Each piece has a deterministic eruption origin, start delay, rise direction,
  overshoot, and settle transform derived from its authored spatial role. The
  first eruption overlaps the trail head so delivery and enclosure are one
  continuous material event.
- A brief white-cyan overlap pulse and the blue-purple square accents mark
  contact near the lower impact region. Squares remain fixed-size/readable in
  the retro view, cluster around contact rather than orbiting the whole body,
  and clear before the completed hold.
- Formation timing is reallocated without making the famously quick attack
  sluggish: propagation is legible, enclosure snaps shut decisively, and the
  completed statue still owns a readable hold before fracture.
- Forward/backward seek across trail-to-eruption boundaries is exact; no layer
  pops, double-arrives, or samples RNG after construction.

**Risk:** changing two previously independent phase systems can produce a
one-frame gap, duplicated impact flash, or discontinuity under backward seek.
Drive both from one normalized timeline and prove the boundary with tightly
spaced frames before proceeding to fracture work.

**Proof checkpoint:** capture a full-composite tight sheet covering empty path,
early/middle/final spike, first lower slab, lateral climb, cap closure, and hold.
Add a contact-only capture proving the blue-purple squares remain visible but
do not replace the erupting geometry.

**Adds to final validation coverage:** continuous material flow from ground
spikes into cocoon, directional bottom-up formation, asymmetric closure,
contact-square readability, impact flash hierarchy, phase continuity, and
exact seek at the delivery/formation boundary.

**Resolution target:** implemented; pending end-of-plan validation. Run the
debug proof checkpoint, focused diff inspection, and `git diff --check`; no
full battle.

### STATUE-10 — Give the same shell pieces natural deterministic fracture motion

**Model:** Opus 5 / GPT Sol

**Depends on:** STATUE-7 and STATUE-9.

**Files:** `IceTargetEncasementEffect.gd`,
`IceTargetEncasementProfile.gd`, its shader(s), `docs/VFX_DESIGN.md`, and the
relevant backlog files.

**End state:**

- The same instances visible in the held cocoon remain the breaking instances;
  no replacement debris burst hides an identity swap.
- Each chunk stores seeded initial linear velocity, gravity response, angular
  velocity/axis, and any authored drag/fade data. Its transform is evaluated as
  a pure function of normalized fracture time—analytic ballistic motion, not a
  physics body, accumulated integration, or interpolation to a uniformly
  lifted endpoint.
- Four to six large hero chunks take distinct readable trajectories: strong
  lateral left/right motion, at least one high arc, and at least one lower or
  forward departure. Smaller pieces accelerate and spin faster; larger slabs
  feel heavier and rotate more slowly.
- Departure timing and impulse vary slightly by role. The silhouette opens from
  the impact fracture rather than becoming a synchronized radial crown. Gravity
  bends paths naturally, and fragments clear or fade before an unimplemented
  collision response would become conspicuous.
- `seek_normalized()`, backward scrub, repeated seeds, speed scaling, pause,
  and `skip_to_settle()` reproduce the exact same ballistic transforms.

**Risk:** natural-looking motion can tempt frame-state integration or rigid
bodies, breaking deterministic seek and replay. Derive every position and
rotation analytically from stored authored/seeded data and verify the same time
out of order, not only in forward playback.

**Proof checkpoint:** capture a shell-only sheet at 0.02–0.04 normalized-time
steps from held statue through initial separation, plus a wider breakup sheet.
Track the four to six hero chunks across frames, then repeat selected timestamps
out of order and compare hashes. Reject a uniform halo, crown, constant-speed
lerp, synchronized departure, or implausibly fast large-slab spin.

**Adds to final validation coverage:** same-piece continuity, analytic gravity
arcs, directional and size-dependent motion, staggered fracture, deterministic
out-of-order seek, skip behavior, and readable hero-fragment cleanup.

**Resolution target:** implemented; pending end-of-plan validation. Run the
debug proof checkpoint and cheap integrity checks only. Do not launch a battle.

### STATUE-11 — Consolidated final visual, lifecycle, and battle validation

**Model:** Opus 5 / GPT Sol

**Depends on:** all implementation items, including STATUE-7 through
STATUE-10, and every resolved blocking gate.

**Files:** fixes to task-owned files if validation finds defects,
`implementation_plan.md` resolution notes during validation, owning docs and
backlogs if verified truth changes, followed by the required plan-file cleanup.

This is the only item that performs full gameplay and integration validation.
Consolidate the following rather than replaying them after each implementation
item:

1. Run Godot's headless import/parse gate so every changed `.gd`/`.gdshader`
   and generated `.uid` is known to the editor, then load `VFXDebugScene` and
   `Battle25D` cleanly.
2. At one fixed seed, capture the matched reference-phase sequence: empty
   ground, early/middle/final spike, first eruption, lateral climb, completed
   transparent-cyan cocoon, hold, fracture, wide hero-chunk separation, and
   cleanup. Judge at native retro resolution, not only in enlarged frames.
3. For standard, wide, and tall targets, capture core-disabled shell-only
   front-quarter, side, and rear-quarter views with retro on and off. Confirm
   transparent cyan faces, bright overlap, stable sorting, asymmetric
   full-body enclosure, countable hero slabs, and no egg/crown/collar read.
4. Capture trail-only at the harness's minimum, middle, and maximum supported
   source separations, including an elevated route. Preserve its confirmed
   opposing-island composition and empty middle corridor. Confirm every spike
   remains terrain-anchored, its sequential growth reads from caster to target,
   and the last spike joins the bottom-up cocoon eruption without a floating
   projectile or discontinuity.
5. Capture contact-only and tight fracture sheets. Confirm blue-purple squares
   remain readable at the lower impact point, then track four to six original
   hero chunks through distinct gravity-bent trajectories without a uniform
   upward halo. Repeat fracture timestamps out of order at the same seed and
   compare deterministic output.
6. Exercise play, pause, resume, 0.5x and 2x speed, forward and backward scrub,
   settle skip from propagation, formation, hold, and fracture, overlap to the
   live cap, oldest-effect disposal, retrigger, app/battle exit, and repeated
   seeded playback. Confirm no target pose/tint/material state survives an exit.
7. Launch the real game and have Snowzilla cast Ice Statue against at least two
   visibly different target bodies, at short and long legal range, and across
   an elevated terrain case. Confirm event-time placement, terrain-anchored
   delivery, shell fit, transparent-cyan readability through CRT, damage-number
   separation, queue pacing, defeat interaction, and unchanged gameplay
   results. No yellow ring is introduced by this cycle.
8. Re-run existing Ice Storm, Fire Storm, Magenta Reduction, and generic aura
   debug captures to catch shared texture/material/context regressions. Exercise
   at least one multi-target area cast to prove the target-bound changes did not
   disturb established area VFX.
9. Read live node, instance/particle, draw-call, and overlap figures from the
   effect/harness and confirm every asserted profile ceiling. Reconcile both
   backlogs, inspect the final focused diff, and run `git diff --check` before
   staging only task-owned files.

If validation finds a defect, fix it in this session and rerun the smallest
consolidated subset that covers the fix; do not reopen prior items merely to
repeat the same checks.

**Risk:** a debug-perfect material can disappear against live terrain,
ground-spike placement can diverge from the battle surface, transparent sorting
can fail on real models, natural fracture can lose determinism under lifecycle
controls, or queue pacing can release before the statue reads. Only the real
battle pass can close those combined risks.

**Completion rule:** record the actual visual and manual evidence, mark every
covered implementation item done, reconcile both backlogs, and commit the final
validation result. Then, in the same session, grep the repository for
`STATUE-1` through `STATUE-11`, rewrite any accidental persistent reference as
a durable description, and clear `implementation_plan.md` completely in a
follow-up lifecycle-cleanup commit. The completed plan remains recoverable from
Git history; do not leave its resolution log in the working contract.

## 6. Deliberately not doing

- No ripped Digimon World models, textures, code, or proprietary assets.
- No dynamic fluid ice, rigid-body fracture, collision debris, or random
  physics.
- No shell made primarily from camera-facing sprites.
- No replacement or redesign of the existing Ice Storm profile.
- No yellow rings and no changes to damage-number ownership or styling.
- No gameplay stun/status/balance change inferred from a presentation
  reference.
- No per-monster placement tables or spell-name branches in the adapter.
- No general storm-profile resource refactor; this target-bound structure is
  not a storm and does not prove that abstraction.
- No broad shared hit-confirm framework until another effect demonstrates the
  same contact-accent structure.

## 7. Resolution notes

### Target-bound cast context transport

Implemented 2026-08-11; pending end-of-plan validation.

- `spell_cast_started` now carries ordered resolved target identities alongside
  its existing live footprint, without importing presentation data into the
  simulation layer.
- `VisualAction` snapshots source and impact world positions, target identities,
  target positions, and body-only local bounds before delayed playback.
- Every `VfxPlayback` receives the same typed `VfxCastContext` through a default
  no-op method before `play()`. Existing optional `setFootprint` delivery is
  unchanged.
- Missing target visuals use the standard authored body box at the event impact.
- Architecture and VFX contracts were updated. Both backlogs were reviewed;
  the long-term radius entry now distinguishes stable target identities from
  still-open exact affected-tile transport, and no critical backlog change was
  warranted.
- Focused diff inspection and `git diff --check` passed. Godot 4.4 completed a
  headless editor import and a five-frame project load with the compatibility
  renderer and dummy audio. No battle was launched, as required for this item.

### Target-context VFX harness

Implemented 2026-08-11; pending end-of-plan validation.

- The debug scene now has explicit caster and target anchors. It creates each
  playback context through the same `VfxCastContext.create()` factory used by
  `GodotVisualAdapter`.
- Standard, short/wide, and tall/narrow target-bound presets, source distance,
  and camera yaw are available through both the HUD and CLI. The status panel
  reports those values with profile, seed, normalized time, node/particle
  totals, and a draw-call estimate.
- Target-bound captures retain the existing phase-sheet, golden, layer, and
  retro-render paths. The retro viewport now starts enabled.
- Captured the standard, wide, and tall guide states plus side and rear-quarter
  views through the retro renderer. The final tall side-view capture also
  verified the shared factory after the focused cleanup.
- `git diff --check` and the Godot editor import passed. Relevant backlogs were
  reviewed; this harness work leaves no durable unresolved item to add. No
  battle was launched, as required for this item.

### Low-poly target encasement shell

Implemented 2026-08-11; pending end-of-plan validation.

- The target-bound profile builds 15 deterministic, thick 3D chunks from block,
  wedge, and irregular-crystal meshes. Named rear, side, front, and cap layers
  fit the supplied body bounds; the restrained core remains independently
  toggleable.
- Every chunk records its intact and outward broken transforms at construction.
  The shell uses opaque faceted blue-white materials and explicit layer render
  priorities. It is registered in the debug catalog only; spell data is
  unchanged.
- Build assertions enforce the authored count and ceilings. The measured build
  uses 15 chunks, no more than 19 effect nodes, and 13 draw calls.
- Shell-only retro captures passed for standard front-quarter, side, and
  rear-quarter views and for short/wide and tall/narrow front-quarter targets.
  The geometry visibly retained thickness, parallax, enclosure, and readable
  seams without relying on the core.
- Repeating the standard capture at seed 7 produced the same SHA-256 hash,
  confirming deterministic placement. Godot's headless editor import and
  `git diff --check` passed. Relevant backlogs were reviewed and require no
  durable change. No battle was launched, as required for this item.

### Encasement formation, hold, and same-piece fracture

Implemented 2026-08-11; pending end-of-plan validation.

- Named normalized-time windows now cover arrival, rear/lower and side growth,
  front/cap closure, completed hold, fracture impulse, outward tumble, and
  settle. Every frame is recomputed from time; no physics, global shader time,
  or random sampling occurs after shell construction.
- Each original chunk owns one stable MultiMesh slot. Formation interpolates
  from its compressed body-adjacent transform to its intact transform; breakup
  sends that same slot toward its stored broken transform with deterministic
  stepped rotation. The core grows and collapses independently.
- `seek_normalized()` applies the same pure timeline forward or backward, and
  `skip_to_settle()` targets normalized time 0.92 where all large chunks are
  already visibly separated. A repeated seed-7 hold capture at 0.49 produced
  the exact prior SHA-256 hash
  `42152F11ED6B4AB54F9F2ABD618D88F2DAF93406CE99383F9B3A949FEF630B15`.
- The current typed context exposes no mutable target visual, so no pose/tint
  lease was added. The effect remains readable without target treatment and
  does not gain an unsafe dependency on arbitrary model materials.
- Shell-only retro proof sheets passed: an eight-frame sequence covers empty,
  first growth, side closure, completed statue, hold, initial separation, wide
  breakup, and settle; a seven-frame tight fracture sequence preserves
  countable large-piece continuity. All capture markers reported `error=0` and
  stderr was empty.
- Godot 4.4's headless editor import and `git diff --check` passed. Relevant
  backlogs were reviewed and require no durable change. No battle was launched,
  as required for this item.

### Subordinate delivery and contact cues

Implemented 2026-08-11; pending end-of-plan validation.

- `delivery_trail` uses seven tapered low-poly segments whose head travels from
  the cast context's source position to the target body center exactly once.
  The frozen taper fades during first shell growth and is gone by normalized
  time 0.20.
- `contact_accents` uses eight deterministic deep-blue square prisms in one
  MultiMesh. Their staggered scale/motion envelope briefly distributes them
  around the impact volume without resembling the large shell chunks.
- `impact_flash` is a separate low-alpha, depth-independent internal sphere
  synchronized with first growth. It was kept small enough to tint the impact
  volume rather than replace the shell.
- An attempted standard billboard material was rejected during proof because
  Godot replaced the per-instance basis and ignored the MultiMesh scale used to
  hide each square. Scale-safe thin prisms fixed the lifecycle; the durable
  guardrail is recorded in `docs/VFX_DESIGN.md`.
- Trail-only and contact-only sheets, a flash isolation capture, and the
  full-composite sheet passed through the retro path with every capture marker
  reporting `error=0` and empty stderr. The completed composite hold is
  byte-identical to the prior shell-only hold, proving the supporting layers
  clear before the statue owns the frame.
- The HUD measured 25 nodes, 31 allocated geometry instances, zero particles,
  and an approximately 16-draw peak when core and supporting layers overlap.
  Seven trail plus eight contact instances remain under the asserted combined
  ceiling of 16.
- Godot 4.4's headless editor import and `git diff --check` passed. Relevant
  backlogs were reviewed and require no durable change. No battle was launched,
  as required for this item.

### Ice Statue production registration

Implemented 2026-08-11; pending end-of-plan validation.

- At the user's explicit direction, `Ice Statue` was added as a new
  single-target copy of Ice Punch. It retains Ice Punch's damage 3, ice element,
  radius 1, empty-target behavior, and height constraint; its authored minimum
  range is 1 and maximum range is 5.
- `VFX_PROFILE: "ice_target_encasement"` assigns the completed target-bound
  effect without a spell-name branch. Ice Punch is unchanged and Ice Plow keeps
  `ice_area_storm`.
- PowerShell JSON parsing found 61 entries with 61 unique names and exactly one
  Ice Statue entry carrying the requested normalized fields. Godot 4.4's
  headless editor import completed successfully, and `git diff --check` passed.
- At the user's direction, Snowzilla now owns Ice Statue immediately after Ice
  Punch in its existing Ice set. The temporary critical-backlog ownership entry
  was removed; no other monster or spell set changed.
- JSON integrity checks found exactly one Snowzilla, exactly one Ice Statue in
  its set, unique spell names, and no unresolved owned spell name. Godot 4.4's
  editor import passed after the ownership change.
- No unrelated gameplay fields changed, and no battle was launched, as required
  for this item.

### Debug anchor terrain centering correction

Implemented 2026-08-11; pending end-of-plan validation.

- The caster and target anchors now each own a terrain support tile whose top
  surface is exactly at anchor-local y=0. Model bases and body proxies therefore
  share the support tile's horizontal centre and correct surface height.
- The fixed terrain sample grid omits the centre travel row, preventing a
  movable caster support from overlapping or appearing to belong to an adjacent
  sample when source distance changes.
- Retro captures passed at default distance 4 and at fractional distance 3.25
  with a 90-degree camera yaw. Both proxies remained centred on their own
  supports; all capture markers reported `error=0` and stderr was empty.
- Godot 4.4's editor import and `git diff --check` passed. No battle was
  launched; this is a debug-harness correctness fix ahead of consolidated
  validation.

### Opposing debug-island layout restoration

Implemented 2026-08-11; pending end-of-plan validation.

- The single support-tile correction was visually rejected by the user because
  it destroyed the established two-island composition. It was replaced rather
  than carried into final validation.
- The harness again builds the exact original terrain arrangement: a flat 3×3
  green island centred at x=-2, an uneven 3×3 blue island centred at x=+2 with
  its centre at terrain height 2, and the x=0 corridor empty. The caster and
  target capsule proxies occupy those respective centres; the target capsule
  scales to preserve the selectable body-bound presets.
- Source separation now moves both complete islands symmetrically. Its minimum
  is 4 world units so the two 3×3 footprints cannot close the middle corridor.
- Godot 4.4's editor import passed. A retro Magenta Reduction capture at the
  original distance 4 reproduced the opposing-island composition with both
  proxies on their centre cells and no terrain in the middle corridor; its
  capture marker reported `error=0` and stderr was empty.
- `git diff --check` passed. No battle was launched before consolidated
  validation.
