## Design tokens and Theme factories for the battle UI.
##
## This file is the single source of truth for every colour, font, spacing, and
## timing value in the battle HUD. No colour literal may appear anywhere else
## under `src/presentation/` — that rule is what keeps a restyle a one-file
## edit. See `docs/UI_DESIGN.md` for the reasoning behind each token.
##
## Nothing here applies itself. `build_game_theme()` and `build_dev_theme()`
## return Theme resources for a caller to assign; `build_window_frame()`
## returns a configured NinePatchRect. Consumers arrive in UI-2 and UI-3.

class_name NoggTheme
extends RefCounted

# --- Canvas layers --------------------------------------------------------
#
# Game UI renders ABOVE the CRT overlay and therefore takes no scanlines, mask,
# or vignette. That is deliberate (docs/UI_DESIGN.md §10): crisp menus over a
# filtered scene keep the pixel font readable at every scanline strength and
# stop the 16px bevel shimmering as mask size changes.
const CRT_LAYER := -20
const GAME_LAYER := 10
const DEV_LAYER := 20

## UI-8's `ui_through_crt` toggle. The CRT shader (`crt_display.gdshader`)
## reads `hint_screen_texture`, i.e. it distorts whatever was already drawn to
## screen at the moment ITS canvas item draws — so making the game UI take
## the CRT treatment is a matter of where the shader's OWN layer sits relative
## to GAME_LAYER, not of moving the game canvas itself (which stays a stable
## constant other code depends on). Both values stay below DEV_LAYER, so the
## dev bar is never affected either way — see docs/UI_DESIGN.md §10.
const CRT_OVERLAY_LAYER_DEFAULT := -10
const CRT_OVERLAY_LAYER_THROUGH_UI := GAME_LAYER + 1

# --- Game palette ---------------------------------------------------------

## Translucent window body. The board reads through it.
const WINDOW_FILL := Color(0.024, 0.059, 0.149, 0.86)
## For windows that must not be read through (confirm prompts).
const WINDOW_FILL_DEEP := Color(0.016, 0.035, 0.102, 0.94)
## Frame tint for the window holding focus.
const FRAME_ACTIVE := Color(0.659, 0.847, 1.0)
## Frame tint for a parent window whose child has focus.
const FRAME_INACTIVE := Color(0.290, 0.353, 0.447)

const TEXT_PRIMARY := Color(1.0, 1.0, 1.0)
## Disabled entries: spent commands, spells on cooldown. Dim, never hidden.
const TEXT_DIM := Color(0.494, 0.576, 0.690)
## Right-column values and headings.
const TEXT_ACCENT := Color(1.0, 0.843, 0.400)
const TEXT_FORECAST := Color(0.608, 0.906, 1.0)
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

## `shining-force-ii-small.otf` (reports itself as "Shining Force II (Small)"),
## NOT `Shining Force 2.ttf`. Both are real Shining Force faces and both load
## without error, but the .ttf is the thin 1px-stroke variant ("Shining Force
## 2 b") and reads weak in a menu. The .otf is the chunky 2px-stroke face.
## Compared side by side 2026-07-30 via `debug/preview_font.gd`; the .otf runs
## roughly twice the advance width of the .ttf, which ROW_HEIGHT and the window
## widths below are sized against.
const GAME_FONT_PATH := "res://assets/Fonts/shining-force-ii-small.otf"
const DEV_FONT_PATH := "res://assets/Fonts/Roboto-Regular.ttf"

## Integer sizes only. A pixel font at a fractional size smears.
## 24 chosen against a reference screenshot 2026-07-30; ROW_HEIGHT and every
## window width in docs/UI_DESIGN.md §8 are measured at this size, so changing
## it means rerunning `debug/preview_theme.gd` and updating both.
const FONT_SIZE_BODY := 24
const FONT_SIZE_HEADING := 24
const FONT_SIZE_FOOTER := 20
const FONT_SIZE_DEV := 13
const OUTLINE_SIZE := 4

# --- Window geometry ------------------------------------------------------

const FRAME_TEXTURE_PATH := "res://assets/ui/MenuFull.png"
## The 9-patch slice size in *source* pixels. MenuFull.png is 48x48: 16px
## corners, 16px edges, 16px centre. This is an art fact, not a layout choice —
## do not tune it. Tune FRAME_SCALE instead.
const FRAME_SOURCE_MARGIN := 16
## Integer upscale applied to the frame art with nearest-neighbour filtering.
##
## The authored ring is only 4 source pixels thick — 1 dark, 2 white, 1 dark —
## which renders far too thin for the JRPG window it is imitating. Scaling the
## texture (rather than stretching the NinePatchRect, which would not thicken
## the corners) turns each source pixel into a crisp NxN block, so 3 gives a
## 12px ring that still reads as pixel art.
const FRAME_SCALE := 3
## Patch margin in screen pixels, after the upscale.
const FRAME_MARGIN := FRAME_SOURCE_MARGIN * FRAME_SCALE
## Thickness of the ring the player actually sees: 4 authored pixels, scaled.
const FRAME_RING_PX := 4 * FRAME_SCALE
## Where content starts, measured from the window edge: the visible ring plus
## breathing room. It is deliberately *not* FRAME_MARGIN — most of the patch
## margin is the stripped body and draws nothing, so insetting content by the
## full margin would waste 36px a side. Tune the padding term, never
## FRAME_SOURCE_MARGIN.
const CONTENT_INSET := FRAME_RING_PX + 10
## A window's height is a function of capacity, not of content (trait 6).
## The font measures exactly FONT_SIZE_BODY px tall, so this is the glyph box
## plus 2px of air — deliberately tight, the way a JRPG command list stacks.
## It cannot go below the font height; the Label enforces its own minimum.
const ROW_HEIGHT := FONT_SIZE_BODY + 2
const ROW_CAPACITY_DEFAULT := 8
## Fixed left edges for the docked status-window grid. The third column is
## reserved for element state; list rows keep their independent HBox layout.
const STATUS_CELL_OFFSETS := [0.0, 192.0, 384.0]
const STATUS_CELL_TEXT_GAP := FONT_SIZE_BODY
## Compact gap between a two-character element code and its drawn bar.
const STATUS_CELL_CONTROL_GAP := 8.0

## Matches the scaled corner curve so the fill never pokes outside the ring.
const WINDOW_CORNER_RADIUS := 12
## Horizontal gap between a parent window and the child stacked to its right.
const WINDOW_STACK_GAP := 8

# --- Animation ------------------------------------------------------------
#
# Owned here rather than at each call site for the same reason as the colours:
# UI-3, UI-4, and UI-6 all read these, and drift between them would read as
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
	# NoggWindow (UI-3) cannot use a Container root and applies CONTENT_INSET
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


## The window frame: MenuFull.png as a 9-patch with its opaque grey centre
## discarded, so the translucent body behind it shows through. `draw_center =
## false` is what makes a translucent body with an opaque bevel possible at
## all — a single StyleBoxTexture modulate cannot do both.
##
## The art is greyscale, so `self_modulate` alone switches the frame between
## its focused and unfocused states.
##
## **The parent must be a plain Control, never a Container.** A Container
## force-fits every child into its content rect, which insets the frame by
## CONTENT_INSET and leaves the ring covering the first and last glyph of each
## row. Verified against `debug/preview_theme.gd` on 2026-07-30. The window
## composition that works is a `Control` root holding a full-rect `Panel` for
## the fill, a content container inset by CONTENT_INSET, and this frame last.
static func build_window_frame() -> NinePatchRect:
	var frame := NinePatchRect.new()
	frame.name = "Frame"
	frame.texture = _frame_ring_texture()
	frame.draw_center = false
	frame.patch_margin_left = FRAME_MARGIN
	frame.patch_margin_right = FRAME_MARGIN
	frame.patch_margin_top = FRAME_MARGIN
	frame.patch_margin_bottom = FRAME_MARGIN
	frame.self_modulate = FRAME_ACTIVE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	return frame


## `MenuFull.png` ships as a complete window, not a bare frame: alongside the
## white bevel and the near-black outer edge it carries a baked translucent
## black body, `(0, 0, 0, 155)`, filling both the centre patch *and* the inner
## part of all four edge tiles.
##
## We split that one image into two 9-patch layers — body and ring — and stack
## them. Both are sliced from the same source at the same patch margins, so
## their corners are identical *by construction*.
##
## That matters more than it sounds. The first version drew the body as a
## `StyleBoxFlat` rounded rect instead, and a rounded rect cannot reproduce a
## pixel-art corner staircase: the fill poked out past the ring around all four
## corners, showing as a dark wedge outside the frame. Any approach that
## describes the body geometry a second time will reintroduce that gap. Do not
## replace either layer with a StyleBox.
##
## The body is the only colour in the file with fractional alpha, which makes
## the split unambiguous and leaves the bevel and outer edge untouched.
##
## Cached: each mask is a pixel walk plus an upscale, run once per process
## rather than once per window.
static var _ring_texture: ImageTexture = null
static var _body_texture: ImageTexture = null


## The bevel and outer edge, with the baked body removed. Tinted per focus
## state, so it must not carry the fill colour.
static func _frame_ring_texture() -> Texture2D:
	if _ring_texture == null:
		_ring_texture = _masked_frame_texture(false)
	return _ring_texture


## The body only, flattened to opaque white so `self_modulate` reproduces
## WINDOW_FILL exactly, alpha included.
static func _frame_body_texture() -> Texture2D:
	if _body_texture == null:
		_body_texture = _masked_frame_texture(true)
	return _body_texture


static func _masked_frame_texture(keep_body: bool) -> ImageTexture:
	var source: Texture2D = load(FRAME_TEXTURE_PATH)
	var image: Image = source.get_image()
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			var is_body := pixel.a > 0.0 and pixel.a < 1.0
			if is_body == keep_body:
				# Keep. The body flattens to white so a modulate lands exactly.
				if keep_body:
					image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))
			else:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
	# Nearest-neighbour upscale so each authored pixel becomes a crisp block.
	# Scaling the texture rather than stretching the NinePatchRect is what
	# thickens the corners too; stretching would only thicken the edges.
	if FRAME_SCALE != 1:
		image.resize(
			image.get_width() * FRAME_SCALE,
			image.get_height() * FRAME_SCALE,
			Image.INTERPOLATE_NEAREST
		)
	return ImageTexture.create_from_image(image)


## The window body: the art's own fill shape, tinted to WINDOW_FILL. Pair it
## with `build_window_frame()` and add the frame last so it draws on top.
static func build_window_body() -> NinePatchRect:
	var body := NinePatchRect.new()
	body.name = "Body"
	body.texture = _frame_body_texture()
	body.draw_center = true
	body.patch_margin_left = FRAME_MARGIN
	body.patch_margin_right = FRAME_MARGIN
	body.patch_margin_top = FRAME_MARGIN
	body.patch_margin_bottom = FRAME_MARGIN
	body.self_modulate = WINDOW_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	return body


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
