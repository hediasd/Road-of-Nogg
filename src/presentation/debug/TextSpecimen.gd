## Text specimen overlay for the VFX debug scene.
##
## A pixel font cannot be judged on a white page. What matters is whether it
## survives the thing it actually sits on: a lit 3D board, at the retro
## viewport's downsample, under the CRT pass. This overlay puts a chosen sample
## on its own CanvasLayer at the same depth the real battle UI occupies, so the
## font is composited exactly the way the shipping HUD is composited.
##
## It is a sibling of the effect controls rather than part of them: the debug
## HUD hides with `H` and is not meant to appear in a capture, while the
## specimen is often the whole point of the capture.
##
## Rebuilding from `glyphs.txt` on demand (`reload_source`) is what makes glyph
## authoring a loop rather than a batch: edit a letter, press R, look at it.

extends CanvasLayer

const NoggBitmapFontScript = preload("res://src/presentation/theme/NoggBitmapFont.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## Which face the specimen draws with.
const FONT_SOURCE := "source"
const FONT_BAKED := "baked"
const FONT_GAME := "game"
const FONT_OPTIONS := [
	{"id": FONT_SOURCE, "label": "Nogg Terminal (live source)"},
	{"id": FONT_BAKED, "label": "Nogg Terminal (baked .res)"},
	{"id": FONT_GAME, "label": "Game font (XenoText)"},
]

## What sits behind the text.
const BACKDROP_SCENE := "scene"
const BACKDROP_WINDOW := "window"
const BACKDROP_SOLID := "solid"
const BACKDROP_OPTIONS := [
	{"id": BACKDROP_SCENE, "label": "Over the board"},
	{"id": BACKDROP_WINDOW, "label": "In a game window"},
	{"id": BACKDROP_SOLID, "label": "Solid black"},
]

## The reference sentence is verbatim from the screenshot this face was drawn
## against, so the specimen can be held up next to it directly. The battle
## sample is real HUD copy — the strings whose widths a font change would
## actually move.
const SAMPLE_OPTIONS := [
	{
		"id": "reference",
		"label": "Reference sentence",
		"text": """For a group of monsters, certain
physical / magical attacks will
cause zero damage because of their
defense mechanisms.

Elemental Hit:
Attack with Elemental Skills that
are opposite the monster attribute
and it will result in double (2x)
the damage.""",
	},
	{
		"id": "pangram",
		"label": "Pangram + digits",
		"text": """The quick brown fox jumps
over the lazy dog.
SPHINX OF BLACK QUARTZ,
JUDGE MY VOW.
0123456789 Il1 O0 rn m
!?.,:;'\"()[]{}<>/\\|-_=+""",
	},
	{
		"id": "charset",
		"label": "Character table",
		"text": "",
	},
	{
		"id": "battle",
		"label": "Battle HUD copy",
		"text": """Move   Attack  Magic
Item   Wait    Status

Ashenwood Walker   HP 128/160
Resonance  FIR ###   ICE ..#

Fire Storm deals 42 damage.
Critical hit! 118
Marek is immune to Darkness.""",
	},
]

## How the glyph is separated from what it sits on.
##
## The reference this face was drawn against uses a **drop shadow**, not a
## halo: the dark edge sits down-and-right of each glyph and the top-left
## terminals meet the background bare. That reads as lit type on a panel. A
## symmetric outline reads as a sticker, and on a face whose strokes are one
## design pixel it also thickens every letter until the counters start to clog
## — which is exactly what "rough" looks like at a two-pixel halo.
##
## The halo is kept because the two are not interchangeable in every context: a
## shadow only defends one side, so text over a bright, arbitrary 3D board can
## still need the halo that `NoggTheme.OUTLINE` exists to provide. Which one
## wins where is a judgement to make by looking, which is what this control is
## for.
const EDGE_SHADOW := "shadow"
const EDGE_OUTLINE := "outline"
const EDGE_NONE := "none"
const EDGE_OPTIONS := [
	{"id": EDGE_SHADOW, "label": "Drop shadow (reference)"},
	{"id": EDGE_OUTLINE, "label": "Outline halo"},
	{"id": EDGE_NONE, "label": "Bare"},
]

## Candidate window fills, darkest first, for choosing how far to lift
## `NoggTheme.WINDOW_FILL` toward the reference's panel.
##
## The problem being solved: a drop shadow is invisible on a near-black panel,
## which is what `WINDOW_FILL` currently is. The reference's mailer panel is a
## warm dark brown, and that is the only reason its shadow reads at all. So the
## shadow treatment and the panel colour are one decision, not two — picking a
## shadow without picking a fill settles nothing.
##
## The ladder runs neutral-to-warm as well as dark-to-light, because both axes
## matter: lifting the fill neutrally makes the shadow legible, while warming it
## is what makes the panel read as the reference's rather than as grey. Alpha
## rises with lightness so the board does not read through a panel that is
## trying to be a surface.
##
## `describe()` prints the picked colour verbatim, so a choice here transfers to
## `NoggTheme.WINDOW_FILL` by copying it rather than by eyedropping a capture.
const FILL_OPTIONS := [
	{"id": "current", "label": "Current WINDOW_FILL", "color": Color(0.012, 0.012, 0.020, 0.76)},
	{"id": "lifted", "label": "Lifted, still neutral", "color": Color(0.055, 0.052, 0.070, 0.82)},
	{"id": "warm_deep", "label": "Warm, deep", "color": Color(0.075, 0.058, 0.042, 0.86)},
	{"id": "warm_panel", "label": "Warm panel (reference-ish)", "color": Color(0.125, 0.098, 0.070, 0.92)},
	{"id": "reference", "label": "Reference panel, opaque", "color": Color(0.145, 0.113, 0.078, 1.0)},
]

## Not fully opaque. At one design pixel an opaque black shadow reads as a
## second stroke competing with the letter; pulling it back lets it sit under
## the glyph as depth instead. The reference's shadow is softer still, but that
## softness is an artifact of the console upscaling its output rather than
## anything drawn, and faking a blur would cost the face its crisp edges for a
## detail nobody is comparing against.
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.72)

## Sizes are always a whole multiple of the design size. Anything else would
## smear the atlas, which is the one thing this face exists to avoid.
const MIN_SCALE := 1
const MAX_SCALE := 4
## Shadow offset and halo width share this control, in design pixels. Three is
## past useful for both and exists only so the ugly end is reachable on purpose.
const MAX_EDGE_SIZE := 3
## Clear of the debug HUD panel, which is 380 wide and docked left.
const LEFT_MARGIN := 404.0
const SCREEN_MARGIN := 16.0

var _fontId: String = FONT_SOURCE
var _sampleId: String = "reference"
var _backdropId: String = BACKDROP_SCENE
## Warm-deep by default: it is the lightest rung that keeps the panel
## translucent while still letting the drop shadow read, and it is the one
## picked by eye against the reference. `NoggTheme.WINDOW_FILL` is unchanged —
## this is the specimen's opinion, not the game's.
var _fillId: String = "warm_deep"
var _edgeMode: String = EDGE_SHADOW
var _scale: int = 2
var _edgeSize: int = 1
var _sourceFont: FontFile
var _bakedFont: FontFile
var _gameFont: Font
var _loadError: String = ""
var _lastCanvasScale: float = -1.0

var _backdrop: ColorRect
var _window: Control
var _windowBody: Panel
var _body: Label
var _metrics: Label


func _init() -> void:
	# Same depth as the shipping battle HUD, so "does the CRT pass touch it?"
	# is answered by the scene's own toggles rather than by this overlay.
	layer = NoggThemeScript.GAME_LAYER
	name = "TextSpecimen"


func _ready() -> void:
	_buildTree()
	reload_source()
	_lastCanvasScale = _canvasScale()


## Rebuilds the face whenever the canvas scale changes, including from a plain
## window drag.
##
## Changing the content scale changes the text server's font oversampling, and
## that clears cached glyph data. A dynamic face re-rasterizes itself from the
## TTF bytes it still holds; a bitmap face assembled in memory has nothing to
## regenerate from, so its glyphs are gone for good and every string silently
## falls back to a system font. Without this watch, resizing the window would
## look exactly like the font being broken.
func _process(_delta: float) -> void:
	var stretch := _canvasScale()
	if is_equal_approx(stretch, _lastCanvasScale):
		return
	_lastCanvasScale = stretch
	reload_source()


## Re-parses `glyphs.txt` and rebuilds the live face. The baked resource is
## reloaded too, so a bake performed while the scene is open is picked up.
func reload_source() -> void:
	_loadError = ""
	_sourceFont = NoggBitmapFontScript.build_font_from_source()
	if _sourceFont == null:
		_loadError = "glyphs.txt failed to parse - see the error log"
	if ResourceLoader.exists(NoggBitmapFontScript.RESOURCE_PATH):
		_bakedFont = ResourceLoader.load(
			NoggBitmapFontScript.RESOURCE_PATH, "FontFile", ResourceLoader.CACHE_MODE_IGNORE
		)
	else:
		_bakedFont = null
	if _gameFont == null:
		_gameFont = NoggThemeScript.build_game_theme().default_font
	# Recorded here rather than only in `_ready`, so a rebuild triggered by
	# something other than the watcher does not leave the watcher believing the
	# scale still needs handling and rebuilding a second time.
	_lastCanvasScale = _canvasScale()
	_apply()


func set_font_id(id: String) -> void:
	_fontId = id
	_apply()


func set_sample_id(id: String) -> void:
	_sampleId = id
	_apply()


func set_backdrop_id(id: String) -> void:
	_backdropId = id
	_apply()


func set_fill_id(id: String) -> void:
	_fillId = id
	_apply()


func set_specimen_scale(value: int) -> void:
	_scale = clampi(value, MIN_SCALE, MAX_SCALE)
	_apply()


func set_edge_mode(id: String) -> void:
	_edgeMode = id
	_apply()


func set_edge_size(value: int) -> void:
	_edgeSize = clampi(value, 0, MAX_EDGE_SIZE)
	_apply()


func get_specimen_scale() -> int:
	return _scale


func get_edge_size() -> int:
	return _edgeSize


## One line for the debug HUD's status readout: what is on screen and how big.
func describe() -> String:
	if not visible:
		return "text: off"
	if not _loadError.is_empty():
		return "text: %s" % _loadError
	var fill := _selectedFill()
	return "text: %s | %s | x%d (size %d) | %s %d | %s\nfill %s = Color(%.3f, %.3f, %.3f, %.2f)" % [
		_fontId, _sampleId, _scale, _fontSize(), _edgeMode, _edgeSize, _backdropId,
		_fillId, fill.r, fill.g, fill.b, fill.a
	]


func _fontSize() -> int:
	return NoggBitmapFontScript.NOMINAL_SIZE * _scale


func _buildTree() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	# A real window frame rather than a plain panel: the halo and rim are part
	# of what the text has to stay readable against in the shipping HUD.
	_window = Control.new()
	_window.name = "Window"
	_window.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window.offset_left = LEFT_MARGIN
	_window.offset_top = SCREEN_MARGIN * 3.0
	_window.offset_right = -SCREEN_MARGIN
	_window.offset_bottom = -SCREEN_MARGIN
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_window)
	_window.add_child(NoggThemeScript.build_window_halo())
	# Built by the theme so the corner radius and geometry stay the shipping
	# ones; only the fill colour is overridden below. A locally constructed
	# panel would drift from the real window the moment a token changed.
	_windowBody = NoggThemeScript.build_window_body()
	_window.add_child(_windowBody)
	_window.add_child(NoggThemeScript.build_window_frame())

	_body = Label.new()
	_body.name = "Body"
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.offset_left = LEFT_MARGIN + NoggThemeScript.CONTENT_INSET
	_body.offset_top = SCREEN_MARGIN * 3.0 + NoggThemeScript.CONTENT_INSET
	_body.offset_right = -SCREEN_MARGIN - NoggThemeScript.CONTENT_INSET
	_body.offset_bottom = -SCREEN_MARGIN - NoggThemeScript.CONTENT_INSET
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_color_override("font_color", NoggThemeScript.TEXT_PRIMARY)
	_body.add_theme_color_override("font_outline_color", NoggThemeScript.OUTLINE)
	add_child(_body)

	# Deliberately in the developer face, not the specimen's: a caption drawn in
	# the font under test is one more thing to mistake for the specimen.
	_metrics = Label.new()
	_metrics.name = "Metrics"
	_metrics.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_metrics.offset_left = LEFT_MARGIN
	_metrics.offset_top = SCREEN_MARGIN
	_metrics.offset_right = -SCREEN_MARGIN
	_metrics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_metrics.add_theme_font_override("font", load(NoggThemeScript.DEV_FONT_PATH))
	_metrics.add_theme_font_size_override("font_size", NoggThemeScript.FONT_SIZE_DEV)
	_metrics.add_theme_color_override("font_color", NoggThemeScript.DEV_TEXT)
	_metrics.add_theme_color_override("font_outline_color", NoggThemeScript.OUTLINE)
	_metrics.add_theme_constant_override("outline_size", 3)
	add_child(_metrics)


func _apply() -> void:
	if _body == null:
		return

	var font := _selectedFont()
	if font != null:
		_body.add_theme_font_override("font", font)
	_body.add_theme_font_size_override("font_size", _fontSize())
	_applyEdge(font)
	_body.text = _sampleText()

	_backdrop.visible = _backdropId == BACKDROP_SOLID
	_backdrop.color = Color(0.0, 0.0, 0.0, 1.0)
	_window.visible = _backdropId == BACKDROP_WINDOW
	_applyWindowFill()

	_metrics.text = _metricsLine(font)


## Sets the shadow and outline theme entries for the current edge treatment.
##
## The two are mutually exclusive rather than additive: stacking a halo under a
## shadow gives the glyph a dark edge on all four sides *and* a displaced copy,
## which is muddier than either alone. Whichever is off is zeroed explicitly,
## because these are theme overrides on a live node and a stale entry would
## otherwise survive the mode change.
##
## The shadow is drawn by the label, not baked into the atlas, so its offset is
## a plain device-pixel count and does scale with the zoom.
##
## The halo is the opposite, and the difference is worth stating: for a bitmap
## face `outline_size` is a *cache key*, not a pixel count. The text server
## looks up the atlas variant baked for that width and then applies the
## fixed-size scale to whatever it finds, so the design width goes in unscaled
## and comes out already multiplied — pre-scaling would square the zoom, and a
## width with no baked variant draws no outline at all rather than an
## approximated one. The dynamic game face has no such table and takes a plain
## pixel count, so it gets the scaled value. Both land at the same thickness on
## screen, which is the only way the two faces are comparable.
func _applyEdge(font: Font) -> void:
	var shadowOffset := 0
	var outlineWidth := 0
	match _edgeMode:
		EDGE_SHADOW:
			shadowOffset = _edgeSize * _scale
		EDGE_OUTLINE:
			outlineWidth = _edgeSize * _scale if font == _gameFont else _edgeSize

	_body.add_theme_constant_override("outline_size", outlineWidth)
	_body.add_theme_color_override("font_outline_color", NoggThemeScript.OUTLINE)
	# Zero keeps the shadow a displaced copy of the glyph itself. Anything
	# larger would draw the shadow from the outline atlas and thicken it, which
	# is the halo this mode exists to avoid.
	_body.add_theme_constant_override("shadow_outline_size", 0)
	_body.add_theme_constant_override("shadow_offset_x", shadowOffset)
	_body.add_theme_constant_override("shadow_offset_y", shadowOffset)
	_body.add_theme_color_override(
		"font_shadow_color",
		SHADOW_COLOR if shadowOffset > 0 else Color(0.0, 0.0, 0.0, 0.0)
	)


func _selectedFill() -> Color:
	for option: Dictionary in FILL_OPTIONS:
		if option["id"] == _fillId:
			return option["color"]
	return FILL_OPTIONS[0]["color"]


## Repaints the theme-built body panel with the picked fill, keeping every other
## property the theme gave it.
func _applyWindowFill() -> void:
	if _windowBody == null:
		return
	var style := _windowBody.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.bg_color = _selectedFill()
	_windowBody.add_theme_stylebox_override("panel", style)


func _selectedFont() -> Font:
	match _fontId:
		FONT_BAKED:
			return _bakedFont if _bakedFont != null else _sourceFont
		FONT_GAME:
			return _gameFont
		_:
			return _sourceFont


func _sampleText() -> String:
	if _sampleId == "charset":
		return _charsetTable()
	for option: Dictionary in SAMPLE_OPTIONS:
		if option["id"] == _sampleId:
			return str(option["text"])
	return ""


## Printable ASCII, sixteen to a row, so the low nibble of each codepoint is the
## column. Same layout as the baked atlas: a glyph that looks wrong here is
## findable in the atlas at the same coordinates.
func _charsetTable() -> String:
	var lines: PackedStringArray = []
	var codepoint := 0x20
	while codepoint <= 0x7E:
		var row := ""
		for column: int in range(16):
			if codepoint + column > 0x7E:
				break
			row += char(codepoint + column)
		lines.append(row)
		codepoint += 16
	return "\n".join(lines)


## The canvas stretch factor, and whether it is a whole number.
##
## This is the single most important number on screen and it is not the font's.
## `project.godot` ships `window/stretch/mode = "disabled"`, so this
## reads x1 under the shipping default at any window size — nothing resamples
## the canvas, and `NoggTheme.ui_scale` is the resolution-aware factor instead,
## applied to design-unit tokens rather than to the canvas. A value other than
## x1 here means this scene's own Canvas stretch control has been pointed at
## one of the non-default presets (`legacy_fractional` reproduces the bug this
## fixed, on purpose, for comparison).
##
## No font setting can survive a fractional canvas factor — a one-pixel stroke
## lands as one device pixel in places and two in others under nearest
## filtering — which is exactly why the reading belongs here: without it, a
## resolution artifact reads as a drawing mistake and the next person re-draws
## glyphs to chase it.
func _canvasScale() -> float:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return 1.0
	return tree.root.get_final_transform().get_scale().x


func _pixelFidelityNote() -> String:
	var stretch := _canvasScale()
	if is_equal_approx(stretch, roundf(stretch)):
		return "  canvas x%.0f PIXEL-EXACT" % stretch
	return "  canvas x%.3f NOT PIXEL-EXACT (set Canvas stretch back to native)" % stretch


func _metricsLine(font: Font) -> String:
	if not _loadError.is_empty():
		return "SPECIMEN ERROR: %s" % _loadError
	if font == null:
		return "SPECIMEN: no font available"
	var name := font.get_font_name()
	if name.is_empty():
		name = "<unnamed>"
	var advance := font.get_string_size(
		"M", HORIZONTAL_ALIGNMENT_LEFT, -1.0, _fontSize()
	).x
	var missing := ""
	if _fontId == FONT_BAKED and _bakedFont == null:
		missing = "  [no baked .res yet - showing live source]"
	return "%s  size %d (x%d)  advance %.0fpx  ascent %.0f  descent %.0f  %s %d design px = %d on screen%s" % [
		name,
		_fontSize(),
		_scale,
		advance,
		font.get_ascent(_fontSize()),
		font.get_descent(_fontSize()),
		_edgeMode,
		_edgeSize,
		_edgeSize * _scale,
		missing,
	] + _pixelFidelityNote()


## Index of the default fill in `FILL_OPTIONS`, so the HUD dropdown opens on the
## same rung the specimen actually renders instead of silently disagreeing
## with it.
static func default_fill_index() -> int:
	for index: int in range(FILL_OPTIONS.size()):
		if FILL_OPTIONS[index]["id"] == "warm_deep":
			return index
	return 0
