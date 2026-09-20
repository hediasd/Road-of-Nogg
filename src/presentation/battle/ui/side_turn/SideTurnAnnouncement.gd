## The turn announcement: NEXT TURN, then TURN #n, over the middle of the screen.
##
## WHY IT IS NOT THE EXISTING BANNER. `SideTurnBanner` answers "whose turn is this" in the HUD's
## own information hierarchy: small, docked to the top edge, Terminal face, gone in a second. This
## answers "the turn changed, and this is which turn it now is" -- a chapter heading rather than a
## status line -- so it is the display face at three times banner size, in the middle of the board,
## and it is the one cue in the battle that is allowed to be large.
##
## THE GROWTH IS VERTICAL ONLY, from zero height to full, and each message leaves the same way it
## arrived. A uniform scale-up reads as something flying toward the camera; growing only in Y reads
## as a title unfurling, which is what a turn boundary should feel like. It is `scale.y` around the
## control's own centre rather than a font size tween because a bitmap face cannot be interpolated
## between sizes -- Herald floors any size that is not a whole multiple of its nominal cell, so an
## animated font size would snap between two sizes instead of growing.
##
## MOUSE-TRANSPARENT AND NON-BLOCKING. The turn opens as it always did; this plays over it. A cue
## that had to finish before the player could act would put the loop's scheduling in two places,
## and `HexBattlePlayback` is deliberately the only thing that decides when anything may start.

class_name SideTurnAnnouncement
extends Control

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## Emitted once the last message has left the screen. Nothing waits on it today; it exists so a
## caller that wants to sequence something after the announcement does not have to time it by hand.
signal announcement_finished()

## Three Herald cells. A multiple of the banner size, never a hand-picked pixel count: the face
## floors any size off its 13-unit grid and renders silently small, and multiplying a size that is
## already on the grid keeps it there at every UI scale.
const FONT_SIZE_MULTIPLE := 3
## One message's beats. The hold is what makes it readable; the exits are quicker than the
## entrances because a title that has been read should get out of the way.
const GROW_SECONDS := 0.16
const HOLD_SECONDS := 0.44
const COLLAPSE_SECONDS := 0.12
## How tall the control is, as a share of the text's own line height. The slack is the letterforms'
## own ascent and descent plus the shadow, which would otherwise be clipped by the scaled rect.
const HEIGHT_SLACK := 1.6

var _label: Label
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_label = NoggThemeScript.make_banner_label()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", NoggThemeScript.TEXT_ACCENT)
	add_child(_label)


func _ready() -> void:
	_label.add_theme_font_size_override(
		"font_size", NoggThemeScript.FONT_SIZE_BANNER * FONT_SIZE_MULTIPLE)


## Plays the whole announcement for the turn that has just opened: NEXT TURN, then TURN #turnNumber.
## Called again before it finishes, it restarts from the beginning -- a turn boundary arriving over
## a half-played announcement means the announcement on screen is stale.
func showTurn(turnNumber: int) -> void:
	_play(["NEXT TURN", "TURN #%d" % maxi(turnNumber, 1)])


## Takes the announcement off the screen at once, with no exit. For teardown and for the battle
## being decided, where a turn heading has nothing left to announce.
func cancel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	visible = false
	scale.y = 1.0


func isAnnouncing() -> bool:
	return visible and _tween != null and _tween.is_valid()


## The text currently on screen, or "". For probes, which cannot read a rendered glyph.
func announcedText() -> String:
	return _label.text if visible else ""


## Centres the announcement on the viewport. Full width, so the longest heading cannot be clipped
## by a rect measured for a shorter one, and its own height is measured from the live face.
func layoutFor(viewportSize: Vector2) -> void:
	var font := _label.get_theme_font("font")
	var fontSize := _label.get_theme_font_size("font_size")
	var lineHeight := font.get_height(fontSize) if font != null else float(fontSize)
	size = Vector2(viewportSize.x, ceilf(lineHeight * HEIGHT_SLACK))
	position = Vector2(0.0, roundf((viewportSize.y - size.y) * 0.5))
	# The growth happens around the middle of the rect, which is where the text sits.
	pivot_offset = size * 0.5
	_label.size = size


func _play(messages: Array) -> void:
	if messages.is_empty():
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_label.text = str(messages[0])
	scale.y = 0.0
	visible = true
	_tween = create_tween()
	for value in messages:
		var text := str(value)
		_tween.tween_callback(func(): _label.text = text)
		_tween.tween_property(self, "scale:y", 1.0, GROW_SECONDS).from(0.0) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_interval(HOLD_SECONDS)
		_tween.tween_property(self, "scale:y", 0.0, COLLAPSE_SECONDS) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_finish)


func _finish() -> void:
	visible = false
	scale.y = 1.0
	_tween = null
	announcement_finished.emit()
