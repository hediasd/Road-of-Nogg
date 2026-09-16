# Side-turn battle

2026-09-16. Rework the hex battle around whole-side turns and a board-first
command model. Today a round schedules **parties** one at a time (ordered by
commander level, then commander speed), a party's members take one member
turn each, and the player drives each turn through a seven-plate command rail
on the right edge with a prompt box, a party panel and a round-order panel on
top. After this cycle, a turn belongs to a **side** (a team): the player
commands every one of their units in any order. Moving is a click on a
walkable cell, attacking is a click on an enemy in reach, and the remaining
verbs sit in a small arc of icons on the selected unit. Spent units go dark,
and the turn ends when every unit is spent or when End turn is pressed. Henri
approved this flow on 2026-09-16 from the storyboard committed with this plan.
This cycle is not a balance pass, does not change damage or spell rules
beyond the two turn rules below, does not touch the world map, and does not
port anything to the retired square battle.

**Henri asked for every item in this cycle to run on GPT Sol 5.** Each item
still carries a real rationale. Where an item would normally fit the Terra
tier, the rationale says so, so the cost is visible.

## Reference

- `docs/plans/references/side-turn-battle/storyboard.html`: the approved
  eight-frame storyboard, with the rules summary and the calls Henri
  confirmed. Open it in a browser. **This is the source of truth for the
  flow.**
- `docs/plans/references/side-turn-battle/walkable-cell-styles.png`: six
  walkable-cell treatments rendered in-engine. Top row: current, soft wash,
  centre pips. Bottom row: **region contour** (the chosen style), dim the
  rest, fine inset line. The storyboard uses the region contour.

## Rules Henri confirmed

1. **A turn belongs to a side.** Every living, non-withdrawn unit of every
   party on that team may act, in any order. A round is every surviving side
   taking one turn. Parties remain as groups (commanders, withdrawal,
   setup) but no longer schedule anything.
2. **Switching units is free.** Selecting another unit never locks or spends
   the first one.
3. **Moving alone does not spend a unit.** A unit that has only moved stays
   bright, can be returned to later, and can undo that move until it acts.
4. **Acting ends the unit.** Attacking, casting, using an item or Wait spends
   it and darkens it. A unit cannot move after it has acted. This reverses
   today's act-then-move order, which is deliberate.
5. **Magic only before moving.** A unit that has moved this turn cannot
   cast. Attack after a move is still allowed.
6. **The turn ends** when every unit on the side is spent, or when the player
   presses End turn. If units can still act, End turn asks first ("2 units can
   still act, end turn?"). Ending spends the remaining units as Wait.
7. **Attacking is a click.** Pointing at an enemy the selected unit can hit
   **from where it stands** shows a sword over that enemy. Clicking it attacks
   at once: the preview is the confirmation. An enemy the unit would have to
   walk to first gets the preview box but no sword, and clicking it inspects.
8. **A damage preview always shows.** Whenever a target is pointed at (an
   attack target, or every unit a spell being aimed would hit), a HUD box shows
   the unit's name and the expected result from the existing forecast: exact
   damage for an attack, damage/crit/chance for a spell, HP before → after, and
   KO when lethal.

## Outcome

- The simulator runs side turns with rules 1–6. Headless battles
  (`scripts/battle/run_battle.gd`, `run_championship.gd`) complete under
  them, deterministically.
- The CPU plays a whole side, choosing its own unit order.
- In the interactive hex battle:
  - The party panel, round-order panel, command rail and prompt box are gone.
  - Selecting a unit shows its walkable region as a contour and an icon arc
    (Magic, Item, Status, Wait).
  - Moving and attacking happen on the board, with the sword and the preview
    box.
  - Spent units are darkened.
  - A turn banner and an End turn button with a ready count frame each turn.
- The design docs describe the new rules and screen, not the old ones.

## Present-state facts an executing agent must not "fix"

- **`docs/plans/battle-ui-brigandine-direction.md` is superseded where it
  conflicts with this cycle.** It calls the right-edge Brigandine command rail
  the golden source for commands. Henri replaced that on 2026-09-16. Its window
  frame language (`NoggWindow`, `NoggTheme`, the Brigandine frame art) still
  applies to every box this cycle draws. Do not edit that frozen file, and do
  not restore the rail.
- **Between waves, some probes will fail, and that is expected.** Once
  STB-1 lands, probes that drive the interactive controller (`probe_playthrough`,
  `probe_member_input`, `probe_command_menu`, `probe_party_panel`,
  `probe_inspection`, `probe_scene_contract`, `restoration/probe_session`) may
  fail until STB-4 replaces the flow they drive. A session whose Touches list
  does not own a failing probe reports it in one line and continues.
- **Championship statistics and replay outputs will change.** Rounds now
  contain side turns and act-then-move is gone, so win rates, round counts and
  history lengths change. Do not tune rules to restore old numbers. Records
  written before STB-1 are not expected to replay.
- **Rule 4 removes a supported order on purpose.** `ORDER_ACT_FIRST` exists
  today because act-then-move was legal. Removing that path is the change,
  not a regression.
- The orange square markers left floating over empty cells after units move
  (seen in the 2026-09-16 play session) are a known separate bug. Fix them
  only if a Touches-owned change causes or cures them, and never widen scope
  for them.
- **Interactive playtesting belongs to Henri** (AGENTS.md, Running the checks).
  Sessions may run headless probes and scripted non-interactive capture
  renders. They do not drive an interactive Godot window.

## Items

### STB-1 — Replace party activations with side turns in the simulator

**Model:** Opus 5 / GPT Sol

**Model rationale:** This is the cycle's boundary item. It rewrites the
scheduling core that every other item, the CPU, the replay format and the
headless runners sit on. The single turn accumulator, the one-command-event-
per-turn history and end-of-turn effect ticking all assume one unit at a time,
and rule 3 (a unit can move, be left, and be resumed) breaks that assumption
in ways the code doesn't show up front. The shape of the per-unit turn state
and the history event is a real design decision with determinism and replay
consequences.

**Depends on:** —

**Touches:**
- `src/battle_sim/BattleSimulator.gd`
- `src/battle_sim/BattleState.gd`
- `src/battle_sim/TurnManager.gd`
- `src/battle_sim/BattleEvents.gd`
- `src/battle_sim/BattleCommand.gd`
- `src/battle_sim/BattleCommandResult.gd`
- `src/battle_sim/BattleStateSerializer.gd`
- `src/battle_sim/BattleReplayRunner.gd`
- `src/battle_sim/IBattleVisualAdapter.gd`
- `src/presentation/ConsoleVisualAdapter.gd`
- `src/presentation/BattleRecordAdapter.gd`
- `src/presentation/battle/HexBattleVisualAdapter.gd`: **only** to keep
  it compiling against changed `IBattleVisualAdapter` hooks. No visual change.
- `scripts/hex_battle/probe_activation.gd`
- `scripts/hex_battle/probe_replay.gd`
- `scripts/hex_battle/probe_proving_ground.gd`
- `scripts/hex_battle/probe_runner_ok.gd`
- `scripts/hex_battle/probe_runner_failure.gd`
- `scripts/hex_battle/side_turn/probe_side_turn_rules.gd` (new, plus `.uid`)
- `docs/GAME_DESIGN.md` (turn and action rules)
- `docs/ARCHITECTURE.md` (battle simulation section)
- `docs/MODULE_MAP.md`

**End state:** `BattleSimulator` exposes a side-turn runtime that enforces
rules 1–6. A headless probe proves each rule, including refusals: casting
after moving, moving after acting, selecting a spent unit, undo after acting,
and End turn spending the ready units as Wait. It also proves the turn ends by
itself when the last unit is spent, and that two runs with the same seed
produce identical histories. The old party-activation queue no longer drives
turns. Its remaining public calls are removed or clearly reduced to the
parts parties still own.

**Implementation (brief):**

The problem is that "whose turn is it" moves from one monster to one side,
while a unit may now hold a half-finished turn (moved, not acted) while
another unit acts.

- **Why the current shape exists.** `_turnAccumulator` holds exactly one
  member turn so the interactive path can resolve move and act one step at a
  time while CPU brains and replays submit both at once through
  `executeCommand()`. Either way the turn writes a single aggregate `command`
  history event in `finishTurn()`. That single event is what replays and the
  serializer read.
- **The tension.** Rule 3 needs per-unit pending state that can outlive a
  switch to another unit. Consider what happens when:
  - an undone move's origin cell is now occupied by a unit that moved later;
  - a unit dies or withdraws while it holds a pending move;
  - a pending move is interleaved with another unit's attack, where history
    order and the "one event per unit turn" record disagree.

  Decide how history represents this so a replay reproduces the exact
  interleaving.
- **Also yours to decide:**
  - When per-unit end-of-turn work fires: effect ticks, cooldowns and
    end-of-turn passives. Today it fires when a member turn completes. Pick
    the moment a unit is spent or the side's turn end, and explain the effect
    on durations counted in turns.
  - How sides are ordered within a round. It must be deterministic and
    stated. Carrying over the commander-level/speed ordering at side level is
    one option.
  - What a replay/record format version change looks like, so old records
    fail loudly instead of replaying wrongly.
- **Invariants:**
  - `BattleState` and `BattleSimulator` stay canonical. Presentation never
    mutates state.
  - Identity stays the deterministic `uniqueID`/monster ID.
  - Every refusal returns a reason string, as today.
  - Commander withdrawal and battle-outcome resolution still fire at the same
    logical points.
  - `executeCommand()` still lets a caller submit a unit's whole move+act in
    one call, since the CPU and replays rely on it.

Write your decisions and the reasoning for each in the commit body.

**Risk:** Silent replay divergence, effects that tick twice or never, and a
turn that never ends because a withdrawn or dead unit is counted as ready.
Watch for these with the determinism check and the probe's all-spent case.

**Validation:**
- Self-contained: the new rules probe passes. The owned probes
  (`probe_activation`, `probe_replay`, `probe_proving_ground`,
  `probe_runner_ok`, `probe_runner_failure` with its intended failure exit)
  pass or are rewritten to the new rules. `run_battle.gd` on
  `proving_ground_cpu_cpu.json` seed 7 completes, twice with identical
  output. The headless load check from AGENTS.md is clean.

### STB-2 — Let the CPU play a whole side

**Model:** Opus 5 / GPT Sol

**Model rationale:** The brains were built to answer "what does this member
do" for a party that is already scheduled. Now the CPU also chooses unit
order across several parties, which changes outcomes: a healer acting before
or after a striker, or a blocker moving out of a lane first. That's
behaviour design with a performance budget, not a mechanical port.

**Depends on:** STB-1

**Touches:**
- `src/entity_ai/**`
- `scripts/battle/run_battle.gd`
- `scripts/battle/run_championship.gd`
- `scripts/hex_battle/probe_ai.gd`
- `docs/ARCHITECTURE.md` (entity AI section only)

**End state:** A CPU-controlled side completes its turn through the STB-1
runtime in the headless runners. It picks a unit order by a stated heuristic,
respects rules 3–5 (it never casts after moving), and stays inside a
per-call deliberation budget the interactive controller can slice across
frames. `run_championship.gd` on `proving_ground_cpu_cpu.json` completes a
100-battle run with no stalls or rejected commands.

**Implementation (brief):**
- **The problem.** `PartyCommandDeliberation` and `StateRevision` assume one
  active party and one current member.
- **Constraints:**
  - Deliberation already runs in time slices (the controller's
    `DELIBERATION_BUDGET_MSEC`), and a whole side is more work per turn.
  - Brains must not read presentation.
  - Results must be deterministic for a seed.
- **Yours to decide:** how unit order is chosen (fixed priority, a cheap score,
  or re-deliberating after each unit resolves), and whether moved-but-not-acted
  states are worth exploring for the CPU at all. It may always submit move+act
  together.

Record the heuristic, why, and the championship win-rate/round-count shift
you observed in the commit body. The shift is expected (see Present-state
facts).

**Risk:** CPU turns that take far longer on screen. The 2026-09-16 play
session already measured about 40–50 s of CPU turn per round at 60 fps, so
report deliberation cost per side turn. Other risks: stalls when a brain
proposes a command the new rules refuse.

**Validation:**
- Self-contained: `probe_ai` passes under the new runtime. The 100-battle
  championship run completes. Deliberation time per side turn is reported
  from the run.

### STB-3 — Build the board and screen cues for side turns

**Model:** Opus 5 / GPT Sol

**Model rationale:** Several new presentation pieces must read clearly
together over painted terrain at the native render and under the harshest
retro preset. That's visual judgement across the region contour, spent-unit
darkening, sword marker, icon arc, preview boxes, banner and End turn
button, and it has to follow the project's layered-oscillator motion rules.
The pieces are independent of the controller, which keeps this item
parallel with STB-2, but their look is design work.

**Depends on:** STB-1 (for the adapter hooks it may have changed)

**Touches:**
- `src/presentation/battle/HexBattleVisualAdapter.gd`
- `src/presentation/battle/HexBattleBoardView.gd`
- `src/presentation/battle/HexBattleMeshFactory.gd`
- `src/presentation/battle/shaders/**`
- `src/presentation/battle/ui/side_turn/**` (new)
- `scripts/hex_battle/probe_board_view.gd`
- `scripts/hex_battle/probe_preview.gd`
- `scripts/hex_battle/side_turn/probe_board_cues.gd` (new, plus `.uid`)
- `docs/UI_DESIGN.md` §10a and §10b (board-space treatments)

**End state:** Each cue exists as a presentation component with a small API
the controller can drive, is exercised by `probe_board_cues`, and matches the
storyboard:
1. **Walkable region contour:** one outline around the reachable set plus a
   very faint wash. It replaces the thick-outlined per-cell reach markers.
2. **Spent-unit darkening:** reversible, and it never touches the unit's own
   materials permanently. Mirror how the hover outline uses
   `material_overlay`.
3. **Sword marker:** floats over a targeted unit and follows it through
   playback.
4. **Icon arc:** Magic, Item, Status and Wait, anchored above the selected
   unit, with enabled, disabled and crossed-out states, an Undo chip, and
   flipping below the unit near the board's top edge.
5. **Target preview box:** takes a forecast dictionary, and several can show
   at once for spell areas.
6. **Turn banner:** "Your turn" / "Enemy turn".
7. **End turn button:** shows a ready count and has a confirm state.

**Implementation (brief):**
- **Constraints that aren't obvious from the code:**
  - Screen-space boxes, the icon arc, banner and button are native-resolution
    CanvasLayer UI anchored to projected world positions, the same way damage
    numbers work. They must never render inside the low-res 3D viewport or be
    occluded by world VFX.
  - Default rendering is native, not 640×480. Look at both the default and
    the harshest retro preset.
  - New motion follows `docs/VFX_DESIGN.md`: an entrance that resolves layered
    over an idle that never does, each on its own constants. The selection
    ring's replayable entrance is the local precedent.
  - Boxes use the `NoggWindow`/`NoggTheme` frame family.
  - The preview box shows the forecast's own fields and wording (see
    `HexBattleHud` forecast formatting). It must never compute damage itself.
- **Yours to decide:** exact visual treatment, sizes and motion constants.
  Also how the icon arc avoids covering the cells the player is about to aim
  at: fade, shrink or reposition while aiming. Explain the choice in the
  commit body.
- **Out of bounds:** do not wire any of this into `HexBattleController` or the
  HUD; that's STB-4. Remove the old per-cell reach marker look only where
  the contour replaces it.

**Risk:** Contour gaps on odd-column offsets, darkening that leaks onto the
team plinth or selection ring, and projected UI that drifts during camera pan
or orbit.

**Validation:**
- Self-contained: `probe_board_cues`, `probe_board_view` and `probe_preview`
  pass. The headless load check is clean.
- Deferred: scripted non-interactive captures of each cue at 1280×720,
  default render and harshest retro preset, and while panned/orbited. Judged in
  STB-V.

### STB-4 — Play a side turn in the hex battle

**Model:** Opus 5 / GPT Sol

**Model rationale:** This is where the rules, the CPU and the cues meet a
live input model. Several judgement calls are left open:
- the left-click meaning changes by context (move, attack, inspect,
  select-another-unit);
- right-drag pans the camera while a right tap cancels;
- keyboard parity has to survive the removal of the menu that keyboard input
  used to drive;
- the HUD loses four windows whose information has to land somewhere or be
  consciously dropped.

**Depends on:** STB-1, STB-2, STB-3

**Touches:**
- `src/systems/hex_battle/HexBattleController.gd`
- `src/systems/hex_battle/HexBattleMemberInput.gd`
- `src/systems/hex_battle/HexBattleMemberTurn.gd`
- `src/presentation/battle/HexBattleHud.gd`
- `src/presentation/battle/ui/HexPartyPanel.gd` (+ `.uid`), for removal
- `src/presentation/battle/ui/HexPartyOrderPanel.gd` (+ `.uid`), for removal
- `src/presentation/battle/ui/HexCommandMenu.gd` (+ `.uid`), for removal or
  reduction
- `src/presentation/battle/ui/HexCommandPlate.gd` (+ `.uid`)
- `src/presentation/battle/ui/HexTextBox.gd` (+ `.uid`)
- `src/presentation/battle/ui/HexCharacterStatus.gd`
- `src/presentation/battle/ui/HexGraphicsPanel.gd`
- `src/presentation/theme/HudLayoutCatalog.gd`
- `scenes/battle/HexBattle.tscn`
- `scripts/hex_battle/probe_playthrough.gd`
- `scripts/hex_battle/probe_member_input.gd`
- `scripts/hex_battle/probe_command_menu.gd`
- `scripts/hex_battle/probe_party_panel.gd`
- `scripts/hex_battle/probe_inspection.gd`
- `scripts/hex_battle/probe_scene_contract.gd`
- `scripts/hex_battle/probe_entrypoints.gd`
- `scripts/hex_battle/restoration/probe_session.gd`
- `docs/UI_DESIGN.md` §6 (input model) and §8 (window taxonomy)
- `docs/HEX_BATTLE.md`

**End state:** In `HexBattle.tscn`, a player side turn plays exactly as the
storyboard's frames 1–8:
- the banner shows;
- clicking a unit selects it with the contour and icon arc;
- clicking a walkable cell moves it, crossing out Magic and showing Undo;
- pointing at an enemy in reach shows the sword and preview box, and clicking
  attacks and darkens the unit;
- Magic opens a short spell list whose aim shows a preview box per affected
  unit;
- End turn with ready units asks first;
- when all units are spent the turn passes;
- the enemy side's turn plays under the "Enemy turn" banner with CPU
  deliberation sliced across frames.

The party panel, round-order panel, command rail and prompt box no longer
exist on screen. `probe_playthrough` drives a full player-vs-CPU battle to a
result through the new flow, by mouse-equivalent events and by keyboard.

**Implementation (brief):**
- **The problem.** The controller's input and HUD were built around "the HUD
  offers a member, the member's command rail offers verbs". Both halves are
  gone.
- **Invariants:**
  - Inspection never mutates state.
  - GUI controls consume their own clicks before the board sees them.
  - The STATUS sheet stays modal.
  - A camera drag never also moves a unit or attacks.
  - Right tap still cancels (today: the command menu; now whatever the
    current aim or selection is).
  - Playback ownership (`HexBattlePlayback` claim/release) still prevents
    input into a side that isn't the player's.
  - Session controls in the Debug drawer keep working.
- **Yours to decide:**
  - The full click-resolution rule and its edge cases: clicking a spent unit,
    a friendly unit while one is selected, empty ground, an out-of-reach enemy
    (rule 7 says inspect).
  - The keyboard path. Every action must stay reachable, e.g. Tab cycles
    ready units, number keys map to the icon arc, Enter confirms. Choose and
    document it.
  - Where round number and "whose units are left" live now that the panels
    are gone. The End turn ready count may be enough; say why.
  - Whether `HexCommandMenu` survives as the spell list or is replaced.

Record each decision and its reasoning in the commit body.
- **Out of bounds:** the orange-square marker bug, camera default zoom, and
  CPU playback speed. Note them if seen; don't fix them here.

**Risk:**
- Click ambiguity that attacks when the player meant to inspect.
- A keyboard dead end once the rail is gone.
- A turn that won't end because a unit's pending move is never closed.
- HUD layout regressions at other UI scales in `HudLayoutCatalog`.

**Validation:**
- Self-contained: every owned probe passes, rewritten to the new flow where
  its old subject no longer exists. `probe_party_panel` and
  `probe_command_menu` may be deleted or repurposed; say which. The headless
  load check is clean, and a grep audit confirms no remaining references to
  removed HUD classes.
- Deferred: the side-turn flow against the storyboard, at 1280×720 and at
  one other UI scale, default render and harshest retro preset. Judged in
  STB-V.

### STB-V — Validate the side-turn battle and close the cycle

**Model:** Opus 5 / GPT Sol

**Model rationale:** Acceptance is a fresh-eyes judgement of look and flow
against a storyboard, across work built in three waves by different sessions.
That rules out folding it into STB-4's session. It also carries closing the
cycle and choosing what to promote into `docs/sketches/`.

**Depends on:** STB-1, STB-2, STB-3, STB-4

**Touches:**
- `docs/plans/side-turn-battle.md` (deleted at close)
- `docs/plans/references/side-turn-battle/**` (moved or deleted at close)
- `docs/sketches/**`
- `BACKLOG_CRITICAL.md`
- `BACKLOG_LONGTERM.md`

**End state:**
- Every probe under `scripts/hex_battle/` has been run at one recorded
  revision, with results listed.
- Scripted non-interactive captures cover each storyboard frame at 1280×720,
  default render and harshest retro preset, and are compared frame by frame
  with the storyboard. Mismatches are listed as pass/fail.
- A short playtest checklist is handed to Henri, who owns interactive play.
  It covers: moving, undoing, attacking, casting before moving, being refused
  a cast after moving, End turn with ready units, and a full battle.
- On Henri's pass, the cycle closes: the storyboard is promoted to
  `docs/sketches/2026-09-16-side-turn-battle-flow.html` if it still reflects
  what shipped, open items are moved to the backlogs and named, and this file
  is deleted in the same commit.

**Implementation (brief):** Record the revision and any unrelated in-flight
changes before capturing. A failure in a path this item doesn't own gets
reported and routed back to its item, not fixed here. Henri's playtest is the
acceptance gate: **blocking on Henri**. Don't close the cycle on captures
alone.

**Risk:** Accepting captures that look right while live input feels wrong,
which is why Henri's playtest gates the close.

**Validation:**
- Self-contained: the probe sweep and capture comparison, recorded in the
  commit body.
- Deferred: Henri's playtest, as the blocking gate above.

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | STB-1 | Boundary item; everything builds on the side-turn runtime |
| 2 | STB-2, STB-3 | `src/entity_ai/**` + headless runners + `probe_ai` + ARCHITECTURE AI section vs. board/view/adapter + `ui/side_turn/**` + board probes + UI_DESIGN §10a–b; no shared path |
| 3 | STB-4 | Controller, member input, HUD and interactive probes; needs both wave-2 items |
| 4 | STB-V | Standalone validation: look-and-feel judgement across three waves, gated on Henri's playtest |

STB-1 and STB-3 both list `HexBattleVisualAdapter.gd`, but in different waves:
STB-1 only keeps it compiling, and STB-3 owns its visuals. `docs/UI_DESIGN.md`
is written by STB-3 (§10a–b) and STB-4 (§6, §8) in different waves.
`docs/ARCHITECTURE.md` is written by STB-1 (simulation) and STB-2 (AI) in
different waves.

## Deliberately excluded

- **Speed-based initiative of any kind**, including per-unit ordering inside a
  side. Henri removed it.
- **A bottom ability bar or a Brigandine right-edge rail** for commands. Both
  were considered in the 2026-09-16 research and rejected in favour of the icon
  arc.
- **Moving and attacking in one gesture** (Fire Emblem Heroes style
  drag-onto-enemy). Out-of-reach enemies get a preview but no sword.
- **A second click to confirm an attack.** The hover preview is the
  confirmation.
- **Camera default zoom, CPU playback speed and the orange-square marker
  bug.** These were real findings from the 2026-09-16 play session, but they
  belong to separate work.
- **Balance changes** to damage, HP or spells, even though battles now run
  differently.
