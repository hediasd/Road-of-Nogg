# Hex battle playable

Prepared 2026-09-08. **Queued; execution has not started.** The hex battle
migration made hex the active product and proved the simulation end to end, but
it stopped short of a playable tactical game: a player can choose which member
acts and can end a party, and cannot issue a move, an attack or a spell through
any interface. This cycle closes that gap and the smaller ones the migration
left behind. It does not add systems the migration deferred — no command radius,
no enclosure bonuses, no capture, no campaign.

Authoring this file does not open its cycle. It may be committed on `main` under
the window rule; execution opens `plan/hex-battle-playable` in a quiet tree.

## Outcome

1. A player can play a whole hex battle from the keyboard and the mouse: choose
   a member, aim, move, undo, attack or cast, and end a party, with every
   command going through `BattleSimulator`'s existing phase API.
2. Before confirming, the player can see what a command will do — where it
   reaches, which cells it affects, and what it is forecast to cost the target.
3. The exit-time access violation has a named cause and a reproducer, whether or
   not the fix lands in this cycle.
4. No documentation describes behaviour the code no longer has.

## Present-state facts an executing agent must not "fix"

- `HexBattleMemberTurn` already exposes `confirmMove`, `confirmAction` and
  `undoMove`, and `HexBattleCursor` already resolves all six neighbours through
  the live camera. **Nothing in `src/` calls them.** That is the gap, not a bug
  in those files — they were built to a contract and left unwired, and the
  acceptance harness drove them directly. Do not rewrite them because they look
  unused.
- The party panel is the whole HUD on purpose. There is no turn order rail
  because ordinary member speed no longer schedules anything; do not restore one.
- `BattleReplayRunner` compares a `jsonSafe` recorded result against a
  `jsonSafe` live one, and drops `lastTurnStartIndex` from its projection. Both
  look like missing comparisons and are deliberate — HXB-V's commit explains
  why, and `probe_replay.gd` fails if either is reverted.
- A battle map is flat across its playable area, and that is now a DECISION
  rather than a limitation -- the user chose flat on 2026-09-08. Terrain heights
  are continuous over the shared hex vertex lattice, so two adjacent playable
  cells cannot differ in elevation without a slope between them, and the export
  refuses a sloped cell rather than rounding it. Do not add a height layer to a
  battle map and do not soften the refusal. See "Deliberately excluded".
- Several files under `src/presentation/effects/` describe
  `ShapeCaster.getCircle` as a Manhattan diamond. That was true before HXB-7 and
  is false now. HBP-5 owns correcting it; no other item may.

## A note on the evidence this cycle inherits

HXB-9 through HXB-14 were implemented and then validated by the same session,
against the migration plan's own instruction that validation not be folded into
the implementing session. The findings recorded there are real and were
reproduced by reverting the fixes, but nothing in that cycle has had an
independent read. `HBP-V` is the first genuinely fresh pair of eyes on it and
should spend some of its budget accordingly.

## Items

### HBP-1 — Wire a member turn to real input

**Model:** Opus 5 / GPT Sol

**Model rationale:** This is the composition boundary the migration stopped at:
input ownership, phase order, undo eligibility, mouse-versus-keyboard intent,
HUD focus, and the playback gate all meet here, and most failures cross several
of them. The individual pieces exist; deciding how they compose, and what the
player is allowed to do when, is the session's call.

**Depends on:** HBP-2, HBP-3.

**Touches:**
- `src/systems/hex_battle/**`
- `src/presentation/battle/HexBattleCursor.gd`
- `src/presentation/battle/HexBattleHud.gd`
- `scripts/hex_battle/probe_member_input.gd`
- `docs/GAME_DESIGN.md`

**End state:** With a player party active, the cursor is driveable by keyboard
and by mouse hover; a reachable cell can be confirmed as a move and undone while
undo is still legal; an action can be chosen from HBP-2's menu and confirmed
against a target; and a member turn ends by acting or waiting. Every command
goes through `executeMovePhase` / `executeActionPhase` / `undoMovePhase` /
`finishTurn`. The playback gate still has exactly one owner.

**Implementation:** Reuse `PlayerTurnController`'s phase *shape* — the migration
already established that as the simulator's contract rather than a square-board
idea — without reviving its rectangular clamping or quadrant rotation, both of
which are wrong on a hex board and both of which are preserved in the frozen
reference if anyone needs to read them.

The tension worth naming: mouse and keyboard must not disagree about what is
selected. The migration's cursor resolves direction in screen space against the
live camera, so a hover and an arrow key both resolve to a cell — decide which
owns the cursor when both are live, and say why in the commit. Undo eligibility
is the simulator's answer, not this item's; ask it rather than tracking a
parallel flag. Do not let input reach a party that is not the player's, and do
not open a member turn while the gate is held — `HexBattlePlayback` already
refuses both, so route through it rather than re-checking conditions locally.

**Risk:** Input reaching a stale party, a second member turn opening over an
open one, undo offered after it has become illegal, or the cursor and the
confirmed command disagreeing about which cell was meant.

**Validation:**
- Self-contained: run the launcher with `-Script res://scripts/hex_battle/probe_member_input.gd -Marker HXB_INPUT_OK`.
  Assert phase ordering and rejection, that undo follows the simulator's own
  eligibility, that the gate is claimed and released exactly once per member
  turn, and that a synthetic direction resolves to the same cell the confirmed
  command carries. Do not call controller handlers directly as a substitute for
  a driven cursor.
- Deferred: HBP-V plays a whole battle from real input, both devices, all six
  directions under a rotated camera.

### HBP-2 — Build the hex command menu from a supplied view model

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A bounded widget with a fixed data shape and two signals,
composed from existing theme controls, mirroring `HexPartyPanel` which already
proved the pattern. It makes no scheduling, targeting or theme decisions.

**Depends on:** none.

**Touches:**
- `src/presentation/battle/ui/HexCommandMenu.gd`
- `scripts/hex_battle/probe_command_menu.gd`

**End state:** A `Control` `HexCommandMenu` exposing
`updateModel(model: Dictionary) -> void`,
`signal command_chosen(commandID: String)`, and
`signal cancelled()`. It renders the supplied commands in supplied order and
emits only for enabled entries when input is enabled.

**Implementation:** View-model keys are `input_enabled: bool`, `title: String`,
and `commands: Array[Dictionary]`. Each command has `id: String`,
`label: String`, `enabled: bool`, `detail: String` (a short right-column value,
which may be empty), and `spent: bool`. Render in supplied order without
sorting; never derive `enabled`. An unknown id is an authoring error, not a
silently dropped row.

Mirror `HexPartyPanel.gd` exactly in shape: one `NoggWindow`, a header row that
is never interactive, rows built through `set_full_rows`, wiring connected once
in `_init` from the window's `row_built` signal, and a "Cancel" row emitting
`cancelled()` the way that panel's End Party row emits its own signal. Read
`docs/UI_DESIGN.md` for the row and token rules; do not edit shared theme files,
`HexPartyPanel`, `PlayerCommandMenu`, or any controller. An empty model clears
the menu.

**Implementation note on tests:** a `NoggWindow` builds its content in
`_ready()`, and `_ready()` is not synchronous with `add_child()` in a `--script`
SceneTree — defer the probe's checks to one `process_frame` signal, exactly as
`probe_party_panel.gd` does, or `add_row` finds a null container.

**Risk:** A stale menu offering a command the phase no longer allows, or
emitting twice after a refresh.

**Validation:**
- Self-contained: run the launcher with `-Script res://scripts/hex_battle/probe_command_menu.gd -Marker HXB_MENU_OK`.
  Feed empty, enabled, disabled and spent models; assert enabled states,
  supplied ordering, the emitted id, that a disabled row emits nothing, and that
  one click after repeated `updateModel` calls emits exactly once.
- Deferred: HBP-V checks readability, focus and keyboard use in the real scene.

### HBP-3 — Show what a command will do before it is confirmed

**Model:** Opus 5 / GPT Sol

**Model rationale:** What to show, and how much of it, is a judgement about
legibility rather than a specification — a preview that draws everything is as
useless as one that draws nothing. It also has to stay honest about uncertainty,
which is a design decision with a correctness edge.

**Depends on:** none.

**Touches:**
- `src/presentation/battle/HexBattleVisualAdapter.gd`
- `scripts/hex_battle/probe_preview.gd`
- `docs/UI_DESIGN.md`

**End state:** The adapter can draw, and clear, a preview of a pending command:
the cells a move would cross, and the cells an action would affect, distinct
from each other and from the existing reach overlay. A forecast value for a
pending action is available to the HUD as data.

**Implementation:** The affected set comes from the same resolver the simulation
will use — HXB-7's queries and HXB-11's `HexVfxFootprint`. Do not re-derive a
shape from a radius; that is the exact drift the migration spent an item
removing, and a preview that disagrees with the resolution is worse than none.

The forecast is a number the player will trust, so it must come from the same
`CombatResolver` maths a real resolution uses, and it must say when it does not
know — a roll has a range, and presenting one number as certainty is a lie the
square battle's own backlog already complains about. Deciding how to present a
range rather than a point is this item's call.

Overlay layers must be independent: a preview must not destroy the reach the
player is aiming from, the same way the square battle kept threat and hover as
separate layers. Do not edit the HUD, the controller, or the member turn.

**Risk:** A preview that shows more or fewer cells than the command will affect,
a forecast that reads as certain when it is not, or a preview layer that clears
the overlay underneath it.

**Validation:**
- Self-contained: run the launcher with `-Script res://scripts/hex_battle/probe_preview.gd -Marker HXB_PREVIEW_OK`.
  Assert the previewed cell set equals the resolver's own affected set for a
  disc, a ring, a line and a set clipped by a wall; that clearing a preview
  leaves the reach overlay intact; and that the forecast agrees with
  `CombatResolver` for a fixed seed.
- Deferred: HBP-V judges whether the preview is legible at real camera angles
  and render scales.

### HBP-4 — Find the cause of the exit-time access violation

**Model:** Opus 5 / GPT Sol

**Model rationale:** A shutdown-ordering fault with no stack trace, reachable
only through a particular mix of live objects. It is a diagnosis, and its write
set cannot be stated until it is diagnosed — which is exactly why this item
diagnoses and does not fix.

**Depends on:** none.

**Touches:**
- `scripts/hex_battle/probe_shutdown.gd`
- `docs/LEARNINGS.md`
- `BACKLOG_CRITICAL.md`

**End state:** A committed reproducer, and a named cause: which objects retain
which, and why the retention outlives the resource system. No production file is
modified by this item.

**Implementation:** HXB-V narrowed it and the evidence is in
`BACKLOG_CRITICAL.md` — all fourteen donor profiles are clean to 42 effects,
each hex subclass is clean alone, repeated, and with a real footprint and ground
wash, clearing the static texture cache does not help, and the crash needs a
particular mix of classes alive at once. Start from that table rather than
re-deriving it.

`--verbose --quit-after 2` enumerates the retained resource graph; the backlog
entry names the roots the square battle retained, which is a starting hypothesis
and not a conclusion. **The fix is deliberately out of scope.** Breaking an
ownership cycle in shared theme or effect code is a change whose blast radius
cannot be judged before the cycle is known, and this cycle is about playability.
Record what a fix would have to touch so the follow-on item can state its write
set.

**Risk:** Concluding from a leak report rather than from the crash; a
"reproducer" that depends on machine timing.

**Validation:**
- Self-contained: run the launcher with `-Script res://scripts/hex_battle/probe_shutdown.gd -Marker HXB_SHUTDOWN_OK`.
  The probe must reproduce the fault deliberately and assert it, so it fails if
  the crash silently stops happening — a reproducer that passes when the bug is
  present and fails when it is gone, stated that way round in its own header.
- Deferred: none.

### HBP-5 — Correct the effect headers that describe a shape the code no longer casts

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A bounded, literal documentation correction with an exact
file list and an exact wrong claim to replace. No judgement and no behaviour.

**Depends on:** none.

**Touches:**
- `src/presentation/effects/FireStormEffect.gd`
- `src/presentation/effects/IceStormEffect.gd`
- `src/presentation/effects/MagentaReductionEffect.gd`
- `src/presentation/effects/MagentaReductionProfile.gd`
- `src/presentation/effects/VfxTextures.gd`
- `src/presentation/debug/VfxDebugWorld.gd`

**End state:** No file under `src/presentation/effects/` or
`src/presentation/debug/` claims that `ShapeCaster.getCircle` produces a
Manhattan diamond. Each corrected comment says what is true now — that it
returns a hex disc since HXB-7 — and, where the surrounding note explains an
authored proportion that was chosen against a diamond, says that the proportion
predates the change rather than silently implying it was chosen for a disc.

**Implementation:** Comments only. **Change no code, no constant, and no
authored value.** These files are donors: HXB-11 built hex variants as
subclasses precisely so the donors keep their behaviour exactly, and an
"obvious" numeric fix here would change an effect nobody asked to change.

`docs/VFX_DESIGN.md` section 8 records this drift and why the migration could
not act on it; leave that record in place — it explains why the correction is a
separate item. Grep for `Manhattan` and `diamond` to find the full set; the
Touches list is what was found on 2026-09-08 and may have grown.

**Risk:** Editing a value while editing the comment beside it.

**Validation:**
- Self-contained: grep the two directories for `Manhattan` and record the
  result in the commit; `git diff --check`; and confirm the diff contains no
  line that is not a comment.
- Deferred: none.

### HBP-6 — Author a neutral proving map

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** The brief is now fixed and the pipeline is documented end to
end: a map with named tactical features, exported through a route that already
works. No creative or lore decision remains, because the map is deliberately
unplaced.

**Depends on:** none.

**Touches:**
- `data/worldmap/authored/proving_ground.json`
- `data/worldmap/regions.json`
- `data/battle/maps/proving_ground.json`
- `data/battle/scenarios/proving_ground_player_cpu.json`
- `data/battle/scenarios/proving_ground_cpu_cpu.json`
- `assets/worldmap/regions/generated/proving_ground.png`
- `assets/worldmap/regions/generated/proving_ground.png.import`
- `scripts/hex_battle/probe_proving_ground.gd`

**End state:** A region `proving_ground` whose tactical layer exercises the whole
vocabulary the battle supports, exported as `data/battle/maps/proving_ground.json`
and bound by two scenarios -- one Player vs CPU, one CPU vs CPU -- both
selectable from the setup screen and both playable to a result.

**Implementation:** The map is a TEST INSTRUMENT, not content. It is deliberately
unplaced and unlore'd; do not name it after anywhere, and do not invent a
setting for it.

It must contain, and the probe must assert, all of: cells in both column
parities; a `rough` band that makes at least one route genuinely cheaper than a
shorter one; `blocked` cells that break line of sight; a chokepoint no wider
than one cell; at least one hole inside the board rather than on its edge; and
two deployment areas far enough apart that the first round is spent closing.
FLAT THROUGHOUT -- see "Deliberately excluded"; a height layer is a defect here,
not an enhancement.

Reuse the `temp2_hex32_ground` tileset for art, exactly as `hex_battle_fixture`
does. Art is not the point and new art is out of scope. Follow
`docs/WORLDMAP_EDITOR.md` section 20 for the bake, the `--headless --import`
step and the export; `--headless --editor --quit` does not satisfy the import
prerequisite. Add only this region to `regions.json` and preserve every other
entry. Model the scenarios on the committed `technical_hxb_contract_*` files.

**Risk:** A map that exercises the vocabulary on paper and plays as an open
field; a scenario whose deployment lets one side reach the other before the
player has made a decision.

**Validation:**
- Self-contained: run the launcher with `-Script res://scripts/hex_battle/probe_proving_ground.gd -Marker HXB_PROVING_OK`.
  Assert every feature listed above is present in the exported map by
  coordinate, that both scenarios load through `BattleScenarioFactory`, and that
  a CPU vs CPU run of each reaches a result within thirty rounds.
- Deferred: HBP-V plays it and judges whether it is worth playing.

### HBP-V — Validate the playable battle, then close the cycle

**Model:** Opus 5 / GPT Sol

**Model rationale:** Acceptance is a judgement about whether the battle is
actually playable — legibility, responsiveness, whether the six directions feel
reachable — which cannot be folded into the session that built it.

**Depends on:** HBP-1 through HBP-6, all committed.

**Touches:**
- `src/systems/hex_battle/**`
- `src/presentation/battle/**`
- `scripts/hex_battle/**`
- `docs/GAME_DESIGN.md`
- `docs/UI_DESIGN.md`
- `docs/VFX_DESIGN.md`
- `BACKLOG_CRITICAL.md`
- `BACKLOG_LONGTERM.md`
- `docs/plans/hex-battle-playable.md` (lifecycle deletion only after passing)

**End state:** A whole Player vs CPU battle is played from real input, defects
found are fixed within this surface, and the cycle merges.

**Implementation:** Run alone, after the user confirms no session is editing.
Play a battle rather than driving the API: choose members, aim with both
devices, move, undo, attack, cast, cancel, end parties, and reach a result. Then
do it again on a rotated camera and a reduced render scale.

Spend part of the budget reading the migration's own work with fresh eyes — see
"A note on the evidence this cycle inherits". The self-contained probes there
all pass; what has never been checked independently is whether they check the
right things.

**Risk:** Accepting a battle that is technically driveable and unpleasant to
play, or repeating the migration's pattern of a probe that passes because it
only exercises the easy case.

**Validation:**
- Self-contained: rerun every `scripts/hex_battle/` probe, focused diffs,
  `git diff --check`. Record the acceptance matrix and any remaining limitation
  in the commit.
- Deferred: all integrated play. A failure holds merge.

## Waves

| Wave | Items and suggested models | Why disjoint |
|---|---|---|
| 1 | HBP-2 — **Sonnet 5 / GPT Terra**; HBP-3 — **Opus 5 / GPT Sol**; HBP-4 — **Opus 5 / GPT Sol**; HBP-5 — **Sonnet 5 / GPT Terra**; HBP-6 — **Sonnet 5 / GPT Terra** | A new menu widget, the adapter's preview layers, a diagnosis that writes only docs and a probe, a comment-only correction in the donor effects, and a new map with its own data files. Five disjoint write sets, no shared file. |
| 2 | HBP-1 — **Opus 5 / GPT Sol** | Wires the menu and the preview into the controller, member turn, cursor and HUD; needs both committed. |
| 3 | HBP-V — **Opus 5 / GPT Sol** | **Validation: standalone, alone, quiet tree** — independent judgement of whether the battle plays. |

Wave 1 is five separate sessions. HBP-2, HBP-5 and HBP-6 are specifications and
can be dispatched without further reading; HBP-3 and HBP-4 are briefs.

## Deliberately excluded

- **Stepped tactical elevation. DECIDED 2026-09-08: battlefields stay flat.**
  The user was asked and chose flat over a separate tactical height layer and
  over quantising the shared surface model. So a battle map is flat across its
  playable area, terrain variety comes from movement cost and blocking rather
  than from height, and the export's refusal of a sloped cell is correct
  behaviour rather than a limitation waiting to be lifted. No item in this cycle
  may add elevation, and nobody should re-propose it without a new decision.
- **A lore-placed battle map.** HBP-6 authors a deliberately unlore'd proving
  map instead. Where a battle map sits in the world, and what it should read as,
  is a creative decision this cycle must not make on the user's behalf.
- **Everything the migration deferred**: command radius, enclosure bonuses,
  allied pass-through, flight, terrain defence and evasion, voluntary retreat,
  capture, turn limits, reinforcement, campaign consequences. Deferring one
  again does not declare it unwanted.
- **Fixing the exit-time crash.** HBP-4 diagnoses it. The fix waits on knowing
  what it touches.
