## The clouds standing over the world map: one horizontal quad per cloud, at an altitude.
##
## This node owns geometry and animation. Where the clouds ARE is `WorldMapCloudField`'s answer
## and nothing here second-guesses it; what they look like is `worldmap_cloud.gdshader`'s. What
## is left here is turning map pixels into world units and keeping a clock running.
##
## IT DRIVES ITS OWN CLOCK. The framing is pushed on change, not per frame, so a node that
## waited to be told would only move when a slider did. Owning the clock also keeps the wind
## running while the day is paused, which is what makes the debug scene usable -- the two are
## separate things to look at and coupling them means never seeing either alone.
##
## The quads are built once at capacity and hidden rather than freed, so dragging the count
## slider does not churn nodes and materials every frame.

class_name WorldMapClouds
extends Node3D

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const CloudCatalog = preload("res://src/presentation/worldmap/WorldMapCloudCatalog.gd")
const CloudField = preload("res://src/presentation/worldmap/WorldMapCloudField.gd")
const CLOUD_SHADER = preload("res://assets/shaders/worldmap_cloud.gdshader")

const U_ATLAS := "atlas"
const U_SPRITE_RECT := "sprite_rect"
const U_CLOUD_OPACITY := "cloud_opacity"
const U_LIGHT_TINT := "light_tint"

var _tiles := Vector2i(31, 22)
var _tilePixels := 8
var _setID := Uniforms.CLOUDS_OFF
var _framing := {}
var _field: Array = []
var _clock := 0.0


func _ready() -> void:
	set_process(true)


## Rebuilds the quads for a region and a cloud set. Safe to call again; the quads are only
## rebuilt when the set or the region actually changes.
func configure(tiles: Vector2i, tilePixels: int, framing: Dictionary) -> void:
	var f := Uniforms.complete(framing)
	var wanted := str(f[Uniforms.K_CLOUDS])
	var changed := wanted != _setID or tiles != _tiles or tilePixels != _tilePixels
	_tiles = tiles
	_tilePixels = maxi(1, tilePixels)
	_setID = wanted
	# Before `_rebuild`, not after: the rebuild sizes the lattice from `_config()`, which reads
	# the framing. Leaving it until `applyFraming` builds a field of zero quads on first call
	# and looks exactly like clouds being off.
	_framing = f
	if changed:
		_rebuild()
	applyFraming(framing)


func applyFraming(framing: Dictionary) -> void:
	_framing = Uniforms.complete(framing)
	var setID := str(_framing[Uniforms.K_CLOUDS])
	if setID != _setID:
		_setID = setID
		_rebuild()
	_place()


func _process(delta: float) -> void:
	if _framing.is_empty() or _setID == Uniforms.CLOUDS_OFF:
		return
	if absf(float(_framing[Uniforms.K_WIND_SPEED])) <= 0.0:
		return
	_clock += delta
	_place()


## The field as last placed: one entry per visible cloud, carrying both its own map-pixel
## position and its shadow's. WMC-4's shadow layer reads this rather than recomputing, so the
## two can never disagree about where a cloud is.
func field() -> Array:
	return _field


func visibleCount() -> int:
	return _field.size()


## How many clouds this region and this art can hold without any two overlapping.
func capacity() -> int:
	var config := _config()
	return 0 if config.is_empty() else CloudField.capacity(config)


## The cloud's native size in map pixels, already multiplied by the size setting.
func cloudMapPixels() -> Vector2i:
	if _setID == Uniforms.CLOUDS_OFF or CloudCatalog.pieceCount(_setID) == 0:
		return Vector2i.ZERO
	var scale := maxi(1, int(round(float(_framing.get(Uniforms.K_CLOUD_SIZE, 1.0)))))
	return CloudCatalog.pieceMapPixels(_setID, 0) * scale


func _config() -> Dictionary:
	if _setID == Uniforms.CLOUDS_OFF or _framing.is_empty():
		return {}
	var pieces := CloudCatalog.pieces(_setID)
	if pieces.is_empty():
		return {}
	var scale := maxi(1, int(round(float(_framing[Uniforms.K_CLOUD_SIZE]))))
	# The field is told ONE cloud size and one shadow size, taken from the first piece. The
	# lattice has to be a lattice, so cells cannot vary per cloud; the pieces are the same
	# width and differ only in the shadow's height, which is what the centring absorbs.
	var cloudRect: Rect2i = (pieces[0] as Dictionary)["cloud"]
	var shadowRect: Rect2i = (pieces[0] as Dictionary)["shadow"]
	return {
		CloudField.K_FIELD: Vector2i(_tiles.x * _tilePixels, _tiles.y * _tilePixels),
		CloudField.K_CLOUD: cloudRect.size * scale,
		CloudField.K_SHADOW: shadowRect.size * scale,
		CloudField.K_PIECES: pieces.size(),
		CloudField.K_COUNT: int(round(float(_framing[Uniforms.K_CLOUD_COUNT]))),
		CloudField.K_ALTITUDE: float(_framing[Uniforms.K_CLOUD_ALTITUDE]),
		CloudField.K_WIND_SPEED: float(_framing[Uniforms.K_WIND_SPEED]),
		CloudField.K_WIND_ANGLE: float(_framing[Uniforms.K_WIND_ANGLE]),
		CloudField.K_SEED: int(round(float(_framing[Uniforms.K_CLOUD_SEED]))),
		CloudField.K_PIXELS_PER_UNIT: float(_tilePixels),
	}


func _place() -> void:
	var config := _config()
	if config.is_empty():
		_field = []
		for child in get_children():
			(child as MeshInstance3D).visible = false
		return

	var sun := WorldMapSun.at(_framing)
	_field = CloudField.at(config, sun, _clock)

	var pixelSize := 1.0 / float(_tilePixels)
	var cloudSize: Vector2i = config[CloudField.K_CLOUD]
	var altitude := float(_framing[Uniforms.K_CLOUD_ALTITUDE])
	# The same derivation WorldMapProps uses, from the SAME sun dictionary -- not a second call
	# to tintAt from the clock. A cloud lit to one value while the ground under it is lit to
	# another is the seam the shared sun exists to remove.
	var tint: Color = sun["tint"]
	var amount: float = float(_framing[Uniforms.K_LIGHT_TINT])
	var lightVector := Vector3(
		1.0 + (tint.r - 1.0) * amount,
		1.0 + (tint.g - 1.0) * amount,
		1.0 + (tint.b - 1.0) * amount
	)
	var pieces := CloudCatalog.pieces(_setID)
	var sheet := CloudCatalog.textureFor(_setID)
	var sheetSize := Vector2(1.0, 1.0) if sheet == null else sheet.get_size()

	var children := get_children()
	for i in children.size():
		var quad := children[i] as MeshInstance3D
		if quad == null:
			continue
		if i >= _field.size():
			quad.visible = false
			continue
		var entry: Dictionary = _field[i]
		var topLeft: Vector2i = entry["cloud"]
		var pieceIndex: int = int(entry["piece"])
		var rect: Rect2i = (pieces[pieceIndex % pieces.size()] as Dictionary)["cloud"]

		quad.visible = true
		var mesh := quad.mesh as QuadMesh
		mesh.size = Vector2(float(cloudSize.x), float(cloudSize.y)) * pixelSize
		# The field reports a TOP-LEFT and a quad is centred on its origin, so the half-size
		# goes back on here. Map pixel y is world +Z.
		quad.position = Vector3(
			(float(topLeft.x) + float(cloudSize.x) * 0.5) * pixelSize,
			altitude,
			(float(topLeft.y) + float(cloudSize.y) * 0.5) * pixelSize
		)

		var material := quad.material_override as ShaderMaterial
		material.set_shader_parameter(U_SPRITE_RECT, Vector4(
			float(rect.position.x) / sheetSize.x,
			float(rect.position.y) / sheetSize.y,
			float(rect.size.x) / sheetSize.x,
			float(rect.size.y) / sheetSize.y
		))
		material.set_shader_parameter(U_CLOUD_OPACITY, float(_framing[Uniforms.K_CLOUD_OPACITY]))
		material.set_shader_parameter(U_LIGHT_TINT, lightVector)
		material.set_shader_parameter(Uniforms.U_FOG_START, _framing[Uniforms.K_FOG_START])
		material.set_shader_parameter(Uniforms.U_FOG_END, _framing[Uniforms.K_FOG_END])
		material.set_shader_parameter(Uniforms.U_FOG_CURVE, _framing[Uniforms.K_FOG_CURVE])
		material.set_shader_parameter(
			Uniforms.U_FOG_COLOR, _framing.get(Uniforms.K_FOG_COLOR, Color.WHITE)
		)
		material.set_shader_parameter(Uniforms.U_CURVATURE_K, _framing[Uniforms.K_CURVATURE])
		# Godot culls against the AABB of the MESH, which knows nothing about what a vertex
		# shader does, and this one drops the quad by `k * d^2`. Without the margin clouds wink
		# out at exactly the curvatures they are most visible at. The props carry the same
		# guard for the same reason.
		quad.extra_cull_margin = clampf(
			float(_framing[Uniforms.K_CURVATURE]) * pow(float(_framing[Uniforms.K_FOG_END]) * 2.0, 2.0)
				+ altitude * 2.0,
			0.0, 16384.0
		)


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if _setID == Uniforms.CLOUDS_OFF:
		return
	var sheet := CloudCatalog.textureFor(_setID)
	if sheet == null:
		push_warning("WorldMapClouds: cloud set '%s' has no texture" % _setID)
		return
	# Built at capacity, not at the current count. The count slider then only toggles
	# visibility, which is what keeps dragging it from allocating a material per frame.
	var config := _config()
	var slots: int = 0 if config.is_empty() else CloudField.capacity(config)
	for i in slots:
		var mesh := QuadMesh.new()
		# FACE_Y is the whole geometric claim of this node: a cloud lies FLAT, parallel to the
		# ground, so the camera's own projection foreshortens it exactly as it foreshortens the
		# terrain art. UV v then runs with world +Z, which is the direction map-pixel y runs.
		mesh.orientation = PlaneMesh.FACE_Y
		mesh.size = Vector2.ONE

		var material := ShaderMaterial.new()
		material.shader = CLOUD_SHADER
		material.set_shader_parameter(U_ATLAS, sheet)

		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		instance.visible = false
		add_child(instance)
