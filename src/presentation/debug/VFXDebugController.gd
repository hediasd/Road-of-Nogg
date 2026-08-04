## Standalone spell-VFX authoring scene using the shipping render pipeline.
##
## Core shortcuts intentionally use letters because project.godot defines no
## custom input actions and the built-in UI owns Enter, Escape, Space, arrows.
## P play | U pause/resume | T settle | O overlap | C capture | M mode

extends Node3D

const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")
const RetroRenderControllerScript = preload("res://src/presentation/RetroRenderController.gd")
const BattleEnvironmentFactoryScript = preload("res://src/presentation/BattleEnvironmentFactory.gd")
const SpellVfxCatalogScript = preload("res://src/presentation/effects/SpellVfxCatalog.gd")
const VfxPlaybackScript = preload("res://src/presentation/effects/VfxPlayback.gd")

const CAMERA_OFFSET := Vector3(6.0, 15.0, 14.0)
## Meadow and Forest are 16 cells across with two elevation steps, producing
## 16 * 0.95 + (2 * 0.5) * 0.35 through the shipping camera-size formula.
const REPRESENTATIVE_CAMERA_SIZE := 15.55
const DEFAULT_FOOTPRINT_RADIUS := 2
const SCREENSHOT_PATH := "user://vfx_debug_capture.png"
const _STATE_PLAYING := "playing"
const _STATE_PAUSED := "paused"
const _STATE_STOPPED := "stopped"
const _ELEMENTS: Array[String] = [
	"fire", "water", "ice", "wind", "earth",
	"wood", "thunder", "darkness", "light", "steel", "none"
]
const _RESOLUTION_OPTIONS := [
	{"label": "Native (shipping default)", "size": Vector2i.ZERO},
	{"label": "640 x 480", "size": Vector2i(640, 480)},
	{"label": "480 x 360", "size": Vector2i(480, 360)},
	{"label": "320 x 240", "size": Vector2i(320, 240)}
]
const _UNEVEN_HEIGHTS := [[0, 1, 0], [1, 2, 1], [0, 1, 2]]

var retroRenderer
var _catalogEntries: Array[Dictionary] = []
var _activePlayback
var _overlapPlaybacks: Array = []
var _playbackState: String = _STATE_STOPPED
var _activeSeed: int = 1
var _activeMode: String = VfxPlaybackScript.MODE_BATTLE
var _layerVisibility: Dictionary = {}
var _syncingScrub: bool = false
var _captureUsed: bool = false
var _captureMessage: String = ""
var _footprintRadius: int = DEFAULT_FOOTPRINT_RADIUS
var _footprintRing: MeshInstance3D

@onready var _spawnAnchor: Node3D = $SpawnAnchor
@onready var _camera: Camera3D = $Camera3D
@onready var _statusLabel: Label = $HUD/PanelContainer/VBoxContainer/StatusLabel
@onready var _effectOption: OptionButton = $HUD/PanelContainer/VBoxContainer/PlaybackGrid/EffectOption
@onready var _elementOption: OptionButton = $HUD/PanelContainer/VBoxContainer/PlaybackGrid/ElementOption
@onready var _modeToggle: CheckButton = $HUD/PanelContainer/VBoxContainer/PlaybackGrid/ModeToggle
@onready var _scaleSetting: SpinBox = $HUD/PanelContainer/VBoxContainer/PlaybackGrid/ScaleSetting
@onready var _seedPin: CheckButton = $HUD/PanelContainer/VBoxContainer/PlaybackGrid/SeedRow/SeedPin
@onready var _seedSetting: SpinBox = $HUD/PanelContainer/VBoxContainer/PlaybackGrid/SeedRow/SeedSetting
@onready var _cycleSeedButton: Button = $HUD/PanelContainer/VBoxContainer/PlaybackGrid/SeedRow/CycleSeedButton
@onready var _playButton: Button = $HUD/PanelContainer/VBoxContainer/CoreButtons/PlayButton
@onready var _pauseButton: Button = $HUD/PanelContainer/VBoxContainer/CoreButtons/PauseButton
@onready var _settleButton: Button = $HUD/PanelContainer/VBoxContainer/CoreButtons/SettleButton
@onready var _overlapButton: Button = $HUD/PanelContainer/VBoxContainer/CoreButtons/OverlapButton
@onready var _screenshotButton: Button = $HUD/PanelContainer/VBoxContainer/CoreButtons/ScreenshotButton
@onready var _scrub: HSlider = $HUD/PanelContainer/VBoxContainer/Scrub
@onready var _layerToggles: GridContainer = $HUD/PanelContainer/VBoxContainer/LayerToggles
@onready var _resolutionOption: OptionButton = $HUD/PanelContainer/VBoxContainer/Controls/ResolutionOption
@onready var _retroToggle: CheckButton = $HUD/PanelContainer/VBoxContainer/Controls/RetroToggle
@onready var _crtToggle: CheckButton = $HUD/PanelContainer/VBoxContainer/Controls/CRTToggle
@onready var _radiusSetting: SpinBox = $HUD/PanelContainer/VBoxContainer/Controls/RadiusSetting


func _ready() -> void:
	retroRenderer = RetroRenderControllerScript.new(self)
	retroRenderer.set_preset(retroRenderer.PRESET_NONE, false)
	_reparentWorldNodes()
	_configureBattleWorld()
	_buildTerrainSamples()
	_buildDummyUnits()
	_buildTargetGuides()
	_configureRenderControls()
	_configurePlaybackControls()
	BattleMeshFactoryScript.prepareNodeMaterials(retroRenderer.world_root)
	_applyRenderControls()
	set_process(true)
	_updateStatus()

	var captureAt := _captureAtArgument()
	if captureAt >= 0.0:
		call_deferred("_runCaptureMode", captureAt)


func _process(_delta: float) -> void:
	_pruneFinishedOverlaps()
	if _activePlayback != null and _activePlayback.is_finished():
		_playbackState = _STATE_STOPPED
		_pauseButton.disabled = true
		_pauseButton.text = "Pause"
	if _activePlayback != null:
		_syncingScrub = true
		_scrub.set_value_no_signal(_activePlayback.get_normalized_time())
		_syncingScrub = false
	_updateStatus()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_P:
			_onPlayPressed()
		KEY_U:
			_onPausePressed()
		KEY_T:
			_onSettlePressed()
		KEY_O:
			_onOverlapPressed()
		KEY_C:
			_captureOnce(false)
		KEY_M:
			_modeToggle.set_pressed_no_signal(not _modeToggle.button_pressed)
			_updateModeToggleText()
			_updateStatus()


func _exit_tree() -> void:
	_disposeAllPlaybacks()


func _configurePlaybackControls() -> void:
	_catalogEntries = SpellVfxCatalogScript.entries()
	assert(not _catalogEntries.is_empty(), "Spell VFX catalog must contain an effect.")
	for entry: Dictionary in _catalogEntries:
		_effectOption.add_item(entry["display_name"])
		_effectOption.set_item_metadata(
			_effectOption.item_count - 1,
			entry["profile_id"]
		)
	for element: String in _ELEMENTS:
		_elementOption.add_item(element.capitalize())
		_elementOption.set_item_metadata(_elementOption.item_count - 1, element)
	_elementOption.select(_ELEMENTS.find("ice"))
	_effectOption.select(0)
	_updateModeToggleText()

	_effectOption.item_selected.connect(_onEffectSelected)
	_elementOption.item_selected.connect(_onElementSelected)
	_modeToggle.toggled.connect(_onModeToggled)
	_scaleSetting.value_changed.connect(_onScaleChanged)
	_cycleSeedButton.pressed.connect(_cycleSeed)
	_playButton.pressed.connect(_onPlayPressed)
	_pauseButton.pressed.connect(_onPausePressed)
	_settleButton.pressed.connect(_onSettlePressed)
	_overlapButton.pressed.connect(_onOverlapPressed)
	_screenshotButton.pressed.connect(_captureOnce.bind(false))
	_scrub.value_changed.connect(_onScrubChanged)


func _onEffectSelected(_index: int) -> void:
	_disposeAllPlaybacks()
	_rebuildLayerToggles([])
	_playbackState = _STATE_STOPPED
	_pauseButton.disabled = true
	_scrub.set_value_no_signal(0.0)
	_updateStatus()


func _onElementSelected(_index: int) -> void:
	_updateStatus()


func _onModeToggled(_enabled: bool) -> void:
	_updateModeToggleText()
	_updateStatus()


func _onScaleChanged(value: float) -> void:
	if _playbackState == _STATE_PLAYING:
		_setAllPlaybackScales(float(value))
	_updateStatus()


func _onPlayPressed() -> void:
	_disposeAllPlaybacks()
	if not _seedPin.button_pressed:
		_cycleSeed()
	_activeSeed = int(_seedSetting.value)
	_activePlayback = _createSelectedPlayback()
	_applyLayerVisibility(_activePlayback)
	_applyFootprintTo(_activePlayback)
	_activePlayback.set_playback_scale(float(_scaleSetting.value))
	_activeMode = _selectedMode()
	_activePlayback.play(_activeSeed, _activeMode)
	_playbackState = _STATE_PLAYING
	_pauseButton.disabled = false
	_pauseButton.text = "Pause"
	_scrub.set_value_no_signal(0.0)
	_rebuildLayerToggles(_activePlayback.get_layer_names())
	_updateStatus()


func _onPausePressed() -> void:
	if _activePlayback == null or _activePlayback.is_finished():
		return
	if _playbackState == _STATE_PAUSED:
		_setAllPlaybackScales(float(_scaleSetting.value))
		_playbackState = _STATE_PLAYING
		_pauseButton.text = "Pause"
	else:
		_setAllPlaybackScales(0.0)
		_playbackState = _STATE_PAUSED
		_pauseButton.text = "Resume"
	_updateStatus()


func _onSettlePressed() -> void:
	if _activePlayback == null or _activePlayback.is_finished():
		_onPlayPressed()
	_disposeOverlaps()
	_activePlayback.set_playback_scale(0.0)
	_activePlayback.skip_to_settle()
	_playbackState = _STATE_PAUSED
	_pauseButton.disabled = false
	_pauseButton.text = "Resume"
	_scrub.set_value_no_signal(_activePlayback.get_normalized_time())
	_updateStatus()


func _onScrubChanged(value: float) -> void:
	if _syncingScrub or _activePlayback == null:
		return
	_disposeOverlaps()
	_activePlayback.set_playback_scale(0.0)
	_activePlayback.seek_normalized(value)
	if _activePlayback.is_finished():
		_playbackState = _STATE_STOPPED
		_pauseButton.disabled = true
		_pauseButton.text = "Pause"
	else:
		_playbackState = _STATE_PAUSED
		_pauseButton.disabled = false
		_pauseButton.text = "Resume"
	_updateStatus()


func _onOverlapPressed() -> void:
	if not _seedPin.button_pressed:
		_cycleSeed()
	var overlapSeed := int(_seedSetting.value)
	var overlap = _createSelectedPlayback()
	_applyLayerVisibility(overlap)
	_applyFootprintTo(overlap)
	overlap.set_playback_scale(
		0.0 if _playbackState == _STATE_PAUSED else float(_scaleSetting.value)
	)
	overlap.play(overlapSeed, _selectedMode())
	if _playbackState == _STATE_PAUSED:
		overlap.set_playback_scale(0.0)
	_overlapPlaybacks.append(overlap)
	if _activePlayback == null:
		_rebuildLayerToggles(overlap.get_layer_names())
	_updateStatus()


func _createSelectedPlayback():
	var profileId: String = _effectOption.get_item_metadata(_effectOption.selected)
	var color := BattleMeshFactoryScript.elementColor(
		_elementOption.get_item_metadata(_elementOption.selected)
	)
	return SpellVfxCatalogScript.create(
		profileId,
		_spawnAnchor,
		Vector3.ZERO,
		color
	)


func _selectedMode() -> String:
	return (
		VfxPlaybackScript.MODE_BATTLE
		if _modeToggle.button_pressed
		else VfxPlaybackScript.MODE_REFERENCE
	)


func _updateModeToggleText() -> void:
	_modeToggle.text = "Battle speed" if _modeToggle.button_pressed else "Reference speed"


func _cycleSeed() -> void:
	var nextSeed := int(_seedSetting.value) + 1
	if nextSeed >= 2147483647:
		nextSeed = 1
	_seedSetting.set_value_no_signal(nextSeed)
	_updateStatus()


func _setAllPlaybackScales(scale: float) -> void:
	if _activePlayback != null:
		_activePlayback.set_playback_scale(scale)
	for overlap in _overlapPlaybacks:
		if is_instance_valid(overlap):
			overlap.set_playback_scale(scale)


func _disposeAllPlaybacks() -> void:
	if _activePlayback != null and is_instance_valid(_activePlayback):
		_activePlayback.dispose()
	_activePlayback = null
	_disposeOverlaps()


func _disposeOverlaps() -> void:
	for overlap in _overlapPlaybacks:
		if is_instance_valid(overlap):
			overlap.dispose()
	_overlapPlaybacks.clear()


func _pruneFinishedOverlaps() -> void:
	for index in range(_overlapPlaybacks.size() - 1, -1, -1):
		var overlap = _overlapPlaybacks[index]
		if not is_instance_valid(overlap) or overlap.is_finished():
			if is_instance_valid(overlap):
				overlap.dispose()
			_overlapPlaybacks.remove_at(index)


func _rebuildLayerToggles(layerNames: Array[String]) -> void:
	for child: Node in _layerToggles.get_children():
		child.queue_free()
	for layerName: String in layerNames:
		if not _layerVisibility.has(layerName):
			_layerVisibility[layerName] = true
		var toggle := CheckButton.new()
		toggle.text = layerName.capitalize()
		toggle.button_pressed = bool(_layerVisibility[layerName])
		toggle.toggled.connect(_onLayerToggled.bind(layerName))
		_layerToggles.add_child(toggle)


func _onLayerToggled(visible: bool, layerName: String) -> void:
	_layerVisibility[layerName] = visible
	if _activePlayback != null:
		_activePlayback.set_layer_visible(layerName, visible)
	for overlap in _overlapPlaybacks:
		if is_instance_valid(overlap):
			overlap.set_layer_visible(layerName, visible)
	_updateStatus()


func _applyLayerVisibility(playback) -> void:
	for layerName: String in playback.get_layer_names():
		if not _layerVisibility.has(layerName):
			_layerVisibility[layerName] = true
		playback.set_layer_visible(layerName, bool(_layerVisibility[layerName]))


func _updateStatus() -> void:
	if _effectOption.item_count == 0:
		return
	var elapsed := 0.0
	var total := 0.0
	var normalized := 0.0
	var particles := 0
	var nodes := 0
	var seekExact := true
	if _activePlayback != null and is_instance_valid(_activePlayback):
		elapsed = _activePlayback.get_elapsed_time()
		total = _activePlayback.get_total_duration()
		normalized = _activePlayback.get_normalized_time()
		particles += _activePlayback.get_live_particle_count()
		nodes += _activePlayback.get_live_node_count()
		seekExact = _activePlayback.is_particle_seek_exact()
	for overlap in _overlapPlaybacks:
		if is_instance_valid(overlap):
			particles += overlap.get_live_particle_count()
			nodes += overlap.get_live_node_count()
			seekExact = seekExact and overlap.is_particle_seek_exact()
	var modeLabel := _activeMode if _activePlayback != null else _selectedMode()
	var renderLabel := _resolutionOption.get_item_text(_resolutionOption.selected)
	var captureSuffix := "\n" + _captureMessage if not _captureMessage.is_empty() else ""
	var statusSeed := _activeSeed if _activePlayback != null else int(_seedSetting.value)
	_statusLabel.text = (
		"%s / %s\n%s speed @ %.2fx | t %.2f | %.2f / %.2fs\n" +
		"seed %d | nodes %d | particles %d | overlaps %d | flurry: %s\n" +
		"%s | Retro %s | CRT %s%s"
	) % [
		_effectOption.get_item_text(_effectOption.selected),
		_playbackState,
		modeLabel,
		float(_scaleSetting.value),
		normalized,
		elapsed,
		total,
		statusSeed,
		nodes,
		particles,
		_overlapPlaybacks.size(),
		"exact" if seekExact else "approx",
		renderLabel,
		"ON" if _retroToggle.button_pressed else "OFF",
		"ON" if _crtToggle.button_pressed else "OFF",
		captureSuffix
	]


func _captureAtArgument() -> float:
	var arguments: PackedStringArray = OS.get_cmdline_args()
	arguments.append_array(OS.get_cmdline_user_args())
	for argument: String in arguments:
		if argument.begins_with("--capture-at="):
			var rawValue := argument.trim_prefix("--capture-at=")
			if rawValue.is_valid_float():
				return clampf(rawValue.to_float(), 0.0, 1.0)
			push_warning("Invalid --capture-at value: %s" % rawValue)
	return -1.0


func _runCaptureMode(normalizedTime: float) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("--capture-at requires a rendered display; headless capture is unsupported.")
		get_tree().quit(2)
		return
	_onPlayPressed()
	_activePlayback.set_playback_scale(0.0)
	_activePlayback.seek_normalized(normalizedTime)
	_playbackState = _STATE_PAUSED if normalizedTime < 1.0 else _STATE_STOPPED
	await get_tree().process_frame
	await get_tree().process_frame
	await _captureOnce(true)


func _captureOnce(quitAfter: bool = false) -> void:
	if _captureUsed:
		_captureMessage = "Capture skipped: one capture is allowed per process."
		_updateStatus()
		if quitAfter:
			get_tree().quit(1)
		return
	if DisplayServer.get_name() == "headless":
		_captureMessage = "Capture unavailable: run with a rendered display."
		push_error(_captureMessage)
		_updateStatus()
		if quitAfter:
			get_tree().quit(2)
		return
	_captureUsed = true
	_screenshotButton.disabled = true
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(SCREENSHOT_PATH)
	var absolutePath := ProjectSettings.globalize_path(SCREENSHOT_PATH)
	_captureMessage = (
		"Capture saved: %s" % absolutePath
		if error == OK
		else "Capture failed with error %d" % error
	)
	print("VFX_DEBUG_CAPTURE path=%s error=%d" % [absolutePath, error])
	_updateStatus()
	if quitAfter:
		get_tree().quit(error)


func _configureRenderControls() -> void:
	for optionIndex in range(_RESOLUTION_OPTIONS.size()):
		var option: Dictionary = _RESOLUTION_OPTIONS[optionIndex]
		_resolutionOption.add_item(option["label"])
		_resolutionOption.set_item_metadata(optionIndex, option["size"])
	_resolutionOption.select(0)
	_retroToggle.set_pressed_no_signal(false)
	_crtToggle.set_pressed_no_signal(false)
	_radiusSetting.set_value_no_signal(DEFAULT_FOOTPRINT_RADIUS)
	_resolutionOption.item_selected.connect(_onResolutionSelected)
	_retroToggle.toggled.connect(_onRenderToggleChanged)
	_crtToggle.toggled.connect(_onRenderToggleChanged)
	_radiusSetting.value_changed.connect(_onRadiusChanged)


func _onResolutionSelected(index: int) -> void:
	_retroToggle.set_pressed_no_signal(index != 0)
	_applyRenderControls()


func _onRenderToggleChanged(_enabled: bool) -> void:
	_applyRenderControls()


func _onRadiusChanged(value: float) -> void:
	_footprintRadius = maxi(1, roundi(value))
	_updateFootprintRing()
	_applyFootprintTo(_activePlayback)
	for overlap in _overlapPlaybacks:
		_applyFootprintTo(overlap)
	_updateStatus()


## No-op for playbacks (like the generic aura) that don't expose a footprint.
## The guide always draws the diamond `ShapeCaster.getCircle` shape, which is
## every carrier's shape except `cross`/`line` — see `IceStormEffect._isDiamondShape`.
func _applyFootprintTo(playback) -> void:
	if playback != null and is_instance_valid(playback) and playback.has_method("setFootprint"):
		playback.call("setFootprint", _footprintRadius, 0.0, "circle")


func _applyRenderControls() -> void:
	var selectedSize: Vector2i = _resolutionOption.get_item_metadata(
		_resolutionOption.selected
	)
	retroRenderer.render_size = (
		selectedSize if selectedSize != Vector2i.ZERO else get_window().size
	)
	retroRenderer.retro_enabled = _retroToggle.button_pressed
	retroRenderer.crt_enabled = _crtToggle.button_pressed
	retroRenderer.set_look_parameter(
		retroRenderer.LOOK_RENDER_SCALE,
		retroRenderer.get_look_parameter(retroRenderer.LOOK_RENDER_SCALE),
		false
	)
	_updateStatus()


func _reparentWorldNodes() -> void:
	for worldNode: Node3D in [_camera, $DirectionalLight, $Ground, _spawnAnchor]:
		worldNode.reparent(retroRenderer.world_root, false)


func _configureBattleWorld() -> void:
	var worldEnvironment := WorldEnvironment.new()
	worldEnvironment.name = "WorldEnvironment"
	worldEnvironment.environment = BattleEnvironmentFactoryScript.createBattleEnvironment()
	retroRenderer.world_root.add_child(worldEnvironment)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = REPRESENTATIVE_CAMERA_SIZE
	_camera.position = _spawnAnchor.position + CAMERA_OFFSET
	_camera.look_at(_spawnAnchor.position, Vector3.UP)
	_camera.current = true


func _buildTerrainSamples() -> void:
	var previewTerrain := Node3D.new()
	previewTerrain.name = "TerrainSamples"
	retroRenderer.world_root.add_child(previewTerrain)
	for zIndex in range(3):
		for xIndex in range(3):
			_addTerrainColumn(
				previewTerrain, Vector2i(xIndex - 3, zIndex - 1), 0,
				Color(0.22, 0.58, 0.28)
			)
			_addTerrainColumn(
				previewTerrain, Vector2i(xIndex + 1, zIndex - 1),
				int(_UNEVEN_HEIGHTS[zIndex][xIndex]), Color(0.34, 0.48, 0.68)
			)


func _addTerrainColumn(
		parent: Node3D,
		coord: Vector2i,
		height: int,
		baseColor: Color) -> void:
	var column := Node3D.new()
	column.name = "Terrain_%d_%d" % [coord.x, coord.y]
	column.position = Vector3(coord.x, 0.0, coord.y)
	parent.add_child(column)
	for layerIndex in range(height + 1):
		var depth := height - layerIndex
		var blockColor := baseColor.darkened(minf(float(depth) * 0.08, 0.24))
		var block := BattleMeshFactoryScript.createMesh("terrain_block", blockColor)
		block.name = "Layer_%d" % layerIndex
		block.position.y = float(layerIndex) * BattleMeshFactoryScript.TERRAIN_CELL_SIZE.y
		column.add_child(block)


func _buildDummyUnits() -> void:
	_addDummyUnit(
		"FlatUnit", Vector3(-2.0, _surfaceY(0), 0.0),
		Color(0.18, 0.42, 0.95), Color(0.62, 0.9, 0.95), 0
	)
	_addDummyUnit(
		"UnevenUnit", Vector3(2.0, _surfaceY(2), 0.0),
		Color(0.9, 0.2, 0.16), Color(0.82, 0.45, 0.2), 1
	)


func _addDummyUnit(
		unitName: String,
		position: Vector3,
		teamColor: Color,
		bodyColor: Color,
		ascensionTier: int) -> void:
	var unit := Node3D.new()
	unit.name = unitName
	unit.position = position
	unit.add_child(BattleMeshFactoryScript.createModelBase(teamColor, ascensionTier))
	var body := BattleMeshFactoryScript.createMesh("shape_capsule", bodyColor)
	body.name = "Body"
	body.position.y = BattleMeshFactoryScript.BASE_TOTAL_HEIGHT + 0.4
	unit.add_child(body)
	retroRenderer.world_root.add_child(unit)


func _buildTargetGuides() -> void:
	var targetMarker := BattleMeshFactoryScript.createMesh(
		"cursor", Color(0.2, 0.85, 1.0, 0.8)
	)
	targetMarker.name = "TargetCentreMarker"
	targetMarker.position.y = 0.02
	targetMarker.scale = Vector3(0.22, 0.22, 0.22)
	retroRenderer.world_root.add_child(targetMarker)
	_footprintRing = MeshInstance3D.new()
	_footprintRing.name = "FootprintGuide"
	_footprintRing.position.y = 0.035
	_footprintRing.material_override = BattleMeshFactoryScript.createMaterial(
		Color(0.42, 0.82, 1.0, 0.72), true, 1.0
	)
	retroRenderer.world_root.add_child(_footprintRing)
	_updateFootprintRing()


## A flat diamond band (`|x| + |z| <= radius`, the shape `ShapeCaster.getCircle`
## actually casts, and the shape `IceStormEffect` now renders for it) rather
## than the previous `TorusMesh` circle, which claimed tiles the spell never
## affects. Built double-sided (each triangle added in both windings) so it
## reads correctly regardless of the debug camera's orbit, without depending on
## `BattleMeshFactoryScript.createMaterial`'s cull mode.
func _updateFootprintRing() -> void:
	if _footprintRing == null:
		return
	var inner := maxf(float(_footprintRadius) - 0.045, 0.05)
	var outer := float(_footprintRadius) + 0.045
	var innerPoints := _diamondPoints(inner)
	var outerPoints := _diamondPoints(outer)
	var surfaceTool := SurfaceTool.new()
	surfaceTool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge in range(4):
		var nextEdge := (edge + 1) % 4
		var quad := [innerPoints[edge], outerPoints[edge], outerPoints[nextEdge], innerPoints[nextEdge]]
		for triangle in [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]]:
			surfaceTool.add_vertex(triangle[0])
			surfaceTool.add_vertex(triangle[1])
			surfaceTool.add_vertex(triangle[2])
			surfaceTool.add_vertex(triangle[0])
			surfaceTool.add_vertex(triangle[2])
			surfaceTool.add_vertex(triangle[1])
	_footprintRing.mesh = surfaceTool.commit()


func _diamondPoints(radius: float) -> Array[Vector3]:
	return [
		Vector3(radius, 0.0, 0.0),
		Vector3(0.0, 0.0, radius),
		Vector3(-radius, 0.0, 0.0),
		Vector3(0.0, 0.0, -radius),
	]


func _surfaceY(height: int) -> float:
	return (
		float(height) * BattleMeshFactoryScript.TERRAIN_CELL_SIZE.y
		+ BattleMeshFactoryScript.TERRAIN_CELL_SIZE.y * 0.5
	)
