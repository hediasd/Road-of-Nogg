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
| 3 | **Stacked sibling windows** | A submenu is its own window opening to the right of its parent. The parent stays on screen with **both its rim and its content** tinted to the inactive state. The action ring is the one exception, and only because it is not docked beside its child: it hides rather than dimming when the spell list opens (see §8). |
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
| `WINDOW_FILL` | `#131007` @ `0.86` | Warm dark translucent body; the board reads through it, and the font's drop shadow reads against it |
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

- **Game:** `assets/Fonts/NoggTerminal/NoggTerminal.res` — **Nogg Terminal**,
  the in-house bitmap face described in the next section. Drawn on an 8 x 12
  design cell with an 8-unit monospace advance, so at the shipping x2 scale it
  is a **24 px body with a 16 px advance**. Sizes are `FONT_SIZE_*_UNITS *
  ui_scale` and must stay whole multiples of 12; the face floors anything else.
  Default edge treatment is the drop shadow (`SHADOW_OFFSET`, `SHADOW_COLOR`),
  not the halo — see "Edge treatment" below.
- **Dev:** `assets/Fonts/Roboto-Regular.ttf` at `13`, no outline. A dynamic
  face, so it is exempt from the whole-multiple rule.

**The face is a third wider than the XenoText it replaced** — 16 px advance
against 12 px at the same size — so every window width in `NoggTheme` was
re-measured against it on adoption rather than inherited. `PROMPT_WIDTH`,
`FORECAST_WIDTH` and `TURN_ORDER_WIDTH` had to grow; `COMMAND_WIDTH`,
`SPELL_WIDTH` and `STATUS_WINDOW_WIDTH` already had the headroom. Re-run
`debug/measure_px4_widths.gd` if the face, a font size unit, or
`CONTENT_INSET` changes.

`xenotext.otf` stays in the repo as `XENOTEXT_FONT_PATH` and remains selectable
in the VFX debug scene's text specimen (`--text-font=game`) for comparison. `Shining Force 2.ttf` and `PressStart2P` remain
non-shipping candidates for the reasons recorded before this migration.

### Nogg Terminal — the in-house pixel face

A bitmap face drawn for this project, in the register of the `.hack` system
font: monospaced, octagonal, flat-terminalled, generously spaced. It is **not
the shipping UI face** — see the adoption cost at the end of this section — but
it is fully built and testable.

**It is authored as text, not as an image.** `assets/Fonts/NoggTerminal/glyphs.txt`
holds every glyph as ASCII art and is the only file anyone edits. The atlas PNG
and the `FontFile` beside it are build outputs of
`scripts/bake_bitmap_font.gd`. That inversion is the whole point: a glyph tweak
is a one-line diff a reviewer can read, rather than an opaque binary blob, and
the baker validates the source strictly enough that a malformed glyph fails the
build instead of shipping as a garbled letter.

The grid: an 8 x 12 cell, advance 8, ascent 9, descent 3. Rows 1-8 are the
cap/ascender band, rows 4-8 the x-height band, rows 9-10 descenders. Bodies
occupy columns 1-6; symmetric glyphs use columns 1-5 so their centre stem lands
on column 3.

Five style rules keep 95 hand-drawn glyphs reading as one face, and are
restated at the top of the source so they are in front of whoever edits it:
one-pixel stroke everywhere; round letters are octagons with corners clipped
exactly one pixel; terminals flat and grid-aligned; diagonals are single-pixel
staircases; counters at least two pixels wide so they survive the retro
viewport's downsample.

**Two things about it behave unlike a dynamic font, and both are load-bearing.**

*Sizes are whole multiples only.* The face declares `fixed_size = 12` with
`FIXED_SIZE_SCALE_INTEGER_ONLY`, so size 24 renders at exactly 2x and 36 at 3x.
A size that is not a multiple of 12 is floored rather than interpolated — which
is correct, but means `FONT_SIZE_FOOTER = 20` has no honest rendering.

*Outlines are baked, and `outline_size` is a cache key rather than a pixel
count.* Godot cannot synthesize an outline for a bitmap face, so widths 1 and 2
(in design pixels) are dilated into the atlas up front. Requesting a width with
no baked variant draws **no outline at all**, silently. Pass the design width
unscaled: the text server applies the fixed-size scale to whatever variant it
finds, so requesting 1 at size 24 yields a two-device-pixel halo. Pre-scaling
squares the zoom.

#### Edge treatment: shadow, not halo

**The face's own treatment is a one-pixel drop shadow down and right, and that
is what the specimen defaults to.** The reference does the same: the dark edge
sits below-right of each glyph and the top-left terminals meet the background
bare, which reads as lit type on a panel.

A symmetric halo was the first attempt and it was wrong. On a face whose
strokes are exactly one design pixel, a halo of the same width doubles the
apparent weight of every letter and starts closing the counters — the five
style rules above are calibrated for a bare stroke, and wrapping each one in
dark defeats them. It reads as a sticker rather than as type.

The shadow is drawn by the label rather than baked, so unlike `outline_size`
its offset is a plain device-pixel count and **does** scale with the zoom. Keep
`shadow_outline_size` at zero: anything larger draws the shadow from the
outline atlas and reintroduces the thickening the shadow exists to avoid.

The halo is kept, and kept baked, because the two are not interchangeable
everywhere. A shadow defends one side only. Text over a bright, arbitrary 3D
board — the case `NoggTheme.OUTLINE` was introduced for — can still need the
halo, and dropping it would trade a legibility guarantee for an aesthetic one.
Which wins where is settled by looking, in the specimen, against the actual
backdrop. Note that neither shows up against `WINDOW_FILL`: a dark treatment on
a near-black panel is invisible by construction, so judge edge treatments over
the board, never in a window.

**Adopting it would move layout.** Its 16 px advance at size 24 is a third
wider than XenoText's 12 px, so every width measured in §8 would need
re-measuring and the recovered breathing room described above would be spent.
That is a deliberate decision to take on its own, not a side effect of the face
existing.

#### Pixel fidelity: fixed by scaling tokens, not the canvas

**Historical bug, fixed by the native-canvas UI scaling change — kept here
because the reasoning still governs how geometry is authored.** `project.godot` used to set
`window/stretch/mode = "canvas_items"` with `aspect = "expand"` and author no
`viewport_width`/`viewport_height`, so Godot fell back to its 1152 x 648
default and scaled the whole canvas by `window_size / 1152`. At 1340 x 754 that
was x1.163. Combined with the project's nearest texture filter
(`textures/canvas_textures/default_texture_filter = 0`), a fractional factor
duplicated some pixel rows and dropped others: a one-design-pixel stroke landed
as two device pixels in places and three in others, within the same word. **No
font configuration could fix this** — it is a canvas problem, not a typography
one.

**It was not specific to Nogg Terminal, and it was not new.** Captured side by
side at 1340 x 754, XenoText's stems were uneven in exactly the same way: it is
also a pixel face, rendered with antialiasing and hinting disabled, so
rasterizing it at `24 x 1.163` produced stem widths the design never intended.
The shipping UI had been mildly wrong at most window sizes all along; the
bitmap face only made it obvious, because uniform strokes are its whole
premise.

The project's smooth chrome was **not** affected, and the distinction is what
made a fix affordable. `StyleBoxFlat` rims, rounded bodies and halos are
redrawn at whatever size they are given rather than resampled, so a fractional
factor cost them nothing — captured at the same two sizes, the window rim was
indistinguishable. The UI was therefore two families: resolution-independent
chrome that did not care, and resolution-dependent content — both fonts, and
the small-integer geometry in `MenuCursor`, `PagerArrow` and `ResonanceBar` —
that did. Only the second family needed defending.

**The fix: stop scaling the canvas, scale the tokens.** `project.godot` now sets
`window/stretch/mode = "disabled"` — nothing is ever resampled, and a device
pixel is a real pixel. `NoggTheme` carries `ui_scale` (default 2, matching what
the pre-fix constants already encoded) and every geometry token is authored in
*design units*, multiplied by `ui_scale` through `NoggTheme.configure()` /
`configure_for_window_height()`. `_static_init()` derives them all together on
class load, and `_scaled()`/`_scaled_int()` round every result to a whole
device pixel — that guarantee lives at the token layer once, rather than being
hoped for at each `_draw()`.

**`ui_scale` is fixed for the process lifetime.** `BattlePresentationController`
calls `configure_for_window_height()` as the first statement of `_ready()`,
before any Theme is built, and never calls it again. This was a deliberate
scope decision, not an oversight: changing `ui_scale` after Theme resources are
already built and assigned would desync two kinds of reader — a `Theme`'s font
size and styleboxes are copied in at build time and would keep the old scale,
while code that reads a token directly at draw time (`NoggWindow`'s cursor
gutter math, `MenuCursor`'s accessors) would see the new one immediately. That
disagreement is worse than not rescaling at all, and correcting it needs a
rebuild-and-relayout path for every open window — tracked in
`BACKLOG_LONGTERM.md` as live UI rescaling, not attempted in this cycle.

Measured at 1152 x 648 (x1.000, the historical baseline) every stroke was
exactly two device pixels; at 1340 x 754 (x1.163) stroke widths varied within a
single word — this was the finding that motivated the fix. The VFX debug
scene's Canvas stretch control (or `--stretch=`) can still reproduce that
fractional behavior on demand under the `legacy_fractional` preset, for
comparison; `native` matches the shipping project default. The text specimen's
pixel-fidelity readout still reports the live canvas factor, which is now x1
everywhere.

**A related finding, measured while building the fix:** a bitmap face whose
glyphs are injected into the cache does not survive a content-scale change.
Oversampling changes with the scale, that clears cached glyph data, and this
face has no source bytes to re-rasterize from — so every string falls back to a
system font with ascent and descent reported as zero. Fixing the canvas scale
at `disabled` removes the failure mode entirely, because oversampling then
never changes at runtime — this is a second, independent reason the project chose
`disabled` over an integer-scaled `canvas_items` mode. The specimen still
watches the scale and rebuilds defensively (it exercises every stretch preset,
including the ones that do change scale), but shipping code no longer needs to.

#### Looking at it

The text specimen lives in the VFX debug scene (`scenes/debug/VFXDebugScene.tscn`),
not in a flat preview page, because the only question that matters about a UI
face is whether it survives what it actually sits on — a lit board, at the
retro viewport's downsample, under the CRT pass. The specimen draws on its own
CanvasLayer at `GAME_LAYER`, so it composites exactly the way the shipping HUD
composites.

Press `X` to toggle it and `R` to re-parse `glyphs.txt` in place; editing a
glyph and pressing `R` is the authoring loop, and it is why the source is text.
Every control is also a flag (`--text`, `--text-font=`, `--text-sample=`,
`--text-scale=`, `--text-edge=`, `--text-edge-size=`, `--text-backdrop=`), so a specimen combines
with `--hide-hud`, `--capture-at=` and the scene's golden-frame comparison the
same way an effect does. The `charset` sample lays printable ASCII out sixteen
to a row, matching the baked atlas exactly: a glyph that looks wrong on screen
is findable in the atlas at the same coordinates.

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
**the selection is the only selection truth.** Mouse hover does not "preview"
a different selection than the keyboard's — it *moves the selection*. This is
what keeps the two devices from disagreeing.

**There are two selection models, and which one is live depends on the
surface.** The root command surface is the `ActionRing` (§8), where a
direction names a slot outright. The spell and confirm surfaces are still
windows with a gutter cursor, where vertical cycles and horizontal pages.
`PlayerCommandMenu.moveSelectionDirection()` is the single place the two are
dispatched between; the controller sends all four directions there rather than
branching, so the ring's geometry lives in one file.

The ring does not cycle, and that is the point. On a fixed-position control a
direction must always mean the same command or it means nothing — pressing up
with `Move` spent does nothing rather than wrapping to a neighbour. All four
directions are consumed by an open command surface whether or not it used
them, so an unused key never falls through to the camera or the board while
the player is looking at a menu.

| Input | Action |
|---|---|
| `ui_up` / `ui_down` / `ui_left` / `ui_right`, on the ring | Focus that slot; no-op if the slot's command is unavailable |
| `ui_up` / `ui_down`, in a window | Move cursor one row, wrapping within the page |
| `ui_left` / `ui_right`, in a window | Previous / next page |
| `ui_accept` | Activate the focused command / the cursor's row |
| `ui_cancel` | Close the focused child window; if root, cancel the phase |
| `T` (held during a player turn) | Show the enemy danger zone; release to restore the current movement/target overlays |
| Mouse motion over a unit on the board | Fill the docked status readout with that unit, immediately, **in every phase** |
| Mouse motion over a ring icon | Focus that slot (no activation) |
| Left click on a ring icon | Focus that slot, then activate |
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
stay visible so the player can see *why* it is unavailable. The ring applies
the same rule with `ACTION_RING_DISABLED_ALPHA`, and additionally narrows its
own hit area (`ActionRing._has_point`) to the *activatable* icons only: the
ring's bounding box is a square sitting on the board around the acting unit,
and a Control that claimed all of it would swallow clicks on that unit and up
to eight surrounding tiles.

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
| Scrolls left at a constant rate | `MARQUEE_SPEED` — 20 design units/s, 40 px/s at the shipping x2 scale |
| Holds at the end | `MARQUEE_END_HOLD` 1.0 s |
| Snaps back to the start, holds, repeats | `MARQUEE_DELAY` again |

`MARQUEE_SPEED` is the one marquee number that scales with `NoggTheme.ui_scale`:
it is a rate over a spatial unit, so it has to track the same scale
the letters it is moving do, or a long name would visibly crawl at x1 and
streak at x4 relative to its own width. `MARQUEE_DELAY` and `MARQUEE_END_HOLD`
are durations, not lengths, and correctly do not scale.

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

**Widths are measured, not chosen, and now live in `NoggTheme` as design units**:
`COMMAND_WIDTH`, `SPELL_WIDTH`, `PROMPT_WIDTH`, `FORECAST_WIDTH`,
`STATUS_WINDOW_WIDTH`, `TURN_ORDER_WIDTH`, `PAGER_WIDTH`. Each was previously a
`const` of a literal device-pixel number local to whichever file built that
window (`BattleUIBuilder`, `PlayerCommandMenu`, `NoggWindow`) — correct at the
scale it was measured at, but unable to track `NoggTheme.ui_scale`, so a window
sized to its worst-case content at x2 would clip that same content at x4, where
the glyphs inside it are twice as wide but the window holding them had not
moved. `debug/measure_px4_widths.gd` (gitignored) re-measures every one of
these against this project's actual worst-case strings — real spell names, real
monster names, real `PlayerTurnController` status/forecast text, not
placeholders — at `ui_scale = 1`, where a design unit and a device pixel are
the same number. Rerun it if the font, `FONT_SIZE_BODY_UNITS`, or
`CONTENT_INSET_UNITS` changes; all three move these numbers.

There is no width *budget* to fit inside anymore. `project.godot` used to cap
every 2D panel to a shared 1152 × 648 logical base (now replaced by
`window/stretch/mode = "disabled"` — see §3), so this table used to report a
running total against that ceiling. Under the current model each window is
simply as wide as its own worst-case content needs, independent of the others;
there is nothing left for them to compete over.

| Window | Dock | Size (design units, device px at shipping x2) | Contents |
|---|---|---|---|
| **Action ring** | Centred on the acting unit, projected per frame | `ACTION_RING_RADIUS` 26 / 52 from centre, `ACTION_RING_ICON` 16 / 32 per icon | Four command icons: Move north, Attack east, Pass south, Spell west, plus the focused command's name beneath. Replaced the docked command window — see the note below |
| **Spell** | Right of Command, `WINDOW_STACK_GAP` | `SPELL_WIDTH` 340 / 680 × up to 8 rows | Sized to the monster's spell count + `< BACK`, capped at 8; pages beyond that. Two-column: spell name left, `Rng N` / `CD n` right in `TEXT_ACCENT` |
| **Turn rail** | Top-centre, `TURN_RAIL_TOP` | `TURN_RAIL_TILE_WIDTH` 20 / 40 x `TURN_RAIL_TILE_HEIGHT` 28 / 56 per tile, up to `TURN_RAIL_CAPACITY` | Portrait tiles: a rendered model miniature, team-coloured frame, round-relative queue number, and a health strip. Crosses the round boundary with a dashed divider; entries past it are a projection and draw at `TURN_RAIL_PROJECTED_ALPHA` |
| **Actor status** | Bottom-left, fixed | `STATUS_WINDOW_WIDTH` 270 / 540 × 4 rows | Name heading in `TEXT_ACCENT`; fixed-cell `HP`, `ATK`/`DEF`, and `SPD`/`MOV` rows, with authored element codes and three-cell Resonance bars in column 3. `open()`s when a monster is showing, `close()`s otherwise — see the note below |
| **Target** | Bottom-right, fixed | `STATUS_WINDOW_WIDTH` 270 / 540 × 4 rows | Same fixed-cell shape and open/close behaviour as actor status |
| **Confirm** | Same origin as Command, replacing it | `COMMAND_WIDTH` 110 / 220 × 2 rows | `CONFIRM / CANCEL`. Docked on top of the command window rather than beside it so the cursor does not travel when the phase changes; the command window hides rather than dimming, because confirm replaces the command list instead of descending from it |
| **Forecast** | Above Command, **left-aligned** with it | `FORECAST_WIDTH` 340 / 680 × 2 rows | Hit chance and damage range in `TEXT_FORECAST`; visible while aiming *and* while confirming |
| **Prompt** | Top-centre, below the rail, own `NoggTheme.PROMPT_LAYER` | `PROMPT_WIDTH` 470 / 940, 1 row | `Select a destination.`, `Choose an action, or Pass to end the turn.` — transient, closed rather than shown empty; see the note below |
| **Battle log** | Right edge, full height | scrolling | The one deliberate exception to trait 5; a log is a scrollback, not a menu |

**The two status windows no longer show an empty frame when there is nothing
to read.** That was the original design here, on the reasoning that an empty
frame reads as "nothing selected" without a second visual language for it —
correct as far as it goes, but it also means the single largest element in the
HUD (both windows together are over a quarter of a 1152×648 frame) is
permanently drawn in a state that says nothing. `_renderStatusWindow()` now
calls the window's own `open()`/`close()` (already built for the spell list
and confirm window, complete with a scale/fade tween and a generation guard
against a close racing a reopen) whenever the monster it would show flips
between real and none. This costs nothing in layout: both windows dock at a
fixed position computed from viewport size alone, so nothing reflows off their
visibility. Both start `visible = false` at construction rather than
open()-then-immediately-close()-ing at battle start, which the Control default
of `visible = true` would otherwise do.

**The status windows are four rows, not six.** Heading, HP, ATK/DEF, SPD/MOV
is the entire content — `_renderStatusWindow()` adds exactly those and nothing
conditionally adds a fifth, since Resonance goes into a *cell* of an existing
row rather than a row of its own. Because a `NoggWindow`'s height is a
function of declared capacity and not of rows actually added (trait 6), the
two spare rows were 52 device pixels of empty frame at the shipping scale, on
the element the audit found occluding the board's near edge where team 1
deploys. Width is unchanged: the HP row's `999 / 999` worst case and the
third-column Resonance cell both still need it.

**The action ring is clamped against the docked windows, not just the display
rect.** The raw display rect reaches the bottom of the screen, which is where
those readouts live, so a unit on the board's near edge put the ring's label
through the actor window's heading — pale text over pale text on the same dark
body. `BattlePresentationController._ring_safe_rect()` subtracts only the
windows that are *currently visible*, which is what makes it worth doing
rather than reserving the band unconditionally: since those windows started
closing when they have nothing to show, the band is usually free, and a ring
dodging an absent window would be the same clutter in a different place.

**The command window is gone; its list is now the board-anchored action
ring.** It docked to a fixed screen corner and named commands in words, which
made every turn a menu lookup at a location that had nothing to do with the
unit taking the turn. The ring puts the four commands *on* the acting unit and
gives each one a fixed direction, so `attack` becomes a direction rather than a
row to find. Three consequences worth stating, because each is a rule this
document asserted and the ring changes:

- **A direction, not a cursor.** The ring has no `MenuCursor` and does not
  cycle; §6 covers the split between the two selection models and why an
  unavailable slot is a no-op rather than a wrap.
- **`Undo` is no longer a fifth row.** It shares the north slot with `Move`,
  which is sound because `menuEntries()` only marks it visible once a move has
  happened — exactly when `Move` itself is spent. That keeps the ring at four
  directions without giving up the safety net that movement's missing confirm
  step depends on, and it is why the ring can be four icons rather than five.
- **It hides rather than dimming when the spell list opens.** Trait 3's dimmed
  parent tells the player where they came from, which reads only when the child
  opens *beside* the parent. The spell window docks to a screen edge while the
  ring sits whereever the unit happens to be, so a dimmed ring would read as a
  second live surface instead of as this one's origin.

The spell, confirm, and forecast windows keep the command window's former
origin as their dock. They were positioned and measured against that point and
nothing about them changed; re-deriving it would move three windows to fix
zero problems.

**The prompt no longer shows "Choose a command." while the command window is
already open, and it now sits on its own layer above the dev bar.**
`PlayerTurnController._menuStatusText()` returns `""` for that baseline case —
the command window being open already says as much, and the prompt saying it
too was the third-largest permanently-drawn element in the HUD. The other two
status strings stay, since each names something the command window's
enabled/disabled rows do not: which specific phase (move or act) is now closed
off, and that Pass still ends the turn. `PlayerCommandMenu._refresh_prompt()`
drives this the same way the status windows work above: `open()`/`close()` off
whether there is text, not a bare `visible` flip.

Separately, `BACKLOG_CRITICAL.md` recorded the prompt rendering behind the dev
bar at the shipping `ui_scale`, since both dock to the same top band and
`DEV_LAYER` draws over `GAME_LAYER`. Docking the prompt below the dev bar's
band was the other candidate that backlog entry named, and was rejected here
because it would make a developer-only action (F1) move a player-facing
element. `PlayerCommandMenu` now takes an externally-supplied parent for the
prompt window alone (`set_prompt_layer_root()`, called by `BattleUIBuilder`
before the node enters the tree) rather than parenting it under `self` like
every other window here, so it can live on `NoggTheme.PROMPT_LAYER` — one above
`DEV_LAYER` — while the rest of the command surface stays on the game layer.
Reparenting it out from under `action_panel` also removed the visibility
coupling that Control hierarchy gave it for free (an invisible ancestor hides
every descendant regardless of the descendant's own `visible`), so
`BattleUIBuilder` now states that coupling explicitly: the new layer's root
mirrors `action_panel.visible` via its `visibility_changed` signal, keeping the
prompt's effective visibility identical to before the split.

**`PROMPT_WIDTH` and `FORECAST_WIDTH` changed value, not just unit — this
was a real, pre-existing bug found while re-measuring the window budgets.**
Measured against the shipping font at the *current* x2 scale, with
nothing to do with `ui_scale`: the old `PROMPT_WIDTH` (620px) was 76px short of
`"Preview tile (12, 12). Empty-center casting is disabled."` (needs 696px), and
the old `FORECAST_WIDTH` (460px) was 44px short of
`"Cast spends action, cooldown & Resonance"` (needs 504px). Both strings are
verbatim from `PlayerTurnController._forecastText()`/its status lines, not
hypothetical worst cases. This predates the width-budget correction entirely —
`debug/preview_theme.gd`'s own `WIDTH_CASES` never covered prompt or forecast
content, only command/spell/actor — so nothing before this measured it. Fixed
by widening both to their true requirement rather than reproducing the old,
too-narrow number in a new unit. Command, Spell, Turn order, and the status
windows all reproduce their prior x2 value exactly; only these two moved.

Status-cell columns keep their existing design-unit positions
(`STATUS_CELL_OFFSETS`); the extra room XenoText's narrower advance leaves at
size 24 goes to scanability rather than a layout migration.

**Docking offsets are design units too** — `SCREEN_MARGIN`, `PROMPT_TOP`,
`TURN_ORDER_TOP`, `FORECAST_GAP`. These were missed when the widths were
migrated and were caught only by rendering the real scene at `ui_scale` 3: the
windows had grown while the margins placing them had not, so the whole HUD
crept toward the screen edges and the prompt sat too high. A margin is a length
like any other. If you add a new window, its position belongs here in units,
not as a literal at the call site.

**The turn rail owns the top band, and the prompt moved down for it.** The band
was already contested — the prompt docked at `PROMPT_TOP` 12 and the developer
bar sits above everything on `DEV_LAYER`, an overlap `BACKLOG_CRITICAL.md`
already records. Adding a third occupant without settling ownership would have
made it a three-way collision. The rail wins the stable position because it is
**persistent and the prompt is transient**: a readout the player consults every
turn should not move because a transient line appeared. `PROMPT_TOP` is now 34.

**Tiles are taller than they are wide, and the miniature is pinned low-right.**
A square tile made the model and the queue number compete for the same area. The
extra height gives the number its own band across the top and leaves the model a
clean square below it. Pinning is done by offsetting the *portrait camera's
frustum*, not by anchoring the rendered square inside the tile — the square has
the model centred in it, so moving the square moves nothing.

The rail replaced a three-row `NoggWindow`. That window could not show the thing
that most punishes a player who did not see it coming: a round re-sorts every
living unit by speed, so a fast unit acting last in one round and first in the
next takes **two turns back to back**, and at three entries stopping inside one
round that is structurally invisible. The rail is also **centred and resizes
with the queue**, which is why `BattleUIRefs` exposes its relayout callable —
a docked window can lay out once on `resized`, but a centred element whose width
changes has to lay out whenever its contents do.

**The forecast is left-aligned, not right-aligned.** An earlier draft of this
table said right-aligned to the command window; that cannot hold once the
forecast needs several hundred pixels and the command window's right edge sits
close by — right-aligning would place the forecast's left edge off-screen.

The bottom HUD uses fixed status cells rather than list rows: `HP` occupies the
first cell, `ATK`/`DEF` and `SPD`/`MOV` hold vertical columns at design-unit
offsets 0 and 96 (0 and 192px at shipping x2), and the third column — 192
design units / 384px — displays authored element codes beside drawn
three-cell Resonance bars (`STATUS_CELL_OFFSETS`, scaled by `ui_scale` like
every other geometry token). Text values remain separate
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

Three `CanvasLayer`s, two themes, one rule: **theme follows audience, not
layer number.** The prompt sits numerically above the dev layer so developer
chrome can never occlude a player-facing message (§8's note on
`NoggTheme.PROMPT_LAYER`), but it is built with `build_game_theme()` like every
other window here — a higher layer number does not make it developer UI.

| | Game layer | Dev layer | Prompt layer |
|---|---|---|---|
| Layer | `10` | `20` (above game) | `21` (above dev) |
| Theme | `build_game_theme()` | `build_dev_theme()` | `build_game_theme()` |
| Holds | Command, Spell, Actor, Target, Forecast, Log | Top bar, graphics menu, screenshot, save replay | Prompt only |
| `F1` | **unaffected** | toggles visibility | **unaffected** — mirrors `action_panel.visible` instead, so it tracks whether a player turn is active, not whether the dev bar is shown |

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
