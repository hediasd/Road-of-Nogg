# Implementation Plan

Opened 2026-08-03. The previous contents completed the action-confirmation and
tactical-legibility cycle, including user-confirmed normal-window visual
validation, and were cleared in commit `7bb6209`. Recover them with
`git show 7bb6209~1:implementation_plan.md`. That cycle left no unstarted or
abandoned item to relocate. This file now holds one new cycle: rework the
battle-window visuals around the supplied XenoText font and the two provided
reference screenshots.

The supplied task asset is `assets/Fonts/xenotext.otf`; Godot generated its
matching `.import` metadata during the accepted visual pass. Both belong to
this cycle. The unrelated untracked `vfx_plan.md` remains user-owned. Resolve
it (commit or remove it) before beginning UIBOX-1, so every implementation
item begins from a clean `git status` as required.

Execute one item per session, in file order, committing at each item boundary.
Implementation items stop after focused diff review, `git diff --check`,
backlog maintenance, and their commit. Only UIBOX-VALIDATE performs the
combined normal-window gameplay and visual acceptance pass.

## Scope and settled decisions

The target is the supplied PS1-era dialogue-window language: a narrow,
cool-white rim with a restrained violet cast; a near-black translucent body;
and a broad, soft black silhouette that deliberately extends outside the rim.
The first reference supplies the faint cool glow and compactness; the second
supplies the quiet, deep transparent body and the smooth outer overdraw.

All game `NoggWindow` instances share the restyle: command, spell, confirm,
prompt, forecast, pager, turn order, actor status, and target status. The
existing input model, window locations, capacities, paging, cursor gutter,
focus semantics, and game/dev UI split remain unchanged. Developer UI keeps
Roboto and its drab flat treatment.

`assets/ui/MenuFull.png` is retired from the runtime window renderer but stays
in the repository. The new shared frame is procedural and comprises four
layers, in draw order:

```text
NoggWindow (Control; clip_contents disabled)
├── Halo backplate: expanded smooth translucent black with soft black shadow
├── Body: near-black translucent rounded rectangle
├── Content: existing VBoxContainer and cursor layout
└── Rim: transparent rounded rectangle with a thin pale-violet border
```

The halo is visually allowed to draw beyond the root Control but must not
change the window's layout bounds or consume pointer input. Giving every layer
the same centralized corner geometry prevents seams. It replaces the old
pixel-art body/ring pairing rather than mixing incompatible corner shapes.

Use `xenotext.otf` (reported family `XenoText`, Regular) as the game UI font.
At 24 px it is about half the advance width of the outgoing font, so retain the
existing window widths and use the recovered space as breathing room instead
of shrinking or re-docking panels. Start with an integer 24 px body size and a
2 px opaque-black outline; keep glyph smoothing disabled unless final visual
validation establishes that XenoText becomes illegible without it. Drawn
cursor and pager glyphs remain drawn even if the new font happens to contain
them.

Initial visual tuning targets, all owned by `NoggTheme.gd` and adjusted only
there: 2 px rim, 12 px content inset, 5-6 px corner radius, 8-12 px halo spread,
near-black body alpha around 0.72-0.78, and a pale violet-white active rim.
These are calibration seeds, not independent local literals. Final tuning must
remain recognizably restrained: no neon glow, ornamental bevel, or opaque slab.

Damage numbers intentionally inherit the game font through `NoggTheme`; this
cycle changes that existing dependency but does not otherwise redesign their
world-space presentation.

## Conventions

Every item has an explicit minimum **Model**, **Risk**, and behavior it **Adds
to validation coverage**. The executing session must verify its running model
before starting and stop if it is more capable than the item needs. Every item
reviews `BACKLOG_CRITICAL.md`, `BACKLOG_LONGTERM.md`, and `docs/BACKLOG.md` for
stale, completed, or newly discovered work. Implementation Resolutions become
**implemented; pending end-of-plan validation**; only UIBOX-VALIDATE marks
covered items done.

---

## UIBOX-1 — Establish the thin-rim visual contract

**Model:** Opus 5 / GPT Sol

**Depends on:** none.

**Risk:** Medium. This changes the authoritative visual language of every game
window; an incomplete contract would let shared and one-off code drift again.

**Adds to validation coverage:** All player-facing battle boxes share one
thin-rim, translucent-black, exterior-halo language while developer panels
remain visually distinct.

**End state:** `docs/UI_DESIGN.md` describes the supplied-reference target and
its centralized token/ownership rules without changing battle interaction.

### Work

1. Replace the Dragon Quest heavy-bevel reference in `docs/UI_DESIGN.md` with
the supplied thin-rim black-translucent target, retaining traits for the cursor,
stacked menus, fixed-height paging, and docked windows.
2. Replace the `MenuFull.png` 9-slice anatomy and scale discussion with the
four-layer procedural `NoggWindow` anatomy above. State that no game code may
create a local border, halo, or color literal outside `NoggTheme.gd`.
3. Update the game palette, typography, and geometry-token sections: XenoText,
initial metrics, 2 px outline/rim, matching corner geometry, and halo
parameters. Keep semantic state colors unless a reference-driven legibility
reason requires a token adjustment.
4. Update text-width guidance: existing window docks and widths are retained;
the former spell-name under-fit exception should be remeasured against
XenoText rather than assumed.
5. Review the backlogs.

**Files:** `docs/UI_DESIGN.md`, `assets/Fonts/xenotext.otf`,
`assets/Fonts/xenotext.otf.import`.

**Resolution:** Not started.

---

## UIBOX-2 — Render the shared halo, body, rim, and XenoText theme

**Model:** Sonnet 5 / GPT Terra

**Depends on:** UIBOX-1.

**Risk:** High. `NoggWindow` serves every battle box. A wrongly clipped halo,
changed mouse filter, mismatched corner geometry, or stale layout constant
would affect every command and readout at once.

**Adds to validation coverage:** Command, spell, confirm, prompt, forecast,
pager, actor, target, and turn-order windows show the new look without changes
to their size contracts, focus behavior, cursor interaction, or board
click-through rules.

**End state:** The battle UI uses one procedural, smooth four-layer renderer
and the XenoText game theme; `MenuFull.png` is no longer loaded at runtime.

### Work

1. In `NoggTheme.gd`, set the game font path to XenoText and centralize its
rasterization, outline, palette, corner, inset, rim, and halo tokens. Keep the
developer theme unchanged.
2. Replace the runtime `MenuFull.png` masks and 9-patch factories with shared
procedural `StyleBoxFlat` factories for a halo backplate, body, and transparent
thin rim. Each layer takes the same corner radius from the theme; only the halo
uses expanded geometry and a soft black shadow.
3. In `NoggWindow.gd`, construct halo, body, content, and rim in documented
draw order. Ensure `clip_contents` remains false and all decorative layers use
`MOUSE_FILTER_IGNORE`; preserve existing root/row transparency behavior.
4. Recompute all coupled geometry (`CONTENT_INSET`, cursor inset/gutter,
window heights, and footer placement) from the new rim tokens. Do not alter
window dock positions or widths merely because XenoText is narrower.
5. Preserve `set_active()` behavior: it tints the rim and dims content, while
the black halo stays visually stable. Preserve every interruptible tween rule
from `docs/LEARNINGS.md`.
6. Review the backlogs.

**Files:** `src/presentation/theme/NoggTheme.gd`,
`src/presentation/theme/NoggWindow.gd`.

**Resolution:** Not started.

---

## UIBOX-3 — Make the preview represent the shipping visual contract

**Model:** Sonnet 5 / GPT Terra

**Depends on:** UIBOX-2.

**Risk:** Low. This is preview-only, but an incomplete specimen can conceal
font fallback, halo clipping, and retained old frame code until final play.

**Adds to validation coverage:** The preview exposes the real shared renderer
on hostile bright/dark backgrounds, active/inactive focus states, paging,
docked status boxes, and a viewport edge where halo overdraw could clip.

**End state:** `debug/preview_theme.gd` is a reliable visual and metric probe
for the shipping XenoText treatment rather than a specimen of the retired
9-slice window.

### Work

1. Make XenoText the first/shipping candidate and retain the old face only as a
comparison option; show the actual engine-reported font name, glyph coverage,
height, and key row widths.
2. Exercise active and inactive command/spell boxes, prompt/forecast, a pager,
and actor/target status windows using the real `NoggWindow` classes.
3. Put a specimen near a viewport edge and include bright, dark, and white
background stress areas, so clipped halo, unreadable text, and corner seams
are visible in one capture.
4. Refresh expected width notes for the longest spell, typical spell, name, and
status values without changing production docking decisions.
5. Review the backlogs.

**Files:** `debug/preview_theme.gd`.

**Resolution:** Not started.

---

## UIBOX-VALIDATE — Integrated gameplay and visual acceptance

**Model:** Opus 5 / GPT Sol

**Depends on:** UIBOX-1, UIBOX-2, UIBOX-3.

**Risk:** Medium. The result is primarily visual; a parse/import check cannot
establish legibility, overdraw, focus, or the effect of CRT on the new frame.

**Adds to validation coverage:** Nothing new; this item consolidates and runs
the complete cycle coverage.

**End state:** The restyle is accepted in a normal game window, all covered
items are done, and this plan is cleared in the same session.

### Work

1. Run an import/parse diagnostic and the preview harness. Confirm XenoText
loads by family name without fallback glyphs, no `MenuFull.png` frame factory
is still reached, and no decorative layer reports input handling.
2. At 1152x648, inspect the preview and live Player vs CPU battle over bright
and dark scene areas. Verify a consistent 2 px rim, smooth corners, visible but
restrained black halo overdraw, and a legible translucent body.
3. Exercise command, spell, confirm, prompt, forecast, pager, turn-order,
actor, and target windows. Confirm status readouts remain click-through,
menus remain clickable, cursor gutters clear the rim, and focus dimming is
unambiguous.
4. Test normal and UI-through-CRT modes, opening/closing/interruption, and a
turn containing damage numbers. Verify XenoText remains readable and no tween,
halo, or panel survives incorrectly at turn/battle end.
5. Capture a representative player-facing screenshot and obtain user approval
of the reference match. User visual approval is blocking for completion.
6. Run `git diff --check`, update owning documentation and backlogs for any
verified durable finding, grep the repository for `UIBOX-`, and rewrite any
hit outside this file as durable prose.
7. Mark UIBOX-1 through UIBOX-3 done, clear this file, and commit validation
results and any fixes together. Recover completed plan contents through Git if
needed.

**Files:** `implementation_plan.md`, `docs/UI_DESIGN.md`,
`BACKLOG_CRITICAL.md`, `BACKLOG_LONGTERM.md`, `docs/BACKLOG.md`, plus only
files requiring a validation fix.

**Resolution:** Not started.