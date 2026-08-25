## Design tokens and Theme factories for the battle UI.
##
## This file is the single source of truth for every colour, font, spacing, and
## timing value in the battle HUD. No colour literal may appear anywhere else
## under `src/presentation/` — that rule is what keeps a restyle a one-file
## edit. See `docs/UI_DESIGN.md` for the reasoning behind each token.
##
## Nothing here applies itself. `build_game_theme()` and `build_dev_theme()`
## return Theme resources for a caller to assign; `build_window_frame()`
## returns a configured rim Panel. The UI builders consume these factories.

class_name NoggTheme
extends RefCounted

# --- Canvas layers --------------------------------------------------------
#
# Game UI renders ABOVE the CRT overlay and therefore takes no scanlines, mask,
# or vignette. That is deliberate (docs/UI_DESIGN.md §10): crisp menus over a
# filtered scene keep the pixel font readable at every scanline strength and
# stop the thin rim shimmering as mask size changes.
const CRT_LAYER := -20
## Transient board annotations render above the world and default CRT pass, but
## below every player-facing or developer-facing UI element.
const WORLD_EFFECT_LAYER := 9
const GAME_LAYER := 10
const DEV_LAYER := 20
## The player-facing prompt window only (`PlayerCommandMenu._prompt_window`),
## which BACKLOG_CRITICAL.md records as overlapped by the dev bar at the
## shipping ui_scale: both dock to the same top band, DEV_LAYER draws over
## GAME_LAYER, and the prompt loses. Docking it below the dev bar's band
## instead was the other candidate the backlog names, rejected because it
## would make the prompt jump position whenever the dev bar (F1) toggles — a
## developer-only action moving a player-facing element is worse than the
## layer split it would fix. A dedicated layer keeps the prompt's position
## fixed regardless of dev-bar visibility and settles which one wins on the
## only defensible grounds: a message meant for the player should never be
## occluded by developer chrome.
const PROMPT_LAYER := DEV_LAYER + 1

## The `ui_through_crt` toggle. The CRT shader (`crt_display.gdshader`)
## reads `hint_screen_texture`, i.e. it distorts whatever was already drawn to
## screen at the moment ITS canvas item draws — so making the game UI take
## the CRT treatment is a matter of where the shader's OWN layer sits relative
## to GAME_LAYER, not of moving the game canvas itself (which stays a stable
## constant other code depends on). Both values stay below DEV_LAYER, so the
## dev bar is never affected either way — see docs/UI_DESIGN.md §10.
const CRT_OVERLAY_LAYER_DEFAULT := -10
const CRT_OVERLAY_LAYER_THROUGH_UI := GAME_LAYER + 1

# --- Game palette ---------------------------------------------------------

## Warm dark translucent window body. The board still reads through it.
##
## Lifted from the previous near-black `(0.012, 0.012, 0.020, 0.76)` when Nogg
## Terminal was adopted, and the two changes are one decision: the face's edge
## treatment is a drop shadow, and a dark shadow on a near-black panel is
## invisible by construction. The reference's own mailer panel is a warm dark
## brown, which is the only reason its shadow reads at all. This is the lightest
## rung that lets the shadow register while keeping the panel translucent —
## picked by eye in the VFX debug scene's text specimen against the real board.
const WINDOW_FILL := Color(0.075, 0.058, 0.042, 0.86)
## For windows that must not be read through (confirm prompts).
const WINDOW_FILL_DEEP := Color(0.004, 0.004, 0.008, 0.90)
## Expanded black backplate and soft shadow outside the visible rim.
const HALO_FILL := Color(0.0, 0.0, 0.0, 0.28)
const HALO_SHADOW := Color(0.0, 0.0, 0.0, 0.58)

## Frame tint for the window holding focus.
const FRAME_ACTIVE := Color(0.902, 0.878, 1.0)
## Frame tint for a parent window whose child has focus.
const FRAME_INACTIVE := Color(0.384, 0.357, 0.471)

const TEXT_PRIMARY := Color(0.957, 0.945, 1.0)
## Disabled entries: spent commands, spells on cooldown. Dim, never hidden.
const TEXT_DIM := Color(0.510, 0.486, 0.588)
## Right-column values and headings.
const TEXT_ACCENT := Color(1.0, 0.843, 0.400)
const TEXT_FORECAST := Color(0.722, 0.851, 1.0)
const TEXT_HEAL := Color(0.62, 1.0, 0.65, 1.0)
const CURSOR := Color(1.0, 0.776, 0.227)
## Font outline. Always opaque, always on — it is what makes text survive an
## arbitrary 3D background.
const OUTLINE := Color(0.0, 0.0, 0.0, 1.0)

## Team identity. Previously a pair of colour literals inside
## `GodotVisualAdapter._on_monster_spawned`, which was the one place in
## `src/presentation/` this file's no-literals rule was being broken. Kept here
## rather than pushed back down: a second surface wanting team colour is a
## matter of time, and two surfaces disagreeing about which blue is team one
## would be worse than the literal ever was.
const TEAM_ONE_COLOR := Color(0.18, 0.42, 0.95)
const TEAM_TWO_COLOR := Color(0.9, 0.2, 0.16)


## Team colour by team index. Two teams today (`docs/GAME_DESIGN.md`); anything
## outside that falls back to team two's colour rather than asserting, because a
## readout is not the right place to halt a battle.
static func team_color(team: int) -> Color:
	return TEAM_ONE_COLOR if team == 1 else TEAM_TWO_COLOR

# --- Dev palette ----------------------------------------------------------
#
# Deliberately drab and deliberately off-brand. Developer controls must never
# be mistakable for game affordances (docs/UI_DESIGN.md §9).
const DEV_FILL := Color(0.063, 0.078, 0.094, 0.92)
const DEV_BORDER := Color(0.227, 0.267, 0.314)
const DEV_TEXT := Color(0.776, 0.808, 0.847)

# --- UI scale -------------------------------------------------------------
#
# Every geometry token below is authored in DESIGN UNITS and multiplied by
# `ui_scale` to reach device pixels. The canvas is not scaled at all
# (`window/stretch/mode = "disabled"`), so a device pixel is a real pixel and
# whole-numbered geometry stays whole at every window size.
#
# **Why the canvas is not doing this.** Scaling the canvas by a fraction — which
# is what `canvas_items` stretch does at nearly every real window size —
# duplicates some pixel rows and drops others under the project's nearest
# filter, so a one-pixel stroke renders two device pixels wide in places and
# three in others inside the same word. Measured at 1340 x 754: x1.163, and both
# fonts visibly damaged. Canvas-level *integer* scaling fixes that but
# letterboxes hard against the inherited 1152 x 648 base. Scaling the tokens
# instead keeps both halves of the UI correct: smooth chrome (rims, rounded
# bodies, halos) is redrawn at the larger size rather than resampled, and pixel
# content lands on whole pixels. See `docs/UI_DESIGN.md` §3.
#
# **These are `static var`, not `const`, and that is the whole design.** Sixty
# call sites across a dozen files read these names. Turning each into a function
# call would break this file's central promise — that a restyle is a one-file
# edit — so the names keep their identity and only their values move.
# `configure()` is the single writer.
const UI_SCALE_MIN := 1
const UI_SCALE_MAX := 4
## Window height, in device pixels, that buys one step of scale. 360 puts 720p
## at x2 and 1080p at x3, which is the ladder the 16:9 resolutions land on.
const UI_SCALE_STEP_HEIGHT := 360

## Defaults to 2 because that is what the current constants already encode:
## `FONT_SIZE_BODY` was 24 and the design body is 12. A correct conversion is a
## no-op at this scale, which is exactly how it is checked.
static var ui_scale: int = 2


## Recomputes the scale from a window height. Returns whether it changed, so a
## caller can decide to rebuild themes and relayout without this file needing to
## know anything about nodes, signals, or the tree.
##
## Deliberately not a signal: `NoggTheme` is a pure token and factory class with
## no node identity, and giving it one so it could emit would be a larger change
## to its role than this problem justifies.
## **Rounds to nearest, deliberately — truncating here is a bug, and was one.**
## A window's usable client height is never the nominal resolution: a nominal
## 1920 x 1080 window measures 1920 x 1056 once the title bar is taken, and
## `1056 / 360` is 2.93. Truncation turned that into x2, throwing away almost a
## whole step because of 24 pixels of window chrome — so a maximised 1080p
## window rendered its UI at the same scale as a 720p one. Rounding maps the
## real measured client heights (696, 1056, 1416) onto the intended 2 / 3 / 4
## rather than onto 1 / 2 / 3.
static func configure_for_window_height(height: int) -> bool:
	return configure(
		clampi(
			roundi(float(height) / float(UI_SCALE_STEP_HEIGHT)),
			UI_SCALE_MIN,
			UI_SCALE_MAX
		)
	)


static func configure(scale: int) -> bool:
	var wanted := clampi(scale, UI_SCALE_MIN, UI_SCALE_MAX)
	if wanted == ui_scale:
		return false
	ui_scale = wanted
	_recompute()
	return true


## Design units are allowed to be fractional where an existing value demands it
## (`RESONANCE_CELL_GAP` is 3 device pixels at x2, so 1.5 design units), but the
## result never is: everything lands on a whole pixel via `roundi`. Whole device
## pixels are the entire objective, so rounding here rather than at each draw
## site is what makes it a property of the tokens instead of a hope.
static func _scaled(units: float) -> float:
	return float(roundi(units * float(ui_scale)))


static func _scaled_int(units: float) -> int:
	return roundi(units * float(ui_scale))


# --- Typography -----------------------------------------------------------

## **Nogg Terminal, the in-house bitmap face** (`docs/UI_DESIGN.md` §3). Drawn
## on an 8 x 12 design cell with an 8-unit monospace advance, so it reports a
## **16px advance at size 24** against XenoText's 12px — a third wider. Every
## window width in this file was re-measured against it on adoption; they are
## not the XenoText numbers.
##
## The baked `.res` carries its own glyph cache and its own outline variants.
## `assets/Fonts/NoggTerminal/glyphs.txt` is the editable source of truth and
## `scripts/bake_bitmap_font.gd` regenerates the resource from it.
const GAME_FONT_PATH := "res://assets/Fonts/NoggTerminal/NoggTerminal.res"
const XENOTEXT_FONT_PATH := "res://assets/Fonts/xenotext.otf"
const DEV_FONT_PATH := "res://assets/Fonts/Roboto-Regular.ttf"

## Nogg Herald, the display face: item banners, hint plates, act titles. It is
## proportional and negatively kerned, so it must NEVER be used where a column
## has to line up — the fixed status cells, the zero-padded stat readouts, and
## anything `debug/measure_px4_widths.gd` measures all depend on Terminal's
## monospace advance. `assets/Fonts/NoggHerald/glyphs.txt` is the source and
## `scripts/bake_herald_font.gd` regenerates the resource.
const BANNER_FONT_PATH := "res://assets/Fonts/NoggHerald/NoggHerald.res"

## The theme type variation banners wear. Assign it to a `Label` with
## `theme_type_variation = NoggTheme.BANNER_TYPE` (or call `make_banner_label`)
## and it picks up Herald, the banner size, and the outline treatment, while
## every other Label under the same Theme stays on Terminal.
const BANNER_TYPE := &"NoggBanner"

## **Every game font size must be a whole multiple of
## `NoggBitmapFont.NOMINAL_SIZE` (12).** Nogg Terminal declares
## `fixed_size = 12` with `FIXED_SIZE_SCALE_INTEGER_ONLY`, so a requested size
## that is not a multiple of 12 is *floored to the next one down* rather than
## interpolated — size 20 silently renders at 12, two thirds of the intended
## height, with no warning. Since these are all `<units> * ui_scale` and
## `ui_scale` is a whole number, keeping the units themselves whole multiples of
## 12 makes that impossible by construction.
##
## `FONT_SIZE_FOOTER` was 10 units (20px at x2) and had to move to 12 on
## adoption: 20 is not a multiple of 12, so the pager footer would have rendered
## at 12px inside a window sized for 20. **The footer is therefore now the same
## size as body text**, and the distinction between them has to come from colour
## or spacing rather than from size. Nothing in the shipping catalog pages
## today, so no live screen currently shows the footer at all.
##
## The dev size is exempt: the dev face is Roboto, a dynamic font, which
## renders any size honestly. 6.5 units keeps it at today's 13 at x2.
const FONT_SIZE_BODY_UNITS := 12.0
const FONT_SIZE_HEADING_UNITS := 12.0
const FONT_SIZE_FOOTER_UNITS := 12.0
const FONT_SIZE_DEV_UNITS := 6.5

## **The banner size follows Herald's grid, not Terminal's: whole multiples of
## `NoggHeraldFont.NOMINAL_SIZE` (13), not 12.** The two faces do not share a
## nominal size, and the failure is silent in the same way described above — a
## banner set to `FONT_SIZE_BODY` (24 at x2) would floor to 13 and render at
## just over half the intended height with no warning. Copying a size across
## from the Terminal constants is therefore always a bug, however reasonable it
## looks; 13 units is one Herald cell and yields 26 at the shipping x2.
const FONT_SIZE_BANNER_UNITS := 13.0

## **A cache key, not a pixel count — and deliberately NOT scaled.** Godot
## cannot synthesise an outline for a bitmap face, so Nogg Terminal ships baked
## outline variants at design widths 0, 1 and 2 (`NoggBitmapFont.OUTLINE_LEVELS`)
## and `outline_size` selects between them. Requesting a width with no baked
## variant draws **no outline at all, silently** — so multiplying this by
## `ui_scale` would ask for width 3 at x3 and lose the outline entirely on
## exactly the screens where text most needs it.
##
## The text server applies the fixed-size scale to whichever variant it finds,
## so requesting 1 at size 24 already yields a 2-device-pixel halo. Scaling here
## would square the zoom.
const OUTLINE_SIZE := 1

## The face's own edge treatment is a one-pixel drop shadow down and right, not
## a symmetric halo — see `docs/UI_DESIGN.md` §3. On strokes exactly one design
## pixel wide a halo of the same width doubles every letter's apparent weight
## and starts closing the counters; the shadow leaves the letterforms alone.
## Unlike `OUTLINE_SIZE` this is drawn by the label rather than baked, so it is
## a real device-pixel offset and does scale.
const SHADOW_OFFSET_UNITS := 1.0
## Not fully opaque: at one design pixel an opaque black shadow reads as a
## second stroke competing with the letter rather than as depth beneath it.
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.72)

static var FONT_SIZE_BODY: int
static var FONT_SIZE_HEADING: int
static var FONT_SIZE_FOOTER: int
static var FONT_SIZE_DEV: int
static var FONT_SIZE_BANNER: int
static var SHADOW_OFFSET: float

# --- Window geometry ------------------------------------------------------

## Thin smooth rim and a deliberately larger exterior black halo. The halo's
## rect draws beyond layout bounds but does not affect them or receive input.
const FRAME_RING_UNITS := 1.0
const WINDOW_CORNER_RADIUS_UNITS := 3.0
const HALO_OUTSET_UNITS := 3.0
const HALO_SPREAD_UNITS := 5.0
const HALO_SHADOW_OFFSET_UNITS := Vector2(0.5, 1.0)
## Where content starts: visible rim plus breathing room.
const CONTENT_INSET_UNITS := FRAME_RING_UNITS + 5.0
## A window's height is a function of capacity, not of content (trait 6).
const ROW_HEIGHT_UNITS := FONT_SIZE_BODY_UNITS + 1.0
## Fixed left edges for the docked status-window grid. The third column is
## reserved for element state; list rows keep their independent HBox layout.
const STATUS_CELL_OFFSET_UNITS := [0.0, 96.0, 192.0]
const STATUS_CELL_TEXT_GAP_UNITS := FONT_SIZE_BODY_UNITS
## Compact gap between a two-character element code and its drawn bar.
const RESONANCE_CELL_SIZE_UNITS := 5.0
const RESONANCE_CELL_GAP_UNITS := 1.5
## An empty cell's outline stroke. 0.5 so it stays the historical 1 device
## pixel at x2 rather than doubling in weight along with everything else —
## a thicker line here reads as a heavier chrome element, not a bigger cell.
const RESONANCE_CELL_BORDER_UNITS := 0.5
const STATUS_CELL_CONTROL_GAP_UNITS := 4.0
## Horizontal gap between a parent window and the child stacked to its right.
const WINDOW_STACK_GAP_UNITS := 4.0

# --- Turn-order rail -------------------------------------------------------
#
# The horizontal strip of portrait tiles across the top of the screen
# (docs/UI_DESIGN.md §8). It replaces the three-row `NoggWindow` turn order,
# which stopped at the round boundary and so could never show the thing that
# most punishes a player who did not see it coming: a fast unit acting last in
# one round and first in the next, twice in a row.
## Portrait tiles are **taller than they are wide**. A square tile forced the
## miniature and the queue number to compete for the same area; the extra height
## gives the number its own band across the top and leaves the model a clean
## square below it.
const TURN_RAIL_TILE_WIDTH_UNITS := 20.0
const TURN_RAIL_TILE_HEIGHT_UNITS := 28.0
const TURN_RAIL_GAP_UNITS := 2.0
## Team-coloured border. At tile size a team-tinted model is not a reliable
## signal on its own, so the frame carries it instead.
const TURN_RAIL_FRAME_UNITS := 1.0
const TURN_RAIL_TOP_UNITS := 5.0
## The active unit sits raised and clear of the row rhythm, so "now" reads as
## detached rather than merely leftmost.
const TURN_RAIL_ACTIVE_LIFT_UNITS := 3.0
## Gap either side of the round divider, on top of the usual tile gap.
const TURN_RAIL_DIVIDER_GAP_UNITS := 4.0
const TURN_RAIL_DIVIDER_WIDTH_UNITS := 1.0
## Health strip along the tile's bottom edge, inside the frame.
const TURN_RAIL_HEALTH_UNITS := 2.0

## Entries shown, across both rounds. Six is enough to cross the boundary with
## room on the far side for the rollover to be visible rather than implied.
const TURN_RAIL_CAPACITY := 6
## Portrait render target, in device pixels. Square, and larger than the tile so
## the bust crop has material to bleed off the corner with.
const TURN_RAIL_PORTRAIT_PX := 64
## Projected next-round entries draw at this alpha: they are a forecast, not a
## fact, and a kill this round will change them.
const TURN_RAIL_PROJECTED_ALPHA := 0.55

# --- Status badges ---------------------------------------------------------
#
# The row of square effect icons carried above each unit. Drawn at native
# resolution and projected, not as world-space sprites: the battle viewport
# drops to 480x360 under the retro presets, where the previous `Sprite3D` badges
# were a few device pixels across and their duration `Label3D` was smaller than
# one.
#
# **A badge rests as a plain colour chip and only becomes an icon under the
# pointer.** At the resting size no icon is legible anyway — an 8-pixel square
# cannot carry a silhouette — so it does not pretend to. It answers "how many
# effects, and roughly what kind" from a flat colour, and hovering answers
# "which one" by growing to full size and crossfading the art in.
#
# **Hover lands at exactly 1:1 with `StatusIconRegistry.SOURCE_PX`.** Resting
# size times `STATUS_BADGE_HOVER_SCALE` must equal that source size at the
# shipping `ui_scale`, or a grown icon is resampled at the one moment the player
# is looking straight at it. `4.0 units * 2 scale * 4.0 hover = 32`. The three
# numbers are chosen together; changing one alone gives the property up.
const STATUS_BADGE_UNITS := 4.0
const STATUS_BADGE_GAP_UNITS := 1.0
const STATUS_BADGE_HOVER_SCALE := 4.0
## Vertical lift from the top of the model's bounds to the badge row.
const STATUS_BADGE_LIFT_UNITS := 5.0
## How long a badge takes to reach its hovered size. Short enough to feel like a
## response rather than an animation; `TWEEN_FOCUS` is the same idea for windows.
const STATUS_BADGE_HOVER_TWEEN := 0.09

## Badges shown before the row collapses the remainder into a counter. Five
## rather than the previous four: with eleven effects in the catalog a unit can
## genuinely carry several, and the old rule spent one of its four slots on the
## counter, so a fifth effect pushed a fourth icon out of sight instead of merely
## adding itself to a tally.
const STATUS_BADGE_MAX_VISIBLE := 5

## How far the overlap search will step before accepting a collision. With
## enough units on one screen point there may be no arrangement that clears
## everything, and a slightly overlapping row beats a frame spent looking for a
## layout that does not exist.
const STATUS_BADGE_DECLUTTER_SLOTS := 8

# --- Action row ------------------------------------------------------------
#
# The four command icons carried above the acting unit, replacing the docked
# command window. Projected and drawn at native resolution for exactly the
# reason the status badges are (see that block above): the battle viewport
# drops to 320x240 under some presets, so anything parented into the 3D world
# would be downsampled with it.
#
# **The icon lands at exactly 1:1 with `ActionIconRegistry.SOURCE_PX`** at the
# shipping scale — `16 units * 2 scale = 32` — the same property
# `STATUS_BADGE_HOVER_SCALE` is chosen to give the badges. Unlike a badge, a
# row icon is never at rest: it is always the size the player reads it at, so
# it must be the authored size at the shipping scale rather than only reaching
# it on hover.
const ACTION_ROW_ICON_UNITS := 16.0
## Clear space between adjacent icons. Wide enough that four icons read as four
## rather than as one strip, without stretching the row so far that its ends
## leave the unit it belongs to.
const ACTION_ROW_GAP_UNITS := 5.0
## Clearance between the top of the unit's model and the bottom of the row.
##
## Larger than `STATUS_BADGE_LIFT_UNITS` on purpose: badges anchor at the same
## point, so a lift equal to theirs would stack the two surfaces on the same
## pixels. This clears a full badge row plus air, which is why it is not simply
## "a bit above the head".
const ACTION_ROW_LIFT_UNITS := STATUS_BADGE_LIFT_UNITS + STATUS_BADGE_UNITS + 4.0
## Gap between the row's icons and the focused action's name beneath them.
const ACTION_ROW_LABEL_GAP_UNITS := 4.0
## The focused icon grows by this much. Deliberately modest: the row has only
## four slots at fixed positions, so focus does not need to be found the way a
## row in an eight-item list does, and a large jump would push the icon into
## its neighbours' space.
const ACTION_ROW_FOCUS_SCALE := 1.25
## How long an icon takes to reach its focused size. Matches
## `STATUS_BADGE_HOVER_TWEEN` so the two icon surfaces respond identically.
const ACTION_ROW_FOCUS_TWEEN := 0.09
## Alpha applied to a command the current phase forbids. Dimmed rather than
## removed: the row's four slots are fixed, so hiding one would leave a hole
## that reads as a missing feature, and a visibly disabled command teaches the
## rule ("you already moved") that hiding it only hides.
const ACTION_ROW_DISABLED_ALPHA := 0.35

## Counts, not lengths. These do not scale — three resonance cells stay three
## cells at every size, and a window holding eight rows holds eight rows.
const RESONANCE_BAR_CELLS := 3
const ROW_CAPACITY_DEFAULT := 8

# --- Window widths ---------------------------------------------------------
#
# Owned here, not in `BattleUIBuilder`/`PlayerCommandMenu`/`NoggWindow`, for the
# same reason every other geometry token moved: each was a local `const` in
# device pixels that could not track `ui_scale`, so a window sized correctly at
# x2 would either waste space at x1 or clip its own content at x4 — the glyphs
# inside it grow with `FONT_SIZE_BODY`; the window that held them did not.
#
# Values are `ceilf(measured design-unit requirement)`, measured directly
# against this project's real worst-case strings at `ui_scale = 1` —
# `debug/measure_px4_widths.gd` (gitignored) — the same
# `CONTENT_INSET * 2 + label + value (+ gap)` formula
# `debug/preview_theme.gd` already used, extended to windows it never covered.
# At x1 a design unit IS a device pixel, so the measurement needed no
# unit conversion that could introduce rounding error.
#
# **Two of these are not merely re-expressed: they were already wrong.**
# Measured against the shipping font at the CURRENT x2 scale — nothing to do
# with UI_SCALE — `PROMPT_WIDTH` (620px) is 76px short of
# "Preview tile (12, 12). Empty-center casting is disabled." (696px needed),
# and `FORECAST_WIDTH` (460px) is 44px short of
# "Cast spends action, cooldown & Resonance" (504px needed). Neither string is
# hypothetical; both come verbatim from `PlayerTurnController`. This predates
# this cycle — `debug/preview_theme.gd`'s own `WIDTH_CASES` never covered
# prompt or forecast content, only command/spell/actor — and is fixed here
# because authoring a new canonical width was the moment to fix it, not a
# reason found and then reproduced.
const COMMAND_WIDTH_UNITS := 110.0
const SPELL_WIDTH_UNITS := 340.0
## Widened on Nogg Terminal adoption: the face is a third wider than XenoText,
## and the longest real status line ("Preview tile (12, 12). Empty-center
## casting is disabled.") needs 460 units against the previous 348.
const PROMPT_WIDTH_UNITS := 470.0
## Likewise: "Cast spends action, cooldown & Resonance" needs 332 units against
## the previous 252.
const FORECAST_WIDTH_UNITS := 340.0
## **Unchanged by the font swap**, and the reason is worth recording. An earlier
## measurement fed this window the string "Elements / Fire, Wind, Ice, Darkness"
## and concluded it needed 288 units. That layout does not exist: the status
## window uses FIXED CELLS at `STATUS_CELL_OFFSETS`, and its third column holds
## a two-character element code plus a drawn `ResonanceBar`, never a
## comma-separated list. Measured against the geometry
## `NoggWindow.add_stat_row()` actually produces, the binding cell needs 243
## units, which 270 already covered. Two of these still fit side by side with
## margins inside a 1152-unit-wide screen at x1.
const STATUS_WINDOW_WIDTH_UNITS := 270.0
## Sized to the row this window actually builds — `"<marker>  <name>"` against
## a `"#<id>"` value column — not to a bare name. Measuring the name alone
## under-sized it and left it truncating mid-word on screen
## ("Envoy of Lig#100"), which is what rendering the real scene caught. The
## worst real row is `NEXT  Polar Weather Wizard` + `#100` at 264 units.
const TURN_ORDER_WIDTH_UNITS := 275.0
## Pager footer: two arrows plus a short page-count label. Still provisional —
## nothing in the shipping catalog pages today, so there is no real content to
## measure against, matching the honest uncertainty the original constant's
## comment already carried.
const PAGER_WIDTH_UNITS := 95.0
const PAGER_ARROW_GAP_UNITS := 3.0
## Deep card (docs/UI_DESIGN.md §8): the held-key reference readout. Measured by
## `debug/measure_deep_card.gd`, which builds the card's real rows for every
## monster in the shipping catalog and reports the widest. That worst case is
## the kill caption — `basic attack by` against the longest monster name in the
## game — at 308 units, not the spell rows, which are the same names the spell
## window carries but without its cursor gutter. Rerun the script if the font,
## `FONT_SIZE_BODY_UNITS`, `CONTENT_INSET_UNITS`, or the card's row set changes.
const DEEP_CARD_WIDTH_UNITS := 310.0
## Fixed top edge. The card grows downward from here rather than staying
## centred, so sweeping from a one-spell unit to a seven-spell one does not make
## the window jump under a stationary pointer.
##
## Derived, not picked, and spelled out as a literal because two of its three
## terms are declared further down this file: `PROMPT_TOP` 34, plus the 25 units
## a one-row window occupies (`CONTENT_INSET_UNITS` twice plus one
## `ROW_HEIGHT_UNITS`), plus `WINDOW_STACK_GAP_UNITS` 4.
##
## A design-unit screen is ~360 tall at every `ui_scale` — that is exactly what
## `UI_SCALE_STEP_HEIGHT` makes true — so this one number clears the prompt
## above and the docked status windows below at every supported scale, with the
## card at its deepest. `debug/measure_deep_card.gd` reports those figures.
const DEEP_CARD_TOP_UNITS := 63.0
## Page size, and therefore the card's maximum height (trait 6). The worst case
## the shipping catalog produces is 16 rows — six fixed rows, seven spells, a
## passive, and two section headings — so the deepest unit in the game pages
## exactly once rather than reaching for most of the screen.
const DEEP_CARD_CAPACITY := 12

## Screen-edge docking offsets. Rendered multi-scale validation found these
## unscaled: the width migration left the positional literals that
## place those windows behind, so at x3 the windows grew while their margins
## did not and the whole HUD crept toward the screen edges. A margin is a length
## like any other and has to scale with what it separates.
const SCREEN_MARGIN_UNITS := 10.0
## Below the turn rail, which owns the top band. The rail is persistent and the
## prompt is transient, so the persistent element holds the stable position —
## see docs/UI_DESIGN.md §8.
const PROMPT_TOP_UNITS := 34.0
const TURN_ORDER_TOP_UNITS := 50.0
## Vertical gap between the forecast window and the command window above which
## it sits.
const FORECAST_GAP_UNITS := 4.0

static var COMMAND_WIDTH: float
static var SPELL_WIDTH: float
static var PROMPT_WIDTH: float
static var FORECAST_WIDTH: float
static var STATUS_WINDOW_WIDTH: float
static var TURN_ORDER_WIDTH: float
static var PAGER_WIDTH: float
static var PAGER_ARROW_GAP: float
static var DEEP_CARD_WIDTH: float
static var DEEP_CARD_TOP: float
static var TURN_RAIL_TILE_WIDTH: float
static var TURN_RAIL_TILE_HEIGHT: float
static var TURN_RAIL_GAP: float
static var TURN_RAIL_FRAME: float
static var TURN_RAIL_TOP: float
static var TURN_RAIL_ACTIVE_LIFT: float
static var TURN_RAIL_DIVIDER_GAP: float
static var TURN_RAIL_DIVIDER_WIDTH: float
static var TURN_RAIL_HEALTH: float

static var SCREEN_MARGIN: float
static var PROMPT_TOP: float
static var TURN_ORDER_TOP: float
static var FORECAST_GAP: float

static var FRAME_RING_PX: int
static var WINDOW_CORNER_RADIUS: int
static var HALO_OUTSET: int
static var HALO_SPREAD: int
static var HALO_SHADOW_OFFSET: Vector2
static var CONTENT_INSET: int
static var ROW_HEIGHT: int
static var STATUS_CELL_OFFSETS: Array
static var STATUS_CELL_TEXT_GAP: int
static var STATUS_BADGE_SIZE: float
static var STATUS_BADGE_GAP: float
static var STATUS_BADGE_LIFT: float
static var ACTION_ROW_ICON: float
static var ACTION_ROW_GAP: float
static var ACTION_ROW_LIFT: float
static var ACTION_ROW_LABEL_GAP: float

static var RESONANCE_CELL_SIZE: float
static var RESONANCE_CELL_GAP: float
static var RESONANCE_CELL_BORDER: float
static var RESONANCE_BAR_WIDTH: float
static var STATUS_CELL_CONTROL_GAP: float
static var WINDOW_STACK_GAP: int


# --- Animation ------------------------------------------------------------
#
# Owned here rather than at each call site for the same reason as the colours:
# Several window behaviours read these, and drift between them would read as
# three different menus.

## Frame tint crossfade. The only thing telling the player which window their
## arrow keys are driving, so it must be visible but not slow.
const TWEEN_FOCUS := 0.12
const TWEEN_WINDOW_OPEN := 0.10
const TWEEN_WINDOW_CLOSE := 0.08
const WINDOW_OPEN_SCALE := 0.94
## Cursor row-to-row move. Interrupting tweens are killed, not queued.
const TWEEN_CURSOR_MOVE := 0.09
const CURSOR_BOB_PERIOD := 0.6
## A length, so it scales — otherwise the bob shrinks to a twitch at x4.
const CURSOR_BOB_UNITS := 1.0
static var CURSOR_BOB_PIXELS: float

## Row label overflow marquee (docs/UI_DESIGN.md §7b). Distance / speed, never
## a fixed duration — a fixed duration makes a long name whip past and a
## barely-overflowing one crawl.
const MARQUEE_DELAY := 1.2
const MARQUEE_END_HOLD := 1.0
## Pixels per second, so it scales: a fixed speed would read twice as fast at
## x1 as at x2 relative to the letters it is moving.
const MARQUEE_SPEED_UNITS := 20.0
static var MARQUEE_SPEED: float

# --- Cursor gutter --------------------------------------------------------
#
# Owned here rather than inside MenuCursor because NoggWindow has to reserve
# space for a cursor it never sees: the two numbers have to agree or the
# cursor lands on the ring (too small) or floats in dead space (too large).

const CURSOR_WIDTH_UNITS := 5.0
const CURSOR_HEIGHT_UNITS := 6.0
## Cursor's resting x: clear of the ring by a few pixels rather than on it.
const CURSOR_INSET_UNITS := FRAME_RING_UNITS + 2.0
## Extra left padding for rows in a window that hosts a cursor, measured from
## CONTENT_INSET. Covers the cursor at its widest bob excursion plus a gap, so
## the arrow never touches either the ring or the text:
##   ring ends 12 | cursor 16..28 (incl. bob) | text starts 34
## (those figures are device pixels at x2, which is the scale they were
## measured at; the agreement they describe is between the design units.)
const CURSOR_GUTTER_WIDTH_UNITS := 6.0

static var CURSOR_WIDTH: float
static var CURSOR_HEIGHT: float
static var CURSOR_INSET: float
static var CURSOR_GUTTER_WIDTH: float


## Derives every device-pixel token from its design units. The single writer of
## the static vars above, and the reason they can be trusted to agree with each
## other: nothing recomputes a subset.
##
## `_static_init` runs on class load, so the tokens are correct at the default
## scale before any caller has had a chance to read one — there is no window in
## which a consumer could observe an unconfigured value.
static func _static_init() -> void:
	_recompute()


static func _recompute() -> void:
	FONT_SIZE_BODY = _scaled_int(FONT_SIZE_BODY_UNITS)
	FONT_SIZE_HEADING = _scaled_int(FONT_SIZE_HEADING_UNITS)
	FONT_SIZE_FOOTER = _scaled_int(FONT_SIZE_FOOTER_UNITS)
	FONT_SIZE_DEV = _scaled_int(FONT_SIZE_DEV_UNITS)
	FONT_SIZE_BANNER = _scaled_int(FONT_SIZE_BANNER_UNITS)
	SHADOW_OFFSET = _scaled(SHADOW_OFFSET_UNITS)

	FRAME_RING_PX = _scaled_int(FRAME_RING_UNITS)
	WINDOW_CORNER_RADIUS = _scaled_int(WINDOW_CORNER_RADIUS_UNITS)
	HALO_OUTSET = _scaled_int(HALO_OUTSET_UNITS)
	HALO_SPREAD = _scaled_int(HALO_SPREAD_UNITS)
	HALO_SHADOW_OFFSET = Vector2(
		_scaled(HALO_SHADOW_OFFSET_UNITS.x), _scaled(HALO_SHADOW_OFFSET_UNITS.y)
	)
	CONTENT_INSET = _scaled_int(CONTENT_INSET_UNITS)
	ROW_HEIGHT = _scaled_int(ROW_HEIGHT_UNITS)
	STATUS_CELL_TEXT_GAP = _scaled_int(STATUS_CELL_TEXT_GAP_UNITS)
	STATUS_CELL_CONTROL_GAP = _scaled(STATUS_CELL_CONTROL_GAP_UNITS)
	WINDOW_STACK_GAP = _scaled_int(WINDOW_STACK_GAP_UNITS)

	var offsets: Array = []
	for units: float in STATUS_CELL_OFFSET_UNITS:
		offsets.append(_scaled(units))
	STATUS_CELL_OFFSETS = offsets

	STATUS_BADGE_SIZE = _scaled(STATUS_BADGE_UNITS)
	STATUS_BADGE_GAP = _scaled(STATUS_BADGE_GAP_UNITS)
	STATUS_BADGE_LIFT = _scaled(STATUS_BADGE_LIFT_UNITS)
	ACTION_ROW_ICON = _scaled(ACTION_ROW_ICON_UNITS)
	ACTION_ROW_GAP = _scaled(ACTION_ROW_GAP_UNITS)
	ACTION_ROW_LIFT = _scaled(ACTION_ROW_LIFT_UNITS)
	ACTION_ROW_LABEL_GAP = _scaled(ACTION_ROW_LABEL_GAP_UNITS)

	RESONANCE_CELL_SIZE = _scaled(RESONANCE_CELL_SIZE_UNITS)
	RESONANCE_CELL_GAP = _scaled(RESONANCE_CELL_GAP_UNITS)
	RESONANCE_CELL_BORDER = _scaled(RESONANCE_CELL_BORDER_UNITS)
	# Derived from the already-rounded cell and gap rather than from their design
	# units, so the bar is exactly as wide as the cells actually drawn. Deriving
	# it from the units and rounding once would disagree with the sum by a pixel
	# at scales where the gap rounds up.
	RESONANCE_BAR_WIDTH = (
		float(RESONANCE_BAR_CELLS) * RESONANCE_CELL_SIZE
		+ float(RESONANCE_BAR_CELLS - 1) * RESONANCE_CELL_GAP
	)

	CURSOR_WIDTH = _scaled(CURSOR_WIDTH_UNITS)
	CURSOR_HEIGHT = _scaled(CURSOR_HEIGHT_UNITS)
	CURSOR_INSET = _scaled(CURSOR_INSET_UNITS)
	CURSOR_GUTTER_WIDTH = _scaled(CURSOR_GUTTER_WIDTH_UNITS)
	CURSOR_BOB_PIXELS = _scaled(CURSOR_BOB_UNITS)
	MARQUEE_SPEED = _scaled(MARQUEE_SPEED_UNITS)

	COMMAND_WIDTH = _scaled(COMMAND_WIDTH_UNITS)
	SPELL_WIDTH = _scaled(SPELL_WIDTH_UNITS)
	PROMPT_WIDTH = _scaled(PROMPT_WIDTH_UNITS)
	FORECAST_WIDTH = _scaled(FORECAST_WIDTH_UNITS)
	STATUS_WINDOW_WIDTH = _scaled(STATUS_WINDOW_WIDTH_UNITS)
	TURN_ORDER_WIDTH = _scaled(TURN_ORDER_WIDTH_UNITS)
	PAGER_WIDTH = _scaled(PAGER_WIDTH_UNITS)
	PAGER_ARROW_GAP = _scaled(PAGER_ARROW_GAP_UNITS)
	DEEP_CARD_WIDTH = _scaled(DEEP_CARD_WIDTH_UNITS)
	DEEP_CARD_TOP = _scaled(DEEP_CARD_TOP_UNITS)
	TURN_RAIL_TILE_WIDTH = _scaled(TURN_RAIL_TILE_WIDTH_UNITS)
	TURN_RAIL_TILE_HEIGHT = _scaled(TURN_RAIL_TILE_HEIGHT_UNITS)
	TURN_RAIL_GAP = _scaled(TURN_RAIL_GAP_UNITS)
	TURN_RAIL_FRAME = _scaled(TURN_RAIL_FRAME_UNITS)
	TURN_RAIL_TOP = _scaled(TURN_RAIL_TOP_UNITS)
	TURN_RAIL_ACTIVE_LIFT = _scaled(TURN_RAIL_ACTIVE_LIFT_UNITS)
	TURN_RAIL_DIVIDER_GAP = _scaled(TURN_RAIL_DIVIDER_GAP_UNITS)
	TURN_RAIL_DIVIDER_WIDTH = _scaled(TURN_RAIL_DIVIDER_WIDTH_UNITS)
	TURN_RAIL_HEALTH = _scaled(TURN_RAIL_HEALTH_UNITS)

	SCREEN_MARGIN = _scaled(SCREEN_MARGIN_UNITS)
	PROMPT_TOP = _scaled(PROMPT_TOP_UNITS)
	TURN_ORDER_TOP = _scaled(TURN_ORDER_TOP_UNITS)
	FORECAST_GAP = _scaled(FORECAST_GAP_UNITS)

## Content tint for a window that has handed focus to a child. Roughly the
## same brightness drop the frame takes (FRAME_INACTIVE is ~44% of
## FRAME_ACTIVE), so the text and the border read as dimming together rather
## than as two unrelated effects. Multiplied over the row colours, so a
## disabled row inside an inactive window correctly ends up dimmest of all.
const CONTENT_ACTIVE_MODULATE := Color(1.0, 1.0, 1.0, 1.0)
const CONTENT_INACTIVE_MODULATE := Color(0.45, 0.47, 0.52, 1.0)



## Height of a window with the given row capacity, frame inset included.
static func window_height(row_capacity: int) -> float:
	return float(CONTENT_INSET * 2 + row_capacity * ROW_HEIGHT)


## The battle UI Theme. Assign to a root Control and every Label, Panel, and
## container beneath it inherits from it.
##
## The two overrides exist for `debug/preview_theme.gd`'s font switcher, which
## is how a font candidate gets evaluated against real window content before it
## is adopted. Production callers pass nothing.
static func build_game_theme(
		font_path: String = GAME_FONT_PATH,
		font_size: int = FONT_SIZE_BODY) -> Theme:
	var theme := Theme.new()
	var font := _load_pixel_font(font_path)
	# Not affected by the `font_path` override: that exists so the preview
	# harness can audition a *body* face against real window content, and
	# swapping the banner face out from under it would confuse the comparison.
	var banner_font := _load_pixel_font(BANNER_FONT_PATH)

	theme.default_font = font
	theme.default_font_size = font_size

	# The window body. Corner radius stays at or below FRAME_MARGIN so the
	# fill never pokes outside the frame ring's rounded corners.
	var window_style := StyleBoxFlat.new()
	window_style.bg_color = WINDOW_FILL
	window_style.set_corner_radius_all(WINDOW_CORNER_RADIUS)
	window_style.set_border_width_all(0)
	# The inset lives on the stylebox rather than in a MarginContainer, so any
	# PanelContainer under this theme clears its own frame automatically.
	# NoggWindow cannot use a Container root and applies CONTENT_INSET
	# as explicit offsets instead — see build_window_frame().
	window_style.content_margin_left = CONTENT_INSET
	window_style.content_margin_right = CONTENT_INSET
	window_style.content_margin_top = CONTENT_INSET
	window_style.content_margin_bottom = CONTENT_INSET
	theme.set_stylebox("panel", "PanelContainer", window_style)
	theme.set_stylebox("panel", "Panel", window_style)

	# Shadow, not halo. Nogg Terminal's strokes are one design pixel, and a
	# symmetric outline of the same width doubles every letter's apparent weight
	# and starts closing the counters — see docs/UI_DESIGN.md §3. The baked halo
	# stays reachable through `OUTLINE_SIZE` for anything that needs to survive
	# an arbitrary bright background, but the default treatment is the drop
	# shadow the reference face itself uses.
	#
	# `shadow_outline_size` is left at 0 deliberately: anything larger draws the
	# shadow from the outline atlas and reintroduces exactly the thickening the
	# shadow exists to avoid.
	for type in ["Label", "RichTextLabel"]:
		theme.set_font("font", type, font)
		theme.set_font_size("font_size", type, font_size)
		theme.set_color("font_color", type, TEXT_PRIMARY)
		theme.set_color("font_shadow_color", type, SHADOW_COLOR)
		theme.set_constant("shadow_offset_x", type, int(SHADOW_OFFSET))
		theme.set_constant("shadow_offset_y", type, int(SHADOW_OFFSET))
		theme.set_constant("shadow_outline_size", type, 0)
		theme.set_color("font_outline_color", type, OUTLINE)
		theme.set_constant("outline_size", type, 0)

	# Banners: Nogg Herald, outlined rather than shadowed.
	#
	# A type variation rather than a second Theme, so one Theme at the battle
	# root still covers everything and a banner is just a Label with one
	# property set. Every other Label beneath it stays on Terminal.
	#
	# **Outline, not drop shadow — the opposite of the body default, for exactly
	# the same reason.** The body rule exists because Terminal's strokes are one
	# design pixel, so a one-pixel halo doubles their apparent weight and closes
	# the counters. Herald's stems are two pixels, so the same halo is half a
	# stroke — which is the proportion the reference art actually carries: white
	# letters, one pixel of black all round, and no shadow behind them. The
	# shadow constants are zeroed here deliberately rather than left to inherit.
	theme.set_type_variation(BANNER_TYPE, "Label")
	theme.set_font("font", BANNER_TYPE, banner_font)
	theme.set_font_size("font_size", BANNER_TYPE, FONT_SIZE_BANNER)
	theme.set_color("font_color", BANNER_TYPE, TEXT_PRIMARY)
	theme.set_color("font_outline_color", BANNER_TYPE, OUTLINE)
	theme.set_constant("outline_size", BANNER_TYPE, OUTLINE_SIZE)
	theme.set_constant("shadow_offset_x", BANNER_TYPE, 0)
	theme.set_constant("shadow_offset_y", BANNER_TYPE, 0)
	theme.set_constant("shadow_outline_size", BANNER_TYPE, 0)

	# Rows are plain Controls, not Buttons (docs/UI_DESIGN.md §5). These
	# entries exist only so a stray Button does not arrive wearing Godot's
	# default chrome; nothing in the game UI should need them.
	var button_flat := StyleBoxFlat.new()
	button_flat.bg_color = Color(0, 0, 0, 0)
	button_flat.set_corner_radius_all(0)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		theme.set_stylebox(state, "Button", button_flat)
	theme.set_font("font", "Button", font)
	theme.set_font_size("font_size", "Button", font_size)
	theme.set_color("font_color", "Button", TEXT_PRIMARY)
	theme.set_color("font_hover_color", "Button", TEXT_ACCENT)
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)
	theme.set_color("font_shadow_color", "Button", SHADOW_COLOR)
	theme.set_constant("shadow_offset_x", "Button", int(SHADOW_OFFSET))
	theme.set_constant("shadow_offset_y", "Button", int(SHADOW_OFFSET))
	theme.set_constant("shadow_outline_size", "Button", 0)
	theme.set_color("font_outline_color", "Button", OUTLINE)
	theme.set_constant("outline_size", "Button", 0)

	theme.set_constant("separation", "BoxContainer", 0)
	theme.set_constant("separation", "HBoxContainer", 0)
	theme.set_constant("separation", "VBoxContainer", 0)

	return theme


## The developer-bar Theme. Flat, square, unstyled on purpose.
static func build_dev_theme() -> Theme:
	var theme := Theme.new()
	var font: Font = load(DEV_FONT_PATH)

	theme.default_font = font
	theme.default_font_size = FONT_SIZE_DEV

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = DEV_FILL
	panel_style.border_color = DEV_BORDER
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(0)
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 6
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	theme.set_stylebox("panel", "PanelContainer", panel_style)
	theme.set_stylebox("panel", "Panel", panel_style)

	for type in ["Label", "RichTextLabel", "Button", "CheckButton", "OptionButton"]:
		theme.set_font("font", type, font)
		theme.set_font_size("font_size", type, FONT_SIZE_DEV)
		theme.set_color("font_color", type, DEV_TEXT)

	theme.set_constant("separation", "BoxContainer", 4)
	theme.set_constant("separation", "HBoxContainer", 4)
	theme.set_constant("separation", "VBoxContainer", 4)

	return theme


## Shared smooth window layers. Each Panel receives a local stylebox built from
## centralized tokens; callers never construct a frame, body, or halo directly.
static func _rounded_window_style(fill: Color, corner_radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_border_width_all(0)
	style.set_corner_radius_all(corner_radius)
	style.anti_aliasing = true
	return style


static func _base_window_panel(name: String) -> Panel:
	var panel := Panel.new()
	panel.name = name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	return panel


## Deliberately overdraws the layout bounds to give the box a quiet black
## silhouette. Its corner radius grows by the same outset, keeping the halo
## concentric with the body and rim rather than producing a second shape.
static func build_window_halo() -> Panel:
	var halo := _base_window_panel("Halo")
	halo.offset_left = -HALO_OUTSET
	halo.offset_top = -HALO_OUTSET
	halo.offset_right = HALO_OUTSET
	halo.offset_bottom = HALO_OUTSET
	var style := _rounded_window_style(HALO_FILL, WINDOW_CORNER_RADIUS + HALO_OUTSET)
	style.shadow_color = HALO_SHADOW
	style.shadow_size = HALO_SPREAD
	style.shadow_offset = HALO_SHADOW_OFFSET
	halo.add_theme_stylebox_override("panel", style)
	return halo


## The translucent near-black body. Its geometry exactly matches the rim.
static func build_window_body() -> Panel:
	var body := _base_window_panel("Body")
	body.add_theme_stylebox_override(
		"panel", _rounded_window_style(WINDOW_FILL, WINDOW_CORNER_RADIUS)
	)
	return body


## Transparent, thin pale rim. Focus tints this panel only; the halo remains
## stable while the content dims, so focus reads as state rather than glow.
static func build_window_frame() -> Panel:
	var rim := _base_window_panel("Rim")
	var style := _rounded_window_style(Color(0.0, 0.0, 0.0, 0.0), WINDOW_CORNER_RADIUS)
	style.border_color = Color.WHITE
	style.set_border_width_all(FRAME_RING_PX)
	rim.add_theme_stylebox_override("panel", style)
	rim.self_modulate = FRAME_ACTIVE
	return rim

## A banner `Label` wearing the Herald variation.
##
## Prefer this over setting `theme_type_variation` by hand. A variation only
## resolves for a node that is actually beneath a Theme carrying it, so a banner
## parented outside the battle root — or read back before it is parented —
## silently falls back to Terminal at body size rather than erroring. Keeping
## the one property that matters in one place makes that harder to get wrong.
##
## Autowrap is left at the caller's discretion: banners in the reference art are
## hand-broken across lines, and wrapping needs a width this has no opinion on.
static func make_banner_label(text: String = "") -> Label:
	var label := Label.new()
	label.theme_type_variation = BANNER_TYPE
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## Loads a TTF with every smoothing feature off. A pixel font rendered with
## antialiasing, hinting, or subpixel positioning turns to mush.
## Loads the game face with every smoothing feature off. A pixel font rendered
## with antialiasing, hinting, or subpixel positioning turns to mush.
##
## **Two kinds of face arrive here and they load differently.** A baked
## `FontFile` resource (`.res` — Nogg Terminal, the shipping face) already
## contains its glyph cache and is loaded whole; calling `load_dynamic_font()`
## on it would produce an empty font. A `.ttf`/`.otf` is rasterised on demand
## and must go through `load_dynamic_font()`. The smoothing settings are applied
## either way, but they only mean anything for the dynamic case — a bitmap face
## has nothing to smooth.
static func _load_pixel_font(path: String) -> FontFile:
	if path.get_extension().to_lower() == "res":
		var baked: FontFile = load(path)
		if baked == null:
			push_error("NoggTheme: could not load baked font at %s" % path)
			return FontFile.new()
		return baked
	var font := FontFile.new()
	font.load_dynamic_font(path)
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.force_autohinter = false
	font.generate_mipmaps = false
	return font
