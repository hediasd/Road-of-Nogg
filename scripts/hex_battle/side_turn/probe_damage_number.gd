## The hit number's arc: the throw is the shape it claims to be, the exit drops
## the outline before it fades, and the whole motion is a function of the
## effect's clock rather than a value accumulated along the way.
##
## Three groups of checks:
##
## 1. ARC. The crest falls at `RISE_SPEED / FALL_ACCELERATION` and reaches
##    `CREST_HEIGHT` glyph heights, both derived from the two motion constants
##    rather than restated here, so an edit to either constant moves the
##    assertion with it. The crest is verified to be the highest point the
##    number reaches, and the lateral term is verified linear -- twice the
##    time is twice the drift, with no easing hiding at either end.
## 2. EXIT. The outline is present for every sample before `OUTLINED_DURATION`
##    and gone for every sample after it, alpha holds at 1 until that moment
##    and reaches zero by the summed lifetime, and the number keeps travelling
##    through the flash instead of freezing where it crested.
## 3. DETERMINISM. `docs/VFX_DESIGN.md` section 3 requires proving a rate has
##    its integral in closed form rather than asserting it, by reaching one
##    instant along several routes and comparing what is rendered. Three routes
##    reach the same instant here: one jump, sixty even steps, and an uneven
##    walk. An accumulated position diverges between them; a closed form cannot.
##    The comparison is on the state that drives the draw -- position, alpha and
##    the outline flag -- rather than on captured images, because for this
##    effect those three values are the whole of what a frame would show, and
##    checking them needs no renderer.

extends SceneTree

const BillboardScript = preload("res://src/presentation/effects/DamageNumberBillboard.gd")

const MARKER_OK := "STB_DAMAGE_NUMBER_OK"
const MARKER_FAIL := "STB_DAMAGE_NUMBER_FAILURE"

## The arc is rounded to whole device pixels, so two routes that agree land on
## the same integer. Alpha is continuous and compared with float slack.
const ALPHA_TOLERANCE := 0.001
## Slack for the closed-form checks, in glyph heights.
const ARC_TOLERANCE := 0.0001

var failures: Array[String] = []
var _layer: Control
var _glyph_height := 1.0


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_layer = Control.new()
	_layer.name = "ProbeNumberLayer"
	root.add_child(_layer)
	_glyph_height = float(load("res://src/presentation/theme/NoggTheme.gd").FONT_SIZE_BODY)

	_phaseArc()
	_phaseScales()
	await _phaseGrid()
	await _phaseExit()
	await _phaseDeterminism()
	_finish()


# --- A1: the grid is whole at every shipping ui_scale ------------------------


## The check that was missing while the number looked soft.
##
## `FONT_SIZE_BODY` is `12 * ui_scale`, so an art pixel taken as a plain
## division is 1.5 device pixels at x1 and 4.5 at x3. Blown up by a fraction,
## the glyph's edges stop landing on device pixels -- consecutive art pixels
## render two device pixels wide and then three -- and the number reads ragged
## however pure its colours are. Nothing rendered can be pixel perfect if this
## arithmetic is not, so it is checked here rather than in a capture.
func _phaseScales() -> void:
	var theme = load("res://src/presentation/theme/NoggTheme.gd")
	var restore: int = theme.ui_scale
	for scale in range(theme.UI_SCALE_MIN, theme.UI_SCALE_MAX + 1):
		theme.configure(scale)
		var art: float = BillboardScript.art_pixel()
		_require(
			absf(art - roundf(art)) < 0.0001,
			"ui_scale %d gives an art pixel of %.2f device px, which is not whole"
				% [scale, art]
		)
		_require(art >= 1.0, "ui_scale %d gives an art pixel of %.2f" % [scale, art])

		# The glyph and the arc's unit are whole device pixels too, since both
		# are art pixels multiplied up.
		var glyph: float = BillboardScript.ART_PIXELS_PER_GLYPH * art
		_require(
			absf(glyph - roundf(glyph)) < 0.0001,
			"ui_scale %d gives a glyph height of %.2f device px" % [scale, glyph]
		)
		_require(
			glyph >= float(theme.FONT_SIZE_BODY),
			"ui_scale %d draws the number at %.0f px, under body text at %d px"
				% [scale, glyph, theme.FONT_SIZE_BODY]
		)
	theme.configure(restore)


# --- A2: the number lives on a coarse art-pixel grid -------------------------


## What keeps the number reading as pixel art rather than as moving text. The
## reference's glyph is eight art pixels tall, outlined one art pixel thick and
## stepping one art pixel at a time; drawn on the device grid instead it turns
## into a hairline that glides.
func _phaseGrid() -> void:
	var art: float = BillboardScript.art_pixel()
	_require(
		absf(art - _glyph_height / BillboardScript.ART_PIXELS_PER_GLYPH) < 0.001,
		"an art pixel is %.3f px, not a glyph height over %.0f"
			% [art, BillboardScript.ART_PIXELS_PER_GLYPH]
	)
	_require(
		art >= 2.0,
		"an art pixel is %.2f device px: the outline is back to a hairline" % art
	)

	# The outline is a filled disc, so it cannot be seen through at the corners.
	var radius := maxi(1, roundi(art))
	var ring: Array = BillboardScript.outline_offsets(radius)
	_require(
		ring.has(Vector2(radius, 0)) and ring.has(Vector2(0, -radius)),
		"the outline ring is missing its cardinal extremes at radius %d" % radius
	)
	var diagonal := int(floor(float(radius) / sqrt(2.0)))
	_require(
		ring.has(Vector2(diagonal, diagonal)),
		"the outline ring is open on the diagonal at radius %d" % radius
	)

	# Every drawn position is a whole number of art pixels from the anchor.
	#
	# Counting distinct positions would prove nothing: the number crosses about
	# 38 art pixels in its life and the reference crosses about 42, so both
	# visit roughly as many places as a frame-rate sampling has frames. What
	# separates stepping from gliding is that a coarse grid makes the number
	# *hold* -- once its speed drops below an art pixel per frame it stays put
	# for consecutive frames, which is plainly visible in the reference near its
	# crest and impossible on a grid 24ths of a glyph fine.
	var frame := 1.0 / 60.0
	var frames := int(BillboardScript.DAMAGE_VISIBLE_DURATION / frame)
	var previous := Vector2(NAN, NAN)
	var holds := 0
	for index in range(frames + 1):
		var state := await _stateAt([frame * float(index)])
		var offset: Vector2 = state.get("position", Vector2.ZERO)
		for component in [offset.x, offset.y]:
			var steps: float = float(component) / art
			_require(
				absf(steps - roundf(steps)) < 0.35,
				"a drawn offset of %.1f px is not a whole art pixel (%.2f px)"
					% [component, art]
			)
		if index > 0 and offset == previous:
			holds += 1
		previous = offset
	_require(
		holds >= 5,
		"the number held still on only %d of %d frames: it is gliding, not stepping"
			% [holds, frames]
	)


# --- A: the arc is the shape it claims ---------------------------------------


func _phaseArc() -> void:
	var crest: float = BillboardScript.CREST_TIME
	_require(
		absf(crest - BillboardScript.RISE_SPEED / BillboardScript.FALL_ACCELERATION) < ARC_TOLERANCE,
		"CREST_TIME does not follow from RISE_SPEED and FALL_ACCELERATION"
	)

	var at_crest: Vector2 = BillboardScript.offset_at(crest, _glyph_height)
	var expected := -BillboardScript.CREST_HEIGHT * _glyph_height
	_require(
		absf(at_crest.y - expected) < ARC_TOLERANCE * _glyph_height,
		"crest height is %.4f px, expected %.4f px" % [at_crest.y, expected]
	)

	# The crest is the highest the number gets: every other sample is lower,
	# which on screen means a larger y.
	for step in range(0, 61):
		var seconds: float = BillboardScript.DAMAGE_VISIBLE_DURATION * float(step) / 60.0
		var point: Vector2 = BillboardScript.offset_at(seconds, _glyph_height)
		_require(
			point.y >= at_crest.y - ARC_TOLERANCE * _glyph_height,
			"t=%.3f rises above the crest (%.4f < %.4f)" % [seconds, point.y, at_crest.y]
		)

	# The number is descending again by the time it flashes out.
	var at_flash: Vector2 = BillboardScript.offset_at(BillboardScript.OUTLINED_DURATION, _glyph_height)
	var at_end: Vector2 = BillboardScript.offset_at(BillboardScript.DAMAGE_VISIBLE_DURATION, _glyph_height)
	_require(
		BillboardScript.OUTLINED_DURATION > crest,
		"the outline drops at %.3f s, before the crest at %.3f s"
			% [BillboardScript.OUTLINED_DURATION, crest]
	)
	_require(
		at_end.y > at_flash.y,
		"the number does not keep falling through the flash"
	)

	# Lateral drift is linear: no ease is hiding at either end.
	var quarter: Vector2 = BillboardScript.offset_at(0.1, _glyph_height)
	var half: Vector2 = BillboardScript.offset_at(0.2, _glyph_height)
	_require(
		absf(half.x - 2.0 * quarter.x) < ARC_TOLERANCE * _glyph_height,
		"lateral drift is not linear: %.4f then %.4f" % [quarter.x, half.x]
	)
	_require(
		absf(quarter.x) > 0.0,
		"the number does not drift sideways at all"
	)


# --- B: the exit drops the outline, then fades -------------------------------


func _phaseExit() -> void:
	var outlined_duration: float = BillboardScript.OUTLINED_DURATION
	var total: float = BillboardScript.DAMAGE_VISIBLE_DURATION

	for fraction in [0.0, 0.25, 0.5, 0.9, 0.999]:
		var seconds: float = outlined_duration * float(fraction)
		var state := await _stateAt([seconds])
		_require(
			bool(state.get("outlined", false)),
			"the outline is already gone at t=%.3f s" % seconds
		)
		_require(
			absf(float(state.get("alpha", 0.0)) - 1.0) < ALPHA_TOLERANCE,
			"alpha is %.4f at t=%.3f s, before the flash" % [state.get("alpha", 0.0), seconds]
		)

	var flash_span := total - outlined_duration
	for fraction in [0.001, 0.25, 0.5, 0.9]:
		var seconds: float = outlined_duration + flash_span * float(fraction)
		var state := await _stateAt([seconds])
		_require(
			not bool(state.get("outlined", true)),
			"the outline is still drawn at t=%.3f s, inside the flash" % seconds
		)
		var expected_alpha: float = 1.0 - float(fraction)
		_require(
			absf(float(state.get("alpha", -1.0)) - expected_alpha) < 0.05,
			"alpha is %.4f at t=%.3f s, expected about %.2f"
				% [state.get("alpha", -1.0), seconds, expected_alpha]
		)

	var ending := await _stateAt([total * 0.9999])
	_require(
		float(ending.get("alpha", 1.0)) < 0.01,
		"alpha is still %.4f as the number ends" % ending.get("alpha", 1.0)
	)

	# The number is somewhere else than it started, and not where it crested.
	var crest_state := await _stateAt([BillboardScript.CREST_TIME])
	var start_state := await _stateAt([0.0])
	_require(
		crest_state.get("position", Vector2.ZERO) != start_state.get("position", Vector2.ZERO),
		"the number never leaves its spawn anchor"
	)
	_require(
		ending.get("position", Vector2.ZERO) != crest_state.get("position", Vector2.ZERO),
		"the number freezes at its crest instead of falling back"
	)


# --- C: one instant, three routes --------------------------------------------


func _phaseDeterminism() -> void:
	var target: float = BillboardScript.DAMAGE_VISIBLE_DURATION * 0.8

	var jump := await _stateAt([target])

	var even: Array[float] = []
	for _index in range(60):
		even.append(target / 60.0)
	var walked := await _stateAt(even)

	var uneven: Array[float] = []
	var spent := 0.0
	var slice := target / 7.0
	for index in range(7):
		var delta := slice * (0.4 if index % 2 == 0 else 1.6)
		uneven.append(delta)
		spent += delta
	uneven.append(target - spent)
	var wandered := await _stateAt(uneven)

	for pair in [["sixty even steps", walked], ["an uneven walk", wandered]]:
		var label: String = pair[0]
		var state: Dictionary = pair[1]
		_require(
			state.get("position", Vector2.ONE) == jump.get("position", Vector2.ZERO),
			"%s lands at %s, a single jump lands at %s"
				% [label, state.get("position"), jump.get("position")]
		)
		_require(
			absf(float(state.get("alpha", -1.0)) - float(jump.get("alpha", 0.0)))
				< ALPHA_TOLERANCE,
			"%s reaches alpha %.6f, a single jump reaches %.6f"
				% [label, state.get("alpha", -1.0), jump.get("alpha", 0.0)]
		)
		_require(
			state.get("outlined", null) == jump.get("outlined", null),
			"%s disagrees with a single jump about the outline" % label
		)


# --- helpers -----------------------------------------------------------------


## A fresh number advanced by the given deltas, then read. The tween is paused
## first so the routes differ only in how they were stepped, never in how many
## frames happened to elapse while the probe was running.
func _stateAt(deltas: Array) -> Dictionary:
	var tween: Tween = BillboardScript.spawn(_layer, Vector2(240.0, 200.0), 7, false)
	if tween == null:
		_require(false, "the billboard did not spawn")
		return {}
	tween.pause()
	var billboard := _layer.get_child(_layer.get_child_count() - 1) as Control
	var anchor := billboard.position
	for delta in deltas:
		tween.custom_step(float(delta))

	var digit: Node = billboard.get_child(0) if billboard.get_child_count() > 0 else null
	var state := {
		"position": billboard.position - anchor,
		"alpha": billboard.modulate.a,
		"outlined": digit.outlined if digit != null else null,
	}
	tween.kill()
	billboard.queue_free()
	await process_frame
	return state


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print(MARKER_OK)
		quit(0)
		return
	for failure in failures:
		printerr("%s: %s" % [MARKER_FAIL, failure])
	quit(1)
