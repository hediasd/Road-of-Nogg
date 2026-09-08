## Builds the Nogg Terminal face from its pixel source.
##
## The font is authored as ASCII art in `assets/Fonts/NoggTerminal/glyphs.txt`
## and baked into a `FontFile` here. Nothing about it is a vector outline, so
## there is no rasterizer to fight: what the source draws is exactly what
## renders, at every integer scale.
##
## Two callers use this class and they want different things:
##
##   * `scripts/bake_bitmap_font.gd` parses the source once and saves the
##     resulting `FontFile` (and a viewable atlas PNG) as build outputs. That is
##     what shipping code should load — no text parsing at runtime.
##   * The VFX debug scene parses the source *live*, so editing a glyph and
##     pressing R shows the change without a re-bake. That loop is the entire
##     reason the source is text rather than a hand-painted PNG.
##
## **A face built this way does not survive a content-scale change.** Changing
## the window's content scale changes the text server's font oversampling, which
## clears cached glyph data. A dynamic face re-rasterizes itself from the font
## bytes it still holds; this one has no bytes — its glyphs were injected
## directly into the cache — so they are gone, and every string silently falls
## back to a system font with ascent and descent reported as zero.
##
## Measured, not theorised: switching the debug scene's canvas stretch at
## runtime reproduces it every time, and calling `build_font` again is the only
## recovery. Any consumer that can see the content scale change — a window
## resize under `canvas_items` stretch, a fullscreen toggle — must rebuild, or
## must run under a stretch mode whose scale never changes. That constraint is
## the strongest argument against a manually-injected face and for letting
## Godot's own bitmap-font importer own a `.fnt`, which it can regenerate.
##
## See `docs/UI_DESIGN.md` for the grid and the style rules the glyphs obey.

class_name NoggBitmapFont
extends RefCounted

const SOURCE_PATH := "res://assets/Fonts/NoggTerminal/glyphs.txt"
const ATLAS_PATH := "res://assets/Fonts/NoggTerminal/nogg_terminal_atlas.png"
const RESOURCE_PATH := "res://assets/Fonts/NoggTerminal/NoggTerminal.res"

## The design cell. Every glyph fills it and every glyph advances CELL.x, so
## the face is monospaced by construction rather than by convention.
const CELL := Vector2i(8, 12)
const ADVANCE := 8
## Baseline sits immediately below row 8 of the cell; rows 9-10 are descenders.
const ASCENT := 9
const DESCENT := 3

## The font size at which the atlas is pixel-exact. Combined with
## FIXED_SIZE_SCALE_INTEGER_ONLY below, a request for 24 renders at exactly 2x
## and a request for 36 at exactly 3x. Sizes that are not multiples of this
## cannot be honoured without smearing, and are floored to the nearest whole
## multiple by the text server rather than interpolated.
const NOMINAL_SIZE := 12

## Outline widths baked into the atlas, in design pixels. Godot cannot
## synthesize an outline for a bitmap face the way it does for a dynamic one --
## `outline_size` is simply ignored unless a glyph exists under that cache key
## -- so each supported width is dilated and stored up front. Level 0 is the
## glyph itself.
const OUTLINE_LEVELS: Array[int] = [0, 1, 2]

## Atlas grid width, in glyphs. 16 columns puts printable ASCII in six rows and
## keeps the codepoint's low nibble as the column, so the atlas is readable as a
## character table when something looks wrong.
const ATLAS_COLUMNS := 16
## Transparent gutter around each cell. Nearest filtering plus integer scaling
## means bleed should be impossible, but a one-pixel margin costs nothing and
## removes the question.
const ATLAS_PADDING := 1

const INK := "#"


## Parses the glyph source into `{codepoint: Array[String] of CELL.y rows}`.
##
## Returns an empty dictionary and pushes an error on any malformed input. The
## validation is deliberately strict -- a glyph one row short would otherwise
## ship as a quietly garbled letter instead of as a failure.
static func parse_source(path: String = SOURCE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Nogg Terminal source missing: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Nogg Terminal source unreadable: %s (error %d)" % [
			path, FileAccess.get_open_error()
		])
		return {}

	var glyphs: Dictionary = {}
	var pending: int = -1
	var rows: Array[String] = []
	var lineNumber := 0

	while not file.eof_reached():
		var line := file.get_line()
		lineNumber += 1
		# Comments and blank lines separate glyphs; they are never rows, so a
		# glyph that has started collecting rows must not see one.
		var isRow := pending >= 0 and rows.size() < CELL.y
		if not isRow:
			if line.is_empty() or line.begins_with("#"):
				continue
			if not line.begins_with("@"):
				push_error("Nogg Terminal source line %d: expected '@ <hex> <label>', got '%s'" % [
					lineNumber, line
				])
				return {}
			var parts := line.split(" ", false)
			if parts.size() < 2 or not parts[1].begins_with("0x"):
				push_error("Nogg Terminal source line %d: malformed glyph header '%s'" % [
					lineNumber, line
				])
				return {}
			pending = parts[1].hex_to_int()
			if glyphs.has(pending):
				push_error("Nogg Terminal source line %d: codepoint 0x%X declared twice" % [
					lineNumber, pending
				])
				return {}
			rows = []
			continue

		if line.length() != CELL.x:
			push_error("Nogg Terminal source line %d: codepoint 0x%X row %d is %d wide, expected %d" % [
				lineNumber, pending, rows.size(), line.length(), CELL.x
			])
			return {}
		rows.append(line)
		if rows.size() == CELL.y:
			glyphs[pending] = rows.duplicate()
			pending = -1

	if pending >= 0:
		push_error("Nogg Terminal source ended mid-glyph: codepoint 0x%X has %d of %d rows" % [
			pending, rows.size(), CELL.y
		])
		return {}
	if glyphs.is_empty():
		push_error("Nogg Terminal source declared no glyphs: %s" % path)
	return glyphs


## Rasterizes every glyph into one atlas image at the given outline dilation.
##
## Returns `{"image": Image, "rects": {codepoint: Rect2i}, "cell": Vector2i}`.
## Glyphs are drawn opaque white so `font_color` and `font_outline_color` tint
## them; nothing about the palette is baked in.
static func build_atlas(glyphs: Dictionary, outline: int = 0) -> Dictionary:
	var cell := CELL + Vector2i.ONE * (outline * 2)
	var stride := cell + Vector2i.ONE * (ATLAS_PADDING * 2)
	var codepoints := glyphs.keys()
	codepoints.sort()
	var rowCount := int(ceil(float(codepoints.size()) / float(ATLAS_COLUMNS)))
	var image := Image.create(
		stride.x * ATLAS_COLUMNS, stride.y * maxi(rowCount, 1), false, Image.FORMAT_RGBA8
	)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))

	var rects: Dictionary = {}
	for index: int in range(codepoints.size()):
		var codepoint: int = codepoints[index]
		var origin := Vector2i(
			(index % ATLAS_COLUMNS) * stride.x + ATLAS_PADDING,
			(index / ATLAS_COLUMNS) * stride.y + ATLAS_PADDING
		)
		_blitGlyph(image, glyphs[codepoint], origin, outline)
		rects[codepoint] = Rect2i(origin, cell)

	return {"image": image, "rects": rects, "cell": cell}


## Assembles the `FontFile`. Every smoothing feature is off for the same reason
## `NoggTheme._load_pixel_font` turns them off on the dynamic faces: a pixel
## font that is filtered, hinted, or subpixel-positioned turns to mush.
static func build_font(glyphs: Dictionary) -> FontFile:
	if glyphs.is_empty():
		return null
	var font := FontFile.new()
	font.font_name = "Nogg Terminal"
	font.style_name = "Regular"
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.force_autohinter = false
	font.generate_mipmaps = false
	font.multichannel_signed_distance_field = false
	# Integer-only scaling is the whole contract. Without it a request for an
	# awkward size would blend the atlas up and undo the point of the face.
	font.fixed_size = NOMINAL_SIZE
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY

	font.set_cache_ascent(0, NOMINAL_SIZE, float(ASCENT))
	font.set_cache_descent(0, NOMINAL_SIZE, float(DESCENT))
	font.set_cache_underline_position(0, NOMINAL_SIZE, 2.0)
	font.set_cache_underline_thickness(0, NOMINAL_SIZE, 1.0)

	for outline: int in OUTLINE_LEVELS:
		_populateVariant(font, glyphs, outline)
	return font


## Convenience for the debug harness: source text straight to a usable face.
static func build_font_from_source(path: String = SOURCE_PATH) -> FontFile:
	return build_font(parse_source(path))


## Draws one glyph's ink into the atlas, dilated by `outline` design pixels.
##
## Dilation uses a square (Chebyshev) kernel rather than a cross, so corners are
## covered too and the halo stays a constant width all the way around a diagonal
## stroke. A cross kernel leaves diagonal terminals half-exposed, which reads as
## a broken outline exactly where a pixel font can least afford one.
static func _blitGlyph(
		image: Image, rows: Array, origin: Vector2i, outline: int) -> void:
	for y: int in range(CELL.y):
		var row: String = rows[y]
		for x: int in range(CELL.x):
			if row[x] != INK:
				continue
			if outline <= 0:
				image.set_pixel(origin.x + x, origin.y + y, Color.WHITE)
				continue
			for dy: int in range(-outline, outline + 1):
				for dx: int in range(-outline, outline + 1):
					image.set_pixel(
						origin.x + x + outline + dx,
						origin.y + y + outline + dy,
						Color.WHITE
					)


## Registers one outline level's atlas and per-glyph metrics on the font.
##
## The glyph index is the codepoint itself. That is not a shortcut: a font with
## no FreeType face behind it has no separate glyph space, and the engine's own
## BMFont importer indexes the same way.
static func _populateVariant(font: FontFile, glyphs: Dictionary, outline: int) -> void:
	var baked := build_atlas(glyphs, outline)
	var key := Vector2i(NOMINAL_SIZE, outline)
	font.set_texture_image(0, key, 0, baked["image"])

	var rects: Dictionary = baked["rects"]
	for codepoint: int in rects.keys():
		var rect: Rect2i = rects[codepoint]
		font.set_glyph_texture_idx(0, key, codepoint, 0)
		font.set_glyph_uv_rect(0, key, codepoint, Rect2(rect))
		font.set_glyph_size(0, key, codepoint, Vector2(rect.size))
		# The dilated cell grows around the design cell in both axes, so the
		# outline's own draw origin moves out by the same amount its bitmap did.
		font.set_glyph_offset(
			0, key, codepoint, Vector2(-outline, -(ASCENT + outline))
		)
		# Advance is keyed by size alone, not by outline width: an outlined
		# glyph must occupy exactly the same cell as its unoutlined self or the
		# two passes would drift apart across a line.
		font.set_glyph_advance(0, NOMINAL_SIZE, codepoint, Vector2(ADVANCE, 0))
