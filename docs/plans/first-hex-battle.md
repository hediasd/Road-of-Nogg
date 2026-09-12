# First hex battle

2026-09-12. Take the hex battle from a validated data pipeline with a grey empty
board to a battle that can be simulated headlessly into a readable file and then
watched with models moving on authored terrain. Two gates, in order: a backend
mode good enough to run championships that train a homebrew model, then the
played battle. Along the way the battlefield stops being something a person
decides cell by cell, because the tilesets already say what each tile is.

This is not a combat-design cycle. Nothing here changes what an attack does, how
a party is ordered, or what a terrain costs to enter beyond what the ledger
already declares.

## Read first and dispatch safely

Read `../README.md`, the current `AGENTS.md`, `../POLICIES.md`,
`../ARCHITECTURE.md`, `../DEVELOPMENT.md`, and `../WORLDMAP_EDITOR.md` §6 and
§20. The editor side of this cycle rests on the foundation accepted on
2026-09-12; the battle side rests on the hex battle migration that shipped
before it.

Resume from this file and from commit bodies, never by editing status into the
plan:

```powershell
git log --grep="Plan-Item: FHB-" --format="%h %s"
```

Each item commits once, with its finding in the body and a `Plan-Item: FHB-N`
trailer. Run the item's own self-contained checks before that commit.

## Outcome

- A hex battle draws its units. Models appear at their deployment cells and move
  when the simulation moves them.
- A hex battle draws its authored terrain. The painted map is what a player
  looks at; the tactical hexes become an overlay on top of it.
- `hexmap` is playable: it carries a battlefield layer, exports to battle
  products, and has a scenario that deploys two sides on it.
- A battlefield layer is derived from the tileset's own terrain kinds rather
  than decided cell by cell, and the editor can author and override it per tile.
- One command runs a battle headlessly and writes both a readable log and a
  machine-readable record, and one command runs many of them for a championship.
- Both cycle gates are signed off against a launched game, and this plan file is
  deleted.

## Present-state facts an executing agent must not "fix"

**The board's grey hexes are pick geometry, not terrain.** `HexBattleBoardView`
and `HexBattleMeshFactory` say so in their own headers. Do not restyle them into
scenery; FHB-7 puts real terrain underneath and decides what this layer becomes.

**`scenes/worldmap/generated/` is gitignored on purpose.** `ResourceSaver.save()`
assigns fresh resource ids on every write, so a committed export would show a
spurious diff after every re-export. A fresh checkout therefore has the battle
map and the baked art but not the scene. That is a declared state that
`BattleMapAssetManifest` exists to report. Do not commit generated scenes, and
do not "fix" the manifest by making it lenient.

**`BattleSetupFactory.createHexState()` adds monsters to the state directly
rather than through `BattleSimulator.spawnMonster()`.** That is correct: setup
builds a state, it does not narrate one. The missing piece is that nobody ever
announces the finished board to the visual adapter. Do not reroute setup through
`spawnMonster`, which would add every monster twice.

**A scenario is bound to its map by id, revision AND source fingerprint.**
Re-exporting a map invalidates every scenario that named the old fingerprint,
and `BattleScenarioFactory` refuses to load with `map_fingerprint_mismatch`.
That is the binding working. When a map is re-exported, its scenarios are
updated in the same commit.

**The tactical terrain ledger is deliberately tiny**: `clear`, `rough`,
`blocked`, everything at one movement point except `rough` at two. Its own
header explains that a richer table would be inventing balance this migration is
not allowed to invent. Do not add terrain kinds in this cycle.

**`HexBattleLayout`'s X/Z already match `WorldMapHexGrid.cellCentre` exactly at
the editor's 2.0/2.0 cell metrics.** An authored map and its battle view agree
on where a cell sits without either side duplicating the parity step. If
authored terrain looks misaligned under the board, the bug is elsewhere; do not
add a corrective offset.

**`WorldMapGround.authoring_surface` is an editor-instance flag and must never
reach an export.** `WorldMapSceneExport.buildRuntime()` builds its own ground
carrying the default.

**Two export paths exist, and both are correct for their caller.** The editor's
in-app Export Battle goes through `WorldMapDocumentExport.publish()`, which
names its products by document UUID because publication identity is the saved
envelope. `WorldMapBattleExport.exportBoth()` names them by a human map id,
which is what committed authored content and its scenarios use. Do not collapse
them.

**`docs/battle_log.txt` is where `ConsoleVisualAdapter` writes and is
gitignored.** Its emoji prose is for a person reading a run, not for a machine.

**`scripts/hex_battle/probe_playthrough.gd` already drives a whole battle
through the real player input path.** The interaction layer is not broken; the
board is simply empty while it happens.

## Items

### FHB-1 — Announce the starting board so a battle has units on it

**Model:** Sonnet 5 / GPT Terra.

**Model rationale:** A located defect with a single cause, an existing correct
implementation to reuse, and a literally checkable end state. The judgement —
that setup builds the state and the simulator announces it — is made here in the
plan, leaving an exact edit at one seam.

**Depends on:** nothing.

**Touches:**
- `src/battle_sim/BattleSimulator.gd`
- `src/systems/hex_battle/HexBattleController.gd`
- `scripts/hex_battle/probe_board_population.gd` (new) and its `.uid`

**End state:** Starting `proving_ground_player_cpu` leaves every alive monster in
`BattleState` with a model node under the adapter's root, seated at its
deployment cell's world position. `HexBattleVisualAdapter.modelFor(id)` returns a
non-null node for all eight members. No monster is added to the state twice: the
count of `Unit_*` children equals the count of alive monsters exactly.

**Implementation:** `BattleSimulator.emitRestoredBattle()` already does precisely
the right thing — it walks `state.monsters`, skips the dead, builds the stats
dictionary and emits `monster_spawned` for each, then emits `battle_started`. It
has no caller. Rename it to `emitInitialBoard()` and keep `emitRestoredBattle()`
as a one-line delegate so any future replay caller still resolves.

In `HexBattleController.startBattle()`, call `sim.emitInitialBoard()` after
`adapter.connectToEvents(sim.events)` and before `sim.startBattle()`. The order
matters and is the whole of the fix: the adapter must be listening, and the
announcement must precede the loop that will start moving things.

`BattleSimulator.startBattle()` emits `battle_started` too. Emitting it twice is
harmless today but is a loose end, so have `startBattle()` skip its own emission
when `emitInitialBoard()` has already run for this battle, tracked by a private
bool reset in `configureHexState`.

Do not touch `BattleSetupFactory`, `BattleState.addMonster`, or the square
battle's own path.

The new probe loads `scenes/battle/HexBattle.tscn` in a real window, starts the
scenario, waits for layout, and asserts the model count, each model's position
against `adapter.worldPositionOf(cell)`, and that no id is duplicated. Marker
`HXB_BOARD_POPULATION_OK`.

**Risk:** The console adapter also listens for `monster_spawned`, so the headless
log gains a spawn line per monster. That is an improvement, not a regression, but
it changes `docs/battle_log.txt`; say so in the commit body. Emitting to an
adapter that is not connected yet would silently do nothing, which is why the
probe asserts models rather than asserting the call happened.

**Validation:**
- Self-contained: the new probe with its exact marker; `probe_playthrough.gd`,
  `probe_proving_ground.gd` and `probe_replay.gd` still pass.

### FHB-2 — Derive battle terrain from the tileset's own terrain kinds

**Model:** Sonnet 5 / GPT Terra.

**Model rationale:** The mapping is decided here rather than left open, and the
input already exists: every frame of the starter sheet declares `land`, `sea` or
`grass`. What remains is a pure function and its probe, with exact names and an
exactly checkable result.

**Depends on:** nothing.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapTacticalLayer.gd`
- `src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd`
- `scripts/worldmap_editor/checks/terrain/probe_terrain_derivation.gd` (new) and
  its `.uid`
- `docs/WORLDMAP_EDITOR.md` §20

**End state:** `WorldMapTacticalLayer.derivedFrom(data, groundLayerID)` returns a
`Vector2i -> String` dictionary giving every lattice cell a ledger terrain id,
using this mapping of the tile's declared terrain kind:

| Tile terrain kind | Battle terrain |
|---|---|
| `sea` | `blocked` |
| `land` | `clear` |
| `grass` | `clear` |
| absent or unrecognised | `clear` |
| empty cell (no tile painted) | `blocked` |

`WorldMapTacticalLayer.applyDerived(data, groundLayerID, layerID)` creates the
battlefield layer if absent and writes that result into it, replacing whatever
was there. Applied to `hexmap`, the sea cells become `blocked` and the rest
`clear`.

**Implementation:** The kind comes from the tileset catalog's per-tile `TERRAIN`
field; add a `terrainKindFor(tilesetID, tileID) -> String` accessor to
`WorldMapTilesetCatalog` rather than reading the raw dictionary from the tactical
layer. Only the starter hex sheet declares kinds today and the other sheets do
not, which is why "absent" has a defined answer rather than being an error.

`grass` maps to `clear`, not `rough`. Rough means difficult ground and costs two
movement points; grass is ordinary. Choosing otherwise would be a balance
decision, which this cycle does not make.

Whole-layer replacement, with no record of which cells a person changed by hand.
Per-cell override and its provenance are FHB-8's problem; building half of it
here would give that item a format to migrate rather than to design.

The probe builds a small synthetic document on the starter sheet with one cell of
each kind plus one empty cell, asserts the five outcomes above, asserts that
applying twice is identical to applying once, and asserts that a document with no
battlefield layer gains one. Marker `HEX_TERRAIN_DERIVATION_OK`.

Do not touch the editor controller, chrome or actions; nothing in this item is
reachable from the UI yet.

**Risk:** A sheet whose tiles declare no kind derives an entirely `clear` map,
which is playable but wrong-looking. That is the intended fallback and the
documentation says so.

**Validation:**
- Self-contained: the new probe with its exact marker; the existing painting and
  editor-export probes still pass.

### FHB-3 — Export a map's battle products without opening the editor

**Model:** Sonnet 5 / GPT Terra.

**Model rationale:** A thin runner over an API that already exists and is already
probed. Its inputs, outputs, failure codes and marker can all be named exactly.

**Depends on:** nothing.

**Touches:**
- `scripts/worldmap_editor/export_battle_products.gd` (new) and its `.uid`
- `scripts/worldmap_editor/checks/export/probe_headless_export.gd` (new) and its
  `.uid`
- `docs/DEVELOPMENT.md`

**End state:**

```powershell
./Godot_v4.4-stable_win64.exe --headless --path . --script scripts/worldmap_editor/export_battle_products.gd ++ hexmap
```

reads `data/worldmap/authored/hexmap.noggmap.json`, writes
`data/battle/maps/hexmap.json` and `scenes/worldmap/generated/hexmap.tscn` plus
the baked texture, prints each written path, and ends with
`HEX_EXPORT_OK <mapID>`. A refusal prints the exporter's own reason and exits
non-zero without having written anything.

**Implementation:** Through `WorldMapBattleExport.exportBoth(data, framing,
mapID)` with the map id taken from the file's basename, not through
`WorldMapDocumentExport.publish()` — see the present-state note on why both exist.
Use `WorldMapGroundUniforms.DEFAULTS` for the framing; an exported scene's framing
is a property of the shipped map, not of whatever the editor was showing.

Accept the map id as a user argument after `++`. Refuse a name that
`WorldMapWorkspacePaths.isValidName` rejects, and refuse a missing source file,
both with their own message.

The probe runs the runner's own entry function against `proving_ground` into a
`user://` destination, asserts the battle JSON parses through
`BattleMapFactory.fromDictionary`, asserts the scene loads, and asserts a
refusal for a name with a path separator in it. Marker `HEX_HEADLESS_EXPORT_OK`.

Document the command in `DEVELOPMENT.md` beside the existing probe instructions,
including that the scene it writes is gitignored and must be regenerated after a
fresh checkout.

Do not modify the exporter, the baker or the editor.

**Risk:** Re-exporting a map changes its fingerprint and invalidates scenarios
bound to it. The runner must say so on success: print a reminder naming the
scenarios under `data/battle/scenarios` whose `MAP.ID` matches.

**Validation:**
- Self-contained: the new probe with its exact marker; `probe_editor_export.gd`
  still passes.

### FHB-4 — Author the first battle on hexmap

**Model:** Opus 5 / GPT Sol.

**Model rationale:** The mechanical half is trivial; the judgement is what makes
a first fight worth watching. Roughly two fifths of this map is water, so
deployment, reach and the shape of the approach decide whether the battle reads
as a fight or as two lines that never meet. That is a design call against a
specific map, not a specification.

**Depends on:** FHB-2, FHB-3.

**Touches:**
- `data/worldmap/authored/hexmap.noggmap.json`
- `data/battle/maps/hexmap.json` (new)
- `data/battle/scenarios/hexmap_player_cpu.json` (new)
- `data/battle/scenarios/hexmap_cpu_cpu.json` (new)

**End state:** `hexmap` carries a derived battlefield layer, exports cleanly, and
both scenarios load through `BattleScenarioFactory` without a refusal. The
CPU-versus-CPU scenario reaches a winner when run headlessly. Deployment cells are
standable, non-overlapping, and on opposite approaches to whatever the water
divides.

**Implementation:** Apply FHB-2's derivation to the source, then export through
FHB-3's runner. Commit the source, the battle map and both scenarios together;
the generated scene is gitignored and must not be committed.

Two scenarios, mirroring `proving_ground`: one player-versus-CPU for the played
gate, one CPU-versus-CPU for the headless gate. Keep the party shape close to
`proving_ground`'s so the two are comparable when something looks wrong — two
parties a side, two members each, a commander in each.

The open questions are yours. Whether the water should divide the sides or sit
beside them; whether a crossing exists at all; whether anyone deploys somewhere a
melee member cannot reach a target before the round limit. If the derived layer
makes a bad battlefield, say so in the commit body and hand-edit the specific
cells rather than changing FHB-2's rule — the rule is right for the general case
and this map is one map.

Choose the monsters from the existing catalog and keep levels modest; a first
battle that ends in two exchanges tells you nothing about movement.

**Risk:** A scenario that loads but deadlocks — nobody can reach anybody — looks
like a hung battle rather than a bad map. Run the CPU-versus-CPU scenario to a
result before committing, and record the round count.

**Validation:**
- Self-contained: both scenarios load; the CPU-versus-CPU one runs to a winner
  through `scripts/demo_battle.gd` pointed at it, or through FHB-5's runner if
  that has landed; record the outcome and the round count.

### FHB-5 — A headless runner that writes a readable log and a machine record

**Model:** Opus 5 / GPT Sol.

**Model rationale:** This is the cycle's first gate and the foundation for
training a model later. What a record must contain to be worth keeping — the
observation a decision was made against, the legal alternatives, what was chosen,
what it led to — is a design question whose wrong answer is expensive to
discover, because it is only discovered when someone tries to learn from the
data.

**Depends on:** FHB-1.

**Touches:**
- `scripts/battle/run_battle.gd` (new) and its `.uid`
- `scripts/battle/run_championship.gd` (new) and its `.uid`
- `src/presentation/BattleRecordAdapter.gd` (new) and its `.uid`
- `scripts/demo_battle.gd` (retire or reduce to a wrapper)
- `docs/DEVELOPMENT.md`

**End state:** One command runs any scenario at any seed and writes a readable
log and a machine-readable record to named paths outside the repository. Another
runs a set of seeds and writes one record per battle plus a summary. Both end
with an exact marker. Two runs at the same seed produce byte-identical records.

**Implementation:** `scripts/demo_battle.gd` already proves the shape works: it
loads a scenario, builds a hex state, attaches `ConsoleVisualAdapter`, and calls
`runFullBattle`. What it is not is reusable — the scenario, the seed and the
output path are constants in the file, and its output is emoji prose.

Keep the human log; a person reading one run is a real use. Add a second adapter
alongside it rather than replacing it, so the two never compete for one format.
`ConsoleVisualAdapter` writes to `res://docs/battle_log.txt` today, which is a
gitignored path inside the repository; the runner should direct both outputs
under `user://` by default and accept an override.

The record's shape is the item's real work. Constraints it must satisfy:

- **Replayable.** Scenario id, map id and revision, source fingerprint, seed, and
  the engine's own version, so a record can be tied back to exactly what produced
  it.
- **Per decision, not per frame.** A battle is a sequence of member activations.
  Each should carry the acting member, the state it acted against, what it could
  legally have done, what it did, and what changed.
- **Outcome attached.** Every record ends with the winner, the round count, and
  why it ended, so a batch can be scored without replaying it.
- **One battle per line, or one file per battle** — decide which, and say why in
  the commit body. Many small files and one large file have opposite costs when
  a championship runs thousands of battles.

Determinism is not optional and is not free: dictionary iteration order, float
formatting and timestamps all break it. Assert it rather than assume it — the
runner's own probe should run one scenario twice at one seed and compare bytes.

The championship runner is a thin loop over seeds with a summary; do not build
scheduling, parallelism or a matchmaking model here.

Player-controlled parties cannot be simulated headlessly, because a console has
nobody to choose. Refuse a scenario containing a player party with a clear
message rather than silently letting the CPU play both sides.

**Risk:** A record that looks complete and is missing the one field a learner
needs is discovered months later, by which point there is a corpus in the wrong
shape. Write one real battle's record and read it back as if you were the model
before settling the schema; say in the commit body what you checked.

**Validation:**
- Self-contained: a probe running one scenario twice at one seed and asserting
  identical bytes, plus a refusal for a player-party scenario; marker
  `HEX_BATTLE_RUNNER_OK`.
- Deferred: FHB-6 reads a real run's output and judges whether it is legible and
  sufficient.

### FHB-6 — Accept the backend battle

**Model:** Opus 5 / GPT Sol.

**Model rationale:** The cycle's first gate. Judging whether a record is
sufficient for its purpose is exactly the call that cannot be reduced to an
assertion, and it should be made by a session that did not design the schema.

**Depends on:** FHB-1, FHB-2, FHB-3, FHB-4, FHB-5.

**Touches:**
- Union of FHB-1 through FHB-5 Touches, for observed defects only.
- `docs/DEVELOPMENT.md`

**End state:** A championship of at least twenty seeds runs on
`hexmap_cpu_cpu.json` to completion. Outcomes vary across seeds. Records are
identical on a re-run of the same seed. A person can read one battle's human log
and follow what happened, and a reader of the machine record can reconstruct each
decision without the log beside it.

**Implementation:** Run it, then read it. Specifically: check that seeds actually
diverge rather than all reaching the same result, that no battle hits the round
limit without a winner, and that the map's water is doing something — if every
battle plays out identically the battlefield is not a battlefield.

Then take the model's side. Pick one record and answer, from the file alone,
what the acting member could see, what it could have done instead, and why the
outcome followed. Where you cannot, that is a finding, and it is worth more than
a passing assertion.

Record timings: a championship that takes an hour for twenty battles will not
train anything, and if it is slow, say where the time goes rather than
optimising blind.

Fix defects inside the owned set and rerun the affected checks only. A defect
outside it is reported, not silently edited.

**Risk:** Declaring the gate passed on a run that technically completed while the
data is unusable. The judgement above is the item; the assertions are not.

**Validation:**
- Deferred: this item is the consolidation. Record the championship's command,
  its outputs' location, the outcome spread, the timings, and the model's-eye
  reading, in the commit body.

### FHB-7 — Show the authored terrain under the battle board

**Model:** Opus 5 / GPT Sol.

**Model rationale:** Two rendering layers have to coexist without either being
useless: authored art a player reads, and a pick surface that has to stay
selectable and legible over it. How much of the tactical layer survives, and what
happens on a checkout where the generated scene is absent, are judgement calls
with no obviously correct answer.

**Depends on:** FHB-1.

**Touches:**
- `src/systems/hex_battle/HexBattleController.gd`
- `src/presentation/battle/HexBattleVisualAdapter.gd`
- `src/presentation/battle/HexBattleBoardView.gd`
- `src/presentation/battle/HexBattleMeshFactory.gd`
- `src/presentation/battle/HexBattleCamera.gd`
- `scripts/hex_battle/probe_board_terrain.gd` (new) and its `.uid`
- `docs/HEX_BATTLE.md` (new)

**End state:** Starting a battle on a map whose visual scene exists puts the
authored terrain under the board, aligned cell for cell with the tactical hexes,
and the board reads as the map the author painted. A map whose scene is absent
still starts, with the tactical surface as it is today and a status line saying
the terrain needs re-exporting.

**Implementation:** `BattleMapDefinition.visualScenePath` is already populated and
`BattleMapAssetManifest` already reports whether the file is there. Nothing
instantiates it. That is the gap.

`HexBattleLayout`'s X/Z already match the editor's own cell centres, so the
exported ground should drop in at the origin with no correction. If it does not,
find out why before adding an offset — see the present-state note.

The open question is what happens to `HexBattleBoardView`. Its own header says it
is not the terrain players see and that this item controls its visibility. The
range runs from hiding it entirely and picking against the terrain, through
keeping it as a translucent overlay, to keeping it opaque only where the
simulation needs to say something. Whatever you choose, picking must still work:
the pick bodies are on their own collision layer precisely so they can be
invisible and still be hit.

Terrain arrives with its own colours and the board's markers were tuned against
flat grey. Movement ranges, target highlights and the cursor have to stay
readable over painted art in any palette. If a marker stops reading, that is part
of this item.

Camera framing currently frames the map's valid cells. Authored terrain may
extend past them. Decide whether the frame follows the battlefield or the art,
and say why.

A missing scene is a normal state, not an error: do not refuse to start.

**Risk:** Terrain that renders over the units, or a pick surface that stops
receiving rays once something is drawn above it. The probe must assert that a
raycast at a known cell still returns that cell with terrain present.

**Validation:**
- Self-contained: the new probe asserting alignment at three known cells, that
  picking still resolves with terrain loaded, and that a map with no scene still
  starts; marker `HXB_BOARD_TERRAIN_OK`. Existing board-view, spatial and
  playthrough probes still pass.
- Deferred: whether the board reads well, and whether markers stay legible over
  painted terrain, is FHB-9's.

### FHB-8 — Author battle terrain per tile in the editor

**Model:** Opus 5 / GPT Sol.

**Model rationale:** A feature with a stated purpose — that the author should not
be deciding walkability cell by cell — and an unstated shape. Where derivation
ends and override begins, how an override survives a repaint of the art beneath
it, and what else is worth carrying per tile are the design.

**Depends on:** FHB-2.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapTacticalLayer.gd`
- `src/presentation/worldmap/editor/WorldMapEditorController.gd`
- `src/presentation/worldmap/editor/WorldMapEditorHud.gd`
- `src/presentation/worldmap/editor/workspace/WorldMapWorkspaceActions.gd`
- `src/presentation/worldmap/editor/workspace/WorldMapWorkspaceChrome.gd`
- `scripts/worldmap_editor/checks/terrain/probe_terrain_authoring.gd` (new) and
  its `.uid`
- `docs/WORLDMAP_EDITOR.md` §20
- `docs/HEX_MAP_FORMAT.md`

**End state:** The battlefield layer can be filled from the art in one action,
inspected per cell, and overridden per cell, and an override is visibly distinct
from a derived value. Re-deriving after painting new art keeps overrides and
updates everything else. The document format carries whatever provenance that
requires, versioned.

**Implementation:** FHB-2 gave you the rule and a whole-layer replace. This is
the half it deliberately left: a person looking at a map and disagreeing with it
in three places.

The tension is that derivation and override want opposite things. Derivation is
only useful if it can be re-run after the art changes; override is only useful if
re-running does not erase it. That needs the document to remember which cells a
person set, which is a format change — `HEX_MAP_FORMAT.md` owns the schema, and
the envelope is versioned for exactly this.

The user's stated goal is that they should not have to decide where can be walked.
Bias every default toward the derived answer and make override the deliberate
act, not the reverse.

"Any other useful info at tile level" is open, and the constraint is the
present-state note: the ledger is `clear`, `rough`, `blocked` and this cycle does
not extend it. What you *can* surface is what the map format already supports and
the editor does not expose well — per-cell elevation is the obvious candidate,
since the battle map carries it and the export already quantises it. Decide
whether that belongs here or is a later cycle, and say which in the commit body.

Fit the controls into the left column's menu that the foundation established; do
not reintroduce a toolbar row.

**Risk:** A provenance format decided quickly here is carried by every map
afterwards. If the answer is not clear, a smaller version that cannot be wrong —
derive-on-demand with an explicit confirm, and no stored provenance — is a better
commit than a format you are unsure of.

**Validation:**
- Self-contained: the new probe covering fill-from-art, per-cell override,
  re-derive preserving overrides, and a round trip through the envelope; marker
  `HEX_TERRAIN_AUTHORING_OK`. Document-safety, file-format and foundation
  acceptance probes still pass.
- Deferred: whether authoring a battlefield actually feels faster than deciding
  by hand is FHB-9's.

### FHB-9 — Accept the played battle and close the cycle

**Model:** Opus 5 / GPT Sol.

**Model rationale:** The final gate is a judgement about whether a battle is worth
watching, spanning rendering, interaction and authoring work from three different
waves. A fresh session, separate from every implementing lane.

**Depends on:** FHB-1 through FHB-8.

**Touches:**
- Union of FHB-1 through FHB-8 Touches, for observed integration defects only.
- `docs/HEX_BATTLE.md`
- `docs/plans/first-hex-battle.md` (delete on successful closure only)
- `docs/sketches/` and `docs/sketches/README.md` (only if a sketch earns a place)

**End state:** A player starts `hexmap_player_cpu.json` from the setup screen and
plays a battle to a result on authored terrain, with models moving, at both
1280x720 and 1920x1080. Every defect found inside the owned set is fixed and its
affected checks rerun. This plan file is deleted in the closing commit.

**Implementation:** Play it. Not a probe — the probes already pass, and they
passed while the board was empty.

Exercise, and record evidence for:

1. The setup screen with both new scenarios listed, at both window sizes.
2. A full player-versus-CPU battle to a result: select a member, move, attack,
   end the party, let the CPU answer, repeat. Models appear at deployment, move
   along their paths, and leave the board when defeated.
3. The terrain reading against the editor's own view of the same map. Markers,
   cursor and movement range staying legible over painted art.
4. A battle on a map whose generated scene has been deleted, confirming it still
   starts and says why the terrain is missing.
5. The editor's battlefield authoring on a second map: derive, disagree in three
   cells, re-derive after repainting the art, export, and play the result.
6. One CPU-versus-CPU run through the headless runner after all of the above,
   confirming the backend gate still holds.

Record the observed client sizes and the models' scale against the cells — a
first look is when "the units are the wrong size for the board" is cheap to fix
and expensive to leave.

Attribute failures precisely. An outside-path defect is reported, not silently
edited. If the gate fails, retain this plan and report the concrete failure.

On success, write `docs/HEX_BATTLE.md` up to what shipped, promote a sketch only
if one settled a judgement call, and delete this file in the same commit.

**Risk:** A battle that passes every check and is unpleasant to play. That
finding belongs in the commit body even when nothing is fixed, because the next
cycle is written from it.

**Validation:**
- Self-contained: check changed links and affected probes after any fix; verify
  no `FHB-` reference survives in `docs`, `src` or `scripts`.
- Deferred: the six observations above are the acceptance, recorded in this
  item's commit rather than in another status file.

## Waves

| Wave | Items | Why disjoint / validation form |
|---|---|---|
| 1 | FHB-1, FHB-2, FHB-3 | battle simulator and controller, versus the tactical layer and tileset catalog, versus a new headless runner. `WORLDMAP_EDITOR.md` belongs to FHB-2; `DEVELOPMENT.md` to FHB-3. |
| 2 | FHB-4, FHB-5 | authored data and scenarios, versus runner scripts and a new record adapter. No shared file. |
| 3 | FHB-6 | **Validation: standalone, early.** The backend gate. Nothing later should be built on an unproven simulation pipeline. |
| 4 | FHB-7, FHB-8 | battle presentation and `HEX_BATTLE.md`, versus editor authoring and `WORLDMAP_EDITOR.md`. No shared file. |
| 5 | FHB-9 | **Validation: standalone, quiet tree.** Judgement spanning three waves. |

## Deliberately excluded

**New terrain kinds.** The ledger stays `clear`, `rough`, `blocked`. Cover,
elevation-based defence, flight and terrain-driven evasion are balance decisions
and belong to a combat cycle.

**Training the model.** This cycle produces the data a championship needs. It
does not build a learner, a reward function, a tournament format or an
evaluation harness.

**Parallel or distributed championship runs.** One loop over seeds. Throughput
work is worth doing once the record schema has survived contact with a learner.

**Replaying a recorded battle back into the 3D view.** A record good enough to
train from is probably good enough to replay, and that is a reason to keep the
idea, not to build it now.

**Rebuilding the setup screen.** It lists scenarios and takes a seed, which is
what this cycle needs from it. Party editing, map preview and scenario authoring
in-game are their own work.

**Square battle parity.** The square path is frozen. Nothing here restores it,
and nothing here may break it.

**Map selection from inside the editor.** Exporting and then choosing a scenario
is two steps, and collapsing them into a "play this map now" button is a
convenience worth having only once there is something good to play.
