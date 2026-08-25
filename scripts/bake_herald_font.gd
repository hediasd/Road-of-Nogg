#!/usr/bin/env -S godot --headless --script
## Bakes the Nogg Herald pixel source into its shippable build outputs.
##
##   Godot_v4.4-stable_win64.exe --headless --path . --script res://scripts/bake_herald_font.gd
##
## Writes three files beside the source:
##
##   NoggHerald.res              the FontFile the game loads, textures embedded.
##   nogg_herald_atlas.png       the glyphs as a viewable character table.
##   nogg_herald_specimen.png    the reference strings, set with pair values
##                               applied and drawn the way the game draws them.
##
## The specimen is not decoration. This face's whole character lives in how
## adjacent letters collide, and that is invisible in a character table -- a
## glyph sheet shows 39 correct letters whether or not `ht` welds. The specimen
## is the only output where a wrong pair value is actually visible.
##
## Flags:
##   --check    validate the source and report metrics without writing anything
##
## Exits non-zero when the source is malformed or a write fails.

extends SceneTree

const HeraldScript = preload("res://src/presentation/theme/NoggHeraldFont.gd")

## Printable ASCII. The source is expected to cover exactly this range: a gap
## renders as a missing character in game -- and not as a visible tofu box,
## because Godot silently substitutes a system font -- while an extra glyph
## outside it means the source and this expectation have drifted apart.
const FIRST_CODEPOINT := 0x20
const LAST_CODEPOINT := 0x7E

const EXIT_SOURCE_INVALID := 2
const EXIT_WRITE_FAILED := 3
const EXIT_VERIFY_FAILED := 4

## Scale the specimen is drawn at. Four is enough to read a one-pixel overlap
## on screen without the sheet becoming unwieldy.
const SPECIMEN_SCALE := 4
const SPECIMEN_MARGIN := 4
const SPECIMEN_LINE_GAP := 3

## Lines drawn on the specimen. The first block reproduces the reference art
## verbatim so the two can be held side by side; the last block isolates the
## pairs, because a weld that is right inside a word can still be wrong when
## the letters carry no context.
const SPECIMEN_LINES: Array[String] = [
	"Use Flute of Light",
	"to Remove Tree",
	"SILVER SWORD",
	"FLUTE OF LIGHT",
	"Frea",
	"Use Awakened Staff",
	"of Sarana to Dry Up Lake",
	"Left Mine Right Mine",
	"Awaken, staff!",
	"ht ff ft gh rt",
	"Tree Dry Frea staff",
	"ABCDEFGHIJKLM",
	"NOPQRSTUVWXYZ",
	"abcdefghijklm",
	"nopqrstuvwxyz",
	"0123456789 1200 GOLD",
	"!\"#$%&'()*+,-./",
	":;<=>?@[\\]^_`{|}~",
]

## Background and ink, matched to the reference art so the specimen is judged
## under the contrast the face actually ships against.
const SPECIMEN_BACKGROUND := Color("6ab417")
const SPECIMEN_FILL := Color.WHITE
const SPECIMEN_OUTLINE := Color.BLACK


func _init() -> void:
	var checkOnly := "--check" in OS.get_cmdline_args() or "--check" in OS.get_cmdline_user_args()

	var parsed := HeraldScript.parse_source()
	if parsed.is_empty():
		quit(EXIT_SOURCE_INVALID)
		return
	var glyphs: Dictionary = parsed["glyphs"]
	var kerning: Dictionary = parsed["kerning"]

	print("BAKE_HERALD glyphs=%d pairs=%d height=%d ascent=%d descent=%d nominal=%d" % [
		glyphs.size(),
		kerning.size(),
		HeraldScript.CELL_HEIGHT,
		HeraldScript.ASCENT,
		HeraldScript.DESCENT,
		HeraldScript.NOMINAL_SIZE,
	])
	if not _reportCoverage(glyphs):
		quit(EXIT_SOURCE_INVALID)
		return
	if not _reportMetrics(glyphs, kerning):
		quit(EXIT_SOURCE_INVALID)
		return

	if checkOnly:
		print("BAKE_HERALD status=CHECK_ONLY")
		quit(0)
		return

	var atlas: Dictionary = HeraldScript.build_atlas(glyphs, 0)
	var atlasImage: Image = atlas["image"]
	var atlasError := atlasImage.save_png(HeraldScript.ATLAS_PATH)
	print("BAKE_HERALD atlas=%s size=%dx%d error=%d" % [
		ProjectSettings.globalize_path(HeraldScript.ATLAS_PATH),
		atlasImage.get_width(), atlasImage.get_height(), atlasError,
	])
	if atlasError != OK:
		quit(EXIT_WRITE_FAILED)
		return

	var specimen := _renderSpecimen(parsed)
	if specimen == null:
		quit(EXIT_SOURCE_INVALID)
		return
	var specimenError := specimen.save_png(HeraldScript.SPECIMEN_PATH)
	print("BAKE_HERALD specimen=%s size=%dx%d error=%d" % [
		ProjectSettings.globalize_path(HeraldScript.SPECIMEN_PATH),
		specimen.get_width(), specimen.get_height(), specimenError,
	])
	if specimenError != OK:
		quit(EXIT_WRITE_FAILED)
		return

	var font: FontFile = HeraldScript.build_font(parsed)
	if font == null:
		quit(EXIT_SOURCE_INVALID)
		return
	var saveError := ResourceSaver.save(font, HeraldScript.RESOURCE_PATH)
	print("BAKE_HERALD resource=%s error=%d" % [
		ProjectSettings.globalize_path(HeraldScript.RESOURCE_PATH), saveError
	])
	if saveError != OK:
		quit(EXIT_WRITE_FAILED)
		return

	quit(0 if _verifyRoundTrip(parsed) else EXIT_VERIFY_FAILED)


## Confirms the source covers printable ASCII exactly, naming what is wrong
## rather than reporting a count mismatch and leaving the caller to diff it.
func _reportCoverage(glyphs: Dictionary) -> bool:
	var missing: Array[String] = []
	for codepoint: int in range(FIRST_CODEPOINT, LAST_CODEPOINT + 1):
		if not glyphs.has(codepoint):
			missing.append("0x%X '%s'" % [codepoint, char(codepoint)])
	var extra: Array[String] = []
	for codepoint: int in glyphs.keys():
		if codepoint < FIRST_CODEPOINT or codepoint > LAST_CODEPOINT:
			extra.append("0x%X" % codepoint)
	if missing.is_empty() and extra.is_empty():
		return true
	if not missing.is_empty():
		push_error("Nogg Herald source is missing %d glyph(s): %s" % [
			missing.size(), ", ".join(missing)
		])
	if not extra.is_empty():
		push_error("Nogg Herald source declares %d glyph(s) outside printable ASCII: %s" % [
			extra.size(), ", ".join(extra)
		])
	return false


## Reports the widths the face actually produces, and refuses a pair value that
## would drive two letters more than one pixel into each other.
##
## A pair tighter than that is almost always a typo rather than a decision: at
## two pixels of overlap the letters stop reading as two letters, which is the
## line between the reference art's texture and an unreadable smear.
func _reportMetrics(glyphs: Dictionary, kerning: Dictionary) -> bool:
	var narrowest := 99
	var widest := 0
	for codepoint: int in glyphs.keys():
		var advance: int = HeraldScript.advance_of(codepoint, glyphs)
		narrowest = mini(narrowest, advance)
		widest = maxi(widest, advance)
	print("BAKE_HERALD advance min=%d max=%d gap=%d" % [
		narrowest, widest, HeraldScript.LETTER_GAP
	])

	var offenders: Array[String] = []
	for pair: Vector2i in kerning.keys():
		if kerning[pair] < -(HeraldScript.LETTER_GAP + 1):
			offenders.append("%s%s=%d" % [
				char(pair.x), char(pair.y), kerning[pair]
			])
	if offenders.is_empty():
		return true
	push_error("Nogg Herald pair values overlap by more than one pixel: %s" % ", ".join(offenders))
	return false


## Draws the specimen lines at 1x, then scales the sheet with nearest
## filtering. Drawing small and scaling once keeps every stroke and every
## overlap on the design grid; drawing at scale would let rounding hide exactly
## the one-pixel collisions this sheet exists to show.
func _renderSpecimen(parsed: Dictionary) -> Image:
	var glyphs: Dictionary = parsed["glyphs"]
	var lineHeight := HeraldScript.CELL_HEIGHT + SPECIMEN_LINE_GAP

	var layouts: Array = []
	var widest := 0
	for line: String in SPECIMEN_LINES:
		var layout := HeraldScript.layout_line(line, parsed)
		if layout.is_empty():
			return null
		layouts.append(layout)
		widest = maxi(widest, layout["width"])

	var size := Vector2i(
		widest + SPECIMEN_MARGIN * 2,
		lineHeight * layouts.size() + SPECIMEN_MARGIN * 2
	)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(SPECIMEN_BACKGROUND)

	# Two passes over the whole line rather than per glyph: an outline drawn
	# glyph by glyph would paint black over the neighbour a pair value just
	# welded to it, erasing the join this sheet is meant to show.
	for index: int in range(layouts.size()):
		var origin := Vector2i(
			SPECIMEN_MARGIN, SPECIMEN_MARGIN + index * lineHeight
		)
		_drawLine(image, layouts[index], glyphs, origin, true)
		_drawLine(image, layouts[index], glyphs, origin, false)

	image.resize(size.x * SPECIMEN_SCALE, size.y * SPECIMEN_SCALE, Image.INTERPOLATE_NEAREST)
	return image


func _drawLine(
		image: Image, layout: Dictionary, glyphs: Dictionary,
		origin: Vector2i, outlinePass: bool) -> void:
	for placement: Dictionary in layout["placements"]:
		var rows: Array = glyphs[placement["codepoint"]]
		var width: int = (rows[0] as String).length()
		for y: int in range(HeraldScript.CELL_HEIGHT):
			var row: String = rows[y]
			for x: int in range(width):
				if row[x] != HeraldScript.INK:
					continue
				var at := Vector2i(origin.x + placement["x"] + x, origin.y + y)
				if not outlinePass:
					_plot(image, at, SPECIMEN_FILL)
					continue
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						_plot(image, at + Vector2i(dx, dy), SPECIMEN_OUTLINE)


func _plot(image: Image, at: Vector2i, color: Color) -> void:
	if at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height():
		return
	image.set_pixel(at.x, at.y, color)


## Loads the saved resource back and measures it.
##
## Two things are being proved, and the second is the one that can actually
## fail: that the glyph caches survived serialization (the hazard documented on
## `NoggBitmapFont`), and that the *kerning table* survived with them. A face
## that reloads with its glyphs but not its pairs measures wider than it should
## and sets every banner slightly loose -- a failure subtle enough to ship.
func _verifyRoundTrip(parsed: Dictionary) -> bool:
	var reloaded = ResourceLoader.load(
		HeraldScript.RESOURCE_PATH, "FontFile", ResourceLoader.CACHE_MODE_IGNORE
	)
	if reloaded == null or not (reloaded is FontFile):
		push_error("Baked Herald did not load back as a FontFile.")
		return false
	var font := reloaded as FontFile
	var nominal: int = HeraldScript.NOMINAL_SIZE

	var unkerned := "oxo"
	var kerned := "oho"
	var sample := "Light"
	var expected: int = HeraldScript.layout_line(sample, parsed)["width"]
	var measured := font.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1.0, nominal)
	print("BAKE_HERALD verify '%s' measured=%.1f expected=%d (unkerned refs %s/%s)" % [
		sample, measured.x, expected, unkerned, kerned
	])

	var doubled := font.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1.0, nominal * 2)
	if not is_equal_approx(doubled.x, measured.x * 2.0):
		push_error(
			"Baked Herald does not scale by whole multiples: '%s' is %.1f at %d and %.1f at %d."
			% [sample, measured.x, nominal, doubled.x, nominal * 2]
		)
		return false

	if not is_equal_approx(measured.x, float(expected)):
		push_error(
			"Baked Herald measures %.1f for '%s'; the source lays it out at %d. "
			% [measured.x, sample, expected]
			+ "The kerning table did not survive the round trip."
		)
		return false

	print("BAKE_HERALD status=OK")
	return true
