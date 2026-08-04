## Standalone VFX preview using the shipping battle render pipeline and scale.
##
## Controls:
##   Left / Right arrow  -> cycle element
##   Space               -> retrigger the current aura
##
## Run this scene directly with F6 ("Play Current Scene") in the Godot editor.

extends Node3D

const SpellCastAuraScript = preload("res://src/presentation/effects/SpellCastAura.gd")
const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")
const RetroRenderControllerScript = preload("res://src/presentation/RetroRenderController.gd")
const BattleEnvironmentFactoryScript = preload("res://src/presentation/BattleEnvironmentFactory.gd")

const CAMERA_OFFSET := Vector3(6.0, 15.0, 14.0)
## Meadow and Forest are 16 cells across with two elevation steps, producing
## 16 * 0.95 + (2 * 0.5) * 0.35 through the shipping camera-size formula.
const REPRESENTATIVE_CAMERA_SIZE := 15.55
const DEFAULT_FOOTPRINT_RADIUS := 2
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
var _elementIndex: int = 0
var _footprintRadius: int = DEFAULT_FOOTPRINT_RADIUS
var _footprintRing: MeshInstance3D

@onready var _spawnAnchor: Node3D = $SpawnAnchor
@onready var _camera: Camera3D = $Camera3D
@onready var _label: Label = $HUD/PanelContainer/VBoxContainer/StatusLabel
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
	_configureControls()
	BattleMeshFactoryScript.prepareNodeMaterials(retroRenderer.world_root)
	_applyRenderControls()
	_updateLabel()
	_triggerAura()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT:
				_elementIndex = (_elementIndex - 1 + _ELEMENTS.size()) % _ELEMENTS.size()
				_updateLabel()
				_triggerAura()
			KEY_RIGHT:
				_elementIndex = (_elementIndex + 1) % _ELEMENTS.size()
				_updateLabel()
				_triggerAura()
			KEY_SPACE:
				_triggerAura()


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


func _configureControls() -> void:
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
	_updateLabel()


func _applyRenderControls() -> void:
	var selectedSize: Vector2i = _resolutionOption.get_item_metadata(
		_resolutionOption.selected
	)
	retroRenderer.render_size = (
		selectedSize if selectedSize != Vector2i.ZERO else get_window().size
	)
	retroRenderer.retro_enabled = _retroToggle.button_pressed
	retroRenderer.crt_enabled = _crtToggle.button_pressed
	## Reapplying the unchanged scale through the public parameter API refreshes
	## viewport size, display parameters, and every retro material as one recipe.
	retroRenderer.set_look_parameter(
		retroRenderer.LOOK_RENDER_SCALE,
		retroRenderer.get_look_parameter(retroRenderer.LOOK_RENDER_SCALE),
		false
	)
	_updateLabel()


func _updateFootprintRing() -> void:
	if _footprintRing == null:
		return
	var ring := TorusMesh.new()
	ring.inner_radius = maxf(float(_footprintRadius) - 0.045, 0.05)
	ring.outer_radius = float(_footprintRadius) + 0.045
	_footprintRing.mesh = ring


func _surfaceY(height: int) -> float:
	return (
		float(height) * BattleMeshFactoryScript.TERRAIN_CELL_SIZE.y
		+ BattleMeshFactoryScript.TERRAIN_CELL_SIZE.y * 0.5
	)


func _triggerAura() -> void:
	var element: String = _ELEMENTS[_elementIndex]
	var color: Color = BattleMeshFactoryScript.elementColor(element)
	SpellCastAuraScript.spawn(_spawnAnchor, Vector3.ZERO, color)


func _updateLabel() -> void:
	if _label == null or _resolutionOption == null:
		return
	var element: String = _ELEMENTS[_elementIndex]
	var color: Color = BattleMeshFactoryScript.elementColor(element)
	_label.text = (
		"[%d/%d] Element: %s | Radius: %d\n%s | Retro: %s | CRT: %s" % [
			_elementIndex + 1, _ELEMENTS.size(), element.to_upper(),
			_footprintRadius,
			_resolutionOption.get_item_text(_resolutionOption.selected),
			"ON" if _retroToggle.button_pressed else "OFF",
			"ON" if _crtToggle.button_pressed else "OFF"
		]
	)
	_label.modulate = color.lightened(0.2)
