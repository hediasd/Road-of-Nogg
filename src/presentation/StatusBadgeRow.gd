## The row of square status-effect icons carried above one unit.
##
## **A projected Control, not world-space sprites.** The battle world renders
## into an isolated `SubViewport` that presets drop to 480x360; the previous
## `Sprite3D` badges were downsampled with it to a few device pixels, and their
## duration `Label3D` came out smaller than one. Positioning by projection keeps
## the row at native resolution at every preset. `GodotVisualAdapter` owns the
## projection; this class owns layout, hover and drawing.
##
## **A badge rests as a plain colour chip and becomes an icon only under the
## pointer.** At the resting size no silhouette is legible — an eight-pixel
## square cannot carry one — so the row does not pretend otherwise. At rest it
## answers "how many effects, and roughly what kind" through flat colour;
## hovering answers "which one" by growing to `StatusIconRegistry.SOURCE_PX` and
## crossfading the art in. The grown size is exactly 1:1 with the source, so the
## icon is never resampled at the one moment the player is looking straight at
## it.

class_name StatusBadgeRow
extends Control

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const StatusEffectIconsScript = preload("res://src/presentation/StatusEffectIcons.gd")

## Entries currently drawn: `{"texture": Texture2D, "chip": Color, "duration": int}`.
var _entries: Array = []
## Index of the badge under the pointer, or -1. Drives which badge grows.
var _hovered: int = -1
## Per-badge growth, tweened toward 1.0 or `STATUS_BADGE_HOVER_SCALE` so a badge
## does not snap between sizes as the pointer crosses it.
var _scales: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Rebuilds the row from the unit's active effects. Returns whether anything
## changed, so a caller polling every frame can skip the redraw on the frames
## where the effects are identical — which is nearly all of them.
func set_effects(effects: Array) -> bool:
	var built := _build_entries(effects)
	if not _entries_differ(built):
		return false
	_entries = built
	_scales.resize(_entries.size())
	for index in range(_scales.size()):
		if _scales[index] == null:
			_scales[index] = 1.0
	_hovered = mini(_hovered, _entries.size() - 1)
	_resize_to_entries()
	queue_redraw()
	return true


## `local_point` is the pointer in this row's own space, or `null` when the
## pointer is elsewhere. Returns whether the hovered badge changed.
func set_hover_point(local_point) -> bool:
	var found := -1
	if local_point != null:
		var point: Vector2 = local_point
		for index in range(_entries.size()):
			if _rest_rect(index).has_point(point):
				found = index
				break
	if found == _hovered:
		return false
	_hovered = found
	queue_redraw()
	return true


## Advances the growth tween. Driven by the caller's frame loop rather than by an
## internal `_process`, so the whole row hierarchy has one update path.
func advance(delta: float) -> bool:
	var changed := false
	var rate := delta / maxf(NoggThemeScript.STATUS_BADGE_HOVER_TWEEN, 0.0001)
	for index in range(_scales.size()):
		var target := (
			NoggThemeScript.STATUS_BADGE_HOVER_SCALE if index == _hovered else 1.0
		)
		var current: float = _scales[index]
		if is_equal_approx(current, target):
			continue
		_scales[index] = move_toward(current, target, rate * (NoggThemeScript.STATUS_BADGE_HOVER_SCALE - 1.0))
		changed = true
	if changed:
		queue_redraw()
	return changed


func has_entries() -> bool:
	return not _entries.is_empty()


func _build_entries(effects: Array) -> Array:
	var ordered: Array = StatusEffectIconsScript.sorted_effects(effects)
	var maximum: int = NoggThemeScript.STATUS_BADGE_MAX_VISIBLE
	var built: Array = []
	if ordered.size() <= maximum:
		for effect in ordered:
			built.append({
				"texture": StatusEffectIconsScript.texture_for(effect),
				"chip": StatusEffectIconsScript.chip_color(effect),
				"duration": int(effect.get("remainingTurns", 0))
			})
		return built
	# One slot goes to the counter, so only `maximum - 1` icons are shown and the
	# counter reports everything it displaced — including the effect whose slot
	# it took.
	for index in range(maximum - 1):
		var effect: Dictionary = ordered[index]
		built.append({
			"texture": StatusEffectIconsScript.texture_for(effect),
			"chip": StatusEffectIconsScript.chip_color(effect),
			"duration": int(effect.get("remainingTurns", 0))
		})
	built.append({
		"texture": StatusEffectIconsScript.overflow_texture(),
		"chip": StatusEffectIconsScript.overflow_chip_color(),
		"duration": ordered.size() - (maximum - 1)
	})
	return built


func _entries_differ(built: Array) -> bool:
	if built.size() != _entries.size():
		return true
	for index in range(built.size()):
		if built[index]["texture"] != _entries[index]["texture"]:
			return true
		if built[index]["chip"] != _entries[index]["chip"]:
			return true
		if built[index]["duration"] != _entries[index]["duration"]:
			return true
	return false


## The row is sized to its resting layout. A hovered badge overflows these
## bounds deliberately — `clip_contents` stays false — because reserving room for
## the grown size would leave a gap above every unit that is not being hovered.
func _resize_to_entries() -> void:
	var badge: float = NoggThemeScript.STATUS_BADGE_SIZE
	var gap: float = NoggThemeScript.STATUS_BADGE_GAP
	var count := _entries.size()
	var width := 0.0 if count == 0 else float(count) * badge + float(count - 1) * gap
	size = Vector2(width, badge)
	pivot_offset = size * 0.5


func _rest_rect(index: int) -> Rect2:
	var badge: float = NoggThemeScript.STATUS_BADGE_SIZE
	var gap: float = NoggThemeScript.STATUS_BADGE_GAP
	return Rect2(Vector2(float(index) * (badge + gap), 0.0), Vector2(badge, badge))


func _draw() -> void:
	# Grown badges draw last so a hovered one is never clipped by its neighbour.
	var deferred: Array = []
	for index in range(_entries.size()):
		if _scales[index] > 1.0:
			deferred.append(index)
		else:
			_draw_badge(index)
	for index in deferred:
		_draw_badge(index)


func _draw_badge(index: int) -> void:
	var entry: Dictionary = _entries[index]
	var rest := _rest_rect(index)
	var scale_value: float = _scales[index]
	# Grows about its own centre, so a badge expands in place instead of pushing
	# its row sideways and making the player chase it.
	var grown := rest.size * scale_value
	var target := Rect2(rest.get_center() - grown * 0.5, grown)

	# The chip is the resting state and the icon fades in over it as the badge
	# grows, so there is no moment where the badge is neither one nor the other.
	draw_rect(target.grow(_outline_width()), NoggThemeScript.OUTLINE, true)
	draw_rect(target, entry["chip"], true)

	var reveal := _reveal(scale_value)
	if reveal <= 0.0:
		return
	var texture: Texture2D = entry["texture"]
	if texture != null:
		draw_texture_rect(texture, target, false, Color(1.0, 1.0, 1.0, reveal))
	_draw_duration(entry, target, reveal)


## How far this badge has turned from a chip into an icon, 0 at rest and 1 at
## full hover.
func _reveal(scale_value: float) -> float:
	var span: float = NoggThemeScript.STATUS_BADGE_HOVER_SCALE - 1.0
	if span <= 0.0:
		return 1.0
	return clampf((scale_value - 1.0) / span, 0.0, 1.0)


## One device pixel at every `ui_scale`. A chip this small needs a hairline to
## separate it from the board, not a border that scales with it.
func _outline_width() -> float:
	return 1.0


## Duration rides the badge's own scale and reveal, so it appears only on the
## hovered badge — which is the whole point of growing it. At the resting size
## there is no room for a numeral at all.
func _draw_duration(entry: Dictionary, rect: Rect2, reveal: float) -> void:
	var duration := int(entry["duration"])
	if duration <= 0:
		return
	var text := "*" if BattleState.isPermanentDuration(duration) else str(duration)
	var cell := maxf(1.0, rect.size.x / float(StatusEffectIconsScript.ICON_SIZE))
	var glyph_width := float(DIGIT_COLUMNS) * cell
	var origin := Vector2(
		rect.position.x + rect.size.x - glyph_width * float(text.length()) - cell,
		rect.position.y + rect.size.y - float(DIGIT_ROWS) * cell - cell
	)
	for index in range(text.length()):
		_draw_glyph(
			text.substr(index, 1),
			origin + Vector2(glyph_width * float(index), 0.0),
			cell,
			reveal
		)


const DIGIT_COLUMNS := 3
const DIGIT_ROWS := 5
## Drawn rather than typed, for the reason `docs/UI_DESIGN.md` §3 gives: the
## shipping bitmap face floors to whole multiples of 12 device pixels, which is
## far larger than a resting badge. A drawn glyph has no floor.
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
	"*": ["000", "101", "010", "101", "000"],
}


func _draw_glyph(character: String, origin: Vector2, cell: float, reveal: float) -> void:
	var glyph: Array = DIGIT_GLYPHS.get(character, [])
	for row in range(glyph.size()):
		var line: String = glyph[row]
		for column in range(line.length()):
			if line[column] != "1":
				continue
			var at := origin + Vector2(float(column) * cell, float(row) * cell)
			var ink := NoggThemeScript.OUTLINE
			var face := NoggThemeScript.TEXT_PRIMARY
			ink.a *= reveal
			face.a *= reveal
			draw_rect(Rect2(at + Vector2(cell, cell), Vector2(cell, cell)), ink)
			draw_rect(Rect2(at, Vector2(cell, cell)), face)
