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
