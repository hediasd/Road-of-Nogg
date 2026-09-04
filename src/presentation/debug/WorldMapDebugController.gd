## Standalone world map framing scene, using the shipping ground rig.
##
## Hosts `WorldMap.tscn` inside a `SubViewport` and owns framing, region, and overlay
## policy. The surfaces it drives own their own documentation:
##
## - `WorldMapDebugHud` -- control construction, collapsible sections, status readout.
## - `WorldMapFramingCatalog` -- the named framings and what each one came from.
## - `WorldMapRegionCatalog` -- available regions and their tile dimensions.
## - `WorldMapSkyCatalog` -- available backdrops.
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
## F recentre the camera on the region | T run/stop the clock
##
## DRAG TO PAN. Hold the left mouse button on the view and drag. Screen pixels are converted
## to world units through the framing itself, so a drag moves the ground under the cursor at
## roughly the cursor's own speed at any zoom. Panning here is deliberately UNCLAMPED, unlike
## the shipping `panTo(focus, rect)` call: a debug tool has to be able to look at the map's
## edge, which is exactly what the clamp exists to prevent. The readout keeps flagging
## `EDGES SHOW`, so the clamp's reason stays visible while its behaviour is suspended.
##
## Every interactive control is also reachable from the command line, so a validation pass
## is scriptable rather than a sequence of clicks:
##   --preset=<id>       framing preset to open with (default: tile_exact)
##   --region=<id>       region to load (default: the catalogue's default region)
##   --tile-grid         start with the 16 px tile grid on
##   --hide-hud          start with the panel hidden, for clean captures
##   --quit-after=<n>    quit after n frames, for bounded probes
## and an override for every framing key, applied over the chosen preset:
##   --pitch= --fov= --height= --fog_start= --fog_end= --fog_curve= --sky=
##   --sky_offset= --sky_scale= --sky_tint= --billboard=
##   --time_of_day= --sun_high= --sun_low= --sun_arc= --sun_reach=
##   --shadow_strength= --shadow_spread= --light_tint=
##   --shadow_edge= --shadow_band= --shadow_color_mode= --shadow_steps=
##   --lamp_mode= --lamp_strength= --lamp_reach= --lamp_levels= --lamp_core= --lamp_dither=
##   --run-clock         start with the day running
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
var _sky: WorldMapSky
var _tileGrid: MeshInstance3D
var _props: WorldMapProps

var _regionID := ""
var _regionTiles := Vector2i.ZERO
var _presetID := FramingCatalog.TILE_EXACT
var _framing: Dictionary = {}
var _quitAfter := 0
var _frames := 0

## Where the camera is looking. Held here rather than recomputed from the region on every
## apply, or a drag would be undone by the next control edit.
var _focus := Vector2.ZERO
var _dragging := false
## Wall-clock driven, so how fast a day passes does not depend on frame rate.
var _clockRunning := false
const DAY_SECONDS := 40.0
var _propCounts := {"count": 0, "houses": 0, "towers": 0}
var _region: Dictionary = {}
var _billboard := Uniforms.BILLBOARD_OFF


func _ready() -> void:
	_viewport = get_node("World") as SubViewport
	_display = get_node("Display") as TextureRect
	_display.texture = _viewport.get_texture()

	_map = WorldMapScene.instantiate()
	_viewport.add_child(_map)
	_ground = _map.get_node("Ground")
	_camera = _map.get_node("Camera")
	_sky = _map.get_node("Camera/Sky")
	_props = _map.get_node("Props")
	_camera.current = true

	_buildTileGrid()
	_buildUi()

	_presetID = _presetFromArguments()
	_regionID = _regionFromArguments()
	# The region is resolved BEFORE the framing, because it owns the fog and void colours.
	# Building the framing first would leave those keys absent, so a --fog_color= override
	# would have nothing to coerce against and the colour pickers would open empty.
	var base := _resolveRegionColours(FramingCatalog.framingFor(_presetID), _regionID)
	_framing = _framingFromArguments(base)
	# --sky= rides the generic per-key override loop, which only coerces types. Without this
	# a typo silently turned the backdrop off while the readout still named it, unlike
	# --preset= and --region= which both warn and fall back.
	var skyID := str(_framing[Uniforms.K_SKY])
	if not WorldMapSkyCatalog.has(skyID):
		push_warning("WorldMapDebugController: unknown sky '%s'" % skyID)
		_framing[Uniforms.K_SKY] = Uniforms.SKY_OFF
	# Same trap as --sky=: the generic override loop only coerces types, so a typo would
	# silently leave the structures flat while the readout named a mode.
	var billboardID := str(_framing[Uniforms.K_BILLBOARD])
	if not Uniforms.BILLBOARD_IDS.has(billboardID):
		push_warning("WorldMapDebugController: unknown billboard mode '%s'" % billboardID)
		_framing[Uniforms.K_BILLBOARD] = Uniforms.BILLBOARD_OFF
	for pair in [
		[Uniforms.K_SHADOW_EDGE, Uniforms.SHADOW_EDGE_IDS, Uniforms.SHADOW_EDGE_HARD],
		[Uniforms.K_SHADOW_COLOR_MODE, Uniforms.SHADOW_COLOR_IDS, Uniforms.SHADOW_COLOR_PALETTE],
	]:
		var value := str(_framing[pair[0]])
		if not (pair[1] as Array).has(value):
			push_warning("WorldMapDebugController: unknown %s '%s'" % [pair[0], value])
			_framing[pair[0]] = pair[2]
	var lampID := str(_framing[Uniforms.K_LAMP_MODE])
	if not Uniforms.LAMP_IDS.has(lampID):
		push_warning("WorldMapDebugController: unknown lamp mode '%s'" % lampID)
		_framing[Uniforms.K_LAMP_MODE] = Uniforms.LAMP_OFF
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

	_clockRunning = Arguments.flag("--run-clock")
	_quitAfter = Arguments.integer("--quit-after=", 0)
	_applyFraming()


func _process(delta: float) -> void:
	if _clockRunning:
		var hour: float = float(_framing[Uniforms.K_TIME_OF_DAY])
		_framing[Uniforms.K_TIME_OF_DAY] = fposmod(hour + delta * (24.0 / DAY_SECONDS), 24.0)
		_hud.setFraming(_framing)
		_applyFraming()
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
		KEY_F:
			_recentre()
		KEY_T:
			_clockRunning = not _clockRunning


## Drag to pan. The conversion is the framing's own: at the frame's centre one screen height
## spans `2 * centre_depth * tan(fov/2)` world units, and the vertical axis is divided by
## sin(pitch) because dragging up the screen moves further across the ground than dragging
## sideways does -- the ground is being seen at an angle. Without that term a diagonal drag
## slides diagonally on screen but not on the map.
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		return
	var motion := event as InputEventMouseMotion
	if motion == null or not _dragging:
		return
	var window := get_viewport().get_visible_rect().size
	if window.y <= 0.0:
		return
	var pitch := deg_to_rad(float(_framing[Uniforms.K_PITCH]))
	var centreDepth := float(_framing[Uniforms.K_HEIGHT]) / tan(pitch)
	var unitsPerPixel := (centreDepth * 2.0 * tan(deg_to_rad(float(_framing[Uniforms.K_FOV])) * 0.5)) / window.y
	_focus.x -= motion.relative.x * unitsPerPixel
	_focus.y -= motion.relative.y * unitsPerPixel / maxf(0.15, sin(pitch))
	_camera.panTo(_focus)


func _recentre() -> void:
	var rect := _ground.regionRect()
	_focus = rect.position + rect.size * 0.5
	_camera.panTo(_focus)


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
	# Switching region adopts that region's fog and void, discarding anything the pickers
	# had set. Predictable beats clever here: a different place looks like itself until you
	# change it again, rather than inheriting the last place's sea colour.
	_framing.erase(Uniforms.K_FOG_COLOR)
	_framing.erase(Uniforms.K_VOID_COLOR)
	_framing = _resolveRegionColours(_framing, ids[index])
	_loadRegion(ids[index])
	_hud.setFraming(_framing)
	_applyFraming()


## Any control edit drops the selection to Custom, the same way RenderPresetCatalog's
## CUSTOM entry works: the panel no longer describes the named preset it started from.
func _onFramingEdited() -> void:
	_framing = _hud.readFraming()
	_presetID = FramingCatalog.CUSTOM
	_selectOption(_hud.presetOption, FramingCatalog.values().find(FramingCatalog.CUSTOM))
	_applyFraming()


## Fills in whichever of the region-owned colours the framing has not named for itself, so
## a preset that specifies a fog colour keeps it and every other preset inherits the place's.
func _resolveRegionColours(framing: Dictionary, regionID: String) -> Dictionary:
	return Uniforms.completeForRegion(
		framing, RegionCatalog.fogColorFor(regionID), RegionCatalog.voidColorFor(regionID)
	)


func _loadRegion(regionID: String) -> void:
	var region := RegionCatalog.loadRegion(regionID)
	if region.is_empty():
		push_warning("WorldMapDebugController: could not load region '%s'" % regionID)
		return
	_regionID = regionID
	_region = region
	_regionTiles = region["tiles"]
	_focus = Vector2(float(_regionTiles.x), float(_regionTiles.y)) * 0.5
	_refreshProps()
	_rebuildTileGrid()


## Rebuilds the structures and hands the resulting ground texture to the ground rig.
##
## Order matters and is the whole reason this is one function. The props pass is what DECIDES
## what the ground texture is: with structures standing, the ground must be the patched copy,
## or every building is drawn twice -- once lying down where it was painted, and once standing
## up next to itself.
func _refreshProps() -> void:
	if _region.is_empty():
		return
	_billboard = str(_framing.get(Uniforms.K_BILLBOARD, Uniforms.BILLBOARD_OFF))
	_propCounts = _props.rebuild(_region["texture"], _regionID, _billboard)
	_ground.configure(
		_regionTiles, _propCounts["ground"], _framing,
		_region["fog_color"], _region["void_color"]
	)


func _applyFraming() -> void:
	# Changing the mode changes the ground TEXTURE, not just a uniform, so it needs the full
	# props pass rather than the cheap per-frame update.
	if str(_framing.get(Uniforms.K_BILLBOARD, Uniforms.BILLBOARD_OFF)) != _billboard:
		_refreshProps()
	_ground.applyFraming(_framing)
	_camera.applyFraming(_framing)
	# After the camera, because the backdrop is sized against its FOV.
	_sky.applyFraming(_framing, _camera, Vector2(get_viewport().get_visible_rect().size))
	# The region rect is in WORLD units. It happens to equal the tile count under the
	# one-tile-one-unit invariant, but going through the rect keeps that in a single place.
	# Unclamped: see the DRAG TO PAN note at the top of this file.
	_camera.panTo(_focus)
	_props.applyFraming(_framing)
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
	# Under the ground outranks folded: both leave the frame empty, but only the first one is
	# the camera having nowhere to stand, and reading "0.63 of the frame" next to a black
	# window is what sent the last search after the clouds instead of after the rig.
	var curve_warning := ""
	if bool(readout["camera_below_ground"]):
		curve_warning = "   <-- CAMERA IS UNDER THE GROUND, FRAME IS EMPTY"
	elif float(readout["curve_fold"]) > 1.0:
		curve_warning = "   <-- CURVE FOLDS THE MAP OUT OF FRAME"

	_hud.setStatus({
		"preset": _presetLabel(),
		"region": "%s  (%d x %d tiles)" % [_regionID, _regionTiles.x, _regionTiles.y],
		"structures": _structureLabel(),
		"tiles": "%.1f across the bottom edge" % readout["tiles_across"],
		"density": "%.1f buffer px" % readout["buffer_px_per_tile"],
		"ratio": "1 : %.2f" % readout["near_far_ratio"],
		# The constraint that sizes the art. Flagged rather than merely reported, because
		# the plane edges showing is the visible symptom and it looks like a bug.
		"needed": "%d tiles wide (have %d)%s" % [
			int(needed), have, "   <-- EDGES SHOW" if needed > float(have) else "   ok"
		],
		"depth": "%.1f to %.1f units" % [readout["near_depth"], readout["far_depth"]],
		# Flagged rather than merely reported, for the same reason EDGES SHOW is: the symptom
		# is the map vanishing, which reads as a bug rather than as a setting.
		"curve": "%.2f of the frame%s" % [readout["curve_fold"], curve_warning],
		"buffer": "%d x %d" % [int(buffer.x), int(buffer.y)],
		"sky": _skyLabel(),
		"horizon": (
			"on screen at pitch < fov/2"
			if readout["horizon_on_screen"]
			else "above the frame (matches reference)"
		),
		"clock": _clockLabel(),
		"sun": _sunLabel(),
		"shadow": _shadowLabel(),
	})


## The two elevations are reported separately on purpose. They are not interchangeable, and a
## readout that showed one number would hide the reason shadows stay legible at 06:05.
func _sunLabel() -> String:
	var sun := WorldMapSun.at(_framing)
	if not bool(sun["up"]):
		return "down"
	return "geometry %.0f deg   light %.0f deg   azimuth %.0f deg" % [
		rad_to_deg(sun["elevation"]), rad_to_deg(sun["lit"]), rad_to_deg(sun["azimuth"])
	]


func _shadowLabel() -> String:
	if float(_framing[Uniforms.K_SHADOW_STRENGTH]) <= 0.0:
		return "off"
	var sun := WorldMapSun.at(_framing)
	if not bool(sun["up"]):
		return "none -- sun is down"
	var step: Vector2 = sun["shadow_step"]
	return "%.2f tiles per tile of height%s   north %.2f" % [
		float(sun["shadow_reach"]), "   (CLAMPED)" if bool(sun["clamped"]) else "", -step.y
	]


func _clockLabel() -> String:
	var night := WorldMapSun.nightAt(WorldMapSun.at(_framing)["lit"])
	return "%s   %s   lamps %.0f%%" % [
		WorldMapSun.clockText(float(_framing[Uniforms.K_TIME_OF_DAY])),
		"running (T)" if _clockRunning else "stopped (T)",
		night * float(_framing[Uniforms.K_LAMP_STRENGTH]) * 100.0
	]


func _structureLabel() -> String:
	var mode := str(_framing.get(Uniforms.K_BILLBOARD, Uniforms.BILLBOARD_OFF))
	if mode == Uniforms.BILLBOARD_OFF:
		return "off (region as painted)"
	var index := Uniforms.BILLBOARD_IDS.find(mode)
	var label: String = Uniforms.BILLBOARD_LABELS[index] if index >= 0 else mode
	return "%s  --  %d up (%d houses, %d towers)" % [
		label, _propCounts["count"], _propCounts["houses"], _propCounts["towers"]
	]


func _skyLabel() -> String:
	var id := str(_framing.get(Uniforms.K_SKY, Uniforms.SKY_OFF))
	var index := WorldMapSkyCatalog.ids().find(id)
	return WorldMapSkyCatalog.labels()[index] if index >= 0 else id


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
	var fallback := RegionCatalog.defaultRegion()
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
