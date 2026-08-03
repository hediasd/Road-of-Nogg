# Critical backlog

Items here need prompt resolution because they leave current gameplay incomplete
or misleading.

## The action forecast says nothing about a buff or debuff spell

`PlayerTurnController._forecastText()` branches on `spell.heals`, then on
`spell.damage_lines`. A spell that is neither — every pure buff, debuff, and
status spell in the catalogue — matches no branch and falls through to
`"Expected: N unit(s) affected"`. `Empower` is the clearest case: it grants
`BUFFS_ATK: 3` for `BUFF_DURATION: 2`, and the one window whose entire job is
to tell the player what an action will do reports only that one unit is
affected. The confirm step is therefore blind for a whole class of spells: the
player is asked to commit to an effect the UI never states. The authored fields
are already on `Spell` and the affected-target list is already computed, so
this is a presentation gap, not a missing mechanic.

## Monster spell kits

- **Blue Crowned Pidgeon:** has no spells at all. Assign at least one Wind set
  using the implemented Level 1 pool.
- **Level 2-4 pool covers one element of ten.** Wood is complete as of
  2026-07-28 (`Gather` → `Thornlash` → `Bramble Crown` → `Roses at Summers End`,
  on `Walker of the Woods`) and is the reference implementation. The other nine
  elements still stop at Level 1, so Resonance cannot exceed one charge for any
  monster that does not own the Wood ladder. Author against the tier contract in
  `docs/GAME_DESIGN.md`, which the reference-catalog check enforces.
- **23 of 25 Level 1 spells are assigned to no monster.** They are implemented
  and tested; they simply have no home. Reported as warnings by the
  reference-catalog check (pass `verbose` to list them).
- **Roster readiness check:** after each kit is authored, run the integration
  tier. Sets may be partial, but each set must stay on one element and hold at
  most one spell per Level.

## Monster level and growth

- **Battle setup cannot choose monster level.** The runtime already derives
  HP, ATK, and DEF from a monster's level, and battle-state serialization
  records that level, but every setup still constructs every roster slot at
  level 1. Add a per-slot level to the setup contract and UI, preserve it
  through replay reconstruction, and default older setup snapshots to level 1.
- **All authored growth values are zero.** After level can vary through setup,
  choose a bounded level range and author role-shaped HP/ATK/DEF growth for all
  monsters. Level 1 must remain unchanged; mixed-level construction, replay,
  and the visible setup-to-status-window path need integrated validation.

## Player command UI

- **The command UI rework is done** (2026-07-29 through 2026-07-31). Turn
  execution is split into order-aware phases, the player state machine lives in
  `src/systems/PlayerTurnController.gd`, the play/pause toggle gates visual
  playback while the simulation runs ahead under `RUN_AHEAD_LIMIT`, and
  `CONFIRM_ACTION` shows a damage/heal/elevation forecast sourced from the same
  `CombatResolver` math real resolution uses. The command menu, playback pause,
  surface-accurate picking, and Spell/`< BACK` navigation are stabilized.
- **Positional targeting has passed headless in-window acceptance**
  (2026-07-31). The pass drove the real `Battle25D` scene through synthetic
  input for legal empty and occupied centers, target cycling with no free grid
  roaming, blocked-empty confirmation, a zero-hit `Dark Nova` cast, mouse
  picking across two elevations and two rotated camera yaws, and both phase
  orders.
- **Still open: camera-relative controls and broader visual accessibility.**
  Cursor movement is board-relative, so it does not follow a rotated camera.
- **`debug/drive_battle.gd` now covers ten checks, up from five.** Its
  occupied-only target assertions were replaced with positional ones, and it
  gained typed reference/lifecycle coverage, animation-flow and pause/resume
  coverage, and the empty-center targeting flow.
- **What headless input still cannot establish:** appearance, animation feel,
  and camera-angle usability. A human pass at a normal window remains the only
  way to judge those, and no such pass has been done.
- **`activeActionKind()` cannot observe `focus` or `message` actions.** They
  resolve inside the start handler and never become the active action, so any
  future animation harness must cover that path indirectly (the battle log
  growing) rather than by polling the queue.

## Content inconsistencies

- **`Purple Dungeon Slime` claims "immune to physical crits"** in its
  `DESCRIPTION`, but no such mechanic exists. **Decided 2026-08-01: reword it**,
  do not build the immunity — physical attacks cannot crit at all
  (`_rollCritical()` is only reached from the spell path), so the immunity
  would guard a code path that does not exist.
- **No monster `DESCRIPTION` is read by any production code.** 11 of 28
  monsters carry one and no player has ever seen them, which is how the Slime's
  claim drifted from the implementation unnoticed. The other 10 have never been
  checked against actual mechanics; worth a sweep when descriptions are
  surfaced in the UI.
