# Critical backlog

Items here need prompt resolution because they leave current gameplay incomplete
or misleading.

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

## Player command UI

- **`PC-1` through `PC-5` are all done** (PC-1/PC-2 2026-07-29, PC-4/PC-5
  2026-07-30). Turn execution is split into order-aware phases, the player
  state machine lives in `src/systems/PlayerTurnController.gd`, the
  play/pause toggle gates visual playback while the simulation runs ahead
  under `RUN_AHEAD_LIMIT`, and `CONFIRM_ACTION` shows a damage/heal/elevation
  forecast sourced from the same `CombatResolver` math real resolution uses.
  BM-0 through BM-2 stabilize the command menu, playback pause,
  surface-accurate picking, and Spell/< Back navigation. They await
  in-window verification; see `implementation_plan.md`.
- **PC-3/BM-3 and POS-3 are implemented but still need in-window acceptance.**
  Legal empty and occupied centers cycle without free grid roaming; disallowed
  empty spell centers preview but cannot confirm, and area shapes/forecasts use
  authoritative resolver queries. BM-4 remains for camera-relative controls
  and broader visual accessibility work.
- **Mouse tile picking now uses dedicated rendered-surface hitboxes.** Verify it
  at multiple elevations and camera angles before considering it resolved.
- **The player input surface has now been exercised headlessly against the
  real scene**, closing most of the original gap. `TD-1` (2026-07-30,
  `debug/drive_battle.gd`) drives `Battle25D` through synthetic `InputEvent`s,
  but its occupied-only target assertions predate POS-3. POS-VALIDATE must
  replace those assertions with empty attack, empty-center spell, blocked-empty
  confirmation, zero-hit cast, and occupied-center coverage. Headless input
  still cannot establish appearance, animation feel, or camera-angle usability,
  so the specified in-window playthrough remains required.

## Content inconsistencies

- **`Purple Dungeon Slime` claims "immune to physical crits"** in its
  description, but no such mechanic exists. Now that Luck is live this is a
  visible inconsistency. Either implement the immunity or reword the
  description.
