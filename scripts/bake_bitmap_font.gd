#!/usr/bin/env -S godot --headless --script
## Bakes the Nogg Terminal pixel source into its shippable build outputs.
##
##   Godot_v4.4-stable_win64.exe --headless --path . --script res://scripts/bake_bitmap_font.gd
##
## Writes two files beside the source:
##
##   NoggTerminal.res           the FontFile the game loads. Textures are
##                              embedded, so there is no sidecar PNG to lose
##                              and no bitmap-font importer to depend on.
##   nogg_terminal_atlas.png    the same glyphs as a viewable character table.
##                              Nothing loads it; it exists so a broken glyph
##                              can be found by looking rather than by guessing.
##
## Flags:
##   --check    validate the source and report metrics without writing anything
##
## Exits non-zero when the source is malformed or a write fails, so a scripted
## caller can tell a bad glyph from a successful bake.

extends SceneTree

const NoggBitmapFontScript = preload("res://src/presentation/theme/NoggBitmapFont.gd")

## Printable ASCII. The source is expected to cover exactly this range: a gap
## would render as a missing character in game, and an extra glyph outside it is
## a sign the source and this expectation have drifted apart.
const FIRST_CODEPOINT := 0x20
const LAST_CODEPOINT := 0x7E

const EXIT_SOURCE_INVALID := 2
const EXIT_WRITE_FAILED := 3
const EXIT_VERIFY_FAILED := 4


func _init() -> void:
	var checkOnly := "--check" in OS.get_cmdline_args() or "--check" in OS.get_cmdline_user_args()

	var glyphs := NoggBitmapFontScript.parse_source()
	if glyphs.is_empty():
		quit(EXIT_SOURCE_INVALID)
		return
	if not _reportCoverage(glyphs):
		quit(EXIT_SOURCE_INVALID)
		return

	print("BAKE_FONT glyphs=%d cell=%dx%d advance=%d ascent=%d descent=%d nominal=%d" % [
		glyphs.size(),
		NoggBitmapFontScript.CELL.x,
		NoggBitmapFontScript.CELL.y,
		NoggBitmapFontScript.ADVANCE,
		NoggBitmapFontScript.ASCENT,
		NoggBitmapFontScript.DESCENT,
		NoggBitmapFontScript.NOMINAL_SIZE,
	])

	if checkOnly:
		print("BAKE_FONT status=CHECK_ONLY")
		quit(0)
		return

	var atlas: Dictionary = NoggBitmapFontScript.build_atlas(glyphs, 0)
	var atlasImage: Image = atlas["image"]
	var atlasError := atlasImage.save_png(NoggBitmapFontScript.ATLAS_PATH)
	print("BAKE_FONT atlas=%s size=%dx%d error=%d" % [
		ProjectSettings.globalize_path(NoggBitmapFontScript.ATLAS_PATH),
		atlasImage.get_width(),
		atlasImage.get_height(),
		atlasError,
	])
	if atlasError != OK:
		quit(EXIT_WRITE_FAILED)
		return

	var font: FontFile = NoggBitmapFontScript.build_font(glyphs)
	if font == null:
		quit(EXIT_SOURCE_INVALID)
		return
	var saveError := ResourceSaver.save(font, NoggBitmapFontScript.RESOURCE_PATH)
	print("BAKE_FONT resource=%s error=%d" % [
		ProjectSettings.globalize_path(NoggBitmapFontScript.RESOURCE_PATH), saveError
	])
	if saveError != OK:
		quit(EXIT_WRITE_FAILED)
		return

	quit(0 if _verifyRoundTrip() else EXIT_VERIFY_FAILED)


## Confirms the source covers printable ASCII exactly, and names what is wrong
## rather than reporting a count mismatch and leaving the caller to diff it.
func _reportCoverage(glyphs: Dictionary) -> bool:
	var missing: Array[String] = []
	for codepoint: int in range(FIRST_CODEPOINT, LAST_CODEPOINT + 1):
		if not glyphs.has(codepoint):
			missing.append("0x%X" % codepoint)
	var extra: Array[String] = []
	for codepoint: int in glyphs.keys():
		if codepoint < FIRST_CODEPOINT or codepoint > LAST_CODEPOINT:
			extra.append("0x%X" % codepoint)
	if missing.is_empty() and extra.is_empty():
		return true
	if not missing.is_empty():
		push_error("Nogg Terminal source is missing %d glyph(s): %s" % [
			missing.size(), ", ".join(missing)
		])
	if not extra.is_empty():
		push_error("Nogg Terminal source declares %d glyph(s) outside printable ASCII: %s" % [
			extra.size(), ", ".join(extra)
		])
	return false


## Loads the saved resource back and measures it.
##
## Worth the extra seconds: a `FontFile` assembled in memory can measure
## correctly and still lose its embedded glyph caches on serialization, and that
## failure is invisible until something tries to draw text. Measuring after a
## round trip is what proves the file on disk is the font, not just that the
## builder ran.
func _verifyRoundTrip() -> bool:
	var reloaded = ResourceLoader.load(
		NoggBitmapFontScript.RESOURCE_PATH, "FontFile", ResourceLoader.CACHE_MODE_IGNORE
	)
	if reloaded == null or not (reloaded is FontFile):
		push_error("Baked font did not load back as a FontFile.")
		return false

	var nominal: int = NoggBitmapFontScript.NOMINAL_SIZE
	var sample := "MMMM"
	var expected := float(NoggBitmapFontScript.ADVANCE * sample.length())
	var measured := (reloaded as FontFile).get_string_size(
		sample, HORIZONTAL_ALIGNMENT_LEFT, -1.0, nominal
	)
	var doubled := (reloaded as FontFile).get_string_size(
		sample, HORIZONTAL_ALIGNMENT_LEFT, -1.0, nominal * 2
	)
	print("BAKE_FONT verify advance_x@%d=%.1f (expected %.1f) advance_x@%d=%.1f (expected %.1f)" % [
		nominal, measured.x, expected, nominal * 2, doubled.x, expected * 2.0
	])
	if not is_equal_approx(measured.x, expected):
		push_error("Baked font measures %.1f for '%s' at size %d; expected %.1f." % [
			measured.x, sample, nominal, expected
		])
		return false
	if not is_equal_approx(doubled.x, expected * 2.0):
		push_error(
			"Baked font does not scale by whole multiples: '%s' measures %.1f at size %d, expected %.1f."
			% [sample, doubled.x, nominal * 2, expected * 2.0]
		)
		return false
	print("BAKE_FONT status=OK")
	return true
