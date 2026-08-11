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
large ice blocks and shards that grows around the target, holds as an enclosing
mass, and then breaks apart using those same visible pieces**.

The caster-to-target trail and blue square contact accents are supporting
layers. They must never become the effect's dominant read. Damage numbers stay
owned by the existing damage-number presentation, and the yellow rings in the
reference are explicitly out of scope.

The finished effect must:

- travel from the caster to the impact point;
- envelope the target from behind, both sides, in front, and above with real
  low-poly geometry that has visible depth and parallax;
- close the visual gaps with a restrained bright internal ice core without
  using that core to fake the shell;
- hold long enough for the completed enclosure to read;
- move the same shell pieces into deterministic outward breakup trajectories;
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

### Carrier spell — blocking only registration and battle validation

No carrier is inferred from a spell name. The catalog currently offers
`Ice Punch` and `Ice Plume` as possible existing candidates, while `Ice Plow`
already owns the area-storm profile and must not be repurposed. Creating a new
spell named after the reference would be a content, lore, and balance decision
outside this plan's authority.

The user must choose one of these before the registration item begins:

1. assign `ice_target_encasement` to an existing confirmed single-target spell;
2. identify a different existing carrier; or
3. explicitly commission a separate spell-data/design cycle.

The context transport, debug harness, geometry, and choreography can be built
and judged before this choice. Registration and final in-battle validation
cannot.

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
trajectories give exact scrub/replay behavior, make the break art-directable,
and match the authored character of the reference.

### Fit the creature body, not the tile or model base

`GodotVisualAdapter` already accumulates mesh bounds for picking and status
placement. The new context path reuses that capability but measures the creature
body only: model bases, selection collision, status icons, and other
presentation helpers do not enlarge the shell. The effect receives a body-local
bounding box plus event-time source and impact positions.

Placement is normalized against that box so one authored layout can surround a
short/wide, standard, or tall/narrow body without inventing per-monster branches.

### Prefer faceted solidity over modern glass

Most ice faces are opaque or nearly opaque, unshaded or flat-shaded, and use a
small cold palette. A few overlay faces and the internal core may use additive
or mixed transparency. Front/rear render groups are explicit so transparent
sorting cannot randomly place the back of the statue over its front.

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

The profile owns and asserts its limits. Initial ceilings for one effect are:

- 16 large enclosing pieces, with up to 24 only if the proof sheet shows a
  measured silhouette gap that cannot be fixed by placement;
- 96 small trail/contact particles or instances;
- 14 estimated draw calls;
- 20 effect-owned nodes;
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

**Depends on:** STATUE-1, STATUE-4, STATUE-5, and the carrier-spell user
decision. **Blocking until that decision is recorded.**

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

### STATUE-7 — Consolidated final visual, lifecycle, and battle validation

**Model:** Opus 5 / GPT Sol

**Depends on:** all implementation items and both blocking gates.

**Files:** fixes to task-owned files if validation finds defects,
`implementation_plan.md` resolution notes during validation, owning docs and
backlogs if verified truth changes, followed by the required plan-file cleanup.

This is the only item that performs full gameplay and integration validation.
Consolidate the following rather than replaying them after each implementation
item:

1. Run Godot's headless import/parse gate so every new `.gd`/`.gdshader` and
   generated `.uid` is known to the editor, then load `VFXDebugScene` and
   `Battle25D` cleanly.
2. In the debug harness, capture the named phase sheet at a fixed seed for
   standard, wide, and tall targets. Capture shell-only front-quarter, side,
   and rear-quarter views with core/trail/contact hidden. Confirm visible
   thickness, parallax, full-body enclosure, and stable front/rear ordering.
3. Capture trail-only, contact-only, break-only, and full-composite sheets.
   Confirm the trail reaches the target, squares mark contact, the closed statue
   dominates the composite, and the same countable large pieces move from shell
   to breakup.
4. Exercise play, pause, resume, 0.5x and 2x speed, forward and backward scrub,
   settle skip from formation and hold, overlap to the live cap, oldest-effect
   disposal, retrigger, app/battle exit, and repeated seeded playback. Confirm
   no target pose/tint lease survives any exit.
5. Launch the real game and cast the confirmed carrier in a live battle against
   at least two visibly different target bodies and across an elevated terrain
   case. Confirm event-time source/target placement, shell fit, damage-number
   separation, queue pacing, camera/CRT composition, defeat interaction, and
   unchanged gameplay results. No yellow ring is introduced by this cycle.
6. Re-run existing Ice Storm, Fire Storm, Magenta Reduction, and generic aura
   debug captures to catch shared texture/material/context regressions. Exercise
   at least one multi-target area cast to prove the expanded event contract did
   not disturb established area VFX.
7. Read live node, instance/particle, draw-call, and overlap figures from the
   effect/harness and confirm every asserted profile ceiling. Inspect the final
   focused diff and run `git diff --check` before staging only task-owned files.

If validation finds a defect, fix it in this session and rerun the smallest
consolidated subset that covers the fix; do not reopen prior items merely to
repeat the same checks.

**Risk:** a debug-perfect shell can still miss a moving or unusually sized live
monster, leak reversible target state, or release the visual queue before the
statue reads. Only the real-battle pass can close those risks.

**Completion rule:** record the actual visual and manual evidence, mark every
covered implementation item done, reconcile both backlogs, and commit the final
validation result. Then, in the same session, grep the repository for
`STATUE-1` through `STATUE-7`, rewrite any accidental persistent reference as a
durable description, and clear `implementation_plan.md` completely in a
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
