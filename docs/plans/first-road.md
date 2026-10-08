# The first stretch of the road

2026-10-08. Henri asked for "the first stretch of the road" after it was
proposed as the item that turns the battle prototype into a game: a short road
of battles on the world map, a company of monsters that carries over between
fights, and progression through the lore's Pyramid of Belief. Belief drives
levels and, at its peaks, ascension along the catalog's `ASCENDS_FROM` lines.
Today battles happen in a vacuum. The setup screen offers one map and a fixed
lineup, every growth value is zero, and the world map renders but nothing
travels on it. This cycle builds the loop end to end on placeholder content. It
is not a story, a campaign structure, or a lore pass, and it invents no names.
One session executes it in order on `main`; the wave table still keeps the
Touches lists disjoint so a later re-run could split it.

## Outcome

From the battle setup screen the player opens the road. A world map shows four
stops joined by a road, a company of six monsters, and a panel listing each
monster's level and Belief. The player picks up to four to field and which one
commands, then travels to an open stop. That starts a hex battle with those
monsters against the stop's enemies, played in the normal battle scene. When it
ends, the road shows what each fielded monster earned. Belief raises levels,
levels raise HP/ATK/DEF through catalog growth, and a monster whose Belief
reaches an ascension threshold can ascend into its ascended form. Winning opens
the next stop. Cleared stops can be fought again. Progress is saved to
`user://` and resumes the next time the road opens.

## Creative decisions this cycle does not make

AGENTS.md makes these the user's. Each stays empty or `TBC` in data and is
listed in the closing report:

- the road's name, each stop's name, and any story or flavour text;
- which lore episode or place the road is, if any;
- whether "Belief" is the on-screen word. It is the lore's own term for what
  fuels ascension ("Pyramid of Belief") and was proposed by that name, so it is
  used, and flagged;
- the other two ascension components the lore names, relics and elemental
  dominance. They are not modelled. Belief alone gates ascension here.

## Mechanical defaults chosen (AGENTS.md: stated, overrulable)

- **Belief per battle, per fielded monster:** +1 for being fielded, +1 for
  standing at the end (not defeated, not withdrawn), +1 per enemy it felled,
  +2 more if that enemy was a commander, +1 to every fielded monster on a win.
  Monsters left out earn nothing. A loss or draw still pays what was earned.
  An abandoned battle pays nothing.
- **Level from Belief:** reaching level L costs `3 × (L−1) × L / 2` Belief in
  total (3, 9, 18, 30, 45, 63, 84, 108, 135), with the cap at level 10.
- **Growth by archetype**, in the catalog's hundredths per level
  (HP/ATK/DEF): defender 400/34/67, striker 250/67/34, controller 300/50/50,
  leader 300/34/50. Three levels are roughly one default ascension step.
- **Ascension:** the first ascension needs 18 Belief (level 4) and the second
  63 (level 7). It is offered, never automatic. Species changes to the
  catalog entry whose `ASCENDS_FROM` names it. Belief and level are kept: the
  lore says followers' belief built the ascension, not that it is spent.
- **Company:** Lesser Bigua and Paper Cat (the two monsters with an ascension
  line), Walker of the Woods (the one complete Resonance ladder), Healer Mage,
  Humility, Kraken Summoner. All start at Belief 0. The first four start
  fielded, with Walker of the Woods commanding.
- **Stops:** four battles on the two maps with committed terrain, alternating
  hexmap and proving_ground, with enemy levels 1, 2, 3, 4. HP does not carry
  between battles and nobody is lost for good. Defeat keeps the company at
  that stop.
- **Map:** temp2, the default world-map region. Stops sit beside its painted
  buildings. Positions are layout, not lore.

## Present-state facts an executing agent must not "fix"

- **Levels already appear in every scenario and do nothing.** All eight
  scenario monsters are authored at levels 1–4, and growth is zero. Once
  growth lands, those battles become real mixed-level battles. Their numbers
  move on purpose. `checks/fixtures/legacy_decisions.json` is regenerated
  because CPU behaviour moves on new stats, which is the documented procedure
  (DEVELOPMENT.md, "A failure there means CPU behaviour moved").
- **`probe_forecast` fails once after any content change** and passes on the
  next run. It compares against a leftover file in `battle_output/`. That is
  not a regression caused by this cycle.
- **`hexmap.noggmap.json` cannot be battle-exported** (no tactical layer).
  The road uses the committed battle maps as they are.
- Runtime code never imports `map_editor/`; the road reads battle maps through
  `content/` like every battle does.

## Items

### ROAD-1 — Build the road as a headless model

**Model:** Opus 5 / GPT Sol

**Model rationale:** This opens a new headless root that later items and later
cycles build on. Its state shape, serialization, the line between catalog data
and rules, and how a battle result is tallied without presentation are
boundary decisions with no existing sibling to copy.

**Depends on:** —

**Touches:**
- `road/**` (new headless root)
- `content/RoadReferences.gd` (+ `.uid`)
- `data/roads.json`
- `checks/road/probe_road_rules.gd` (+ `.uid`)
- `checks/manifests/road.json`

**End state:** `data/roads.json` holds one road with the company, four stops,
their maps, deployment cells and enemy parties, loaded and validated through
`content/`. A headless road state records the company (species, Belief), who
is fielded and who commands, which stops are cleared, and an attempt counter.
It derives levels, offers and applies ascension, composes the next battle as a
scenario dictionary that `BattleScenarioFactory.fromDictionary` accepts,
tallies a finished battle from `BattleEvents` and `BattleState`, and applies
the result. It round-trips through a `user://` save. The probe proves the
rules and plays one real CPU-vs-CPU road battle headlessly through
`BattleSimulator`, then applies it.

**Implementation:** Mirror `simulation/`'s discipline: no scene tree, no
presentation, deterministic seeds (road seed, stop index, attempt), stable
member ids that map back to company slots. The session decides the file split
and whether the rules live beside the state or apart, and records why. Keep
catalog parsing in `content/` (MODULE_MAP: `data/` is loaded only through
`content/`). Fail loudly on a save that does not match the road it names.

**Risk:** A save format that is hard to evolve. Version it from the start.

**Validation:**
- Self-contained: `probe_road_rules` (registered in the new `road.json`
  manifest) covers Belief arithmetic, level thresholds, ascension offer and
  apply, save round-trip, catalog refusal of a bad record, scenario
  composition for every stop, and one played battle.

### ROAD-2 — Make levels real: author growth by archetype

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A catalog edit with exact values given here, plus a
procedure-defined fixture regeneration and one probe adjustment. The values
are decided above, and nothing in it needs a design call.

**Depends on:** —

**Touches:**
- `data/monsters.json` (the three `*_GROWTH` keys of every monster, nothing else)
- `checks/fixtures/legacy_decisions.json`
- `checks/battle/probe_playthrough.gd`
- `docs/GAME_DESIGN.md` (the "Level-based stat growth" status row, and a growth table under "Entities and elements")
- `BACKLOG.md` ("Make levels playable")

**End state:**
- Every monster's `STATS` has `HP_GROWTH`/`ATK_GROWTH`/`DEF_GROWTH` equal to
  its `ARCHETYPE`'s row: defender 400/34/67, striker 250/67/34, controller
  300/50/50, leader 300/34/50. `git diff --stat -- data/monsters.json` shows
  111 changed lines (37 × 3) and no others.
- `checks/fixtures/legacy_decisions.json` is regenerated with
  `LegacySidePolicy.decisionRecord` at its existing seeds, with
  `policy_fingerprint` unchanged.
- `probe_playthrough` passes again. It failed with "no player attack
  resolved" once stats moved. Fix the probe's coverage drive or seed, not the
  game, and say which in the commit.
- GAME_DESIGN's status row reads live. The backlog item keeps only per-slot
  level selection in battle setup.

**Implementation:** Edit the JSON so only the 111 growth lines change
(preserve tab indentation and key order). Regenerate the fixture with a
throwaway script that calls the probe's own `_simulator(seed)` path. Do not
touch any policy, resolver, or scenario.

**Risk:** Hidden probes encoding level-1 numbers. Run
`powershell -NoProfile -ExecutionPolicy Bypass -File checks/run_probe_sweep.ps1 -Filter "checks/battle"`
and expect only the stale-artifact `probe_forecast` first-run failure.

**Validation:**
- Self-contained: that sweep, green apart from the `probe_forecast` first-run
  quirk, which must pass on its rerun.

### ROAD-3 — Let a host embed a battle and hear how it ended

**Model:** Opus 5 / GPT Sol

**Model rationale:** It changes the lifecycle of `HexBattleController`, which
every battle runs through: setup, restart, teardown and the session drawer. The
contract it offers a host, and what restart and "Setup" mean inside it, are
judgement calls whose mistakes surface as stale callbacks or double results.

**Depends on:** —

**Touches:**
- `battle/HexBattleController.gd`
- `battle/HexBattleSetupUI.gd`
- `ui/HexGraphicsPanel.gd`
- `checks/battle/probe_embedded_battle.gd` (+ `.uid`)
- `checks/manifests/hex_battle.json`

**End state:** A host can add the battle scene, start a battle from a scenario
path and seed without the setup screen ever showing, receive a signal once
when the battle completes (after playback drains, as the result line does
today), and receive one when the player leaves. Inside an embedded battle the
drawer's Setup row says so and leaves instead, and Restart does not run. The
standalone setup screen gains an entry that opens the road scene. Standalone
battles behave exactly as before.

**Implementation:** Existing probes that drive the controller
(`probe_playthrough`, `probe_board_terrain`, `probe_scene_contract`) must pass
unchanged. The session decides how embedding is declared. A road scene path
constant is fine. The scene itself is ROAD-4's.

**Risk:** A completion signal emitted twice, or a leave that does not tear
down. The probe asserts exactly-once and a clean teardown.

**Validation:**
- Self-contained: `probe_embedded_battle` plus the hex battle probes it could
  disturb.

### ROAD-4 — Put the road on the world map

**Model:** Opus 5 / GPT Sol

**Model rationale:** New presentation that composes the world-map rig, a 2D
panel under the Nogg theme, and an embedded battle without changing any shared
world-map or battle class. It needs layout and orchestration judgement, and
its acceptance is partly visual.

**Depends on:** ROAD-1, ROAD-3.

**Touches:**
- `scenes/Road.tscn`
- `worldmap/WorldMapRoadController.gd` (+ `.uid`)
- `worldmap/WorldMapRoadMarkers.gd` (+ `.uid`)
- `ui/RoadPanel.gd` (+ `.uid`)
- `checks/road/probe_road_scene.gd` (+ `.uid`)
- `checks/manifests/road.json`

**End state:** `scenes/Road.tscn` opens on temp2 with the stops, the road
between them and the company's position. The panel shows each company
monster's level, Belief toward the next level, fielded state, the commander,
and an Ascend action when one is offered, plus the selected stop's map and
enemies and a Travel/Fight action. Travelling hides the map and runs the
battle embedded. Completion shows what each fielded monster earned, and
returning saves and redraws. The scene probe drives a whole CPU-controlled
road battle through the real scene and checks the saved state moved.

**Implementation:** Follow `WorldMapDebugController`'s rig (SubViewport,
`WorldMap.tscn`, region catalog, props, a framing preset) without editing it,
or any shared world-map class. Text uses the game fonts and theme tokens
(UI_DESIGN.md, `hud-spacing` rules). The session judges marker and panel
design. Record the judgement in the commit, and keep it plain: the visual
pass is the validation item's.

**Risk:** A second 3D world running under the battle's. Stop the map's
processing while a battle is embedded.

**Validation:**
- Self-contained: `probe_road_scene` (headless load, travel, CPU battle,
  return, save).
- Deferred: the road reads well on temp2 at the default framing, markers and
  panel are legible, and the battle hand-off feels like one game.

### ROAD-5 — Document the road

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Prose that records decisions already made above and in
the item commits, in the documents that own each fact. There is no judgement
beyond placement.

**Depends on:** ROAD-1, ROAD-2, ROAD-3, ROAD-4.

**Touches:**
- `docs/GAME_DESIGN.md` (new "The road (first slice)" section)
- `docs/MODULE_MAP.md` (`road/` row and dependency line)
- `docs/ARCHITECTURE.md` (a short "The road" section: ownership and flow)
- `docs/DEVELOPMENT.md` (opening the road scene; the road probes)
- `docs/README.md` (index row if a new owning doc is needed; otherwise untouched)
- `BACKLOG.md` (follow-ups: names TBC, relics and elemental dominance, recruitment)

**End state:** GAME_DESIGN states every mechanical default listed in this file
under a heading that marks them as defaults awaiting confirmation. MODULE_MAP
lists `road/` as headless with its allowed dependencies. ARCHITECTURE explains
who owns road state, how a battle is composed, tallied and applied, and where
the save lives. DEVELOPMENT names the two road probes and how to open
`scenes/Road.tscn`. BACKLOG gains only verified, actionable follow-ups.

**Implementation:** Do not cite item ids outside `docs/plans/` (AGENTS.md).

**Risk:** Docs that drift from code. Quote the constants' names, not only
their values.

**Validation:**
- Self-contained: every path named in the new prose exists (grep audit).

### ROAD-V — Play the road

**Model:** Opus 5 / GPT Sol, in a fresh session, after Henri plays it.

**Model rationale:** Acceptance is a judgement of look and feel across the
world map, the panel and the battle hand-off, built in different items.
Interactive play is Henri's (AGENTS.md), so the session records what he saw,
triages defects across those subsystems, and fixes what is in scope.

**Depends on:** ROAD-1 to ROAD-5.

**Touches:** whatever a found defect needs, named in its commit; otherwise
none (an empty validation commit).

**End state:** Henri has opened the road from setup, fielded a lineup, won and
lost a battle, seen Belief and levels rise, ascended a monster, quit and
resumed. Defects are fixed or moved to the backlog. The cycle file is deleted
and the creative decisions above are put to him.

**Validation:**
- Deferred: the playthrough above, on the default render preset and the
  harshest retro preset.

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | ROAD-1, ROAD-2 | new road root, catalog loader and probe vs. monster growth and its fixtures |
| — | convergence review after ROAD-2 | — |
| 2 | ROAD-3 | battle controller, setup and session drawer only |
| 3 | ROAD-4 | road scene, markers and panel; needs ROAD-1 and ROAD-3 |
| 4 | ROAD-5 | documentation only |
| 5 | ROAD-V | validation, standalone: Henri plays, a fresh session records |

## Deliberately excluded

- Recruiting new monsters, items, equipment, money, shops.
- HP or status carrying between battles, and permanent loss.
- Branching roads, random encounters, travel time.
- Per-slot level selection in the standalone battle setup. It stays in the
  backlog's "Make levels playable".
- Any name, lore, description or story text (see the creative decisions above).
- Changing any shared world-map, battle, theme or VFX class beyond the three
  battle-side files ROAD-3 names.
