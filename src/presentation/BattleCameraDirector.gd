## Drives the battle camera when the player is not.
##
## Two camera modes exist. In **free** mode the player owns the view outright
## and this director does nothing — that is the historical behaviour, and the
## rule `BattleCameraController.panFocusTo()` was built for: the camera may
## guarantee visibility but never take authorship. In **director** mode this
## class takes authorship deliberately, using the controller's
## `frameTo()`/`orbitBy()`/`settleToQuadrant()` group, and hands it back
## intact via `restoreFreeView()`.
##
## **It subsumes the old `_pan_camera_to_active_unit()`.** That function was
## already a small director — same off-screen-only test, same `panFocusTo()`
## — and running both would give two things an opinion about where the camera
## belongs. Its behaviour survives here as `_frame_unit()`, and free mode
## still calls exactly that and nothing else, so turning the director off
## leaves the shipping camera behaviour unchanged rather than degraded.
##
## **What it does with a turn:**
##
##   player turn opens  -> frame the actor, settle to a quadrant
##   CPU turn opens     -> start a slow orbit
##   a big spell casts  -> frame and zoom to the affected area
##   playback drains    -> stop orbiting, settle, frame whoever is next
##
## **Why the orbit is a rate and not a tween.** A CPU turn's length is not
## known when it starts: deliberation is 2-11 frames (~74ms, measured on a
## real battle), but the perceptible window is the whole turn including its
## animation playback, which depends on how many actions the AI queued. There
## is no end time to tween toward, so the orbit is started, left running, and
## stopped when playback drains.
##
## **Why it settles to a quadrant.** Rotating between turns is only safe
## because tile aiming snaps its input to `nearestQuadrantYaw()`. Landing on
## an exact multiple of 90 degrees makes that snap exact rather than an
## approximation across an arbitrary angle — the player only ever aims from
## one of four clean orientations.

class_name BattleCameraDirector
extends RefCounted

## Degrees per second of drift during a CPU turn.
##
## **A feel value, not a derived one.** At 8 deg/s a three-second enemy turn
## moves about 24 degrees, so the view crosses into a new quadrant roughly
## every second enemy turn — slow enough to read as drift rather than as
## spin, fast enough that the board is not always seen from one side. Tune by
## eye; nothing else depends on the number.
const ORBIT_DEGREES_PER_SECOND := 8.0

## How tight the director sits on the acting unit, as a fraction of the
## board-wide framing the battle opens at.
##
## **This is what makes a cast read as a zoom-out at all.** Resting at the
## board-wide framing, a spell's affected area already fits — a radius-3 spell
## is 7 tiles across against a view roughly 11 tiles tall — so "widen to fit
## the spell" would compute a smaller number than the current zoom every time
## and do nothing. Pulling the resting framing in is what gives the cast
## somewhere to pull back to.
##
## A feel value, and the one most worth tuning: lower is more intimate and
## more cinematic, but a tactics player planning a turn needs to see enough
## board to plan against. Raise it toward 1.0 if the player turn feels blind.
const RESTING_ZOOM_FRACTION := 0.75

## How much clear space to leave around a framed spell, in tiles. The affected
## area is `2 * radius + 1` tiles across; this is the margin on top of that.
const CAST_FRAME_MARGIN_TILES := 3.0

## Spells at or below this radius never move the camera.
##
## A single-tile zap does not need a cinematic, and framing every cast would
## put two camera moves on every enemy turn. Above it, the affected area is
## large enough that the player benefits from seeing all of it at once, which
## is exactly when a zoom-out earns its cost.
const CAST_FRAME_MIN_RADIUS := 2

## Margin, in the same logical screen space `docs/UI_DESIGN.md` §8 measures
## windows against, that keeps a unit clear of the displayed view's edge
## rather than merely inside it. `RetroRenderController.get_display_rect()` is
## used rather than the raw viewport rect because retro rendering can
## letterbox the world image inside the window; a unit sitting in the
## letterbox bar would otherwise read as "visible".
##
## Moved here from `BattlePresentationController.CAMERA_FOCUS_EDGE_MARGIN`
## along with its only reader, `_frame_unit()`.
const FOCUS_EDGE_MARGIN := 64.0

var _camera: BattleCameraController
var _visual_adapter
var _retro_renderer
var _enabled: bool = false
## The unit the director considers the subject of the current turn. Framing
## returns here after a spell pulls the camera away.
var _subject_monster_id: int = -1
## The board-wide framing the battle opened at, captured when the director is
## enabled. `_resting_size` is derived from it.
##
## Captured rather than read from the camera's
## `default_size`, which is deliberately NOT used here: `default_size` is
## snapshotted in `BattleCameraController._ready()`, and the battle's real
## framing size is assigned later, once the board dimensions are known. By
## then `default_size` still holds the pre-battle placeholder. (That also
## means the free camera's double-middle-click reset returns to that
## placeholder rather than the battle framing — pre-existing, and left alone
## here rather than fixed silently as a side effect of a camera-director
## change.)
var _battle_framing_size: float = 0.0
## The zoom the director sits at on a normal turn, and returns to after a
## spell widened it. `_battle_framing_size * RESTING_ZOOM_FRACTION`.
var _resting_size: float = 0.0


func _init(camera: BattleCameraController, visual_adapter, retro_renderer) -> void:
	_camera = camera
	_visual_adapter = visual_adapter
	_retro_renderer = retro_renderer


func is_enabled() -> bool:
	return _enabled


## Entering director mode snapshots the player's framing so leaving it can
## give that exact view back. Leaving restores it and stops every motion in
## flight — a director that kept orbiting after being switched off would be
## the worst of both modes.
func set_enabled(enabled: bool) -> void:
	if enabled == _enabled:
		return
	_enabled = enabled
	if _camera == null:
		return
	if enabled:
		_camera.snapshotFreeView()
		_battle_framing_size = _camera.size
		_resting_size = _battle_framing_size * RESTING_ZOOM_FRACTION
		_camera.settleToQuadrant()
		# Take up the director's own framing immediately rather than waiting
		# for the next turn: the toggle should visibly do something on the
		# frame it is pressed.
		_frame_subject_at_resting_zoom()
	else:
		_camera.restoreFreeView()


## The player's turn is starting. Frame them and stop drifting: aiming happens
## from here, and it must happen from a settled quadrant.
func on_player_turn_began(monster_id: int) -> void:
	_subject_monster_id = monster_id
	if not _enabled:
		# Free mode keeps exactly the old behaviour and nothing more.
		_frame_unit(monster_id)
		return
	_camera.settleToQuadrant()
	# Unconditionally, not under free mode's off-screen-only rule: "focus on
	# the acting piece" is the whole premise of director mode, and a unit that
	# happens to already be on screen still needs the camera centred and
	# zoomed onto it rather than left wherever the last turn ended.
	_frame_subject_at_resting_zoom()


## A CPU turn is starting. Begin the drift; `on_turn_playback_drained()` ends
## it. Deliberately does not frame the actor here — the unit has not moved or
## acted yet, so there is nothing to look at that was not already on screen,
## and the cast hook below handles the moment there is.
func on_cpu_turn_began(monster_id: int) -> void:
	_subject_monster_id = monster_id
	if not _enabled:
		return
	_camera.orbitBy(ORBIT_DEGREES_PER_SECOND)


## A spell is beginning to play. `center` is the affected area's centre in
## world space and `radius` its board radius.
##
## Called from the adapter at the moment the cast animation starts rather than
## when the command resolves, so the camera arrives with the effect instead of
## before or after it.
func on_cast_started(center: Vector3, radius: int) -> void:
	if not _enabled or _camera == null:
		return
	if radius < CAST_FRAME_MIN_RADIUS:
		return
	var span := float(2 * radius + 1) + CAST_FRAME_MARGIN_TILES
	# Never zoom *in* to frame a spell: `size` is the orthographic view's
	# height in world units, so a small area at an already-wide zoom would pull
	# the camera closer and lose context the player already had. Clamped
	# against the board framing too, so a huge radius cannot pull the camera
	# back further than the whole board.
	var wanted := clampf(span, _camera.size, maxf(_battle_framing_size, _camera.size))
	_camera.frameTo(center, wanted)


## Playback for the turn has finished. Stop drifting, settle, and put whoever
## is next back in frame.
func on_turn_playback_drained() -> void:
	if not _enabled or _camera == null:
		return
	_camera.settleToQuadrant()
	if _subject_monster_id != -1:
		_frame_subject_at_resting_zoom()


## Returns the camera to the turn's subject at the resting zoom, undoing
## whatever a spell did to the framing.
func _frame_subject_at_resting_zoom() -> void:
	var world_pos = _unit_world_position(_subject_monster_id)
	if world_pos == null:
		return
	_camera.frameTo(world_pos, _resting_size)


## The old `_pan_camera_to_active_unit()`, verbatim in behaviour: guarantees
## the unit is on screen and otherwise moves the camera not at all. Uses
## `panFocusTo()` — position only — because in free mode this must not take
## authorship of a view the player set.
func _frame_unit(monster_id: int) -> void:
	if _camera == null or _visual_adapter == null or _retro_renderer == null:
		return
	var world_pos = _unit_world_position(monster_id)
	if world_pos == null:
		return
	if _camera.is_position_behind(world_pos):
		_camera.panFocusTo(world_pos)
		return
	var viewport_pos := _camera.unproject_position(world_pos)
	# Annotated rather than inferred: `_retro_renderer` is deliberately untyped
	# (constructed with `_init(self)`, no class_name), so its returns arrive as
	# Variant and `:=` cannot infer from them.
	var screen_pos: Vector2 = _retro_renderer.world_to_screen(viewport_pos)
	var visible_rect: Rect2 = _retro_renderer.get_display_rect().grow(-FOCUS_EDGE_MARGIN)
	if visible_rect.has_point(screen_pos):
		return
	_camera.panFocusTo(world_pos)


## `null` rather than a sentinel Vector3: every caller has a real "then do
## nothing" branch, and Vector3.ZERO is a legal board position.
func _unit_world_position(monster_id: int):
	if monster_id == -1 or _visual_adapter == null:
		return null
	return _visual_adapter.get_monster_world_position(monster_id)
