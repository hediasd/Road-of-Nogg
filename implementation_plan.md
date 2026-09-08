# Pixel-Exact UI Cycle

**Opened 2026-08-09.** The previous contents were the Fire Storm cycle, opened
2026-08-04. Its two implementation items were committed and are live; its final
validation item (`FIRE-3`) was **in progress and never completed** — the
automatable half passed and the half needing a real battle never ran. That
outstanding validation is **not** dropped: it moved verbatim into
`BACKLOG_CRITICAL.md` under "Fire storm and ice storm have never been validated
in a real battle", including the tuning provenance a future session would
otherwise undo. Nothing else from that cycle is left open. Recover its full text
with `git show a5ea3a5:implementation_plan.md`.

---

## 1. Goal

**UI text is not pixel-exact at most window sizes, and it never has been.**

`project.godot` sets `window/stretch/mode = "canvas_items"` with
`aspect = "expand"` and authors no `viewport_width`/`viewport_height`, so Godot
falls back to its 1152 x 648 default and scales the entire canvas by
`window_size / 1152`. That factor is fractional at nearly every real window
size. With `textures/canvas_textures/default_texture_filter = 0` (nearest), a
fractional factor duplicates some pixel rows and drops others, so a one-pixel
stroke renders two device pixels wide in places and three in others *inside the
same word*.

Make every resolution-dependent UI element land on whole device pixels at every
window size, without letterboxing and without redesigning existing layouts.

## 2. Established facts (measured 2026-08-09 — do not re-derive)

All of the following was captured in the VFX debug scene at 1340 x 754 and is
reproducible with `--stretch=` plus `--capture-at=`.

### The damage is real and pre-existing

- At 1152 x 648 the canvas factor is x1.000 and every stroke is exactly two
  device pixels. At 1340 x 754 it is x1.163 and stroke widths vary within one
  word.
- **XenoText is damaged identically.** It is also a pixel face, rendered with
  antialiasing and hinting disabled, so rasterizing it at `24 x 1.163` produces
  stem widths the design never intended. This is not a defect the new bitmap
  face introduced — it exposed it.

### Only half the UI is affected, and that is what makes a fix affordable

- **Resolution-independent:** `StyleBoxFlat` rims, rounded bodies, halos. These
  are *redrawn* at whatever size they are given rather than resampled. Captured
  at both factors the window rim is indistinguishable. They cost nothing either
  way, and they are the majority of the chrome.
- **Resolution-dependent:** both fonts, and the small-integer geometry in
  `MenuCursor` (10 x 12), `PagerArrow`, and `ResonanceBar` (10 px cells, 3 px
  gaps).

### The chokepoint already exists

- `NoggTheme` is already declared the single source of truth for every colour,
  font, spacing and timing value, and the rule that no colour literal appears
  elsewhere under `src/presentation/` is already enforced.
- Only **14** numeric size literals exist outside `NoggTheme` in
  `src/presentation/`, and all but one are 3D/VFX values (particle radii, mesh
  sizes, CRT uniforms) rather than UI geometry. The exception is
  `StatusEffectIcons`, which is a world-space billboard and scales by a
  different mechanism.
- Only four scripts draw UI geometry directly — `MenuCursor`, `PagerArrow`,
  `ResonanceBar`, `DamageNumberBillboard` — and all already read their sizes
  from `NoggTheme` tokens rather than from literals.

### Canvas-level integer scaling was evaluated and rejected

- `scale_mode = "integer"` against the inherited 1152 x 648 base admits only x1
  at 1920 x 1080, because x2 would need 2304 x 1296. Heavy letterboxing.
- A 640 x 360 base divides the 16:9 ladder exactly, and renders crisply — but
  every existing layout is authored against roughly 1152 logical pixels and
  would have to be re-authored at half scale. Captured at 1340 x 754 the
  specimen's own 404 px margin already consumes most of a 670 x 377 viewport.

### A bitmap face does not survive a content-scale change

Changing the content scale changes the text server's font oversampling, which
clears cached glyph data. A dynamic face re-rasterizes from the font bytes it
still holds; `NoggBitmapFont` injects glyphs directly into the cache and has no
bytes, so they are gone and every string falls back to a system font reporting
ascent and descent as zero. **`stretch/mode = "disabled"` removes this failure
mode entirely** rather than working around it, because oversampling then never
changes — including across a window resize.

## 3. Design decisions

### Stop scaling the canvas; scale the design tokens by a whole number

`project.godot` moves to `window/stretch/mode = "disabled"`, so nothing is ever
resampled. `NoggTheme` gains a `UI_SCALE` integer derived from window height,
and every geometry token becomes a design unit multiplied by it.

Both families win under this scheme, which is the point: smooth chrome is
redrawn at the larger size and stays smooth, while pixel content lands on whole
device pixels. There is no letterboxing, no aspect-ratio constraint, and no
`viewport_width` to keep in sync with anything.

`UI_SCALE` is also the resolution-aware scale ladder the bitmap face needs,
applied to the whole UI instead of only to text — the font's whole-multiple
constraint stops being a special case and becomes the general rule.

### Design units are the authored unit; device pixels are derived

Tokens are authored at `UI_SCALE = 1` and multiplied on read. `12` is the body
size, not `24`. This is a deliberate re-basing: the current constants are
already `UI_SCALE = 2` values in disguise, which is why `FONT_SIZE_BODY = 24`
happens to be exactly twice `NoggBitmapFont.NOMINAL_SIZE`.

### `FONT_SIZE_FOOTER` survives this cycle after all

**Corrected during PX-1.** This section originally claimed 20 could not survive.
It can: 10 design units resolves to exactly 20 at `UI_SCALE = 2`, so nothing
moves. The problem is narrower than stated — 10 is not a multiple of
`NoggBitmapFont.NOMINAL_SIZE`, so the footer has no honest size *if Nogg
Terminal is adopted as the game face*. That belongs to the adoption decision in
`BACKLOG_LONGTERM.md`, not here. XenoText is a dynamic face and renders 10 and
20 happily.

## 4. Items

### PX-1 — `UI_SCALE` and design-unit tokens in `NoggTheme`

**Model:** Opus 5 / GPT Sol *(this decides an architectural boundary: who owns
the scale value, how consumers observe a change, and whether tokens stay
constants or become functions. Every later item depends on the answer.)*

Introduce `UI_SCALE` and convert `NoggTheme`'s geometry tokens to design units
multiplied by it. Decide and document:

- **Where the value lives and who computes it.** It is a function of window
  height and must be readable before any theme is built.
- **Constants vs functions.** Tokens that are currently `const` and read at
  parse time (`ROW_HEIGHT`, `STATUS_CELL_OFFSETS`, `CURSOR_*`,
  `RESONANCE_*`, `CONTENT_INSET`, `FRAME_RING_PX`, `WINDOW_CORNER_RADIUS`,
  `HALO_*`, `WINDOW_STACK_GAP`) cannot stay constants if the scale can change at
  runtime. Choose whether they become static functions or whether the theme is
  rebuilt wholesale on change, and say why.
- **The change signal.** Themes are built once today and there is no path from
  a window resize to a rebuild and relayout. Establish one, or establish
  explicitly that `UI_SCALE` is fixed at startup and a resize does not restyle.

Colour, timing, and animation tokens are untouched — they are not geometry.

**Risk:** this is the item that can silently move every window in the game. The
mitigation is that it changes no observable value at `UI_SCALE = 2`, which is
what the current constants already encode; a correct conversion is a no-op at
today's effective scale, and that is the check.

**Adds to final validation:** every window renders identically at `UI_SCALE = 2`
to the pre-change build.

### PX-2 — Switch the project to native 1:1 and wire the scale

**Model:** Sonnet 5 / GPT Terra *(mechanical once PX-1 has fixed the ownership
and the signal; the end state is fully specified by it.)*

Set `window/stretch/mode = "disabled"` in `project.godot`. Compute `UI_SCALE`
at startup from window height and, if PX-1 chose a runtime signal, recompute and
rebuild on resize.

**Risk:** UI occupies a smaller share of a large screen than it does today
whenever `UI_SCALE` resolves lower than the effective factor the fractional
stretch was applying. Expect the HUD to look different at unusual window sizes;
that is the change, not a regression.

**Adds to final validation:** text is pixel-exact at 1152 x 648, 1340 x 754,
1920 x 1080, and fullscreen.

### PX-3 — Migrate the direct-drawing UI components

**Model:** Sonnet 5 / GPT Terra *(four files, stated end state, no design
latitude.)*

Convert `MenuCursor`, `PagerArrow`, `ResonanceBar`, and `DamageNumberBillboard`
to the scaled tokens. They already read `NoggTheme`, so this is mostly
confirming that each read goes through the scaled accessor rather than a cached
`const`, and that `_draw()` rounds to whole device pixels.

**Risk:** the cursor gutter is a two-number agreement — `CURSOR_WIDTH` and
`CURSOR_GUTTER_WIDTH` must scale together or the arrow lands on the ring or
floats in dead space, which `NoggTheme` already warns about.

**Adds to final validation:** cursor, pager arrows, and resonance bars are
crisp and correctly placed at `UI_SCALE` 1, 2, and 3.

### PX-4 — Re-measure the width budgets and update `UI_DESIGN.md`

**Model:** Sonnet 5 / GPT Terra

§7b's marquee thresholds and §8's window-width measurements are recorded in
device pixels at the current effective scale. Re-take them in design units and
update the doc.

**This item legitimately changes the numbers a passing check reports.** The
existing measurements are not wrong; they are expressed in the wrong unit. Do
not try to restore the old values.

**Adds to final validation:** no row marquees that should not, and no window
clips content it previously fit.

### PX-5 — Decide whether the CRT pass follows `UI_SCALE`

**Model:** Opus 5 / GPT Sol *(a look decision, and one that trades authenticity
against legibility rather than having a correct answer.)*

`RetroRenderController` sets `crt_scanline_size = 1.0` and `crt_mask_size = 1.0`
in device pixels. Under `disabled`, a one-device-pixel scanline is invisible at
4K and overwhelming at 720p. Decide whether these follow `UI_SCALE`, follow the
retro viewport's own render scale, or stay fixed — and capture the alternatives
rather than arguing them.

**Blocking on a user decision.** The outcome is a matter of taste about how
present the CRT effect should be at high resolution, and this item should
present captures and stop rather than pick.

**Adds to final validation:** the CRT pass reads correctly at 720p, 1080p, and
fullscreen.

### PX-6 — Final validation

**Model:** Opus 5 / GPT Sol *(cross-layer, and the only item that judges whether
the whole change held.)*

Depends on PX-1 through PX-5. The only item that marks the others done.

1. Launch `Battle25D`. Exercise every window kind — command menu, status,
   confirm prompt, paging, marquee — at 1152 x 648, 1340 x 754, 1920 x 1080,
   and fullscreen.
2. Confirm text is pixel-exact at each, using the VFX debug scene's specimen
   readout as the objective check rather than judging by eye.
3. Confirm the union of the per-item validations above.
4. Resize the window during play and confirm the UI restyles correctly, or
   that it explicitly does not if PX-1 chose a startup-fixed scale.
5. Confirm the bitmap face never falls back — ascent and descent stay non-zero
   across every resize.

## 5. Deliberately not doing

- **Adopting Nogg Terminal as the game face.** That is a separate decision with
  its own layout cost (16 px advance against XenoText's 12 px) and is recorded
  in `BACKLOG_LONGTERM.md`. This cycle makes the display correct for whichever
  face ships; it does not choose the face.
- **Changing `WINDOW_FILL`.** The warm-deep candidate has been picked by eye in
  the specimen but lifting the shipping token is a restyle, not a scaling fix.
- **Re-authoring layouts for a smaller base.** Rejected above with measurement.

## 6. Resolution notes

- **PX-1** — implemented; pending end-of-plan validation.
  `NoggTheme` now carries `ui_scale`, `configure()`,
  `configure_for_window_height()`, and design-unit constants for every geometry
  token. Four `const` captures in `MenuCursor` and `PagerArrow` became accessors.

  **The three decisions the item existed to make:**

  1. **Static vars, not functions.** Sixty call sites across a dozen files read
     these token names. Converting each into a function call would have broken
     this file's central promise — that a restyle is a one-file edit — for no
     gain, since the values only change when `configure()` says so. The names
     keep their identity; only their values move. `configure()` is the single
     writer and `_recompute()` derives all of them together, so no subset can
     drift out of agreement.
  2. **No signal, and `NoggTheme` gains no node identity.** `configure()`
     returns whether the scale actually changed, and the caller decides whether
     to rebuild themes and relayout. Giving a pure token-and-factory class a
     node so it could emit would have been a larger change to its role than the
     problem justifies. PX-2 owns the caller.
  3. **Rounding is a property of the tokens, not of each draw site.** Design
     units are allowed to be fractional where an existing value demands it
     (`RESONANCE_CELL_GAP` is 3 device pixels at x2, so 1.5 units), but every
     result goes through `roundi`. Whole device pixels are the objective, so
     guaranteeing them once at the token layer beats hoping each `_draw()`
     remembers.

  **`_static_init()` closes the uninitialised window.** It runs on class load,
  so tokens are correct at the default scale before any consumer can read one.
  There is no moment where a caller observes an unconfigured value.

  **PX-3's scope shrank.** `MenuCursor._WIDTH/_HEIGHT` and
  `PagerArrow.WIDTH/HEIGHT` were `const NoggThemeScript.CURSOR_*`, which stops
  parsing the moment those become static vars — so they had to move in this item
  for the project to load at all. They are now `_width()`/`_height()` and
  `width()`/`height()` accessors read at draw time. Both were internal-only;
  nothing outside those two files referenced them. `ResonanceBar` and
  `DamageNumberBillboard` were untouched and remain PX-3's work.

  **A correction to this plan's own §3**, recorded there: `FONT_SIZE_FOOTER`
  was claimed unsurvivable and is not. 10 design units gives exactly 20 at x2.
  The multiple-of-12 problem is real but belongs to the font-adoption decision,
  not to this cycle.

  **Verified.** `debug/verify_ui_scale.gd` (new, gitignored) asserts all 23
  tokens reproduce their pre-change literals **exactly** at x2 — the item's
  stated check, that a correct conversion is a no-op at today's effective
  scale — plus whole-pixel results for all 17 geometric tokens at x1/x2/x3/x4,
  agreement between `RESONANCE_BAR_WIDTH` and the cells it is supposed to span,
  agreement between `window_height()` and its inputs, and the height-to-scale
  mapping including `configure()`'s changed/unchanged return. Result: PASS.
  `Battle25D` and `VFXDebugScene` both load clean, and the pre-existing
  `debug/verify_status_layout.gd` harness reports all checks passed.

  **Not verified here, and left to PX-6:** nothing has been *looked at*. The
  numeric equivalence at x2 is strong evidence the UI is unchanged, but no
  window has been rendered and compared, and no scale other than 2 has been
  seen on screen at all. The cursor and pager accessor changes are on the draw
  path specifically and have only been proven to parse and to return the right
  numbers.
- **PX-5** — **investigated; blocked on a user decision, as the item said it
  would be.** No value was chosen and no default changed.

  **The harness gained the controls the decision needs.** `--crt-scanline-size=`
  and `--crt-mask-size=` now reach the live renderer, so the alternatives are
  captured rather than argued. Both were already runtime-settable and clamped
  (scanline 0.5-4.0, mask 1.0-6.0); nothing about the renderer changed.

  **A false result was produced and corrected before it was reported.** The
  first attempt routed both through `set_look_parameter()`, which has no arm for
  `CRT_*` names and no fallback, so it silently did nothing. The captures
  differed by mean 0.009 / peak 1 — which reads as "this parameter does not
  matter" rather than "this parameter was never set". Routing through
  `set_crt_parameter()` gives mean 1.383 / peak 31. Recorded in
  `docs/LEARNINGS.md` under "Retro render parameters", with the general rule:
  diff two frames numerically before concluding a visual parameter has no
  effect.

  **What the decision actually rests on.** Scanline and mask pitch are in device
  pixels. Under the fractional stretch they inherit whatever the canvas factor
  is, so their apparent size has always drifted with window size; under PX-2's
  `disabled` they become genuinely fixed, and a one-pixel scanline is a
  different thing at 720p than at 4K. Captures exist at 1920 x 1080 for pitch 1
  (today's value) and pitch 3.

  **Not decided, deliberately:** whether pitch follows `UI_SCALE`, follows the
  retro viewport's own render scale, or stays fixed. This trades CRT
  authenticity against legibility at high resolution and has no correct answer,
  which is why the item is marked blocking. It should be resumed with a choice,
  not a recommendation.
- **PX-2** — implemented; pending end-of-plan validation.
  `project.godot` now sets `window/stretch/mode = "disabled"`.
  `BattlePresentationController._ready()` calls
  `NoggThemeScript.configure_for_window_height(get_window().size.y)` as its
  first statement, before any Theme is built.

  **The resize question PX-1 deferred is answered: fixed at startup, not live.**
  `configure()` changing `ui_scale` after Theme resources are already built and
  assigned would desync two kinds of reader — a `Theme`'s font size and
  styleboxes are copied in at build time and would keep the old scale, while
  code reading a token directly at draw time (`NoggWindow`'s cursor gutter math,
  `MenuCursor`'s accessors) would see the new one immediately. That
  disagreement is worse than not rescaling, and fixing it needs a
  rebuild-and-relayout path for every open window, which is real, separate work
  — recorded in `BACKLOG_LONGTERM.md` as live UI rescaling, deliberately not
  attempted here. `configure_for_window_height()` is therefore called exactly
  once per process.

  **The debug harness's stretch presets were reordered and relabeled, not left
  stale.** Before this item its first preset was called "Project default
  (fractional)" and its `native` entry called itself the alternative — both
  became lies the moment `project.godot` changed. `native` is now first (it is
  what the project does, and what the HUD dropdown shows by default), and the
  old fractional entry survives as `legacy_fractional`, explicitly kept rather
  than deleted so the bug this cycle fixed stays reproducible on demand.
  `--stretch=project` no longer resolves; it is `--stretch=native` or
  `--stretch=legacy_fractional` now, and both the flag's own doc comment and
  its unknown-value warning were updated to match. `TextSpecimen`'s pixel
  fidelity comment and its "not exact" hint also referenced the old default and
  were rewritten — the hint now says to reset the Canvas stretch control rather
  than resize the window, since a window resize can no longer produce a
  fractional factor on its own.

  **Verified.** `debug/verify_ui_scale.gd` still PASSes (this item touched no
  token math). `Battle25D` loads headless clean at 1340 x 754 with no override
  flag. Captured proof of the actual fix: XenoText at 1340 x 754 under
  `project.godot`'s own new default (no `--stretch` flag at all) reads
  `canvas x1 PIXEL-EXACT`, and every stroke is uniform — the same capture that
  previously read `x1.163 NOT PIXEL-EXACT`. Captured proof the comparison path
  still works: `--stretch=legacy_fractional` at the same resolution reproduces
  `x1.163 NOT PIXEL-EXACT` on demand.

  **Not verified here, left to PX-6:** nothing has been seen in the actual
  `Battle25D` scene rendered on screen, only headless-loaded. The startup
  `configure_for_window_height()` call has not been exercised at a launch size
  other than whatever the default window is.
- **PX-3** — implemented; pending end-of-plan validation.

  **Audit result: `MenuCursor` and `PagerArrow` needed nothing further** — PX-1
  already converted their `const` captures to accessors as a parsing necessity,
  and both were re-verified here rather than re-touched.

  **`ResonanceBar` needed one real fix.** Every size and position it reads was
  already a live `NoggTheme` token (never a captured `const`), so it tracked
  scale correctly for everything except one thing: the empty-cell outline
  stroke was `draw_rect(..., 1.0, false)` — a literal device pixel that never
  scaled while the cell it outlines grows fourfold from x1 to x4. Added
  `RESONANCE_CELL_BORDER_UNITS := 0.5` to `NoggTheme` (0.5 so it reproduces the
  historical 1px at x2, the same no-op-at-x2 rule PX-1 used throughout) and
  pointed the draw call at it.

  **`DamageNumberBillboard` was audited and left unchanged, deliberately.**
  `FONT_SIZE_BODY` is already a live read, so its glyph size already scales.
  Its four-direction 1px halo (`OUTLINE_OFFSETS`) does not, and — unlike the
  resonance border — this was judged correct as found rather than fixed: the
  halo is this component's crisp finishing hairline, the same
  resolution-independent role `docs/UI_DESIGN.md` §3 already assigns
  `StyleBoxFlat` rims. A halo that grew with the glyph would read as thicker,
  blurrier text at high scale, the opposite of the "same crisp number, drawn
  bigger" look this component exists for. Documented in-file so a future
  reader finds the reasoning rather than "fixing" it as an oversight.

  **A wrong verifier, caught before it shipped a false failure.** The first
  version of `debug/verify_px3_geometry.gd` (new, gitignored) checked the
  cursor's bob excursion against `CURSOR_GUTTER_WIDTH` alone and failed at
  every scale, including x2 — which would mean the *shipping* geometry, never
  touched by this cycle, was already broken. Tracing the real call sites
  (`PlayerCommandMenu._build_cursor()` parents the cursor at
  `position.x = CURSOR_INSET` in the window's own local space;
  `set_content_indent()` starts content at `CONTENT_INSET + CURSOR_GUTTER_WIDTH`,
  not at `CURSOR_GUTTER_WIDTH` alone) showed the older prose comment in
  `NoggTheme` ("ring ends 12 | cursor 16..28 | text starts 34") is illustrative
  and does not correspond to that formula either — it predates this cycle and
  was left as-is, since correcting an unrelated pre-existing comment was out of
  this item's scope. The corrected verifier checks the two real inequalities:
  the cursor's near edge at its bob excursion must not cross `FRAME_RING_PX`,
  and its far edge must not cross `CONTENT_INSET + CURSOR_GUTTER_WIDTH`.

  **Verified.** `debug/verify_px3_geometry.gd`: at x1/x2/x3/x4, `MenuCursor` and
  `PagerArrow` report identical whole-pixel sizes (family agreement holds), the
  cursor clears both the ring and the text start at every scale, `ResonanceBar`
  reports `size` matching `RESONANCE_BAR_WIDTH`/`RESONANCE_CELL_SIZE`, every
  cell's computed left edge is a whole pixel, and the border stroke is whole
  and never thinner than 1px. `debug/verify_px3_damage_number.gd`: at every
  scale, a spawned billboard's height matches `FONT_SIZE_BODY` and every
  digit's x position is whole. Both PASS. `debug/verify_ui_scale.gd` still
  PASSes (untouched by this item). `Battle25D` still loads headless clean at
  1340 x 754. The pre-existing `debug/verify_status_layout.gd` still reports
  "all checks passed" (its `save_png`/texture null-value noise is the
  established headless-dummy-renderer artifact this harness always prints, not
  a regression — see its own prior passing runs).

  **Not verified here, left to PX-6:** none of this geometry has been looked
  at on screen — only measured. Whether the resonance border actually reads as
  "a crisp thin line, not a heavier chrome element" at x1 and x4, and whether
  the damage-number halo genuinely looks intentional rather than thin at x4,
  are look judgments PX-6 is where they get made.
- **PX-4** — implemented; pending end-of-plan validation.

  **Scope grew beyond the item's own text, and the reason is a correction to
  PX-1's own "Established facts" — recorded here rather than silently
  absorbed.** PX-1 claimed only 14 size literals existed outside `NoggTheme`,
  nearly all 3D/VFX. That census used a case-sensitive grep for lowercase
  `width`/`height`/etc. and missed every constant named in SCREAMING_CASE —
  `STATUS_WINDOW_WIDTH`, `TURN_ORDER_WIDTH`, `COMMAND_WIDTH`, `SPELL_WIDTH`,
  `PROMPT_WIDTH`, `FORECAST_WIDTH`, `PAGER_WIDTH` — seven real window-width
  constants across `BattleUIBuilder.gd`, `PlayerCommandMenu.gd`, and
  `NoggWindow.gd`, none of them 3D/VFX, all of them exactly the class of
  resolution-dependent geometry PX-1 set out to find. A case-insensitive rerun
  surfaced them. Left alone, every one would have stayed a fixed device-pixel
  width while the text inside it grew fourfold from x1 to x4 — directly
  contradicting this item's own stated validation bar, "no window clips content
  it previously fit." Widening PX-4 to cover them was the only way to actually
  meet that bar, not a scope choice made for its own sake.

  All seven became `NoggTheme` design-unit tokens (`COMMAND_WIDTH`,
  `SPELL_WIDTH`, `PROMPT_WIDTH`, `FORECAST_WIDTH`, `STATUS_WINDOW_WIDTH`,
  `TURN_ORDER_WIDTH`, `PAGER_WIDTH`, plus `PAGER_ARROW_GAP` found alongside
  `PAGER_WIDTH`), following PX-1's established pattern exactly: `_UNITS`
  constant, `static var`, populated in `_recompute()`. The four consumer files
  had their local `const` literals deleted and every call site pointed at the
  live `NoggThemeScript.*` token instead.

  **Values were measured, not derived by dividing the old number by two.**
  `debug/measure_px4_widths.gd` (new, gitignored) reuses
  `debug/preview_theme.gd`'s own `CONTENT_INSET * 2 + label + value (+ gap)`
  formula against the *real* longest strings in this codebase — pulled from
  `data/spells.json`, `data/monsters.json`, and `PlayerTurnController`'s actual
  status/forecast text, not placeholders — at `ui_scale = 1`, where a design
  unit and a device pixel are the same number and no conversion step exists to
  introduce rounding error.

  **That measurement found a real, pre-existing bug, independent of this whole
  cycle, and PX-4 fixed it rather than reproducing it.** Measured against the
  shipping font at the *current* x2 scale — nothing to do with `UI_SCALE` —
  `PROMPT_WIDTH` (620px) was 76px short of
  `"Preview tile (12, 12). Empty-center casting is disabled."` (needs 696px),
  and `FORECAST_WIDTH` (460px) was 44px short of
  `"Cast spends action, cooldown & Resonance"` (needs 504px). Both strings are
  verbatim from `PlayerTurnController`. `debug/preview_theme.gd`'s own
  `WIDTH_CASES` never covered prompt or forecast content at all — only
  command/spell/actor — which is presumably how this went unmeasured. The other
  five widths (`COMMAND_WIDTH`, `SPELL_WIDTH`, `STATUS_WINDOW_WIDTH`,
  `TURN_ORDER_WIDTH`, `PAGER_WIDTH`) reproduce their prior x2 value exactly —
  those really were only a unit problem, matching this item's original framing.

  §7b and §8 of `UI_DESIGN.md` were rewritten, not just re-numbered: §8's old
  "budget of 1152 × 648" framing described the `canvas_items` stretch mode PX-2
  removed and no longer applies — under `disabled` stretch there is no shared
  ceiling for windows to compete over, each is simply as wide as its own
  content needs. §7b's `MARQUEE_SPEED` entry now notes it is the one marquee
  number that scales with `ui_scale` (a rate over a spatial unit has to track
  the same scale as what it's moving) while `MARQUEE_DELAY`/`MARQUEE_END_HOLD`
  correctly do not (durations, not lengths).

  **Verified.** `debug/verify_px4_widths.gd` (new, gitignored) re-measures
  every one of the eight real worst-case strings against the live font at
  x1/x2/x3/x4 and confirms each still fits its window's budget, plus confirms
  every width token is a whole device pixel at every scale. PASS at all four.
  `debug/verify_ui_scale.gd` and `debug/verify_px3_geometry.gd` still PASS
  (neither's tokens were touched by this item). `Battle25D` and
  `VFXDebugScene` both still load headless clean at 1340 x 754.
  `debug/verify_status_layout.gd` still reports all checks passed.

  **Not verified here, left to PX-6:** nothing has been seen on screen. In
  particular, the corrected `PROMPT_WIDTH`/`FORECAST_WIDTH` have only been
  confirmed to hold their worst-case *string* — whether the wider windows still
  read as correctly positioned and don't collide with anything else on screen
  at their new size is a look judgment PX-6 is where it gets made.
- **PX-5** — **decided and implemented.** The item was marked blocking on a user
  decision; the user instructed "run PX-5 and 6" after twice being offered the
  choice, so the call was made here and the captures are provided for override.

  **Decision: scanline and mask pitch follow `ui_scale`.** The multiply lives in
  `RetroRenderController._apply_display_parameters()` and nowhere else. Stored
  values stay resolution-independent multipliers (`1.0` = "this project's
  default look"), so a settings file or render preset written at one resolution
  still means the same thing at another; only the number handed to the shader
  carries resolution in it. The graphics menu's "Line size" / "Mask size"
  sliders are labelled generically and keep working unchanged.

  **Rationale, from the shader's actual math:** it spaces both effects off
  `FRAGCOORD`, which is device pixels. A pitch fixed in device pixels is
  backwards for what it simulates — a physical CRT has a fixed scanline
  *count*, not a fixed pixel pitch — so the old behaviour gave ~360 lines at
  720p and ~1080 at 4K, the effect dissolving into flat darkening exactly where
  the screen is big enough to show it off. Measured after the change: 180 lines
  at 720p, 176 at 1080p. Effectively constant, which is the point.

  **A hypothesis of mine was wrong and is recorded so it is not re-derived.** I
  expected PX-2's move to `disabled` stretch to have already changed the CRT,
  since the old fractional canvas scaled everything. It did not:
  `FRAGCOORD` is device pixels under *both* stretch modes. Measured at
  1920 x 1080, the scanline period is 2px under `native` and 2px under
  `legacy_fractional`, amplitudes 0.0278 vs 0.0279. The small whole-frame
  difference between those two captures (mean 1.89, peak 9) is the world image
  resampling through a different canvas transform, not the CRT — a same-config
  control pair differs by mean 0.0076, which is what ruled noise out.

  **Two real bugs were found while validating this, both outside PX-5's stated
  scope, both fixed:**

  1. **`configure_for_window_height()` truncated where it had to round —
     a PX-2 defect.** A window's usable client height is never its nominal
     resolution: a nominal 1920 x 1080 window measures 1056 once the title bar
     is taken, and `1056 / 360` is 2.93, which truncation turned into x2. So a
     maximised 1080p window rendered its UI at the same scale as a 720p one,
     losing almost a whole step to 24 pixels of window chrome. Now rounds to
     nearest, mapping the real measured client heights (696 / 1056 / 1416) onto
     the intended 2 / 3 / 4. `debug/verify_ui_scale.gd`'s cases were rewritten
     around those measured heights rather than nominal resolutions, because the
     measured ones are what the function actually receives.
  2. **`VFXDebugScene` never configured `ui_scale` at all**, so it ran at the
     default x2 regardless of window size — silently failing to reproduce the
     game and making it useless for judging anything that scales, including the
     CRT pitch it exists to tune. It now makes the same first-statement call
     `BattlePresentationController` does.

  **A third bug was in my own measurement tool, caught before it was trusted.**
  The first `debug/measure_scanline_pitch.gd` scored "rows N apart differ",
  which grows with N on any smooth gradient regardless of scanlines; it
  confidently reported 11px periods on frames whose real period was 4px.
  Replaced with a detrended periodogram, which reports a single sharp peak.
  The lesson generalises and matches the one already in `docs/LEARNINGS.md`
  from the `set_look_parameter` no-op: measure the output, then sanity-check
  the measurement against a case whose answer is known.

  **Verified.** Scanline period measured off the rendered frame (not read from
  the uniform): 4px at 1280 x 720 (ui_scale 2), 6px at 1920 x 1080
  (ui_scale 3) — both exactly `2 * ui_scale` as intended. All four PX
  verifiers still PASS after the ladder change; both scenes load clean.

  **Not verified:** ui_scale 4. This machine's display clamps a requested
  2560 x 1440 window down to 1924 x 1056, so the x4 rung has only ever been
  exercised through `configure()` directly in the verifiers, never rendered.
  Anyone with a larger display should look at it before assuming it is right.
- **PX-6** — **done. The plan is complete.** All of PX-1, PX-2, PX-3, PX-4 and
  PX-5 are marked done by this item.

  **The real game was launched and looked at**, which is the one thing none of
  the preceding items did. `debug/validate_px6.gd` (new, gitignored) drives the
  actual `Battle25D` scene rendered — setup, confirm, CPU turns, into a live
  player turn via the real input routing — and captures the shipping HUD at a
  given window height. Reuses `debug/drive_battle.gd`'s established path
  because that path is already known to reach a real turn.

  **Judged at `ui_scale` 2 (1280 x 720) and 3 (1920 x 1080 => 1056 client):**
  text is crisp at both, with no uneven stems anywhere — the defect that opened
  this cycle is gone in the real game, not just in a specimen. The cursor sits
  correctly in its gutter and scales with the window. Resonance bars render
  their three cells with a legible outline at both scales. Command and spell
  windows dock correctly with `WINDOW_STACK_GAP` between them, the command
  window dims correctly when the spell window takes focus, and the spell
  window's two-column layout holds. Both status windows dock to their corners.
  **The x2 capture is the pre-change layout exactly**, which is the strongest
  confirmation available that the whole design-unit conversion was the promised
  no-op at today's shipping scale.

  **PX-6 found and fixed a real defect, per the plan's own rule that final
  validation fixes what it finds.** Rendering at x3 showed the HUD creeping
  toward the screen edges and the prompt sitting too high: PX-4 migrated every
  window *width* but left the positional literals placing those windows —
  `STATUS_WINDOW_MARGIN` (20), prompt top (24), `TURN_ORDER_TOP` (100), and the
  forecast gap (8) — as unscaled numbers. Windows grew; their margins did not.
  All four are now `NoggTheme` design units (`SCREEN_MARGIN`, `PROMPT_TOP`,
  `TURN_ORDER_TOP`, `FORECAST_GAP`), added to `verify_ui_scale.gd`'s
  no-op-at-x2 baseline, and confirmed to reproduce their historical values
  exactly at x2. This is the same class of miss as PX-4's own SCREAMING_CASE
  gap, and it is the reason a rendered pass is not optional: no amount of
  headless measurement surfaces "the margins look wrong relative to the
  windows."

  **One defect found and deliberately NOT fixed here**, recorded in
  `BACKLOG_CRITICAL.md` instead: the prompt window renders behind the developer
  HUD at x2 and its text is partly unreadable. Established as **pre-existing**
  rather than cycle-caused by the x2 capture being byte-identical to the
  pre-change layout, and by the arithmetic — the prompt is centred and the dev
  bar's panel already reached past its left edge at the old, narrower width.
  Fixing it means deciding whether a player-facing prompt outranks developer
  chrome positionally, which `docs/UI_DESIGN.md` §9 does not currently answer;
  that is a design decision, not a mechanical fix, so it is not smuggled into a
  validation item.

  **Consolidated final checks, all passing:** `verify_ui_scale` (all 27 tokens
  reproduce their pre-cycle values at x2; whole device pixels at x1/x2/x3/x4;
  scale ladder correct against measured client heights),
  `verify_px3_geometry`, `verify_px3_damage_number`, `verify_px4_widths`,
  the pre-existing `verify_status_layout`, and a clean headless load of
  `Battle25D` with zero errors.

  **Known limits of this validation, stated rather than papered over:**
  `ui_scale` 4 was never rendered — this machine's display clamps a requested
  2560 x 1440 window to 1924 x 1056 — so the x4 rung is verified only through
  `configure()` in the verifiers. Live window *resizing* was not exercised
  either, because PX-2 deliberately fixes `ui_scale` for the process lifetime;
  what was confirmed is that launching at different sizes produces the right
  scale, which is the behaviour that actually ships. Marquee overflow, paging,
  and the confirm window were not driven — no shipping content currently
  overflows or pages, so there was nothing real to exercise them with.

---

## 7. Follow-on: Nogg Terminal adopted as the battle UI face

**2026-08-10, after the cycle above closed.** Requested directly rather than
planned, and recorded here because it changes tokens the cycle above measured.

`GAME_FONT_PATH` is now `assets/Fonts/NoggTerminal/NoggTerminal.res` and
`WINDOW_FILL` is the warm `(0.075, 0.058, 0.042, 0.86)` picked earlier in the
specimen. The two are one decision: the face's edge treatment is a drop shadow,
and a dark shadow on the old near-black panel is invisible by construction.

**Four traps this face carries, all of them previously documented and all hit:**

1. **`_load_pixel_font()` could not load it.** A baked `FontFile` resource
   already contains its glyph cache; `load_dynamic_font()` on a `.res` yields an
   empty font. The loader now branches on extension.
2. **Widths had to be re-measured, not converted.** The face is a third wider
   (16 px advance at size 24 against XenoText's 12 px). `PROMPT_WIDTH`
   360 -> 470, `FORECAST_WIDTH` 260 -> 340, `TURN_ORDER_WIDTH` 150 -> 275.
   `COMMAND_WIDTH`, `SPELL_WIDTH` and `STATUS_WINDOW_WIDTH` already had headroom.
3. **`FONT_SIZE_FOOTER` had no honest size.** 20 is not a whole multiple of the
   face's 12px nominal, and `FIXED_SIZE_SCALE_INTEGER_ONLY` floors rather than
   interpolates, so it would have rendered at 12 inside a window sized for 20.
   Now 24 — the same size as body text, so the footer/body distinction has to
   come from colour or spacing. Tracked in `BACKLOG_LONGTERM.md`.
4. **`OUTLINE_SIZE` is a cache key, not a pixel count, and must not scale.**
   The face ships baked outline variants at widths 0/1/2; requesting a width
   with no baked variant draws no outline **silently**. Scaling it would have
   asked for width 3 at x3 and lost the outline on exactly the screens where
   text is largest. It is now an unscaled `const 1`, and game text ships with
   `outline_size = 0` plus the drop shadow instead.

**Two measurement errors of mine, both caught by rendering rather than by
arithmetic:**

- The status window was briefly sized against `"Elements" / "Fire, Wind, Ice,
  Darkness"` — a layout that does not exist. Its stat rows are fixed cells at
  `STATUS_CELL_OFFSETS`, and the third column holds a two-character element code
  plus a drawn `ResonanceBar`. Measured against the geometry
  `NoggWindow.add_stat_row()` actually builds, the binding cell needs 243 units,
  which the existing 270 already covered — so this window needed **no** change,
  where the wrong measurement said it needed widening to 288.
- `TURN_ORDER_WIDTH` was first sized to a bare monster name and shipped a
  window that truncated mid-word on screen ("Envoy of Lig#100"). The rows are
  `"<marker>  <name>"` against a `"#<id>"` value column; the worst real row needs
  264 units. Only visible by looking.

**Verified.** All four PX verifiers PASS (`verify_ui_scale`'s baseline updated
for the two deliberate token changes, with the reasons recorded inline rather
than the checks deleted). `Battle25D` loads headless clean. Rendered through
`debug/validate_px6.gd` at ui_scale 2 and 3: the face renders crisply at both,
the warm fill reads, the turn-order row fits, status cells and resonance bars
fit, and the spell window keeps its two-column layout.

**Known open:** the prompt window's collision with the developer HUD
(`BACKLOG_CRITICAL.md`) is more visible now that the prompt is wider — the
prompt is unchanged in position, but its frame reaches further. Still a
game-vs-dev layering decision, still not made here.
