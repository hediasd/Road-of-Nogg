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
  surface-accurate picking, and Spell/< Back navigation, and their in-window
  verification landed with POS-VALIDATE on 2026-07-31; see
  `implementation_plan.md`.
- **PC-3/BM-3 and POS-3 have passed headless in-window acceptance.**
  POS-VALIDATE (2026-07-31) drove the real `Battle25D` scene through synthetic
  input for legal empty and occupied centers, target cycling with no free grid
  roaming, blocked-empty confirmation, a zero-hit `Dark Nova` cast, mouse
  picking across two elevations and two rotated camera yaws, and both phase
  orders. BM-4 remains for camera-relative controls and broader visual
  accessibility work.
- **`debug/drive_battle.gd` now covers ten checks, not TD-1's five.** Its
  occupied-only target assertions were replaced with positional ones, and it
  gained TYPE-2 reference/lifecycle coverage, TYPE-3 animation-flow and
  pause/resume coverage, and POS-3's empty-center flow.
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
  would guard a code path that does not exist. See `implementation_plan.md`.
- **No monster `DESCRIPTION` is read by any production code.** 11 of 28
  monsters carry one and no player has ever seen them, which is how the Slime's
  claim drifted from the implementation unnoticed. The other 10 have never been
  checked against actual mechanics; worth a sweep when descriptions are
  surfaced in the UI.
