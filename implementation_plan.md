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

**Model:** Opus 5 / GPT Sol. Deciding where the turn boundary lives and how order is
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

**Model:** Opus 5 / GPT Sol. The seam between the controller and the state machine is
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

**Model:** Sonnet 5 / GPT Terra, once PC-2 has fixed the menu model and phase API.

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

**Model:** Opus 5 / GPT Sol for the pacing and drain-gate design in items 3
and 4;
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

**Model:** Sonnet 5 / GPT Terra.

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

**Model:** Sonnet 5 / GPT Terra. The design decision is made and the data path already
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

**Model:** Sonnet 5 / GPT Terra per element, given the contract above is fixed. Flag any
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

**Model:** Sonnet 5 / GPT Terra, once the value is confirmed.

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

**Model:** Sonnet 5 / GPT Terra either way — a reword and a real immunity
mechanic sit in the same tier.

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

**Model:** Sonnet 5 / GPT Terra. Single file, stated end state, zero blast radius; the
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

## Battle UI restyle (UI-1 … UI-9)

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
   `assets/Fonts/shining-force-ii-small.otf` at body size 24 as a `FontFile`
   with antialiasing,
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

**Model:** Opus 5 / GPT Sol. Choosing a palette that survives an arbitrary 3D background,
and committing to the tint-driven active/inactive scheme that traits 1 and 3
both depend on, is a design decision rather than transcription.

**Resolution (2026-07-30): done.** All five items landed.
`src/presentation/theme/NoggTheme.gd` holds the tokens, both Theme factories,
the layer constants, and `build_window_frame()`. Verified by rendering
`debug/PreviewTheme.tscn` (gitignored scratch, not reinstated test
infrastructure) over a green-to-yellow gradient plus a pure-white block — the
worst case for both the translucent fill and the font outline.

Confirmed working: the pixel font is crisp at 16px with smoothing disabled; the
outline carries white text directly on white; `draw_center = false` genuinely
lets the translucent body show through the frame ring; the frame's
active/inactive tint is legible at a glance; and an 8-capacity window holding 3
rows does not shrink.

Three findings changed the spec, all folded into `docs/UI_DESIGN.md` and into
UI-3 and UI-6 above:

1. **A `Container` cannot be the window root.** `PanelContainer` force-fits
   every child into its content rect — including the frame — so the ring drew
   16px inboard and covered the first and last glyph of every row. The window
   root is now a plain `Control`. This fails visually, never throws.
2. **`FRAME_MARGIN` and `CONTENT_INSET` had to split.** The 9-patch edge tiles
   carry opaque art across their whole 16px rather than a thin bevel line, so
   content inset by exactly `FRAME_MARGIN` sits flush against the ring.
   `CONTENT_INSET` is 22 and is the tunable one; `FRAME_MARGIN` is an art fact.
3. **The font was wrong.** `Shining Force 2.ttf` loads without error and is a
   real Shining Force face, but it reports as "Shining Force 2 b" and is the
   thin 1px-stroke variant — it does not match the reference. The shipping
   font is now `shining-force-ii-small.otf` ("Shining Force II (Small)"), the
   chunky 2px-stroke face, confirmed against a user-supplied reference on
   2026-07-30. Both files load silently, so verify with `get_font_name()`
   (`debug/preview_font.gd` prints it), never by filename.
4. **The shipping font is ASCII-only.** Established with `Font.has_char()`,
   not by eye — Godot substitutes a Windows system font rather than drawing
   tofu, so a missing glyph looks merely *wrong*, not broken. Missing:
   `‹ › ◀ ▶ ▲ ▼ … — ✓ •`. Every UI symbol is therefore drawn with
   `_draw()` instead of typed — which UI-4's cursor already did and UI-6's
   pager now must — and truncation uses `OVERRUN_TRIM_CHAR`, since `…` is
   among the missing glyphs.
5. **`MenuFull.png` is a whole window, not a bare frame.** It carries a baked
   translucent black body, `(0, 0, 0, α=155)`, across the centre patch *and*
   the inner part of all four edge tiles. `draw_center = false` skips only the
   centre, so the 16px band inside the ring rendered as `WINDOW_FILL` plus
   baked black while the centre rendered as `WINDOW_FILL` alone — two
   different shades of the same window. `_frame_ring_texture()` strips the
   baked body once at load, keying on fractional alpha (the only colour in the
   file that has any), leaving a true ring. Do not replace it with a raw
   `load()`; the two-tone returns immediately.
6. **The body must be a 9-patch layer, not a `StyleBoxFlat`.** Stripping the
   baked body to transparent and filling with a rounded-rect stylebox behind it
   left the fill poking out past the ring at every corner — visible as a dark
   wedge outside the frame. A rounded rect cannot reproduce a pixel-art corner
   staircase. `_masked_frame_texture()` now emits *two* 9-patches from the same
   source, body and ring, so their corners match by construction. Confirmed by
   reading the rendered corner pixels before and after, not by eye.
7. **Window widths are measured, not chosen, and size 24 is near the ceiling.**
   The .otf runs ~2x the advance width of the .ttf and the body size settled at
   24, so every width this plan originally implied was too narrow.
   `debug/preview_theme.gd` prints the requirement for each window's worst-case
   real catalogue content; §8 carries the results. Command + Spell is 948 of
   the 1152px default viewport and Actor + Target is 1080 — both fit, neither
   with much slack. Rerun the harness if the font, font size, or
   `CONTENT_INSET` changes.

One trap for UI-3: the `CONTENT_INSET` inset must be applied as explicit
offsets on the body, because the theme's stylebox content margins only affect
`PanelContainer` children, and the window root is no longer a `PanelContainer`.
The stylebox margins are kept anyway so incidental `PanelContainer` use (the
battle log) still clears its own frame.

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

**Model:** Sonnet 5 / GPT Terra. Multi-file with a fully stated end state and no open
design questions.

**Resolution (2026-07-30): done.** `BattleUIBuilder.build()` now returns
`game_canvas`/`dev_canvas` instead of a single `canvas`; every other returned
key is unchanged. `_buildThemedRoot()` adds a plain `Control` under each
CanvasLayer carrying `NoggTheme.build_game_theme()` /
`build_dev_theme()` — necessary because `Theme` lives on `Control`, not
`CanvasLayer`, and the prior code parented every panel directly under the
CanvasLayer with no such root. `BattleGraphicsMenu.build()`'s first parameter
was widened from `CanvasLayer` to `Node` (it only ever called `add_child` on
it) so the graphics panel could be parented under `dev_root` and inherit the
dev theme. `BattlePresentationController` now sets both canvases together at
the two lifecycle boundaries (`_show_setup()`, `_start_battle()`) and toggles
`dev_canvas` alone on SPACEBAR.

Verified with three separate single-shot windowed processes
(`debug/verify_ui2_spacebar.gd -- STATE=a|b|c`, real scene, synthetic
`InputEventKey` for SPACE via `root.push_input()`) plus a full rerun of the
existing headless suite (`drive_battle.gd`, `verify_pc1.gd`, `verify_pc2.gd`)
for regressions — all pass. State b's screenshot shows the dev bar and
graphics panel fully gone while the command menu and bottom HUD render and
report `is_visible_in_tree() == true`; state c shows the dev bar back with the
graphics panel still open, proving SPACEBAR does not reset dev-bar sub-state.

Two findings:

1. **`debug/drive_battle.gd` (TD-1) read the old `"canvas"` key** for its
   click-occlusion check and would have broken silently (dictionary miss ->
   null -> crash on the first `get_children()`). Fixed to check both
   `game_canvas` and `dev_canvas`, since either can now occlude a click.
2. **Capturing two screenshots in one running SceneTree process returns a
   stale image the second time.** `root.get_texture().get_image()` after a
   `CanvasLayer.visible` flip returned pixels byte-identical to the
   pre-toggle capture — confirmed by sampling fixed opaque button pixels, not
   by eye — even though the property read correctly and more `await
   process_frame` / `RenderingServer.frame_post_draw` did not fix it. A
   single capture per process, immediately after the toggle, is correct every
   time. This is a Godot capture quirk, not a bug in the canvas split; anyone
   writing another windowed before/after screenshot harness in this repo
   should capture once per process rather than "fix" a stale second capture
   with more waiting.

As flagged when this item was planned: assigning the theme to `game_root`
immediately changed every existing Label under it to the pixel font at size
24 with a black outline — visible in the screenshots on the command menu and
the bottom-left status panel, whose "CURRENT TURN: Envoy of Lightnin…" now
wraps and overflows its fixed 220×150 box. This is expected and is exactly
what UI-7 (restructure the bottom HUD as game windows) resolves; panel
*geometry* was deliberately left as-is per this item's own scope.

---

## UI-3 — The `NoggWindow` widget

Implement `src/presentation/theme/NoggWindow.gd` per `docs/UI_DESIGN.md` §4.

1. `class_name NoggWindow extends Control` — a plain `Control`, **not** a
   `PanelContainer`. Composition is exactly the §4 diagram:
   `NoggTheme.build_window_body()`, a `VBoxContainer` inset by `CONTENT_INSET`,
   then `NoggTheme.build_window_frame()` added last so it draws on top.

   Two traps here, both found by UI-1 on screen and both of which fail visually
   rather than throwing. A `Container` root force-fits the frame into its
   content rect, and the ring then covers the first and last glyph of every
   row. And the body must be the 9-patch layer, **not** a `StyleBoxFlat` — a
   rounded rect cannot reproduce the art's pixel corner staircase, so the fill
   leaks past the ring at all four corners.
2. `set_active(active: bool)` tweens the frame's `self_modulate` between
   `FRAME_ACTIVE` and `FRAME_INACTIVE` over 0.12 s.
3. `open()` / `close()` with the §4 scale-and-fade tweens. `close()` must be
   awaitable or emit `closed` so callers can sequence teardown.
4. `set_row_capacity(rows: int)` fixes `custom_minimum_size.y` from the theme's
   row height and font metrics, so a window's height is a function of capacity
   and not of content. Trait 6 depends on this. Width is set by the caller from
   the measured table in §8 — do not size a window to its content.
5. `add_row(label: String, value: String = "", disabled: bool = false)`
   building the two-column `HBoxContainer` of trait 4 — label left, value right
   in `TEXT_ACCENT`. Truncate with `TextServer.OVERRUN_TRIM_CHAR`, not
   `OVERRUN_TRIM_ELLIPSIS` (§3). **Reserve the value column's width before
   laying out the label**, or a long label runs straight into its value with no
   gap — UI-1's preview reproduced exactly that. Rows are plain `Control`s,
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

**Model:** Sonnet 5 / GPT Terra. UI-1 settled the look and §4 fixes the composition, so
what remains is careful Godot container work against a written spec.

**Resolution (2026-07-30): done.** `src/presentation/theme/NoggWindow.gd`
implements the §4 composition exactly — body/content/frame, `Control` root,
`set_active()`, `open()`/`close()`, `set_row_capacity()`, `add_row()`,
`clear_rows()`, `row_rect()`.

Verified by extending `debug/preview_theme.gd` to build the mock windows from
the real class instead of a hand-rolled look-alike, then reading pixels back
out of the rendered screenshot rather than trusting the thumbnail:

- Active window ring sampled `(168, 216, 255)`, inactive `(74, 90, 114)` —
  both **exact** matches to `FRAME_ACTIVE`/`FRAME_INACTIVE` converted to
  8-bit. `set_active(false)` genuinely retints the shared frame texture.
- The 8-capacity command window holding 4 rows stayed at capacity height, not
  content height.
- The spell window's 30-char outlier and the actor window's three-element
  `Elements` row both hard-truncated exactly as §8 predicts, not before.

One finding that matters beyond this item: **a brand-new `class_name` is not
resolvable as a bare static type until Godot's project has scanned it once.**
`var x: NoggWindow` inside `debug/preview_theme.gd` failed with `Could not
find type "NoggWindow" in the current scope` on the very first run after the
class was created, even though `load()`-ing the same script and calling
`.new()` on it worked fine. Root cause, confirmed by comparing the two: a
script's `class_name` only becomes a usable bare type after Godot generates
its `.gd.uid` sidecar, which happens on a project filesystem scan — and
neither `--headless -s script.gd` nor `--path . scene.tscn` reliably triggers
that scan for a file created moments earlier in the same session.
`NoggTheme.gd` (older, has `NoggTheme.gd.uid`) resolved fine as a bare type
the whole time; `NoggWindow.gd`/`MenuCursor.gd` (no `.uid` yet) did not. Fixed
by typing the harness's variables as `Control` instead — method calls still
resolve at runtime regardless of the static type, so this costs nothing.
**Any script that both defines a new `class_name` and uses it as a bare
static type in the same session should expect this** until an editor session
(or another full project scan) has run at least once. UI-5 will hit the same
trap the first time it types a variable as `NoggWindow`/`MenuCursor` if that
session starts before this repo's `.godot/` cache has seen them — check for
`src/presentation/theme/NoggWindow.gd.uid` first, or just use `Control`/`Node`
typing defensively the way this item's harness now does.

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

**Model:** Sonnet 5 / GPT Terra. Single new file, every number specified, no
dependency beyond UI-1's `CURSOR` token.

**Resolution (2026-07-30): done.** `src/presentation/theme/MenuCursor.gd`
draws a filled right-pointing triangle, bobs `position.x` continuously via a
looping tween, and moves/snaps `position.y` via a second, independent tween
per row. Bob and move deliberately animate different sub-properties
(`position:x` vs `position:y`) of the same Vector2 so `move_to_row()`'s
kill-before-tween never touches the bob — the two cannot conflict by
construction, not by careful sequencing.

**Found and fixed one real ordering bug while wiring the harness demo:** the
bob's centre is captured as `position.x` inside `_ready()`, which the spec
requires fire in `_ready()`. If a caller sets `position.x` to the frame-gutter
offset *after* `add_child()`, `_ready()` has already captured `0` (the
pre-add-child default) as the bob's centre, and the bob's next tick silently
drags the cursor back toward `x=0` regardless of what the caller just set —
wrong, and it fails visually with no error. Fixed by setting `position.x`
*before* `add_child()` in the harness, and documented as a hard requirement at
the top of `MenuCursor.gd` so UI-5 does not rediscover it.

Verified in `debug/preview_theme.gd -- shot`: two synthetic Down presses
before capture moved the cursor from `Move` to `Attack` (row 0 → row 2),
visible in the screenshot as the gold triangle sitting beside `Attack`, not
`Move` — confirming `move_to_row()` and `NoggWindow.row_rect()` both return
correct geometry immediately after `add_row()`, with no extra frame needed to
wait out `VBoxContainer`'s deferred sort (worth having actually checked rather
than assumed — Godot's container layout is deferred in general, and a stale
`row_rect()` would have looked identical to a working one for row 0 by pure
coincidence).

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

**Model:** Opus 5 / GPT Sol. Separating rebuild from selection is a structural change to
the menu's state model, and the mouse/keyboard reconciliation in §6 is a design
contract rather than a transcription.

**Resolution (2026-07-31): done.** `PlayerCommandMenu` is rebuilt on
`NoggWindow` + `MenuCursor`. The `"› "` string-prefix mechanism is gone;
selection is now `_root_index` / `_spell_index` (cursor position) and
`moveSelection()` never calls a `_rebuild_*`. Prompt and forecast became their
own small windows, so the last `StyleBoxFlat` left the game layer.
`BattleUIBuilder`'s `action_panel` went from a styled `PanelContainer` to a
plain full-rect `Control` — a Container there would force-fit the menu into one
rect and its stylebox would draw a second border competing with the frame.

Verified windowed, one screenshot per process, then **pixel-sampled rather than
eyeballed** — the frame ring was read straight out of the captures:

| | command ring | spell ring |
|---|---|---|
| root focused | `(168,216,255)` ACTIVE | — |
| spell open | `(74,90,114)` INACTIVE | `(168,216,255)` ACTIVE |

Both exact matches to the tokens. Trait 3 asserted structurally too: with the
spell window open the command window is still `visible`, still at `x=20`, and
the spell window sits to its right — it dims, it does not hide, move, or
resize. TD-1 passes.

Four findings:

1. **A new `class_name` never registers under headless/scripted runs.** UI-3
   worked around `Could not find type "NoggWindow"` by typing everything as
   `Control`; that then broke *here* as `Cannot infer the type of "row"`, since
   a `Control`-typed receiver has no `add_row()` to infer from. Root fix, which
   also retires UI-3's workaround: **`--headless --editor --quit-after 200`
   forces the project scan** that writes the `.gd.uid` sidecars and populates
   `.godot/global_script_class_cache.cfg`. After one such run all three classes
   resolve as bare types normally. Run it once after adding any `class_name`.
2. **`clear_rows()` needed `remove_child` before `queue_free`.** `queue_free`
   alone defers removal to end-of-frame, so a rebuild-then-measure in one call
   sees the VBoxContainer holding stale *and* new rows.
3. **`row_rect()` had to become arithmetic, not a node read.** `Container`
   sorting is deferred, so a row's `position` is stale on the frame it was
   added — a cursor snapped right after a rebuild would land on the wrong row
   and, since nothing re-runs, silently stay there. Now derived from
   `ROW_HEIGHT` + index, which the fixed-capacity layout guarantees agrees.
4. **`close()` must not await `tween.finished`.** A killed tween never emits
   it, so an `open()` interrupting a `close()` stranded the coroutine forever.
   Now waits on a SceneTree timer with a generation counter, so a stale close
   drops instead of hiding a just-reopened window.

Two deliberate deviations from `docs/UI_DESIGN.md` §8, both recorded there:

- **Forecast is left-aligned with the command window, not right-aligned to
  it.** At size 24 the forecast needs ~460px and the command window's right
  edge is x=300, so right-aligning would push it off the left of the screen.
  §8's dock spec predates the size-24 metrics.
- **`debug/drive_battle.gd` now pins `root.size` to 1152x648.** Headless
  defaults to 100x100, which was merely awkward when the HUD was small fixed
  panels but is fatal once the command window docks by *screen* geometry — a
  280x252 window covers the whole 100x100 viewport and `_occludedByUI()` then
  reports every tile unclickable. Two checks failed exactly that way before the
  pin. The same change made `_buildTileScreenMap`'s 1px scan ~750k probes
  (a raycast plus a UI-tree walk each), pushing a *passing* run past two
  minutes; its step is now viewport-relative and the run is back to ~20s.

The harness also stopped reaching into menu internals: it read
`_root_selected_id` / `_root_selectable_ids()`, which the state-model change
deleted. Rather than re-couple it to the new private shape, `PlayerCommandMenu`
now exposes read-only `selectedEntryId()` / `selectableEntryIds()` /
`selectedSpellId()`.

**Follow-up in the same session (2026-07-31), from design review of the first
screenshots:** two adjustments, both in `docs/UI_DESIGN.md`.

- **Windows were reserving space they could never use.** The command window
  held 4 rows in an 8-row frame — 104px, half the window, empty. §4's sizing
  rule was too strong: what traits 5 and 6 need is that a window never resizes
  *while being navigated*, not that it reserve maximum capacity up front. Now
  "size on open, then hold": the command window is 5 rows (its true maximum,
  and it can never page), and the spell window sizes to
  `clampi(spells + 1, 1, 8)` so a one-spell monster gets a 2-row window instead
  of eight. Docked readouts keep fixed capacity — they are the no-jitter case.
  `NoggWindow.set_row_capacity()` now assigns `size.y` outright rather than
  only growing it, since a shrinking capacity has no parent container to re-fit
  these free-floating windows.
- **Command labels render uppercase.** `MOVE / UNDO MOVE / ATTACK / SPELL /
  PASS`, and `< BACK`; spell and monster names stay mixed-case, because
  all-caps strips the word-shape cues that make an unfamiliar name scannable
  and names are the strings most likely to truncate. Verified the font is
  **monospace** first — every command label measures identical in both cases,
  so §8's widths are untouched and the choice is purely aesthetic. Applied at
  render time via `UPPERCASE_COMMANDS`, never to the model, since those strings
  also feed logs and harness assertions.

**Second design-review pass (2026-07-31):** three more adjustments.

- **The cursor was sitting on the frame ring.** Cursor-hosting windows now
  indent their rows by `CURSOR_GUTTER_WIDTH` on top of `CONTENT_INSET`, giving
  `ring 0-12 | cursor 16-28 incl. bob | text 34+`. `CURSOR_WIDTH` /
  `CURSOR_INSET` / `CURSOR_GUTTER_WIDTH` moved into `NoggTheme` — `NoggWindow`
  reserves space for a cursor it never sees, so a private copy inside
  `MenuCursor` would have let the two drift. Windows with no cursor keep a zero
  indent.
- **Inactive windows now dim their content, not just their border.** A lit list
  inside a greyed frame reads as a glitch rather than as loss of focus.
  `set_active()` tweens `_content.modulate` alongside the frame tint; measured
  on screen, command text goes `(255,255,255)` focused → `(115,120,133)` while
  the spell window holds focus. Modulating the container (not restyling rows)
  makes a disabled row in an inactive window compound to the dimmest state for
  free.
- **`Undo Move` → `Undo`.** A move is the only undoable thing and the row sits
  directly under `MOVE`, so the long form bought nothing. It was also the
  binding constraint on `COMMAND_WIDTH`: dropping it moved the longest label to
  `ATTACK` and let the window come down from 300 to **220**. The id stays
  `undo_move`, so every harness assertion was unaffected.

**Not yet exercised:** the mouse path (hover-to-move, click-to-activate, wheel)
is implemented per §6 and compiles, but every check above drove the keyboard.
§6's real risk — cursor desync between devices — needs a human alternating
mouse and keyboard mid-menu, which no harness here simulates.

---

## UI-6 — Paging

Add fixed-capacity paging to `NoggWindow` per `docs/UI_DESIGN.md` §7.

1. `NoggWindow` takes the full row set and slices it by `row_capacity` (8).
   `page`, `page_count`, `next_page()`, `prev_page()`, circular in both
   directions.
2. The footer is its own small `NoggWindow` reading the page indicator,
   horizontally centred and overlapping the parent's bottom border by half its
   height. It is absent — not disabled — when `page_count == 1`.
   **Draw the arrows with `_draw()`, do not type them.** `◀` and `▶` are
   absent from the shipping font and silently fall back to a Windows system
   font, which renders as thin outline triangles beside a pixel font (§3).
   Mirror `MenuCursor`'s triangle so pager and cursor read as one family.
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

**Model:** Sonnet 5 / GPT Terra. Multi-file with a stated end state; the design questions
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

**Model:** Sonnet 5 / GPT Terra. Mechanical once §8 fixes the taxonomy, but it spans three
files and several call sites.

**Resolution (2026-07-31): done, with scope expanded beyond the stated files**
**by explicit user direction.** Item 5 (prompt/forecast windows) turned out to
already exist — UI-5 built `_prompt_window`/`_forecast_window` while wiring the
command menu, since the design called for them at the same time. So this item
was really just 1–4: the actor/target windows.

Discovered before writing any code: `left_ui_label`/`right_ui_label` were not
simple stat displays. `_update_selection_ui` (click-to-inspect) only ever
touched the LEFT label; the right one was hardcoded to `"No target"` at the two
lifecycle boundaries and **never updated again** — dead since before this UI
work started. The actual live driver of both labels turned out to be
`GodotVisualAdapter.gd`, which pushes preformatted multi-line strings
(`"TARGET:
%s
Takes %s Damage..."`) through `_update_left_ui`/`_update_right_ui`
as combat plays back — a second, separate data path the plan's file list
(`BattleUIBuilder.gd`, `BattlePresentationController.gd`, `PlayerCommandMenu.gd`)
didn't anticipate. Asked the user how the target window should behave rather
than guess; the answer was both: click-to-inspect **and** a live
attacker/target override during combat. Delivered:

- `BattleUIBuilder.gd`: `actor_window`/`target_window`, two 540×6 `NoggWindow`s
  docked bottom-left/bottom-right, replacing the old `PanelContainer`s.
- `BattlePresentationController.gd`: one renderer, `_renderStatusWindow(window,
  monsterID)`, building the heading + HP + ATK/DEF + SPD/MOV + Elements rows
  from `sim.state` (or leaving the window empty at `-1` — item 4). Click
  routing now splits by team: same team as the active monster → actor window,
  otherwise → target window; with no active turn it always goes to actor,
  matching the old single-inspector behaviour.
- `GodotVisualAdapter.gd` (added to scope): every `left_text`/`right_text`
  producer (`_on_turn_started`, `_on_monster_attacked`, `_on_monster_cast_spell`,
  `_on_monster_healed`, `_on_monster_defeated`, `_on_battle_ended`) now emits
  `left_monster_id`/`right_monster_id` — a monster reference, not a frozen
  string — resolved fresh against `sim.state` at the moment the queued visual
  action actually plays. This is strictly more correct than the string it
  replaces: the old text was baked at queue time, so a second event landing
  before the first finished animating could show stale HP; resolving at
  display time cannot. `"BATTLE COMPLETE..."` moved to a new `prompt_text` key
  routed to the prompt window instead — it was never about a monster's stats
  and didn't belong in a stat panel. Precedence between the two writers (click
  vs. live combat push) is last-write-wins, same relationship the two paths
  already had before this item, just split across two windows instead of one.
- HP colours `TEXT_ACCENT` below one third, `TEXT_PRIMARY` above — inverted
  from every other value column, which defaults to accent. Healthy HP is
  meant to blend in as unremarkable; only low HP should compete for the eye.

Verified with three single-shot windowed processes (`debug/verify_ui7_hud.gd
-- STATE=turn|attack|click`, real scene, synthetic input) plus the full
headless regression suite. `STATE=attack` first failed
(`_pressAction("ui_accept")` twice reaches `CONFIRM_ACTION` and stops there;
`confirmSelection()` needs a THIRD accept to actually call `_commitAction()`
and resolve) — fixed in the harness, not the game. All three now pass and the
attack screenshot shows the defender's real post-hit HP (45→44) in the target
window, sourced live rather than typed into a test assertion.

**One inaccuracy in §8 found and corrected, not chased.** The doc claimed
Elements-row truncation was rare ("only a three-element list"). Measuring the
real catalogue found **no monster has 3 elements at all** (2 is the observed
maximum), while several ordinary 2-element monsters — `water, darkness`,
`fire, darkness` — already need ~584px against the window's 496px content
area and do truncate today (seen live in the `attack`/`click` screenshots:
`Elemen  fire, darkness`). Not fixed, because there is no room to fix it:
Actor + Target already spend the entire 1152px budget with zero slack (540 +
540 + 32 gap + 40 margins = 1152). §8 now states the measured reality instead
of the wrong assumption.

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

**Model:** Sonnet 5 / GPT Terra. Four files, but each edit is small and the end state is
fully stated.

**Resolution (2026-07-31): done.** The CRT shader (`crt_display.gdshader`)
reads `hint_screen_texture` — it distorts whatever was already drawn to
screen at the moment ITS canvas item draws. That means making the game UI
take the CRT treatment is about where the SHADER's own layer sits relative to
the game canvas, not about moving the game canvas itself (which stays the
stable `NoggTheme.GAME_LAYER` constant other code already depends on).

So `crt_overlay` moved out of `display_layer` (which now holds only the
backdrop and world texture) into its own `crt_overlay_layer` CanvasLayer,
toggled between `NoggTheme.CRT_OVERLAY_LAYER_DEFAULT` (-10, below the game UI
— today's behaviour) and `CRT_OVERLAY_LAYER_THROUGH_UI` (`GAME_LAYER + 1`,
above it). Both stay below `DEV_LAYER`, so the dev bar is never affected
either way — confirmed on screen, not just by the layer arithmetic.

One persistence subtlety: `RetroRenderController._init()` calls
`_load_settings()` **before** `_build_render_target()`, so
`set_ui_through_crt()` cannot run during load — `crt_overlay_layer` does not
exist yet, and would hit the same null-node trap NoggWindow's marquee tween
almost did. `_load_settings()` now sets the raw `ui_through_crt` bool only;
`_apply_settings()` (which runs after the build, like every other
loaded-then-applied value here) is what actually sets the layer. Persisted
outside the `PRESET_CUSTOM` gate that guards the look/CRT numeric values —
whether the UI takes the CRT pass is orthogonal to which visual preset is
active, not a property of the preset itself.

Verified with two single-shot windowed processes at cranked CRT strength
(`debug/verify_ui8_crt.gd -- STATE=off|on`) rather than eyeballing a toggle
mid-session — `off` shows a crisp menu over a scanlined board; `on` shows the
same menu visibly scanlined and desaturated along with it. Both confirm the
command menu stays genuinely interactive (`selectedEntryId() == "move"`, not
merely `visible`) across the toggle.


---

## UI-9 — Scroll the focused row when its label overflows

Truncation (§3) is the resting state for a row that does not fit, and it stays
that way. But truncation hides information the player needs — `Closing of the
Third San` and `Closing of the Third Sanc` are indistinguishable — so the row
under the cursor reveals the rest by scrolling. Specified in
`docs/UI_DESIGN.md` §7b; that section is the contract, this item is the build.

1. Add the timing tokens to `NoggTheme.gd` alongside the existing animation
   block: `MARQUEE_DELAY` 1.2, `MARQUEE_SPEED` 40.0 (pixels per second),
   `MARQUEE_END_HOLD` 1.0. They belong there for the same reason the tween
   timings do — nothing else in `src/presentation/` may hold a timing literal.
2. Wrap the **label column only** in a `clip_contents = true` Control and tween
   the label's `position.x`. The value column (`Rng 3`, `CD 12`) is
   right-aligned against the frame and must stay anchored; scrolling the whole
   row slides the two columns across each other.
3. Duration is **distance ÷ `MARQUEE_SPEED`**, never a fixed duration. A fixed
   duration makes a long name scroll fast and a barely-overflowing one crawl.
4. Cycle: hold `MARQUEE_DELAY`, scroll to reveal the tail, hold
   `MARQUEE_END_HOLD`, **snap** back to the start, repeat. Snap, not a reverse
   tween — reversing reads as indecision and doubles the time before the start
   is legible again.
5. Only the row under the cursor scrolls, ever. Wire it to the same selection
   change that moves `MenuCursor`, so a row starts its cycle when the cursor
   arrives and **resets immediately** when the cursor leaves — no easing out,
   no finishing the cycle. If the reset lands after the cursor's move tween the
   two animations visibly fight.
6. A row whose label fits must never scroll and must never wait out the delay.
   Compare against the clip rect, not against a character count.
7. Applies to any `NoggWindow` row, not just spells. The actor status window's
   `Elements` row overflows on three-element monsters (§8) and gets the same
   behaviour for free if this lives in the row, not in the spell list.

**Files:** `src/presentation/theme/NoggWindow.gd`,
`src/presentation/theme/NoggTheme.gd`,
`src/presentation/PlayerCommandMenu.gd`.

**Verify:** Open the spell window on a monster with `Closing of the Third
Sanctuary`. Confirm the row is truncated at rest; that it begins scrolling only
after the delay; that it snaps rather than reverses; and that the value column
never moves. Then arrow up and down through the list at speed and confirm no
row is left mid-scroll and nothing animates except the row under the cursor.
Finally select a three-element monster and confirm its `Elements` row scrolls
in the actor window with no extra wiring.

**Risk:** Low. Additive and self-contained — if it misbehaves the row still
reads as a truncated row, which is the current behaviour. The one thing that
can look broken is a stale scroll left behind by a cursor move, which item 5
exists to prevent.

**Model:** Sonnet 5 / GPT Terra. Three files, and §7b already settled the
timings and the five behavioural rules, so what remains is wiring against a
written contract.

**Depends on:** UI-3 (rows) and UI-5 (the cursor's selection change is the
trigger). Independent of UI-6, UI-7, and UI-8 — it can run any time after UI-5.

**Resolution (2026-07-31): done.** `NoggTheme.gd` gained the three timing
tokens. `NoggWindow.add_row()`'s label now sits inside a `clip_contents`
wrapper sized to the label's full natural width (`Label.get_minimum_size()`,
correct immediately — a pure function of font/text/theme, no layout pass
needed), rather than relying on `Label.clip_text`/`OVERRUN_TRIM_CHAR` alone;
the wrapper is what makes `position:x` a meaningful thing to tween. A new
`set_focused_row(index)` drives it: kill whatever was scrolling, snap it to 0,
and if the newly focused row's label overflows its arithmetically-computed
available width (same reasoning as `row_rect()` — Container sorting is
deferred, so a live-read size would be stale on the same frame), start the
delay-scroll-hold-snap loop, guarded by a generation counter exactly like
`close()`'s. `PlayerCommandMenu._select()` calls it on every selection change,
alongside the cursor move.

**One real bug found and fixed by the verification, not by inspection.** The
scroll tween created inside the marquee loop was never stored, so
`set_focused_row()`'s reset (`label.position.x = 0.0`) was correct for exactly
one frame — the still-running tween then overwrote it on the very next frame,
since nothing had ever told it to stop. Confirmed on screen: a row refocused
away mid-scroll stayed visibly scrolled instead of snapping back, which is
precisely the failure item 5 was written to prevent. Fixed by storing the
tween and killing it in `set_focused_row()`, matching the pattern `set_active()`
and `open()`/`close()` already use. This would not have been caught by reading
the code; the reset call was right there and looked correct.

Verified directly against the widget (`debug/verify_ui9_marquee.gd`, four
single-shot states: `rest`/`mid`/`fits`/`reset`) rather than through a full
battle. Reaching it through `Battle25D` first, to exercise the real catalogue's
`Closing of the Third Sanctuary` on `Walker of the Woods`, hit an unrelated
setup bug: forcing that monster into a roster slot via
`_select_option_by_metadata` left `player_turn` permanently inactive after 500+
`_advance_battle()` ticks, for reasons that have nothing to do with anything
this item touches. Not chased down — the marquee lives entirely in
`NoggWindow`/`NoggTheme`, needs no battle at all to verify, and the existing
mock windows in `debug/preview_theme.gd` already carry the exact same
30-character catalogue outlier. Screenshots confirm: `rest` shows
`Closing of tl` (truncated, not yet scrolling); `mid` shows `losing of the`
(genuinely slid left, later characters visible); `fits` shows the unfocused
row unchanged after waiting past the full cycle, confirming rule 6; `reset`
confirms rule 5 after the tween-kill fix.

Also corrects a stale example while touching this: item 7 originally cited
"three-element monsters" for the actor window's Elements row as a case this
would help — UI-7 already found no monster has 3 elements, and the real
overflow case is common 2-element combos. The behaviour works identically
either way (`BattlePresentationController._renderStatusWindow` already calls
`set_focused_row()` on the Elements row unconditionally, per UI-7's own
notes); only the illustrative example was wrong.

---

## DATA-1 — Centralize atomic JSON loading and nest monster stats

Create one shared JSON boundary for file access, parse diagnostics, array/entry
shape, unique non-empty names, deep copies, and name indexing. Keep
monster/race-specific coercion in their wrappers. Move all monster base,
movement, Luck, Jump, and growth values into STATS; reject legacy top-level
stat keys and adapt every consumer without changing the runtime replay schema.

**Model:** Opus 5 / GPT Sol.

**Verify:** Run the headless project launch; run a focused Godot verifier that
checks all 28 entries, monster construction, setup labels, atomic failed reload,
successful production reload, and race resistance behavior; then run
scripts/demo_battle.gd to battle completion. Finish with git diff --check.

**Risk:** Medium. A schema cutover touches data, factories, simulation, and setup
presentation simultaneously. Atomic reload and rejecting the old schema reduce
the risk of partial or ambiguous state.

**Resolution (2026-07-31): done.** JsonCatalogLoader now owns the shared
file/parse/shape/name-index boundary. MonsterReferences and RaceReferences keep
domain normalization and commit only complete catalogs. Every monsters.json
entry has an explicit STATS dictionary; Monster, MonsterStatCalculator, and
BattleSetupUI consume it. Runtime serialization remains unchanged because
BattleStateSerializer restores resolved monster state after catalog-backed
construction. The focused verifier passed all checks, the seeded demo reached
Team 1 victory, the project launched without script errors, and git diff
--check passed.

## DATA-2 — Move spell references to JSON

Move the authored SpellReferences catalog to a JSON file loaded through
JsonCatalogLoader. Preserve SpellFactory/Spell runtime behavior, normalize
spell-specific numeric, boolean, collection, and targeting fields in the domain
wrapper, reject duplicate or malformed names atomically, and document the
schema. Do not combine this item with other catalog migrations.

**Model:** Sonnet 5 / GPT Terra.

**Final validation coverage:** Construct every spell through SpellFactory and
exercise rejected/preserved and successful spell-catalog reloads.

**Risk:** Medium. Spell data feeds validation, AI, forecasts, resolution,
cooldowns, Resonance, and presentation; a coercion mismatch can remain latent
until a specific effect is cast.

**Resolution (2026-07-31): done.** The
59 authored spell definitions now live in data/spells.json. SpellReferences
uses JsonCatalogLoader, preserves atomic catalog replacement and constant-time
lookup, and normalizes scalar, damage-line, and effect values before Spell
construction. The spell schema and documentation index were added. Validated
under DATA-VALIDATE, which found and fixed one coercion defect in this item
(the `RESONANCE_ELEMENT` default — see that item's Resolution).

## DATA-3 — Move remaining authored reference catalogs to JSON

Inventory the remaining hardcoded reference-data classes, migrate them to
explicit JSON catalogs through JsonCatalogLoader, and retain small domain
wrappers only where coercion or behavioral lookup is required. The stated end
state is no authored content arrays embedded in GDScript reference classes;
engine class/registry mappings remain code where they represent behavior rather
than content.

**Model:** Sonnet 5 / GPT Terra.

**Final validation coverage:** Enumerate and construct every migrated reference
through its public API and exercise atomic reload failure for each catalog shape.

**Risk:** Medium. The mechanical migrations are broad and missing export
inclusion or string-to-type coercion can break only selected content. Keep the
item to its stated end state and do not redesign gameplay registries here.

**Resolution (2026-07-31): done.** The
remaining authored reference catalogs now live in elements.json, archetypes.json,
passives.json, status_effects.json, and maps.json. Their wrappers retain only
domain coercion and public lookup behavior. Maps encode `SIZE` and deployment
slots as `[x, y]` in JSON and restore `Vector2i` at the wrapper boundary. The
reference-catalog guide and documentation index were updated. Validated under
DATA-VALIDATE with no defects found in this item.

## DATA-VALIDATE — Validate the completed catalog migrations

Run one consolidated validation after DATA-2 and DATA-3 are committed. Cover
the shared loader, every migrated public lookup/factory API, reload atomicity,
export inclusion, spell construction, and an integrated battle. Fix integration
defects here and update DATA-2/DATA-3 Resolutions from pending validation to
done only after the combined flow passes.

**Model:** Sonnet 5 / GPT Terra.

**Depends on:** DATA-2 and DATA-3.

**Verify:** Start from a clean status; launch Godot; run one focused catalog
harness that enumerates and constructs every migrated reference and exercises
failed/successful reloads; run scripts/demo_battle.gd to completion; inspect
export_presets.cfg coverage; finish with git diff --check.

**Risk:** Medium. This is the first integrated acceptance boundary for the
catalog cutover, so failures may cross data, factory, AI, or presentation
ownership even when each migration diff was mechanically straightforward.

**Resolution (2026-07-31): done.** Validated with
`debug/verify_data_validate.gd` (gitignored scratch, matching the existing
`debug/verify_*.gd` pattern — not reinstated test infrastructure), plus the
headless project launch, two `scripts/demo_battle.gd` runs, an
`export_presets.cfg` inspection, and `git diff --check`.

Coverage that passed: the shared loader rejects all ten malformed shapes
(missing file, empty, unparseable, non-array root, non-dictionary entry,
missing/empty/duplicate `NAME`, missing root key, non-array root key value)
with a diagnostic each; all eight catalogs enumerate and round-trip through
their own lookup APIs (59 spells, 28 monsters, 15 races, 11 elements, 4
archetypes, 3 passives, 11 status effects, 3 maps); every spell, monster, map,
and passive constructs through its factory with its authored scalar, boolean,
and collection fields intact; no monster reference retains a legacy top-level
stat key; map `SIZE` and both deployment slot arrays come back as `Vector2i`;
every race resistance is a float matching `getDamageMultiplier`; each of the
eight catalogs rejects both a missing file and a malformed file **without
changing its live entry count** and then reloads the production file; and a
catalog-backed CPU battle reaches a winner with zero rejected commands.
`export_presets.cfg` covers all eight files via `include_filter="data/*.json"`
with `export_filter="all_resources"`.

**One real defect found and fixed, in DATA-2.** `SpellReferences.STRING_DEFAULTS`
carried `"RESONANCE_ELEMENT": ""`, so normalization wrote the key with a blank
value into every reference. `Spell._init` reads it as
`str(parameterDictionary.get("RESONANCE_ELEMENT", element))` — a fallback that
only applies when the key is **absent**. No authored spell declares the field
(none did before the migration either), so all 59 spells were built with
`resonance_element == ""` instead of their own element.

The consequence was not cosmetic. `Monster.record_cast()` bails on
`resonance_element == "none"`, not `""`, so all 28 sequenced spells charged a
single shared `""` bar regardless of element. `Walker of the Woods` — the one
monster with a complete ladder, and the one P4-2 names for verifying it — also
carries `Stroll` (wind, Level 1); casting it charged the wood ladder, and
`would_advance_resonance(Thornlash)` then returned true, unlocking the wood
Level 2 spell off a wind cast. Confirmed empirically before the fix:
`resonance_bars == {"wood": 0, "wind": 0, "": 1}`.

Fixed by removing `RESONANCE_ELEMENT` from `STRING_DEFAULTS` and normalizing it
explicitly to the spell's own `ELEMENT` when absent or blank, which restores
pre-migration semantics and keeps the resolved value in the reference rather
than in `Spell`'s implicit fallback. After the fix the same cast yields
`{"wood": 0, "wind": 1}` and the ladder gate holds.

**Worth knowing before touching a catalog wrapper again:** a `*_DEFAULTS` table
is not equivalent to the entity's own `get(key, fallback)` default whenever
that fallback is *derived from another field*. The table always writes the key,
which permanently wins over the derived fallback. This class of defect is
invisible at load time and survives a full battle without an error, so check
derived defaults specifically rather than relying on the catalog loading
cleanly.

**Expected value change:** the DATA-VALIDATE harness's own integrated battle
(seed 1234, `Walker of the Woods` on team 1) went from 94 turns to 214 turns
once resonance stopped accumulating on one shared bar. The seeded
`scripts/demo_battle.gd` log hash is unchanged (`cbb6ce50…`) because that
roster casts no sequenced spell.

---

## Typed and positional command contracts (TYPE-1, POS-1 … POS-3)

Recovered from the 2026-07-31 architecture plan. These items deliberately add
small value objects rather than merging cohesive classes: class count is not a
problem, while string-keyed public orchestration contracts are.

## TYPE-1 — Typed battle command boundary

Add typed `BattleCommand` and `BattleCommandResult` value objects with explicit
`to_dictionary()` / `from_dictionary()` adapters. Update AI, player control,
simulator, replay, and command history without changing behavior. Internal
scoring and resolver payload dictionaries remain internal; JSON catalogs remain
dictionaries after validation. Replay version stays 4 for this item.

**Model:** Opus 5 / GPT Sol.

**Final validation coverage:** Replay round-trip plus one player/CPU command of
every action type. Serialized fields and behavior must remain unchanged.

**Risk:** Medium-high. This changes the public controller-neutral command seam
shared by player control, CPU brains, history, and replay.

**Resolution (2026-07-31): implemented; pending end-of-plan validation.**
`BattleCommand` and `BattleCommandResult` now own the public orchestration
contract. AI and simulator exchange typed commands, command history and replay
use explicit dictionary adapters, and typed execution results replace dynamic
result lookups. Resolver-specific action payloads remain dictionaries. A narrow
headless project-load smoke passed; behavioral and replay acceptance remain the
final validation item's responsibility.

## TYPE-2 — Typed UI reference bundles

Replace the string-keyed `battle_ui` and `setup_ui` orchestration dictionaries
with `BattleUIRefs` and `BattleSetupUIRefs`. The graphics-menu builder returns
its own typed child bundle, while renderer-parameter maps remain dictionaries
because their keys are dynamic authored settings. Update every consumer,
including visual prompt status, to use typed fields.

**Model:** Sonnet 5 / GPT Terra.

**Verify:** Run the headless Godot editor load command; inspect that no
`battle_ui[...]` or `setup_ui[...]` access remains. Consolidated manual
acceptance covers setup, graphics toggles, status windows, command menu, and
new-battle lifecycle.

**Risk:** Medium. The reference bundles are constructed during scene startup;
a missing assignment would fail only when a particular setup or HUD interaction
is used.

**Resolution (2026-07-31): implemented; pending consolidated presentation
acceptance.** `BattleUIRefs`, `BattleSetupUIRefs`, and the nested
`BattleGraphicsMenuRefs` now make the stable UI contract explicit. The
controller and visual adapter use typed fields only; dynamic renderer parameter
maps remain local to graphics synchronization.

## TYPE-3 — Typed visual action queue contract

Replace the visual queue's string-keyed action dictionaries with a typed
`VisualAction` value object. Use enums for action and cursor modes, explicit
flags for optional status-panel updates, and cloning at the enqueue boundary.
Preserve FIFO ordering, pause/watchdog behavior, run-ahead accounting, and all
existing animation/log/status semantics.

**Model:** Sonnet 5 / GPT Terra.

**Verify:** Run the headless Godot editor load and runtime startup commands;
inspect that no queued action dictionary construction or lookup remains.
Consolidated presentation acceptance covers focus, movement, occupied and empty
attacks, spell damage/healing/no-target casts, defeat, victory, pause, and
watchdog recovery.

**Risk:** Medium. Visual actions intentionally snapshot event-time data for
later playback. Losing optional-field presence or cloning semantics would cause
status panels or animations to display later authoritative state incorrectly.

**Resolution (2026-07-31): implemented; pending consolidated presentation
acceptance.** `VisualAction` now owns action/cursor enums and typed payload
fields. `VisualActionQueue` stores cloned typed actions, and
`GodotVisualAdapter` produces and consumes the contract without string-keyed
action access. Queue scheduling, pause, watchdog, recovery, and disposal logic
remain unchanged.

## POS-1 — Position-based simulation contract

Extend `BattleCommand` with canonical `target_pos`; `target_id` becomes the
derived occupant/result field rather than targeting identity. Basic Attack may
target any adjacent in-bounds, height-reachable empty or enemy tile, but not an
allied tile. An empty attack spends the action, animates a miss toward the tile,
deals no damage, and fires no target passive.

Every non-self spell exposes positional centers. Every spell has an explicit
`CAN_TARGET_EMPTY` catalog flag controlling whether an empty center can be
confirmed; the flag does not control whether the center is shown by the player
UI. A legal zero-unit cast consumes the action, cooldown, and Resonance. Resolver
queries take `center_pos`, targeting/cast events include positions, and replay
bumps to version 5. Replay v2-v4 commands derive `target_pos` from `target_id` at
the moment each legacy command executes. No fake monster IDs are introduced.

**Model:** Opus 5 / GPT Sol.

**Final validation coverage:** Occupied/empty attack, occupied/empty spell
center, zero-hit cast, LoS/elevation, cooldown and Resonance consumption, plus
v2-v5 replay. Expected values change: legal center counts increase and replay
version becomes 5.

**Risk:** High. Simulation validation, resolution, events, history, and replay
must agree on one canonical coordinate without diverging between controllers.

**Resolution (2026-07-31): implemented; pending end-of-plan validation.**
`target_pos` is canonical in typed commands, validation, phase accumulation,
history, and replay v5; replay v2-v4 derives positions just before legacy
commands execute. Basic attacks accept legal empty adjacent tiles without
firing target passives. Spell targeting separates displayed reachable centers
from confirmable centers, and all 59 spells explicitly declare
`CAN_TARGET_EMPTY`. Legal zero-unit casts emit a positional cast event and still
call `record_cast()`, consuming cooldown and Resonance. Positional action events
carry real coordinates and `target_id = -1` for empty centers. POS-3 now owns
the coordinate-based player selector. A narrow headless project-load smoke
passed; behavioral/replay acceptance remains POS-VALIDATE.

## POS-2 — AI positional targeting

AI enumerates legal center positions rather than only unit IDs. Area spells are
scored from every affected unit around a center; centers producing equivalent
outcomes are deduplicated. Empty attacks and zero-effect spells remain legal but
score below Wait unless authored effects make the position useful. Preserve
deterministic tie-breaking by coordinate and action identity.

**Model:** Opus 5 / GPT Sol.

**Final validation coverage:** Seeded AI chooses an empty-centered area spell
that affects multiple units, declines a useless empty cast, and replays to the
same result.

**Risk:** Medium-high. Candidate counts increase and inconsistent utility or
tie-breaking would damage both performance and determinism.

**Resolution (2026-07-31): implemented; pending end-of-plan validation.**
`BattleCommandEvaluator` now enumerates sorted legal attack/spell coordinates
from every destination. It derives occupants only for results/history, scores
all units affected by an area center, and deduplicates equivalent affected-ID
sets per spell and destination. Legal empty misses and zero-unit/no-utility
casts score below the Wait candidate at the same destination. Tie keys include
destination, action/spell identity, and target coordinate. The shared resolver
also models the actor's projected destination/origin vacancy so pre-move AI
queries match execution. A narrow headless project-load smoke passed; seeded
choice and replay acceptance remain POS-VALIDATE.

## POS-3 — Player positional targeting and visuals

Replace occupied target IDs in the player controller with legal target
positions. Mouse and keyboard/gamepad can select empty or occupied centers;
legal centers remain yellow and affected area remains red/green. Empty centers
leave target status blank, forecasts aggregate affected units and warn on zero
units, and empty attacks animate a miss toward the chosen tile. Preserve cancel,
confirm, camera ownership, and both phase orders.

**Model:** Opus 5 / GPT Sol.

**Final validation coverage:** In-window mixed mouse/keyboard playthrough of
empty attack, empty-centered area spell, zero-hit cast, occupied target, cancel,
both phase orders, multiple elevations, and camera angles.

**Risk:** High. This is the input/presentation half of the positional contract
and absorbs the outstanding player-command visual acceptance work.

**Resolution (2026-07-31): implemented; pending POS-VALIDATE.**
`PlayerTurnController` now stores, sorts, cycles, cancels back to, and submits
canonical target positions. Attack selection includes legal empty adjacent
tiles. Spell selection displays reachable empty centers regardless of
`CAN_TARGET_EMPTY`, while resolver-backed confirmation blocks disallowed empty
centers. The preview keeps all legal centers visible, overlays the selected
spell footprint, clears target status for empty centers, and aggregates forecast
damage/healing/unit counts with explicit zero-unit warnings. Godot presentation
accepts target positions directly. A narrow parser/runtime smoke passed; mixed
in-window input, camera/elevation coverage, and integrated replay acceptance
remain POS-VALIDATE.

## POS-VALIDATE — Validate typed presentation and positional targeting

Run one consolidated acceptance pass after TYPE-1 through TYPE-3 and POS-1
through POS-3 are committed. Cover TYPE-1's serialization boundary, TYPE-2's
setup/HUD reference lifecycle, TYPE-3's queued animation contract, POS-1's
simulation/replay cases, POS-2's seeded AI choices, and POS-3's in-window player
flow. Update pending resolutions to done only after this combined pass succeeds.

**Model:** Opus 5 / GPT Sol.

**Depends on:** TYPE-1 through TYPE-3 and POS-1 through POS-3.

**Verify:** Run focused typed-command and replay-v2-v5 harnesses, seeded AI
scenarios, and a full deterministic battle/replay round-trip. In-window, cover
setup/confirm/new-battle lifecycle, graphics toggles, command and status windows,
focus/move/attack/spell/heal/defeat/victory animations, pause/resume, and the
specified mixed-input positional playthrough; finish with `git diff --check`.

**Risk:** High. This is the first integrated acceptance boundary for all
controllers sharing coordinate-based targeting.
