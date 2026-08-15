## UnitPlate — the board-space readout carried under every living unit.
##
## See `docs/UI_DESIGN.md` §10c for the contract. Three properties are
## load-bearing and easy to undo by accident.
##
## **It is a Control, not world-space geometry.** The battle world renders into
## an isolated `SubViewport` that presets drop to 480x360. A five-pixel bar or a
## drawn digit inside that viewport is downsampled with it and stops being
## readable. The plate is positioned by projecting the unit's world position into
## screen space instead, the way `DamageNumberBillboard` already does, so it
## stays crisp at every preset. `GodotVisualAdapter` owns that projection; this
## class only draws.
##
## **It is delicate on purpose, and it carries no backing chrome.** The
## reference is Fire Emblem Awakening's map health bar: a thin line at the
## unit's feet, about one tile wide, defended by a hard dark outline rather than
## by a slab behind it. Health is peripheral information — the board reads
## first. A first pass that used a filled backing plate and a font-sized ring
## came out three times this size and was rejected on sight; `PLATE_INK` is what
## replaced it, and removing that outline would bring the slab back.
##
## **The digits are drawn, not typed.** The shipping bitmap face floors to whole
## multiples of 12 device pixels, and sizing the ring to hold a glyph at that
## floor is precisely what made the first plate wider than its own unit. A 3x5
## drawn glyph has no floor, and `StatusEffectIcons` already establishes drawing
## symbols rather than typing them.

class_name UnitPlate
extends Control

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## A 3x5 cell per digit. Levels are the only numbers this draws, so the set stops
## at the ten digits rather than growing into a general font.
const DIGIT_GLYPHS := {
	"0": ["111", "101", "101", "101", "111"],
	"1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"],
	"3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"],
	"5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"],
	"7": ["111", "001", "010", "010", "010"],
	"8": ["111", "101", "111", "101", "111"],
	"9": ["111", "101", "111", "001", "111"],
}

var level: int = 1
var team_color: Color = Color.WHITE
var hitpoints: int = 1
var max_hitpoints: int = 1
var spent: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(NoggThemeScript.PLATE_WIDTH, NoggThemeScript.PLATE_HEIGHT)
	pivot_offset = size * 0.5


## Returns whether anything actually changed, so the caller can skip the redraw
## on the frames where a unit's readout is identical to the last one — which is
## most frames, since this is polled rather than event-driven.
func configure(
		level_value: int,
		team_color_value: Color,
		hitpoints_value: int,
		max_hitpoints_value: int,
		spent_value: bool) -> bool:
	if (
		level == level_value
		and team_color == team_color_value
		and hitpoints == hitpoints_value
		and max_hitpoints == max_hitpoints_value
		and spent == spent_value
	):
		return false
	level = level_value
	team_color = team_color_value
	hitpoints = hitpoints_value
	max_hitpoints = max_hitpoints_value
	spent = spent_value
	modulate = NoggThemeScript.PLATE_SPENT_MODULATE if spent else Color.WHITE
	queue_redraw()
	return true


func _draw() -> void:
	_draw_level_ring()
	_draw_health_bar()


## An unfilled circle: the stroke carries team identity and the digits carry
## level, and leaving the interior transparent is what lets one small element
## hold both without the digits fighting a fill for contrast. The dark ring just
## outside it is the same defence the bar's outline provides.
func _draw_level_ring() -> void:
	var centre := Vector2(
		NoggThemeScript.PLATE_RING_OUTLINE + NoggThemeScript.PLATE_RING_DIAMETER * 0.5,
		size.y * 0.5
	)
	var radius := (NoggThemeScript.PLATE_RING_DIAMETER - NoggThemeScript.PLATE_RING_STROKE) * 0.5
	var outline_radius := (
		radius
		+ NoggThemeScript.PLATE_RING_STROKE * 0.5
		+ NoggThemeScript.PLATE_RING_OUTLINE * 0.5
	)
	# Halo outside the dark outline, not inside it: both source effects bloom
	# outward from a defined edge rather than blurring the edge itself.
	var glow := team_color
	glow.a = NoggThemeScript.PLATE_RING_GLOW_ALPHA
	draw_arc(
		centre, outline_radius + NoggThemeScript.PLATE_RING_OUTLINE,
		0.0, TAU, 24, glow, NoggThemeScript.PLATE_RING_OUTLINE * 2.0, true
	)
	draw_arc(
		centre, outline_radius,
		0.0, TAU, 24, NoggThemeScript.PLATE_INK, NoggThemeScript.PLATE_RING_OUTLINE, true
	)
	draw_arc(
		centre, radius, 0.0, TAU, 24,
		team_color, NoggThemeScript.PLATE_RING_STROKE, true
	)
	_draw_digits(str(level), centre)


func _draw_digits(text: String, centre: Vector2) -> void:
	var cell := NoggThemeScript.PLATE_DIGIT_CELL
	var stride := NoggThemeScript.PLATE_DIGIT_COLUMNS + NoggThemeScript.PLATE_DIGIT_GAP_CELLS
	var total_cells := text.length() * stride - NoggThemeScript.PLATE_DIGIT_GAP_CELLS
	var origin := Vector2(
		centre.x - float(total_cells) * cell * 0.5,
		centre.y - float(NoggThemeScript.PLATE_DIGIT_ROWS) * cell * 0.5
	).round()

	for index in range(text.length()):
		var glyph: Array = DIGIT_GLYPHS.get(text.substr(index, 1), [])
		for row in range(glyph.size()):
			var line: String = glyph[row]
			for column in range(line.length()):
				if line[column] != "1":
					continue
				var at := origin + Vector2(
					float(index * stride + column) * cell, float(row) * cell
				)
				# Shadow down and right only, matching the face's own edge
				# treatment (docs/UI_DESIGN.md §3) rather than haloing a glyph
				# whose strokes are already one cell wide.
				draw_rect(Rect2(at + Vector2(cell, 0), Vector2(cell, cell)), NoggThemeScript.PLATE_INK)
				draw_rect(Rect2(at + Vector2(0, cell), Vector2(cell, cell)), NoggThemeScript.PLATE_INK)
				draw_rect(Rect2(at, Vector2(cell, cell)), NoggThemeScript.TEXT_PRIMARY)


func _draw_health_bar() -> void:
	var outline := NoggThemeScript.PLATE_BAR_OUTLINE
	var bar := Rect2(
		Vector2(
			NoggThemeScript.PLATE_RING_OUTLINE * 2.0
			+ NoggThemeScript.PLATE_RING_DIAMETER
			+ NoggThemeScript.PLATE_GAP,
			(size.y - NoggThemeScript.PLATE_BAR_HEIGHT) * 0.5
		),
		Vector2(NoggThemeScript.PLATE_BAR_WIDTH, NoggThemeScript.PLATE_BAR_HEIGHT)
	)

	draw_rect(bar.grow(outline), NoggThemeScript.PLATE_INK, true)
	draw_rect(bar, NoggThemeScript.PLATE_BAR_TRACK, true)

	var safe_max := maxi(1, max_hitpoints)
	var ratio := clampf(float(hitpoints) / float(safe_max), 0.0, 1.0)
	if ratio > 0.0:
		_draw_ramp(
			Rect2(bar.position, Vector2(round(bar.size.x * ratio), bar.size.y))
		)

	# Separators are drawn over the fill and the track alike, so a boundary stays
	# visible whether that part of the bar is spent or not — the count of
	# segments is what the player reads, not only how far the fill reaches.
	var notch := NoggThemeScript.PLATE_HP_PER_NOTCH
	var hp_at := notch
	while hp_at < safe_max:
		var x: float = bar.position.x + round(bar.size.x * (float(hp_at) / float(safe_max)))
		draw_rect(
			Rect2(Vector2(x, bar.position.y), Vector2(outline, bar.size.y)),
			NoggThemeScript.PLATE_INK,
			true
		)
		hp_at += notch


## Fills a rect with a vertical luminance ramp and a one-pixel specular along
## its top, which is the treatment both `aurora_veil_field` and
## `solar_storm_field` are built on: never a flat colour, always deep at the
## bottom and hot at the top.
##
## Drawn a row at a time rather than through a gradient texture. The bar is only
## `PLATE_BAR_HEIGHT` device pixels tall, so this is a handful of `draw_rect`
## calls — cheaper than sampling a texture, and pixel-exact in a way a sampled
## ramp at this size would not be.
func _draw_ramp(rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var top := ramp_top()
	var bottom := ramp_bottom()
	var rows := maxi(1, int(round(rect.size.y)))
	for row in range(rows):
		# Sampled at each row's centre, so a two-row bar still reads as a ramp
		# between the two stops rather than as the top stop twice.
		var t := (float(row) + 0.5) / float(rows)
		draw_rect(
			Rect2(
				Vector2(rect.position.x, rect.position.y + float(row)),
				Vector2(rect.size.x, 1.0)
			),
			top.lerp(bottom, t),
			true
		)
	draw_rect(
		Rect2(rect.position, Vector2(rect.size.x, 1.0)),
		NoggThemeScript.PLATE_BAR_HIGHLIGHT,
		true
	)


## Below one third burns. Deliberately the same threshold the docked status
## window applies to its own HP value, so the plate and the window can never
## disagree about when a unit is in trouble — only the treatment differs, with
## the plate taking Solar Storm's ember stops where the window turns its text
## `TEXT_ACCENT`.
func is_critical() -> bool:
	return (
		hitpoints * NoggThemeScript.PLATE_CRITICAL_DENOMINATOR
		< max_hitpoints * NoggThemeScript.PLATE_CRITICAL_NUMERATOR
	)


func ramp_top() -> Color:
	return (
		NoggThemeScript.PLATE_BAR_CRITICAL_TOP
		if is_critical() else
		NoggThemeScript.PLATE_BAR_FILL_TOP
	)


func ramp_bottom() -> Color:
	return (
		NoggThemeScript.PLATE_BAR_CRITICAL_BOTTOM
		if is_critical() else
		NoggThemeScript.PLATE_BAR_FILL_BOTTOM
	)
