class_name SideTurnScreenCues
extends CanvasLayer

signal action_requested(actionID: String)
signal end_turn_requested()

const BannerScript = preload("res://src/presentation/battle/ui/side_turn/SideTurnBanner.gd")
const IconArcScript = preload("res://src/presentation/battle/ui/side_turn/SideTurnIconArc.gd")
const PreviewBoxScript = preload("res://src/presentation/battle/ui/side_turn/SideTurnPreviewBox.gd")
const EndButtonScript = preload("res://src/presentation/battle/ui/side_turn/SideTurnEndButton.gd")

const ActionIconsScript = preload("res://src/presentation/ActionIcons.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const PREVIEW_OFFSET := Vector2(24.0, -96.0)
## The target sword is the arc's own attack icon at the arc's own size, so the cue that promises an
## attack reads as one of the icons already floating over the board.
const SWORD_SIZE := 42.0
const SWORD_ENTRANCE_SCALE := 1.35
const SWORD_ENTRANCE_SECONDS := 0.16

var _root: Control
var _banner
var _arc
var _endButton
var _previews: Array = []
var _projectWorld: Callable
var _arcWorldAnchor := Vector3.ZERO
var _sword: TextureRect
var _swordSource: Callable
var _swordAnchor: Node3D
var _arcVisible := false


func _init() -> void:
	# Board annotations: under every HUD window, so a sheet or menu the HUD opens is never drawn
	# beneath the arc, the sword or a forecast.
	layer = NoggThemeScript.WORLD_EFFECT_LAYER
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The game theme, or every window, banner and button here falls back to Godot's default sans.
	_root.theme = NoggThemeScript.build_game_theme()
	add_child(_root)
	_banner = BannerScript.new()
	_root.add_child(_banner)
	_arc = IconArcScript.new()
	_arc.action_requested.connect(func(id: String): action_requested.emit(id))
	_root.add_child(_arc)
	_sword = TextureRect.new()
	_sword.name = "TargetSword"
	_sword.texture = ActionIconsScript.texture_for("attack")
	_sword.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sword.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sword.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sword.size = Vector2.ONE * SWORD_SIZE
	_sword.pivot_offset = _sword.size * 0.5
	_sword.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sword.visible = false
	_root.add_child(_sword)
	_endButton = EndButtonScript.new()
	_endButton.end_requested.connect(func(): end_turn_requested.emit())
	_root.add_child(_endButton)


func _ready() -> void:
	_layoutFixedCues()
	get_viewport().size_changed.connect(_layoutFixedCues)


func _process(_delta: float) -> void:
	if not _projectWorld.is_valid():
		return
	if _arcVisible:
		_arc.position = _projectWorld.call(_arcWorldAnchor)
	_updateSword()
	for preview in _previews:
		if is_instance_valid(preview):
			preview.position = _projectWorld.call(preview.worldAnchor) + PREVIEW_OFFSET


## Hidden whole while a HUD modal is open: under the sheet the arc would still take clicks, and a
## forecast or End turn has nothing to say about a unit being read.
func setModalOpen(open: bool) -> void:
	_root.visible = not open


func setProjector(projectWorld: Callable) -> void:
	_projectWorld = projectWorld


## `source` returns the targeted unit's world anchor Node3D, or null.
func setSwordSource(source: Callable) -> void:
	_swordSource = source


func _updateSword() -> void:
	var anchor: Node3D = _swordSource.call() if _swordSource.is_valid() else null
	if anchor == null or not anchor.is_inside_tree():
		_swordAnchor = null
		_sword.visible = false
		return
	if anchor != _swordAnchor:
		_swordAnchor = anchor
		_sword.scale = Vector2.ONE * SWORD_ENTRANCE_SCALE
		_sword.create_tween().tween_property(_sword, "scale", Vector2.ONE, SWORD_ENTRANCE_SECONDS) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sword.position = (_projectWorld.call(anchor.global_position) as Vector2) - _sword.size * 0.5
	_sword.visible = true


func showTurnBanner(friendly: bool) -> void:
	_banner.showTurn("Your turn" if friendly else "Enemy turn", friendly)


func hideTurnBanner() -> void:
	_banner.visible = false


func showActionArc(
		worldAnchor: Vector3, enabled: Dictionary, crossed: Array = [], undo: bool = false
) -> void:
	_arcWorldAnchor = worldAnchor
	_arcVisible = true
	var screen: Vector2 = _projectWorld.call(worldAnchor) if _projectWorld.is_valid() else Vector2.ZERO
	_arc.showArc(screen, enabled, crossed, undo)


func setAiming(aiming: bool) -> void:
	_arc.setAiming(aiming)


func hideActionArc() -> void:
	_arcVisible = false
	_arc.hideArc()


func showForecasts(models: Array) -> void:
	clearForecasts()
	for model: Dictionary in models:
		var preview = PreviewBoxScript.new()
		_root.add_child(preview)
		var anchor: Vector3 = model.get("world_anchor", Vector3.ZERO)
		preview.position = _projectWorld.call(anchor) + PREVIEW_OFFSET \
			if _projectWorld.is_valid() else Vector2.ZERO
		preview.configure(
			int(model.get("monster_id", -1)), str(model.get("name", "Target")),
			anchor, model.get("forecast", {}))
		_previews.append(preview)


func clearForecasts() -> void:
	for preview in _previews:
		if is_instance_valid(preview):
			preview.queue_free()
	_previews.clear()


func setReadyCount(count: int) -> void:
	_endButton.setReadyCount(count)


## End turn belongs to the player's side. During a CPU turn it would count the enemy's ready units
## on the player's own button.
func setEndTurnVisible(shown: bool) -> void:
	_endButton.visible = shown


func setEndTurnConfirming(confirming: bool) -> void:
	_endButton.setConfirming(confirming)


func previewCount() -> int:
	return _previews.size()


func actionArcFlipped() -> bool:
	return _arc.isFlipped()


func endTurnConfirming() -> bool:
	return _endButton.isConfirming()


func _layoutFixedCues() -> void:
	var viewportSize := get_viewport().get_visible_rect().size
	_root.size = viewportSize
	# Screen-docked cues keep the HUD's own screen margin, like every other HUD window.
	var margin := NoggThemeScript.HEX_SCREEN_MARGIN
	_banner.setRestPosition(Vector2(roundf((viewportSize.x - _banner.size.x) * 0.5), margin))
	_endButton.position = Vector2(
		viewportSize.x - _endButton.size.x - margin,
		viewportSize.y - _endButton.size.y - margin)
