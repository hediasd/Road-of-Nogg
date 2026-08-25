## Builds the Nogg Herald face from its pixel source.
##
## Herald is the display face: item banners, hint plates, act titles -- the
## places the reference art puts big outlined text over the board. It is a
## companion to Nogg Terminal, not a replacement, and the two divide the work
## along a hard line:
##
##   * **Terminal** is monospaced by construction (advance 8, one-pixel stroke).
##     Everything in the battle HUD that measures itself -- fixed status cells,
##     three-digit padding, `debug/measure_px4_widths.gd` -- depends on that.
##   * **Herald** is proportional, two pixels of stroke, and *kerned negative*.
##     It must never be used where a column has to line up.
##
## The negative kerning is the point of the face, not a detail of it. In the
## reference art `h` and `t` overlap: the `t` crossbar reaches left across the
## gap and lands on the `h` shoulder, so the pair reads as one welded shape.
## The same happens to `ff`, `ft`, `Fl`, `ry`, and every pair where one glyph's
## arm has empty space to occupy. A face that merely sets these letters side by
## side loses the texture entirely, so pair values are authored in the source
## next to the glyphs and baked into the `FontFile` kerning table.
##
## Everything else -- the ASCII-art source, the strict parse, the dilated
## outline levels, the integer-only scaling -- follows `NoggBitmapFont`
## deliberately, so there is one way to author a face in this project.
##
## The content-scale caveat documented on `NoggBitmapFont` applies here too: a
## face whose glyphs are injected into the cache loses them when oversampling
## changes. See that file's header for the full account.

class_name NoggHeraldFont
extends RefCounted

const SOURCE_PATH := "res://assets/Fonts/NoggHerald/glyphs.txt"
const ATLAS_PATH := "res://assets/Fonts/NoggHerald/nogg_herald_atlas.png"
const SPECIMEN_PATH := "res://assets/Fonts/NoggHerald/nogg_herald_specimen.png"
const RESOURCE_PATH := "res://assets/Fonts/NoggHerald/NoggHerald.res"

## Rows per glyph. Widths vary per glyph -- that is the whole difference from
## Terminal -- but the body height is fixed so the band structure below holds
## for every letter.
const CELL_HEIGHT := 13

## The vertical bands, as row indices into the cell. Every number here was
## measured off the reference art at native resolution, not estimated:
##
##   row  0      the dot of `i`/`j`, and headroom for accents
##   rows 1-8    cap and ascender band (cap height 8)
##   rows 3-8    x-height band (x-height 6)
##   -- baseline sits immediately below row 8 --
##   rows 9-10   descender band (descender 2)
##   rows 11-12  bottom leading
##
## Ascent 9 and descent 4 sum to 13, which is the reference's line height
## exactly -- its three baselines fall on rows 13, 26, and 39.
const ASCENT := 9
const DESCENT := 4
const CAP_TOP_ROW := 1
const X_TOP_ROW := 3
const BASELINE_ROW := 8

## Blank columns inserted between two glyph boxes when no pair value applies.
## Glyph art carries no side bearings of its own: a glyph is exactly as wide as
## its ink, and all spacing lives here or in the kerning table. That is what
## makes a pair value readable -- `-1` closes the gap so the letters touch, `-2`
## drives them one pixel into each other.
const LETTER_GAP := 1

## The font size at which the atlas is pixel-exact.
const NOMINAL_SIZE := 13

## Digits are held to one advance regardless of their ink, so a changing number
## never reflows the text around it. Herald is not a HUD face, but a banner
## reading "1200 GOLD" should not jitter as the count ticks.
##
## Seven, not eight: every digit is drawn six wide, so seven puts them on the
## same one-pixel rhythm as the letters around them. Eight would set numbers
## visibly looser than the words they sit in.
const TABULAR_DIGIT_ADVANCE := 7

const OUTLINE_LEVELS: Array[int] = [0, 1, 2]

const ATLAS_COLUMNS := 16
const ATLAS_PADDING := 1

const INK := "#"


## Parses the glyph source.
##
## Returns `{"glyphs": {codepoint: Array[String]}, "kerning": {Vector2i: int}}`,
## or an empty dictionary on any malformed input. As with Terminal the
## validation is strict on purpose: a glyph one row short, or a pair naming a
## letter that does not exist, would otherwise ship as a quietly wrong banner.
static func parse_source(path: String = SOURCE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Nogg Herald source missing: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Nogg Herald source unreadable: %s (error %d)" % [
			path, FileAccess.get_open_error()
		])
		return {}

	var glyphs: Dictionary = {}
	var kerning: Dictionary = {}
	var pending: int = -1
	var pendingWidth := 0
	var rows: Array[String] = []
	var lineNumber := 0

	while not file.eof_reached():
		var line := file.get_line()
		lineNumber += 1
		var isRow := pending >= 0 and rows.size() < CELL_HEIGHT
		if not isRow:
			if line.is_empty() or line.begins_with("#"):
				continue
			if line.begins_with("&"):
				if not _parseKerning(line, lineNumber, kerning):
					return {}
				continue
			if not line.begins_with("@"):
				push_error("Nogg Herald source line %d: expected '@ <hex> <label> w=<n>', got '%s'" % [
					lineNumber, line
				])
				return {}
			var parts := line.split(" ", false)
			if parts.size() < 3 or not parts[1].begins_with("0x"):
				push_error("Nogg Herald source line %d: malformed glyph header '%s'" % [
					lineNumber, line
				])
				return {}
			var widthToken: String = parts[parts.size() - 1]
			if not widthToken.begins_with("w="):
				push_error("Nogg Herald source line %d: glyph header must end in 'w=<n>', got '%s'" % [
					lineNumber, line
				])
				return {}
			pendingWidth = widthToken.substr(2).to_int()
			if pendingWidth <= 0:
				push_error("Nogg Herald source line %d: glyph width must be positive, got %d" % [
					lineNumber, pendingWidth
				])
				return {}
			pending = parts[1].hex_to_int()
			if glyphs.has(pending):
				push_error("Nogg Herald source line %d: codepoint 0x%X declared twice" % [
					lineNumber, pending
				])
				return {}
			rows = []
			continue

		if line.length() != pendingWidth:
			push_error("Nogg Herald source line %d: codepoint 0x%X row %d is %d wide, declared %d" % [
				lineNumber, pending, rows.size(), line.length(), pendingWidth
			])
			return {}
		rows.append(line)
		if rows.size() == CELL_HEIGHT:
			glyphs[pending] = rows.duplicate()
			pending = -1

	if pending >= 0:
		push_error("Nogg Herald source ended mid-glyph: codepoint 0x%X has %d of %d rows" % [
			pending, rows.size(), CELL_HEIGHT
		])
		return {}
	if glyphs.is_empty():
		push_error("Nogg Herald source declared no glyphs: %s" % path)
		return {}

	for pair: Vector2i in kerning.keys():
		if not glyphs.has(pair.x) or not glyphs.has(pair.y):
			push_error("Nogg Herald kerning pair 0x%X/0x%X names an undeclared glyph." % [
				pair.x, pair.y
			])
			return {}

	return {"glyphs": glyphs, "kerning": kerning}


## Reads one `& <left> <right> <delta>` pair line.
##
## Letters are written literally rather than as hex -- `& h t -2` is legible as
## the pair it describes, and pair authoring is the part of this face a human
## revisits most.
static func _parseKerning(line: String, lineNumber: int, kerning: Dictionary) -> bool:
	var parts := line.split(" ", false)
	if parts.size() != 4:
		push_error("Nogg Herald source line %d: expected '& <left> <right> <delta>', got '%s'" % [
			lineNumber, line
		])
		return false
	if parts[1].length() != 1 or parts[2].length() != 1:
		push_error("Nogg Herald source line %d: kerning sides must be single characters." % lineNumber)
		return false
	if not parts[3].lstrip("-").is_valid_int():
		push_error("Nogg Herald source line %d: kerning delta '%s' is not an integer." % [
			lineNumber, parts[3]
		])
		return false
	var pair := Vector2i(parts[1].unicode_at(0), parts[2].unicode_at(0))
	if kerning.has(pair):
		push_error("Nogg Herald source line %d: pair '%s%s' declared twice." % [
			lineNumber, parts[1], parts[2]
		])
		return false
	kerning[pair] = parts[3].to_int()
	return true


## The horizontal advance of one glyph: its ink box plus the standard gap,
## except for digits, which are padded to a common width.
static func advance_of(codepoint: int, glyphs: Dictionary) -> int:
	if codepoint >= 0x30 and codepoint <= 0x39:
		return TABULAR_DIGIT_ADVANCE
	var rows: Array = glyphs[codepoint]
	return (rows[0] as String).length() + LETTER_GAP


## Rasterizes every glyph into one atlas image at the given outline dilation.
##
## Cells are sized to the widest glyph so the sheet stays a readable character
## table; the per-glyph UV rect is still tight to that glyph's own box, so the
## slack costs texture space and nothing else.
static func build_atlas(glyphs: Dictionary, outline: int = 0) -> Dictionary:
	var widest := 0
	for codepoint: int in glyphs.keys():
		widest = maxi(widest, (glyphs[codepoint][0] as String).length())
	var cell := Vector2i(widest, CELL_HEIGHT) + Vector2i.ONE * (outline * 2)
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
		var rows: Array = glyphs[codepoint]
		var glyphWidth: int = (rows[0] as String).length()
		var origin := Vector2i(
			(index % ATLAS_COLUMNS) * stride.x + ATLAS_PADDING,
			(index / ATLAS_COLUMNS) * stride.y + ATLAS_PADDING
		)
		_blitGlyph(image, rows, origin, outline)
		rects[codepoint] = Rect2i(
			origin, Vector2i(glyphWidth, CELL_HEIGHT) + Vector2i.ONE * (outline * 2)
		)

	return {"image": image, "rects": rects, "cell": cell}


## Assembles the `FontFile`, including the kerning table.
static func build_font(parsed: Dictionary) -> FontFile:
	if parsed.is_empty():
		return null
	var glyphs: Dictionary = parsed["glyphs"]
	var kerning: Dictionary = parsed["kerning"]
	if glyphs.is_empty():
		return null

	var font := FontFile.new()
	font.font_name = "Nogg Herald"
	font.style_name = "Bold"
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.force_autohinter = false
	font.generate_mipmaps = false
	font.multichannel_signed_distance_field = false
	font.fixed_size = NOMINAL_SIZE
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY

	font.set_cache_ascent(0, NOMINAL_SIZE, float(ASCENT))
	font.set_cache_descent(0, NOMINAL_SIZE, float(DESCENT))
	font.set_cache_underline_position(0, NOMINAL_SIZE, 2.0)
	font.set_cache_underline_thickness(0, NOMINAL_SIZE, 1.0)

	for outline: int in OUTLINE_LEVELS:
		_populateVariant(font, glyphs, outline)

	# Kerning is keyed by size alone, like advance: the outline passes must not
	# space themselves differently from the fill pass or the two would drift.
	for pair: Vector2i in kerning.keys():
		font.set_kerning(0, NOMINAL_SIZE, pair, Vector2(float(kerning[pair]), 0.0))

	return font


static func build_font_from_source(path: String = SOURCE_PATH) -> FontFile:
	return build_font(parse_source(path))


## Draws one glyph's ink, dilated by `outline` design pixels.
##
## Square (Chebyshev) kernel, for the reason given on `NoggBitmapFont`: a cross
## kernel leaves diagonal terminals half-exposed. At two pixels of stroke the
## face has more diagonals than Terminal does, so it matters more here.
static func _blitGlyph(image: Image, rows: Array, origin: Vector2i, outline: int) -> void:
	var width: int = (rows[0] as String).length()
	for y: int in range(CELL_HEIGHT):
		var row: String = rows[y]
		for x: int in range(width):
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
		font.set_glyph_offset(0, key, codepoint, Vector2(-outline, -(ASCENT + outline)))
		font.set_glyph_advance(
			0, NOMINAL_SIZE, codepoint, Vector2(advance_of(codepoint, glyphs), 0)
		)


## Lays out a string and returns the ink coordinates, applying advances and
## pair values exactly as the baked font will.
##
## This is the face's own measurement, independent of the text server, and it
## exists so the specimen renderer and the tests can see what a pair value
## actually does to two letters without standing up a window.
static func layout_line(text: String, parsed: Dictionary) -> Dictionary:
	var glyphs: Dictionary = parsed["glyphs"]
	var kerning: Dictionary = parsed["kerning"]
	var placements: Array = []
	var pen := 0
	var previous := -1
	for index: int in range(text.length()):
		var codepoint := text.unicode_at(index)
		if not glyphs.has(codepoint):
			push_error("Nogg Herald cannot lay out '%s': no glyph for 0x%X." % [text, codepoint])
			return {}
		if previous >= 0:
			var pair := Vector2i(previous, codepoint)
			if kerning.has(pair):
				pen += kerning[pair]
		placements.append({"codepoint": codepoint, "x": pen})
		pen += advance_of(codepoint, glyphs)
		previous = codepoint
	return {"placements": placements, "width": pen}
