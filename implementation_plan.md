# Implementation Plan

Reset 2026-08-01. The previous contents — the PC, UI-1…UI-9, DATA, TYPE, POS,
FRAME, and LVL blocks plus their resolution logs — were deleted wholesale when
this plan opened, per the plan-file lifecycle rule in `AGENTS.md`. Everything
there is recoverable with `git show HEAD:implementation_plan.md`. Before this
cycle proceeds, the genuinely open work has a durable home: monster level and
growth and the remaining Level 2-4 spell pool are in `BACKLOG_CRITICAL.md`; the
in-world Resonance/critical feedback row is in `BACKLOG_LONGTERM.md`; and Purple
Dungeon Slime's description remains in the critical backlog. `Kickatoo`'s
MOVE = 8 was not open — the user settled it as intentional on 2026-08-01, so it
was not copied into a backlog.

This file now holds one plan: window scaling and the docked status-window
rework, UI-10 through UI-VALIDATE.

**Execution order is file order.** UI-10 → UI-11 → UI-12 → UI-13 → UI-14 →
UI-VALIDATE. Dependencies are stated per item; nothing depends on an item
below it.

There is no automated test suite in this repository (see
`docs/DEVELOPMENT.md`). Every behaviour below is verified manually by launching
the game, consolidated into UI-VALIDATE.

## Conventions

- **Adds to validation coverage** is the behaviour the item contributes to
  UI-VALIDATE. Items do not run the full manual pass themselves.
- **Risk** is the blast radius if the change is wrong.
- **Model** is the smallest model that can safely execute the item.

---

## Window scaling and status-window compaction (UI-10 … UI-VALIDATE)

### Problem

Three observations against a running battle on 2026-08-01:

1. **No panel scales with the window.** `project.godot` has no `[display]`
   section at all, so stretch mode is Godot's default `disabled`: the root
   viewport grows in real pixels while every window stays the size §8 measured
   it at. On a maximised 1920×1080 window the 540-wide status windows occupy
   half the screen fraction they were designed for, and the pixel font shrinks
   toward illegibility as the window grows.
2. **The status rows spend their width on whitespace.** `NoggWindow.add_row()`
   is two-column by construction — label left, value right-aligned against the
   frame's inner edge (trait 4) — so `SPD / MOV` and `3 / 3` sit roughly 250px
   apart with nothing between them. That is the right call for spell rows,
   where the value is a uniform `Rng N` column; it is the wrong call for a stat
   readout, where a label and its number are one unit.
3. **`Elements` prints a word list, not a state.** Resonance has been live
   since 2026-07-28 and is the only source of the +10/20/30% ATK/DEF bonus, but
   `_renderStatusWindow()` renders `", ".join(monster.elements)` and the charge
   is invisible. The row also spends an 8-character label (`Elements`)
   restating what the element names already say.

### Settled this session

No item below is blocking; every open question was decided in the planning
session on 2026-08-01.

- **Stretch mode is `canvas_items` + `expand`.** Rejected: `keep` (letterboxes
  to a fixed logical rect, which makes the existing `resized`-driven
  repositioning dead code) and integer scale mode (crisp, but does not step
  until roughly 2× the base size, so most window sizes look exactly like
  today).
- **Resonance cells are drawn, not typed.** `docs/UI_DESIGN.md` §3 verified
  with `Font.has_char()` that `■`/`□` are absent from all 12 pixel fonts in
  `assets/Fonts`, and Godot substitutes a system font silently rather than
  failing — a smooth vector square beside pixel text, which reviews clean and
  looks wrong on screen.
- **Layout is "B2": elements form a third column beside the stats**, using
  two-letter element codes. Rejected: full element names one per row (three
  across needs 624px against a 496px budget), and a single dedicated element
  row (fits, but leaves the freed rows unused rather than shrinking anything).

- **The stat-cell API accepts text or a custom control and returns handles.** A
  cell is `{label, value}` for ordinary text or `{label, control}` for a drawn
  value such as `ResonanceBar`; exactly one of `value` and `control` is present.
  The builder returns the created label/value nodes per cell, so tinting never
  depends on child indexes.
- **The identifier sweep includes policy examples and every historical family.**
  `AGENTS.md`'s literal examples are rewritten to non-identifier placeholders;
  the sweep recognizes numeric items and `VALIDATE` items for the P-numbered,
  PC, UI, DATA, TYPE, POS, FRAME, BM, TD, and LVL families.
- **`Dump` is the intentional no-element fixture.** Its catalog `ELEMENTS`
  array is empty. It owns no spells, so this removes no cast eligibility; it
  gives the empty-state renderer a real roster entry for acceptance.

### The measured grid

Everything below is arithmetic against numbers already recorded in
`docs/UI_DESIGN.md`, not estimates: the status window is 540 wide with
`CONTENT_INSET` 22 a side, giving **496px of content**, and the shipping font
is monospace at a **24px advance** (§3's casing note; §8's `ATTACK` = 144px
over 6 characters). Three fixed columns:

```
col px:  0             192           384      476  496
         |             |             |          |   |
         Megidos                                    |
         HP  44 / 60                 FI ■■□         |
         ATK 9         DEF 6         DA □□□         |
         SPD 4         MOV 4         ST □□□         |
                                                    <- 20px slack
```

Worst cases all clear: `DEF 100` in column 2 ends at 360 against the element
column's 384 start, `HP  999 / 999` ends at 312, and an element cell is
2 characters (48) + gap (8) + bar (36) = 92px, ending at 476.

---

## UI-10 — Scale every panel with the window

Fixed at the project level, not per panel. A per-panel pass would have to touch
`BattleUIBuilder`, `BattleSetupUI`, `PlayerCommandMenu`, `BattleGraphicsMenu`,
`NoggWindow`, and every width constant in §8, and would still silently miss the
next panel someone adds. Stretch mode makes scaling a property of the viewport
instead, which is what "every panel, consistently" actually requires.

1. Add to `project.godot`: `display/window/stretch/mode="canvas_items"` and
   `display/window/stretch/aspect="expand"`. Base size stays Godot's default
   1152×648 — the budget every width in §8 was measured against — so no
   measurement in that section changes meaning.
2. `expand`, not `keep`, is deliberate. `keep` letterboxes to a fixed 1152×648
   logical rect, which would make the `resized`-driven repositioning in
   `BattleUIBuilder` and `PlayerCommandMenu._layout_windows()` dead code that
   never fires again. `expand` keeps the logical size varying with the window's
   aspect, so that code stays live and load-bearing, and there are no bars.
3. `RetroRenderController._resize_world_viewport()` sizes the world SubViewport
   from `host.get_viewport().get_visible_rect().size` when retro is disabled.
   Under `canvas_items` that call returns the *logical* size, so the 3D would
   render at ~1152×648 and be upscaled to the window — a sharpness regression
   with retro off, which is the default. Size that branch from the real window
   (`host.get_window().size`) instead. The retro branch already uses
   `render_size` and is unaffected.
4. Do **not** touch `get_display_rect()`, `screen_to_world()`, or
   `screen_motion_scale()`. All three are ratio-based between the visible rect
   and the world viewport, and mouse events arrive in the same logical space
   `get_visible_rect()` reports, so the mapping stays internally consistent.
   Rewriting one of them in real-window pixels is what would break picking.
5. Record the stretch settings and their consequences in `docs/UI_DESIGN.md`
   §8, next to the sentence naming 1152×648 as the budget — that number is now
   a *logical* base rather than a physical window size, and the section should
   say so.

**Files:** `project.godot`, `src/presentation/RetroRenderController.gd`,
`docs/UI_DESIGN.md`, `BACKLOG_LONGTERM.md`.

**Adds to validation coverage:** every panel on every canvas scales with the
window; board picking still resolves to the correct tile at a non-default
window size; the 3D stays at native sharpness with retro off; the pixel font
and the CRT scanlines remain acceptable at a fractional scale.

**Risk:** Medium. The diff is four lines, but stretch mode is global: it
changes the coordinate space that every mouse event, every
`get_viewport_rect()` call, and the CRT shader all live in. Reverting is
trivial — two project settings and one branch — but a subtly wrong picking
offset reads as a misclick rather than as a bug and can survive a casual look.

**Model:** Opus 5 / GPT Sol. Not for the size of the edit, which is trivial,
but because the failure modes are cross-cutting and none of them throw:
picking drifts, the 3D softens, the font smears. Judging "does this read as
retro or as broken" across several window sizes is the actual work.

**Resolution (2026-08-01):** Implemented; pending end-of-plan validation.
Configured `canvas_items` + `expand`, kept the non-retro world SubViewport at
the real window resolution, documented the logical coordinate contract, and
updated the high-resolution frame-scale backlog note to await the consolidated
visual decision. The headless editor parse/load smoke check passed; window
scaling, picking, fractional pixel-font quality, scanlines, and 3D sharpness
remain for UI-VALIDATE's in-window pass.

---

## UI-11 — Two-letter element codes in the catalog

The status window's element column (UI-13) is too narrow for element names —
`DARKNESS` alone is 192px of a 92px cell — so each element needs a two-letter
code. That mapping is authored content, not presentation logic: it belongs in
`data/elements.json` beside the element it names, where changing `TH` to `TN`
is a data edit rather than a code edit.

The catalog already exists and is already loaded atomically.
`data/elements.json` holds eleven bare `{"NAME": "fire"}`-shaped entries,
including the `none` sentinel, and
`src/factories/ElementReferences.gd` validates them, so this item is a field
addition, not new machinery.

1. Add `"CODE"` to every entry in `data/elements.json`: `FI` fire, `IC` ice,
   `WA` water, `WI` wind, `EA` earth, `WO` wood, `TH` thunder, `DA` darkness,
   `LI` light, `ST` steel, `NO` none. All eleven are unique, so no invented
   spellings are needed.
2. Validate `CODE` in `ElementReferences.reloadCatalog()` with the same
   strictness `NAME` already gets: present, exactly two characters, and unique
   across the catalog, rejecting the whole load otherwise. Uniqueness is the
   one that matters — two elements sharing a code makes them indistinguishable
   in the status window, which is a content bug that must fail loudly at load
   rather than render ambiguously.
3. Normalize to uppercase on load, the mirror of what `NAME` already does with
   `to_lower()`, so an author writing `"fi"` is not a second failure mode.
4. Expose it the way `STANDARD` is exposed: a static `CODES` dictionary built
   during the same pass, plus a `code(element)` accessor. On an unknown
   element, `push_warning` and return `"??"` — a visible placeholder, never a
   guessed abbreviation, because a silently plausible wrong code is worse than
   an obviously missing one.
5. Document the field in `docs/REFERENCE_CATALOGS.md` alongside the other
   authored catalogs, including the two-character and uniqueness rules.
6. **Colour is deliberately left behind.** `BattleMeshFactory.elementColor()`
   still hardcodes the per-element palette, so an element added to the catalog
   now gets a code from data but falls back to grey until that map is edited
   too. Moving colour into the catalog is the obvious follow-on and is out of
   scope here — it feeds 3D material construction in `GodotVisualAdapter`, a
   different blast radius from a UI label. Record it in `BACKLOG_LONGTERM.md`.

**Files:** `data/elements.json`, `src/factories/ElementReferences.gd`,
`docs/REFERENCE_CATALOGS.md`, `BACKLOG_LONGTERM.md`.

**Blocks:** UI-13, which reads the codes.

**Adds to validation coverage:** the catalog loads with codes present; a
deliberately duplicated or malformed code is rejected at load with a warning
rather than accepted.

**Risk:** Low. Additive field on a catalog that already validates atomically —
a bad edit fails the whole load loudly at startup, which is the existing
contract, not a new failure mode.

**Model:** Sonnet 5 / GPT Terra. One data file and one loader, with the
validation shape already established by the `NAME` handling directly above it.

**Resolution (2026-08-01):** Implemented; pending end-of-plan validation.
Added all eleven codes, including `NO` for the sentinel, and kept reload atomic
across names and codes. The catalog documentation and colour-migration backlog
now describe the split. The focused headless catalog smoke check passed;
malformed and duplicate-code rejection remains covered by UI-VALIDATE.

---

## UI-12 — Compact the docked status rows

The two-column row (trait 4) stays the rule for lists. The status windows are
not lists — they are a readout of labelled scalars, and pushing each value to
the frame's far edge separates it from the label naming it. Pair them instead,
and spend the reclaimed width on a second stat per row and, in UI-13, on an
element column.

1. Add a cell-based row builder to `NoggWindow` — `add_stat_row(cells)` — beside
   `add_row()`, not replacing it. Each cell is either `{label: String, value:
   String}` or `{label: String, control: Control}`; reject a cell that supplies
   both or neither. Return one handle dictionary per cell containing the cell
   root, its label `Label`, and its value `Control` (the generated value `Label`
   for text, or the supplied custom control). Every spell and command row keeps
   `add_row()` untouched, so §8's two-column measured widths continue to
   describe them exactly.
2. Cells start at **fixed pixel offsets**, not from a flex container: 0, 192,
   and 384, per the measured grid above. Fixed offsets keep `ATK`/`SPD` and
   `DEF`/`MOV` in vertical columns across the two rows, which a flow layout
   would break the moment a value went from one digit to three. Column 3 is
   unused by this item and is UI-13's.
3. The offsets belong in `NoggTheme` beside the other window geometry, not as
   literals in the row builder — same rule that owns `CONTENT_INSET` and
   `CURSOR_GUTTER_WIDTH` there.
4. Label keeps `TEXT_PRIMARY`; a generated text value keeps `TEXT_ACCENT`, with
   one space between them. Two Labels per text cell, not one concatenated
   string — preserving the colour split is the whole reason not to just pass
   `"ATK 5"` to `add_row()`. A supplied custom control owns its drawing colours
   and is positioned in the same value slot after the label.
5. `_tint_row_value()` in `BattlePresentationController` reaches into
   `row.get_children()[1]` to gold the HP value below one third of max. That
   index is the value Label of a *two-column* row and does not survive this
   change. Rename it to `_tint_value_label(value_label, colour)` and pass the HP
   cell handle's value `Label` directly. Do not re-derive an index into a
   structure that now varies by cell count.
6. Keep `STATUS_WINDOW_WIDTH` at 540 and `STATUS_WINDOW_CAPACITY` at 6. The
   width is set by the name heading, not by the stat rows — `Blue Crowned
   Pidgeon` is 20 characters and already fills the grid — and the two windows
   plus their margins already consume 1120 of the 1152 base width, so there is
   nowhere to widen into. Capacity 6 leaves two spare rows after UI-13; that
   headroom is deliberate, and dropping it to 5 or 4 later is a one-constant
   change.
7. Update `docs/UI_DESIGN.md` §8's actor/target rows to describe the new row
   set, and add the cell-row exception to §4's trait-4 note so the next reader
   does not "fix" it back to right-aligned.

**Files:** `src/presentation/theme/NoggWindow.gd`,
`src/presentation/theme/NoggTheme.gd`,
`src/systems/BattlePresentationController.gd`, `docs/UI_DESIGN.md`.

**Adds to validation coverage:** `HP`, `ATK`/`DEF`, `SPD`/`MOV` render as
label-value pairs in two vertical columns; the low-HP gold tint still fires;
a 20-character monster name still fits its heading; spell and command rows are
visually unchanged.

**Risk:** Low. Additive API, and the only existing behaviour touched is the HP
tint — which fails visibly on the first damaged monster selected, not silently.

**Model:** Sonnet 5 / GPT Terra. The layout is measured and fully specified
above; what remains is wiring it, with the one known trap called out in item 5.

---

## UI-13 — Resonance bars as a third column

`Elements  fire` tells the player something the monster's spell list already
implies. What is invisible is charge, which drives the only always-on stat
bonus in the game. Replace the row with an element column beside the stats —
one element per row, top-aligned from the HP row down:

```
| Ashen Wyrm           |
| HP  44 / 60   FI ■■□ |
| ATK 9  DEF 6  DA □□□ |
| SPD 4  MOV 4  ST □□□ |
|                      |
|                      |
```

**Depends on:** UI-11 for the codes and UI-12 for the column offset. Both edit
`_renderStatusWindow()`.

1. New `src/presentation/theme/ResonanceBar.gd`, built exactly like
   `PagerArrow.gd`: a small `Control` drawing three cells in `_draw()`. Charged
   cells fill, empty cells draw as an outline. Not typed glyphs — see "Settled
   this session" above for why.
2. Cell size and gap are tokens in `NoggTheme` beside the cursor metrics, not
   literals in `ResonanceBar`, for the same reason `CURSOR_WIDTH` lives there:
   the bar and the column offset in UI-12 item 3 have to agree, and they cannot
   agree if each owns its own copy. Size them against the 24px row height so a
   bar reads as one line of text — roughly 10px cells with 3px gaps, 36px
   total, which is what the 92px element cell in the measured grid assumes.
3. Charged cells fill with `BattleMeshFactory.elementColor(element)`; empty
   cells outline in `TEXT_DIM`.
4. The two-letter label comes from `ElementReferences.code(element)` — never a
   literal table in the UI, and never a `substr(0, 2)` derived on the fly. The
   catalog is the mapping; UI-11 exists to make it editable without touching
   this file.
5. Charge comes from `monster.get_resonance(element)`, which already clamps to
   0-3. Iterate `monster.elements` for order, never `resonance_bars.keys()` —
   the dictionary's order is insertion order and the array is the authored one.
6. `Dump` is the no-element acceptance fixture: its `ELEMENTS` array is empty,
   and it gets no bars and no placeholder. It owns no spells, so the catalog
   change removes no cast eligibility. Document explicitly in
   `docs/MONSTER_CATALOG_SCHEMA.md` that `ELEMENTS` is required but may be an
   empty array; every present value must still be a supported non-`none`
   element.
7. The column holds **three** elements: rows 2, 3, and 4. The shipping catalog
   is now one no-element, 15 one-element, and 12 two-element monsters, with no
   three-element entry, so three is headroom, not a fit problem. A fourth
   element has nowhere to go — the only free row is the name row, and putting a
   cell there would truncate names like `Blue Crowned Pidgeon`. Render the first
   three and `push_warning` on the fourth, so a catalog change announces itself
   instead of silently dropping an element.
8. `docs/GAME_DESIGN.md`'s mechanic table still lists Resonance UI as "designed,
   not yet live". Update that row to describe what this item ships. The separate
   in-world Resonance/critical feedback work is already preserved in
   `BACKLOG_LONGTERM.md`; do not implement or remove it in this item.

**Files:** `src/presentation/theme/ResonanceBar.gd` (new),
`src/presentation/theme/NoggTheme.gd`,
`src/systems/BattlePresentationController.gd`, `docs/UI_DESIGN.md` §8,
`data/monsters.json`, `docs/GAME_DESIGN.md`, `docs/MONSTER_CATALOG_SCHEMA.md`.

**Adds to validation coverage:** the bar tracks a Resonance ladder 0→1→2→3 and
back to 0; a two-element monster renders two bars without the window growing;
`Dump` renders no element cells; bar colour matches the element, the code
matches the catalog, and no system font appears in the window.

**Risk:** Low. Presentation is additive. `Dump`'s serialized element array
changes from `["ice"]` to empty, but it owns no spells, and race — not this array
— owns damage resistance/weakness, so no current battle outcome should change.

**Model:** Sonnet 5 / GPT Terra. `PagerArrow.gd` is a working precedent for the
drawing, `elementColor()` for the palette, `ElementReferences.code()` for the
labels, and `get_resonance()` for the data — every design decision is made
above.

---

## UI-14 — Purge plan identifiers from source comments

`AGENTS.md` forbids any persistent file from citing an `implementation_plan.md`
item, because the plan file is transitory and its identifiers die with the
cycle that created them. Roughly **124 GDScript hit lines across 26 files**
remain, plus four lines in `AGENTS.md` whose policy examples accidentally use
the very identifier shapes the policy forbids.

Runs **last** so it also sweeps any identifiers UI-10 through UI-13 introduce,
and so it does not fight those items over the same comment blocks in
`NoggWindow.gd`, `NoggTheme.gd`, and `BattlePresentationController.gd`.

1. Re-derive both hit lists with the workspace's installed `rg`; do not use
   Unix `grep`, which is unavailable in this Windows environment:

   ```powershell
   $identifierPattern = '\b(?:P[0-9]+|PC|UI|DATA|TYPE|POS|FRAME|BM|TD|LVL)-(?:[0-9]+[a-z]?|VALIDATE)\b'
   rg --no-ignore -n --glob '*.gd' $identifierPattern src debug scripts
   rg --no-ignore -n --glob '*.md' --glob '!implementation_plan.md' $identifierPattern .
   ```

   The pattern deliberately includes the previously omitted monster-level
   family and named validation items, as well as every older numeric family.
2. **The usual GDScript fix is deletion, not rewriting.** Most hits sit directly
   beside a durable section reference, where the design document already
   carries the meaning and the identifier adds nothing. Drop the identifier and
   keep the section.
3. Where no durable section reference exists, describe the actual dependency or
   behaviour instead of narrating which transitory item introduced it.
4. `src/` is 17 hits across 7 files: `theme/NoggTheme.gd`, `theme/NoggWindow.gd`,
   `theme/PagerArrow.gd`, `PlayerCommandMenu.gd`, `BattleUIBuilder.gd`,
   `BattleGraphicsMenu.gd`, `systems/BattlePresentationController.gd`. These
   matter most — production code outlives every plan cycle by definition.
5. `debug/` is the remaining ~107 hit lines across 19 harness scripts,
   concentrated in `drive_battle.gd`, `verify_pos_validate.gd`, and
   `verify_frame_pacing.gd`. Apply the same comments-only treatment.
6. Rewrite `AGENTS.md`'s literal examples using neutral placeholders such as
   `<cycle-item>` and descriptions of the work. Preserve the policy's meaning;
   only the self-defeating example strings change.
7. **GDScript comments only. No behaviour change.** The backlog and policy prose
   are intentionally outside this assertion. Verify only the GDScript paths
   with PowerShell:

   ```powershell
   $nonCommentChanges = @(
     git diff -U0 -- src debug scripts |
       Where-Object {
         $_ -match '^[+-]' -and
         $_ -notmatch '^(\+\+\+|---)' -and
         $_ -notmatch '^[+-]\s*#'
       }
   )
   if ($nonCommentChanges.Count -gt 0) {
     $nonCommentChanges
     throw 'Identifier cleanup changed a non-comment GDScript line.'
   }
   ```

8. After editing, run the zero-hit assertion used again in final validation:

   ```powershell
   $identifierPattern = '\b(?:P[0-9]+|PC|UI|DATA|TYPE|POS|FRAME|BM|TD|LVL)-(?:[0-9]+[a-z]?|VALIDATE)\b'
   $identifierHits = @()
   $identifierHits += @(rg --no-ignore -n --glob '*.gd' $identifierPattern src debug scripts 2>$null)
   if ($LASTEXITCODE -gt 1) { throw 'rg failed while scanning GDScript.' }
   $identifierHits += @(rg --no-ignore -n --glob '*.md' --glob '!implementation_plan.md' $identifierPattern . 2>$null)
   if ($LASTEXITCODE -gt 1) { throw 'rg failed while scanning Markdown.' }
   if ($identifierHits.Count -gt 0) {
     $identifierHits
     throw 'Persistent plan identifiers remain.'
   }
   ```

9. **Filenames are out of scope.** Fourteen harness scripts are named after old
   plan items. Renaming them to describe behaviour is the consistent end state,
   but it churns paths and commands and is a separate user decision. Record the
   filename cleanup in `BACKLOG_LONGTERM.md` and leave the files named as they
   are.

**Files:** ~26 `.gd` files under `src/` and `debug/`, comments only;
`AGENTS.md`; `BACKLOG_LONGTERM.md`.

**Adds to validation coverage:** none — this item changes no behaviour. Its
integrity gates are the GDScript diff assertion in item 7 and the repository
identifier assertion in item 8.

**Risk:** Low, but wide: 27 persistent source/policy files plus one backlog
entry. The only behavioural risk is clipping a GDScript code line along with a
comment, which item 7 catches before commit.

**Model:** Sonnet 5 / GPT Terra. High file count, entirely mechanical, and the
end state is stated exactly — the tier's description of multi-file work with a
stated end state.

---

## UI-VALIDATE — Validate window scaling and the status rework

Run one consolidated pass after UI-10 through UI-14 are committed. This is the
only item that launches the game for acceptance.

**Depends on:** UI-10, UI-11, UI-12, UI-13, UI-14.

**Verify:** Start from a clean `git status`. Launch the game, then:

- **Every panel scales.** Drag the window from small to maximised and confirm
  the game windows, the dev top bar, the graphics menu, the battle log, and the
  setup screen all scale together. A panel that stayed put is a panel outside
  the canvas, and is the failure this plan exists to prevent.
- **Picking still lands.** At a non-default window size, click a monster near
  each of the four corners of the board and confirm the correct unit selects.
  This is the single most likely thing UI-10 breaks and the least obvious — an
  offset picks a neighbouring tile.
- **The 3D stays sharp with retro off** at a maximised window (UI-10 item 3),
  and the CRT scanlines at maximum strength read as scanlines rather than as
  banding.
- **The pixel font at a fractional scale.** 1920/1152 is 1.67; with the
  project's nearest texture filter the glyph strokes thicken unevenly. Judge it
  at a maximised window *and* at an awkward intermediate size. If it reads as
  broken rather than retro, the fallback is
  `display/window/stretch/scale_mode="integer"`, which is crisp but only steps
  at 2×; record the decision either way.
- **Stat rows.** Select a monster and confirm `HP`, `ATK`/`DEF`, `SPD`/`MOV`
  are label-value pairs with the four stat labels in two clean vertical
  columns. Damage one below a third of max HP and confirm the HP value still
  golds (UI-12 item 5). Select a monster with a 20-character name and confirm
  the heading fits.
- **Element column.** Deploy `Walker of the Woods`, the only monster with a
  complete Level 1-4 ladder and therefore the only one that can reach charge 3.
  Cast `Gather` → `Thornlash` → `Bramble Crown`, confirming the bar tracks
  0→1→2→3, then `Roses at Summers End` and confirm it depletes to 0. Confirm
  the second element's bar sits on the next row down and the window does not
  grow. Select a one-element monster, then select `Dump` and confirm it shows
  no element cell or placeholder and that the spare rows remain empty.
- **Codes come from data.** Edit one `CODE` in `data/elements.json`, relaunch,
  and confirm the status window shows the edited value — the point of UI-11.
  Revert the edit. Separately, duplicate a code and confirm the catalog is
  rejected at load with a warning.
- **Nothing else moved.** Open the spell window and confirm its rows are still
  two-column with `Rng N` right-aligned, that paging still works, and that the
  focused-row marquee still runs.
- **No plan identifiers survive.** Re-run UI-14 item 8's PowerShell/`rg`
  assertion. It scans `src/`, `debug/`, `scripts/`, and every `.md` outside
  this file and must return zero hits.
- Finish with `git diff --check`.

**Expected value change:** `Dump.elements` changes from `["ice"]` to `[]`, and
that array is serialized in battle state. No current battle outcome should
change because `Dump` owns no spells and race owns elemental damage matchups,
but a snapshot or hash containing `Dump` may legitimately change. Record the
new expected value if that is the only delta; do not restore the old element to
preserve an obsolete hash. All other changes are presentation, catalog labels,
comments, project settings, and docs.

**Risk:** Medium, concentrated entirely in UI-10. A picking offset or a
softened 3D render is invisible in a diff and only shows up here.

**Model:** Opus 5 / GPT Sol. The pass is mostly judgement calls about how the
scaled UI reads — font smear, scanline weight, density of the new three-column
row — which is the tier's stated boundary.

---
