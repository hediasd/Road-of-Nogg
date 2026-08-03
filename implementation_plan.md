# Implementation Plan

Opened 2026-08-02. The file was empty when this plan opened: the previous cycle
covered repository structure and typed-boundary maintenance, completed its
final validation, and was cleared in commit `35c9f40` with no unstarted or
abandoned items to relocate. Recover it with
`git show 35c9f40~1:implementation_plan.md`. This file now holds one cycle in
two phases: repairing the player's action-confirmation path (CAST-1 through
CAST-5), then adding the tactical-legibility affordances the genre has settled
on (FEEL-1 through FEEL-14), closed by a single PLAN-VALIDATE.

The two phases are ordered, not independent. CAST fixes a shipping defect and
comes first; FEEL builds on the surfaces CAST establishes. An executing agent
that reaches FEEL-1 with any CAST item unresolved should stop and say so.

The worktree carried one untracked file when this plan was opened —
`scenes/main.tscn`. It is unrelated to this cycle. Resolve it (commit or
remove) before starting CAST-1 so each item still begins from a clean
`git status`.

Execute one item per session, in file order, committing at each item boundary.
Implementation items stop after focused diff review, `git diff --check`,
backlog maintenance, and their commit. Only CAST-VALIDATE performs full
import, replay, runtime, and manual gameplay validation.

## Scope and settled decisions

A player casting a self-targeted spell — `Empower` is the reproducing case —
has no usable way to confirm the cast. Five defects compound:

1. `BattlePresentationController._on_player_menu_changed` collapses the command
   surface to `showPromptOnly()` for every non-`MENU` phase, so `CONFIRM_ACTION`
   renders one line of top-centre text and no interactive control.
2. `PlayerTurnController.acceptsGridInput()` is false in `CONFIRM_ACTION`, so a
   left click falls through to `_handle_click_selection` — the inspect path —
   and silently re-renders the target status window instead of confirming.
3. `BattlePresentationController._input` claims `KEY_SPACE` for the dev-canvas
   toggle across the whole battle lifecycle and marks it handled. `_input`
   precedes `_unhandled_input`, so Space — one of Godot's three default
   `ui_accept` binds, and the one players reach for — never arrives at confirm.
4. A self/range-0 spell has exactly one legal target: the caster's own tile,
   under its own model. `TARGET_SELECT` presents a chooser with one option, and
   the player pays two confirmations for a decision with one outcome.
5. Player-facing copy calls the caster a "target" and renders `Rng 0` for a
   self spell, which reads as a data bug.

This cycle fixes all five. Together they restore the guarantee
`docs/UI_DESIGN.md` §6 already makes and the confirm phase currently breaks:
keyboard and mouse resolve to the same state.

**Settled decisions**, so no item needs to reopen them:

- The confirm surface is a **new window**, not a reused command window: two
  cursor-driven rows, `CONFIRM` and `CANCEL`, docked at the command window's
  position and size so the player's cursor does not travel. It joins the §8
  taxonomy as a new row.
- The command window **hides** during confirm rather than dimming. Dimming is
  the parent-window idiom for the spell column opening beside it; confirm
  replaces the command list rather than descending from it.
- The **forecast window stays visible** through both `TARGET_SELECT` and
  `CONFIRM_ACTION`. §8 says "visible only during confirm"; the shipping code
  already shows it while aiming, that is the better behaviour, and CAST-2
  corrects the doc rather than the code.
- Grid click during confirm: a click **on the pending target tile confirms**;
  a click **anywhere else on the board cancels** back to target select. Clicks
  never fall through to unit inspection while a confirmation is pending.
- The dev-canvas toggle moves to **F1**. It is a developer key and must not
  outrank the game's accept action.
- Self/range-0 spells **skip `TARGET_SELECT` entirely** and enter
  `CONFIRM_ACTION` with the caster as the pending target. Cancelling from there
  returns to the **spell list**, not to a chooser that was never shown.

**Deliberately out of scope.** `PlayerTurnController._forecastText` branches on
`spell.heals` then `spell.damage_lines`; a pure buff such as `Empower`
(`BUFFS_ATK: 3`, `BUFF_DURATION: 2`) matches neither and falls through to
`"Expected: N unit(s) affected"`, so the forecast says nothing about what the
spell does. Every buff, debuff, and status spell in the catalogue has this
hole. It is a real gap, it is not in this cycle, and CAST-VALIDATE records it
in `BACKLOG_CRITICAL.md` as a described behaviour rather than as a plan item.

### Phase two: tactical legibility

The FEEL items come from a survey of how the genre solves the same problems —
Fire Emblem, Into the Breach, Final Fantasy Tactics. Each is a legibility fix,
not a rules change: the simulation's behaviour is identical before and after,
and only what the player can see about it changes. Anything that alters what a
mistake costs is excluded below.

**Settled decisions for phase two:**

- The threat overlay is **held, not toggled**. A held key cannot be left on by
  accident and needs no state to communicate.
- The camera may **guarantee visibility, never take authorship**: pan only when
  the active unit is off-screen or within the edge margin, never re-zoom, never
  rotate, and abandon the pan on any camera input. This is deliberately the
  weak version. Final Fantasy Tactics ships the strong version — the camera
  re-orients on every unit change — and its own players describe re-fixing the
  camera each turn as the game's most persistent irritation.
- Re-arming from target select rebinds `ui_up`/`ui_down` to spell cycling.
  Today all four directions cycle targets via `_cycleTargetPosition`; after
  FEEL-2 the horizontal pair keeps that job and the vertical pair changes the
  spell. This is a deliberate break with the current input contract.
- Animation pacing is a **global setting with a per-action override**, not one
  or the other.
- Picking resolves from an **ordered list of every hit along the ray**, not from
  the nearest one. What the player pointed at is a question about intent, and
  intent is phase-dependent; the nearest collider only answers it by accident.
- The turn order is **shown, not derived**. The simulator already sorts and
  emits it; making the player infer it from a speed stat is a puzzle nobody
  asked for.
- Status values are **zero-padded to three digits** and the status windows keep
  every stat they carry today. Fixed-width values do not reflow as they change,
  so the eye can park on a position instead of re-finding it each turn. This is
  a deliberate choice of a uniform, slightly odd-looking `004` over a stable
  layout's alternative, and it is not up for re-litigation mid-cycle.
- Every monster stat is **clamped to 0–999 inclusive in the simulation**, so
  three digits is a guarantee rather than an assumption. This is the single
  exception to the rule that this cycle does not change simulation behaviour,
  and it is called out again in the item that makes it.
- Model bases separate from creature bodies by **surface finish, not colour** —
  dark and metallic against matte bodies. A finish difference survives every
  team colour; a hue shift does not.
- A queued visual action is held until its animation is **mostly** through, not
  fully. Waiting for every effect to finish completely turns a battle into a
  slideshow; the overlap is what keeps it moving.
- Damage numbers use the **menu font with a hard offset shadow** — black drawn
  once, white drawn over it offset up and diagonally — not a symmetric outline.
  The offset is the look; an outline is a different one.
- Models the player is not choosing between render with **screen-space dither**,
  never alpha fade. It holds depth, needs no transparency sorting, matches the
  hardware era the scene imitates, and — unlike fading — never makes a unit
  ambiguous about whether it is still there.

**Not scheduled, and not to be started without a decision.** One candidate from
the same survey changes the game's difficulty contract rather than its
legibility, so it is not an item here: a charge-limited rewind of whole turns
(Fire Emblem's Turnwheel / Divine Pulse). Movement `Undo` already covers the
common case, and anything beyond it changes what a mistake costs.

**Dropped after checking the code.** "Jump to the next unmoved unit", standard
in Fire Emblem, has no meaning here: `TurnManager` sorts a turn order and pops
one unit at a time, so the player never chooses who acts.

No item needs a product or balance decision. A discovered dependency that would
force one of the settled decisions to change is blocking: record it and ask.

## Conventions

Every item has an explicit minimum **Model**, **Risk**, and behavior it **Adds
to validation coverage**. The executing session must verify its running model
before starting, and stop if the running model is more capable than the item
needs. Every item reviews `BACKLOG_CRITICAL.md`, `BACKLOG_LONGTERM.md`, and
`docs/BACKLOG.md` for stale, completed, or newly discovered work.
Implementation Resolutions become **implemented; pending end-of-plan
validation**; only CAST-VALIDATE marks them done.

---

## CAST-1 — Free the accept key

**Model:** Sonnet 5 / GPT Terra

**Depends on:** none.

**Risk:** Low. A single input branch moves. The one hazard is rebinding to a key
another handler already claims, which would trade one swallowed action for
another.

**Adds to validation coverage:** Space reaches `ui_accept` in every player-turn
phase, and F1 toggles the developer canvas in `BATTLE` and `COMPLETE`.

**End state:** No developer affordance consumes a default `ui_accept` bind
during a player turn.

### Work

1. In `BattlePresentationController._input`, change the dev-canvas toggle from
   `KEY_SPACE` to `KEY_F1`, keeping the existing `lifecycle` guard, the
   `pressed`/`not echo` guards, and `set_input_as_handled()`.
2. Sweep `_input` and `_unhandled_input` for any other handler that consumes a
   default `ui_accept` bind (Space, Enter, KP Enter) ahead of the player-turn
   branches. Report anything found; do not rebind beyond the dev toggle.
3. Update the comment above the branch — it currently documents Space by name —
   and any on-screen or documented reference to the Space toggle.
4. Confirm no `[input]` section in `project.godot` rebinds `ui_accept`; the
   project relies on Godot's defaults, and this item does not change that.
5. Review the backlogs.

**Files:** `src/systems/BattlePresentationController.gd`; `docs/UI_DESIGN.md`
only if it names the Space toggle.

**Resolution:** Implemented; pending end-of-plan validation. Rebound the
dev-canvas toggle in `_input` from `KEY_SPACE` to `KEY_F1`, keeping the
`lifecycle`, `pressed`/`not echo` guards and `set_input_as_handled()`
unchanged, and rewrote the comment above it to state the rebind and why.
Swept `_input` and `_unhandled_input`: the only other handler in `_input` is
Ctrl+R for the monster-catalog hot-reload, which does not collide with
`ui_accept`'s default binds (Enter, KP Enter, Space); no other handler claims
`KEY_SPACE`, `KEY_ENTER`, or `KEY_KP_ENTER`. `project.godot` has no `[input]`
rebind of `ui_accept`, so Godot's defaults apply. Updated the remaining
`SPACEBAR` references: the doc comment in `BattleUIBuilder.gd`, the §9 table
and prose in `docs/UI_DESIGN.md`, and one incidental mention in
`BACKLOG_LONGTERM.md`.

---

## CAST-2 — Give the confirm phase a real window

**Model:** Opus 5 / GPT Sol

**Depends on:** none. Order after CAST-1 so the phase is reachable by hand.

**Risk:** High. This adds a third cursor-driven window to a file whose central
rule is that content changes rebuild rows, selection changes move the cursor,
and neither path calls the other. Violating it reintroduces the
rebuild-per-keypress defect the file exists to prevent. A confirm window that
fails to hide on phase exit would also occlude the command list for the rest of
the turn.

**Adds to validation coverage:** `CONFIRM_ACTION` presents `CONFIRM` / `CANCEL`
rows; the cursor lands on `CONFIRM`; keyboard and mouse both activate either
row; the window disappears on confirm, on cancel, and on turn end; and the
command window returns with its prior selection intact.

**End state:** Confirmation is a first-class, visible, clickable phase surface
that obeys §5 and §6.

### Work

1. In `PlayerCommandMenu`, add a confirm window built by `_build_window` at
   `COMMAND_WIDTH` with a capacity of 2, its own `MenuCursor`, and the standard
   `set_content_indent(CURSOR_GUTTER_WIDTH)`. Dock it at the command window's
   position in `_layout_windows` so the cursor does not travel between phases.
   Hidden by default.
2. Add a `CONFIRM` mode alongside `ROOT` and `SPELLS`, and route `_mode` through
   the existing `moveSelection`, `acceptSelection`, `_select`, hover, click, and
   wheel paths rather than adding parallel ones. Selection stays an index into a
   row-metadata array; `moveSelection` must not rebuild rows.
3. Add `openConfirm()` / `closeConfirm()` mirroring `openSpells()` /
   `closeSpells()`: hide the command and spell windows and their cursors, show
   the confirm window, snap the cursor to `CONFIRM`. Closing restores the
   command window and its cursor without rebuilding its rows.
4. Emit through the existing `entry_activated` signal with two new ids so the
   controller keeps one activation path. Add the ids as constants next to
   `BACK_ID`.
5. In `BattlePresentationController._on_player_menu_changed`, branch
   `CONFIRM_ACTION` to `openConfirm()` before the existing non-`MENU`
   `showPromptOnly()` fallback, and ensure every exit from the phase — confirm,
   cancel, rejected action, turn end — closes it.
6. In `BattlePresentationController`, map the two new ids to
   `player_turn.confirmSelection()` and `player_turn.cancel()` wherever
   `entry_activated` is currently handled. `PlayerTurnController` gains no new
   public API and no new rules.
7. Keep the existing `CONFIRM_ACTION` + `ui_accept` keyboard branch working; it
   must not double-fire with the menu's own `acceptSelection`.
8. Add the confirm window to the `docs/UI_DESIGN.md` §8 taxonomy table with its
   dock, size, and contents, and correct the forecast row to state that the
   forecast is visible while aiming as well as while confirming.
9. Review the backlogs.

**Files:** `src/presentation/PlayerCommandMenu.gd`,
`src/systems/BattlePresentationController.gd`, `docs/UI_DESIGN.md`.

**Resolution:** Implemented; pending end-of-plan validation.

`PlayerCommandMenu` gained a third cursor-driven surface: a `CONFIRM_CAPACITY`
(2) window at `COMMAND_WIDTH` with its own `MenuCursor` and the standard gutter
indent, docked at the command window's *own* origin in `_layout_windows()` so
the cursor does not travel across the screen on a phase change. A `CONFIRM`
mode joins `ROOT`/`SPELLS`, and rather than branch on `_mode` at each call
site, the shared paths now read through two helpers (`_rows_for_mode()`,
`_index_for_mode()`); `moveSelection`, `acceptSelection`, `_select`, hover,
click, and wheel all route through them, so `moveSelection` still never
rebuilds rows. `openConfirm()`/`closeConfirm()` mirror the spell pair, except
they hide the command window rather than dimming it, per the settled decision.
Activation goes out through the existing `entry_activated` signal with two new
ids next to `BACK_ID`, and `_on_command_menu_entry` maps them to
`confirmSelection()`/`cancel()` — `PlayerTurnController` gained no new API.

Three things the item's Work list did not anticipate, all decided here:

1. **The keyboard branch could not stay as written.** It called
   `player_turn.confirmSelection()` directly on `ui_accept`. With a cursor now
   in the phase, parking on `CANCEL` and pressing Enter would have committed
   the action the player was backing out of. It now routes through
   `command_menu.acceptSelection()`, which is also what makes the
   "must not double-fire" requirement hold trivially: the menu emits
   `entry_activated` exactly once and the controller owns what each id means.
   `ui_up`/`ui_down` were added for the same reason — the phase had no cursor
   before, so nothing moved one.
2. **FEEL-5's skip binding had to be narrowed.** It claimed `ui_accept`
   whenever `isAnimationBusy()`, on the reasoning that confirm is always over
   before an animation starts. That is wrong when the queue is still draining
   from the previous turn as a player turn opens — the stale animation would
   eat the player's first confirm. It now also requires that no player turn is
   active, or that the phase is `RESOLVING`. Recorded here rather than
   silently, because it revises a shipped item.
3. **Stranding is prevented structurally, not by enumeration.** Instead of
   closing the window at each of confirm/cancel/rejection/turn-end,
   `showRoot()` and `showPromptOnly()` — the only two ways any other phase
   reaches the screen — both hide it unconditionally. A phase transition added
   later cannot strand one.

**Verified by a narrow parse probe** (`--check-only`), which `AGENTS.md` allows
when later items cannot safely build on possibly-unparseable code, as five
queued items build directly on this. It caught a real defect **in FEEL-4's
already-committed code**, not in this item: `_pan_camera_to_active_unit()` used
`:=` on two values returned from the deliberately untyped `retro_renderer`,
which GDScript cannot infer, so `BattlePresentationController.gd` failed to
parse entirely — FEEL-4 as committed did not load. Fixed here with explicit
`Vector2`/`Rect2` annotations and a comment naming the cause. Every other file
touched this cycle was then parse-checked and was clean, and both edited
shaders were confirmed to compile and accept their new uniforms.

---

## CAST-3 — Make the grid agree with the menu during confirm

**Model:** Sonnet 5 / GPT Terra

**Depends on:** CAST-2.

**Risk:** Medium. Widening what the confirm phase accepts from the mouse means a
misrouted click could commit an action the player meant only to inspect. The
tile-equality test is the whole safety margin.

**Adds to validation coverage:** During `CONFIRM_ACTION`, clicking the pending
target tile casts; clicking any other board tile returns to target select; and
no click reaches unit inspection while a confirmation is pending.

**End state:** §6's promise — mouse and keyboard resolve to the same state —
holds in the confirm phase, the one phase where it currently fails.

### Work

1. Add a read-only accessor to `PlayerTurnController` exposing the pending
   target position (the existing `_pendingTargetPos`), so the controller can
   compare a clicked tile without reaching into private state — follow the
   pattern already set by the read-only selection observers in
   `PlayerCommandMenu`.
2. In `BattlePresentationController`'s left-click branch, handle
   `CONFIRM_ACTION` before the `acceptsGridInput()` test: resolve the clicked
   tile, call `confirmSelection()` when it equals the pending target, and
   `cancel()` otherwise. Consume the event in both cases.
3. Leave `acceptsGridInput()` unchanged. It gates cursor movement, and the
   confirm phase must not accept cursor movement; this item routes clicks
   around it rather than widening it.
4. Leave hover behaviour alone during confirm. The pending target is committed;
   moving a highlight over it would contradict that.
5. Record the confirm-phase click semantics in the `docs/UI_DESIGN.md` §6 input
   table.
6. Review the backlogs.

**Files:** `src/systems/BattlePresentationController.gd`,
`src/systems/PlayerTurnController.gd`, `docs/UI_DESIGN.md`.

**Resolution:** Implemented; pending end-of-plan validation.

`PlayerTurnController.pendingTargetPosition()` returns `_pendingTargetPos`
directly, mirroring `validTargetPositions()`'s pattern. The left-click handler
in `_unhandled_input` gained a `CONFIRM_ACTION` branch ahead of the
`acceptsGridInput()` check — exactly as specified, since that gate is false in
this phase by design and must stay that way. A click on the pending tile
confirms; anything else, including a click that misses the board entirely,
cancels. Both branches call `get_viewport().set_input_as_handled()`, which the
item's Work list did not mention but every sibling branch in this function
does; leaving it off would have let the click fall through further than
intended. `acceptsGridInput()` and the hover branch (which already only runs
when that gate is true) are untouched.

**This is additive, not a replacement for CAST-2's window.** CONFIRM_ACTION
now has two independent paths to the same two outcomes: click `CONFIRM`/`CANCEL`
in the window, or click the target tile / anywhere else on the board.
`cancel()` already knows which phase to return to via CAST-4's
`_confirmSkippedTargetSelect` flag, so this item did not need to special-case
that — both entry points converge on the same `confirmSelection()`/`cancel()`
calls the window's rows use.

Added a §6 input-table entry for the two board-click rows, with a note on why
they cannot disagree with the window: during `CONFIRM_ACTION` the cursor no
longer moves, so §5's "cursor position is the only selection truth" has
nothing left to contradict — there is only a commit to make, not a target to
aim.

Checked `debug/drive_battle.gd` for a confirm reached by clicking the same
tile twice: every `CONFIRM_ACTION` case in it confirms via `ui_accept`
assertions, never a second click, so this item adds a capability without
touching harness behavior. Parse-checked with `--check-only`.

---

## CAST-4 — Stop asking for a choice that does not exist

**Model:** Opus 5 / GPT Sol

**Depends on:** CAST-2.

**Risk:** High. This adds a second entry path into `CONFIRM_ACTION` and a second
exit path out of `cancel()`, in a state machine whose phases are its entire
contract. A self-cast entering confirm without its overlays or forecast
populated would confirm blind; a `cancel()` returning to a chooser that was
never shown would strand the player.

**Adds to validation coverage:** Selecting a self/range-0 spell enters
`CONFIRM_ACTION` directly with the caster as pending target, affected-area
overlays and forecast populated; cancelling returns to the spell list; and
ranged, area, and self spells with a non-zero radius keep the target-select
step unchanged.

**End state:** A spell with exactly one possible target costs the player one
decision, not two.

### Work

1. Add a private predicate to `PlayerTurnController` for "this spell offers no
   target choice". Derive it from the authored spell — `targetType == "self"`
   with range 0 — and not from `_validTargetPositions.size() == 1`, which is a
   board-state coincidence that would silently skip aiming for a ranged spell
   with one enemy left in reach.
2. In `_enterTargetSelect`, when the predicate holds for the selected spell, set
   the pending target to the caster's position, call `_refreshTargetPreview` so
   overlays, target status, and forecast populate exactly as they do on the
   normal path, set `phase = CONFIRM_ACTION`, emit the confirm status text, and
   `menu_changed.emit()`. Do not duplicate `_commitTarget`'s body — factor the
   shared tail if that is cleaner than branching.
3. Preserve the guard behaviour: a self spell that is not castable must still
   route to `_enterMenu("No spell is ready.")` rather than into confirm.
4. Teach `cancel()` that leaving `CONFIRM_ACTION` returns to the spell list when
   the confirm was entered without a target-select step, and to
   `_enterTargetSelect` otherwise. Track which path was taken explicitly; do not
   re-derive it from the spell.
5. Confirm `_commitAction` needs no change — it already reads `_pendingTargetPos`
   and the selected spell indices.
6. Verify against the catalogue that the predicate selects the intended spells
   and no others, and state in the Resolution which spells it matches.
7. Review the backlogs.

**Files:** `src/systems/PlayerTurnController.gd`;
`src/presentation/PlayerCommandMenu.gd` and
`src/systems/BattlePresentationController.gd` only if reopening the spell list
on cancel requires it.

**Resolution:** Implemented; pending end-of-plan validation.

`_selectedSpellOffersNoTargetChoice()` reads the authored spell —
`targetType == "self" and range == 0` — exactly as specified, not
`_validTargetPositions.size() == 1`. `_enterTargetSelect()` branches to the new
`_enterConfirmAction(pos, skippedTargetSelect)` *after* `_sortValidTargetPositions()`,
so every existing guard still runs first: an unready spell is still turned away
to `_enterMenu("No spell is ready.")`, and `_validTargetPositions` is populated,
which `_refreshTargetPreview()` requires in order to render overlays, target
status and forecast. `_commitTarget()`'s tail was factored into that same
function rather than duplicated, so the two entry paths cannot drift.
`_commitAction()` needed no change, as predicted — it reads `_pendingTargetPos`
and the spell indices, all of which the new path sets.

`cancel()` branches on a new `_confirmSkippedTargetSelect` flag, set at the one
place confirm is entered and cleared in `beginTurn()`, `_enterMenu()`, and
`_enterTargetSelect()`. Returning to the spell list needed a window this
controller does not own, so it emits a new `spell_list_requested` signal after
`_enterMenu()` (ordering matters: the root window must be on screen before the
spell column opens beside it), which `BattlePresentationController` answers
with `openSpells()`.

**The catalogue check found the item's own validation line to be unsatisfiable.**
All 27 self-target spells in `data/spells.json` have `RANGE: 0`, so the
specified predicate matches every one of them — including the five with a
non-zero `SELF_RADIUS` (`Chill` 1, `Shine` 2, `Cheers` 2, `Gather` 2,
`Ooze Shield` 2). This item's **Adds to validation coverage** says "self spells
with a non-zero radius keep the target-select step unchanged"; with the
specified predicate they do not, and no predicate could both match the stated
rule and spare them. Implemented as specified rather than quietly narrowed,
because skipping is still correct for them: `getSpellTargetPositionsFrom()`
returns `[fromPos]` for *any* self spell whatever its radius, so target select
would offer one option regardless, and the affected area still renders in
`CONFIRM_ACTION` through the same `_refreshTargetPreview()` call. **PLAN-VALIDATE
should treat that clause as withdrawn**, and verify instead that a self spell
with a radius enters confirm with its full area overlay drawn.

**Note for CAST-5:** the confirm status text it is scoped to reword
("Confirm Spell at <name>.") now lives in `_enterConfirmAction()`, not
`_commitTarget()`.

Parse-checked with `--check-only`. `debug/drive_battle.gd` needs no update: its
spell coverage filters for `targetType == "area"` with `can_target_empty`, so
it never drives a self spell and its `CONFIRM_ACTION` assertions are unaffected.

---

## CAST-5 — Say what a self spell is

**Model:** Sonnet 5 / GPT Terra

**Depends on:** CAST-4, so the copy is written against the phase flow that
ships.

**Risk:** Low. Player-facing strings and one derived label, contained by the
existing rule that command chrome is uppercased at render time and proper nouns
are not.

**Adds to validation coverage:** A self spell lists `Self` rather than `Rng 0`,
and no player-facing string describes the caster as its own target.

**End state:** The self-cast path reads as a self-cast throughout.

### Work

1. In `PlayerCommandMenu._spell_value`, render a ready range-0 spell as `Self`
   instead of `Rng 0`. Keep the `CD n` branch unchanged. Take the range from the
   existing spell entry dictionary; do not add a field the controller does not
   already supply.
2. In `PlayerTurnController._refreshTargetPreview` and `_commitTarget`, use
   self-directed phrasing when the pending target is the caster — the status
   line currently emits `"Choose a target: <name>."` and
   `"Confirm Spell at <name>."` about the player's own unit.
3. Keep `selectSpell`'s status line honest for a range-0 spell; it currently
   reports `range 0`.
4. Check `ConsoleVisualAdapter` and `ConsoleRoundSummary` for the same
   assumption and fix only what is player-facing.
5. Leave `docs/SPELL_CATALOG_SCHEMA.md` and the authored `RANGE: 0` data alone.
   This is presentation, not schema.
6. Review the backlogs.

**Files:** `src/presentation/PlayerCommandMenu.gd`,
`src/systems/PlayerTurnController.gd`, console adapters if affected.

**Resolution:** Implemented; pending end-of-plan validation.

**The literal instruction in Work step 1 — "take the range from the existing
spell entry dictionary" — would have mislabelled real spells.** All 27 true
self spells have `RANGE: 0`, but so do `Think` and `Thought`, two spells
genuinely attached to `Mage Dragon`'s kit in `data/monsters.json` with
`targetType == "single"` (the default; the data sets no `TARGET_TYPE` for
either). `range == 0` is not a safe proxy for "self" — using it would have
shown `Self` on two spells that are not self-targeted by the data, even though
they happen to be reachable only from the caster's own tile. Added a
`self_targeted` field to `spellEntries()`'s dictionary instead, computed by a
new `static func spellOffersNoTargetChoice(spell: Spell)` that both this and
CAST-4's `_selectedSpellOffersNoTargetChoice()` now call — one predicate, so
a spell can never be labelled `Self` in the list and still show a chooser when
picked, or the reverse. `Think`/`Thought` still read `Rng 0`, honestly.

`_spell_value()` checks `self_targeted` before falling to `Rng %d`.
`selectSpell()`'s status line substitutes `"self"` for `"range %d"` on the
same field. `_refreshTargetPreview()` and `_enterConfirmAction()` (renamed
from `_commitTarget`'s inline tail by CAST-4) both compare
`target.uniqueID == activeMonsterID` rather than reading `_confirmSkippedTargetSelect`
— deliberately not CAST-4's flag, because a deliberate self-heal cycled onto
one's own tile during ordinary `TARGET_SELECT` (the caster is its own ally,
so this is reachable for any heal spell) hits this same phrasing and never
skipped target select at all. `_enterConfirmAction()`'s line reads "Confirm
Spell **on** yourself" rather than "at yourself", the one place the
preposition changes with the subject.

**Console adapters left untouched, and why.** `ConsoleVisualAdapter` and
`ConsoleRoundSummary` render fixed `Attacker -> Target` log lines with both
names and ids always shown, so a self-cast already reads as `Grubb #3 -> Grubb
#3` — identical name and id make it unambiguous without any special-casing.
The confusion CAST-5 exists to fix was specific to the live UI's phrasing,
which implied *choosing* an external target; a static log line makes no such
claim. Judged not player-facing in the sense this item means, and left alone
per its own conditional Files entry.

`docs/SPELL_CATALOG_SCHEMA.md` and the authored `RANGE: 0` data are untouched,
as scoped. Recorded `Think`/`Thought` in `BACKLOG_LONGTERM.md` — the naming and
zero-damage/no-element data read like an unfinished or placeholder kit entry
on a real monster, a content question this item has no authority to resolve.

Parse-checked with `--check-only`.

---

## FEEL-1 — Show what the enemy can reach

**Model:** Opus 5 / GPT Sol

**Depends on:** CAST-5.

**Risk:** High. This is the first overlay drawn from a source other than the
active unit's own phase, and the first that must compose with the overlays
already on screen rather than replace them. Recomputing every enemy's reach on
each frame of a held key would also make the key itself feel like a stall.

**Adds to validation coverage:** Holding the threat key during any player-turn
phase draws the union of living enemy reach; releasing it restores the previous
overlay exactly; the tactical overlays owned by move and target select are
never clobbered; and the key is inert during CPU turns and after battle end.

**End state:** The player can see the danger before stepping into it, without
counting tiles by hand.

### Work

1. Read `src/algorithms/ThreatMap.gd` first and use what it already computes.
   Add a new traversal only if the existing one cannot answer "every tile any
   living enemy can reach or strike this round".
2. Decide and record whether threat means movement reach, attack reach from
   that movement, or their union. Fire Emblem's danger zone is the union, and
   the union is the number a player actually needs; state the choice in the
   Resolution either way.
3. Compute once per press, not per frame. The board does not change while the
   key is held.
4. Add an adapter entry point for the overlay alongside `show_movement_options`
   and `show_target_options`, and give it a tint distinct from both. Restore
   the prior overlay on release rather than clearing to nothing — a player
   holding the key mid-aim must get their target tiles back.
5. Bind a held key that no existing handler claims, and verify it against the
   sweep CAST-1 performed.
6. Add the overlay and its tint to `docs/UI_DESIGN.md`.
7. Review the backlogs.

**Files:** `src/algorithms/ThreatMap.gd`,
`src/systems/BattlePresentationController.gd`,
`src/presentation/GodotVisualAdapter.gd`, `src/battle_sim/IBattleVisualAdapter.gd`,
`docs/UI_DESIGN.md`.

**Resolution:** _pending_

---

## FEEL-2 — Re-arm without leaving the aim

**Model:** Opus 5 / GPT Sol

**Depends on:** CAST-4, FEEL-1 (ordering only, to keep overlay changes serial).

**Risk:** Medium. Changing the spell mid-aim invalidates the target set that
was computed for the previous spell. A cursor left on a tile the new spell
cannot reach would let the player confirm an illegal cast, or strand them on a
tile with no valid neighbours.

**Adds to validation coverage:** During `TARGET_SELECT`, vertical input cycles
ready spells with overlays, forecast, and status recomputed for each; the
cursor lands on a legal target for the newly selected spell every time;
horizontal input still cycles targets; and a spell whose target set is empty
from the current tile is skipped rather than entered.

**End state:** "Which spell" and "which target" are one decision made in one
place, as the genre's combat forecast has worked since Genealogy of the Holy
War.

### Work

1. In `PlayerTurnController`, add spell cycling for `TARGET_SELECT`: step to the
   next entry of `spellEntries()` that is ready, set the selection, recompute
   `_validTargetPositions` from the current position, and refresh the preview.
2. Preserve the aimed tile across the change when the new spell can also target
   it; otherwise fall to the sorted target set's first entry. Never leave the
   cursor on an invalid tile.
3. Skip a ready spell with no valid target from the current position rather than
   entering it with an empty set — `_enterTargetSelect` treats an empty set as a
   reason to abandon the phase, which mid-cycle would be a surprise.
4. Do not enter spell cycling when the phase was reached from `Attack`. Attacks
   have no spell to cycle.
5. Rebind `ui_up`/`ui_down` in the `acceptsGridInput()` branch of
   `BattlePresentationController` per the settled decision, leaving
   `ui_left`/`ui_right` on target cycling.
6. Surface the currently armed spell in the status or forecast text. Cycling
   spells with no on-screen name for the armed one is worse than not cycling.
7. Update the `docs/UI_DESIGN.md` §6 input table.
8. Review the backlogs.

**Files:** `src/systems/PlayerTurnController.gd`,
`src/systems/BattlePresentationController.gd`, `docs/UI_DESIGN.md`.

**Resolution:** _pending_

---

## FEEL-3 — Draw reach and threat as one shape

**Model:** Sonnet 5 / GPT Terra

**Depends on:** FEEL-1, whose overlay tint and adapter entry point this reuses.

**Risk:** Medium. Attack reach from every reachable tile is a larger
computation than reachability alone, and it runs on entry to move select where
the player is waiting on it.

**Adds to validation coverage:** Move select draws reachable tiles and the
tiles attackable from them in two distinguishable tints; the path preview still
renders over both; and entering move select stays responsive on the largest
shipping board.

**End state:** A player choosing where to stand can see what they will threaten
from there, without walking the cursor tile by tile.

### Work

1. Compute attack reach as the union over the reachable set, using the existing
   `combatResolver.getBasicAttackTargetPositionsFrom`, which already takes a
   from-position.
2. Exclude reachable tiles from the attack tint so the two sets do not overlap;
   reachability is the stronger signal and wins the tile.
3. Extend `show_movement_options` with the second set rather than adding a
   parallel call, keeping the existing path-preview argument working.
4. Measure entry time into move select on the largest board before and after,
   and record both numbers in the Resolution. If the computation is visibly
   slow, cache per phase entry rather than optimising the traversal.
5. Add the second tint to `docs/UI_DESIGN.md`.
6. Review the backlogs.

**Files:** `src/systems/PlayerTurnController.gd`,
`src/presentation/GodotVisualAdapter.gd`, `src/battle_sim/IBattleVisualAdapter.gd`,
`src/presentation/ConsoleVisualAdapter.gd`, `docs/UI_DESIGN.md`.

**Resolution:** _pending_

---

## FEEL-4 — The camera assists, never authors

**Model:** Sonnet 5 / GPT Terra

**Depends on:** none. Order here to keep camera work clear of the overlay items.

**Risk:** Medium. A camera that moves when the player did not ask is the single
most complained-about behaviour in this genre's back catalogue. The risk is not
that the feature breaks; it is that it works as specified and is still
unpleasant.

**Adds to validation coverage:** A player turn beginning with the active unit
off-screen or in the edge margin pans it into view; a turn beginning with it
comfortably in view moves the camera not at all; zoom and rotation are never
touched; and any camera input during a pan cancels the pan immediately.

**End state:** The player never hunts for whose turn it is, and never fights
the camera for control of it.

### Work

1. In `_begin_player_turn`, test the active unit's screen position against the
   viewport rect inset by an edge margin. Pan only on failure.
2. Pan position only. Do not touch zoom, rotation, or any other camera property,
   per the settled decision.
3. Cancel an in-flight pan on any camera input. `camera.handle_input` is already
   routed ahead of the player-turn branches in `_unhandled_input`, so the
   player wins ties by construction; verify that holds during the pan.
4. Keep the pan short and make its duration a named constant, not a literal.
5. Do not extend this to CPU turns in this item. Whether the camera follows
   enemy actions is a pacing decision, not a legibility one; note it and leave
   it.
6. Review the backlogs.

**Files:** `src/systems/BattlePresentationController.gd`, the camera script it
drives.

**Resolution:** Implemented; pending end-of-plan validation. Added
`BattleCameraController.panFocusTo()` / `cancelPanFocus()`, tweening
`focus_point` only under a named `FOCUS_PAN_DURATION` — `_update_camera_transform()`
re-derives `position` from `focus_point` every frame, so yaw, pitch, and `size`
are untouched by construction. `handle_input()` was split into a thin wrapper
plus the original logic renamed `_handle_camera_input()`; the wrapper cancels
an in-flight pan whenever the inner call reports it handled the event (zoom,
orbit/pan drag start or stop, or the double-click reset), which composes
correctly with both `_input`'s drag-continuation gate and `_unhandled_input`'s
routing, since both already call through the one `handle_input()` entry point.
Hover motion and grid clicks fall through to `false` and do not cancel a pan.

`BattlePresentationController._begin_player_turn` calls the new
`_pan_camera_to_active_unit()`, which pans only when the active unit's
projected position falls outside `RetroRenderController.get_display_rect()`
inset by `CAMERA_FOCUS_EDGE_MARGIN` (64px) — `get_display_rect()` rather than
the raw viewport rect, because retro rendering can letterbox the world image
inside the window, and a unit sitting in the letterbox bar must still count as
off-screen. A `camera.is_position_behind()` check handles the case of a unit
directly behind the camera, where an unprojected position would otherwise be
unreliable.

Getting the unit's actual world position required a small addition:
`GodotVisualAdapter.get_monster_world_position()`, which prefers the live
visual (mid-tween or bumped off-tile) over the authoritative tile position,
since a pan is exactly the case that cares where the unit visually is.

This item does not extend to CPU turns, per its own scope note — left as an
open pacing question, not built.

---

## FEEL-5 — Let the player set the pace

**Model:** Sonnet 5 / GPT Terra

**Depends on:** none.

**Risk:** Medium. `_resolveThenReturnToMenu` waits on
`animation_queue_drained` before reopening the menu. A skip that empties the
queue without emitting that signal hangs the turn in `RESOLVING` with no menu
and no way out.

**Adds to validation coverage:** A speed setting scales action animations; a
skip resolves the current action immediately; the menu reopens correctly after
both; and the simulation's outcome, event log, and replay are byte-identical
whatever the pacing.

**End state:** Pacing is the player's choice, and the model never notices.

### Work

1. Add a speed multiplier to the visual adapter's animation timing. Presentation
   only — no simulation timing, no event ordering, and no replay input may
   depend on it.
2. Add a skip that drains the queue to its final state and **still emits**
   `animation_queue_drained`. Trace `_resolveThenReturnToMenu` and
   `_onQueueDrained` before writing it; that signal is the turn's only way back
   to the menu.
3. Expose the speed setting in the developer canvas alongside the existing speed
   slider rather than building a new options surface.
4. Add the per-action skip as a held or pressed key during `RESOLVING`.
5. Run a replay before and after and diff the event history to prove the
   simulation is untouched.
6. Review the backlogs.

**Files:** `src/presentation/GodotVisualAdapter.gd`,
`src/systems/BattlePresentationController.gd`, the battle UI scene for the
setting.

**Resolution:** Implemented; pending end-of-plan validation.
`GodotVisualAdapter._animation_speed_scale` (clamped 0.1–8.0) is applied
through a single new choke point, `_activateScaled()`, which every timed
animation now calls instead of `_queue.activate()` directly (move, bump,
defeat — the three sites that existed). It calls `Tween.set_speed_scale()` on
the action's own tween and divides the duration handed to
`VisualActionQueue.activate()` by the same factor, since that duration only
ever sizes the watchdog margin — leaving it unscaled would let slow motion's
longer real playback time outrun a watchdog armed for the original speed and
misreport a stall. The defeat animation's capsule-shatter `GPUParticles3D`
also gets `speed_scale` set from the same value, in-scope since it's built
inline in the same file; `SpellCastAura`'s own independent tween is not, and
is left to FEEL-13, which already owns reconciling effect lifetimes with the
queue.

Skip is a new `VisualActionQueue.skipActive()`: finalizes the active action
and bumps the queue's serial exactly as the watchdog path does, but without
its warning, then advances via the existing deferred `startNext()` — which is
what actually emits `drained` when the queue empties, so
`_resolveThenReturnToMenu`'s wait is satisfied. Bound in
`BattlePresentationController._unhandled_input` to `ui_accept` (not a new key)
whenever `visual_adapter.isAnimationBusy()`, deliberately not filtered on
`event.echo` so a held key's OS repeat cascades through several queued
actions. This is broader than the item's literal "during `RESOLVING`" wording:
`RESOLVING` is a `PlayerTurnController` phase and does not exist during a CPU
turn, but `isAnimationBusy()` covers both, and nothing in `ui_accept`'s
existing handling conflicts — `CONFIRM_ACTION`'s own `ui_accept` branch has
already resolved to a different phase by the time an animation is playing.

The speed control is a second slider in the dev canvas's existing top row,
next to the CPU-pacing slider it is not to be confused with (that one paces
`turn_timer`, i.e. how often a CPU turn *begins*; this one paces how long one
action's animation *takes*), wired through
`BattleUIBuilder`/`BattleUIRefs`/`_on_anim_speed_changed`.

Every file touched (`GodotVisualAdapter.gd`, `VisualActionQueue.gd`,
`BattleCameraController.gd` from FEEL-4, `BattlePresentationController.gd`,
`BattleUIBuilder.gd`, `BattleUIRefs.gd`) is presentation or scene-level; no
`src/battle_sim/` or `src/entities/` file was touched, so the simulation is
untouched by construction. Per `AGENTS.md`'s per-item execution rule — full
manual/replay validation runs once, in the plan's own final validation item,
not after each implementation item — the actual replay-diff called for by
this item's Work step 5 is deferred to `PLAN-VALIDATE` rather than run now.

---

## FEEL-6 — Make a spent phase legible on the board

**Model:** Sonnet 5 / GPT Terra

**Depends on:** none.

**Risk:** Low. A presentation tint driven by state the simulator already
exposes through `turnPhaseState`.

**Adds to validation coverage:** A unit that has spent both phases renders
distinctly from one that has not; the state clears at turn end and on undo; and
the treatment matches the dimming already used for spent command rows.

**End state:** The rule the command window already follows — a spent option
stays visible and dim rather than disappearing — holds on the board too.

### Work

1. Drive the tint from `turnPhaseState`, not from a presentation-side copy of
   turn state.
2. Match `TEXT_DIM`'s intent from `NoggTheme` so the board and the menu agree
   about what "spent" looks like.
3. Clear the treatment on turn end and after an undo restores a phase.
4. Confirm it does not fight the existing selection highlight or the FEEL-1
   threat overlay when both apply to one unit.
5. Review the backlogs.

**Files:** `src/presentation/GodotVisualAdapter.gd`,
`src/systems/BattlePresentationController.gd`.

**Resolution:** Implemented; pending end-of-plan validation, with one discovery
that changed the item's scope.

**Discovery:** the "both phases spent" state this item was written against
never reaches the screen. `PlayerTurnController._enterMenu()` calls
`endTurnNow()` the instant `has_moved and has_acted` are both true, before
`menu_changed` even emits for that state — so a board treatment gated on
literally both phases would be unobservable and untestable. Retargeted to dim
a unit once it has spent *either* phase (Move or Act), which is the real,
persistent state already visible in the command menu's own row-level dimming,
and is what makes this legible at all. The "both spent" case is still covered
as a trivial subset — it's just never on screen long enough to notice, exactly
as before this item.

**Mechanism:** rather than re-tint each material's `color_a`/`color_b` (which
would require remembering an original colour per material to undo), added a
`dim_amount` uniform to both `retro_surface.gdshader` and
`retro_surface_transparent.gdshader` (kept in sync; a monster body converted
from an imported `StandardMaterial3D` can legitimately land on either),
defaulting to 0.0 so every material is pixel-identical until it opts in.
`ALBEDO` is darkened by up to 55% in place — a plain darken, not a shift
toward `TEXT_DIM`'s specific blue-grey, since recolouring a monster's body
toward a UI text colour would fight its own team/element identity; read
`TEXT_DIM`'s *intent* (legible-but-muted, not hidden) rather than its literal
value. `BattleMeshFactory.setDimAmountRecursive()` walks a monster's visual
container the same way `updateMaterialsRecursive()`/`_configureSplitBoundsRecursive()`
already do, touching only materials tagged `RETRO_MATERIAL_META` and leaving
anything else alone. `GodotVisualAdapter.set_monster_dimmed()` is the public
entry point.

`BattlePresentationController._update_active_unit_dim()` — called from
`_on_player_menu_changed()` (which already fires on every phase transition)
and once more from `_finish_battle()` as a direct safety net — reads
`sim.turnPhaseState(activeMonsterID)` and tracks the single dimmed unit by id
in `_dimmedMonsterID`, mirroring how `BattleVisualEffects` tracks
`selectedMonsterID` for `highlight_monster`. Clears on turn end (`activeMonsterID`
already reads -1 by the time `endTurnNow()`'s `menu_changed` fires), on Undo
restoring `has_moved` to false, and at battle end.

**Composability, checked:** `highlight_monster`'s selection ring is a separate
additive aura mesh parented alongside the body; `dim_amount` only darkens the
body's own `ALBEDO`. The two do not fight and a unit can carry both at once.
The ascension base's layers share the monster's visual container and use the
same tagged materials, so they dim along with the body — read as more
thorough, not a conflict, and orthogonal to FEEL-11's later `METALLIC`/`ROUGHNESS`
uniforms on the same shader. FEEL-1's threat overlay is a ground-plane tile
marker, not a per-monster material, so it should not interact with this
either — but FEEL-1 has not been built yet in this session, so that
composability is asserted from the overlay's known construction, not verified
against running code; PLAN-VALIDATE should confirm it once FEEL-1 lands.

---

## FEEL-7 — Resolve picking and occlusion from the whole ray

**Model:** Opus 5 / GPT Sol

**Depends on:** FEEL-4, whose camera work shares the camera-to-focus ray.

**Risk:** High. `_world_pick` is the single translation from a screen position
to a board position, and every mouse interaction in the game runs through it —
hover, target selection, unit inspection, and after CAST-3 the confirm click. A
priority rule that resolves differently from the current nearest-hit behaviour
in an unanticipated case changes what every click in the game means. It also
runs on `InputEventMouseMotion`, so its cost is per-motion-event, not per-turn.

**Adds to validation coverage:** A tile whose view is blocked by another
model or by terrain can still be hovered and clicked; during target select the
resolved tile prefers a legal target over a nearer illegal one; unit inspection
outside a player turn still resolves to the unit actually under the pointer;
and hover remains smooth with the pointer swept across a crowded board.

**End state:** What the player pointed at is decided by an explicit rule over
every candidate along the ray, and geometry between the camera and the focus
stops hiding it.

### Work

1. Replace the single `intersect_ray` in `_world_pick` with an ordered list of
   hits. Two approaches — evaluate both and record the choice:
   - **Per-layer casts.** `MONSTER_PICK_COLLISION_LAYER` and
     `TILE_PICK_COLLISION_LAYER` are already separate, so two fixed queries
     yield the two candidates that matter at constant cost. Sufficient for
     picking, and the cheaper option on the hover path.
   - **Exclude-loop.** Repeat `intersect_ray`, accumulating hit RIDs in the
     query's `exclude`, to get every collider in depth order. Needed for the
     occlusion half, where the question is "everything between these two
     points", not "which of two layers".
   Use the cheap one on the hover path and the full one only where the full
   list is genuinely required.
2. Write the priority rule down before implementing it, as a comment at
   `_world_pick`. It must be deterministic and stated in one place. The
   phase-aware clause is the point of the item: while a target set exists,
   a hit resolving to a tile inside `_validTargetPositions` outranks a nearer
   hit that does not.
3. Keep the existing translation from a monster collider to that monster's tile
   position. It is correct — the player aiming at a body means the tile it
   stands on — and only its precedence changes.
4. Do not let the rule depend on private phase state. Pass the candidate set in,
   or ask `PlayerTurnController` through a read-only accessor, following
   CAST-3's precedent.
5. For the occlusion half, cast from the camera to the active unit or cursor and
   collect the intervening colliders. **Do not implement fading here.** FEEL-12
   hides non-chosen models by dither and covers this case better; two systems
   hiding geometry from the camera would fight. Build the query if a later item
   needs it, ship no visual change from it, and read the note below.
6. Measure the hover path's cost before and after with the pointer swept across
   the most crowded shipping board, and record both numbers. If the full list is
   needed on hover and is not free, cache per pointer position rather than
   per event.
7. Review the backlogs.

**Fading is only half the fix, and not the half that bit us.** Two distinct
failures hide a highlight, and this item must not conflate them. *Scene
occlusion* — terrain or another model between the camera and the tile — is what
fading addresses, and the genre's own experience is that fading alone is not
sufficient. *Self-occlusion* — a unit's own model covering the ground-plane quad
`_add_overlay` draws beneath it — is not a camera problem at all and fading is
the wrong tool: dissolving the unit the player is looking at costs more than it
returns. If self-occlusion is addressed here, address it by how the highlight is
drawn — a ring at the tile border rather than a filled quad, a vertical marker
no ground-level model can cover, depth-test-off rendering for the cursor, or
reusing `highlight_monster` when the target tile is occupied. Any of those is in
scope; fading a unit to reveal its own tile is not.

**Files:** `src/systems/BattlePresentationController.gd`,
`src/presentation/GodotVisualAdapter.gd`,
`src/systems/PlayerTurnController.gd` for the read-only accessor,
`docs/UI_DESIGN.md`.

**Resolution:** Implemented; pending end-of-plan validation.

**Neither of the two offered approaches, and deliberately so.** The item framed
this as per-layer casts vs an exclude-loop, and worried about the cost of
either on a path that runs per motion event. Both framings assume the extra
work is always paid. It need not be: the nearest hit is *already* the right
answer in every case except the one this item exists to fix. So
`_mouse_to_battle_coord()` casts the combined mask once, exactly as before, and
only when that nearest hit is **not** in the current target set does it pay a
second, tile-layer-only cast to see past whatever is in front. The common path
is bit-for-bit the old cost, and the extra cast is spent only where it can
change the answer. `_world_pick()` gained an optional `layerMask` to serve
both.

The priority rule is written once, as a doc comment on
`_mouse_to_battle_coord()`: nearest hit wins by default; while a target set is
on screen, a tile inside that set outranks a nearer hit that is not. The
monster-collider-to-tile translation is unchanged — only its precedence moved.
`_coord_from_hit()` factors that translation out so both casts interpret a hit
identically.

**Scoped to `TARGET_SELECT`, not `MOVE_SELECT`.** Move select accepts a cursor
on any in-bounds tile (`_previewPath()` handles an unreachable one), so
preferring reachable tiles there would pull the cursor away from what the
pointer is actually over — a behaviour change, not a fix. Recorded because the
item's wording ("while a target set exists") could be read either way.

The candidate set is read through a new
`PlayerTurnController.validTargetPositions()`, which returns a copy, per step
4's requirement not to depend on private phase state.

**Two things this item asked for that were not built, each with a reason:**

- **No occlusion query.** Step 5 says to build it "if a later item needs it"
  and to ship no visual change from it. FEEL-12 supersedes the fade and needs
  the *pick* result, not a camera-to-focus ray, so nothing consumes such a
  query — building it now would be dead code. FEEL-12 will take the hovered
  identity from this pick, as step 3 of that item requires.
- **No before/after hover measurement.** Step 6 asks for two recorded numbers.
  Obtaining them means launching the game and sweeping a pointer, which
  `docs/DEVELOPMENT.md` reserves for the final validation item. Rather than
  invent figures, the design was changed so the measurement is not the
  deciding factor: the hover path's cast count is unchanged at one.
  `PLAN-VALIDATE` should still confirm hover feels smooth on a crowded board.

Parse-checked with `--check-only`.

---

## FEEL-8 — Show the turn order

**Model:** Opus 5 / GPT Sol

**Depends on:** CAST-5. Independent of the other FEEL items.

**Risk:** Medium. A turn-order display that drifts from the simulator's actual
order is worse than none: the player plans against it and is punished for
trusting it. Death, and any future effect that reorders turns mid-round, are
where it will drift.

**Adds to validation coverage:** The displayed order matches
`TurnManager.turnOrder` at every point in a round; it updates when a unit dies
mid-round; it survives save/load and replay; and it never shows a dead unit as
upcoming.

**End state:** The player can see who acts next without inferring it from speed
stats.

### Work

1. Read `src/battle_sim/TurnManager.gd` first. `turnOrder` is sorted once per
   round and popped from the front, and `BattleEvents.round_started` already
   emits the full order — build the display from those, and add no second copy
   of turn state in the presentation layer.
2. Render the upcoming order as a window per the §8 taxonomy. Dock it where it
   does not collide with the command window (left), the status pair (bottom), or
   the prompt (top-centre); state the chosen dock and its measured width in the
   Resolution, and add the row to the §8 table.
3. Show the acting unit distinctly from those queued behind it, and show enough
   entries to be useful without becoming a second battle log — cap the count
   and say what the cap is.
4. Subscribe to the events that change the order: round start, turn end, and
   death. Do not poll.
5. Verify against a unit dying mid-round that its entry leaves the display, and
   that the entry for the unit currently acting is correct at every step.
6. Confirm the display is presentation-only: replaying a battle with and without
   it produces an identical event history.
7. Review the backlogs.

**Files:** `src/systems/BattlePresentationController.gd`,
`src/presentation/` for the window, `docs/UI_DESIGN.md`.

**Resolution:** _pending_

---

## FEEL-9 — Bound every stat to the displayable range

**Model:** Opus 5 / GPT Sol

**Depends on:** none. Execute before FEEL-10, which formats to the range this
item guarantees.

**Risk:** High, and of a different kind from every other item in this phase.
**This is the one item in the cycle that changes simulation behaviour.** A stat
that today reaches 1004 or -2 will resolve differently afterwards, so combat
outcomes, recorded event histories, and any stored replay that exercises an
out-of-range value legitimately change. An executing agent must not treat a
changed replay number here as a regression to be restored — but must confirm
each change traces to a clamp and not to an unrelated defect.

**Adds to validation coverage:** No monster stat is ever below 0 or above 999
at any point in a battle, including immediately after buff application, buff
expiry, damage, healing, and level or ascension growth; and a replay diff
against a pre-clamp run is explained entirely by clamping.

**End state:** The displayable range is a property the simulation guarantees,
not one the presentation layer hopes for.

### Work

1. Find every write to `hitpoints`, `max_hitpoints`, `atk`, `def`, `speed`, and
   `move` on `Monster`. Start from `src/entities/Monster.gd`,
   `src/battle_sim/SpellEffectResolver.gd`, `src/battle_sim/CombatResolver.gd`,
   and `src/battle_sim/DirectDamageRules.gd`, then sweep for the rest — a clamp
   applied at four of five write sites is worse than none, because the one gap
   becomes the case nobody expects.
2. Clamp at the point of write, in the entity, so no caller can bypass it. A
   helper on `Monster` that every mutation routes through is preferable to a
   `clampi` repeated at each call site.
3. **Bounds are 0 and 999 inclusive**, per the settled decision. Buff
   application, buff expiry, and growth all clamp; expiry in particular must not
   restore a value the clamp already discarded — decide whether buffs are stored
   as modifiers over an unclamped base or as clamped absolute values, and say
   which in the Resolution. This is the item's one real design decision.
4. Check the floor against gameplay meaning before finalising. `speed` feeds
   `TurnManager`'s sort and `move` feeds reachability; verify a 0 in either
   degrades sensibly rather than producing an unreachable or unorderable unit.
   Report what you find; do not raise the floor to 1 without asking.
5. Leave `hitpoints` reaching 0 alone as the death condition. Clamping must not
   change what death is.
6. Run a replay before and after and diff the event history. Explain **every**
   divergence, line by line, in the Resolution. An unexplained one is a defect.
7. Review the backlogs.

**Files:** `src/entities/Monster.gd`, `src/battle_sim/SpellEffectResolver.gd`,
`src/battle_sim/CombatResolver.gd`, `src/battle_sim/DirectDamageRules.gd`, plus
whatever the sweep in step 1 turns up.

**Resolution:** Implemented; pending end-of-plan validation. **This item turned
out to be far lower risk than it was written as**, for two reasons found by
inspection rather than assumed.

**The sweep found only one file, not four.** Every write to the six stats is
either in `Monster.gd` itself (construction from derived stats; `take_damage`'s
`max(0, ...)`; `heal`'s `min(max_hitpoints, ...)`) or in
`BattleStateSerializer.gd`'s deserialization. `CombatResolver`,
`SpellEffectResolver`, and `DirectDamageRules` only *read* these fields to
populate events; they mutate HP exclusively through `take_damage`/`heal`.

**The item's "one real design decision" is moot.** Buffs never write a stat.
`_applyAttackBuff()` stores `{"atk_bonus": N}` as a status effect, and
`_statBonus()` sums those at damage time on top of `get_effective_atk()`. So
there is no stored absolute to clamp and nothing for expiry to restore — the
feared "expiry restores a value the clamp already discarded" is structurally
impossible, not merely avoided.

**Mechanism:** property setters on the six fields, not a helper. A helper only
binds callers who remember it; a setter cannot be bypassed, including by code
written later. Assigning to a property inside its own setter does not re-enter
it in GDScript 4 — verified with a throwaway probe before relying on it, since
a wrong assumption there is a runtime stack overflow that no parse check would
catch.

**Scope held deliberately at stored stats.** `get_effective_atk()`'s Resonance
multiplier and the buff bonus can still carry a *derived* total past 999. Those
are not clamped: the status windows FEEL-10 formats render the stored fields,
and bounding combat math would change outcomes rather than what a readout can
show — a balance change this item does not own.

**Floors checked (step 4), nothing raised.** `TurnManager.sortBySpeed()` only
sorts, with an id tie-break and no division, so a 0-speed unit still takes
turns, last. `move` 0 leaves a unit only its own tile, which
`_enterMoveSelect()` already appends unconditionally. Neither is reachable from
authored data today; both degrade sensibly if they ever are.

**Replay divergence: none is possible on current data**, so step 6's "explain
every divergence" has nothing to explain. The whole catalogue tops out at
HP 60 / ATK 8 / DEF 8 with every growth at 0 (identical at levels 1, 50, and
99) — more than an order of magnitude below the bound. A focused probe
confirmed all six stats clamp on write, that ordinary damage, death at exactly
0, and healing after death are unchanged, and that **no** catalogue monster at
levels 1/50/99 lands on or beyond either bound. The clamp is therefore a
guarantee for future data and for FEEL-10's three-digit assumption, not a
change to any battle that can currently be played. `PLAN-VALIDATE`'s replay
diff should accordingly expect **zero** divergence from this item, not
clamp-explained divergence.

---

## FEEL-10 — Fixed-width stat values

**Model:** Sonnet 5 / GPT Terra

**Depends on:** FEEL-9, which makes three digits sufficient by construction.

**Risk:** Low. Formatting inside one render function. The only hazard is a value
that does not fit the assumed width.

**Adds to validation coverage:** Every numeric stat in the actor and target
status windows renders three digits wide; values do not reflow horizontally as
they change; and a value outside three digits degrades legibly rather than
truncating.

**End state:** A stat sits at a fixed screen position for the whole battle.

### Work

1. In `BattlePresentationController._renderStatusWindow`, zero-pad to three
   digits: both sides of the `HP` pair, and `ATK`, `DEF`, `SPD`, `MOV`. Use one
   small helper rather than repeating a format string six times.
2. FEEL-9 makes three digits sufficient by construction, so no out-of-range
   branch is needed for correctness. Still assert rather than assume: if a value
   arrives outside 0–999, render its true value and take the extra column, and
   `push_warning` — a stat that escaped the clamp is a FEEL-9 defect and the
   status window should say so instead of hiding it behind a format string.
3. Keep every stat currently in the windows. This item changes formatting only —
   no row is dropped, added, or reordered.
4. Confirm the change is width-neutral. The body font is monospace and §8's
   widths were measured against real content, so padding must not push the
   540px status windows over budget; re-run `debug/preview_theme.gd` and record
   the numbers.
5. Leave the HP threshold tint at [BattlePresentationController.gd:830](src/systems/BattlePresentationController.gd:830)
   working — it reads the model, not the string, so padding must not disturb it.
   Verify rather than assume.
6. **Scope boundary:** the forecast window, the prompt, and the battle log keep
   their unpadded numbers. Padding is for values that sit in a fixed cell and
   are re-read every turn; prose and one-shot readouts are neither. Do not
   propagate this to `_forecastText`.
7. Update the §8 note on the status windows' fixed-cell shape.
8. Review the backlogs.

**Files:** `src/systems/BattlePresentationController.gd`, `docs/UI_DESIGN.md`.

**Resolution:** Implemented; pending end-of-plan validation.

Added one helper, `_statText(value: int) -> String`, used by all six numeric
cells (`HP`'s pair, `ATK`, `DEF`, `SPD`, `MOV`). It checks
`value < Monster.STAT_MIN or value > Monster.STAT_MAX` (FEEL-9's clamp
constants) and `push_warning`s rather than truncating if a value ever escapes
that range — the out-of-range branch the item anticipated turned out to need
no special formatting, since `%03d` already renders a wider value in full;
the only thing worth adding was the warning, because an escaped clamp is a
FEEL-9 defect this window should surface, not silently format around.

**Width-neutrality verified with real font metrics, not estimated**, since
`debug/preview_theme.gd` is interactive (needs a rendering context to judge
visually) and this cycle's convention has been to defer that class of check to
`PLAN-VALIDATE`. Instead wrote a temporary headless probe — same technique as
`preview_theme.gd`'s own `_required_width()`, `Font.get_string_size()` against
the real shipping font and theme, no rendering required — measured, recorded
the numbers below, and deleted it; it is scratch, not part of this diff.

The first pass compared every cell against the single-column width
(`STATUS_CELL_OFFSETS[1] - [0]`, 192px) and flagged `HP` as a failure: `"999 /
999"` needs 288px, over 192px. **That comparison was wrong for `HP`
specifically.** `HP`'s row only ever places one cell at column 0 —
`ATK`/`DEF` and `SPD`/`MOV` are the rows that fill both column 0 and column 1,
which is what actually bounds them to 192px each. `HP`'s real ceiling is
column 2, where the Resonance cell sits when present (`STATUS_CELL_OFFSETS[2] -
[0]`, 384px) — `add_stat_row()` positions each cell at its column offset and
never clips or wraps, so a too-wide value bleeds into whatever's next, and for
`HP` that is empty space unless a Resonance cell occupies column 2 for that
monster. Corrected numbers: `HP` needs 288px of 384px available (96px to
spare); `ATK`/`DEF`/`SPD`/`MOV` each need 168px of their 192px column (24px to
spare). All four comfortably fit. Recorded in the new §8 paragraph rather than
only here, since a future change to any of these strings should be checked
against the same two numbers.

The HP threshold tint at [BattlePresentationController.gd:1084](src/systems/BattlePresentationController.gd:1084)
needed no change and none was made — verified rather than assumed: it reads
`monster.hitpoints` and `monster.max_hitpoints` directly, never the formatted
string. `_forecastText`, the prompt, and the battle log are untouched, per the
item's scope boundary.

---

## FEEL-11 — Give the base its own material

**Model:** Sonnet 5 / GPT Terra

**Depends on:** none.

**Risk:** Medium. `retro_surface.gdshader` is shared by every mesh in the scene,
so new uniforms must default to today's hardcoded values or the whole board
changes appearance at once. The aesthetic risk is the larger one: a
physically-correct metal would read as a modern material dropped into a
deliberately PS1-era scene.

**Adds to validation coverage:** A model base is distinguishable from the
creature body standing on it at a glance and at gameplay camera distance; every
other mesh in the scene is pixel-identical to before; and the ascension stack
stays countable.

**End state:** The base reads as a manufactured plinth the creature stands on,
not as more creature.

### Work

1. `retro_surface.gdshader` hardcodes `ROUGHNESS = 1.0`, `METALLIC = 0.0`, and
   `SPECULAR = 0.25` in `fragment()`. Promote all three to uniforms defaulting
   to exactly those values, so every existing material is unchanged until it
   opts in.
2. Extend `createMaterial` with an optional surface-finish argument, and give
   `createModelBase` a finish distinct from creature bodies: **metallic, low
   roughness, dark**. Combined with the existing `BASE_COLOR_DARKEN`, the base
   becomes dark-but-polished — pewter or oiled bronze — which separates from a
   matte body by *how it catches light*, not by being brighter. That distinction
   survives any team colour, which a hue shift would not.
3. Make the finish carry the ascension tier. The stack already lightens each
   layer up ([BattleMeshFactory.gd:165](src/presentation/BattleMeshFactory.gd:165));
   ramp metallic up and roughness down alongside it, so a higher tier reads as
   *more refined metal* rather than only *more layers*. Two signals for one
   fact, both derived from `layerIndex`, no new state.
4. Keep it era-appropriate. The scene commits to vertex snapping and affine
   texture mapping; a full PBR metal fights that. Aim for a raised specular
   response and, if it helps the base's edge separate against a dark board, a
   cheap fresnel rim term — not physical accuracy. If a rim term is added, put
   it behind its own uniform, default off.
5. Verify at gameplay camera distance under the retro pipeline, not just in a
   close-up preview. An effect that only reads when zoomed in has not solved the
   problem; say so plainly if that is what you find.
6. Confirm the ascension-tier probe from `createModelBase` still passes: layer
   count, stack top landing on `BASE_TOTAL_HEIGHT`, unchanged footprint, and the
   base carrying its own material.
7. Review the backlogs.

**Files:** `assets/shaders/retro_surface.gdshader`,
`src/presentation/BattleMeshFactory.gd`, `docs/UI_DESIGN.md` if it records
material language.

**Resolution:** Implemented; pending end-of-plan validation. `docs/UI_DESIGN.md`
had no material language to update; `docs/ARCHITECTURE.md`'s existing
paragraph on `createModelBase()` did, and was touched instead — see below.
`retro_surface.gdshader`'s previously hardcoded `ROUGHNESS = 1.0`,
`METALLIC = 0.0`, `SPECULAR = 0.25` are now uniforms (`surface_roughness`,
`surface_metallic`, `surface_specular`) defaulting to those exact values, so
every existing material is unchanged until it opts in. Added a cheap fresnel
rim (`rim_amount`/`rim_color`, off by default) behind its own uniform per the
item's "if it helps" phrasing — deliberately left off for the base itself in
this pass, since judging whether it helps separation against the board needs a
real window, which this session does not have; available for `PLAN-VALIDATE`
to turn on if the plain finish change is not enough.

`BattleMeshFactory.createMaterial()` gained matching optional trailing
parameters, all defaulting to the shader's own defaults, so no existing call
site's behaviour changes. `createModelBase()` now derives `metallic`/`roughness`
from `layerIndex` via two new constant pairs (`BASE_METALLIC_START`/`_PER_LAYER`,
`BASE_ROUGHNESS_START`/`_PER_LAYER`, clamped), alongside the colour-lightening
it already did — dark and polished at tier 0 (metallic 0.55, roughness 0.35),
ramping to metallic 0.85/roughness 0.20 by tier 3, the highest tier the
existing probe exercises, without saturating either clamp.

**Deferred to `PLAN-VALIDATE`, per `docs/DEVELOPMENT.md`'s validation-timing
rule** (no relaunching the game or repeating acceptance flows after each
item): actually running `debug/probe_ascension_base.gd`, and judging the
result at gameplay camera distance through the retro pipeline. Verified
instead by static review against the probe's own assertions — layer count,
height budget, footprint, and a non-null, distinct-instance base material are
all untouched by this change, and none of the new parameters affect geometry.

---

## FEEL-12 — Dither away what the player is not choosing

**Model:** Opus 5 / GPT Sol

**Depends on:** FEEL-7, whose picking work supplies the hovered-model identity
this item needs, and whose scene-occlusion half this item largely replaces.

**Risk:** High. This changes how every model in the scene renders, driven by
phase state that lives in a different layer. The failure modes are a model left
dithered after the phase ends, the active unit dithering itself, and hover
thrash — a model flickering between solid and dithered as the pointer crosses
its edge.

**Adds to validation coverage:** During move select and target select every
model dithers except the active unit and the model currently under the pointer;
hovering any model — target or not — restores it solid for as long as the
pointer is on it; all models return solid on leaving the phase, on turn end, and
at battle end; and the dither pattern is stable in screen space as the camera
moves.

**End state:** The board reads through the units standing on it while the player
is choosing a tile, without anything vanishing.

### Work

1. Implement as **screen-door transparency**: a Bayer-matrix threshold on
   `FRAGCOORD` with `discard` below it, in `retro_surface.gdshader` behind a
   `dither_amount` uniform defaulting to 0. Do **not** route this through
   `retro_surface_transparent.gdshader` — `discard` keeps depth writes and needs
   no transparency sorting, and screen-door is what the hardware this scene
   imitates actually did. The pattern must be anchored to `FRAGCOORD`, not to
   UV: a screen-space grid reads as a stable pixel dither, while a UV-space one
   swims across the model as it moves and looks like a texture bug.
2. Drive it from one rule, stated in one place: a model renders solid if it is
   the active unit **or** the model currently under the pointer; otherwise it
   dithers. Everything else follows.
3. Take the hovered model from FEEL-7's resolved pick, not from a second
   raycast. One source of "what is under the pointer" for the whole game.
4. Apply hysteresis or a small dwell before a hover restores a model, and verify
   by sweeping the pointer rapidly across a crowded board. Flicker is the defect
   most likely to survive to acceptance, because it does not appear when testing
   one careful hover at a time.
5. Gate on `MOVE_SELECT` and `TARGET_SELECT` only. `MENU`, `CONFIRM_ACTION`, and
   `RESOLVING` all render solid — during confirm the player is reading a
   committed choice, and during resolution they are watching it happen.
6. Restore every model on phase exit through a single path, so a new phase or an
   early turn end cannot strand one dithered. Prefer clearing all, not tracking
   who was dithered.
7. Check interaction with FEEL-6's spent-unit treatment and FEEL-1's threat
   overlay: a spent, dithered, threatened unit must still be legible as all
   three. Report if the combination does not hold rather than tuning it silently.
8. Confirm against the CRT and retro pipeline that the dither survives
   downsampling. A one-pixel checker at 320×240 upscaled through the CRT shader
   may read as a haze rather than a pattern; if so, use a coarser matrix and say
   which.
9. **This supersedes FEEL-7's fade half.** Record that in FEEL-7's Resolution if
   FEEL-7 has already run, or drop the fade from FEEL-7's scope if it has not.
   Do not ship both — two systems hiding geometry from the camera will fight.
10. Review the backlogs.

**Files:** `assets/shaders/retro_surface.gdshader`,
`src/presentation/BattleMeshFactory.gd`,
`src/presentation/GodotVisualAdapter.gd`,
`src/systems/BattlePresentationController.gd`, `docs/UI_DESIGN.md`.

**Resolution:** Implemented; pending end-of-plan validation.

Screen-door transparency as specified: a Bayer threshold on `FRAGCOORD` with
`discard`, behind a `dither_amount` uniform defaulting to 0, in
`retro_surface.gdshader` — not routed through the transparent variant. The
matrix is **4×4 rather than 2×2**, chosen up front against step 8's concern:
a one-pixel checker at 320×240 through the CRT upscale flattens into haze,
where a 4×4 cell stays a visible weave. `DITHER_STRENGTH` is 0.55, not 1.0 —
a fully discarded model is invisible, and the intent is to see *past* units,
not to remove them.

The rule lives in one place, `_update_model_dither()`: solid if the active
unit or the model under the pointer, dithered otherwise, and only during
`MOVE_SELECT`/`TARGET_SELECT`. `set_models_dithered(dithered, solidIDs)` takes
the whole exception list and rewrites every model each call rather than
diffing — step 6 asked for restoration through a single path, and clearing all
is what makes stranding impossible, since a diff needs remembered state and
remembered state is exactly what strands a model on an unenumerated exit.
Called from `_on_player_menu_changed()` (every phase transition) and
`_finish_battle()`.

Hover identity comes from FEEL-7's already-resolved tile via
`monster_id_at_position()`, not a second raycast, per step 3. Step 4's
hysteresis is a dwell (`DITHER_HOVER_DWELL_SECONDS`, 80ms) applied only to
*gaining* hover; losing it is immediate, since a model no longer under the
pointer should not linger solid.

**A latent bug was found and closed while wiring this.** A pointer miss
resolves to `Vector2i(-1, -1)`, and `Matrix.at()` indexes its backing arrays
directly — GDScript's negative indexing would have returned the board's far
corner, so "pointer over nothing" would have read as "pointer over whichever
unit stands at the last tile". `monster_id_at_position()` bounds-checks first.

**Step 7, composability:** FEEL-6's dim and this dither cannot co-occur on one
model. FEEL-6 only ever dims the *active* unit, and the active unit is
permanently in the solid list, so a spent unit is dim but never dithered. They
are independent uniforms regardless (`dim_amount` scales ALBEDO,
`dither_amount` discards fragments) and would compose if that ever changed.
FEEL-1's threat overlay could not be checked: it is blocked on CAST-5 and does
not exist yet. It draws ground-plane tile markers rather than per-monster
material state, so no interaction is expected, but that is reasoned from its
specified construction, not verified — `PLAN-VALIDATE` should confirm once
FEEL-1 lands.

**Step 9 was already satisfied by FEEL-7**, which ran earlier this session and
recorded in its own Resolution that no occlusion query and no fade were built
because this item supersedes them. Nothing to reconcile; the two do not ship
overlapping systems.

Shader compilation was probed directly — worth doing, because a shader error
does not surface in a GDScript `--check-only` pass, and the first attempt used
an invalid array-literal form that only the compile caught. All four touched
files parse clean. The visual questions this item raises — whether the weave
survives the CRT at gameplay distance, and whether the dwell is long enough on
a crowded board — need a real window and belong to `PLAN-VALIDATE`.

---

## FEEL-13 — Let an action finish before the next one starts

**Model:** Opus 5 / GPT Sol

**Depends on:** FEEL-5, whose speed multiplier every duration here must respect.

**Risk:** High. `VisualActionQueue` has four documented invariants and a
serial-number race between a tween's `finished` signal and its watchdog. Any
change to how long an action is considered active moves the watchdog's arming
window, and a watchdog that fires early turns a normal completion into a
"stalled action" warning plus a forced finalize. The queue is also what
`PlayerTurnController._resolveThenReturnToMenu` waits on, so a hold that never
ends strands the player's turn in `RESOLVING` with no menu.

**Adds to validation coverage:** An attack, a spell cast, and a defeat each
remain visible through the substantial part of their effect before the next
queued action begins; no watchdog warning appears during normal play; the
`drained` signal still fires and the command menu still reopens after every
resolved phase; and holds scale with the FEEL-5 speed setting and are cut by
its skip.

**End state:** The queue advances on how long an action actually looks like it
takes, not on the duration of the one tween that happens to represent it.

### Work

1. Read `src/presentation/VisualActionQueue.gd` end to end before editing,
   including the `setPaused` comment explaining why pause deliberately does not
   bump `_serial`. That reasoning constrains this change.
2. The defect is concrete: `activate(tween, action, duration)` is told the tween
   duration, but start handlers spawn effects outside the tween.
   `_start_bump_animation` runs a 0.25s tween and also calls
   `SpellCastAuraScript.spawn`; `_start_defeat_animation` runs a 0.38s tween
   alongside `GPUParticles3D` with `lifetime = 0.42`. Read
   `src/presentation/effects/SpellCastAura.gd` for its real lifetime rather
   than assuming.
3. Let a start handler declare a **hold** — the duration the action should
   occupy regardless of its tween — and have the queue advance on
   `max(tween, hold)`. Prefer this to padding tweens with dead trailing time,
   which would make the tween lie about what it animates.
4. **Recompute `_watchdogDuration` from the same maximum.** It is currently
   `duration + WATCHDOG_MARGIN`; if a hold outlasts the tween and the watchdog
   is still armed against the tween, it fires mid-hold and reports a stall that
   did not happen. This is the most likely way to get this item wrong.
5. Keep the single completion path in `_complete` and the serial guard exactly
   as they are. Add the hold before completion, not a second completion route.
6. "Mostly through", not "fully through", per the settled decision. Overlapping
   the tail of one effect with the start of the next is what keeps a battle from
   feeling like a slideshow; pick the fraction, make it a named constant, and
   say what you picked.
7. Make the hold obey FEEL-5: scaled by the speed multiplier, and cut by the
   skip. A hold that ignores the speed setting makes the setting look broken.
8. Verify `_resolveThenReturnToMenu` and `_onQueueDrained` still return the
   player to the menu after a move, an attack, a spell, and a defeat.
9. Review the backlogs.

**Files:** `src/presentation/VisualActionQueue.gd`,
`src/presentation/GodotVisualAdapter.gd`,
`src/presentation/effects/SpellCastAura.gd` if it must report its lifetime.

**Resolution:** Implemented; pending end-of-plan validation.
**`VisualActionQueue.gd` was not modified at all** — which was this item's whole
High-risk surface.

The item proposed teaching the queue a hold and recomputing `_watchdogDuration`
from `max(tween, hold)`. That works, but it puts the change inside the four
documented invariants and the serial race, and step 4 correctly identified the
watchdog as the most likely thing to get wrong. The hold does not need to live
there. `_activateScaled()` now appends the remainder to the action's **own
tween** as an explicit `tween_interval`, so the tween genuinely *is* as long as
the action looks — and the queue advancing on `tween.finished` becomes correct
by construction rather than by a second mechanism. The item's End state is met
exactly; the invariants are untouched.

Appending to the tween also satisfies step 7 for free, where a parallel
`SceneTree` timer (the obvious alternative) would have silently broken two
things: `setPaused()` pauses this tween, so the hold freezes with everything
else; `set_speed_scale()` compresses the interval, so the hold obeys the speed
setting; and `skipActive()`'s `kill()` cuts the hold short, so skip works on
it. A timer reaches none of those. Step 3's objection — that padding "would
make the tween lie about what it animates" — does not apply to
`tween_interval`, which is the engine's explicit "then wait" tweener and states
the intent plainly.

**Measured, not assumed.** `SpellCastAura`'s visible run is 1.1s (its
`lifetime_progress` tween and wisp particles), now a public `VISIBLE_DURATION`
used by both rather than two copies of a literal, while the bump tween is
0.25s — the queue was advancing with roughly three-quarters of the aura still
playing. `ACTION_HOLD_FRACTION` is 0.6, so a spell now occupies 0.66s. A probe
against the real tween shape (0.10 + 0.15 property tweens, then
`chain().tween_interval(0.41)`) measured 0.655s, and confirmed `set_speed_scale`
compresses a hold proportionally and `kill()` prevents `finished` from firing.
`chain()` is used so the interval waits for every preceding step, including on
the defeat animation's parallel tween.

Defeat is deliberately unchanged: its shatter particles
(`CAPSULE_SHATTER_LIFETIME`, now named rather than a literal) run 0.42s against
a 0.38s tween, so the 0.6 fraction yields 0.252s and no interval is appended.
The relationship is stated at the call site anyway, so it stays correct if
either constant moves.

Step 8's check that the menu still reopens is left to `PLAN-VALIDATE` with the
rest of the manual flows; the mechanism it depends on — `drained` firing from
`tween.finished` — is the one that was deliberately not altered.

---

## FEEL-14 — Damage numbers over the models

**Model:** Sonnet 5 / GPT Terra

**Depends on:** FEEL-13, which is what stops a number appearing after the queue
has already moved on to the next action.

**Risk:** Medium. A pixel font drawn in 3D space smears at fractional sizes —
`NoggTheme` states the integer-size rule explicitly — and this is the first
text the project renders in the world rather than in a window. Numbers that
outlive their unit, or that stack into an unreadable pile on a multi-target
spell, are the other two failure modes.

**Adds to validation coverage:** Every unit taking damage shows a number above
it; the number is legible at gameplay camera distance through the retro and CRT
pipeline; several units damaged by one spell each show their own readable
number; and no number survives its unit's defeat or the end of the battle.

**End state:** Damage is something the player reads off the board, not
something they infer from a health bar moving.

### Work

1. Follow `src/presentation/StatusEffectBillboard.gd` as the precedent — it is
   already a `Node3D` that re-orients to the active camera each frame — rather
   than inventing a second way to put something above a model.
2. Use the menu font, `NoggTheme.GAME_FONT_PATH`
   (`shining-force-ii-small.otf`), at an integer size. `NoggTheme` is the single
   source of truth for fonts; do not load the file path directly from here.
3. Draw the number **twice**: a black copy, and a white copy offset slightly up
   and diagonally over it. This is a hard offset shadow, not a symmetric
   outline — `Label3D.outline_size` produces the wrong look and must not be
   substituted for it. Two `Label3D` nodes with an offset is the intended
   construction.
4. Set `fixed_size` on the labels so the glyphs hold a constant screen size and
   the pixel font never lands on a fractional scale, whatever the camera
   distance.
5. Animate: pop up, then pop down and fade out. Overshoot on the way up reads as
   impact — `TRANS_BACK` is already used for the defeat animation and is the
   consistent choice. Make the durations named constants and scale them by
   FEEL-5's speed multiplier.
6. Stack or offset simultaneous numbers so a multi-target spell produces several
   readable numbers rather than one overlapping pile. State the rule you chose.
7. Free every number on its own completion, and also when its unit is defeated
   or the battle ends. A billboard parented to a container that `_finalize_animation`
   calls `queue_free()` on will go with it — verify that rather than assume it.
8. Count the number's lifetime in the FEEL-13 hold for the action that caused
   it, so the queue does not advance out from under it.
9. Drive it from the damage the adapter already receives for its health-bar
   update. Do not add a second event subscription for the same fact.
10. Confirm legibility at gameplay distance through the retro downsample and the
    CRT shader, not only in a close-up. Report plainly if the font is unreadable
    at 320×240 rather than quietly enlarging it past the theme's sizes.
11. Review the backlogs.

**Files:** `src/presentation/` for the new billboard,
`src/presentation/GodotVisualAdapter.gd`,
`src/presentation/theme/NoggTheme.gd` if a size constant belongs there,
`docs/UI_DESIGN.md`.

**Resolution:** Implemented; pending end-of-plan validation.

`src/presentation/effects/DamageNumberBillboard.gd` follows
`StatusEffectBillboard.gd` as instructed — it IS the container (a
`StatusEffectBillboardScript.new()` instance), not a re-derivation of its
camera-facing logic. Two `Label3D` children, black then white, offset up and
diagonally (`_SHADOW_OFFSET`/`_FRONT_OFFSET`, the white also nudged toward the
camera in local +Z so draw order never depends on child-add order), both
`billboard = BILLBOARD_DISABLED` (the container already billboards the whole
group) and `fixed_size = true`. Font comes from
`NoggThemeScript.build_game_theme().default_font`, cached in a static var
after the first call rather than rebuilding a `Theme` per spawn. `spawn(parent,
world_pos, amount, is_heal)` mirrors `SpellCastAura.spawn`'s exact signature
shape and parenting convention (a shared `visual_parent`, world-space
position) rather than parenting to the target's own container — deliberate,
see the lifecycle note below. A heal is `+amount`, not a separate colour: the
item's own spec is a single black+white scheme for every number, and adding a
colour axis for heals would be a second visual language it did not ask for.

**A real, reproducible defect was found and fixed before this could be
trusted, and it is worth another engineer's five minutes to read.** The first
version chained phases with `tween.chain().set_parallel(true)` — mirroring
what looked like FEEL-13's own pattern. Measured against real elapsed time
(a temporary headless probe; not part of this diff) it completed in ~47-57%
of its declared `VISIBLE_DURATION`, reproducibly. Rewriting to use only the
persistent `set_parallel(bool)` toggle (no `chain()`/`parallel()` one-shot
calls) fixed the *sequencing*, verified against an isolated reproduction —
but the real file, unchanged in structure, still measured short. The actual
cause, found by bisecting `_build_label`'s properties down to nothing and
back up: **the file needs a `tween_callback()` with an empty body at every
phase boundary.** Without one, a `set_parallel` transition with no callback
between it and the next tweener group loses time — empirically roughly 30% of
the fade phase, reproducible across repeated runs, fixed by adding the
no-op callbacks and reproducibly correct (0.783–0.790s measured against a
declared 0.800s) across repeated runs afterward. The three no-op callbacks in
`_animate()` are that fix, not debug residue — the comment above the function
says so explicitly, because a future reader stripping them as pointless would
reintroduce this. No complete theoretical explanation for *why* was found;
the fix is verified empirically against real elapsed time, the same standard
FEEL-13 held itself to for its own tween work.

**Wiring:** `VisualAction` gained `has_damage_number`/`damage_number`/`is_heal_number`,
copied in `clone()`. `_on_monster_attacked`, `_on_monster_cast_spell`, and
`_on_monster_healed` set them; a miss or an empty-tile cast leaves
`has_damage_number` false, so no number shows where there is no target.
`_start_bump_animation` (attacks and spell damage) spawns the number and folds
`DamageNumberBillboardScript.VISIBLE_DURATION` into `holdDuration` via `maxf`
— unlike the aura's `ACTION_HOLD_FRACTION` scaling, the number's hold is
**not** fractioned, because the aura is allowed to still be playing when the
queue moves on but a number's fade must fully resolve first, per the item's
own step 8.

**Heals needed a mechanism that did not exist.** `_on_monster_healed` builds a
`MESSAGE`-kind action, and `_present_queued_message` — correctly, for every
other `MESSAGE` action — is a synchronous state update with no tween, so the
queue has always advanced past it instantly. A heal carrying a number is the
one case that now needs to hold. Added `_start_message_damage_number()`,
called from `_start_queued_animation`'s `MESSAGE` branch: it returns `false`
unchanged for every other `MESSAGE` action (`has_damage_number` unset), and
for a heal it spawns the number and gives `_activateScaled` a real `Tween` —
created on `visual_parent` with nothing to animate but the hold itself, the
plainest way to satisfy `_activateScaled`'s requirement without inventing a
second hold mechanism next to FEEL-13's.

**Step 6 (stacking) is moot, verified against the simulator, not assumed.**
`CombatResolver.executeCastSpell` (`for affectedID in actualTargets:
_applySpellEffects(...)`) emits one damage/heal event per affected target, each
becoming its own queued action. `VisualActionQueue`'s first documented
invariant is "exactly one action animates at a time." With the hold correctly
folded in (this item's own step 8), a second target's action cannot begin
until the first target's number has *fully* finished, including its fade —
so two numbers from one multi-target spell are structurally never
simultaneous, and stacking/offset logic would be unreachable dead code. Noted
in `docs/ARCHITECTURE.md` rather than built.

**Step 7 (free on defeat/battle end), reasoned rather than specially
handled.** During ordinary playback the same serialization guarantee applies:
a defeat action for the same target cannot begin until this one's number has
finished and freed itself, so there is nothing to race. The one narrow
exception is an explicit player **skip**: `skipCurrentAnimation()` kills the
*queue's* carrier/hold tween, not the billboard's own independent tween
(`DamageNumberBillboard._animate` creates its own), so a skip lets the queue
advance while the number keeps fading in the background — this is not a new
gap; `SpellCastAura` already has the identical property (its own
`_CLEANUP_DELAY` timer is independent of the queue too), and this item does
not go further than that precedent. At battle-end teardown, freeing the
scene tree kills any in-flight tween on a freed node automatically — standard
Godot node/tween lifecycle, not code this item had to write.

**Parenting to `visual_parent`, not the target's own container, was a
deliberate choice against the double-offset trap.** The target's own
container's `.position` already *is* its world position within its parent;
parenting there and then setting `billboard.position = world_pos + offset`
would apply that offset twice. `SpellCastAura.spawn(visual_parent, worldPos,
...)` already establishes world-space-position-under-a-shared-parent as this
codebase's convention for transient VFX; this follows it rather than
inventing per-target parenting, and per the note above, the serialization
guarantee makes the "does it outlive its target" concern the target-container
approach would have solved for free a non-issue anyway.

**Sizing (`_FONT_SIZE`, `_PIXEL_SIZE`) and legibility through the retro/CRT
downsample are judgment calls, stated as such**, and deferred to
`PLAN-VALIDATE` per `docs/DEVELOPMENT.md` — this session has no rendering
context to judge them in. `docs/UI_DESIGN.md` documents no 3D/world-space
effect (`SpellCastAura` and `StatusEffectIcons` have no entry there either);
the architectural note went in `docs/ARCHITECTURE.md` instead, beside the
`VisualAction`/queue paragraph it extends.

Parse-checked with `--check-only`. Tween timing verified against real elapsed
time via a temporary headless probe (not part of this diff, deleted).

---

## PLAN-VALIDATE — Full validation

**Model:** Opus 5 / GPT Sol

**Depends on:** CAST-1, CAST-2, CAST-3, CAST-4, CAST-5, FEEL-1, FEEL-2, FEEL-3,
FEEL-4, FEEL-5, FEEL-6, FEEL-7, FEEL-8, FEEL-9, FEEL-10, FEEL-11, FEEL-12,
FEEL-13, FEEL-14.

**Risk:** Medium. The cycle's whole value is a path that only manual play
exercises; a validation stopping at import and replay would miss exactly the
defect that opened it.

**Adds to validation coverage:** nothing new — this item consolidates and runs
the cycle's coverage.

**End state:** The plan is complete and every covered item is done.

### Work

1. Run the project's standard import, replay, and runtime checks per
   `AGENTS.md`.
2. Play a Player vs CPU battle and verify, by hand:
   - Casting `Empower` end to end **with the mouse only** — no keyboard.
   - Casting `Empower` end to end **with the keyboard only**, using Space as
     accept.
   - A ranged single-target spell and a basic attack still aim, confirm, and
     cancel through the unchanged two-step path.
   - Cancelling a confirm returns to the spell list for a self spell and to
     target select for a ranged one.
   - Right-click and `ui_cancel` behave identically in confirm.
   - The command window returns with its prior selection after a cancel.
   - `Move` → `Undo` → act, and act → move, both still complete a turn.
   - F1 toggles the developer canvas; Space does not.
3. In the same battle, verify the phase-two behaviour:
   - The threat key draws enemy reach from every phase and restores the prior
     overlay on release, including mid-aim.
   - Vertical input during target select cycles spells with the forecast and
     overlays following; horizontal input still cycles targets; the cursor
     never rests on an illegal tile.
   - Move select shows reachable and attackable tiles as two distinguishable
     sets, with the path preview still readable over both.
   - A turn beginning with the active unit already in view moves the camera not
     at all; one beginning off-screen pans without zooming or rotating; any
     camera input during a pan wins.
   - Animation speed and per-action skip both return control to the menu.
   - A unit with both phases spent reads as spent on the board.
   - A tile visually blocked by another model or by terrain can still be
     hovered and clicked, and during target select the pointer resolves to a
     legal target rather than a nearer illegal one.
   - The turn order display matches the simulator's order at every step of a
     round, including after a mid-round death.
   - Every status-window stat renders three digits and holds its horizontal
     position as values change, and no stat leaves the 0–999 range during a
     full battle including buffs, debuffs, and their expiry.
   - A model base is distinguishable from the body standing on it at gameplay
     camera distance, and the ascension stack is still countable.
   - During move and target select every model dithers except the active unit
     and the one under the pointer; hover restores solid without flicker; and
     all models are solid again on leaving the phase and at battle end.
   - An attack, a spell and a defeat each stay on screen through the bulk of
     their effect before the next queued action starts, with no watchdog
     warning during normal play.
   - Damaged units show a readable number at gameplay camera distance through
     the retro and CRT pipeline, including several at once from one spell, and
     no number outlives its unit.
4. Confirm no window is left on screen after a turn ends, after a rejected
   action, and at battle end.
5. Replay a recorded battle and diff the event history against a pre-cycle run.
   Every item in this cycle except FEEL-9 is presentation work, so the only
   admissible divergences are ones FEEL-9's Resolution already explains as stat
   clamping. Anything else is a defect, not a changed expectation.
6. Record the buff-forecast gap described under **Deliberately out of scope** in
   `BACKLOG_CRITICAL.md`, as a description of the missing behaviour with its
   file and function named — never as a plan item identifier. Record the
   unscheduled candidate under **Not scheduled** in `BACKLOG_LONGTERM.md` the
   same way, as a description carrying its open decision.
7. Grep the repository for `CAST-`, `FEEL-`, and `PLAN-VALIDATE` before closing;
   rewrite any hit outside this file as a description.
8. Mark CAST-1 through FEEL-14 done, then clear this file's contents in the same
   session per the plan file lifecycle.

**Files:** `implementation_plan.md`, `BACKLOG_CRITICAL.md`,
`BACKLOG_LONGTERM.md`.

**Resolution:** _pending_
