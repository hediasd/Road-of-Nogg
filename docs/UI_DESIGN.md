# UI / UX Design

Status: authoritative for battle UI presentation. Last restyled 2026-08-03.

This document owns the *visual and interaction language* of the battle HUD:
the window frame, the selection cursor, the input model, the theme tokens, and
the split between game UI and developer UI. It does not own gameplay
semantics — turn structure and command meaning live in
[`GAME_DESIGN.md`](./GAME_DESIGN.md), and node ownership lives in
[`ARCHITECTURE.md`](./ARCHITECTURE.md).

This document is the contract: the six traits below are settled and
implemented. Any future build work against this document belongs in
[`BACKLOG_CRITICAL.md`](../BACKLOG_CRITICAL.md) or
[`BACKLOG_LONGTERM.md`](../BACKLOG_LONGTERM.md) depending on urgency, not in a
transitory plan file, so nothing here cites a plan item by name.

---

## 1. Reference and intent

The target is the supplied PS1-era dialogue-window language: a narrow
cool-white rim with a restrained violet cast, a near-black transparent body,
and a soft black silhouette that leaks beyond the frame. The first supplied
reference contributes the faint cool glow and compactness; the second supplies
the quiet deep body and smooth exterior overdraw.

We are adopting it because it solves three problems the current HUD has:

- **Legibility over a 3D scene.** A thin outlined rim, dark translucent body,
  and hard text outline keep the board visible without losing the UI.
- **Selection without occlusion.** A gutter cursor never covers row text or
  fights the rim for contrast, unlike a filled highlight bar.
- **Depth without modality.** Stacked windows show the player where they are in
  a menu tree without dimming or replacing the board.

### The six traits

All six are in scope. They are acceptance criteria, not aspiration.

| # | Trait | Rule |
|---|---|---|
| 1 | **Thin shared halo frame** | Every game window uses the shared `NoggWindow` halo, body, and rim from `NoggTheme`. No local border, shadow, or colour literal appears in game UI. |
| 2 | **Gutter cursor sprite** | Selection is a cursor node's position, never a background fill and never a text prefix. The cursor bobs continuously and tweens between rows, and sits in a reserved gutter clear of both the rim and the text. |
| 3 | **Stacked sibling windows** | A submenu is its own window opening to the right of its parent. The parent stays on screen with **both its rim and its content** tinted to the inactive state. |
| 4 | **List rows and status cells** | Lists keep a left label and right-aligned value against the frame's inner edge; never centre or wrap them - hard-truncate instead (`OVERRUN_TRIM_CHAR`). Docked status readouts are the exception: fixed cells start at x=0, 192, and 384, keeping each label/value unit together. |
| 5 | **Paging, not scrolling** | Windows are fixed-height. Overflow pages, with a `n / m` footer window straddling the parent's bottom border, its arrows drawn rather than typed. |
| 6 | **Docked context windows** | Secondary readouts (actor status, target info) dock to fixed screen corners and never move or resize with content. |

---

## 2. What a Theme is, and why we need one

A **`Theme`** is a Godot resource that maps `(control class, property name)`
to a value, and is inherited down the node tree from whatever Control or
Window it is assigned to. Assign one `Theme` at the battle `CanvasLayer`'s root
Control and every `Label`, `Button`, and `PanelContainer` beneath it picks up
its fonts, colours, styleboxes, and spacing constants automatically.

Three kinds of entries matter to us:

- **StyleBox** — the drawn background of a control (`Panel/panel`,
  `Button/normal`, `Button/hover`, …). This is where the window frame lives.
- **Font / font size / font colour** — including `font_outline_color` and
  `outline_size`, which is how we get the hard black outline that makes text
  survive over a bright 3D scene.
- **Constants** — separations, margins, and paddings.

The project uses a code-built `Theme` at the game UI root. `NoggTheme.gd` is
the single source of truth for game-window colours, fonts, spacings, and
styleboxes; the practical consequence is that a restyle stays a shared-system
change instead of a collection of drifting local edits.

### How we author it

**As GDScript, not as a hand-written `.tres`.** `NoggTheme.gd` exposes the
token constants and a `build_game_theme()` / `build_dev_theme()` pair that
return fully-populated `Theme` objects.

The tradeoff is deliberate: a `.tres` gives live preview in the Godot editor,
which we lose. In exchange we get a theme that is diffable in review, editable
without opening the editor, and — decisively for this repository — safely
editable by an agent, which a 400-line serialised `.tres` with `SubResource`
back-references is not. The project builds all of its UI procedurally already,
so a code-built theme is also the consistent choice.

**The tokens are the contract.** No colour literal may appear anywhere in
`src/presentation/` outside `NoggTheme.gd`. That single rule is what makes the
whole restyle a one-file edit next time.

---

## 3. Design tokens

### Game palette

| Token | Value | Use |
|---|---|---|
| `WINDOW_FILL` | `#030305` @ `0.76` | Near-black translucent body; the board reads through it |
| `WINDOW_FILL_DEEP` | `#010102` @ `0.90` | Confirm/modal body that must not be read through |
| `HALO_FILL` | `#000000` @ `0.28` | Expanded soft backplate outside the rim |
| `HALO_SHADOW` | `#000000` @ `0.58` | Smooth exterior shadow, never neon glow |
| `FRAME_ACTIVE` | `#E6E0FF` | Pale-violet rim for the window holding focus |
| `FRAME_INACTIVE` | `#625B78` | Subdued rim for a parent window whose child has focus |
| `TEXT_PRIMARY` | `#F4F1FF` | Row labels |
| `TEXT_DIM` | `#827C96` | Disabled entries |
| `TEXT_ACCENT` | `#FFD766` | Right-column values and headings |
| `TEXT_FORECAST` | `#B8D9FF` | Damage/hit forecast line |
| `CURSOR` | `#FFC63A` | Selection cursor |
| `OUTLINE` | `#000000` | Opaque font outline |

Layout tokens that matter to more than one item:

| Token | Value | Meaning |
|---|---|---|
| `FRAME_RING_PX` | 2 | Thin rim thickness in screen pixels |
| `WINDOW_CORNER_RADIUS` | 6 | Shared rounded geometry for halo, body, and rim |
| `HALO_OUTSET` | 6 | Extra backplate extent beyond the layout bounds |
| `HALO_SPREAD` | 10 | Soft black shadow spread in screen pixels |
| `CONTENT_INSET` | 12 | Rim plus 10 px breathing room; where content starts |
| `ROW_HEIGHT` | 26 | Body-font line box plus 2 px air |
| `ROW_CAPACITY_DEFAULT` | 8 | Rows per window before paging |

`ROW_HEIGHT` cannot go below the font height - a `Label` enforces its own
minimum, so a smaller value is silently ignored rather than tightening further.

Animation timings live in `NoggTheme.gd` for the same reason as the colours:
the window, the cursor, and the pager all read them, and drift between them
would read as three different menus.

`FRAME_ACTIVE` -> `FRAME_INACTIVE` is a **tween over 0.12 s**, not a snap. It
is the only thing telling the player which window their arrow keys are driving.

### Dev palette

Deliberately drab, and deliberately not on-brand. Developer controls must never
be mistakable for game affordances.

| Token | Value |
|---|---|
| `DEV_FILL` | `#101418` @ `0.92` |
| `DEV_BORDER` | `#3A4450`, 1px, square corners |
| `DEV_TEXT` | `#C6CED8` |

### Typography

- **Game:** `assets/Fonts/xenotext.otf`, reporting `XenoText` Regular. Render
  at integer sizes with antialiasing, hinting, and subpixel positioning disabled
  by default: its 24 px body face is 19 px tall and carries a 12 px monospace
  advance. Body `24`, heading `24`, footer `20`; `font_outline_color = OUTLINE`
  and `outline_size = 2` on every game text entry. The disabled smoothing is a
  visual calibration decision; final normal-window validation may enable it
  only if XenoText proves materially less legible without it.
- **Dev:** `assets/Fonts/Roboto-Regular.ttf` at `13`, no outline.

At 24 px, XenoText's longest authored spell name measures about 360 px before
its value column, compared with roughly 720 px in the outgoing Shining Force
face. Existing window widths and docks stay fixed; the recovered space is
intentional breathing room, not permission to grow or move panels.

`shining-force-ii-small.otf` remains available as a comparison font but is no
longer the game UI face. `Shining Force 2.ttf` and `PressStart2P` remain
non-shipping candidates for the reasons recorded before this migration.

### Glyph coverage is a hard constraint

Validate XenoText with `Font.has_char()` in the preview harness rather than by
eye. A missing glyph does not render as a visible tofu box: Godot silently
substitutes a system font, so the mismatch can look merely wrong rather than
broken.

**Rule: every UI symbol is drawn with `_draw()`, never typed.** The cursor and
pager arrows remain drawn even if XenoText provides a matching glyph. This
keeps UI weight and fallback behavior independent of the installed font.
### Casing: caps for chrome, mixed for names

Command labels and menu chrome render in **UPPERCASE** (`MOVE`, `UNDO`,
`< BACK`). Proper nouns — spell names, monster names — stay mixed-case
(`Lightningbolt`, `Blue Crowned Pidgeon`), as does prose like the prompt line.

Caps put the commands in the right register: they read as fixed menu chrome
rather than as content, which is the 16-bit console-menu convention the frame
is already imitating. Names are excluded because all-caps strips the
ascender/descender word shapes that make an *unfamiliar* name scannable, and
names are exactly the strings most likely to be long and truncated.

**This costs nothing in width.** The shipping font is monospace — measured
2026-07-31, every command label is byte-for-byte the same pixel width in either
case — so the §8 measurements are unaffected and the choice is purely
aesthetic.

Apply it at render time, never in the model. `PlayerTurnController` keeps
returning `"Undo Move"`; `PlayerCommandMenu.UPPERCASE_COMMANDS` is the single
switch, because those strings also feed logs and harness assertions.

For text truncation, use `TextServer.OVERRUN_TRIM_CHAR` (hard cut).
`OVERRUN_TRIM_ELLIPSIS` is not an option — `…` is one of the missing glyphs, so
every truncated row would pull in a fallback font for its final character.

---

## 4. The window system

### Smooth shared geometry

`assets/ui/MenuFull.png` remains in the repository but is no longer a runtime
window dependency. It was authored for a thick pixel-art bevel; scaling it down
cannot produce the smooth, restrained frame this contract now requires.

Every `NoggWindow` instead uses four procedural layers from `NoggTheme`, in
this draw order:

```text
NoggWindow (Control; clip_contents = false)  <- plain Control, never a Container
|- Halo (Panel): expanded translucent-black backplate and soft shadow
|- Body (Panel): near-black translucent rounded rectangle
|- Content (VBoxContainer): full rect, inset by CONTENT_INSET
`- Rim (Panel): transparent rounded rectangle with thin pale-violet border
```

The halo deliberately extends beyond the root Control, but has
`MOUSE_FILTER_IGNORE` and never contributes to layout. Halo, body, and rim take
the same `WINDOW_CORNER_RADIUS` from the theme. That single geometry source
prevents seams while allowing the halo to leak outside the box intentionally.

The root must not be a `Container`. A `PanelContainer` force-fits every child
into its stylebox content rect, which would inset the rim and cover the first
and last glyph of each row. Decorative panels are always input-transparent;
only interactive rows may stop pointer input.

### The cursor gets a reserved gutter

A window that hosts a `MenuCursor` indents its rows by `CURSOR_GUTTER_WIDTH`
on top of `CONTENT_INSET`, so the arrow occupies clear space rather than
overlapping the thin rim:

```text
0 .. 2 .... 6 ......... 16 ....... 24 ............
  |rim|      |<- cursor ->|        |<- text
                     (including bob)
```

Windows with no cursor - prompt, forecast, docked readouts - leave the indent
at zero; indenting them would only look misaligned. `CURSOR_WIDTH`,
`CURSOR_INSET`, and `CURSOR_GUTTER_WIDTH` all live in `NoggTheme` rather than
inside `MenuCursor`, because `NoggWindow` has to reserve space for a cursor it
never sees.

### Behaviour

- **Open:** scale `0.94 -> 1.0` and alpha `0 -> 1` over 0.10 s, `EASE_OUT`.
  Close is the reverse over 0.08 s. The halo follows the root's existing
  animation rather than receiving an independent lifecycle.
- **Focus:** `set_active(bool)` tweens the **rim tint and content tint**
  together over `TWEEN_FOCUS`. The black halo stays stable; it is depth, not a
  second focus indicator. A window never moves to show focus.
- **Sizing:** size on open, then hold. A window's height is fixed for the
  lifetime of one opening and pages never shrink it. Docked readouts keep their
  fixed capacity so changing values cannot jitter the layout.

---

## 5. The cursor

The cursor is the load-bearing change, and the reason the current menu has to
be refactored rather than reskinned.

Selection is presently encoded *in the row's text string* — `("› " if selected
else "  ") + label` — so `moveSelection()` calls `_rebuild_root()`, which
`queue_free()`s and reconstructs every row on every keypress. Nothing can be
animated across a rebuild.

### The rule

> **Content changes rebuild rows. Selection changes move the cursor. These are
> two different code paths and neither may call the other.**

### Spec

- A single `MenuCursor` node per menu, parented to the window's reserved gutter, sibling to the row list rather than a child of any
  row.
- Idle bob: `±2 px` horizontal, 0.6 s period, sine, looping.
- Move: tween `position.y` to the target row's centre over **0.09 s**,
  `EASE_OUT`, `TRANS_CUBIC`. Interrupting tweens are killed, not queued — held
  arrow keys must feel like tracking, not like a queue draining.
- Crossing into a child window: the parent's cursor hides and the child's
  cursor appears already at its default row. The cursor does not fly between
  windows.
- Rows are plain `Control`s with a two-column `HBoxContainer`, **not
  `Button`s**. Buttons bring focus rings, default hover styleboxes, and a
  keyboard focus model we would spend the whole item fighting.

---

## 6. Input model

Keyboard and mouse are both first-class, and they resolve to the same state:
**the cursor position is the only selection truth.** Mouse hover does not
"preview" a different selection than the keyboard's — it *moves the cursor*.
This is what keeps the two devices from disagreeing.

| Input | Action |
|---|---|
| `ui_up` / `ui_down` | Move cursor one row, wrapping within the page |
| `ui_left` / `ui_right` | Previous / next page |
| `ui_accept` | Activate the cursor's row |
| `ui_cancel` | Close the focused child window; if root, cancel the phase |
| `T` (held during a player turn) | Show the enemy danger zone; release to restore the current movement/target overlays |
| Mouse motion over a row | Move the cursor to that row (no activation) |
| Left click on a row | Move the cursor there, then activate |
| Left click on `◀` / `▶` | Page |
| Right click | Same as `ui_cancel` |
| Mouse wheel over a window | Move cursor one row |
| Left click on the pending target tile, during `CONFIRM_ACTION` | Confirm — same as clicking `CONFIRM` |
| Left click anywhere else on the board, during `CONFIRM_ACTION` | Cancel — same as clicking `CANCEL` |

During TARGET_SELECT, spell aiming gives the vertical pair a different meaning: up and down cycle ready spells, recompute the legal target set, and keep the current tile only when it remains legal. Left and right continue cycling legal targets. Attack aiming keeps all four directions on target cycling.

Disabled rows are skipped by keyboard movement and are inert to hover and
click. They render in `TEXT_DIM` and are never hidden — a spent `Move` must
stay visible so the player can see *why* it is unavailable.

The two board-click rows are a second path to the same two outcomes the
confirm window already offers, not a competing one: during `CONFIRM_ACTION`
the cursor no longer moves (§5's cursor-position-is-truth rule does not apply
to the board — there is nothing left to aim, only to commit), so a board click
cannot disagree with the window. Clicking the target tile and clicking
`CONFIRM` reach `confirmSelection()`; anything else on the board and clicking
`CANCEL` both reach `cancel()`.

---

## 7. Overflow

Two kinds, handled differently: too many rows pages, too wide a row scrolls.

### 7a. Vertical — paging

Fixed capacity, currently **8 rows** per window. Overflow pages.

The footer is its own small `NoggWindow`, horizontally centred and overlapping
the parent's bottom border by half its height, reading `2 / 7` between two
arrows. It is present only when `page_count > 1`; a single-page window shows no
footer at all rather than a disabled `1 / 1`.

**The arrows are drawn, not typed.** `◀` and `▶` are absent from
the shipping font and fall back to a system font — see §3. Draw them with
`_draw()` as filled triangles in `TEXT_ACCENT`, mirroring `MenuCursor`, so the
pager and the cursor are visibly the same family of shape.

Cursor movement past the last row of a page advances to the next page and
lands on its first row. Paging is circular in both directions.

### 7b. Horizontal — truncate at rest, scroll on focus

A row that does not fit is hard-truncated (§3). That is the resting state and
it never changes. But a truncated row hides information the player may need —
`Closing of the Third San` and `Closing of the Third Sanc` are indistinguishable
— so **the row under the cursor scrolls its label after a delay**, revealing the
rest, then returns.

| Phase | Timing |
|---|---|
| Cursor lands, text held still | `MARQUEE_DELAY` 1.2 s |
| Scrolls left at a constant rate | `MARQUEE_SPEED` 40 px/s |
| Holds at the end | `MARQUEE_END_HOLD` 1.0 s |
| Snaps back to the start, holds, repeats | `MARQUEE_DELAY` again |

Five rules, each of which exists because the obvious alternative reads badly:

1. **Only the focused row ever scrolls.** Every overflowing row animating at
   once is noise, and it makes the window look broken rather than informative.
   This is what DQ and FF do.
2. **Constant speed, not constant duration.** A fixed duration makes a long
   name scroll fast and a barely-overflowing one crawl. Distance ÷ speed keeps
   every row legible at the same reading rate.
3. **The delay is not optional.** Without it, arrowing down a spell list fires
   a scroll on every row the cursor passes through, which is far worse than
   truncation. 1.2 s is longer than a deliberate keypress and shorter than a
   pause to read.
4. **Snap back, do not scroll back.** Reversing reads as indecision and doubles
   the time before the player sees the start again.
5. **Leaving the row resets immediately** — no easing out, no finishing the
   cycle. The row must be back at its start before the cursor's move tween
   lands, or the two animations fight.

Rows that fit never scroll and never delay; the behaviour is invisible until it
is needed.

**Marquee is reserved for content the player is choosing between — spell
names — not for passive status readouts.** The actor/target windows' `Elements`
row was briefly wired to marquee too, on the reasoning
that any overflowing row should get the same treatment "for free." Reversed on
design review: a status window is read, not navigated, and there is no cursor
to justify drawing the eye to one row over the others. An overflowing
`Elements` combo (`water, darkness`, `fire, darkness` — see §8) simply stays
truncated, like every other value in that window.

Implementation is a `clip_contents = true` wrapper around the label with its
`position.x` tweened. It applies to the **label column only** — the value column
(`Rng 3`, `CD 12`) is right-aligned against the frame and must stay anchored, or
the two columns slide across each other.

---

## 8. Window taxonomy

Every game window, its dock, and its size.

Widths are **measured, not chosen** — `debug/preview_theme.gd` prints the
requirement for each window's worst-case real catalogue content at the shipping
font and size. Rerun it if the font, the font size, or `CONTENT_INSET` changes;
all three move these numbers. The figures below are at **size 24**, and the
budget they have to fit inside is Godot's default **1152 × 648** logical base.
The project uses `canvas_items` stretch mode with `expand` aspect: every 2D
panel scales from that base while the logical rect expands with the window's
aspect ratio, so the existing resize-driven docks remain active and no
letterbox bars appear. The world SubViewport uses the real window size when
retro rendering is disabled, preserving native 3D sharpness; screen/world input
mapping remains in the root viewport's logical coordinate space.

| Window | Dock | Size | Contents |
|---|---|---|---|
| **Command** | Left, vertically centred | 220 x 5 rows | `MOVE / UNDO / ATTACK / SPELL / PASS` - existing width retained for compatibility and deliberate breathing room; 5 is the list's true maximum |
| **Spell** | Right of Command, `WINDOW_STACK_GAP` | 680 × up to 8 rows | Sized to the monster's spell count + `< BACK`, capped at 8; pages beyond that. Two-column: spell name left, `Rng N` / `CD n` right in `TEXT_ACCENT` |
| **Turn order** | Upper-left, x=20 / y=100 | 300 × 3 rows | Up to three entries: NOW for the active unit, NEXT for the next unit, and UP for the following queued unit |
| **Actor status** | Bottom-left, fixed | 540 × 6 rows | Name heading in `TEXT_ACCENT`; fixed-cell `HP`, `ATK`/`DEF`, and `SPD`/`MOV` rows, with authored element codes and three-cell Resonance bars in column 3 |
| **Target** | Bottom-right, fixed | 540 × 6 rows | Same fixed-cell shape as actor status; shows an empty frame, not a hidden window, when there is no target |
| **Confirm** | Same origin as Command, replacing it | 220 × 2 rows | `CONFIRM / CANCEL`. Docked on top of the command window rather than beside it so the cursor does not travel when the phase changes; the command window hides rather than dimming, because confirm replaces the command list instead of descending from it |
| **Forecast** | Above Command, **left-aligned** with it | 460 × 2 rows | Hit chance and damage range in `TEXT_FORECAST`; visible while aiming *and* while confirming |
| **Prompt** | Top-centre | auto, 1 row | `Select a destination`, `Select a target` — replaces today's status label |
| **Battle log** | Right edge, full height | scrolling | The one deliberate exception to trait 5; a log is a scrollback, not a menu |

Command + gap + Spell is 908 of 1152. Actor + Target is 1080 of 1152. Both fit,
but the status pair has little room left — **size 24 is close to the ceiling
this viewport supports** for the two-window layouts. Going larger means either a
bigger default window size or dropping to one status window at a time.

XenoText at size 24 leaves materially more horizontal room while the logical
1152 x 648 layout stays unchanged. The longest authored spell name is expected
to fit inside the existing 680 px spell window beside `CD 12`; the preview
harness owns the final Godot measurement. Status-cell columns likewise retain
their current positions, using the extra width for scanability rather than a
layout migration.
**The forecast is left-aligned, not right-aligned.** This table originally said
right-aligned to the command window; that cannot hold at size 24. The forecast
needs ~460px and the command window's right edge is at x=300, so right-aligning
would place its left edge off-screen. Corrected against the real metrics once
the body font size was settled at 24.

The bottom HUD uses fixed status cells rather than list rows: `HP` occupies the
first cell, `ATK`/`DEF` and `SPD`/`MOV` hold vertical columns at 0 and 192px,
and the 384px cell displays authored element codes beside drawn three-cell
Resonance bars. Text values remain separate
Labels, so HP can still turn `TEXT_ACCENT` under its threshold without treating
the readout as an interactive menu.

Every numeric value in these cells is zero-padded to three digits (`004`, not
`4`) — the range `Monster.STAT_MIN`/`STAT_MAX` clamp every stat to, so a value
never grows or shrinks a fixed cell's content width as it changes turn to
turn. Measured against the shipping font: `ATK`/`DEF`/`SPD`/`MOV` each need
168px of their 192px column, and `HP`'s combined `999 / 999` needs 288px of
the 384px it has before the Resonance cell begins — both comfortably inside
budget with real font metrics, not estimated.

---

## 9. Game UI vs developer UI

The game-window language stays distinct from the debug HUD so player controls never read as developer affordances. The developer layer holds pause, a speed slider, new battle, graphics, screenshot, save replay, and the battle log. Skinning a frame-pacing slider in ornate JRPG chrome would
teach the player it is a game mechanic.

### The split

Two `CanvasLayer`s, two themes, one rule.

| | Game layer | Dev layer |
|---|---|---|
| Layer | `10` | `20` (always above) |
| Theme | `build_game_theme()` | `build_dev_theme()` |
| Holds | Command, Spell, Actor, Target, Forecast, Prompt, Log | Top bar, graphics menu, screenshot, save replay |
| `F1` | **unaffected** | toggles visibility |

`F1` toggles the dev layer only, so a clean screenshot still shows the game UI
as a player sees it — which is the actual reason the key exists. It was
`SPACEBAR` until Space turned out to be one of Godot's default `ui_accept`
binds: a dev-only toggle bound to it was swallowing the player's own accept
action during a battle.

Dev UI is off by default in a release build.

---

## 10. CRT layering

The world (backdrop + 3D scene texture) renders on a `CanvasLayer` at
`NoggTheme.CRT_LAYER` (-20). The CRT shader itself — `crt_display.gdshader`,
which reads `hint_screen_texture` and therefore distorts whatever was already
drawn to screen at the moment its own canvas item draws — lives on a
**separate** `CanvasLayer`, `crt_overlay_layer`, precisely so its layer number
can move independently of both the world and the game UI.

By default `crt_overlay_layer` sits at `CRT_OVERLAY_LAYER_DEFAULT` (-10):
above the world, below the game UI (`GAME_LAYER`, 10). The UI therefore
renders after the CRT pass has already finished and receives no scanlines,
mask, or vignette. **This is a decision, not an accident of layer numbers:**
crisp menus over a filtered scene is the standard retro-styled-modern
convention, it keeps the pixel font readable at every scanline strength, and
it prevents the thin rim from shimmering as the mask size changes.

A `ui_through_crt` toggle in the graphics menu's CRT tab moves
`crt_overlay_layer` to `CRT_OVERLAY_LAYER_THROUGH_UI` (`GAME_LAYER + 1`)
instead — now the game UI draws *before* the CRT pass, so its
`hint_screen_texture` sampling captures and distorts the UI too. Both layer
values stay below `DEV_LAYER` (20), so the dev bar is never affected by this
toggle either way. Default off; persisted alongside the other rendering
settings, independent of which visual preset is active. Watch the
`_load_settings()`/`_apply_settings()` ordering trap this ran into: the setting
loads before the node that would apply it exists, so applying it at load time
silently does nothing.

---

## 10a. Board-space model treatments

Two treatments read *on the models themselves* rather than in a window, both
as uniforms on `retro_surface.gdshader` that default to inert so nothing
changes until something opts in.

| Treatment | Uniform | Applied to | Means |
|---|---|---|---|
| **Spent** | `dim_amount` | the active unit, once it has spent Move or Act | the same thing a dimmed command row means: still there, no longer available |
| **Not being chosen between** | `dither_amount` | every model except the active unit and the one under the pointer, during move and target select only | the board reads *through* the units while a tile is being picked |

**Dither, not alpha fade.** The treatment is screen-door transparency — a 4×4
Bayer threshold on `FRAGCOORD` with `discard` — not blended alpha. It holds
depth writes, needs no transparency sorting, and is what the hardware this
scene imitates actually did. Two details are load-bearing: the pattern is
anchored to `FRAGCOORD` rather than UV, because a UV-space pattern swims
across a model as it turns and reads as a texture bug; and the cell is 4×4
rather than 2×2 so the weave survives the render downsample and the CRT
upscale instead of flattening into a haze.

**Dither strength is deliberately partial** (`DITHER_STRENGTH`, 0.55). A fully
discarded model is an invisible one, and the point is that the player can see
past the units, not that units vanish.

Gaining hover waits out a short dwell before a model is restored to solid;
losing it takes effect immediately. Without the dwell, a pointer swept across
a crowded board restores each model it crosses for a frame or two, which reads
as flicker.

---

Move select draws reachable tiles in blue. It also draws the union of tiles
that can be attacked from any reachable destination in purple, excluding
tiles already reachable so movement remains the stronger signal. The hovered
path is drawn in yellow over both sets. These are presentation-only previews
and use the same movement and combat resolver queries as command validation.

---

## 10b. Threat overlay

The held T key shows the **danger zone**: the union of every tile that a
living enemy can reach with movement and then threaten with a damaging spell or
basic attack this round. It is computed once when the key is pressed, not every
frame. The overlay uses a magenta-red tint (0.95, 0.16, 0.48, 0.40),
distinct from movement blue, target yellow, and affected-area red/green.

The threat layer is additive to the current tactical layer. Releasing T
removes only the danger zone, so a player holding it during movement or target
selection gets the exact overlay they were already using back. The key is inert
outside an active player turn and is cleared at turn end and battle end.

---

## 11. Open knobs

Deliberately unresolved; revisit after the first playable pass.

- **Frame scale at high resolution.** The 9-patch border is 16 physical px. At
  1440p+ it reads thin. Options are a pre-scaled 96×96 asset or an integer
  `Control` scale on the frame. Not worth deciding before the layout is on
  screen.
- **Row capacity.** 8 is a guess. If spell lists routinely run 9–12, a 10-row
  window may beat paging for the spell window specifically.
- **Window open sound.** DQ's window language is half audio. No audio system
  exists yet; noted so the hooks are not designed out.
