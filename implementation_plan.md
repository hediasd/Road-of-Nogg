# Implementation Plan

Consolidated from `AUDIT_REMEDIATION_PLAN.md` and `PHASE4_DECISIONS.md` on
2026-07-29, when both were deleted along with `docs/AUDIT_COMPLETED.md`,
`docs/CAPSULE_MONSTERS_PLAN.md`, `docs/PLAYABLE_BATTLE_PLAN.md`, and
`docs/archive/BATTLE_RUNTIME_MIGRATION.md` as completed/superseded planning
documents. This file holds only what was still genuinely open at that point,
cross-checked against `docs/AUDIT_COMPLETED.md`'s resolution log so nothing
already-decided carried forward by mistake. Several `PHASE4_DECISIONS.md`
proposals (legacy roster promotion, race matchup rebalance, LUCK values,
Petrify's cooldown, guard/focus duration) were already decided and implemented
before deletion and are not repeated here.

There is no automated test suite in this repository right now (see
`docs/DEVELOPMENT.md`). Every item below must be verified manually by
launching the game and exercising the affected behavior.

## Conventions

- **Verify** lists what must be manually exercised before the item is done.
- **Risk** is the blast radius if the change is wrong.
- **Model** is the smallest model that can safely execute the item.

---

## Player command UI rework (PC-1 … PC-5)

Added 2026-07-29. Supersedes the former **P5-2b — Extract the player-turn
state machine**: that extraction is still required, but it is no longer a
behaviour-preserving refactor, because the turn model it would have preserved
is itself being replaced. P5-2b is absorbed into **PC-2** below.

### Problem

Three defects, in the order they must be fixed:

1. **The action economy is atomic.** `_submit_player_command()` assembles one
   `{move_path, action, target_id, …}` dictionary and fires a single
   `BattleSimulator.executeCommand()`, which resolves movement and the action
   together and then fires `ON_TURN_END`. The player therefore *previews* a
   destination, chooses an action from a position they are not yet standing
   in, and confirms both at once. Acting before moving is not expressible at
   all: `validateCommand()` always evaluates the action from the post-move
   destination.
2. **The menu is a button bar, not a menu.** `BattleUIBuilder` builds two
   horizontal rows — `Move | Attack | [spell OptionButton] | Cast | Wait` and
   `Confirm | Cancel | End Turn` — with a status label that prints internal
   state-machine identifiers at the player (`"MOVE_PREVIEW — select a blue
   tile"`). `Wait` and `End Turn` are near-duplicates. Arrow keys drive the
   grid cursor and never the menu, so there is no menu-space navigation.
3. **Pause stops the simulation.** `_on_play_toggled()` starts and stops
   `turn_timer`, which is what steps the simulation. `VisualActionQueue` has
   no pause concept. `GodotVisualAdapter.animation_queue_drained` and
   `queuedAnimationCount()` exist but have no consumers anywhere in the
   repository.

Defect 3 hides a latent bug that becomes load-bearing once pause is
decoupled: nothing gates the start of a player turn on the visual queue being
drained, so the menu can already open over a board that is still animating
earlier turns. Fixed in **PC-4**.

### Target design

Fire Emblem's presentation over Final Fantasy Tactics' semantics. FE locks the
player into move-then-act; the required behaviour is either order, which is
FFT's `Move / Act / Wait` model with each entry spent independently.

```text
Move        greyed once moved
Undo Move   present only while the move is spent and the action is not
Attack      greyed once acted
Magic    >  opens a second vertical column of spells
Pass        always enabled; ends the turn
```

Each selection resolves to completion — including its animation — and the menu
reopens with that entry spent. Both spent ends the turn automatically. `Pass`
ends it from any menu state. `Wait` and `End Turn` collapse into `Pass`.

**Movement is undoable; the action is not.** Decided 2026-07-29. Selecting a
destination commits and resolves immediately, with no confirm prompt — Fire
Emblem's feel — and the safety net is an `Undo Move` entry that rewinds the
unit to where the turn began.

Undo is affordable because a resolved move has no side effects to unwind:
`PassiveSkillResolver` exposes only `ON_TURN_END`, `ON_DEATH`,
`ON_DAMAGE_TAKEN`, and `ON_TARGETED`, so nothing in the game reacts to
movement, and under PC-1 the move does not reach the replay ledger until
`finishTurn`. Undo is therefore a position rewind plus a reverse walk emitted
through the existing `monster_moved` event — the visual queue animates it as
an ordinary move and needs no new action kind.

**Undo is withdrawn the moment an action resolves.** An attack or spell is
validated against range, line of sight, and elevation from the position it was
cast from; rewinding that position afterwards would retroactively falsify a
resolution that has already dealt damage. So `Undo Move` is offered while
`hasMoved and not hasActed`, in either order — a unit that acted first, then
moved, may still undo the move, because the action was resolved from the
pre-move tile and is unaffected by the rewind.

Attacks and spells keep an explicit confirm step, since damage cannot be
taken back. PC-5 puts the forecast on that step.

---

## PC-1 — Order-aware split turn execution in the simulator

Give `BattleSimulator` an incremental turn API so movement and the action can
resolve as separate, independently-timed steps while a turn stays a single
unit for history and replay.

1. Add `executeMovePhase(monsterID, path, source)`,
   `executeActionPhase(monsterID, action, targetID, spellSetIndex, spellIndex,
   source)`, and `finishTurn(monsterID)`. `finishTurn` is the sole caller of
   `passiveSkillResolver.fireEvent(ON_TURN_END, monsterID)` — it must fire
   exactly once per turn regardless of how many phases ran.
2. Track per-turn `hasMoved` / `hasActed` and reject a second phase of the
   same kind.
3. Add `undoMovePhase(monsterID)`, valid only while `hasMoved and not
   hasActed`. It restores the position recorded at turn start, clears the
   accumulated move path and `hasMoved`, appends an `undo_move` event to
   `state.history` for diagnostic fidelity, and emits `monster_moved` along
   the reverse path so presentation walks the unit back. It must not touch
   cooldowns, effects, or `ON_TURN_END`. Reject it once `hasActed` is set —
   see Target design for why.
4. Accumulate the phases into **one** `command` history event emitted at
   `finishTurn`, so `createReplaySnapshot()` and `BattleReplayRunner`'s
   one-command-per-turn loop keep working unchanged in shape. An undone move
   leaves no trace in that aggregate — the recorded `move_path` is whatever
   survives to `finishTurn`, so a replay reproduces the final turn rather than
   the player's deliberation.
5. Add an `order` field to the command dictionary (`"move_first"` default,
   `"act_first"`). `validateCommand()` must evaluate an `act_first` action
   against the **pre-move** position, and `executeCommand()` must resolve in
   the recorded order. Without this, an act-then-move turn replays as
   move-then-act and re-validates against the wrong tile.
6. Bump the replay snapshot to version 4; keep version 3 loading with
   `order` defaulting to `"move_first"`.
7. Rewrite `executeCommand()` as a composition of the phase calls so CPU
   brains, `executeTurn()`, and the replay runner keep one entry point and one
   contract. `undoMovePhase` is not part of that composition; it exists only
   for the interactive path.

**Files:** `src/battle_sim/BattleSimulator.gd`,
`src/battle_sim/BattleReplayRunner.gd`, `docs/ARCHITECTURE.md`

**Verify:** Run a full CPU vs CPU battle to a winner with no rejected
commands in the log; use Save Replay, then replay that snapshot and confirm it
reaches the same winner. Both must be done before PC-2 starts, because PC-2
has no other way to detect that the split broke CPU turns. `undoMovePhase`
has no CPU caller and cannot be exercised until PC-2 wires the menu entry;
confirm here only that it rejects when `hasActed` is set.

**Risk:** High. This is the controller-neutral command contract that CPU,
player, and replay all share; `ON_TURN_END` firing zero or twice per turn
would corrupt passives and cooldowns silently.

**Model:** Opus 5. Deciding where the turn boundary lives and how order is
recorded without breaking replay determinism is the actual work.

**Resolution (2026-07-29, commit `a7659a4`): done.** All seven items landed as
written. `executeCommand()` is now a composition of the phase calls, so CPU
brains and replay keep one entry point.

Verified with `debug/verify_pc1.gd` (gitignored scratch, not reinstated test
infrastructure): a seeded CPU vs CPU battle reproduces a byte-identical
1373-line battle log against a pre-change baseline; a 205-command replay
round-trips to identical HP, positions, alive sets, and turn count; and one
command is accepted as `act_first` while the identical command declared
`move_first` is refused with `invalid_attack_target`, confirming `order`
actually gates validation rather than just being recorded.

One trap for anyone extending this: `runFullBattle()` returns
`_determineWinnerByNumbers()` when it hits the round cap, which is a points
decision, not a wipeout. Comparing that return against a replay's
`checkWinCondition()` produces a false mismatch.

---

## PC-2 — Extract `PlayerTurnController` on the new phase model

Absorbs P5-2b. Extract the player state machine out of
`BattlePresentationController` into its own class, and replace its phases
while doing so — the old
`UNIT_SELECTED -> MOVE_PREVIEW -> ACTION_MENU -> TARGETING -> CONFIRM` chain
assumes one atomic submission at the end and cannot express the new model.

New phases:

```text
MENU -> MOVE_SELECT                    -> (resolve, animate) -> MENU
MENU -> TARGET_SELECT -> CONFIRM_ACTION -> (resolve, animate) -> MENU
MENU -> (Undo Move)                     -> (rewind, animate) -> MENU
MENU -> (Pass)                                               -> turn end
```

Movement has no confirm phase: selecting a reachable tile resolves it. `Undo
Move` is the safety net, and the controller withdraws that menu entry as soon
as `hasActed` becomes true.

The controller owns phase, `hasMoved` / `hasActed`, the turn-start position
that undo restores, pending selections, the menu's enabled/disabled model, and
submission through PC-1's API. It does not own scene lifecycle, camera,
pacing, or adapter wiring — those stay with `BattlePresentationController`,
which routes input to it.

After a resolved phase, the menu must not reopen until the visual queue for
that phase has drained; otherwise the player picks a target while the model is
still walking.

**Outstanding, carried over from the `VisualActionQueue` extraction:** manual
in-game confirmation that movement, attacks, spell casts, and defeats still
animate correctly was never performed. Do it as part of this item's
verification.

**Files:** `src/systems/BattlePresentationController.gd`, new
`src/systems/PlayerTurnController.gd`, `docs/ARCHITECTURE.md`

**Verify:** A Player vs CPU battle exercising every order — move then attack,
attack then move, move then cast, cast then move, Pass immediately, Pass after
moving, Pass after acting — plus cancel out of `MOVE_SELECT`,
`TARGET_SELECT`, and `CONFIRM_ACTION`, and a turn where both phases are spent
and the turn ends by itself. For undo specifically: move, undo, move somewhere
else, then attack, and confirm the unit ends the turn on the second
destination with full HP accounting intact; then confirm `Undo Move` has
disappeared from the menu once an action has resolved, in both the
move-then-act and act-then-move orders.

**Risk:** Medium-high. Interactive path, no automated coverage.

**Model:** Opus 5. The seam between the controller and the state machine is
not yet drawn, and the phase model is a design decision.

**Resolution (2026-07-29, commit `f1fe38b`): done, with one verification gap
carried into PC-3.** `src/systems/PlayerTurnController.gd` owns the phases, the
menu model (`menuEntries()`), and phase submission; the scene controller routes
input and reacts to `menu_changed`, `status_changed`, and `turn_finished`.
`BattleUIBuilder`'s rows were rewired onto the menu model as an interim
rendering — `Wait` and `End Turn` became `Pass`, and `Undo Move` was added.

Verified with `debug/verify_pc2.gd`, which drives the phase machine against a
stub adapter: every order, all three Pass timings, undo then re-move, cancel
from `MOVE_SELECT`/`TARGET_SELECT`/`CONFIRM_ACTION`, and the drain gate holding
the menu shut mid-animation.

**Still outstanding — the in-window playthrough.** No GUI automation is
available in this environment, so mouse ray-casting, keyboard routing, the
button wiring, and the animation confirmation carried over from the
`VisualActionQueue` extraction were not exercised in a real battle. The
headless harness covers the phase machine, not the input surface. PC-3 rebuilds
that surface anyway, so do this check as part of PC-3 rather than twice.

**Two notes for PC-3.** `menuEntries()` is the whole contract — id, label,
`enabled`, `visible` — so the widget needs no rules of its own. And the undo
window is exactly the gap between moving and acting: spending both phases ends
the turn, so `Undo Move` is never visible next to a spent `Attack`.

---

## PC-3 — Vertical command menu widget

Replace the two button rows with a keyboard/gamepad-navigable vertical menu
driven by PC-2's menu model.

1. New `src/presentation/PlayerCommandMenu.gd` building a vertical entry list
   with a selection cursor, disabled styling for spent entries, and `Pass`
   pinned last. The panel is anchored at a fixed screen position, not
   projected beside the unit (decided 2026-07-29 — the camera orbits and pans
   freely, so a following menu would drift and need clamping).
2. `Undo Move` appears and disappears rather than greying out, since it is
   meaningless before a move and forbidden after an action. Entries shifting
   position under the cursor is the cost; keep the cursor on a stable entry
   across a rebuild rather than resetting it to the top.
3. `Spell` opens a second vertical column listing spells with name, range, and
   remaining cooldown; unavailable spells are shown disabled rather than
   hidden. This replaces the `spell_option` `OptionButton` entirely.
4. Input, modal by phase: `MENU` takes up/down plus accept/cancel in menu
   space; `MOVE_SELECT` takes the four directions as grid-cursor movement with
   a live path preview; `TARGET_SELECT` cycles the valid-target set rather
   than free-roaming the grid. Mouse click stays available in every phase.
   Legal occupied target centers use yellow markers and a yellow cursor; the
   selected area footprint previews the resolver's authoritative shape. Retire
   the `M`/`A`/`S`/`W`/`E` hotkeys, or rebind them to menu entries — they must
   not bypass a phase.
5. Replace status text that names internal states with player-facing wording.

**Files:** `src/presentation/BattleUIBuilder.gd`, new
`src/presentation/PlayerCommandMenu.gd`,
`src/presentation/BattleCursorController.gd`,
`src/presentation/GodotVisualAdapter.gd`,
`src/systems/BattlePresentationController.gd`,
`src/systems/PlayerTurnController.gd`, `src/battle_sim/CombatResolver.gd`

**Verify:** Drive one complete Player vs CPU turn using only the keyboard, and
a second using only the mouse. Confirm spent entries grey out, `Spell` lists
cooldowns correctly, and cancel from the spell column returns to the root
menu. Confirm target cycling visits only yellow legal centers and area previews
match the tiles affected by resolution.

**Risk:** Medium-high. It is the entire player input surface and adds a
read-only affected-position query that must remain identical to spell resolution.

**Model:** Sonnet 5, once PC-2 has fixed the menu model and phase API.

**Resolution (2026-07-30):** PC-3 and BM-3 are the same item. The code is
implemented, including `Spell`, `< Back`, modal prompt-only targeting,
legal-target cycling, yellow target markers/cursor, and authoritative area
previews. Headless Godot startup and `git diff --check` pass; the full keyboard
and mouse Player vs CPU verification above remains mandatory before this item is
marked complete.

---

## PC-4 — Pause the visual queue, decouple simulation pacing

The play/pause toggle becomes a playback control over the visual queue. The
simulation no longer stops when it is pressed.

1. `VisualActionQueue.setPaused(bool)`: while paused, `startNext()` returns
   without dequeuing and the active tween is paused. On resume, the tween
   plays and `startNext()` runs.
2. **The watchdog must not fire against a paused tween.** A paused tween never
   emits `finished`, so the existing `SceneTreeTimer` would time out and
   force-finalize a still-visible action. Suppress `_complete(serial, true)`
   while paused and re-arm a fresh watchdog on resume. Re-arming at full
   duration is acceptable — the watchdog is stall recovery, not pacing.
3. Gate the start of every player turn on the queue being drained **and** not
   paused, using the already-present `animation_queue_drained` signal, which
   currently has no consumer. Without this the menu opens over a stale board.
4. Backpressure: throttle `turn_timer` while `queuedAnimationCount()` is above
   a high-water mark, resuming below it. Unthrottled, a paused queue lets the
   simulation run to the end of the battle in seconds and overflow
   `MAX_QUEUED_ACTIONS` (4096), which triggers `recover()` and discards the
   animations the player paused in order to watch. See the blocking question
   below on the bound.
5. Keep the pause button enabled during player turns; it is a view control
   now, not a turn control.

**Files:** `src/presentation/VisualActionQueue.gd`,
`src/presentation/GodotVisualAdapter.gd`,
`src/systems/BattlePresentationController.gd`, `docs/ARCHITECTURE.md`

**Verify:** In a CPU vs CPU battle, pause mid-move and confirm the model
freezes in place, the battle log stops advancing, no watchdog warning appears
in the output for at least 30 seconds, and resuming completes the same
movement rather than snapping. Then pause through a long stretch and confirm
no overflow error is pushed. Finally, in Player vs CPU, pause during CPU turns
and confirm the player menu opens only on a fully-caught-up board.

**Risk:** Medium-high. `VisualActionQueue` documents the invariants it exists
to hold at the top of the file; the serial/watchdog interaction is exactly
what breaks quietly.

**Model:** Opus 5 for the pacing and drain-gate design in items 3 and 4;
items 1 and 2 alone would be Sonnet 5 work, but splitting the file across two
sessions is not worth it.

**Resolution (2026-07-30): done.** Items 1, 3, and 5 had already landed
alongside PC-3. This session fixed item 2, corrected item 4, and verified the
lot with `debug/verify_pc4.gd` (gitignored scratch), which drives the queue
with real tweens and real frames.

Two defects were found and fixed:

- **`setPaused()` bumped `_serial`.** That orphaned the active tween's
  `finished` connection — empirically the only one that fires; the replacement
  connection the code added under the new serial never did. Every resumed
  action was therefore completed by watchdog recovery: 1150ms instead of the
  tween's own ~400ms, with a "stalled action" warning on every single resume.
  Pause now leaves the serial alone, which in turn makes the `timedOut and
  _paused` guard in `_complete()` load-bearing rather than defensive. Measured
  resume latency went from watchdog-bound to 373ms, and the warning is gone.
- **Backpressure stopped the turn timer.** Restarting it then depended on the
  `drained` signal, which only fires when the queue reaches *zero*, so the
  simulation stalled for a full playback of the backlog rather than resuming
  as soon as there was room. The timer now keeps ticking and re-checks, which
  is also self-healing if `drained` is ever missed. The bound is named
  `RUN_AHEAD_LIMIT`.

Worth knowing for anything else that touches tweens: **`Tween.is_valid()`
returns `true` for a killed tween**, so it cannot be used to detect one. The
resume path arms a watchdog specifically to cover that case.

**Verification gap, unchanged from PC-2 and PC-3:** no GUI automation is
available here, so the in-window checks in this item — pausing mid-move and
watching the model freeze, the battle log stopping, resuming completing the
same movement — were exercised headlessly at the queue level rather than by
eye in a running battle.

---

## PC-5 — Action forecast on confirm

`CONFIRM_ACTION` shows predicted outcome before commit: target name, expected
damage or healing, and any elevation modifier. Every mainline TRPG in this
genre shows a forecast, and it is the largest remaining usability gap after
the menu itself.

`DirectDamageRules` already owns the 110/100/90-percent elevation arithmetic
used by both real attacks and CPU estimates, so the forecast reads from the
same source the resolution does, not a parallel formula.

**Files:** `src/presentation/PlayerCommandMenu.gd` or a sibling panel,
`src/systems/PlayerTurnController.gd`

**Verify:** Attack the same target from equal, higher, and lower elevation and
confirm the forecast tracks the damage actually dealt in the battle log.

**Risk:** Low. Read-only against existing rules.

**Model:** Sonnet 5.

**Resolution (2026-07-30): done.** The bulk of this item — `forecast_changed`,
`CONFIRM_ACTION` wiring, and `_forecastText()` reading `calculateBasicDamage`
/ `calculateSpellDamage` / `calculateHeal` / `getElevationPercent` off
`CombatResolver` — had already landed in the same external session that did
PC-1 through PC-3. Review found and fixed one real defect in it.

**The bug:** the attack forecast called `calculateBasicDamage(attacker,
target)` without `is_simulation=true`. Every other estimator in the codebase
— `BattleCommandEvaluator`, `BerserkBrain`, `MageBrain`, `TacticalBrain`, and
this file's own spell-damage forecast — passes that flag so
`PassiveSkillResolver.applyDamageModifiers()` skips emitting
`passive_triggered`. Without it, merely highlighting an attack target and
reaching `CONFIRM_ACTION` fired a real `passive_triggered` event before
Confirm was ever pressed — invisible today only because
`GodotVisualAdapter._on_passive_triggered` happens to be an inherited no-op;
wiring that handler for anything, which is a natural next step now that
Resonance/crit UI is on the backlog, would have surfaced it as a false
"passive triggered" toast fired by hovering a target.

Verified with `debug/verify_pc5.gd` (gitignored scratch): forecast damage
matches actual damage dealt for a basic attack, a spell, and a heal;
elevation is checked with a matchup whose raw damage (5) is large enough for
the ±10% modifier to survive rounding (`floor((raw*pct+50)/100)`) — the
initial attempt used a raw-3 matchup where 100/110/90% all floor to the same
number, which would have passed even if elevation were never applied; and,
directly, that computing the forecast alone emits zero `passive_triggered`
events and writes zero `state.history` entries. PC-1/PC-2/PC-4 checks and the
seeded battle-log determinism check are unchanged.

**Two things worth knowing if this is touched again:**
- `Spell.targetType` defaults to `"single"` even for range-0 "Setup" spells
  (e.g. Mage Dragon's `Think`) that are functionally self-only by the tier
  contract in `docs/GAME_DESIGN.md` — `getSpellTargetsFrom` requires an enemy
  at that distance, which a range-0 spell can never produce. Filtering
  "is this spell aimable at the enemy" by `targetType == "self"` alone misses
  these; filter on `range <= 0` too, or on `getSpellTargetsFrom` returning
  something other than `[casterID]`.
- A crit or elemental-weakness roll can make an actually-resolved spell
  differ from its non-critical forecast — `calculateSpellDamage` deliberately
  never calls `_rollCritical()` (that's the RNG draw, gated to real
  resolution only), so the forecast is a floor, not always an exact
  prediction, for spells.

---

## PC decisions — resolved 2026-07-29

Resolved by the user on 2026-07-29. Recorded here so an executing agent does
not reopen them.

1. **Menu placement — fixed anchored panel.** Not projected beside the active
   unit. The camera orbits and pans freely, so a following menu would drift
   and need clamping; a fixed column still reads as the genre. Applies to
   PC-3.
2. **Run-ahead while paused — throttle at a high-water mark.** The simulation
   runs ahead a few turns' worth of queued actions and then waits, rather than
   running to the end of the battle. Uncapped run-ahead is the literal reading
   of "pause the queue, not the backend", but it overflows
   `MAX_QUEUED_ACTIONS` and `recover()` then discards precisely the animations
   the player paused to watch. Applies to PC-4.
3. **Movement undo instead of a movement confirm.** Selecting a destination
   resolves it with no confirm prompt; an `Undo Move` entry rewinds it. The
   action keeps its confirm, because damage cannot be taken back. Full
   reasoning and the withdrawal rule are in Target design; implementation in
   PC-1 item 3, PC-2, and PC-3 item 2.

Still open, and **not** blocking any item above:

4. **`act_first` for CPU brains.** Recommendation: player-only for now. AI
   proposals stay move-then-act and default `order` to `"move_first"`;
   teaching `BattleCommandEvaluator` to enumerate act-then-move candidates is
   a separate balance decision, not part of this rework.

---

## P4-2 — Minimal Resonance and critical UI

Nothing in `src/presentation/` references Resonance or criticals, so players
cannot see charge state, and crit/weakness hits look identical to normal ones.
`resonance_changed` reaches adapters and `ConsoleVisualAdapter` logs it, so the
data is available — only the 3D presentation is missing. Decision already
taken (recorded in the deleted `AUDIT_REMEDIATION_PLAN.md`): build it now,
minimally, by extending the existing `StatusEffectIcons` badge row rather than
inventing a new display.

1. `GodotVisualAdapter._on_resonance_changed(monsterID, element, oldCharge, newCharge, reason)`
   — currently the inherited no-op — should refresh the badge row for that
   monster.
2. Show the **highest** charged element and its charge (0-3), matching the
   rule in `GAME_DESIGN.md` that the highest bar grants the ATK/DEF bonus.
   Charge 0 shows nothing.
3. Tint by element using `BattleMeshFactoryScript.elementColor()`, which
   already maps every element to a colour.
4. Criticals: `monster_cast_spell`'s `damageLines` entries already carry
   `critical` and `weakness` booleans, and `_on_monster_attacked` has the
   damage figure. Distinguish a crit in the right-hand UI text at minimum.

`Walker of the Woods` has the only complete Wood ladder (`Gather` -> `Thornlash`
-> `Bramble Crown` -> `Roses at Summers End`), so it is the one monster that
can currently reach charge 3 and exercise every display state.

**Files:** `src/presentation/GodotVisualAdapter.gd`,
`src/presentation/StatusEffectIcons.gd`

**Verify:** A real battle with `Walker of the Woods` deployed, casting through
its full spell ladder and confirming the indicator tracks 0->1->2->3->0.

**Risk:** Low. Additive presentation; no simulation code changes.

**Model:** Sonnet 5. The design decision is made and the data path already
exists.

**Note:** a dedicated element-coloured charge bar under the HP bar, plus
crit/weakness damage-number styling, remains a richer option, explicitly
deferred rather than rejected. Reconsider if the minimal version proves
insufficient in play.

---

## Author the Level 2-4 spell pool for the remaining nine elements

Wood is the only element with a complete Level 1-4 ladder (piloted first to
validate the ladder end to end before committing further). The other nine
elements (fire, ice, water, darkness, earth, steel, thunder, light, wind) stop
at Level 1, so Resonance can never exceed charge 1 for any monster that isn't
Wood-affiliated.

The tier design contract that was an open question when the pilot started is
now settled and documented in `docs/GAME_DESIGN.md` under "Tier contract":

| Level | Role | Required shape |
|---|---|---|
| 1 | Setup | Targets the caster at range 0. Self-centred AOE allowed when explicitly defined. |
| 2 | Engage | Single-target, range 1 or greater. |
| 3 | Commit | Area spell, cooldown 3 or greater. |
| 4 | Ascension | Area spell, radius 2 or greater, cooldown 6 or greater. Requires three charge and empties the bar. |

Remaining work is repeatable authoring against this contract: author L2/L3/L4
spells per element, assign a complete vertical set to a monster with the right
element(s), and verify the ladder in real play.

**Files:** `data/monsters.json`, `src/factories/SpellReferences.gd`

**Verify:** Manually play a battle with the newly-completed element's monster
and confirm the ladder advances 0->1->2->3->0 as designed.

**Risk:** Medium — content/balance work without automated catalog validation
right now (see `docs/MONSTER_CATALOG_SCHEMA.md`), so a malformed spell set
will only surface at runtime.

**Model:** Sonnet 5 per element, given the contract above is fixed. Flag any
case that seems to need a contract exception rather than resolving it
unilaterally.

---

## Growth values — blocked on a prerequisite

Every monster's `HP_GROWTH`/`ATK_GROWTH`/`DEF_GROWTH` is `0`, and no
production code ever spawns a monster above level 1 — `BattleSetupFactory`
calls `spawnMonster(name, team, pos)` with the default `level = 1`. Growth
values are doubly inert: even non-zero growth would change nothing until
something varies level.

**Recommendation: keep deferring** until there's a reason for level to vary
(campaign progression, a level control in setup, or an ascension system).
Assigning growth numbers now would be unverifiable and untestable.

**Blocking decision needed from the user:** where does monster level come
from? This is a product question, not a balance table, and nothing below it
can proceed without an answer.

---

## Kickatoo's MOVE = 8 — unconfirmed outlier

`Kickatoo` is the sole authored-roster outlier at `MOVE = 8`; the next highest
is 5. Never confirmed as intentional — plausible as a deliberate
high-mobility scout, plausible as a typo for 5.

**Blocking decision needed from the user:** intentional, or should it be
corrected to 5 (or some other value)?

**Files:** `data/monsters.json`

**Risk:** Low — a single data value.

**Model:** Haiku 4.5, once the value is confirmed.

---

## Purple Dungeon Slime's description is inconsistent with implemented mechanics

`Purple Dungeon Slime`'s description claims "immune to physical crits," but no
such immunity mechanic exists anywhere in the codebase. This was a dormant
inconsistency before Luck/criticals went live; now that critical hits are
live, it is a visible one.

**Blocking decision needed from the user:** implement the immunity as a real
mechanic, or reword the description to match actual behavior?

**Files:** `data/monsters.json`, and `src/battle_sim/CombatResolver.gd` only if
the immunity option is chosen.

**Risk:** Low if reworded; Medium if implemented as a new mechanic (touches
crit resolution).

**Model:** Haiku 4.5 for a reword; Sonnet 5 if implementing real immunity.

## BM-0 through BM-2 ? implementation resolution (2026-07-29)

Implemented as one scoped follow-up after the player-menu audit; in-window
verification remains outstanding.

- **BM-0:** separated forecast output from instructions, removed obsolete menu
  callback registrations, kept playback controls usable during player turns,
  and made pending player turns wait for an unpaused, drained visual queue.
- **BM-1:** replaced the `y = 0` click approximation with a dedicated collision
  surface for every rendered board tile; mouse movement previews a move before
  click commits it.
- **BM-2:** renamed the root entry to `Spell`, made Spell a second visible
  column, added `< Back`, preserved root/spell selections independently, and
  added keyboard and right-click back paths.

**Verification gap:** Headless Godot startup and `git diff --check` passed for
the scoped changes. Real Player vs CPU checks at rotated cameras and differing
elevations are still mandatory before any BM item is marked done.

---

## TD-1 — Headless input driver for the player command surface

Every PC and BM item carries "in-window verification outstanding," and it has
survived four sessions because no GUI automation was thought to be available.
That premise is wrong: the real scene is fully drivable headless. This item
builds the harness that closes the gap.

**Confirmed by probe on 2026-07-30 — do not re-derive these:**

- `load("res://scenes/Battle25D.tscn").instantiate()` added to `root` runs
  headless. After ~20 `await process_frame`, calling `_on_setup_confirmed()`
  reaches `lifecycle == BATTLE` with a live `sim`, 8 monsters, 16x8 board.
- **`root.push_input(event)` genuinely reaches `_input()`** — verified by
  pushing `KEY_SPACE` and observing `battle_ui["canvas"].visible` flip. This is
  the whole premise of the item and it holds.
- **Raycasts must use the SubViewport's world**:
  `scene.retro_renderer.world_root.get_world_3d().direct_space_state`. That
  returns `TilePickBody` for a downward ray. `scene.get_world_3d()` is the main
  window's world and returns nothing — the board is not in it.
- Default `battleMode` is `cpu_vs_cpu`. Select Player vs CPU before confirming,
  via `_select_option_by_metadata(setup_ui["mode_option"], "player_vs_cpu")`.
- **There is no rendering headless.** `get_texture().get_image()` returns null
  under the dummy driver. Assert on state, never on pixels. Screenshots are
  Tier 2 and out of scope here.

**End state:** `debug/drive_battle.gd` (gitignored scratch, matching the
existing `debug/verify_*.gd` pattern — this is not reinstated test
infrastructure) starts a Player vs CPU battle and drives a full player turn
through synthetic input only, asserting after each step. It must cover what the
stub-adapter harnesses structurally cannot reach:

1. Keyboard menu navigation — `ui_up`/`ui_down` move the selection,
   `ui_accept` activates, `ui_cancel` backs out.
2. The `Spell` column: opening it, `< Back`, right-click back, and that root
   and spell selections are preserved independently (BM-2).
3. Mouse tile picking through `_world_pick` at more than one elevation, using
   the SubViewport world above (BM-1). Confirm a click on a reachable tile
   commits the move and a click on an unreachable one is rejected.
4. Target cycling: legal occupied targets only, no free grid roaming, invalid
   clicks rejected (BM-3/PC-3).
5. That `player_turn.phase` and `menuEntries()` track correctly across
   move-then-act, act-then-move, undo, and pass.

**Verify:** `./Godot_v4.4-stable_win64.exe --headless -s debug/drive_battle.gd`
prints a pass/fail summary in the same shape as `verify_pc5.gd`. Then re-run
`verify_pc1/pc2/pc4/pc5.gd` and the seeded `scripts/demo_battle.gd` log
comparison to confirm nothing regressed.

**Expect the first run to fail.** None of this path has ever been executed. The
deliverable is the harness plus a written list of what it found — not a green
check. Report failures; do not fix production code and the harness in the same
session, or a harness bug and a real bug become indistinguishable.

**Escalation guardrail:** if making input reach a handler requires restructuring
input routing in `BattlePresentationController` (production code), stop and hand
back. Reshaping the real input path is an architectural change and is not in
scope for a test harness.

**Files:** `debug/drive_battle.gd` only. No production code.

**Risk:** Low. Gitignored scratch file, nothing ships.

**Model:** Sonnet 5. Single file, stated end state, zero blast radius; the
remaining unknowns are empirical iteration rather than design.

**Resolution (2026-07-30): done.** `debug/drive_battle.gd` exists and passes
all five numbered checks against the real `Battle25D` scene. Two corrections
to the plan's own confirmed-by-probe notes, found while building it:

- `push_input()` lives on `Viewport`/`Window`, not `SceneTree`. Call it as
  `root.push_input(event)` (`root` is `SceneTree.root`, a `Window`) — not
  `self.push_input(...)`. The plan's probe notes already said this correctly;
  the first draft of the driver called it on the scene node by mistake, which
  is a harness bug, not a finding.
- `menuEntries()`'s `attack` entry is enabled whenever the action phase is
  unspent, regardless of whether any target is actually in range —
  `_enterTargetSelect()` falls back to `MENU` gracefully when
  `getBasicAttackTargetsFrom()` is empty. A precondition of "Attack is
  selectable, therefore an adjacent enemy exists" is wrong; the driver instead
  places an enemy adjacent to the active unit via direct `state.moveMonsterTo`
  surgery before giving any input (see `_forcePlayerAdjacentToEnemy()`),
  matching how `verify_pc2.gd`/`verify_pc5.gd` already rig fixture geometry.
  Default deployment slots put the two teams on opposite sides of the map, so
  this is necessary for checks 4, 5a, and 5b regardless of harness design —
  Attack is never actually reachable on turn one otherwise.

**One genuine finding, not a harness bug — reported, not fixed, per this
item's own instruction not to mix the two:** at headless's default viewport
(`root.get_visible_rect()` settles to roughly 64x64 once a battle starts, not
the 100x100 a very early probe saw), `BattleUIBuilder`'s HUD panels are
positioned with fixed pixel offsets sized for a normal desktop window. At that
tiny scale they cover nearly the whole screen, and since they carry Godot's
default `MOUSE_FILTER_STOP`, Godot's GUI layer consumes a click or hover
inside their rect during normal input processing — before
`BattlePresentationController._unhandled_input()` ever sees the event. A
screen point that `_mouse_to_battle_coord()` resolves correctly when called
directly can therefore be **unreachable by any real `InputEvent`**, which is
exactly what happened when check 3 first tried an elevated tile: the point the
scan found sat under the top HUD strip.

Confirmed by temporarily instrumenting `_unhandled_input()`'s mouse-motion
branch with trace prints, observing they never fired for the occluded point,
walking the `battle_ui["canvas"]` Control tree to find the two panels
(`topHud`'s inner `PanelContainer` and the left info panel) whose
`get_global_rect()` covered it, and reverting the instrumentation completely
(`git status` clean before and after — verified both times) once the cause
was located. The driver's `_buildTileScreenMap()` now excludes any point
occluded by a non-`MOUSE_FILTER_IGNORE` Control, so it only offers the harness
screen points a real click could also reach.

This is real and structural — the top/bottom screen strips are permanently
under the HUD at *any* window size, since the offsets are fixed pixels, not
proportional — but its practical severity is scale-dependent. At a normal
desktop window the clear board area dwarfs the HUD strips and this is
unremarkable, ordinary HUD-over-3D-scene occlusion. It only became load-
bearing here because headless's viewport is a tiny fraction of any real
window. Whether it is worth a production fix (e.g., excluding HUD rects from
`isWalkable`-adjacent tile picking, or simply accepting it as expected HUD
behavior) is a product call, not something this item should decide — recorded
in `BACKLOG_LONGTERM.md` rather than acted on.

**Verify:** all four `verify_pc*.gd` harnesses and the seeded
`scripts/demo_battle.gd` log comparison were re-run after `drive_battle.gd`
was finished; all pass, and the demo log hash
(`ed22caa8dfeb83728bd3d9a35803794b`) is unchanged from the very first baseline
captured for PC-1 — nothing regressed.

---

## Battle UI restyle (UI-1 … UI-8)

Added 2026-07-30. The visual and interaction contract is
[`docs/UI_DESIGN.md`](docs/UI_DESIGN.md) — read it before executing any item
below; these items are the delivery schedule, not the specification.

### Problem

The battle HUD is procedurally built with no `Theme` resource anywhere in the
repository. Every colour is a literal at its construction site, the same
`StyleBoxFlat` is duplicated across `BattleUIBuilder._styleHudPanel()` and
`PlayerCommandMenu._style_panel()`, and font colours are per-label
`add_theme_color_override` calls. Restyling is therefore an N-file edit with no
single source of truth.

Two structural defects block the target design specifically:

1. **Selection is a text string.** `PlayerCommandMenu` encodes the cursor as a
   `"› "` prefix on the row's label, so `moveSelection()` calls
   `_rebuild_root()`, which frees and reconstructs every row on each keypress.
   No cursor can be animated across that rebuild.
2. **Game UI and developer UI share one `CanvasLayer`.** `SPACEBAR` toggles
   `battle_ui["canvas"].visible`, hiding the player's command menu along with
   the debug bar, so there is no way to screenshot the game as a player sees it.

Ordering below is a genuine dependency chain: UI-1 is the token source every
later item reads, UI-2 must land before UI-5 or the two rewrite
`BattleUIBuilder` in conflict, and UI-5 needs both UI-3 and UI-4 to exist.

---

## UI-1 — Theme foundation and design tokens

Create `src/presentation/theme/NoggTheme.gd`: the token constants from
`docs/UI_DESIGN.md` §3 plus `build_game_theme() -> Theme` and
`build_dev_theme() -> Theme`.

1. Declare every token in §3 as a `const`. These become the only colour
   literals permitted anywhere under `src/presentation/`.
2. `build_game_theme()` populates `Panel/panel`, `Label/font`,
   `Label/font_size`, `Label/font_color`, `Label/font_outline_color`,
   `Label/outline_size`, and the container separation constants. Load
   `assets/Fonts/Shining Force 2.ttf` as a `FontFile` with antialiasing,
   hinting, and subpixel positioning all disabled — it is a pixel font and will
   smear otherwise. Integer sizes only.
3. `build_dev_theme()` uses `Roboto-Regular.ttf` at 13, `DEV_FILL`,
   `DEV_BORDER`, square corners, no outline. It must look plainly unlike the
   game theme; that is its whole job.
4. Add `GAME_LAYER = 10`, `DEV_LAYER = 20`, `CRT_LAYER = -20` as named
   constants with the §10 rationale in a comment.
5. Add `build_window_frame() -> NinePatchRect` returning the configured
   `MenuFull.png` 9-patch: `patch_margin_*` 16, `draw_center = false`,
   `mouse_filter = IGNORE`, `self_modulate = FRAME_ACTIVE`.

Do not apply the themes to anything yet. This item ships a resource factory and
nothing else, so a failure here cannot be confused with a layout failure later.

**Files:** `src/presentation/theme/NoggTheme.gd` (new), `docs/UI_DESIGN.md`
(correct §3 if a token proves unworkable).

**Verify:** Add a throwaway `debug/preview_theme.gd` that instantiates one
`PanelContainer` per theme with a few labels and a frame, and screenshot it.
Confirm the pixel font is crisp at integer sizes, the outline is visible over a
light background, and `draw_center = false` genuinely lets the fill show
through the frame ring.

**Risk:** Low in blast radius — nothing consumes it yet. High in leverage:
every later item inherits these decisions, and a token set that reads badly
over the 3D scene costs a rework of UI-3, UI-5, and UI-7.

**Model:** Opus 5. Choosing a palette that survives an arbitrary 3D background,
and committing to the tint-driven active/inactive scheme that traits 1 and 3
both depend on, is a design decision rather than transcription.

---

## UI-2 — Split the game canvas from the developer canvas

Restructure `BattleUIBuilder.build()` to return two `CanvasLayer`s and rebind
`SPACEBAR`.

1. Build `game_canvas` at `GAME_LAYER` and `dev_canvas` at `DEV_LAYER`, each
   with its theme from UI-1 assigned to a root `Control`.
2. Move the top bar (pause, speed slider, new battle, graphics, screenshot,
   save replay) and the graphics menu onto `dev_canvas`. Move the command menu,
   action panel, bottom HUD panels, and the battle log onto `game_canvas`.
   Existing panel styling stays as-is here — UI-3 and UI-7 restyle it.
3. Return both under `"game_canvas"` / `"dev_canvas"`. Keep every other
   dictionary key the same so `BattlePresentationController`'s call sites keep
   working.
4. In `BattlePresentationController._input()`, `SPACEBAR` toggles
   `dev_canvas.visible` only. Game UI visibility becomes lifecycle-driven, as
   it already is via `action_panel`.
5. The battle-log toggle and graphics toggle both live on the dev bar but the
   log renders on the game canvas — keep the existing mutual exclusion between
   them working across the layer boundary.

**Files:** `src/presentation/BattleUIBuilder.gd`,
`src/systems/BattlePresentationController.gd`.

**Verify:** Start a battle, reach a player turn, press `SPACEBAR`. The debug
bar and graphics menu must disappear while the command menu, bottom HUD, and
cursor stay fully interactive — take a screenshot in that state and confirm it
looks like a player-facing frame. Press `SPACEBAR` again and confirm the
graphics menu returns in its prior toggle state, not forced open.

**Risk:** Medium. Touches every UI wiring point in the controller. The failure
mode is silent — a panel parented to the wrong canvas only reveals itself when
`SPACEBAR` is pressed.

**Model:** Sonnet 5. Multi-file with a fully stated end state and no open
design questions.

---

## UI-3 — The `NoggWindow` widget

Implement `src/presentation/theme/NoggWindow.gd` per `docs/UI_DESIGN.md` §4.

1. `class_name NoggWindow extends PanelContainer`. Composition is exactly the
   §4 diagram: `StyleBoxFlat` body, `MarginContainer` for content clearing the
   16px frame, `NinePatchRect` frame added last so it draws on top.
2. `set_active(active: bool)` tweens the frame's `self_modulate` between
   `FRAME_ACTIVE` and `FRAME_INACTIVE` over 0.12 s.
3. `open()` / `close()` with the §4 scale-and-fade tweens. `close()` must be
   awaitable or emit `closed` so callers can sequence teardown.
4. `set_row_capacity(rows: int)` fixes `custom_minimum_size.y` from the theme's
   row height and font metrics, so a window's height is a function of capacity
   and not of content. Trait 6 depends on this.
5. `add_row(label: String, value: String = "", disabled: bool = false)`
   building the two-column `HBoxContainer` of trait 4 — label left, value right
   in `TEXT_ACCENT`, ellipsis truncation on overflow. Rows are plain `Control`s,
   never `Button`s; §5 explains why.
6. Expose `row_rect(index)` so UI-4's cursor can position against a row without
   reaching into the window's children.

**Files:** `src/presentation/theme/NoggWindow.gd` (new).

**Verify:** Extend `debug/preview_theme.gd` to show two `NoggWindow`s side by
side over the live 3D battle scene, one active and one inactive, one at 8-row
capacity holding 3 rows. Confirm the fill is translucent and the frame is not,
the capacity window does not shrink, long values ellipsise, and `set_active`
reads clearly at a glance.

**Risk:** Medium. Every game window is this widget; a layout bug here appears
seven times over.

**Model:** Sonnet 5. UI-1 settled the look and §4 fixes the composition, so
what remains is careful Godot container work against a written spec.

---

## UI-4 — The `MenuCursor` node

Implement `src/presentation/theme/MenuCursor.gd` per `docs/UI_DESIGN.md` §5.

1. `class_name MenuCursor extends Control`, drawing the gold cursor in
   `CURSOR`. Draw it with `_draw()` as a filled triangle roughly 10x12 px — no
   art asset exists and none is required.
2. Continuous idle bob: 2 px either side on `position.x`, 0.6 s period, sine,
   looping, started in `_ready()` and never stopped.
3. `move_to_row(rect: Rect2)` tweens `position.y` to the row's vertical centre
   over 0.09 s with `EASE_OUT` / `TRANS_CUBIC`. Any in-flight move tween is
   killed first, not queued — held arrow keys must track rather than drain a
   queue. The bob tween is independent and must survive the kill.
4. `snap_to_row(rect: Rect2)` for the no-animation case (window just opened,
   page just turned).
5. `set_visible_cursor(bool)` for handing focus to a child window.

This item ships the node only. UI-5 is what parents it into a menu.

**Files:** `src/presentation/theme/MenuCursor.gd` (new).

**Verify:** In `debug/preview_theme.gd`, place a cursor in an 8-row
`NoggWindow` and drive `move_to_row` from arrow keys. Confirm the bob never
stops, holding an arrow key produces continuous tracking with no visible
queueing, and killing the move tween mid-flight does not freeze the bob.

**Risk:** Low. Self-contained node, no consumers until UI-5.

**Model:** Haiku 4.5. Single new file, every number specified, no dependency
beyond UI-1's `CURSOR` token.

---

## UI-5 — Rebuild `PlayerCommandMenu` on windows and cursor

The architectural item. Replace the panel-with-two-columns with stacked sibling
windows and a cursor, and separate rebuild from selection.

1. **Enforce the §5 rule:** content changes rebuild rows, selection changes
   move the cursor, and neither path calls the other. `moveSelection()` must
   not call `_rebuild_root()`. Delete the `"› "` string-prefix mechanism
   entirely.
2. Replace `_root_column` / `_spell_column` with two `NoggWindow`s. The spell
   window opens to the right of the command window; the command window calls
   `set_active(false)` while it is open, and `set_active(true)` on close. It
   does not hide, move, or resize.
3. Each window owns a `MenuCursor`. Opening the spell window hides the command
   window's cursor and snaps the spell cursor to its default row — the cursor
   does not fly between windows.
4. Rows become plain `Control`s. Disabled rows render in `TEXT_DIM`, are
   skipped by keyboard movement, and are inert to hover and click, but stay
   visible.
5. **Mouse input, per §6.** Hover moves the cursor without activating; left
   click moves then activates; wheel moves one row; right click cancels. The
   cursor position stays the single selection truth — mouse and keyboard must
   never disagree about what is selected.
6. Keep `entry_activated` and `spell_activated` signal shapes unchanged so
   `BattlePresentationController._on_command_menu_entry` /
   `_on_command_menu_spell` need no edit. Mouse routing is new wiring in
   `_unhandled_input` alongside the existing `ui_up` / `ui_down` / `ui_accept`
   handling.

**Files:** `src/presentation/PlayerCommandMenu.gd`,
`src/systems/BattlePresentationController.gd`,
`src/presentation/BattleUIBuilder.gd`.

**Verify:** Reach a player turn. Drive the full tree — root, into `Magic`, back
out, activate a spell — with the keyboard only, then repeat with the mouse
only, then alternate mid-menu and confirm the cursor never disagrees with the
last input device. Confirm the command window dims rather than disappears while
the spell window is open. Confirm a spent `Move` stays visible and dim, and
that keyboard movement skips it while the mouse cannot activate it.

**Risk:** High. This is the interactive path for every player turn, and it
replaces the input model rather than extending it. A cursor desync between
mouse and keyboard is the specific regression to watch for.

**Model:** Opus 5. Separating rebuild from selection is a structural change to
the menu's state model, and the mouse/keyboard reconciliation in §6 is a design
contract rather than a transcription.

---

## UI-6 — Paging

Add fixed-capacity paging to `NoggWindow` per `docs/UI_DESIGN.md` §7.

1. `NoggWindow` takes the full row set and slices it by `row_capacity` (8).
   `page`, `page_count`, `next_page()`, `prev_page()`, circular in both
   directions.
2. The footer is its own small `NoggWindow` reading the page indicator,
   horizontally centred and overlapping the parent's bottom border by half its
   height. It is absent — not disabled — when `page_count == 1`.
3. Cursor movement past a page boundary turns the page and snaps the cursor to
   the first (or last) row of the new page. Use `snap_to_row`, not
   `move_to_row`; tweening across a page turn reads as a glitch.
4. `ui_left` / `ui_right` page. Clicking the footer arrows pages.
5. Wire into UI-5's command and spell windows.

**Files:** `src/presentation/theme/NoggWindow.gd`,
`src/presentation/PlayerCommandMenu.gd`,
`src/systems/BattlePresentationController.gd`.

**Verify:** Give a monster enough spells to exceed 8 — temporarily, via a data
edit reverted before commit — and confirm the footer appears, pages wrap in
both directions, the cursor snaps rather than tweens across a turn, and the
footer disappears entirely at 8 or fewer.

**Risk:** Medium. Off-by-one page arithmetic interacting with disabled-row
skipping is the likely bug, and it is only reachable with a long list.

**Model:** Sonnet 5. Multi-file with a stated end state; the design questions
were settled in §7.

---

## UI-7 — Restructure the bottom HUD as game windows

Replace the two 220x150 `PanelContainer`s and their newline-joined labels with
the docked windows of `docs/UI_DESIGN.md` §8.

1. Actor status becomes a 6-row `NoggWindow` docked bottom-left; target becomes
   its mirror bottom-right. Both are fixed size and never resize with content.
2. Replace the single-string stat formatting in
   `BattlePresentationController._update_selection_ui()` with real two-column
   rows: name as a heading, then `HP`, `ATK/DEF`, `SPD/MOV`, `Elements`.
3. With values now individually addressable, colour HP in `TEXT_ACCENT` below
   one third and hold `TEXT_PRIMARY` above it. This is the payoff for dropping
   the string formatting and is the acceptance criterion for trait 4.
4. The target window shows an empty frame when there is no target — it does not
   hide. A window appearing and disappearing at the corner of the eye during
   cursor movement is worse than an empty one.
5. Add the prompt window (top-centre, 1 row) and move the forecast out of
   `PlayerCommandMenu` into its own window above the command window. Today
   `setStatus` prints state-machine text into the menu panel; the prompt window
   replaces that surface.

**Files:** `src/presentation/BattleUIBuilder.gd`,
`src/systems/BattlePresentationController.gd`,
`src/presentation/PlayerCommandMenu.gd`.

**Verify:** Run a battle through several turns. Confirm the actor window does
not resize between a monster with 3 elements and one with none, the target
window shows an empty frame with no target selected, HP recolours as a unit is
damaged past one third, and the forecast appears only on a confirm step.

**Risk:** Medium. `_update_selection_ui` is called from several event paths;
missing one leaves a stale window rather than an obviously broken one.

**Model:** Sonnet 5. Mechanical once §8 fixes the taxonomy, but it spans three
files and several call sites.

---

## UI-8 — Make CRT layering deliberate

1. Replace the literal layer numbers in `RetroRenderController` and
   `BattleUIBuilder` with `NoggTheme.CRT_LAYER` / `GAME_LAYER` / `DEV_LAYER`,
   carrying the §10 rationale as a comment at the constant, not at each use.
2. Add a `ui_through_crt` toggle to the graphics menu. When on, the game canvas
   moves below the CRT overlay so the UI takes scanlines, mask, and vignette.
   Default off. The dev canvas is never affected.
3. Persist it alongside the existing graphics parameters.

**Files:** `src/presentation/RetroRenderController.gd`,
`src/presentation/BattleGraphicsMenu.gd`,
`src/presentation/BattleUIBuilder.gd`,
`src/systems/BattlePresentationController.gd`.

**Verify:** Toggle `ui_through_crt` during a player turn at high scanline
strength. Confirm the game UI visibly gains and loses the CRT treatment, the
dev bar never does, and the command menu stays interactive across the toggle.

**Risk:** Low. Isolated, reversible, and visible the instant it is wrong.

**Model:** Sonnet 5. Four files, but each edit is small and the end state is
fully stated.
