## Standalone world map framing scene, using the shipping ground rig.
##
## Hosts `WorldMap.tscn` inside a `SubViewport` and owns framing, region, and overlay
## policy. The surfaces it drives own their own documentation:
##
## - `WorldMapDebugHud` -- control construction, collapsible sections, status readout.
## - `WorldMapFramingCatalog` -- the named framings and what each one came from.
## - `WorldMapRegionCatalog` -- available regions and their tile dimensions.
##
## The `SubViewport` is not decoration. `render_scale` is a framing key here, and buffer
## pixels per tile is what decides whether the ground is minified enough for its sparkle to
## read as texture; rendering at window resolution and merely reporting a scaled number
## would make the readout describe something that is not on screen. Note this viewport is
## the world map's own and is deliberately NOT `RetroRenderController` -- on the battle side
## a low-resolution buffer is an opt-in retro treatment, here it is part of the framing.
## See `docs/WORLDMAP_DESIGN.md` section 3.
##
## EXTENDING THIS SCENE. Later world-map work -- a road-spline editor, a node-graph
## inspector, an encounter-marker placer -- adds a section rather than editing this file's
## structure. Declare the controls in `WorldMapDebugHud.SECTIONS`' shape, call
## `hud.addSection(section, callable)` from `_buildUi()`, and add the handlers here. Add
## readout rows the same way, via `WorldMapDebugHud.STATUS_ROWS`. Nothing below needs to
## learn what the new tool is for. What is deliberately NOT here is a stub for any of it.
##
## Core shortcuts use letters because project.godot defines no custom input actions and the
## built-in UI owns Enter, Escape, Space and the arrows.
## G tile grid | H hide hud | C copy settings | R reset to the selected preset
##
## Every interactive control is also reachable from the command line, so a validation pass
## is scriptable rather than a sequence of clicks:
##   --preset=<id>       framing preset to open with (default: tile_exact)
##   --region=<id>       region to load (default: the first catalogued region)
##   --tile-grid         start with the 16 px tile grid on
##   --hide-hud          start with the panel hidden, for clean captures
##   --quit-after=<n>    quit after n frames, for bounded probes
## and an override for every framing key, applied over the chosen preset:
##   --pitch= --fov= --height= --units_per_map_pixel= --fog_start= --fog_end=
##   --fog_curve= --fog_color= --void_color= --curvature= --cloud_strength=
##   --cloud_scale= --cloud_speed= --filter_mode= --render_scale= --sprite_mode=

extends Node

const Arguments = preload("res://src/presentation/debug/VfxDebugArguments.gd")
const HudScript = preload("res://src/presentation/debug/WorldMapDebugHud.gd")
const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const FramingCatalog = preload("res://src/presentation/worldmap/WorldMapFramingCatalog.gd")
const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")
const WorldMapScene = preload("res://scenes/WorldMap.tscn")

## Lifted just off the ground so the lines are not z-fighting the plane they describe.
const TILE_GRID_HEIGHT := 0.05
## Beyond this the lattice is denser than the pixels drawing it and reads as a haze rather
## than a grid, which makes it worse than useless for counting.
const TILE_GRID_MAX_LINES := 400

var _hud: WorldMapDebugHud
var _viewport: SubViewport
var _display: TextureRect
var _map: Node3D
var _ground: WorldMapGround
var _camera: WorldMapCameraRig
var _tileGrid: MeshInstance3D

var _regionID := ""
var _regionTiles := Vector2i.ZERO
var _presetID := FramingCatalog.TILE_EXACT
var _framing: Dictionary = {}
var _quitAfter := 0
var _frames := 0


func _ready() -> void:
	_viewport = get_node("World") as SubViewport
	_display = get_node("Display") as TextureRect
	_display.texture = _viewport.get_texture()

	_map = WorldMapScene.instantiate()
	_viewport.add_child(_map)
	_ground = _map.get_node("Ground")
	_camera = _map.get_node("Camera")
	_camera.current = true

	_buildTileGrid()
	_buildUi()

	_presetID = _presetFromArguments()
	_regionID = _regionFromArguments()
	var base := FramingCatalog.framingFor(_presetID)
	_framing = _framingFromArguments(base)
	# A command-line override leaves the framing no longer matching the preset it started
	# from, so it reports Custom for the same reason a control edit does. Without this the
	# readout and the copied settings block would both name a preset that is not in effect.
	if _framing != base:
		_presetID = FramingCatalog.CUSTOM

	_loadRegion(_regionID)
	_hud.setFraming(_framing)
	_selectOption(_hud.presetOption, FramingCatalog.values().find(_presetID))
	_selectOption(_hud.regionOption, RegionCatalog.ids().find(_regionID))
	_hud.tileGridToggle.button_pressed = Arguments.flag("--tile-grid")
	_tileGrid.visible = _hud.tileGridToggle.button_pressed
	if Arguments.flag("--hide-hud"):
		_hud.toggleVisible()

	_quitAfter = Arguments.integer("--quit-after=", 0)
	_applyFraming()


func _process(_delta: float) -> void:
	# The readout is resolution-dependent, and the window can be resized at any time, so it
	# is refreshed per frame rather than only when a control moves.
	_refreshStatus()
	if _quitAfter <= 0:
		return
	_frames += 1
	if _frames >= _quitAfter:
		print(_settingsBlock())
		get_tree().quit()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_G:
			_hud.tileGridToggle.button_pressed = not _hud.tileGridToggle.button_pressed
		KEY_H:
			_hud.toggleVisible()
		KEY_C:
			_copySettings()
		KEY_R:
			_onPresetSelected(FramingCatalog.values().find(_presetID))


func _buildUi() -> void:
	_hud = HudScript.new(get_node("Ui") as CanvasLayer)
	_hud.build(_onFramingEdited)

	for label in FramingCatalog.labels():
		_hud.presetOption.add_item(label)
	for id in RegionCatalog.ids():
		_hud.regionOption.add_item(id)

	_hud.presetOption.item_selected.connect(_onPresetSelected)
	_hud.regionOption.item_selected.connect(_onRegionSelected)
	_hud.tileGridToggle.toggled.connect(func(on: bool) -> void: _tileGrid.visible = on)
	_hud.copyButton.pressed.connect(_copySettings)


func _onPresetSelected(index: int) -> void:
	var ids := FramingCatalog.values()
	if index < 0 or index >= ids.size():
		return
	_presetID = ids[index]
	if _presetID == FramingCatalog.CUSTOM:
		return
	_framing = FramingCatalog.framingFor(_presetID)
	_hud.setFraming(_framing)
	_applyFraming()


func _onRegionSelected(index: int) -> void:
	var ids := RegionCatalog.ids()
	if index < 0 or index >= ids.size():
		return
	_loadRegion(ids[index])
	_applyFraming()


## Any control edit drops the selection to Custom, the same way RenderPresetCatalog's
## CUSTOM entry works: the panel no longer describes the named preset it started from.
func _onFramingEdited() -> void:
	_framing = _hud.readFraming()
	_presetID = FramingCatalog.CUSTOM
	_selectOption(_hud.presetOption, FramingCatalog.values().find(FramingCatalog.CUSTOM))
	_applyFraming()


func _loadRegion(regionID: String) -> void:
	var region := RegionCatalog.loadRegion(regionID)
	if region.is_empty():
		push_warning("WorldMapDebugController: could not load region '%s'" % regionID)
		return
	_regionID = regionID
	_regionTiles = region["tiles"]
	_ground.configure(_regionTiles, region["texture"], _framing)
	_rebuildTileGrid()


func _applyFraming() -> void:
	_ground.applyFraming(_framing)
	_camera.applyFraming(_framing)
	_camera.panTo(
		Vector2(float(_regionTiles.x) * 0.5, float(_regionTiles.y) * 0.5),
		_ground.regionRect()
	)
	_applyRenderScale()


## Sizes the internal buffer from the framing, taking the size the rig itself derived so
## the buffer and the readout can never disagree.
func _applyRenderScale() -> void:
	var window := get_viewport().get_visible_rect().size
	var readout := _camera.framingReadout(Vector2i(window))
	var buffer: Vector2 = readout["buffer_size"]
	var wanted := Vector2i(maxi(int(buffer.x), 2), maxi(int(buffer.y), 2))
	if _viewport.size != wanted:
		_viewport.size = wanted


func _refreshStatus() -> void:
	_applyRenderScale()
	var window := get_viewport().get_visible_rect().size
	var readout := _camera.framingReadout(Vector2i(window))
	var needed: float = readout["region_tiles_needed"]
	var have := _regionTiles.x
	var buffer: Vector2 = readout["buffer_size"]

	_hud.setStatus({
		"preset": _presetLabel(),
		"region": "%s  (%d x %d tiles)" % [_regionID, _regionTiles.x, _regionTiles.y],
		"tiles": "%.1f across the bottom edge" % readout["tiles_across"],
		"density": "%.1f buffer px" % readout["buffer_px_per_tile"],
		"ratio": "1 : %.2f" % readout["near_far_ratio"],
		# The constraint that sizes the art. Flagged rather than merely reported, because
		# the plane edges showing is the visible symptom and it looks like a bug.
		"needed": "%d tiles wide (have %d)%s" % [
			int(needed), have, "   <-- EDGES SHOW" if needed > float(have) else "   ok"
		],
		"depth": "%.1f to %.1f tiles" % [readout["near_depth"], readout["far_depth"]],
		"buffer": "%d x %d" % [int(buffer.x), int(buffer.y)],
		"horizon": (
			"on screen at pitch < fov/2"
			if readout["horizon_on_screen"]
			else "above the frame (matches reference)"
		),
	})


func _presetLabel() -> String:
	var ids := FramingCatalog.values()
	var index := ids.find(_presetID)
	return FramingCatalog.labels()[index] if index >= 0 else _presetID


## The tile lattice is world-space lines at one-unit intervals, because one tile is one
## world unit. It is a separate mesh rather than a shader branch so the ground material
## stays exactly what the game ships. Consequence worth knowing: with curvature above zero
## the ground bends and these lines do not, so the grid is only truthful at k = 0.
func _buildTileGrid() -> void:
	_tileGrid = MeshInstance3D.new()
	_tileGrid.mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.0, 0.24, 0.36, 1.0)
	_tileGrid.material_override = material
	_tileGrid.visible = false
	_map.add_child(_tileGrid)


func _rebuildTileGrid() -> void:
	var mesh := _tileGrid.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if _regionTiles.x + _regionTiles.y > TILE_GRID_MAX_LINES:
		push_warning("WorldMapDebugController: tile grid suppressed, region too large")
		return
	var width := float(_regionTiles.x)
	var height := float(_regionTiles.y)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for x in range(_regionTiles.x + 1):
		mesh.surface_add_vertex(Vector3(float(x), TILE_GRID_HEIGHT, 0.0))
		mesh.surface_add_vertex(Vector3(float(x), TILE_GRID_HEIGHT, height))
	for z in range(_regionTiles.y + 1):
		mesh.surface_add_vertex(Vector3(0.0, TILE_GRID_HEIGHT, float(z)))
		mesh.surface_add_vertex(Vector3(width, TILE_GRID_HEIGHT, float(z)))
	mesh.surface_end()


func _copySettings() -> void:
	var block := _settingsBlock()
	DisplayServer.clipboard_set(block)
	print(block)


## Printed as well as copied, so a headless or `--quit-after` run captures it too. The
## shape is meant to be pasted into WorldMapFramingCatalog or a design note.
func _settingsBlock() -> String:
	var window := get_viewport().get_visible_rect().size
	var readout := _camera.framingReadout(Vector2i(window))
	var lines: Array[String] = []
	lines.append("# World map framing -- preset %s, region %s" % [_presetID, _regionID])
	for key in Uniforms.FRAMING_KEYS:
		lines.append("  %-22s %s" % [key, _framing[key]])
	lines.append("# derived at %d x %d:" % [window.x, window.y])
	lines.append("  %-22s %.2f" % ["tiles_across", readout["tiles_across"]])
	lines.append("  %-22s %.2f" % ["buffer_px_per_tile", readout["buffer_px_per_tile"]])
	lines.append("  %-22s %.3f" % ["near_far_ratio", readout["near_far_ratio"]])
	lines.append("  %-22s %d" % ["region_tiles_needed", int(readout["region_tiles_needed"])])
	return "\n".join(lines)


func _presetFromArguments() -> String:
	var wanted := Arguments.string("--preset=")
	if wanted.is_empty():
		return FramingCatalog.TILE_EXACT
	if not FramingCatalog.has(wanted):
		push_warning("WorldMapDebugController: unknown preset '%s'" % wanted)
		return FramingCatalog.TILE_EXACT
	return wanted


func _regionFromArguments() -> String:
	var ids := RegionCatalog.ids()
	var fallback := ids[0] if ids.size() > 0 else ""
	var wanted := Arguments.string("--region=")
	if wanted.is_empty():
		return fallback
	if not RegionCatalog.has(wanted):
		push_warning("WorldMapDebugController: unknown region '%s'" % wanted)
		return fallback
	return wanted


## Command-line parity for every framing key, applied over the chosen preset. Driven from
## `FRAMING_KEYS` rather than a hand-written flag list, so a key added to the contract gets
## its flag for free instead of silently having no command-line equivalent.
func _framingFromArguments(base: Dictionary) -> Dictionary:
	var framing := base.duplicate(true)
	for key in Uniforms.FRAMING_KEYS:
		var raw := Arguments.string("--%s=" % key)
		if raw.is_empty():
			continue
		var current = framing[key]
		if current is Color:
			framing[key] = Color(raw)
		elif current is int:
			framing[key] = raw.to_int()
		elif current is float:
			framing[key] = raw.to_float()
		else:
			framing[key] = raw
	return framing


func _selectOption(option: OptionButton, index: int) -> void:
	if index >= 0 and index < option.item_count:
		option.selected = index
