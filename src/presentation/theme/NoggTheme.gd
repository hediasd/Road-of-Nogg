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

## Near-black translucent window body. The board reads through it.
const WINDOW_FILL := Color(0.012, 0.012, 0.020, 0.76)
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

# --- Dev palette ----------------------------------------------------------
#
# Deliberately drab and deliberately off-brand. Developer controls must never
# be mistakable for game affordances (docs/UI_DESIGN.md §9).
const DEV_FILL := Color(0.063, 0.078, 0.094, 0.92)
const DEV_BORDER := Color(0.227, 0.267, 0.314)
const DEV_TEXT := Color(0.776, 0.808, 0.847)

# --- Typography -----------------------------------------------------------

## XenoText reports a 12px monospace advance at size 24, about half the width
## of the outgoing Shining Force face. Existing windows retain their widths as
## deliberate breathing room; do not re-dock panels around the narrower text.
const GAME_FONT_PATH := "res://assets/Fonts/xenotext.otf"
const DEV_FONT_PATH := "res://assets/Fonts/Roboto-Regular.ttf"

## Integer sizes only. A pixel font at a fractional size smears.
## Keep XenoText at integer sizes. The final visual pass owns any decision to
## enable smoothing, along with rerunning `debug/preview_theme.gd` metrics.
const FONT_SIZE_BODY := 24
const FONT_SIZE_HEADING := 24
const FONT_SIZE_FOOTER := 20
const FONT_SIZE_DEV := 13
const OUTLINE_SIZE := 2

# --- Window geometry ------------------------------------------------------

## Thin smooth rim and a deliberately larger exterior black halo. The halo's
## rect draws beyond layout bounds but does not affect them or receive input.
const FRAME_RING_PX := 2
const WINDOW_CORNER_RADIUS := 6
const HALO_OUTSET := 6
const HALO_SPREAD := 10
const HALO_SHADOW_OFFSET := Vector2(1.0, 2.0)
## Where content starts: visible rim plus breathing room.
const CONTENT_INSET := FRAME_RING_PX + 10
## A window's height is a function of capacity, not of content (trait 6).
const ROW_HEIGHT := FONT_SIZE_BODY + 2
const ROW_CAPACITY_DEFAULT := 8
## Fixed left edges for the docked status-window grid. The third column is
## reserved for element state; list rows keep their independent HBox layout.
const STATUS_CELL_OFFSETS := [0.0, 192.0, 384.0]
const STATUS_CELL_TEXT_GAP := FONT_SIZE_BODY
## Compact gap between a two-character element code and its drawn bar.
const RESONANCE_BAR_CELLS := 3
const RESONANCE_CELL_SIZE := 10.0
const RESONANCE_CELL_GAP := 3.0
const RESONANCE_BAR_WIDTH := RESONANCE_BAR_CELLS * RESONANCE_CELL_SIZE + (RESONANCE_BAR_CELLS - 1) * RESONANCE_CELL_GAP
const STATUS_CELL_CONTROL_GAP := 8.0
## Horizontal gap between a parent window and the child stacked to its right.
const WINDOW_STACK_GAP := 8

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
const CURSOR_BOB_PIXELS := 2.0
const CURSOR_BOB_PERIOD := 0.6

## Row label overflow marquee (docs/UI_DESIGN.md §7b). Distance / speed, never
## a fixed duration — a fixed duration makes a long name whip past and a
## barely-overflowing one crawl.
const MARQUEE_DELAY := 1.2
const MARQUEE_SPEED := 40.0
const MARQUEE_END_HOLD := 1.0

# --- Cursor gutter --------------------------------------------------------
#
# Owned here rather than inside MenuCursor because NoggWindow has to reserve
# space for a cursor it never sees: the two numbers have to agree or the
# cursor lands on the ring (too small) or floats in dead space (too large).

const CURSOR_WIDTH := 10.0
const CURSOR_HEIGHT := 12.0
## Cursor's resting x: clear of the ring by a few pixels rather than on it.
const CURSOR_INSET := FRAME_RING_PX + 4.0
## Extra left padding for rows in a window that hosts a cursor, measured from
## CONTENT_INSET. Covers the cursor at its widest bob excursion plus a gap, so
## the arrow never touches either the ring or the text:
##   ring ends 12 | cursor 16..28 (incl. bob) | text starts 34
const CURSOR_GUTTER_WIDTH := 12.0

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

	for type in ["Label", "RichTextLabel"]:
		theme.set_font("font", type, font)
		theme.set_font_size("font_size", type, font_size)
		theme.set_color("font_color", type, TEXT_PRIMARY)
		theme.set_color("font_outline_color", type, OUTLINE)
		theme.set_constant("outline_size", type, OUTLINE_SIZE)

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
	theme.set_color("font_outline_color", "Button", OUTLINE)
	theme.set_constant("outline_size", "Button", OUTLINE_SIZE)

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

## Loads a TTF with every smoothing feature off. A pixel font rendered with
## antialiasing, hinting, or subpixel positioning turns to mush.
static func _load_pixel_font(path: String) -> FontFile:
	var font := FontFile.new()
	font.load_dynamic_font(path)
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.force_autohinter = false
	font.generate_mipmaps = false
	return font
