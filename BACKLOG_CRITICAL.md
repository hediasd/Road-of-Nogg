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

## AI deliberation blocks the frame

Reported from play on 2026-08-01 as "the game is lagging" in CPU vs CPU, and
confirmed by measurement. The contract is in `docs/ARCHITECTURE.md` under
"Frame budget: deliberation must not block presentation" — read that before
acting on this.

`_advance_battle()` runs on the main thread and calls `brain.decideTurn()`
inline, so every AI turn is computed inside a frame and the frame lasts as long
as the decision. Measured headless (so excluding render cost) on seed 42:
idle frames 6.9 ms median, frames carrying a turn 24 ms median at 1 turn/s and
31 ms median / 75 ms max at 8 turns/s. At the higher playback speeds 4.1% of
frames miss 60fps and 1.9% miss 30fps.

A first pass on 2026-08-01 cut the cost per decision from 103 ms to 36.5 ms
(bounded spell-center scans, hoisted per-tile revalidation, short-circuited
threat map) with a byte-identical seeded demo log. That bought headroom; it did
not remove the coupling, and the coupling is what matters, because candidate
counts grow every time the AI gets smarter.

**The fix is affordable because the seam already exists.** `decideTurn()` is
verified pure — six consecutive calls mutate nothing, draw no RNG, emit no
events, and return the same command — so a decision can be computed off the
frame and applied through `executeCommand()` on the main thread in turn order,
with determinism and the replay ledger untouched.

**Not started.** It is an architectural change (worker task or time-sliced
evaluator, plus the ownership rules for reading `BattleState` while a task is
in flight) and wants a planned item with a model assignment, not an incidental
edit. Do it before, not after, the next significant increase in AI depth.

## Content inconsistencies

- **`Purple Dungeon Slime` claims "immune to physical crits"** in its
  description, but no such mechanic exists. Now that Luck is live this is a
  visible inconsistency. Either implement the immunity or reword the
  description.
