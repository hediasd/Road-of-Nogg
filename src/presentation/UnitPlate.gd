## UnitPlate — the board-space readout carried under every living unit.
##
## See `docs/UI_DESIGN.md` §10c for the contract this implements. Two properties
## of it are load-bearing and easy to undo by accident:
##
## **It is a Control, not world-space geometry.** The battle world renders into
## an isolated `SubViewport` that presets drop to 480x360. A bar hairline or a
## numeral drawn inside that viewport is downsampled with it and stops being
## readable. The plate is positioned by projecting the unit's world position into
## screen space instead, the same way `DamageNumberBillboard` already does, so it
## stays crisp at every preset. `GodotVisualAdapter` owns that projection; this
## class only draws.
##
## **The bar is notched, and that is not decoration.** Shipped stats put most
## exchanges at 2-8 damage against 28-60 max HP, so a continuous fill moves
## roughly 7% per hit and reads as not having moved at all. Notching every
## `PLATE_HP_PER_NOTCH` gives each unit three to six segments and makes a typical
## hit cross a visible boundary.

class_name UnitPlate
extends Control

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## One opaque copy per cardinal offset, then the glyph on top. A plate sits over
## an arbitrary lit board, so the numeral needs the same defence the damage
## number and the window text already use. Deliberately a fixed one device pixel
## at every `ui_scale`: it is the crisp hairline finishing the glyph, not a
## stroke that should grow with it.
const OUTLINE_OFFSETS := [
	Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)
]

## Building a Theme is not free and every plate wants the same face, so the one
## font is resolved once for the process rather than per plate.
static var _font: Font = null

var level: int = 1
var team_color: Color = Color.WHITE
var hitpoints: int = 1
var max_hitpoints: int = 1
var spent: bool = false


static func _ensure_font() -> void:
	if _font == null:
		_font = NoggThemeScript.build_game_theme().default_font


func _init() -> void:
	_ensure_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(NoggThemeScript.PLATE_WIDTH, NoggThemeScript.PLATE_RING_DIAMETER)
	pivot_offset = size * 0.5


## Returns whether anything actually changed, so the caller can skip a redraw on
## the frames where a unit's readout is identical to the last one — which is most
## frames, since this is polled rather than event-driven.
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


## An unfilled circle: the stroke carries team identity and the numeral carries
## level, and leaving the interior transparent is what lets one element hold both
## without the numeral fighting a fill for contrast. The board reads through the
## gap, which matters on a crowded tile.
func _draw_level_ring() -> void:
	var radius := (NoggThemeScript.PLATE_RING_DIAMETER - NoggThemeScript.PLATE_RING_STROKE) * 0.5
	var centre := Vector2(NoggThemeScript.PLATE_RING_DIAMETER * 0.5, size.y * 0.5)
	draw_arc(centre, radius, 0.0, TAU, 32, team_color, NoggThemeScript.PLATE_RING_STROKE, true)

	if _font == null:
		return
	var text := str(level)
	var font_size := NoggThemeScript.FONT_SIZE_BODY
	var extent := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	# draw_string takes a baseline, not a top-left, so the ascent has to come
	# back in or the numeral sits a full line high of the ring's centre.
	var baseline := Vector2(
		centre.x - extent.x * 0.5,
		centre.y - extent.y * 0.5 + _font.get_ascent(font_size)
	).round()
	for offset in OUTLINE_OFFSETS:
		draw_string(
			_font, baseline + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			font_size, NoggThemeScript.OUTLINE
		)
	draw_string(
		_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		font_size, NoggThemeScript.TEXT_PRIMARY
	)


func _draw_health_bar() -> void:
	var bar := Rect2(
		Vector2(
			NoggThemeScript.PLATE_RING_DIAMETER + NoggThemeScript.PLATE_GAP,
			(size.y - NoggThemeScript.PLATE_BAR_HEIGHT) * 0.5
		),
		Vector2(NoggThemeScript.PLATE_BAR_WIDTH, NoggThemeScript.PLATE_BAR_HEIGHT)
	)
	draw_rect(bar, NoggThemeScript.PLATE_BAR_TRACK, true)

	var safe_max := maxi(1, max_hitpoints)
	var ratio := clampf(float(hitpoints) / float(safe_max), 0.0, 1.0)
	if ratio > 0.0:
		draw_rect(
			Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)),
			fill_color(),
			true
		)

	# Notches are drawn over the fill and the track alike, so a segment boundary
	# stays visible whether that part of the bar is full or empty — the count of
	# segments is what the player reads, not just how far the fill reaches.
	var notch := NoggThemeScript.PLATE_HP_PER_NOTCH
	var hp_at := notch
	while hp_at < safe_max:
		var x := bar.position.x + bar.size.x * (float(hp_at) / float(safe_max))
		draw_line(
			Vector2(x, bar.position.y),
			Vector2(x, bar.position.y + bar.size.y),
			NoggThemeScript.OUTLINE,
			NoggThemeScript.PLATE_BAR_BORDER
		)
		hp_at += notch

	draw_rect(bar, NoggThemeScript.OUTLINE, false, NoggThemeScript.PLATE_BAR_BORDER)


## Below one third turns gold. Deliberately the same threshold and token the
## docked status window applies to its own HP value, so the plate and the window
## can never disagree about when a unit is in trouble.
func fill_color() -> Color:
	var critical := (
		hitpoints * NoggThemeScript.PLATE_CRITICAL_DENOMINATOR
		< max_hitpoints * NoggThemeScript.PLATE_CRITICAL_NUMERATOR
	)
	return NoggThemeScript.TEXT_ACCENT if critical else NoggThemeScript.PLATE_BAR_FILL
