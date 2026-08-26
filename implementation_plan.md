# Second Window Skin

**Opened 2026-08-25.** This file was cleared earlier the same day, after the
Battle Legibility Cycle validated and closed; that cycle's items and Resolution
notes are recoverable with `git show 99ceec7:implementation_plan.md`, and the two
pieces it left open are in `BACKLOG_CRITICAL.md` (health readable for at most two
units out of eight; a spell blocked by anything except a cooldown reading
`CD 0`). Nothing from it is carried forward here.

This cycle exists because of a look review conducted 2026-08-25 against
`assets/ui/references/brigandine2.png` — Brigandine: The Legend of Forsena, PS1.
The finding that drives it, in the user's words: dissatisfaction with **the
border of the UI boxes** and **the size of the text**. The request is not to
retune the current look but to add a **second, switchable one** matching the
reference: borders and inner fill sharing one edge, the text-to-edge distance
matched to the reference, a more transparent fill, **Nogg Herald as the face for
every battle UI element**, and the skin reaching everything except the developer
console.

## Outcome

The battle HUD renders in one of two named skins, chosen at runtime and
persisted with the other presentation options:

- **Nogg** — the current look, unchanged in every particular: Nogg Terminal at
  12 units, rounded corners, a translucent-black halo leaking beyond the frame,
  a violet-cast rim, an 0.86-alpha body. Nothing about it moves; it is the
  baseline the second skin is judged against and validation asserts it by hash.
- **Brigandine Plate** — the reference look: **Nogg Herald throughout**, square
  corners, no halo at all, a hairline neutral border whose inner edge is exactly
  where the fill begins, a fill around 0.6 alpha, and the reference's own
  text-to-edge distance. It covers every player-facing surface, including the
  turn rail tiles, the action row, and the status badges.

Switching is a dropdown in the developer graphics menu beside the render preset,
takes effect live without restarting the battle, and survives a restart.

## What the reference actually measures

Sampled from `assets/ui/references/brigandine2.png` by
`debug/sample_reference_ui.gd` (gitignored), not estimated. The image is 320x240,
so **one source pixel is 1.50 design units** — a design-unit screen is ~360 tall
at every `ui_scale`, and it is the ratio that transfers, not the pixel count.

| Property | Reference | `nogg` today |
|---|---|---|
| Dialogue panel | 236 x 48 px = **354 x 72 design units** | `PROMPT_WIDTH` 470 x 25 units for one row |
| Border thickness | 1 px = **1.50 units** | `FRAME_RING_UNITS` 1.0 |
| Border colour | **(0.937, 0.937, 0.937)** — neutral | `FRAME_ACTIVE` (0.902, 0.878, 1.0) — violet cast |
| Row immediately inside the border | fill, no second line | fill, no second line |
| Fill | terrain clearly readable through it; sampled spread 0.325 | `WINDOW_FILL` alpha 0.86 |
| Text inset, left / right / top / bottom | 7 / 8 / 9 / 7 px = **10.5 / 12.0 / 13.5 / 10.5 units** | `CONTENT_INSET_UNITS` 6.0 |

**Two of these overturn the working assumption and must not be "corrected" back.**

- **The reference is airier than we are, not tighter.** Its text sits 10.5 to
  13.5 design units from the border; ours sits at 6. Its two text rows occupy 72
  units of panel, a 36-unit row pitch against our 13. An earlier reading of this
  review — that the boxes are too big for their text — is wrong in the padding
  direction, and the plan does not act on it. `CONTENT_INSET` goes **up** under
  this skin.
- **The border is thicker and neutral, not thinner.** 1.5 units against our 1.0,
  and grey rather than violet-cast.

What is genuinely smaller is the **face**, which is why answer 1 below is the
load-bearing decision of the cycle rather than a detail of it.

## Present-state facts an executing agent must not "fix"

- **Nogg Herald can carry the HUD, and the two things that would have stopped it
  are already handled.** Coverage is 95 glyphs, byte-identical in codepoint set
  to Nogg Terminal — the whole of ASCII 0x20 to 0x7E, so no HUD string can hit a
  missing glyph. And `NoggHeraldFont.TABULAR_DIGIT_ADVANCE` is 7 with every digit
  drawn 6 wide, so a changing number holds its column. The `%03d` stat padding
  and the fixed status cells survive the swap for that reason and only that
  reason; do not remove the padding on the theory that a proportional face makes
  it pointless.
- **Herald is pixel-exact only at `NOMINAL_SIZE` 13.** It is a bitmap face with a
  baked atlas. A body size that is not 13, or a whole multiple of it, resamples a
  pixel font — which `docs/UI_DESIGN.md` §3 spends a section forbidding. **The
  Herald skin's body size is therefore 13 units, one unit *larger* than
  Terminal's 12.** The text will not get shorter; it gets narrower, because
  Herald is proportional with a 7-unit digit advance, a 1-unit letter gap, and a
  negative kerning table, against Terminal's flat 8-unit monospace advance. If
  the result still reads as too large, the lever is the skin's row pitch and
  window widths, not the font size.
- **Every window width in `NoggTheme` is measured output.** `COMMAND_WIDTH`,
  `SPELL_WIDTH`, `PROMPT_WIDTH`, `FORECAST_WIDTH`, `STATUS_WINDOW_WIDTH`,
  `TURN_ORDER_WIDTH`, `PAGER_WIDTH`, `DEEP_CARD_WIDTH` and
  `STATUS_CELL_OFFSET_UNITS` were each measured against real worst-case strings
  at `ui_scale = 1`, against Terminal's advance and a 6-unit inset. Changing the
  face **and** the inset invalidates all nine. SKIN-6 exists for this.
- **`CONTENT_INSET` is load-bearing beyond padding.** `NoggWindow.row_rect()`
  positions the `MenuCursor` from it, `add_row()` computes each row's label clip
  width from it, and `window_height()` counts it twice.
- **The halo is deliberately outside the layout.** A `Panel` with negative
  offsets and `MOUSE_FILTER_IGNORE` that never contributes to sizing. A skin
  without it must drop the *node*, not merely make it transparent.
- **The developer HUD is out of scope.** `docs/UI_DESIGN.md` §9 keeps the game
  window language distinct from the debug HUD deliberately. The dev bar, the
  graphics menu, and the battle log keep Roboto and their own styling under both
  skins — this is the one exclusion the user named.

## Items

### SKIN-1 — Settle the skin contract in the design document

**Model:** Opus 5 / GPT Sol

**Model rationale:** The output is a written contract eight later items execute
against, and it converts an image into numbers that must survive four `ui_scale`
values. Ambiguity peaks here and boundary impact is total — every later item
cites this section — so the judgement is made once, centrally, rather than
re-litigated per item.

**Depends on:** nothing.

**End state:** `docs/UI_DESIGN.md` §4 gains a "Skins" subsection naming both
skins, stating which tokens vary and which are shared, and giving Brigandine
Plate's target values in design units and alpha, each attributed to a
measurement. §3 gains the rule that a skin's body size must be a whole multiple
of its face's nominal size. The reference image and the sampler are recorded as
the source. No code changes.

**Implementation:** The table above is the starting point, not the finished
contract. Two numbers it does not yet carry:

- **The fill's alpha, derived rather than guessed.** Extend
  `debug/sample_reference_ui.gd` to pair each covered terrain pixel with the
  same terrain uncovered just outside the panel and solve `covered =
  terrain * (1 - a)` for `a`. The sampled spread of 0.325 proves the terrain
  survives the fill; it does not yet say by how much.
- **Which edge the border and fill share.** The sample shows fill immediately
  inside the border with no second line, but `StyleBoxFlat` draws its border
  *inside* the panel rect, so our fill already extends under the border. Record
  whether the reference aligns outer or inner edges, because at radius 0 the two
  readings differ by exactly the border thickness.

**Risk:** The reference is a different game at a different vertical resolution,
and some of what reads as "the look" is its output hardware. A scanline-softened
border sampled naively encodes an artefact as a contract. Sample the crispest
region and say in the document where each number came from.

**Adds to final validation:** The shipped skin matches the values this section
records, checked against a capture.

**Resolution (2026-08-25):** Implemented; pending end-of-plan validation.

`docs/UI_DESIGN.md` §4 gains "4a. Skins" with the two skins' token table, and §3
gains the rule that a skin's body size must be a whole multiple of its face's
nominal size — the constraint that fixes Herald at 13 units and makes "smaller
text" a row-pitch and width question rather than a font-size one.

**The alpha method was replaced, and the failure is recorded in the document
because it is not obvious from the method's shape.** Regressing covered pixels
against uncovered ones paired across the border reads as the rigorous approach.
It is not: pairs far enough apart to span the border stop seeing the same
terrain, and pairs close enough to see the same terrain have no variance left to
fit a slope against. Fitted at r = 0.41 with a wide gap; tightening the gap made
it *worse*, at r = 0.27. There is no gap that satisfies both. What replaced it
compares the *range* of brightness under the panel with the range just outside —
the constant term cancels out of a difference, so nothing has to correspond to
anything. It reports alpha 0.363 / 0.506 / 0.724 per channel, and the document
records 0.55 as a starting value with an explicit 0.45–0.65 tuning band, plus
the direction of the method's bias so whoever tunes it knows which way to move.

**One measurement changed the design rather than filling in a blank.** The
reference gives each text row 21 pixels for a 10-pixel glyph cell — a pitch of
2.10 cells against our 1.08. Adopting that is arithmetically impossible: with
the reference's own inset, a 360-unit design screen, the deep card at
`DEEP_CARD_TOP` and the status windows at the bottom margin, the card's 12-row
capacity binds the pitch to **at most ~14 units**, which on Herald's 13-unit
cell is a pitch/cell of 1.08 — exactly what we already have. The reference
contains no list; its dialogue panel carries two lines. So the skin adopts the
reference's **inset**, which nearly doubles from 6 units to 11, and leaves the
pitch where the geometry allows. At our row counts the inset is where the
reference's air actually comes from.

Two findings that make later items smaller than the plan assumed. The reference's
border and fill already share an edge the way our construction does —
`StyleBoxFlat` draws its border inside the panel rect and its background across
the whole rect, so with an opaque border the two readings are
indistinguishable, and only the radius and the colours need to change. And the
four-sided inset asymmetry (10.5 / 12.0 / 13.5 / 10.5) is deliberately not
adopted: `CONTENT_INSET` is read by `row_rect()`, `add_row()` and twice by
`window_height()`, and splitting it would touch all three for at most two units
of difference.

Probe: `debug/sample_reference_ui.gd` runs clean and prints `SAMPLE COMPLETE`.
No engine code changed in this item.

### SKIN-2 — Introduce the skin mechanism, with no visual change

**Model:** Opus 5 / GPT Sol

**Model rationale:** A `const`-to-table migration across the file every
presentation file reads its geometry from, and the boundary it draws — which
tokens may vary per skin — decides whether the remaining items are simple or
impossible. Extraction plus architectural boundary.

**Depends on:** SKIN-1.

**End state:** `NoggTheme` carries a skin id and `set_skin(name)` that re-runs
`_recompute()`. Skin-varying tokens move from `const` to a new
`WindowSkinCatalog`, mirroring `RenderPresetCatalog`'s id/label/description
shape. The `nogg` skin reproduces today's numbers exactly and **the HUD is
pixel-identical to before this item at every `ui_scale`.** Nothing switches yet.

**Implementation:** The dividing line is the thing to get right. Varying per
skin: the game font path and `FONT_SIZE_BODY_UNITS`, `ROW_HEIGHT_UNITS`,
`WINDOW_CORNER_RADIUS_UNITS`, the four halo tokens plus `HALO_FILL` and
`HALO_SHADOW`, `WINDOW_FILL`, `FRAME_RING_UNITS`,
`FRAME_ACTIVE`/`FRAME_INACTIVE`, `CONTENT_INSET_UNITS`,
`STATUS_CELL_OFFSET_UNITS`, and every window width. Shared: canvas layer
numbers, text colour roles, tween durations, and marquee timings, none of which
the reference speaks to.

Prove the no-change claim rather than asserting it: capture before and after at
`ui_scale` 2 and 3 and compare by file hash, the way the threat-map extraction
proved itself with a byte-identical transcript.

**Risk:** Promoting a `const` to a `static var` is a silent behaviour change for
any caller using it where a compile-time constant is required — a match arm, an
array size, a default argument. Enumerate every reader before promoting.
Secondly, `_recompute()` already has order dependencies between already-rounded
values (`RESONANCE_BAR_WIDTH` documents one); inserting lookups above them can
reorder that silently.

**Adds to final validation:** Both skins at `ui_scale` 1 through 4 with no
fractional-pixel border or half-unit inset; `nogg` identical to its pre-cycle
capture.

**Resolution (2026-08-25):** Implemented; pending end-of-plan validation.

`WindowSkinCatalog` carries both skins' look tokens behind
`RenderPresetCatalog`'s id/label/description shape. `NoggTheme.set_skin()` sits
beside `configure()` and is shaped like it, because they are the same kind of
value: a global presentation choice every derived token is a function of, which
therefore has to be the only way that choice moves. `_apply_skin_tokens()` runs
first inside `_recompute()`, since several scaled values already depend on each
other in an order that matters.

**The item's stated proof does not work, and the substitute is stronger.** The
plan proposed capturing the HUD before and after and comparing file hashes. The
capture harness is not frame-deterministic: the menu cursor bobs on a continuous
timer and effects animate, so **two runs of identical code produced 24 differing
PNGs out of 24** — measured, not assumed, by running it twice against an
unchanged tree. Any before/after pixel comparison would have "failed" no matter
what the code did.

`debug/dump_theme_tokens.gd` compares what actually determines the look instead:
every scaled token, at every `ui_scale`, for both skins. Every visual property
of a window is a function of those numbers, so identical tokens mean an
identical look by construction, where a pixel diff could only ever sample.
Against a `git worktree` at the pre-item commit, **280 token values are
identical across all four `ui_scale` values.**

**The promotion risk the item named was real and the parser caught it.**
`CURSOR_INSET_UNITS` was a `const` defined as `FRAME_RING_UNITS + 2.0`, which
stops being a constant expression the moment the ring becomes a skin token. It
is now assigned alongside the ring — and following the ring is the correct
behaviour rather than a workaround, because its own comment states the
requirement: a cursor that clears a 1.0-unit ring sits *on* a 1.5-unit one. It
was the only such case; every other reader of a promoted token reads it at call
or draw time.

One shape decision worth recording: a skin with no halo returns `null` from
`build_window_halo()` and `NoggWindow` simply has no halo child, rather than
building a transparent one. The halo is the one chrome layer that deliberately
sits outside the layout, and keeping an invisible copy would mean both skins
carrying a node whose entire purpose is to be seen, in a draw order that then
has to be maintained across every restyle.

Probe: `--check-only` reports no parse errors on the theme, the window, the
controller, the UI builder or the rail; the token dump runs clean and prints
`DUMP COMPLETE`.

### SKIN-3 — Make a live skin switch possible

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Single-file mechanical work against an end state SKIN-2 has
already fixed — `NoggWindow` builds its chrome once in `_ready()` and needs to
rebuild on demand. No design judgement, no cross-layer boundary.

**Depends on:** SKIN-2.

**End state:** `NoggWindow.restyle()` rebuilds halo, body, and rim from the
current skin, preserving row content, page position, focus state, cursor row,
and visibility. `BattlePresentationController` restyles every live window and
reassigns freshly built themes to the game and prompt canvas roots on a skin
change, so switching mid-battle is immediate and needs no reload.

**Implementation:** The halo is a node under one skin and absent under the
other, so `restyle()` adds or frees it rather than only re-styling it, and the
draw order — halo, body, content, rim — must be re-established afterwards, since
`add_child` appends. `Content` and the rows are not rebuilt: the labels carry
their own colour overrides, and rebuilding would drop marquee state and the deep
card's page.

The face and its size change with the skin, so the `Theme` on each canvas root
is rebuilt too. The roots: the game canvas, the prompt layer that
`BattleUIBuilder` parents separately, and **not** the dev canvas.

**Risk:** A restyle during an open or close tween. `NoggWindow` already carries a
`_visibility_generation` guard for a close overtaken by an open; freeing and
rebuilding panels mid-tween can leave a tween targeting a freed node. Kill or
re-target the active tweens; `is_instance_valid` alone does not cover it.

**Adds to final validation:** Switching during MENU, MOVE_SELECT, TARGET_SELECT,
CONFIRM_ACTION, an open spell list, a page turn, an open deep card, and CPU
playback; the cursor still landing on the right row afterwards.

**Resolution (2026-08-25):** Implemented; pending end-of-plan validation.

**This item was materially larger than "single-file," and that is worth stating
plainly rather than leaving the model rationale looking wrong in hindsight.**
`NoggWindow.restyle()` is the mechanical core the rationale describes, but a
live switch has to reach every window's *owner*, because width is the caller's
responsibility (trait 6's own rule) and a restyled window does not resize
itself. The actual edit touched `NoggWindow`, `MenuCursor` (a new
`reposition_gutter()` — the class's own contract already forbids moving
`position.x` after `_ready()` without restarting the bob), `PlayerCommandMenu`,
`DeepCard`, `BattleUIBuilder`/`BattleUIRefs`, and a new orchestrating
`BattlePresentationController.set_window_skin()`. No new design boundary was
drawn anywhere in that sweep, though — every decision follows mechanically from
what SKIN-2 already fixed, which is what actually justifies the tier.

**`_ready()`'s own comment on `configure_for_window_height()` describes this
exact hazard for `ui_scale` and defers it as separate, harder work — worth
reading before assuming this item was simpler than that one.** It names the
same failure mode this item had to solve: a `Theme`'s font and styleboxes are
copied in at build time while code reading a token directly sees the change
immediately, and the gap between those two is worse than not switching at all.
That comment's answer for `ui_scale` was "not now." This item's answer for a
skin switch had to be "now," because switching is the feature — so
`set_window_skin()` is the rebuild-and-relayout sweep that comment named as the
missing piece, scoped strictly to skin tokens. `ui_scale` itself remains
untouched and deferred, exactly as before.

**The risk as written assumed `set_active()` has callers; it does not, anywhere
in this codebase.** `_active_tween` — the one tween that actually targets a
node `restyle()` frees (`_rim`) — is therefore never running in current
practice, and the mid-tween hazard the item worried about was already narrower
than stated. `restyle()` still kills it unconditionally rather than trusting
that absence to hold forever. The tween that IS routinely live during a
restyle, `_open_tween` (the open/close scale-and-fade), turns out to be safe by
construction: it targets `self`, which `restyle()` never frees, only the
halo/body/rim children. Verified rather than assumed:
`debug/verify_skin_restyle.gd` fires `open()` and switches skin one frame later,
deliberately inside `TWEEN_WINDOW_OPEN`'s 0.10s, and the window survives.

**One real defect, found by capture rather than by reasoning about it in
advance.** A status window still showing a monster at the moment of a switch
put its third column outside the newly-resized frame. The cause is a real
asymmetry between the two row-building paths: `add_row()`'s label and value
live inside an `HBoxContainer` that keeps reflowing on its own, so the
row-height patch `restyle()` applies is sufficient — confirmed in the capture,
where the open spell list survives a live switch with no defect at all. But
`add_stat_row()` bakes each cell's x position from `STATUS_CELL_OFFSETS`
*at construction time*, which nothing about a chrome-only restyle touches.
`set_window_skin()` now calls `_refreshStatusWindows()` after restyling, which
rebuilds actor, target and (through its own existing call) the deep card from
scratch against the live tokens — the only thing that actually moves a baked
cell, and the same treatment `_refreshDeepCard()` already existed to give the
card.

**Verification, both by assertion and by looking.**
`debug/verify_skin_restyle.gd` drives a real battle and switches skin inside
MENU, MOVE_SELECT, TARGET_SELECT, CONFIRM_ACTION, an open spell list (checking
the cursor's y against `row_rect()` and its x against the new `CURSOR_INSET`),
an open and paged deep card, mid-CPU-playback, the named mid-open-tween race,
and six switches back to back with nothing in between — `SKIN RESTYLE: all
checks passed`. `debug/capture_skin_switch.gd` opens a spell list under `nogg`,
switches to Brigandine Plate live, and switches back, so the transition and its
reversibility are both visible rather than only asserted. `nogg`'s 272 tokens
remain identical to the pre-cycle baseline throughout — this item recomputes
nothing about that skin's own values, only builds the machinery to leave it
between switches.

**Deliberately not wired: `StatusBadgeRow.restyle()`.** SKIN-7 gave it one, but
every token a badge reads — `STATUS_BADGE_SIZE`, `TEXT_PRIMARY`, the shared
`OUTLINE` — was already confirmed non-skin-varying when that item shipped. A
badge has nothing to change on a switch, so calling it from here would be a
sweep with no effect to show for it.

### SKIN-4 — Put Nogg Herald under the whole battle UI

**Model:** Opus 5 / GPT Sol

**Model rationale:** This is the cycle's load-bearing change and it crosses a
boundary the codebase has an explicit written rule against — `NoggHeraldFont`'s
own header forbids Herald where a column has to line up, and the fixed status
cells are exactly that. Deciding which of those assumptions genuinely break and
which are already safe is judgement about an architectural invariant, not
mechanical substitution.

**Depends on:** SKIN-2.

**End state:** Under the Brigandine Plate skin, every player-facing battle
string renders in Nogg Herald at 13 units: window rows, status cells, the
prompt, the forecast, the turn rail's queue numerals, the action row's command
label, and the deep card. The `nogg` skin still renders Terminal at 12. The
developer HUD renders Roboto under both.

**Implementation:** `build_game_theme()` already takes a font path override for
the preview harness; the skin supplies it rather than a new mechanism being
invented. The `NoggBanner` type variation continues to resolve to Herald under
both skins — it always did, and nothing about it changes.

Enumerate what assumed a monospaced advance and state, for each, whether it
survives:

- **`add_stat_row()` value placement** — survives. It positions the value at the
  *measured* `label.size.x` plus a gap, not at a fixed advance.
- **`%03d` stat padding** — survives, on Herald's tabular digit advance, and
  only on that. Keep it.
- **`STATUS_CELL_OFFSET_UNITS`** — does not survive. Re-measured in SKIN-6.
- **`NoggWindow._row_available_widths`** — survives. Arithmetic over
  `get_minimum_size()`.
- **`debug/measure_px4_widths.gd`** — must learn the skin, since it is the tool
  SKIN-6 depends on.

**Risk:** Herald is a display face being asked to do body work at 13 units with a
two-pixel stroke and a negative kerning table. Negative kerning that reads as
confident on a banner can read as touching or broken at row scale, particularly
for the uppercase label pairs the status cells use. Judge `HP`, `ATK`, `DEF`,
`SPD`, `MOV` and a long monster name side by side at every `ui_scale` before
accepting the item, and if a pair fails, the fix is a kerning-table entry in the
Herald source, not a change to how windows lay out.

**Adds to final validation:** Every HUD string under Herald at `ui_scale` 1
through 4; the status cells holding their columns as values change; no glyph
falling back to a system face.

**Resolution (2026-08-25):** Implemented; pending end-of-plan validation.

**This item needed no product code, and that is the finding rather than a
shortcut.** Making the face a skin token in SKIN-2 was sufficient:
`build_game_theme()` already took its font path as a defaulted argument reading
`GAME_FONT_PATH`, and `_load_pixel_font()` already branched on `.res` versus
`.ttf`, so pointing the token at Herald put it under every window, the prompt,
the forecast, the status cells and the deep card at once. The work here was the
sweep and the evidence, not an edit.

`debug/capture_skin.gd` is what made that judgeable before the live-switch
plumbing exists: it sets the skin **before instantiating the scene**, which
sidesteps the fact that a `Theme` is built once as the canvas roots are created
and a `NoggWindow` builds its chrome in `_ready()`. Booting into a skin needs no
product code and no restyle path.

**Every monospace assumption the item listed was checked against a rendered
frame, and all of them hold.**

- `add_stat_row()` value placement survives, as predicted — it measures the
  label rather than assuming an advance, so Herald's proportional `HP`, `ATK`,
  `DEF`, `SPD` and `MOV` labels each get their own width and the values sit
  where they should.
- The `%03d` padding survives on Herald's tabular digit advance. `040 / 040`
  and `003` hold their columns in the capture, which is the only reason the
  fixed cells still work.
- No glyph falls back: Herald's codepoint set is identical to Terminal's, so
  every HUD string renders in-face at both scales.
- The negative kerning does not misbehave at row scale. The uppercase pairs the
  item singled out as most at risk — `HITS TO KILL`, `WEAK`, `RESIST`, and the
  stat labels — read cleanly with no touching or collision at x2 or x3.
- `CURSOR_INSET_UNITS` following the ring, from SKIN-2, is visibly correct: the
  spell window's cursor sits clear of the thicker 1.5-unit ring rather than on
  it.

**Two problems are visible in the capture and both belong to later items, named
here so they are not rediscovered.** The fill at alpha 0.55 is too transparent
over a lit board — the spell window and the deep card wash out against bright
terrain, exactly as SKIN-5's risk note predicted. And the 11-unit inset, correct
as a proportion of the reference's large two-row panel, makes our *small*
windows mostly padding: a one-row prompt is 30% inset by height against the
reference panel's 15%. That is SKIN-6's, and it means the reference's inset does
not transfer in absolute units to windows much smaller than the one it was
measured from.

Probe: the capture harness runs clean at both scales and prints
`CAPTURE COMPLETE`; the theme report confirms Herald at 13 units, inset 11, row
14, ring 1.5, radius 0 and no halo.

### SKIN-5 — Author the Brigandine Plate chrome

**Model:** Opus 5 / GPT Sol

**Model rationale:** The visual judgement the user actually asked for, made
against a reference by looking at rendered frames. Its inputs are numbers but
its acceptance is an eye, and it is the item most likely to need a second pass.

**Depends on:** SKIN-1, SKIN-3.

**End state:** Square corners, no halo node, a 1.5-unit border in the sampled
neutral grey with its inner edge flush against the fill, and a fill at the alpha
SKIN-1 derived. `set_active()` still tints rim and content together — that is
the only signal telling the player which window their arrow keys drive and it
must survive the skin change.

**Implementation:** Square corners are `WINDOW_CORNER_RADIUS_UNITS = 0`, which
`_rounded_window_style()` already accepts; do not add a second style builder.

Removing the halo removes this skin's entire answer to "legibility over a 3D
scene", which §1 lists as the first problem the window language solves — and the
fill is getting more transparent at the same time, pushing the same way. The
reference gets away with it over a flat painted map; our board is a lit 3D scene
with a bright sky. If the text does not hold over the sky in the capture, the
answer is the text's own shadow or a slightly denser fill, **not** a reinstated
halo: the halo is the thing the user asked to be rid of.

**Risk:** "Borders and inner filling match their edges" is satisfied today only
by accident — body and rim share a radius and the rim draws last. At radius 0
they agree trivially, but `StyleBoxFlat` draws its border inside the panel rect,
so the fill already runs under the border. Whichever edge SKIN-1 recorded, both
panels must be built against it.

**Adds to final validation:** Both skins over the brightest sky and the darkest
board; focus active and inactive under both; open and close tweens under both.

**Resolution (2026-08-25):** Implemented; pending end-of-plan validation.

Square corners, no halo node, a 1.5-unit neutral border and `set_active()`
tinting rim and content together all land as specified. `debug/capture_skin.gd`
boots into a chosen skin, so this was judged against a real battle at both
shipping scales rather than against a swatch.

**The item's risk fired, and the fix is the one it sanctioned.** Removing the
halo while making the fill more transparent pushes the same way, and over a lit
board it went too far. The fill ships at **0.78**, not the 0.55 the reference
measures at — and the gap between those numbers is the useful part. 0.55 was
tried in a real battle and is not legible; nor is 0.65, the ceiling SKIN-1's
first draft of the contract allowed. The measurement was not wrong; the
inference from it was. The reference is a flat painted overworld map with low
local contrast, so a fill letting 45% through lets through *tone*. Our board is
alternating bright green tiles under a light, so the same fill lets through
*texture*, and the ground under a row of text stops being stable even where the
contrast ratio is fine.

Rather than quietly overshoot the band, §4a is amended: it now records both
failed values, why the reference's number does not transfer, and a new 0.70–0.82
band. 0.78 is still visibly more transparent than `nogg`'s 0.86 — the board
reads clearly through every window in the captures — so the request that
prompted the skin is met.

The two sanctioned alternatives were considered and rejected. The text's own
shadow is out because the user asked for it kept as it is. A darker fill colour
is a negligible lever: at 0.65 alpha over a 0.45-luminance tile, moving the fill
from the current warm brown to pure black changes the result from 0.197 to
0.158, which is not the difference between legible and not — the problem was the
35% of high-frequency board coming through, not the tone of the 65%.

Confirmed in the same captures: `CURSOR_INSET_UNITS` following the ring, from
SKIN-2, puts the spell window's cursor clear of the thicker 1.5-unit ring rather
than on it; and border and fill share an edge with no seam at radius 0, which
SKIN-1 predicted from `StyleBoxFlat`'s draw order and this is the frame that
shows it.

### SKIN-6 — Author the metrics and re-measure every width

**Model:** Opus 5 / GPT Sol

**Model rationale:** The judgement is small but the blast radius is the whole
window taxonomy: eight widths and three cell offsets are functions of the two
numbers this item sets, under a face this cycle just changed. Getting the order
wrong silently truncates real content — the class of defect `PROMPT_WIDTH` and
`FORECAST_WIDTH` already carry a written history of.

**Depends on:** SKIN-4, SKIN-5.

**End state:** Brigandine Plate's `CONTENT_INSET_UNITS` reproduces the
reference's text-to-border distance — which is **larger** than `nogg`'s, per the
measurement above — and its row pitch follows Herald's 13-unit cell. Every
measured width and cell offset is re-measured under this skin and stored per
skin. No real string truncates under either skin at any `ui_scale`.

**Implementation:** Re-run the existing harnesses rather than writing new ones —
`debug/measure_px4_widths.gd` for the taxonomy and `debug/measure_deep_card.gd`
for the card, both of which already build real worst-case content from the
shipping catalogs. Make each report per skin.

Widths are stored per skin, not shared at the maximum of the two. A shared
maximum would make the tighter skin carry the looser skin's slack.

The reference's inset is not uniform — 10.5 left, 12.0 right, 13.5 top, 10.5
bottom. `CONTENT_INSET` is a single number today. Decide whether to reproduce
the asymmetry or take one value, and record which and why; a four-sided inset
touches `row_rect()`, `window_height()` and the cursor gutter together.

**Risk:** Herald is proportional, so a width measured against one worst-case
string no longer bounds a different string of the same character count. The
worst case has to be re-derived from actual rendered width across the whole
catalog, not carried over by character count from the Terminal measurement.

**Adds to final validation:** Every window's worst-case real string under both
skins at `ui_scale` 1 through 4; the three-digit padding holding its column; the
cursor centred in its gutter.

**Resolution (2026-08-25):** Implemented; pending end-of-plan validation.

Widths moved into `WindowSkinCatalog` and are stored per skin, not shared at the
maximum of the two. Brigandine Plate's are measured by one stated rule — worst
real string, plus at least five design units of headroom, rounded up to a
multiple of ten. Measured: command 90, spell 248, prompt 332, forecast 267,
status cell 211, pager 63, card 240. Shipped: 100 / 260 / 340 / 280 / 220 / 70 /
250. `nogg` keeps its historical authored values, because the skin is frozen and
re-deriving numbers that already ship would be a change nobody asked for dressed
as a measurement.

**`STATUS_CELL_OFFSET_UNITS` was not derivable from any existing harness, and
now is.** `measure_px4_widths.gd` *consumed* the offsets to size the window
rather than producing them, which was fine while one face was assumed. It now
reports what each column's content actually ends at, per row — column 1 must
clear the widest *paired* column-0 cell, column 2 must clear column 1's end and
the `HP` row's longer value. Terminal's `[0, 96, 192]` technically satisfied
Herald's requirements of 58 and 134, but left 38 and 58 units of dead space,
visible in a capture as a gap between `DEF` and the element cell. Brigandine
Plate ships `[0, 76, 152]`, and the status window drops from 270 units to 220.

**Two defects the measurement caught, both invisible without it.**

`DEEP_CARD_TOP_UNITS` was the literal 63, written as "PROMPT_TOP plus a one-row
window plus a stack gap" — an arithmetic that is only true for `nogg`. Under a
skin with a larger inset and taller pitch the prompt ends at 70, so the literal
put the card straight through it. It is now derived from those three terms, and
`window_height_units()` exists so it can be, since `_recompute()` needs the
height in units before the scaled values it rounds into are assigned.

And the card at 12 rows reached into the docked status windows: 282 against a
272 ceiling. `deep_card_capacity` is now skin-varying at 11 for this skin. The
deepest unit in the catalog builds 16 rows, so it pages once either way — the
lost row costs a page turn on nothing.

**`TURN_ORDER_WIDTH` is deleted rather than re-measured.** It sized the docked
turn-order window the portrait rail replaced, and a caller search found nothing
reading it but a stale comment. `TURN_ORDER_TOP` and
`BattleUIBuilder.TURN_ORDER_CAPACITY` were dead for the same reason and went
with it. Re-measuring a token nothing reads would have been the wrong kind of
diligence.

Verified: `--check-only` clean on all five touched scripts; both measurement
harnesses report every window fitting with no dock clash under either skin; and
the token dump still matches the pre-cycle baseline for `nogg` at all four
`ui_scale` values, 272 values compared.

### SKIN-7 — Extend the skin past the windows

**Model:** Opus 5 / GPT Sol

**Model rationale:** Three surfaces that each draw their own chrome in `_draw()`
against tokens that are about to become skin-dependent. It is design work — what
"this skin" even means for a portrait tile or a badge is not defined by the
reference, which contains neither — and it touches three files that currently
share nothing.

**Depends on:** SKIN-2, SKIN-5.

**End state:** The turn rail's tile frames, the action row's icon chrome and
label, and the status badges follow the active skin: square rather than rounded
where they are rounded, the skin's border weight and colour, the skin's fill
alpha. The developer HUD is untouched, which is the only exclusion the user
named.

**Implementation:** The reference shows none of these surfaces, so the rule is
derivation, not imitation: each takes the skin's border colour, border width,
corner radius and fill alpha from the same catalog the windows read, rather than
inventing per-surface values. Where a surface has no analogue in the skin — the
badge chip colours, the team-colour tile frames — it keeps what it has; those
carry meaning, not style.

`TurnOrderRail`, `ActionRow` and `StatusBadgeRow` each cache geometry on
`_resize()` or at build time, so each needs the same restyle entry point SKIN-3
gave `NoggWindow`, called from the same sweep.

**Risk:** The rail draws its queue numerals with `DIGIT_GLYPHS`, a local
hand-drawn digit table, not with the theme font. Switching the HUD face does not
switch those, and a rail numbering in one face beside windows in another is
exactly the drift this cycle is meant to remove. Decide whether the rail adopts
Herald or keeps its drawn digits, and say why.

**Adds to final validation:** Rail, action row and badges under both skins at
every `ui_scale`; the dev HUD unchanged under both.

**Resolution (2026-08-25):** Implemented; pending end-of-plan validation.

**The item was much smaller than it looked, and the caller sweep is why.** Of
the three surfaces, only one carried a style value that was not already
skin-varying: `TurnOrderRail._ink()`, a `Color(0, 0, 0, 0.88)` literal that also
broke this project's rule that no colour lives outside `NoggTheme`. It is the
rail's halo — the same job the window halo does, on a different surface — so it
became a skin token, and Brigandine Plate sets it fully transparent. Leaving it
would have made the rail the one surface still wearing the look this skin
removed from every window: a dark ring around each tile is a halo by another
name.

`TURN_RAIL_FRAME_UNITS` now follows the skin's window ring so a tile's edge
carries a window's weight. It was 1.0, which is `nogg`'s ring exactly, so that
skin does not move.

**The action row and the status badges needed no change**, and saying so is the
result rather than an omission. The row reads `FONT_SIZE_BODY`, `TEXT_PRIMARY`
and the shadow tokens, all of which the skin already moves; the badges' chip
colours are effect identity and their outline is the shared `OUTLINE`, neither
of which a skin may claim. Both still gained a `restyle()`, because a caller
sweeping every surface should not have to know which ones needed real work.

**The item's risk asked whether the rail should adopt Herald, and the answer is
no, on geometry rather than taste.** A bitmap face floors to whole multiples of
its nominal size — 12 device pixels for Terminal, 13 for Herald — and a tile is
`TURN_RAIL_TILE_WIDTH` 20 design units wide, so no theme face fits its corner at
any skin or any scale. The skin with the *larger* nominal size fits worse. The
drawn `DIGIT_GLYPHS` are not drift from a face that was an option; they exist
because no face is. `StatusBadgeRow`'s overflow digits are drawn for the same
reason, and the comment on both now says so rather than citing the old
single-face arithmetic.

Verified: `--check-only` clean on all five touched scripts; the capture shows
rail tiles as clean team-coloured plates over the translucent body with no dark
ring; and the token dump still matches the pre-cycle baseline for `nogg`, 272
values across all four `ui_scale` values.

### SKIN-8 — Expose the toggle and persist it

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Multi-file but entirely mechanical against a stated end
state, following two existing patterns exactly — the render preset dropdown for
the control, `user://rendering.cfg` for persistence. No boundary is drawn that
SKIN-2 has not already drawn.

**Depends on:** SKIN-3, SKIN-6, SKIN-7.

**End state:** The developer graphics menu carries a **Window Skin** dropdown
beside the render preset, listing both skins with their catalog descriptions.
Choosing one applies it live and writes it to `user://rendering.cfg` alongside
the rendering options. The setup screen offers the same choice, matching how
render presets already appear in both places.

**Implementation:** `BattleGraphicsMenuRefs` gains the option button;
`BattleGraphicsMenu.build()` gains the control and callback;
`BattlePresentationController` gains the handler, which calls
`NoggTheme.set_skin()` then the restyle sweep from SKIN-3 and SKIN-7.
Persistence rides `RetroRenderController`'s existing `ConfigFile` rather than
opening a second settings file.

**Risk:** The skin is read at theme-build time, and `BattleUIBuilder` builds
themes before the persisted value loads if the wiring order is wrong. The first
frame would show the wrong skin and correct itself, which reads as a flicker.
Load the persisted skin before the first theme is built.

**Adds to final validation:** Skin surviving a restart; setup screen and
in-battle menu agreeing; the dev HUD unchanged under both.

### SKIN-9 — Consolidated skin validation

**Model:** Opus 5 / GPT Sol

**Depends on:** SKIN-1 through SKIN-8.

The only item that launches the game. Validate the union in one integrated pass:

1. Capture the full HUD under both skins at `ui_scale` 2 and 3, at the default
   preset, the harshest retro rung, and the CRT pass with and without
   `ui_through_crt`. Reuse `debug/capture_leg_final.gd`'s states — hover with
   reach, the attributed danger zone, the deep card — rather than authoring new
   ones; they already put every window class on screen at once.
2. Confirm the `nogg` skin is **identical** to its pre-cycle capture by file
   hash. Any difference is a regression in a look nobody asked to change.
3. Exercise every window class under Brigandine Plate: prompt, forecast, spell
   list with a page turn, confirm, both docked status windows, the deep card
   with a page turn, and the pager footer that straddles a bottom border — which
   at radius 0 meets a square edge for the first time.
4. Switch skins live in each phase named in SKIN-3, plus during an open or close
   tween, and confirm no surface is left half-styled.
5. Play a complete 4v4 under Brigandine Plate. Judge Herald over the sky and
   over the board while the camera turns, not from stills.
6. Search every caller of each changed shared surface — `NoggTheme`'s promoted
   tokens, `NoggWindow`'s chrome builders, the rail, the action row, the badges,
   the graphics menu refs — and exercise all of them, including
   `debug/preview_theme.gd`, which builds windows outside the battle scene and
   will be the first thing a promoted token breaks.
7. Verify the shipped HUD against `docs/UI_DESIGN.md` as amended by SKIN-1, run
   `git diff --check`, and inspect the focused diff.

**Risk:** A skin that reads well in a still can fail in motion, and this one
removes the depth cue the current look relies on to stay readable over a moving
3D board while also changing the face carrying every string. Judge it while the
camera turns and units move.

**Completion:** Record observations and captures. If defects appear, fix them in
this session and rerun the affected consolidated flow. Once acceptance passes,
grep for this cycle's item identifiers outside this file, rewrite any persistent
hits as durable descriptions, move any genuinely open work to the appropriate
backlog and name it to the user, then clear this plan file in the same session
per the plan lifecycle policy.

## Deliberately excluded

- **Retuning the `nogg` skin.** The user asked for a second look, not a fixed
  first one. `nogg` is frozen and SKIN-9 asserts it by hash.
- **The developer HUD.** The dev bar, graphics menu, and battle log keep Roboto
  and their own styling under both skins. `docs/UI_DESIGN.md` §9 explains why,
  and it is the one exclusion the user named.
- **Making the Herald body text smaller than 13 units.** It is a bitmap face
  exact at its nominal size; a fractional size resamples it. If the result reads
  too large, the levers are row pitch and window width, and that is SKIN-6's
  work, not a font-size change.
- **A third skin, or user-authored skins.** The catalog shape SKIN-2 introduces
  makes one cheap later; adding one now designs for a request nobody has made.
