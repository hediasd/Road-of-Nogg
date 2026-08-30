# Battle camera direction

Opened 2026-08-30. The battle camera has never been directed. `BattleCameraDirector`
exists, is documented in `docs/UI_DESIGN.md` §9 as though it ships, and has never run
a single frame — `set_enabled()` has no caller anywhere in the project, so `_enabled`
is `false` for the life of every battle and all four of its hooks return on their
first line. This cycle switches it on, gives it the states it was missing, and stops
the battle opening at an angle nobody chose.

It also builds the setup-screen board preview, **first**, because that preview is the
only place the opening angle can honestly be judged: `docs/sketches/2026-08-29-battle-camera-behaviour-and-opening-framing.html`
approximates the projection in HTML, but it cannot show the retro preset, the CRT
pass, the sky, the lighting, or how a model actually reads against a tile. The
preview is the same board under the real renderer, so it is both a feature and this
cycle's instrument.

This is **not** a cinematics cycle. There is no establishing shot, no KO camera, no
second `Camera3D`, and no rig blending. The camera guarantees you can see the thing
that matters and gets out of the way; every row of the sketch's §3 table is that and
nothing more.

## Outcome

When this closes:

- The setup screen shows the battle you have configured — its map, its terrain, its
  two rosters standing on their deployment slots — orbiting slowly behind the menu,
  rebuilt as you change the dropdowns.
- Every battle opens square to the board at yaw 0, at a zoom that actually fits the
  board, with angles that were chosen rather than inherited from a placeholder.
- The director drives every battle. There is no mode toggle, and `docs/UI_DESIGN.md`
  §9 no longer describes one.
- The camera frames the acting unit, follows the tile cursor without turning the
  board into a treadmill, follows a piece while it moves, orbits while a CPU thinks,
  pulls back for a wide spell, settles to a quadrant before you aim, and abandons all
  of it the instant you grab the camera yourself.
- The opening pitch and the orbit rate are numbers somebody looked at, not defaults
  nobody has ever seen.

## Present-state facts an executing agent must not "fix"

- **The opening pitch stays at 55.77° until CAM-6.** CAM-4 squares the yaw to 0 and
  fixes the zoom, deliberately leaving pitch alone, so that exactly one variable
  changes before the preview exists to judge the second. Do not "while I'm here" it
  to 38°. CAM-6 is the item that sets it, from what a human actually saw.

- **`camera.radius` (18.14) does nothing and is not a bug.** Under an orthographic
  projection the camera's distance from its focus has no effect on the image; only
  near/far clipping cares. Do not tune it, do not derive it from board size, do not
  "fix" the fact that it was computed from placeholder vectors.

- **`_orbit_rate_deg` is a rate integrated in `_process`, not a tween, and that is
  deliberate.** A CPU turn's length is not known when deliberation starts, so there
  is no end angle to tween toward. The reason is already written in the field comment.
  Leave the shape alone; CAM-6 changes only the number.

- **The `panFocusTo()` / `frameTo()` split is load-bearing.** One is position-only and
  may be used against a view the player set; the other takes authorship. Do not
  collapse them into a single call with a flag.

- **`_frame_unit()`'s off-screen-only test becomes unreachable once the director is
  always on.** That is expected, not a regression. CAM-5 owns the decision about
  whether to delete it; no earlier item should.

- **The battle's opening zoom number changes in CAM-4**, from
  `max(w, h) * 0.95 + elevation * 0.35` to a real fit against aspect and pitch. On
  Meadow at 16:9 that is 15.55 → about 11.2. Any check that records the old number is
  recording a defect; update it, do not restore it.

- **`default_size` is currently the stale placeholder `14.0`**, snapshotted in
  `_ready()` before the board is known, which is why a double-middle-click reset
  returns to a pre-battle framing. CAM-4 fixes this as part of applying the opening
  view. Do not fix it anywhere else.

- **Damage numbers and status badges are native-resolution `CanvasLayer` UI**, not
  world geometry. Camera motion cannot occlude them and they need no camera-space
  handling. They do read `unproject_position()` to follow their units, which is
  exactly why this cycle keeps one camera.

- **The setup panel is a hand-rolled blue `PanelContainer` that predates
  `NoggTheme`.** Putting a real battlefield behind it in CAM-1 will make that obvious.
  It is out of scope — see Deliberately excluded. CAM-1 changes the dim alpha and
  nothing else about how that panel looks.

- **`BattleSimulator.startBattle()` is pure**: it snapshots initial state and emits
  `battle_started`. It does not start a round, a turn, or a timer. This is what makes
  CAM-1 cheap, and it corrects the sketch's §8, which assumed a terrain-only build
  path would have to be extracted from `GodotVisualAdapter._on_battle_started()`.
  It does not. Build the real simulator and never call `turnManager.startNewRound()`.

## Items

### CAM-1 — Preview the configured battle behind the setup menu

**Model:** Opus 5 / GPT Sol

**Model rationale:** This introduces a second `BattleSimulator` and a second
`GodotVisualAdapter` that live outside `Lifecycle.BATTLE`, in a controller whose
entire structure assumes exactly one of each and disposes them in `_show_setup()`.
The judgment is in the lifetime boundary — when the preview is built relative to that
teardown, what owns it, what happens on confirm, and how it avoids leaking a
simulator into the battle that follows. Getting that boundary wrong produces a class
of bug (a disposed adapter queried, or a second sim quietly running turns) that no
mechanical rule catches. The dim-alpha and rebuild-cadence calls are feel judgments
on top.

**Depends on:** nothing.

**Touches:**
- `src/systems/BattlePresentationController.gd`
- `src/presentation/BattleSetupUI.gd`
- `src/presentation/BattleSetupUIRefs.gd`

**End state:** With the setup menu showing, the world behind it shows the configured
battle: the selected map's terrain and elevation, and both rosters standing on their
deployment slots. The camera sits at yaw 0 framing the whole board and orbits slowly.
Changing map, mode, preset, or any monster slot rebuilds the preview to match.
Pressing Confirm disposes the preview and the battle builds exactly as it does today.
Returning to setup from a finished battle produces a live preview again. No turn ever
runs while the menu is up.

**Implementation:** The preview is a real simulator, built the way the battle's is —
`BattleSetupFactory.createSimulator(config, <preview adapter factory>)` followed by
`startBattle()`, and never `turnManager.startNewRound()`. `startBattle()` only
snapshots and emits `battle_started`, which is what makes the adapter build terrain
and models; nothing else in the simulator moves. `lifecycle` stays `Lifecycle.SETUP`
throughout, and every turn path in this controller already guards on
`lifecycle == Lifecycle.BATTLE`, so the preview cannot start a turn even by accident
— preserve that property rather than adding new guards.

Build the preview at the *end* of `_show_setup()`, after the existing teardown nulls
`sim` and `visual_adapter`, so there is one teardown path rather than two. The
preview's adapter factory must not construct `camera_director` the way
`_create_visual_adapter()` does; a director querying a preview adapter for unit
positions is precisely the leak this item exists to avoid.

Rebuild on `item_selected` for the map dropdown (currently unconnected — the map is
read once, at confirm) and on the existing preset/monster/mode callbacks. Defer the
rebuild to the end of frame so a burst of dropdown changes costs one rebuild;
Forest is 16×16 with columns several blocks deep, which is a few hundred meshes.
Never rebuild per frame.

Drop the full-rect dim in `BattleSetupUI` from `Color(0.015, 0.025, 0.06, 0.82)` to
roughly `0.55`, judged against the panel's text remaining comfortably readable at the
harshest render preset, not just at native resolution.

Start the preview camera at yaw 0 and orbit from there, so the resting frame of the
preview is already the candidate opening shot CAM-4 will set and CAM-6 will tune.

**Risk:** Two simulators alive at once is the failure mode. Symptoms to watch for: a
battle that opens with doubled models, a `dispose()` on an already-disposed adapter,
or the turn timer firing during setup. Verify by opening setup, changing every
dropdown, confirming, finishing a battle, returning to setup, and confirming again —
the second battle must be indistinguishable from the first. Secondary risk: the
preview adapter builds damage-number and status-badge `CanvasLayer`s it will never
use; confirm they are torn down with it.

**Adds to final validation:** Setup preview builds, rebuilds on every dropdown, and
disposes cleanly across two consecutive battles with a return to setup between them.

### CAM-2 — Signal the player turn's phase and cursor

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** One file, one mechanical shape already used five times in it —
`PlayerTurnController` emits `menu_changed`, `status_changed`, `forecast_changed`,
`turn_order_preview_changed` and `turn_finished` today, and this adds two more
alongside them. The end state is fully stated, there is no consumer yet to design
against, and no boundary moves: the controller already owns phase and cursor as
private state and already signals other transitions out of it.

**Depends on:** nothing.

**Touches:**
- `src/systems/PlayerTurnController.gd`

**End state:** `PlayerTurnController` emits `phase_changed(phase: Phase)` whenever
`phase` changes, and `cursor_changed(pos: Vector2i)` whenever `gridCursor` changes,
including the changes made inside `setCursor()`, `moveCursor()`, `beginTurn()`,
`cancel()` and `confirmSelection()`. Both are emitted after the state has settled, not
before. No existing signal changes, and with nothing connected the battle behaves
exactly as it does today.

**Implementation:** Emit from wherever the field is actually assigned rather than from
each caller, so no future path can move the cursor silently. `Phase` is already a
public enum on this class, so the signal can carry it directly. Do not emit on a
no-op assignment — the aiming camera in CAM-5 is edge-triggered and a stream of
identical positions is noise it would have to filter.

**Risk:** Low. The realistic failure is a missed assignment site leaving one path
silent, which shows up in CAM-5 as a camera that stops following the cursor in one
specific phase. Grep every write to `phase` and `gridCursor` before finishing.

**Adds to final validation:** Cursor and phase signals fire for keyboard aiming, mouse
hover aiming, cancel, and confirm, in both the move and target phases.

### CAM-3 — Give the controller a follow verb and a tweenable pitch

**Model:** Opus 5 / GPT Sol

**Model rationale:** This adds a third category to a file whose entire documented
contract is currently a two-way split — position-only versus authorship-taking. A
per-frame follow is neither: it takes a moving target but must stay position-only, and
it has to interact correctly with `_cancelDirectorMotion()`, with an in-flight
`frameTo()`, and with the player grabbing the camera mid-follow. Deciding which
category it joins, and what cancels it, is a boundary judgment in the one file where
this cycle's invariants live. Pitch is smaller but lands in the same contract.

**Depends on:** nothing.

**Touches:**
- `src/presentation/BattleCameraController.gd`

**End state:** `followTarget(getter: Callable, lag: float)` drives `focus_point`
toward whatever the callable returns, every frame, until `stopFollowing()` or any
existing cancellation path ends it. It is position-only: it never touches
`current_yaw`, `current_pitch`, or `size`. `isFollowing()` reports it.
`_cancelDirectorMotion()` cancels it, so player input abandons a follow exactly the
way it abandons a pan or an orbit. Separately, pitch becomes settable through a tween
in the same shape as the yaw settle, so a caller can move it without writing
`current_pitch` directly.

**Implementation:** Integrate in `_process` next to the orbit rate, before
`_update_camera_transform()`, and use exponential smoothing toward the target rather
than a fixed speed — a fixed speed either lags a fast tween or snaps on a short move.
The lag is a time constant, not a distance. A follow whose callable returns `null`
must end itself rather than hold a stale focus; the unit it was following may have
been defeated mid-animation.

Cancelling on player input is the point where this could go wrong quietly: a follow
that survives a middle-drag would fight the player for the focus every frame, which
is worse than any behaviour the camera has today.

**Risk:** The interaction surface is `_process` and `_cancelDirectorMotion()`, both of
which every other camera motion already uses. A follow left running is invisible until
the next state tries to frame something and is dragged off it. Add the cancel path
first, then the follow.

**Adds to final validation:** A follow released by its own callable returning `null`,
a follow cancelled by player input mid-motion, and a pitch tween that `restoreFreeView()`
correctly reverses.

### CAM-4 — Open every battle at an explicit framing, with the director driving

**Model:** Opus 5 / GPT Sol

**Model rationale:** The switch-on is not the one-line change it looks like.
`_battle_framing_size` and `_resting_size` are captured inside `set_enabled(true)`, so
defaulting `_enabled` to true leaves them at zero and every `frameTo()` at the resting
zoom would frame to size 0. Making the director always-on therefore means deciding
where the battle framing is announced to it, and what happens to the
snapshot/restore machinery that only existed to make a mode switch reversible. That is
a contract change in a file whose comments argue for the two-mode split at length, and
it spans three files at once.

**Depends on:** CAM-1 (shares `BattlePresentationController.gd`), CAM-3 (shares
`BattleCameraController.gd`).

**Touches:**
- `src/presentation/BattleCameraController.gd`
- `src/presentation/BattleCameraDirector.gd`
- `src/systems/BattlePresentationController.gd`

**End state:** Every battle opens with the board square to the screen — yaw exactly 0
— at a zoom that fits the board with about a tile of margin at the current aspect and
pitch, focused on the board centre. Pitch is unchanged at its present value, held in a
named constant so CAM-6 changes one number. `default_yaw`, `default_pitch`,
`default_size` and `default_focus_point` reflect the battle's real framing, so a
double-middle-click reset returns to the opening shot rather than to a pre-battle
placeholder. The director is driving from the first turn, with no toggle and no caller
of `set_enabled()`. `_battle_framing_size` and `_resting_size` are correct.

**Implementation:** Put the fit on the controller, which is the object that knows its
own viewport aspect: given board extents, a pitch and a margin, return the smallest
`size` that contains the board. Note it goes width-bound on the wide maps — Meadow is
16 tiles across against a 16:9 frame — so a lower pitch does not buy a tighter frame,
it only adds vertical slack. That is expected and is not a reason to over-tighten the
margin.

Add one entry point that applies a complete opening view — yaw, pitch, size, focus —
and refreshes the `default_*` snapshot from it, so the two cannot drift apart again.
`_ready()` deriving angles from a placeholder position is the defect being closed;
leave `_ready()` able to do it for the pre-battle case, but make the battle path
authoritative.

Route CAM-1's preview framing through the same entry point rather than leaving two
places that compute a board framing.

For the director: replace the `set_enabled()` capture with an explicit call made when
the battle framing is applied, and delete the mode plumbing that no longer has two
modes to switch between — `snapshotFreeView()` / `restoreFreeView()` exist to make a
mode switch reversible, and with no mode switch they have no caller. Do not delete
them silently: say in the commit body which of them died and why, because
`docs/UI_DESIGN.md` §9 currently documents them as the guarantee that makes director
mode acceptable, and CAM-7 has to rewrite that section from what actually happened.

**Risk:** The framing fit is the part most likely to be subtly wrong, and it is wrong
in a way that looks fine on Meadow and bad on Forest — check all three maps and both
aspects. The director's captured sizes are the part most likely to be wrong silently:
if `_resting_size` is zero, the first `frameTo()` collapses the view entirely, which
is obvious; if it is merely stale, the resting zoom is subtly wrong all game, which is
not.

**Adds to final validation:** All three maps open square, fitted, and identical across
two consecutive battles; middle-click reset returns to the opening shot; the CPU-turn
orbit and the cast pull-back visibly happen for the first time.

### CAM-5 — Drive the camera from a state machine

**Model:** Opus 5 / GPT Sol

**Model rationale:** This is the architectural item. `BattleCameraDirector` is
currently four entry points that each independently decide what the camera should do;
this turns it into one place that decides, with the states and priorities from the
sketch's §3, including the two rows carrying all the risk — edge-triggered cursor
follow, which is the difference between a helpful camera and a nauseating one, and
movement follow, which has no precedent in the file. It also decides the fate of
`_frame_unit()`. Every part of it is a judgment about what the camera should do, not a
transcription of a stated end state.

**Depends on:** CAM-2, CAM-4.

**Touches:**
- `src/presentation/BattleCameraDirector.gd`
- `src/systems/BattlePresentationController.gd`

**End state:** The director holds an explicit current state and one place that applies
it. Every row of the sketch's §3 table is implemented except Setup (CAM-1) and
Establish (excluded): Planning frames the actor at the resting zoom from a settled
quadrant; Aiming follows the tile cursor position-only and edge-triggered; Confirming
frames actor and target together; Following tracks a moving piece and releases when
its animation ends; Deliberating orbits; Casting widens and never zooms in; Handover
settles and reframes; Resolved orbits the winner on `battle_ended`; and player input
abandons any of them immediately, with the director reasserting at the next turn
boundary rather than mid-turn.

**Implementation:** Edge-triggered means the cursor roams freely inside a dead zone —
start at about 0.6 of the frame — and the camera pans only as it approaches the edge.
Recentring on every cursor keypress turns the board into a treadmill; if the
implementation finds itself calling `panFocusTo()` on every `cursor_changed`, it has
the wrong shape. Measure the dead zone against `RetroRenderController.get_display_rect()`,
not the raw viewport, for the same reason `FOCUS_EDGE_MARGIN` already does: a unit
sitting in a letterbox bar is not visible.

Aiming must not rotate, and the quadrant settle must have completed before an aiming
phase opens, because `_board_direction_for()` snaps arrow keys through
`nearestQuadrantYaw()` and is only exact from a settled quadrant.

Movement follow uses CAM-3's verb against the adapter's live unit position, and
releases on the animation's end rather than on a timer.

Decide `_frame_unit()` explicitly. Its off-screen-only test was free mode's rule and
free mode no longer exists; either it becomes the Aiming state's visibility guarantee
or it goes. Say which in the commit body.

**Risk:** The highest-risk item in the cycle, and the one whose defects are all
subjective — a camera that follows too eagerly, settles too late, or fights the player
reads as broken without failing any check. Budget real time driving actual battles on
all three maps, in both CPU-vs-CPU and player-vs-CPU, rather than reasoning about it.

**Adds to final validation:** Every §3 state observed at least once in a real battle,
plus the interruption rule: grab the camera during each of Aiming, Following,
Deliberating and Casting, and confirm the director yields immediately and returns at
the next turn boundary.

### CAM-6 — Lock the opening pitch and the orbit rate from observation

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Two named constants change to two values the user has stated.
There is no design left in it — the judgment happened at the screen, and the item's
whole job is to transcribe the result and confirm nothing else moved. Routing this to
Sol would be paying for a decision that has already been made.

**BLOCKING — requires a user decision.** This item cannot be executed until the user
has looked at the running preview and the running battle and named two numbers: the
opening pitch in degrees, and the orbit rate in degrees per second. Do not choose them.
Do not fall back to the sketch's 38° or to the existing 8.0. If the numbers have not
been given, stop and ask.

**Depends on:** CAM-5.

**Touches:**
- `src/presentation/BattleCameraDirector.gd`
- `src/systems/BattlePresentationController.gd`

**End state:** The opening pitch constant and `ORBIT_DEGREES_PER_SECOND` hold the
values the user named. Nothing else changes. Both remain single named constants with
comments saying they are feel values judged by eye, so the next person to disagree
knows they are allowed to.

**Implementation:** Changing the pitch changes what the fit returns, because the fit
takes pitch as an input — so the opening zoom moves with it. That is correct and
automatic; do not compensate for it by hand.

**Risk:** Almost none, with one exception: `RESTING_ZOOM_FRACTION` is a fraction *of*
the opening framing, so a materially different opening zoom changes the resting zoom
too. If the resting framing now feels wrong, say so in the commit body rather than
quietly retuning a constant this item does not claim.

**Adds to final validation:** The named values are what ships, on all three maps.

### CAM-7 — Rewrite the camera's design note and validate the cycle

**Model:** Opus 5 / GPT Sol

**Model rationale:** `docs/UI_DESIGN.md` §9 currently documents a two-mode camera with
a reversibility guarantee as the reason director mode is acceptable at all. This cycle
deletes one of those modes, so the section cannot be edited — it has to be re-argued
from what shipped, including what now protects the player's framing in a world where
the director is always driving. That is the same class of judgment the section
originally required. This item also consolidates the cycle's manual validation, which
is entirely subjective camera feel.

**Depends on:** CAM-1, CAM-2, CAM-3, CAM-4, CAM-5, CAM-6.

**Touches:**
- `docs/UI_DESIGN.md`
- `docs/sketches/README.md`
- `BACKLOG_CRITICAL.md`
- `BACKLOG_LONGTERM.md`
- `docs/plans/battle-camera-direction.md` (deletion, on close)

**End state:** §9's camera subsection describes one directed camera and the states it
moves through, not two modes. The claim in `BACKLOG_CRITICAL.md` that camera-relative
controls became load-bearing "when `BattleCameraDirector` started rotating the camera"
is corrected — it never did until this cycle. Anything this cycle deliberately did not
do is in a backlog with enough context to act on. The sketch's index row in
`docs/sketches/README.md` reflects that its open questions were answered here. The
cycle file is deleted in the same commit that merges.

**Implementation:** Every implementation item's finding lives in its own commit body;
read them rather than reconstructing from the diff:

```
git log --grep="Plan-Item: CAM-" --format="%h %s"
```

Consolidated manual validation, on all three maps unless stated:

1. Setup preview builds, rebuilds on every dropdown, survives two battles with a
   return to setup between them, and never runs a turn.
2. Battles open square at yaw 0, fitted, at the pitch CAM-6 set, at 16:9 and at the
   harshest retro preset.
3. Middle-click reset returns to the opening shot, not to a placeholder.
4. Each §3 state observed at least once in a live battle, in both CPU-vs-CPU and
   player-vs-CPU.
5. The interruption rule holds from each of Aiming, Following, Deliberating, Casting.
6. Arrow-key aiming resolves to the correct board direction after an orbit has carried
   the camera through several quadrants and settled.
7. Damage numbers and status badges still track their units through every camera
   motion this cycle added.

**Risk:** The documentation risk is asserting a guarantee that no longer holds. If
CAM-4 deleted `restoreFreeView()`, then "the player's framing is restored intact" is
no longer true and must not survive into the rewritten section in any form.

**Adds to final validation:** —

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | CAM-1, CAM-2, CAM-3 | preview lifetime and setup UI vs. player-turn signals vs. camera verbs — three separate files with no shared path |
| 2 | CAM-4 | needs CAM-1 and CAM-3 committed; shares a file with each |
| 3 | CAM-5 | needs CAM-2 and CAM-4 |
| 4 | CAM-6 | needs CAM-5, and a human observation the plan cannot supply |
| 5 | CAM-7 | validation and the design note, alone, quiet tree |

Wave 1 is the only genuinely parallel wave, and that is a property of the code rather
than of the plan: `BattlePresentationController.gd` is the wiring point for almost
everything the camera does, so once CAM-4 claims it the rest of the cycle is a spine.
Do not try to split CAM-4 or CAM-5 to widen a later wave — both are single decisions
that happen to touch two files, and splitting them would put half a decision in each
commit.

**All `docs/UI_DESIGN.md` edits belong to CAM-7.** No implementation item touches it.
This is deliberate: it is the one file every item would otherwise claim, and routing it
to a single end-of-cycle rewrite is what makes wave 1 legal and keeps the design note
describing what shipped rather than what six items each intended.

## Deliberately excluded

- **Multiple `Camera3D` nodes, and weighted rig blending.** Considered and rejected in
  the sketch's §6. Badge tracking and mouse picking both read `unproject_position()`
  and `project_ray_origin()` off the one camera the controller holds, `nearestQuadrantYaw()`
  needs one authoritative yaw, and a hard cut costs a tactics player the mental map of
  the board they are mid-way through building. A second camera earns its keep only for
  a deliberate cut — a KO or finisher cinematic — which is not in this cycle.

- **The establishing shot.** The sketch's §3 lists it as optional and it is the one row
  that is pure presentation. The setup preview covers the same need — seeing the board
  before the fight — and covers it better, because you can look for as long as you
  like. Revisit only if the opening still feels abrupt after CAM-6.

- **The army-axis yaw.** Facing straight down the team 1 → team 2 diagonal centres the
  fight, but turns the board into a diamond and leaves the aiming quadrant, which
  costs `_board_direction_for()` its exactness. Rejected in the sketch; kept there as
  the recorded alternative. Not a knob for a future session to turn.

- **Restyling the setup panel with `NoggTheme`.** CAM-1 will make its rawness obvious
  and it is still not this cycle's work. It is a UI cycle with its own scope — the
  panel, its layout, and the fact that it is the one screen not wearing the game's
  chrome. CAM-7 backlogs it.

- **Flipping the board for player 2.** Yaw 0 is behind team 1. There is no hot-seat or
  PvP mode for this to matter in yet; when there is, 180° is a legal quadrant and the
  question is whether rotating between every turn is acceptable. Backlog, not scope.

- **Pitch oscillation during the orbit.** A drifting camera that also rose and fell
  slightly would be the first layered oscillator applied to the camera rather than to
  an effect, and it is the easiest thing here to overdo. CAM-3 makes pitch tweenable,
  which is what a later cycle would need; using it is not this cycle's job.

- **Retuning `CAST_FRAME_MIN_RADIUS`, `CAST_FRAME_MARGIN_TILES`, or
  `FOCUS_EDGE_MARGIN`.** All three are reasonable and none has ever been observed
  running. CAM-6 tunes exactly two numbers. If one of these three is visibly wrong
  during CAM-5, say so in that commit body and backlog it.

- **Live UI rescaling.** Already tracked in `BACKLOG_LONGTERM.md`, already argued
  against in `BattlePresentationController`'s own comments, and unrelated to the
  camera.
