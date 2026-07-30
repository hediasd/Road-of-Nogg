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
3. `Magic` opens a second vertical column listing spells with name, range, and
   remaining cooldown; unavailable spells are shown disabled rather than
   hidden. This replaces the `spell_option` `OptionButton` entirely.
4. Input, modal by phase: `MENU` takes up/down plus accept/cancel in menu
   space; `MOVE_SELECT` takes the four directions as grid-cursor movement with
   a live path preview; `TARGET_SELECT` cycles the valid-target set rather
   than free-roaming the grid. Mouse click stays available in every phase.
   Retire the `M`/`A`/`S`/`W`/`E` hotkeys, or rebind them to menu entries —
   they must not bypass a phase.
5. Replace status text that names internal states with player-facing wording.

**Files:** `src/presentation/BattleUIBuilder.gd`, new
`src/presentation/PlayerCommandMenu.gd`,
`src/systems/BattlePresentationController.gd`

**Verify:** Drive one complete Player vs CPU turn using only the keyboard, and
a second using only the mouse. Confirm spent entries grey out, `Magic` lists
cooldowns correctly, and cancel from the spell column returns to the root
menu.

**Risk:** Medium. Presentation only, but it is the entire player input
surface.

**Model:** Sonnet 5, once PC-2 has fixed the menu model and phase API.

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
