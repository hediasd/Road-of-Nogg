# Hex battle migration

Prepared 2026-09-07. **Queued; execution has not started.** This cycle makes hex
battle the active product, preserves the square battle as a frozen runnable
reference, and establishes commander/party activation before the first playable
hex scene. Forsena is the principal reference for rules, style, and layout;
other games supply candidates, not automatic requirements. The world-map hex
authoring cycle continues independently. This file may be refined before
execution; once execution starts it is frozen and findings live in item commits.

## Opening and decision gates

- Do not open a second cycle while `worldmap-hex-authoring` is active. This
  queued document can be committed on the currently checked-out branch under
  the window rule; authoring it does not open its execution cycle.
- After the active cycle closes, and the user declares the tree quiet, open
  `plan/hex-battle-migration`. Follow AGENTS.md's branch audit and wave pushes.
  Reconcile this plan against the editor's then-current source **before the
  first item executes**, especially terrain, objects, bridges, and export.
- The user approved the initial battle rules and standalone square-reference
  scope on 2026-09-07. HXB-1 is therefore a documentation specification rather
  than a product-decision gate; it records the approved contract before runtime
  work begins.
- Square preservation means a frozen, independently runnable reference outside
  the active product path. Hex battle becomes the sole maintained battle model.
  Re-author the plan before execution if that preservation scope changes; an
  in-project square/hex toggle has a materially different dependency and
  regression budget.
- Product choices that remain within the boundaries below are recorded in
  GAME_DESIGN.md by HXB-1, not by editing this frozen plan. A requested expansion
  beyond them requires a separately scoped follow-on cycle; no executing item
  may invent additional owned paths or promise unsupported rules.

## Approved initial battle rules

These decisions are the target contract for HXB-1 and all dependent items. They
are approved product choices, not claims about the current implementation.
Forsena supplies the main reference: Rune Knights lead troops, troops act as
groups, battles use hexes, and commander defeat or retreat drives battle outcome.
Runersia confirms the series-level platoon, terrain, and zone-of-control ideas.
See the [Forsena manual](https://www.videogamemanual.com/ps1/Brigandine%20-%20The%20Legend%20of%20Forsena%20%28USA%29.pdf)
and [Runersia game-system reference](https://brigandine.happinet-games.com/gamesystem/?lang=en).
The exact rules below are Road of Nogg decisions where the references leave room
for interpretation.

- A round gives each surviving party one activation. At round start, order
  parties by commander level descending, effective commander speed descending,
  then deterministic party ID ascending. Rebuild that queue only at the next
  round unless battle termination makes the remainder irrelevant.
- A party has exactly one commander and a deterministic identity. Initial test
  scenarios may designate existing monsters as commanders; this cycle does not
  invent commander characters, names, classes, or artwork.
- During a player party activation, the player chooses any living, eligible,
  unspent member in any order. CPU parties choose dynamically through the same
  canonical eligibility and command APIs. Every eligible member receives at
  most one turn in that party activation.
- Wait consumes that member's turn. End Party converts all remaining eligible
  member turns into waits in deterministic member-ID order. Dead or withdrawn
  members receive no turn and no timing tick.
- A member may move then act or act then move where the chosen command permits
  it. Casting after movement is allowed unless spell data says otherwise. Move
  undo is available only before an action and before any irreversible reaction
  or effect has occurred.
- Status durations, cooldowns, and end-turn passives advance once when that
  member acts, waits, is skipped, or is consumed by End Party. Mid-activation
  effects use the same rule and cannot tick another member merely because they
  share a party. Victory is checked after each fully resolved command/timing
  step and before another member is selected.
- Commander defeat forces the surviving party members to withdraw; it does not
  kill them. Ordinary member defeat does not end the party. A team loses when
  all of its commanders are defeated or withdrawn. If one fully resolved effect
  removes every team's last commander simultaneously, the battle is a draw.
- The initial board allows one unit per valid hex. Occupied cells block stopping
  and passage. All initial traversable terrain costs one movement point; blocked
  terrain and integer elevation/jump limits still use a weighted traversal
  contract so later terrain rules do not require new pathfinding.
- Zone of control ships in the first playable battle: entering a hex adjacent
  to a living hostile unit ends the mover's movement. Enclosure bonuses, allied
  pass-through, flying/aquatic traversal, and terrain defence/evasion remain
  later systems.
- Spell range uses hex distance. Circle becomes a hex disc; minimum range makes
  it a ring. Cross becomes the center plus six axial rays. Line follows the
  selected axial direction and excludes the caster. Self/passive radial effects
  use a hex disc. Existing shapes receive an explicit supported mapping or a
  loud unsupported result rather than silently retaining square geometry.
- Line of sight is symmetric supercover. Intervening cells touched by the line
  block it; source and target cells do not. A line exactly on an edge or vertex
  includes every touched intervening cell, choosing conservative deterministic
  blocking over angle-dependent gaps.
- Presentation keeps the retro 2.5D direction and uses an oblique, flat-top hex
  battlefield. Mouse remains the primary pointer, while keyboard/gamepad input
  must reach all six neighbours under the camera transform. Party/member state
  replaces the individual speed portrait rail.
- Free member order means ordinary member speed no longer schedules turns.
  Commander speed remains a party-order tiebreaker. A later balance cycle may
  redefine ordinary-member speed for accuracy/evasion or another approved use;
  this migration does not invent that balance rule.
- Voluntary retreat, command radius penalties, enclosure bonuses, capture,
  resurrection, turn limits, reinforcements, campaign consequences, and new
  victory objectives remain optional follow-on systems.

## Outcome

1. The square baseline opens independently in Godot 4.4 with its own code,
   catalogs, scenes, and visual resources. A tag, package manifest, and launch
   instructions identify exactly what was preserved. Hex changes cannot modify
   its dependencies.
2. The active engine remains `BattleSimulator` + `BattleState`; there is no
   permanent second simulator family or square/hex product toggle.
3. A real Player vs CPU and CPU vs CPU hex battle uses parties from setup through
   activation, member selection, commands, effect timing, outcomes, and replay.
4. An authored hex map supplies matching visual and headless tactical products.
   Simulation never imports editor or presentation classes.
5. Movement, melee, spells, passives, AI, previews, picking, and effects agree
   on hex coordinates and resolved footprints. Existing non-geometric combat
   systems remain usable, including Resonance, status effects, and reactions.
6. New battle scene, setup, documentation, console entry point, and exported
   application default to hex. Old square entry points have an explicit
   disposition; shared VFX/debug dependencies remain intact.

## Missing capabilities and scope

### Required for this migration

| Capability | Why required | Owner |
|---|---|---|
| Independent square baseline | Copying a scene does not freeze its controller, data, or effects | HXB-2 |
| Shared headless hex mathematics | Prevent parity bugs and a simulation-to-editor dependency | HXB-4 |
| Tactical map definition and valid-cell mask | A baked image does not describe legal cells or terrain rules | HXB-5 |
| Terrain cost/traversal contract | Reachability, validation, and AI must agree; support weighted costs without inventing a terrain balance table | HXB-5, HXB-7 |
| Hex adjacency, ranges, footprints, and LoS | Square algorithms are present throughout live execution and AI | HXB-7 |
| Party identities and activation lifecycle | User explicitly requires the intended activation model in the first playable | HXB-1, HXB-5, HXB-6 |
| Party member selection for player and CPU | Replacing a speed queue without choosing the next member is incomplete | HXB-6, HXB-8, HXB-12, HXB-13 |
| Defined timing and defeat semantics | Cooldowns, skips, durations, reactions, commander loss, and victory cannot inherit accidental square timing | HXB-1, HXB-6 |
| Versioned setup/state/replay | The same coordinate pair must never be reinterpreted under another topology or activation model | HXB-5, HXB-6 |
| Hex scene, picking, overlays, keyboard input, and camera | Replacing terrain meshes alone leaves square interaction | HXB-9, HXB-13 |
| Geometry-aware spell presentation | Existing storm profiles assume Manhattan diamonds and one-unit cells | HXB-11 |
| Tactical authoring and matching runtime export | Battle maps must be authored without making gameplay read the editor | HXB-10 |
| Focused reproducible regression probes | This cross-layer migration needs mathematical, state, and replay evidence beyond a plausible picture | HXB-3 and each implementing item |
| Runtime export resource inclusion | Existing export preset includes `data/*.json`; nested battle data and generated dependencies need explicit verification | HXB-14, HXB-V |

### Forsena fidelity candidates for later scope

These are potentially important to the intended game, but are deferred by the
approved initial contract. Deferring one does not declare it unwanted.

- Command radius and its consequences outside the radius; army capacity and
  monster recruitment/upkeep. Party membership is required now; a particular
  radius penalty or capacity economy is not yet approved.
- Enclosure bonuses, allied pass-through, flying/aquatic movement, and terrain
  defence/evasion. Zone of control itself is required for the first playable.
  The movement contract must distinguish traversal, stopping, costs, and
  movement termination so later rules can be added without replacing
  pathfinding; synthetic weighted fixtures are not production balance.
- Voluntary retreat, castle capture, turn limits, reinforcement, and strategic
  consequences. Commander-loss and battle-end behaviour are required now;
  a campaign and every victory mode are not.
- Wider armies, manual deployment, multiple defending/attacking forces, and
  scenario objectives beyond the initial approved outcome. Setup must not
  hardcode four members, but the first content set can be small.
- Full smooth-terrain tactical classification, bridge underpasses, stacked
  walkable surfaces, and detailed water rules. The exporter must refuse an
  unsupported tactical construction rather than flatten it silently.

### Optional future systems, excluded from this cycle

Campaign travel/encounters, diplomacy, network play, inventory/equipment,
recruitment/evolution economy, new lore or commander artwork, destructible
terrain, facing/back attacks, multi-cell monsters, elaborate projectile physics,
autotiling, terrain self-shadowing, a generic multi-topology framework, and a
repository-wide test framework. None is a condition for promoting the initial
hex battle. New content/balance is separately approved, not smuggled into a port.

## Present-state facts an executing agent must not "fix"

- At preparation, `WorldMapHexGrid.gd` is under
  `src/presentation/worldmap/editor/`. A review's claim that it already lives
  outside the editor package is incorrect. It uses odd-column offset storage
  and axial/cube mathematics; retain that convention.
- Editor hexes are flat-top with world width/height 2, column advance 1.5, row
  advance 2, and odd-column drop 1. Their visual regularity is calibrated to
  pitch 60. These are editor compatibility constants, not a battle distance
  formula or a reason to retune the shared camera.
- Editor brushes include hex primitives, but Rectangle and Stamp controller
  routes still use square operations. Newly saved PNG bakes also need an import
  before export. Recheck after the editor cycle; do not duplicate its work.
- Current export is a ground scene plus metadata, not per-cell tactical data.
  Tileset `WALKABLE` is authored metadata, not an implemented movement resolver.
- Square `temp2_authored` bake parity must survive shared geometry extraction.
  The square **world-map editor** path is distinct from retired square battle.
- The live battle uses Matrix layers in BattleState, not BattleBoard. No source
  callers were found for BattleBoard or ParabolicArc. Confirm reachability
  before retiring anything; do not port dead code just because it is square.
- Live CPU selection uses BattleCommandEvaluator/CommandDeliberation and brain
  weights. Older `_evaluateTile()` methods have no source callers at preparation.
- The two square battle scenes both use BattlePresentationController. Their
  `.tscn` files alone are not a backup.
- State/replay formats are currently version 5. The new format must be newer
  and explicitly identify hex/party semantics. Old files belong to the frozen
  runtime; they are not auto-converted by changing a version number.
- Mathematical footprint counts legitimately change: unobstructed inclusive
  square diamonds have 5/13/41 cells at radii 1/2/4; hex discs have 7/19/61.
  Do not restore the old counts, AI choices, or particle densities as a port fix.
- Source currently supports move-first and act-first phase execution, despite
  older design prose describing only move-first. HXB-1 must explicitly choose
  the target action-order policy rather than inherit stale prose.
- Move undo currently assumes movement causes no irreversible effects.
  Commander/party work cannot accidentally trigger turn-end twice or expire
  every member's statuses when one member acts.
- `docs/DEVELOPMENT.md` contains obsolete workflow text about plan Resolutions
  and deferring all checks. AGENTS.md governs: self-contained checks run in the
  item, plans are frozen, and evidence belongs in commit bodies. Retain the
  development document's Windows process safeguards.

## Architecture and ownership boundaries

Keep canonical headless modules in their existing directories. New board math
goes in `src/board/HexGrid.gd`; new typed data in `src/entities/` and loaders in
`src/factories/`. New hex battle presentation goes under
`src/presentation/battle/`, its scene lifecycle under `src/systems/hex_battle/`,
and its scenes under `scenes/battle/`. Existing shared theme, portrait, model,
render, and VFX helpers need not move merely to make the tree look symmetrical.

Authoring produces a visual scene and a headless map definition with matching
source fingerprints. A scenario binds the map to party rosters and deployment.
The headless definition owns gameplay; the scene owns appearance. Decorative
changes cannot silently alter tactical terrain. Each resource is loaded through
the appropriate factory boundary. Curvature is never tactical elevation.

Retain offset Vector2i coordinates and Matrix storage, with valid-cell membership
separate from rectangle bounds. Preserve the existing invalid-coordinate
sentinel; do not introduce negative axial coordinates into that public contract.
Only HexGrid converts between offset and axial/cube spaces.

Do not generalize or retune existing visual donors. New geometry-sensitive
effects use new owned scripts/profiles/shaders; unchanged effects may be reused
through their existing contracts. The final caller sweep renders donors and
every existing caller of a reused dependency. A broader shared visual contract
migration is not implicitly authorized by this plan.

## Verification convention

All new `.gd` paths below include ownership of their exact `.gd.uid` sidecar;
new `.tscn` resources must have distinct UIDs. Directory globs claim that entire
subtree, including sidecars. Generated captures/logs go to `builds/hex-battle/`
or a task temp directory, not into tracked diagnostics. Hand-authored fixtures
and reusable probes under `scripts/hex_battle/` are tracked by explicit path.

HXB-3 supplies the following bounded Windows command form, used literally by
later self-contained checks from the repository root:

```powershell
powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/hex_battle/probe_grid.gd -Marker HXB_GRID_OK
```

The runner waits for its own process, requires its marker and successful exit,
and fails on parse/runtime errors or timeout. No process-name-wide termination,
global import, editor scan, or game launch is hidden in a probe. Narrow headless
probes check the item's own logic against already-committed dependencies; they
do not constitute visual/gameplay acceptance. If registration is necessary,
schedule an explicit quiet-tree import boundary and inspect its effects.

Every item also reviews `git diff HEAD -- <owned paths>` and runs
`git diff --check -- <owned paths>`. Its commit records implementation,
assumptions found false, intentional exclusions, commands/results, and any
deferred check. End with `Plan-Item: HXB-N` (or HXB-V). Stage and commit explicit
paths only. Follow AGENTS.md for pushes at wave boundaries.

## Items

### HXB-1 — Record the battle rules and preservation contract

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** The user has approved every product decision. This item is
now a bounded two-file documentation update with an exact contract and literal
acceptance checklist; it contains no remaining design judgment.

**Depends on:** cycle-opening conditions; no implementation dependency.

**Touches:**
- `docs/GAME_DESIGN.md`
- `docs/ARCHITECTURE.md`

**End state:** `docs/GAME_DESIGN.md` records every rule in "Approved initial
battle rules" as the initial hex target, distinct from current square behaviour.
`docs/ARCHITECTURE.md` records the party/simulation/presentation ownership and
standalone square-reference boundary. Neither document presents planned work as
already implemented.

**Implementation:** Transcribe the approved contract above into the two owned
documents. Preserve its deterministic queue, free member selection, wait/end
semantics, commander withdrawal/outcome, action/undo rules, per-member clocks,
terrain/occupancy/ZOC, shape/LoS mappings, presentation target, speed consequence,
and explicit deferrals. Cite the Forsena manual and Runersia system page for
reference facts, while labeling Road of Nogg's exact mechanics as project rules.
Use target/current wording so the documentation remains truthful before runtime
items land.

Do not revisit these choices, add alternate rules, modify runtime code, or apply
new penalties/stat changes. Do not copy this cycle's item identifier into either
long-lived document. A later request for incompatible preservation scope requires
the queued cycle to be re-authored before execution begins.

**Risk:** A vague "party turns" label lets UI, AI, replay, and status clocks
implement different games.

**Validation:**
- Self-contained: run
  `rg -n "party|commander|withdraw|zone of control|supercover|square reference|target|planned" docs/GAME_DESIGN.md docs/ARCHITECTURE.md`
  and audit the matches against every bullet in "Approved initial battle rules".
  Confirm examples cover an ordering tie, Wait, End Party, commander loss,
  simultaneous last-commander defeat, and the final eligible member. Confirm both
  citations resolve, no mandatory decision says `TBD`, and planned rules are not
  described as implemented. No deferred check.

### HXB-2 — Preserve a runnable square reference

**Model:** Opus 5 / GPT Sol

**Model rationale:** Correct preservation requires discovering the runtime
dependency closure and choosing a reproducible baseline without capturing other
sessions' unfinished work or creating a second maintained engine.

**Depends on:** HXB-1.

**Touches:**
- `references/square-battle/**`
- `scripts/preserve_square_battle.ps1`

**End state:** A frozen package, dependency/hash manifest, and README recreate
the square project without referencing the active checkout. A non-overwritten
annotated tag identifies its source commit. No engine binary, cache, credentials,
or editor-only scratch output is packaged.

**Implementation:** Select the committed square baseline from source and prior
validation evidence. Do not package the live working tree. If a required runtime
dependency exists only as uncommitted work, name the exact dependency and wait
for its owner to commit it; do not absorb it under the preservation commit.
Use `references/square-battle/.gdignore` and an opaque `source.zip` to prevent
duplicate class registration. Include project settings, code, catalogs, scenes,
and the verified runtime resources; regenerate `.godot` on opening elsewhere.
Document exact Godot version, source SHA, package hash, and launch/replay steps.
Use tag `reference/square-battle-v1` if absent; verify rather than overwrite an
existing tag. Tag publication remains an explicit outward-facing action.

The script must reconstruct from the named Git commit with explicit runtime
paths and checked destinations. Extraction for acceptance uses a new isolated
directory under ignored `builds/square-reference/` with `.gdignore`; it is not a
Git worktree. Do not delete a pre-existing extraction directory or modify HEAD.
Preserve representative seed/setup/replay and effect configurations for HXB-V.
Record limitations of prior validation honestly. The package's final runnable
acceptance remains HXB-V; subsequent source mutations cannot change its bytes.

**Risk:** A package with active-project resource references looks archived but
still changes with hex work; missing generated resources can prevent opening.

**Validation:**
- Self-contained: reconstruct the package from its commit; verify manifest and
  hashes, every `res://` dependency, absence of credentials/caches, and no active
  absolute paths. Run branch-hygiene audit if any branch operation occurred;
  this item requires no branch switch.
- Deferred: HXB-V opens the extracted square project, completes a representative
  battle/replay, and renders the preserved visual reference independently.

### HXB-3 — Supply a bounded probe launcher

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** This is a specified Windows process wrapper with concrete
success/failure semantics; it introduces no gameplay or architecture decisions.

**Depends on:** HXB-1.

**Touches:**
- `scripts/hex_battle/run_probe.ps1`
- `scripts/hex_battle/probe_runner_ok.gd`
- `scripts/hex_battle/probe_runner_failure.gd`

**End state:** `run_probe.ps1` accepts mandatory string `Script`, mandatory string
`Marker`, optional string `GodotPath` defaulting to
`./Godot_v4.4-stable_win64.exe`, and integer `TimeoutSeconds` defaulting to 60.
It returns 0 only when the launched process exits 0, writes the exact marker as
a complete line, and produces no Godot parse/script error. All other outcomes
return nonzero and include paths to fresh captured logs.

**Implementation:** Mirror the waited-process safeguards in DEVELOPMENT.md and
LEARNINGS.md's "Bound native diagnostics". Run Godot with `--headless --path .
--script <Script>` using a process API with safe argument quoting, redirected
stdout/stderr drained without deadlock, and no visible window. Store logs in a
new task-temp directory. Reject nonexistent executables/scripts and nonpositive
timeouts. On timeout terminate only this process. Never run an import, mutate
project settings, scan all probes, or install a test framework. The success
fixture prints `HXB_RUNNER_OK` and exits 0; the failure fixture prints
`HXB_RUNNER_FAILURE` and exits 1.

**Risk:** A detached Windows process or stale log can report a false pass.

**Validation:**
- Self-contained: run `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/hex_battle/probe_runner_ok.gd -Marker HXB_RUNNER_OK` (expect 0);
  repeat with `-Marker INTENTIONALLY_ABSENT` (expect nonzero); run with
  `-Script res://scripts/hex_battle/probe_runner_failure.gd -Marker HXB_RUNNER_FAILURE`
  (expect nonzero). Inspect timeout cleanup and fresh-log handling. No deferred check.

### HXB-4 — Extract the common hex lattice without changing the editor

**Model:** Opus 5 / GPT Sol

**Model rationale:** This moves a shared ownership boundary while preserving
editor geometry, picking, brush ordering, and bake behaviour; a blind file move
would make headless consumers inherit presentation dependencies.

**Depends on:** HXB-2, HXB-3.

**Touches:**
- `src/board/HexGrid.gd`
- `src/presentation/worldmap/editor/WorldMapHexGrid.gd`
- `scripts/hex_battle/probe_grid.gd`
- `docs/ARCHITECTURE.md`

**End state:** Headless consumers use `HexGrid` for offset/axial conversion,
ordered six-neighbour queries, distance, and hex disc enumeration. The existing
WorldMapHexGrid API remains a compatible wrapper and retains editor dimensions.

**Implementation:** Extract coordinate arithmetic; decide the smallest clean
boundary between lattice math and presentation layout. Preserve exact method
behaviour for all existing editor callers. Public headless methods required by
later items are static `offsetToAxial(cell: Vector2i) -> Vector2i`,
`axialToOffset(cell: Vector2i) -> Vector2i`,
`neighbours(cell: Vector2i) -> Array[Vector2i]`,
`distance(a: Vector2i, b: Vector2i) -> int`, and
`disc(center: Vector2i, radius: int) -> Array[Vector2i]`.
Retain the editor's current neighbour order; disc output is row-major `(y,x)`.
No visual data types requiring Nodes or editor imports in HexGrid. Do not
change flat-top dimensions, rounding tie behaviour, brushes, ground shaders,
or bake composition. If another caller needs modification, the wrapper is
inadequate: redesign within these owned paths rather than expanding writes.

**Risk:** Odd-column and negative-coordinate conversions can drift subtly even
when centres look correct.

**Validation:**
- Self-contained: run `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/hex_battle/probe_grid.gd -Marker HXB_GRID_OK`.
  Assert conversion round-trips over positive/negative columns, six unique
  reciprocal neighbours, symmetric distance, translation through axial space,
  disc counts 1/7/19/61, and old/new wrapper parity. Audit headless imports.
- Deferred: HXB-V verifies editor picking/brush parity and the preserved square
  bake, with the then-current editor's committed validation utilities.

### HXB-5 — Define hex battle maps, scenarios, and authoritative state

**Model:** Opus 5 / GPT Sol

**Model rationale:** This determines the editor/runtime data boundary, separates
map identity from party setup, and defines state consumed by concurrent runtime,
query, AI, and presentation work.

**Depends on:** HXB-4.

**Touches:**
- `src/entities/BattleMapDefinition.gd`
- `src/entities/BattleScenario.gd`
- `src/entities/BattleParty.gd`
- `src/factories/BattleMapFactory.gd`
- `src/factories/BattleScenarioFactory.gd`
- `src/battle_sim/BattleState.gd`
- `src/battle_sim/BattleSetupConfig.gd`
- `src/battle_sim/BattleSetupFactory.gd`
- `src/battle_sim/BattleSetupValidationResult.gd`
- `data/battle/maps/**`
- `data/battle/scenarios/**`
- `scripts/hex_battle/probe_map_contract.gd`
- `docs/ARCHITECTURE.md`
- `docs/REFERENCE_CATALOGS.md`

**End state:** Typed headless maps/scenarios describe valid offset cells,
tactical terrain/elevation, visual source identity, deployment, parties, and
controllers. Setup rejects malformed/unsupported maps and overlapping or
insufficient deployment. State has the party fields needed by HXB-6 without
copying live occupancy into presentation.

**Implementation:** Choose a small versioned schema and implement strict
load/validation through factories. Keep terrain art IDs distinct from gameplay
terrain definitions; support explicit per-cell overrides. Keep a valid-cell mask
separate from rectangle bounds, terrain blocking, and occupancy. Define one
standable tactical surface per cell for this initial format; unsupported stacked
surfaces must be rejected explicitly. Integer logical elevation may coexist
with smooth visual geometry according to HXB-1; never infer rules from curvature.
Map source identity must cover tactical data and the visual product it matches.
Party IDs, commander ID, members, team ownership, and starting deployment are
data, not new Monster subclasses. No production `TEAM_SIZE == 4` assumption.

Publish committed consumer contracts in ARCHITECTURE.md before the next wave.
The board-view contract is fixed here: BattleMapDefinition exposes
`boardSize: Vector2i`, `visualScenePath: String`,
`validCells() -> Array[Vector2i]` (row-major),
`containsCell(cell: Vector2i) -> bool`, and
`heightAt(cell: Vector2i) -> int`. It also exposes finite floats
`cellWidth`, `cellHeight`, and `heightStep` for presentation, with positive
cell dimensions. These do not alter logical hex distance.
Initial editor-matching fixtures use 2.0, 2.0, and 0.5 respectively; these are
fixture values, not an approved artistic/balance retuning.

Provide a small synthetic map and scenarios containing at least two parties
per team and a commander plus another member in each party, using existing
monster definitions. Include a hole, obstacle, height edge, and synthetic
weighted route. Keep temporary fixture names clearly technical.
Do not implement scheduling, spatial resolvers, UI, or editor changes here.
Existing BattleSimulator must still parse with the setup seam; the hex factory
must not advertise a playable runtime until HXB-6/HXB-7 land.

**Risk:** A decorative edit can change gameplay; global bounds checks can make
holes walkable; setup can silently create parties with invalid commanders.

**Validation:**
- Self-contained: run `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/hex_battle/probe_map_contract.gd -Marker HXB_MAP_OK`.
  Cover valid load, round-trip data, unknown versions/terrain, malformed masks,
  invalid numeric dimensions, duplicate IDs/members, wrong-team commanders,
  overlaps, missing resources, and unsupported surfaces. Audit headless imports.
  No deferred check; runtime/visual integration belongs to dependent items.

### HXB-6 — Implement party activation, command lifecycle, and replay

**Model:** Opus 5 / GPT Sol

**Model rationale:** Activation changes temporal ownership, command legality,
effects, withdrawal, and replay simultaneously. Preserving deterministic
incremental and atomic execution requires architectural judgment.

**Depends on:** HXB-5.

**Touches:**
- `src/battle_sim/BattleSimulator.gd`
- `src/battle_sim/BattleState.gd`
- `src/battle_sim/TurnManager.gd`
- `src/battle_sim/BattleCommand.gd`
- `src/battle_sim/BattleCommandResult.gd`
- `src/battle_sim/BattleEvents.gd`
- `src/battle_sim/IBattleVisualAdapter.gd`
- `src/battle_sim/BattleStateSerializer.gd`
- `src/battle_sim/BattleReplayRunner.gd`
- `scripts/hex_battle/probe_activation.gd`
- `scripts/hex_battle/probe_replay.gd`
- `scripts/hex_battle/fixtures/activation/**`
- `docs/ARCHITECTURE.md`

**End state:** Canonical simulation implements HXB-1's party model. Every member
selection and action is authoritative; consumed/skipped/withdrawn members cannot
act again. Player, CPU, and replay use the same scheduling and command path.

**Implementation:** Preserve one executor and accepted-versus-resolved outcomes.
Model party activation separately from a member's movement/action phases.
Define validated member-selection/party-completion operations rather than letting
UI set `currentMonsterID`. Persist selected party/member, consumed members,
queue/round identity, phase accumulator when resumable, and pending lifecycle
state. Reject a mid-phase save explicitly if it is not supported; never load it
as a fresh activation. If member selection is free, replay records it explicitly
and CPU selection uses the same operation. Guard action availability by HXB-1,
including skips, pass, commander loss, and undo effects.

Use format versions above the currently supported square version, explicit
`grid_kind`, coordinate convention, and ruleset/content identity. Route square
files to a clear "use frozen square reference" rejection. Hex replay validates
all identity fields before execution and checks resulting state/event outcomes,
not only that commands were accepted. Catalog changes must be detected by a
content fingerprint or self-contained snapshot. Implement capture/restore from
an activation boundary and continuation determinism, including RNG/ID allocation.
Do not change HXB-5's map/party access contracts while HXB-7 reads them.

**Risk:** Party-end ticks every member twice; freely selected actors disappear
from replay; a dead commander leaves a stuck queue or an unauthorized actor.

**Validation:**
- Self-contained: run the launcher with `-Script res://scripts/hex_battle/probe_activation.gd -Marker HXB_ACTIVATION_OK`, then
  `-Script res://scripts/hex_battle/probe_replay.gd -Marker HXB_REPLAY_OK`.
  Assert deterministic ties, all members exhausted, pass/skip, invalid selection,
  commander defeat before/after acting, last party loss, exact effect/cooldown
  tick counts, fizzle recording, and atomic/incremental equivalence. Restore at
  an activation boundary and compare final state, RNG, IDs, and events; reject
  old grid, wrong ruleset/content, and unsupported partial snapshots.
- Deferred: HXB-V exercises the party lifecycle through real player/CPU UI.

### HXB-7 — Make authoritative spatial queries hex-correct

**Model:** Opus 5 / GPT Sol

**Model rationale:** Weighted movement, LoS boundary policy, and footprint
semantics must agree across validation and projected queries. Replacing direction
constants alone cannot establish correctness.

**Depends on:** HXB-5.

**Touches:**
- `src/algorithms/AStarPathfinder.gd`
- `src/algorithms/BFSFloodFill.gd`
- `src/algorithms/HexReachability.gd`
- `src/algorithms/LineOfSight.gd`
- `src/algorithms/ShapeCaster.gd`
- `src/battle_sim/MovementResolver.gd`
- `src/battle_sim/CombatResolver.gd`
- `src/battle_sim/PassiveSkillResolver.gd`
- `src/battle_sim/ReachQuery.gd`
- `scripts/hex_battle/probe_spatial.gd`
- `scripts/hex_battle/fixtures/spatial/**`

**End state:** Movement, target validity, preview/forecast, passive areas, and
resolved effects use one authoritative set of hex rules, including masked maps.

**Implementation:** Use HXB-4 math and HXB-5 state contracts. Decide the smallest
cost-aware path/reach implementation; BFS remains valid only for uniform edges.
Use admissible hex heuristics scaled by minimum traversal cost and stable ties.
Separate enter/pass-through, stop, cost, and terminate-movement decisions so
future control zones do not require another graph rewrite. Sum costs during
command validation, not path length. Preserve occupancy bijection, destination
rules, height legality, and projected vacated-origin semantics.

Implement HXB-1's exact LoS and line/cross/disc definitions. Brush line drawing
is not automatically a combat supercover rule. Height interpolation must use
hex-centre geometry, not raw offset-vector lengths. Skip LoS endpoints as
specified, and handle both seam sides consistently. All target enumeration,
including minimum range and empty centres, must cover the complete hex shape
before filtering. Keep stable output ordering. Expose the actual affected cell
set for presentation without adding presentation fields to simulation. Do not
edit state/scheduler files owned by HXB-6 or alter catalog balance.

**Risk:** Legal previews produce rejected commands; cheap short paths beat
cheaper longer paths incorrectly; edge-aligned sight differs by direction.

**Validation:**
- Self-contained: run the launcher with `-Script res://scripts/hex_battle/probe_spatial.gd -Marker HXB_SPATIAL_OK`.
  Compare shortest costs against an independent exhaustive small-graph oracle;
  cover parity, holes, blocked/occupied endpoints, height edges, rings/minimum
  range, border-clipped areas, aura counts, empty targets, reversal/edge/vertex
  LoS, and projected occupancy. Assert previews and authoritative validation
  agree on positive and negative examples. No squared-grid fallback in active
  spatial paths; unrelated uses of absolute values are not an audit failure.
- Deferred: HXB-V checks visible path/target/effect agreement during real turns.

### HXB-8 — Rewire CPU decisions around parties and shared hex queries

**Model:** Opus 5 / GPT Sol

**Model rationale:** The AI must select a party member as well as a command,
preserve deliberation determinism, and avoid duplicating legality in its threat
optimizations. This is more than a distance substitution.

**Depends on:** HXB-6, HXB-7.

**Touches:**
- `src/entity_ai/**`
- `src/algorithms/ThreatMap.gd`
- `scripts/hex_battle/probe_ai.gd`
- `scripts/hex_battle/fixtures/ai/**`

**End state:** CPU vs CPU and Player vs CPU select eligible party members and
submit legal hex commands through the canonical runtime; resumed deliberation
produces the same result as uninterrupted deliberation.

**Implementation:** Retain CommandDeliberation and role weights. Use scheduling
queries from HXB-6, and resolver queries from HXB-7 for every spatial candidate.
Remove square bounding diamonds and cardinal melee enumeration in ThreatMap,
not merely its final legality predicate. Assess affected cells/units when
building area threats. Use deterministic member-selection ties. Keep state
unchanged while deliberation is in flight and discard/restart a stale proposal
through a documented state revision check. Reuse paths/reach costs where useful
and measure candidate work on the agreed small and stress scenarios.
Remove older unreachable `_evaluateTile` branches after a caller audit; do not
revive them to implement hex. Do not add campaign strategy, production balance
weights, or a new multi-agent tactical planner. Record behavioral limitations
without disguising legal-but-basic AI as full Forsena tactical intelligence.

**Risk:** CPU skips a member, thinks from stale state, or underestimates attacks
from the two previously nonexistent melee neighbours.

**Validation:**
- Self-contained: run the launcher with `-Script res://scripts/hex_battle/probe_ai.gd -Marker HXB_AI_OK`.
  Assert every proposal validates, all eligible members eventually act/pass,
  both parities and all six approaches contribute threats, no hidden state/RNG
  mutations occur during planning, and multiple deliberation slice sizes return
  the same actor/command. Record timing and candidate counts against fixtures;
  no universal machine-dependent latency threshold is invented.
- Deferred: HXB-V observes responsive CPU turns and completed battles.

### HXB-9 — Build the hex board view and picking geometry

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** The map API, coordinate convention, mesh shape, collider
metadata, and height formula are specified; this item implements a bounded view
without owning camera, animation, gameplay, or artistic decisions.

**Depends on:** HXB-5, HXB-7.

**Touches:**
- `src/presentation/battle/HexBattleLayout.gd`
- `src/presentation/battle/HexBattleBoardView.gd`
- `src/presentation/battle/HexBattleMeshFactory.gd`
- `scripts/hex_battle/probe_board_view.gd`

**End state:** `HexBattleLayout` is a RefCounted value mapper constructed with
`BattleMapDefinition`. It exposes `cellCenter(cell: Vector2i) -> Vector3` and
`cellPolygon(cell: Vector2i) -> PackedVector3Array`. HexBattleBoardView is a Node3D
with `build(map: BattleMapDefinition) -> void`, `clear() -> void`, and
`getSurface(cell: Vector2i) -> MeshInstance3D`. HexBattleMeshFactory owns only
new hex geometry/resources.

**Implementation:** Cell centre X is `0.75 * cellWidth * col + cellWidth / 2`;
Z is `cellHeight * row + (cellHeight / 2 if col is odd else 0) + cellHeight / 2`;
Y is `heightAt(cell) * heightStep`. Polygon offsets, in this order, are
`(w/2,0), (w/4,h/2), (-w/4,h/2), (-w/2,0), (-w/4,-h/2), (w/4,-h/2)` in XZ.
Build only `validCells()`. Use a six-triangle top fan with correct upward normals
and a hex-shaped pick surface, not a bounding box. Each pick body has
`battle_coord` metadata and collision layer `1 << 19`, collision mask 0;
unit picking remains outside this item. Rebuilding/clearing frees owned nodes.
Use neutral debug material for probes; no art/palette choice is implied.

Mirror the tile metadata/lifecycle pattern in GodotVisualAdapter's
`_add_tile_column`, but do not edit it, BattleMeshFactory, any shared shader,
WorldMapGround, or existing camera. Surface meshes are tactical overlay/picking
geometry; HXB-13 supplies the visible exported terrain and controls visibility.
Do not multiply gameplay ranges by world dimensions or implement cursor input.

**Risk:** Bounding-box picking selects a neighbour near slanted edges, or a
nonzero map height places overlays above a different cell's terrain.

**Validation:**
- Self-contained: run the launcher with `-Script res://scripts/hex_battle/probe_board_view.gd -Marker HXB_BOARD_OK`.
  Assert both-parity centres against editor geometry at 2x2 dimensions, shared
  edge endpoints, polygon containment samples, upward normals, layer/metadata,
  no nodes for holes, and rebuild/clear counts. Narrow resource load is a smoke
  check; it does not establish on-screen picking correctness.
- Deferred: HXB-V raycasts real hex corners/edges at several camera angles,
  heights, and render scales and checks alignment with the authored ground.

### HXB-10 — Export tactical data and connect battle-map authoring

**Model:** Opus 5 / GPT Sol

**Model rationale:** The editor will have evolved before this cycle opens;
authoring, tactical overrides, resource import, and runtime export must converge
without turning simulation into an editor consumer.

**Depends on:** HXB-5, HXB-7.

**Touches:**
- `src/presentation/worldmap/editor/**`
- `data/worldmap/authored/hex_battle_fixture.json`
- `data/worldmap/regions.json`
- `data/battle/maps/editor_fixture.json`
- `assets/worldmap/regions/generated/hex_battle_fixture.png`
- `assets/worldmap/regions/generated/hex_battle_fixture.png.import`
- `scenes/worldmap/generated/hex_battle_fixture.tscn`
- `src/presentation/battle/BattleMapAssetManifest.gd`
- `scripts/hex_battle/probe_editor_export.gd`
- `docs/WORLDMAP_EDITOR.md`

**End state:** The editor can author explicit tactical cell data and export a
matching visual scene/map definition that instantiates without editor code.
The visual and tactical artifacts agree on source identity, origin, scale,
orientation, and heights. Unsupported geometry produces an actionable refusal.

**Implementation:** Build on the then-current document, history, terrain, and
object contracts; do not redo the editor cycle. Add battle-specific fields as
layers or a clearly attached tactical document, with undo/redo and save/reopen.
Map terrain defaults through the ledger only where semantics are explicit;
unknown metadata is an authoring error, not automatically clear terrain.
Export the HXB-5 schema without importing editor classes from its factory.
Retain generated-scenes/wrapper-scene separation. A manifest must enumerate
the generated resources needed by packaging. Source JSON and regeneration
instructions remain durable even when generated scenes are not committed.

Provide an in-editor route to export both products. Resolve or explicitly
automate the existing PNG import prerequisite using a supported source-tool
workflow; acceptance must include a freshly authored map rather than a
pre-imported fixture. Do not assume EditorFileSystem exists in a standalone
game. Changes stay inside editor-owned code; no shared ground/shader retuning.
If smooth terrain or bridge data cannot be represented faithfully, refuse that
map with the unsupported feature named and provide a supported authored map
for this cycle. Do not silently flatten terrain or block decorative water.
Only the named fixture's region registration may change in regions.json;
preserve every other region. Generated fixture products are owned outputs
whether or not current repository policy tracks them. Temporary fresh-map
acceptance exports go under `builds/hex-battle/`, never arbitrary source paths.

**Risk:** The preview uses newer data than export; a standalone session saves
but cannot export; source-tree-only loading fails in a packaged application.

**Validation:**
- Self-contained: run the launcher with `-Script res://scripts/hex_battle/probe_editor_export.gd -Marker HXB_EXPORT_OK`.
  Cover tactical layer serialization/history, source fingerprints, missing and
  unknown metadata, out-of-date bake, mismatched products, unsupported surfaces,
  and no editor dependencies in runtime resources. Check square document/bake
  behaviour remains unchanged where utilities can prove it without rendering.
- Deferred: HXB-V authors, saves, reopens, exports, and plays a fresh supported
  map, then instantiates its runtime products with the editor absent.

### HXB-11 — Adapt spell presentation in owned hex resources

**Model:** Opus 5 / GPT Sol

**Model rationale:** Existing effects encode square footprints and authored
timing/density assumptions. Preserving donor contracts while presenting the
larger hex areas requires visual and lifecycle judgment.

**Depends on:** HXB-6, HXB-7, HXB-9.

**Touches:**
- `src/presentation/battle/effects/**`
- `assets/shaders/battle_hex/**`
- `scripts/hex_battle/probe_vfx_contract.gd`
- `scripts/hex_battle/fixtures/vfx/**`
- `docs/VFX_DESIGN.md`

**End state:** A `HexBattleVfxBridge` under the owned effects directory dispatches
every currently reachable spell profile to compatible playback. Spatial effects
use actual resolved cells/world bounds; the old effects and shared resources
retain their appearance, timing, and lifecycle.

**Implementation:** Audit SpellVfxCatalog and all effect/profile/shader callers.
Classify body-bound effects reusable unchanged versus ground/area-dependent
effects needing owned copies. Inspect IceStorm, FireStorm, MagentaReduction,
AuroraVeil, SolarStorm, encasement, and charge/cast auras; do not assume an
effect is independent of tile scale because it accepts world positions.
Keep all hex variants and altered shader/material resources in owned subtrees,
with distinct class names and resource identities. Do not mutate donors,
VfxTextures, VfxPlayback, VfxCastContext, theme tokens, or shared mesh factories.

Define a bridge interface using existing VfxCastContext plus an explicit ordered
resolved-cell/world-footprint argument and document it in VFX_DESIGN.md for
HXB-13. Preserve event-time snapshots, target bounds/IDs, cancellation, completion,
and teardown. Bounds include empty affected cells as well as occupied targets;
a spell with one target must not collapse a wide area to that target's body.
If a copied effect assumes a Manhattan diamond, change only its hex-owned copy.
Do not quietly replace a supported spell with a generic flash or disable it.
Capture the donor/caller manifest for final regression comparison.

**Risk:** A cast hits seven cells but draws five, particle density grows
unbounded, or cancelled playback leaves the party controller waiting forever.

**Validation:**
- Self-contained: run the launcher with `-Script res://scripts/hex_battle/probe_vfx_contract.gd -Marker HXB_VFX_OK`.
  Verify catalog coverage, explicit hex resources, no writes/overrides of shared
  resources, footprint ordering/bounds including empty cells, and finite geometry
  at zero/default/stress radii. Resource loading is smoke evidence only.
- Deferred: HXB-V renders every affected donor and existing shared-dependency
  caller, compares available goldens, and checks each hex profile's appearance,
  timing, playback, cancellation, and lifecycle at representative radii/heights.

### HXB-12 — Build a party activation panel from a supplied view model

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** This is a bounded UI component with a fixed data shape and
interaction contract, composed from existing theme widgets; it makes no
scheduling, battle-flow, or visual-theme decisions.

**Depends on:** HXB-6.

**Touches:**
- `src/presentation/battle/ui/HexPartyPanel.gd`
- `scripts/hex_battle/probe_party_panel.gd`

**End state:** A Control `HexPartyPanel` exposes
`updateModel(model: Dictionary) -> void`,
`signal member_selected(monsterID: int)`, and `signal end_party_requested()`.
It displays the active party and its members, and emits selection only for
eligible members when input is enabled.

**Implementation:** View-model keys are `party_id: int`, `label: String`,
`input_enabled: bool`, `can_end_party: bool`, and `members: Array[Dictionary]`.
Each member has `id: int`, `label: String`, `commander: bool`, `eligible: bool`,
`active: bool`, and `spent: bool`. Render in supplied order without sorting or
deriving eligibility. Visually identify the commander, current member, and spent
members using existing NoggWindow/NoggTheme controls and tokens. End-party is
enabled exactly when both input_enabled and can_end_party are true. An empty
model clears stale selection. Update connections without duplication.
Mirror the component ownership style of `PlayerCommandMenu.gd`; do not edit
shared theme files, TurnOrderRail, PlayerCommandMenu, or battle controllers.
Do not read BattleState, dispatch commands, introduce hotkeys, or invent titles.

**Risk:** A stale panel allows selecting an enemy/already-spent member or emits
the same request repeatedly after refresh.

**Validation:**
- Self-contained: run `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/hex_battle/probe_party_panel.gd -Marker HXB_PARTY_PANEL_OK`.
  Feed synthetic empty/active/spent/disabled models; assert enabled states,
  signal IDs, supplied ordering, and one emission after repeated updates.
- Deferred: HXB-V checks readability, focus, keyboard/mouse use, and correct
  party/member display in the real battle scene.

### HXB-13 — Integrate the playable hex scene and interaction lifecycle

**Model:** Opus 5 / GPT Sol

**Model rationale:** This is the composition boundary between asynchronous
playback, party activation, CPU deliberation, player intent, map assets, and
camera/picking. Most failures cross several of these lifetimes.

**Depends on:** HXB-8, HXB-9, HXB-10, HXB-11, HXB-12.

**Touches:**
- `src/systems/hex_battle/**`
- `src/presentation/battle/HexBattleVisualAdapter.gd`
- `src/presentation/battle/HexBattleCursor.gd`
- `src/presentation/battle/HexBattleCamera.gd`
- `src/presentation/battle/HexBattleSetupUI.gd`
- `src/presentation/battle/HexBattleHud.gd`
- `src/presentation/battle/HexBattlePlayback.gd`
- `scenes/battle/**`
- `scenes/debug/HexBattleDebugScene.tscn`
- `scripts/hex_battle/probe_scene_contract.gd`

**End state:** `scenes/battle/HexBattle.tscn` runs setup, Player vs CPU and CPU vs
CPU party battles, and return-to-setup through the canonical runtime. The debug
scene wraps the same composition. Input waits for the relevant playback boundary
without permitting a second scheduling owner.

**Implementation:** Build a new `HexBattleController` in the owned systems
subtree; do not inherit the square BattlePresentationController. Compose the
existing command/effect/portrait/theme infrastructure where its contract fits.
New HexBattleVisualAdapter extends the existing IPlayerTurnVisualAdapter, which
already implements the IBattleVisualAdapter boundary and owns the playback-drain
signal. Do not redeclare that inherited signal. Resolve all terrain,
unit, cursor, marker, spell, and camera positions through HexBattleLayout.
Use the exported visual product together with matching tactical picking geometry.

Player party selection uses HXB-6's authoritative operation, then a hex-owned
member-turn controller may reuse the structure of PlayerTurnController. Do not
copy its rectangular clamping or quadrant direction rotation. Define directional
input by projecting the six neighbouring centres through the current camera,
with stable ties and explicit handling of invalid cells; preserve accept/cancel,
mouse intent ownership, HUD focus, and camera drag capture. Choose an interaction
mapping that reaches all six neighbours and demonstrate it, rather than claiming
four arrows automatically provide six direct directions.

Render the HXB-12 panel from authoritative eligibility. Remove any speed-queue
forecast that no longer describes the approved activation model. Setup exposes
scenario/party composition and keeps seeded presets reproducible. Integrate
HXB-11 playback, target-bound effects, damage/heal feedback, status/Resonance,
and dead/withdrawn-unit disposal. Preserve event-time positions while newer
simulation state exists. One owner controls start-next-member, playback drain,
CPU resumption, and party-end. Teardown disconnects and cancels everything it owns.
Camera changes stay in the new camera implementation; do not retune shared
BattleCameraController/Director or world-map camera resources.

**Risk:** Duplicate end-turn calls, input into a stale party, cursor jumps across
hex seams, VFX on the next actor, or return-to-setup retaining old callbacks.

**Validation:**
- Self-contained: run the launcher with `-Script res://scripts/hex_battle/probe_scene_contract.gd -Marker HXB_SCENE_OK`.
  Narrow-load the new scenes, validate resource paths/UIDs and required adapter
  ports, and audit direct state writes and old square-controller dependencies.
  Do not call controller handlers directly as a substitute for real input.
- Deferred: HXB-V exercises real `Input.parse_input_event()` or actual input,
  both modes, all six directions, rotated camera, render scaling, hover/confirm,
  cancel/undo, party selection/pass, effects, battle end, and repeated setup return.

### HXB-14 — Promote hex and retire obsolete battle entry points

**Model:** Opus 5 / GPT Sol

**Model rationale:** Removing obsolete scene roots while preserving shared VFX
debug dependencies and export resources requires a dependency audit; a broad
directory move or deletion would be unsafe.

**Depends on:** HXB-13.

**Touches:**
- `project.godot`
- `export_presets.cfg`
- `scenes/Battle25D.tscn`
- `scenes/debug/BattleDebugScene.tscn`
- `src/systems/BattlePresentationController.gd`
- `src/systems/PlayerTurnController.gd`
- `src/presentation/GodotVisualAdapter.gd`
- `src/presentation/BattleCursorController.gd`
- `src/presentation/BattleCameraDirector.gd`
- `src/presentation/TurnOrderRail.gd`
- `src/presentation/BattleSetupUI.gd`
- `src/presentation/BattleSetupUIRefs.gd`
- `src/presentation/BattleUIBuilder.gd`
- `src/presentation/BattleUIRefs.gd`
- `src/presentation/ConsoleMapRenderer.gd`
- `src/presentation/ConsoleVisualAdapter.gd`
- `src/presentation/ConsoleRoundSummary.gd`
- `src/board/BattleBoard.gd`
- `src/algorithms/ParabolicArc.gd`
- `scripts/demo_battle.gd`
- `scripts/hex_battle/probe_entrypoints.gd`
- `README.md`
- `docs/README.md`
- `docs/ARCHITECTURE.md`
- `docs/MODULE_MAP.md`
- `docs/GAME_DESIGN.md`
- `docs/DEVELOPMENT.md`
- `docs/UI_DESIGN.md`
- `docs/REFERENCE_CATALOGS.md`
- `BACKLOG_CRITICAL.md`
- `BACKLOG_LONGTERM.md`

**End state:** Main scene is `res://scenes/battle/HexBattle.tscn`; exported builds
contain nested battle data and all map resources; the console demo uses the same
party runtime. Documentation has one clear route to the square reference.

**Implementation:** Retire obsolete square roots/controllers only after auditing
their complete callers. The explicit candidates above may be removed with their
sidecars when unreferenced; if a shared consumer still needs one, preserve and
document its limited compatibility role instead of breaking that consumer.
Shared BattleMeshFactory and model/theme/VFX factories remain at their existing
paths. No cosmetic whole-repository reorganization, no donor retuning, no mass
catalog deletion. Old map factories/data can remain for reference utilities;
they must not be exposed as selectable hex battle scenarios.

Use HXB-10's manifest to ensure the export includes source-independent runtime
resources and `data/battle/**/*.json` where used; account for the existing
source-tree-only editor loading. Exclude the frozen source archive/editor-only
tooling from the playable export. Export to a new ignored builds directory.
Update the owning docs rather than duplicate rules. Correct obsolete workflow
text in DEVELOPMENT.md to match AGENTS.md. Review touched backlog files as
whole-file ownership in this single-session wave: remove entries completed or
superseded by the migration, retain actionable open work, and avoid turning the
optional list above into dozens of speculative backlog entries.

**Risk:** A VFX debug scene still needs a retired helper; nested JSON is missing
from the package; old docs route future work back to the square battle.

**Validation:**
- Self-contained: run the launcher with `-Script res://scripts/hex_battle/probe_entrypoints.gd -Marker HXB_ENTRYPOINTS_OK`.
  Check main scene, resource/caller paths, remaining legacy roles, catalog
  selection, nested export inclusion, document links, and square archive hash.
  Regenerate required runtime assets from committed source before packaging.
- Deferred: HXB-V launches a fresh packaged hex build, the surviving VFX debug
  scene, and the independent archived square battle; all required assets load.

### HXB-V — Validate the integrated system, then close the cycle

**Model:** Opus 5 / GPT Sol

**Model rationale:** Acceptance spans simulation, editor export, party UI, input,
packaging, and visual compatibility. It includes independent judgments of
appearance and readability, so it cannot be folded into the implementing session.

**Depends on:** HXB-1 through HXB-14, all committed.

**Touches:**
- `src/board/HexGrid.gd`
- `src/board/BattleBoard.gd`
- `src/algorithms/**`
- `src/entity_ai/**`
- `src/battle_sim/**`
- `src/entities/BattleMapDefinition.gd`
- `src/entities/BattleScenario.gd`
- `src/entities/BattleParty.gd`
- `src/factories/BattleMapFactory.gd`
- `src/factories/BattleScenarioFactory.gd`
- `src/presentation/battle/**`
- `src/presentation/worldmap/editor/**`
- `src/systems/hex_battle/**`
- `src/systems/BattlePresentationController.gd`
- `src/systems/PlayerTurnController.gd`
- `src/presentation/GodotVisualAdapter.gd`
- `src/presentation/BattleCursorController.gd`
- `src/presentation/BattleCameraDirector.gd`
- `src/presentation/TurnOrderRail.gd`
- `src/presentation/BattleSetupUI.gd`
- `src/presentation/BattleSetupUIRefs.gd`
- `src/presentation/BattleUIBuilder.gd`
- `src/presentation/BattleUIRefs.gd`
- `src/presentation/ConsoleMapRenderer.gd`
- `src/presentation/ConsoleVisualAdapter.gd`
- `src/presentation/ConsoleRoundSummary.gd`
- `assets/shaders/battle_hex/**`
- `scenes/battle/**`
- `scenes/debug/HexBattleDebugScene.tscn`
- `scenes/Battle25D.tscn`
- `scenes/debug/BattleDebugScene.tscn`
- `data/battle/**`
- `data/worldmap/authored/hex_battle_fixture.json`
- `data/worldmap/regions.json`
- `assets/worldmap/regions/generated/hex_battle_fixture.png`
- `assets/worldmap/regions/generated/hex_battle_fixture.png.import`
- `scenes/worldmap/generated/hex_battle_fixture.tscn`
- `scripts/hex_battle/**`
- `scripts/demo_battle.gd`
- `project.godot`
- `export_presets.cfg`
- `README.md`
- `docs/README.md`
- `docs/ARCHITECTURE.md`
- `docs/MODULE_MAP.md`
- `docs/GAME_DESIGN.md`
- `docs/DEVELOPMENT.md`
- `docs/UI_DESIGN.md`
- `docs/VFX_DESIGN.md`
- `docs/WORLDMAP_EDITOR.md`
- `docs/REFERENCE_CATALOGS.md`
- `BACKLOG_CRITICAL.md`
- `BACKLOG_LONGTERM.md`
- `docs/sketches/hex-battle/**`
- `docs/sketches/README.md`
- `docs/plans/hex-battle-migration.md` (lifecycle deletion only after passing)

**End state:** Every deferred line above is accepted with concrete evidence;
defects found are fixed within this surface and relevant checks rerun. The
cycle merges and is cleaned up in this same turn if validation passes.

**Implementation:** Run alone after the user confirms no session is editing.
Read item commit evidence first; reuse passed self-contained results instead
of rerunning everything. Recheck only where changes or uncovered risks justify
it. Keep the frozen package/tag immutable: archive failures hold acceptance and
must be resolved explicitly, not concealed by updating the baseline.

Use one integrated authored-map flow to cover setup, multiple parties/members,
both column parities, weighted route, holes, height, melee, area/single/self
spells, passives, status/Resonance, skips, commander loss, party/battle end, and
setup return. Exercise Player vs CPU and complete a CPU vs CPU battle. Verify
headless/replay outcomes agree with the real command history and that UI order
matches scheduling. Measure AI responsiveness on the documented stress fixture.

Exercise new-map/save/reopen/export without relying on pre-imported images;
launch its runtime products without the editor and in the fresh packaged build.
Check keyboard/gamepad-compatible actions, mouse input, HUD focus, camera drag,
all six neighbour directions, corners/edges, render scales, and raised terrain.
No active source may depend on the extracted square project or archive bytes.

Run the donor/shared-caller VFX sweep against preserved configurations and
available goldens, sequentially with the hex checks. An unexpected change in an
existing effect's appearance, timing, playback, or lifecycle fails acceptance;
fix the new owned code, never the donor. The extracted square baseline completes
its preserved battle/replay and remains hash-identical. Include editor wrapper
parity and square world-map bake verification after shared math extraction.

**Risk:** A superficially playable hex scene hides broken archive dependencies,
missing packaged data, drifted effects, or nondeterministic party scheduling.

**Validation:**
- Self-contained: focused diffs, relevant failing-probe reruns, all runtime
  dependency/UID checks, archive hashes, final docs/backlog consistency. Record
  the complete acceptance matrix and any remaining limitations in this commit.
- Deferred: all integrated gameplay, editor, archived-square, input, visual
  caller, and packaged-build acceptance described above. A failure holds merge.

**Closing:** Promote only a sketch that meets docs/sketches/README.md's retention
bar. Record genuinely open follow-on work once in the appropriate backlog and
owning design note. Delete this cycle file in the final item commit after its
checks pass. Follow AGENTS.md's no-ff merge, push main, safe local branch cleanup,
and branch/worktree audit. Offer remote branch deletion unless the user has
explicitly authorized it; do not infer that authorization from local cleanup.
Do not close with a branch merely "pending merge" when the required quiet-tree
and passing-validation conditions hold.

## Class disposition checklist

This checklist locates work; item Touches lists alone authorize writes.

| Existing class/group | Disposition |
|---|---|
| WorldMapHexGrid | HXB-4 extracts headless math; editor wrapper preserved |
| WorldMapTileData, TilesetCatalog, SceneExport, editor HUD/controller/history | HXB-10 tactical authoring/export additions after editor-cycle reconciliation |
| Matrix | Reuse unchanged; rectangle storage is not square topology |
| BattleState | HXB-5 map/party state; HXB-6 activation/save invariants |
| Map, MapFactory, MapReferences | Square reference/catalog utilities; new typed battle definition/factories own active hex data |
| BattleBoard, ParabolicArc | Confirm no callers; HXB-14 retires if unused |
| AStarPathfinder, BFSFloodFill, ShapeCaster, LineOfSight | HXB-7 weighted hex geometry and authoritative query path |
| MovementResolver, CombatResolver, PassiveSkillResolver, ReachQuery | HXB-7 geometry, costs, resolved footprints |
| BattleSimulator, TurnManager, BattleCommand/Result, BattleEvents, IBattleVisualAdapter | HXB-6 party lifecycle and shared execution |
| BattleStateSerializer, BattleReplayRunner | HXB-6 explicit new identity, scheduling ledger, deterministic continuation |
| BattleSetupConfig/Factory/ValidationResult, BattleSetupPresets | New scenario/party path in HXB-5; old presets not reused as implicit 4v4 constraints |
| EntityBrain, BrainTargeting, all four brain subclasses | HXB-8 shared hex/member queries, weights retained, dormant branches audited |
| BattleCommandEvaluator, CommandDeliberation, ThreatMap | HXB-8 candidate coverage, actor choice, stable budgeted deliberation |
| GodotVisualAdapter, BattlePresentationController, PlayerTurnController | Structural donors for HXB-13 owned hex composition; obsolete roots retired by HXB-14 |
| BattleCursorController, BattleCameraDirector, TurnOrderRail | New hex input/camera/party display; old versions retired if unreferenced |
| BattleMeshFactory, BattleCameraController | Reuse unchanged only where contracts fit; shared debug callers remain valid |
| VisualAction/Queue, BattleVisualEffects, VfxPlayback, VfxCastContext | Stable sequencing/reference contracts; hex-specific copies only where old geometry assumptions require them |
| SpellVfxCatalog and all effect/profile/shader families | HXB-11 complete carrier audit, owned variants, HXB-V donor/caller regression |
| Monster, Spell, PassiveSkill; MonsterStatCalculator, DirectDamageRules, SpellEffectResolver | Reuse non-geometric behaviour; no new balance or commander subclass |
| Monster/Spell/PassiveSkill factories and reference catalogs, elements/races/statuses | Reuse content; replay captures/fingerprints relevant identity |
| MonsterVisualRegistry/ModelFactory, PortraitRenderer, icons, theme widgets | Reuse unchanged, verify scale/lifecycle in new composition |
| BattleUIBuilder/Refs, BattleSetupUI/Refs, PlayerCommandMenu, graphics UI | Compose where compatible; new setup/party boundary owned by HXB-12/HXB-13; retire only obsolete roots |
| BattleEnvironmentFactory, RetroRenderController, render presets | Reuse unchanged; HXB-V checks picking under scaling and packaged resources |
| ConsoleMapRenderer/VisualAdapter/RoundSummary, demo_battle | HXB-14 reports hex coordinates/parties and uses active scenario runtime |

## Waves

Every dependency must already be committed. Models are assigned per item above;
the table repeats routing so the user can dispatch directly. A mixed wave means
separate sessions, never one lower-tier session silently taking its higher-tier
neighbour. Each executing session states whether its actual model matches the
assignment, then proceeds under AGENTS.md's cost-signal rule.

| Wave | Items and suggested models | Why this tier / why disjoint |
|---|---|---|
| 1 | HXB-1 — **Sonnet 5 / GPT Terra** | Exact two-file transcription of the approved rules and ownership contract |
| 2 | HXB-2 — **Opus 5 / GPT Sol**; HXB-3 — **Sonnet 5 / GPT Terra** | Dependency-safe archive judgment vs specified probe launcher; references/preservation script and hex launcher paths are disjoint |
| 3 | HXB-4 — **Opus 5 / GPT Sol** | Shared math extraction and editor compatibility boundary |
| 4 | HXB-5 — **Opus 5 / GPT Sol** | Map/scenario/state contracts must exist before consumers |
| 5 | HXB-6 — **Opus 5 / GPT Sol**; HXB-7 — **Opus 5 / GPT Sol** | Scheduling/state/events/replay vs algorithms/movement/combat/passive queries; both read committed HXB-5 contracts, neither edits the other's paths |
| 6 | HXB-8 — **Opus 5 / GPT Sol**; HXB-9 — **Sonnet 5 / GPT Terra**; HXB-10 — **Opus 5 / GPT Sol** | AI/threat vs specified board-view files vs editor/export/one map fixture; all dependencies are committed and probe paths are distinct |
| 7 | HXB-11 — **Opus 5 / GPT Sol**; HXB-12 — **Sonnet 5 / GPT Terra** | Owned VFX resources/design note vs specified party panel; neither edits shared theme or the future scene adapter |
| 8 | HXB-13 — **Opus 5 / GPT Sol** | Integrates all committed ports; lifecycle, input, and scene ownership decisions |
| 9 | HXB-14 — **Opus 5 / GPT Sol** | Single-session entrypoint/export/retirement and whole-file documentation/backlog reconciliation |
| 10 | HXB-V — **Opus 5 / GPT Sol** | **Validation: standalone, alone, quiet tree**; independent visual judgment and integration across subsystems |

Waves 3 and 4 may be one dependency-consecutive Opus/Sol session, with one commit
per item and a push at each wave boundary. Waves 8 and 9 may similarly be a
single Opus/Sol lane. HXB-V remains a separate validation session. There is one
consolidated deferred-validation item; self-contained checks are never parked
there to save an implementing session work.
