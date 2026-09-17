class_name SideTurnScreenCues
extends CanvasLayer

signal action_requested(actionID: String)
signal end_turn_requested()

const BannerScript = preload("res://src/presentation/battle/ui/side_turn/SideTurnBanner.gd")
const IconArcScript = preload("res://src/presentation/battle/ui/side_turn/SideTurnIconArc.gd")
const PreviewBoxScript = preload("res://src/presentation/battle/ui/side_turn/SideTurnPreviewBox.gd")
const EndButtonScript = preload("res://src/presentation/battle/ui/side_turn/SideTurnEndButton.gd")

const PREVIEW_OFFSET := Vector2(24.0, -96.0)

var _root: Control
var _banner
var _arc
var _endButton
var _previews: Array = []
var _projectWorld: Callable
var _arcWorldAnchor := Vector3.ZERO
var _arcVisible := false


func _init() -> void:
	layer = 12
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_banner = BannerScript.new()
	_root.add_child(_banner)
	_arc = IconArcScript.new()
	_arc.action_requested.connect(func(id: String): action_requested.emit(id))
	_root.add_child(_arc)
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
	for preview in _previews:
		if is_instance_valid(preview):
			preview.position = _projectWorld.call(preview.worldAnchor) + PREVIEW_OFFSET


func setProjector(projectWorld: Callable) -> void:
	_projectWorld = projectWorld


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
	_banner.position = Vector2((viewportSize.x - _banner.size.x) * 0.5, 14.0)
	_endButton.position = Vector2(
		viewportSize.x - _endButton.size.x - 22.0,
		viewportSize.y - _endButton.size.y - 20.0)
