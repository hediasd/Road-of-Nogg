# UI / UX Design

Status: authoritative for battle UI presentation. Written 2026-07-30.

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

The target is the Dragon Quest XI command-window language: translucent
navy windows with a heavy beveled light-blue frame, a gold cursor sprite that
lives in the frame's gutter, nested menus that open as *stacked sibling
windows*, and fixed-height panes that page rather than scroll.

We are adopting it because it solves three problems the current HUD has:

- **Legibility over a 3D scene.** A heavy frame with an outlined font reads on
  any background; a 1px flat border does not.
- **Selection without occlusion.** A gutter cursor never covers the row text
  and never fights the frame for contrast, unlike a filled highlight bar.
- **Depth without modality.** Stacked windows show the player where they are in
  a menu tree without dimming or replacing the board.

### The six traits

All six are in scope. They are listed here as acceptance criteria, not as
aspiration.

| # | Trait | Rule |
|---|---|---|
| 1 | **Beveled 9-slice frame** | Every game window uses the shared `NoggWindow` frame. No ad-hoc `StyleBoxFlat` borders in game UI. |
| 2 | **Gutter cursor sprite** | Selection is a cursor node's position, never a background fill and never a text prefix. The cursor bobs continuously and tweens between rows, and sits in a reserved gutter clear of both the ring and the text. |
| 3 | **Stacked sibling windows** | A submenu is its own window opening to the right of its parent. The parent stays on screen with **both its frame and its content** tinted to the inactive state. |
| 4 | **List rows and status cells** | Lists keep a left label and right-aligned value against the frame's inner edge; never centre or wrap them — hard-truncate instead (`OVERRUN_TRIM_CHAR`; the font has no ellipsis glyph, see §3). Docked status readouts are the exception: fixed cells start at x=0, 192, and 384, keeping each label/value unit together. |
| 5 | **Paging, not scrolling** | Windows are fixed-height. Overflow pages, with a `n / m` footer window straddling the parent's bottom border, its arrows drawn rather than typed (§7). |
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

Today the project has **no `Theme` anywhere**. Every visual value is a literal
at its construction site: `BattleUIBuilder._styleHudPanel()` and
`PlayerCommandMenu._style_panel()` each build a near-identical `StyleBoxFlat`
with the same magic colours duplicated, and font colours are set with
`add_theme_color_override` per label. The practical consequence is that
"change the window look" is an N-file GDScript edit with no single source of
truth, and any two panels drift apart the moment someone edits one of them.

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
| `WINDOW_FILL` | `#060F26` @ `0.86` | Translucent window body; the board reads through it |
| `WINDOW_FILL_DEEP` | `#04091A` @ `0.94` | Modal / confirm windows that must not be read through |
| `FRAME_ACTIVE` | `#A8D8FF` | Frame tint for the window holding focus |
| `FRAME_INACTIVE` | `#4A5A72` | Frame tint for a parent window whose child has focus |
| `TEXT_PRIMARY` | `#FFFFFF` | Row labels |
| `TEXT_DIM` | `#7E93B0` | Disabled entries (spent commands, spells on cooldown) |
| `TEXT_ACCENT` | `#FFD766` | Right-column values, headings |
| `TEXT_FORECAST` | `#9BE7FF` | Damage/hit forecast line |
| `CURSOR` | `#FFC63A` | Selection cursor |
| `OUTLINE` | `#000000` | Font outline, opaque, always on |

Layout tokens that matter to more than one item:

| Token | Value | Meaning |
|---|---|---|
| `FRAME_SOURCE_MARGIN` | 16 | 9-patch slice in *source* pixels — an art fact, never tuned |
| `FRAME_SCALE` | 3 | Integer nearest-neighbour upscale of the frame art |
| `FRAME_MARGIN` | 48 | Patch margin in screen pixels, after the upscale |
| `FRAME_RING_PX` | 12 | Thickness of the ring the player actually sees |
| `CONTENT_INSET` | 22 | `FRAME_RING_PX` + 10 padding — where content starts |
| `ROW_HEIGHT` | 26 | `FONT_SIZE_BODY` + 2; the font measures exactly 24px tall |
| `ROW_CAPACITY_DEFAULT` | 8 | Rows per window before paging |

`ROW_HEIGHT` cannot go below the font height — a `Label` enforces its own
minimum, so a smaller value is silently ignored rather than tightening further.

Animation timings live in `NoggTheme.gd` for the same reason the colours do:
the window, the cursor, and the pager all read them, and drift between them
would read as three different menus.

`FRAME_ACTIVE` → `FRAME_INACTIVE` is a **tween over 0.12 s**, not a snap. It is
the only thing telling the player which window their arrow keys are driving.

### Dev palette

Deliberately drab, and deliberately not on-brand. Developer controls must never
be mistakable for game affordances.

| Token | Value |
|---|---|
| `DEV_FILL` | `#101418` @ `0.92` |
| `DEV_BORDER` | `#3A4450`, 1px, square corners |
| `DEV_TEXT` | `#C6CED8` |

### Typography

- **Game:** `assets/Fonts/shining-force-ii-small.otf`, which reports itself as
  "Shining Force II (Small)". Pixel font — antialiasing off, hinting off,
  subpixel positioning disabled, integer sizes only. Body `24`, heading `24`,
  footer `20`. `font_outline_color = OUTLINE`, `outline_size = 4` on every game
  text entry. 24 was chosen against a reference screenshot; every width in §8
  is measured at it, so changing the size means remeasuring.
- **Dev:** `assets/Fonts/Roboto-Regular.ttf` at `13`, no outline.

**Not `Shining Force 2.ttf`.** Both files are genuine Shining Force faces and
both load without error, so this is easy to get wrong silently. The `.ttf`
reports as "Shining Force 2 b" and is the thin 1px-stroke variant, which reads
weak in a menu; the `.otf` is the chunky 2px-stroke face. Compared side by side
2026-07-30 with `debug/preview_font.gd`, which prints `get_font_name()` for
each candidate — check that, not the filename.

The `.otf` runs roughly **twice the advance width** of the `.ttf`. Every window
width in §8 is measured against it.

`PressStart2P` was evaluated and rejected: its glyph advance is too wide for
two-column rows, which forces truncation on ordinary spell names.

### Glyph coverage is a hard constraint

Verified 2026-07-30 with `Font.has_char()` against the shipping font, not by
eye. **The face is ASCII-only.** Present: `< > / : 0-9` and the basic Latin
set. Missing: `‹ › ◀ ▶ ▲ ▼ … — ✓ •` — every non-ASCII symbol tried.

A missing glyph does not render as a visible tofu box — Godot silently
substitutes a Windows system font, so `◀` renders as a thin outline triangle
sitting next to a pixel font and looks merely *wrong* rather than broken. This
is the failure mode to watch for: it will not throw, and it will not be obvious
in a code review.

**Rule: every UI symbol is drawn with `_draw()`, never typed.** The cursor
(§5) and the pager arrows (§7) are both filled triangles in code. That
guarantees they match each other, match the font's weight, and never depend on
what fonts the player's machine happens to have.

This is not a quirk of one face. `debug/preview_theme.gd -- cycle` walks all 12
pixel fonts in `assets/Fonts` and reports coverage: **`◀`, `▶`, and `✓` are
missing from every single one of them.** No font choice rescues typed symbols,
so the rule holds regardless of what §3 settles on later.

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

### Existing art, used as-is

`assets/ui/MenuFull.png` is a 48×48 grayscale 9-patch source: 16px corners,
16px edges, 16px centre. `MenuCorner`, `MenuLine`, `MenuLine2`, and
`MenuMiddle` are the same tiles split out individually. They are referenced by
the legacy `scenes/main.tscn` as raw `Texture2D` and have never been used as
9-slices.

Because the art is grayscale it **tints cleanly**, which is what makes the
active/inactive frame state cheap: one texture, two `self_modulate` values.

### `NoggWindow` anatomy

`MenuFull.png` is a complete window, not a bare frame. It is RGBA with exactly
six colours: a white bevel, a near-black outer edge, transparent corners, and a
**baked translucent black body `(0, 0, 0, α=155)`** filling the centre patch and
the inner part of all four edge tiles.

We split that one image into **two 9-patch layers off the same source**, sliced
at the same patch margins, and stack them:

```text
NoggWindow (Control)               ← plain Control, NOT a Container
├── Body (NinePatchRect)           draw_center = true,  self_modulate = WINDOW_FILL
├── Content (VBoxContainer)        full rect, inset by CONTENT_INSET
└── Frame (NinePatchRect)          draw_center = false, self_modulate = FRAME_ACTIVE
                                   [added last, draws on top]
```

`NoggTheme._masked_frame_texture()` produces both by keying on fractional
alpha — the body is the only colour in the file that has any, so the split is
unambiguous. The body mask is flattened to opaque white so `self_modulate`
reproduces `WINDOW_FILL` exactly, alpha included; the ring mask keeps the bevel
and outer edge and is tinted per focus state.

**Both layers must come from the same source.** The first version drew the body
as a `StyleBoxFlat` rounded rect instead, and a rounded rect cannot reproduce a
pixel-art corner staircase: around all four corners the fill poked out past the
ring and showed as a dark wedge outside the frame. Sharing the source makes the
corners identical *by construction*. Any approach that describes the body
geometry a second time reintroduces the gap — do not replace either layer with
a StyleBox.

**The root must not be a Container.** A `PanelContainer` force-fits *every*
child into its stylebox content rect, including the frame — which insets the
frame and leaves the ring covering the first and last glyph of every row. This
also fails visually rather than throwing.

### The ring is thickened by scaling the art

The authored ring is **4 source pixels**: 1 dark, 2 white, 1 dark. At 1:1 that
renders far too thin for the window it is imitating. The masks are upscaled by
`FRAME_SCALE` (3) with `Image.INTERPOLATE_NEAREST`, giving a 12px ring where
every authored pixel is a crisp 3×3 block.

**Scale the texture, do not stretch the `NinePatchRect`.** A 9-patch draws its
corner patches at native size, so stretching thickens the edges and leaves the
corners thin — the seam shows immediately.

### The cursor gets a reserved gutter

A window that hosts a `MenuCursor` indents its rows by `CURSOR_GUTTER_WIDTH`
(12px) on top of `CONTENT_INSET`, so the arrow occupies clear space rather
than overlapping the frame:

```text
0 ............ 12 .... 16 ......... 28 ...... 34 ............
  |<-- ring -->|      |<- cursor ->|         |<- text
                       (incl. bob)
```

Windows with no cursor — prompt, forecast, docked readouts — leave the indent
at zero; indenting them would only look misaligned. `CURSOR_WIDTH`,
`CURSOR_INSET`, and `CURSOR_GUTTER_WIDTH` all live in `NoggTheme` rather than
inside `MenuCursor`, because `NoggWindow` has to reserve space for a cursor it
never sees: if the two disagree the arrow either sits on the ring or floats in
dead space.

**`FRAME_MARGIN` and `CONTENT_INSET` are different numbers on purpose.**
`FRAME_SOURCE_MARGIN` (16) is the 9-patch slice — an art fact, never tuned.
`FRAME_MARGIN` (48) is that slice after the upscale. `CONTENT_INSET` (22) is
the visible ring plus padding, and deliberately does **not** follow the scale:
most of the patch margin is body that the ring layer draws as nothing, so
insetting content by the full 48 would waste 36px a side.

### Behaviour

- **Open:** scale `0.94 → 1.0` and alpha `0 → 1` over 0.10 s, `EASE_OUT`.
  Close is the reverse over 0.08 s. Fast enough not to be in the way, present
  enough to sell the window as an object.
- **Focus:** `set_active(bool)` tweens **the frame tint and the content tint
  together**, over `TWEEN_FOCUS`. A window never moves to show focus.

  Dimming the border alone is not enough: a fully-lit list inside a greyed
  frame reads as a rendering glitch rather than as "this window is not
  listening". `CONTENT_INACTIVE_MODULATE` drops the content to roughly the
  same ~44% brightness the frame takes, so the two read as one effect.
  Measured on screen: command-window text peaks at `(255,255,255)` focused and
  `(115,120,133)` while the spell window holds focus.

  It is applied as a `modulate` on the content container rather than as a
  restyle of each row, which means a *disabled* row inside an *inactive*
  window compounds to the dimmest state automatically, with no extra state to
  track.
- **Sizing: size on open, then hold.** A window's height is fixed for the
  lifetime of one opening, but it is sized to what it will actually show:
  `min(row count, max capacity)`.

  The earlier wording here — *"a 6-row window is the same height whether it
  holds 6 entries or 2"* — overshot. What traits 5 and 6 actually require is
  that a window **never resizes while the player is navigating it**: paging
  must not shrink the window on a partial last page, and a docked readout must
  not jitter as an HP string changes length. Neither of those needs a window to
  reserve space it will never use. Sizing as it appears is free.

  Applied: the command list can never page and tops out at five entries, so it
  is a 5-row window — at `ROW_CAPACITY_DEFAULT` it was reserving four empty
  rows, half the window. The spell list can page, so it keeps the 8-row
  ceiling, but a monster with one spell gets a 2-row window, not eight.
  Docked readouts (actor, target) stay at fixed capacity: they are the case the
  no-jitter rule was written for.

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

- A single `MenuCursor` node per menu, parented to the window's frame gutter
  (the 16px left margin), sibling to the row list rather than a child of any
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
| Mouse motion over a row | Move the cursor to that row (no activation) |
| Left click on a row | Move the cursor there, then activate |
| Left click on `◀` / `▶` | Page |
| Right click | Same as `ui_cancel` |
| Mouse wheel over a window | Move cursor one row |

Disabled rows are skipped by keyboard movement and are inert to hover and
click. They render in `TEXT_DIM` and are never hidden — a spent `Move` must
stay visible so the player can see *why* it is unavailable.

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
| **Command** | Left, vertically centred | 220 × 5 rows | `MOVE / UNDO / ATTACK / SPELL / PASS` — longest is `ATTACK` at 144 + 56 overhead; 5 is the list's true maximum |
| **Spell** | Right of Command, `WINDOW_STACK_GAP` | 680 × up to 8 rows | Sized to the monster's spell count + `< BACK`, capped at 8; pages beyond that. Two-column: spell name left, `Rng N` / `CD n` right in `TEXT_ACCENT` |
| **Actor status** | Bottom-left, fixed | 540 × 6 rows | Name heading in `TEXT_ACCENT`; fixed-cell `HP`, `ATK`/`DEF`, and `SPD`/`MOV` rows, with authored element codes and three-cell Resonance bars in column 3 |
| **Target** | Bottom-right, fixed | 540 × 6 rows | Same fixed-cell shape as actor status; shows an empty frame, not a hidden window, when there is no target |
| **Forecast** | Above Command, **left-aligned** with it | 460 × 2 rows | Hit chance and damage range in `TEXT_FORECAST`; visible only during confirm |
| **Prompt** | Top-centre | auto, 1 row | `Select a destination`, `Select a target` — replaces today's status label |
| **Battle log** | Right edge, full height | scrolling | The one deliberate exception to trait 5; a log is a scrollback, not a menu |

Command + gap + Spell is 908 of 1152. Actor + Target is 1080 of 1152. Both fit,
but the status pair has little room left — **size 24 is close to the ceiling
this viewport supports** for the two-window layouts. Going larger means either a
bigger default window size or dropping to one status window at a time.

**Two windows deliberately under-fit.** Sized to the true worst case they would
not fit the budget above:

- **Spell** would need **~950px** to hold `Closing of the Third Sanctuary`
  beside its `CD 12` once the cursor gutter is counted. 680 covers every other
  spell in the catalogue — the next longest, `Corrupting Splatter`, needs 644
  — and hard-truncates the two 30-char
  `…of the Third Sanctuary` outliers. Renaming those two is the cleaner fix and
  is worth doing when the catalogue is next touched.
- **Actor status** no longer renders a prose `Elements` list: each authored
  element occupies the third fixed cell beside its matching stat row, so a
  two-element monster has two compact code-and-bar readouts without widening.

Truncating an outlier is normal in this genre; a half-screen menu is not.

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

---

## 9. Game UI vs developer UI

Dragon Quest's window language works partly *because* that game has no debug
HUD. Ours does: pause, a speed slider, new battle, graphics, screenshot, save
replay, battle log. Skinning a frame-pacing slider in ornate JRPG chrome would
teach the player it is a game mechanic.

### The split

Two `CanvasLayer`s, two themes, one rule.

| | Game layer | Dev layer |
|---|---|---|
| Layer | `10` | `20` (always above) |
| Theme | `build_game_theme()` | `build_dev_theme()` |
| Holds | Command, Spell, Actor, Target, Forecast, Prompt, Log | Top bar, graphics menu, screenshot, save replay |
| `SPACEBAR` | **unaffected** | toggles visibility |

Today `SPACEBAR` toggles `battle_ui["canvas"].visible`, which hides everything
including the player's own command menu. After the split it toggles the dev
layer only, so a clean screenshot still shows the game UI as a player sees it —
which is the actual reason the key exists.

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
it prevents the frame's 12px ring from shimmering as the mask size changes.

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
