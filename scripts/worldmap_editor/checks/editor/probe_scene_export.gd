## WMH-6's self-contained validation: an authored map exports to a scene that carries the
## terrain, carries nothing of the editor, and depends on the committed bake as an EXTERNAL
## resource rather than swallowing a copy of it.
##
## THE ASSERTION THAT MATTERS MOST IS THE ONE ABOUT `[sub_resource type="Image"]`. Godot does not
## fail when a material points at a texture with no `resource_path` -- it silently embeds the
## whole image as base64. Measured while writing WMH-6: 1,728 bytes of `.tscn` with the on-disk
## texture, 67,404 with a runtime one, for a 64 x 64 red square. On a real map that is megabytes
## of pixels duplicated into the scene and thereafter diverging from the PNG the baker keeps
## current. A scene like that loads perfectly and is quietly wrong, which is exactly the failure
## a "does it load?" test would pass.
##
## `temp2_authored` is the subject because its bake is committed AND imported, which is what the
## export requires. The refusal path -- a document whose bake Godot has not imported -- is tested
## separately and deliberately, since falling back to a runtime texture there is precisely the
## embedding this file exists to prevent.

extends SceneTree

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const Baker = preload("res://src/presentation/worldmap/editor/WorldMapBaker.gd")
const SceneExport = preload("res://src/presentation/worldmap/editor/WorldMapSceneExport.gd")
const FramingCatalog = preload("res://src/presentation/worldmap/WorldMapFramingCatalog.gd")
const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

const AUTHORED := "temp2_authored"
## Written into the gitignored validation directory, not `scenes/worldmap/generated/`, so a probe
## run never leaves an artifact in the project tree.
const SCRATCH := "user://probe_scratch/worldmap/_probe_export.tscn"

var _failures := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("user://probe_scratch/worldmap")
	_checkExportSucceeds()
	_checkBakeIsAnExternalDependency()
	_checkNoEditorInTheExportedTree()
	_checkTerrainMatchesTheSource()
	_checkMetadataSurvives()
	_checkLoadedSceneSurvivesBeingDrivenOn()
	_checkUnimportedBakeIsRefused()
	_cleanup()

	print("")
	print("probe_scene_export: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	if _failures == 0:
		print("WORLD MAP SCENE EXPORT OK")
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


func _cleanup() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _load() -> WorldMapTileData:
	return MapData.loadFrom(MapData.pathFor(AUTHORED))


func _framing() -> Dictionary:
	return FramingCatalog.framingFor(FramingCatalog.TILE_EXACT)


func _checkExportSucceeds() -> void:
	print("-- an authored map exports --")
	var data := _load()
	if data == null:
		_fail("could not load %s" % AUTHORED)
		return
	var result := SceneExport.exportScene(data, _framing(), SCRATCH)
	if not bool(result.get("ok", false)):
		_fail("export refused: %s" % str(result.get("error", "?")))
		return
	if not FileAccess.file_exists(SCRATCH):
		_fail("export reported success but wrote no file")
		return
	print("  ok    %s exported to %s" % [AUTHORED, SCRATCH])


## The headline check -- see the class note.
func _checkBakeIsAnExternalDependency() -> void:
	print("-- the bake is an external dependency, not an embedded copy --")
	if not FileAccess.file_exists(SCRATCH):
		_fail("no exported scene to inspect")
		return
	var text := FileAccess.get_file_as_string(SCRATCH)
	var bakePath := Baker.generatedPathFor(AUTHORED)
	if text.find('[ext_resource type="Texture2D" path="%s"' % bakePath) < 0:
		_fail("the scene does not reference %s as an ext_resource" % bakePath)
		return
	for embedded in ['[sub_resource type="Image"', '[sub_resource type="ImageTexture"']:
		if text.find(embedded) >= 0:
			_fail("the scene embeds a copy of the art: found %s" % embedded)
			return
	# A blunt ceiling on top of the structural checks: an embedded 240 x 176 image would run to
	# tens of kilobytes of base64, so a scene this small cannot be hiding one.
	if text.length() > 8192:
		_fail("the exported scene is %d bytes, far larger than geometry alone needs" % text.length())
		return
	print("  ok    PNG referenced externally, no Image sub-resource, %d bytes total" % text.length())


## "Nothing of the editor" made checkable: no script from the editor package, and none of the
## node types the editor scene is built from -- a camera, a HUD layer, or any Control.
func _checkNoEditorInTheExportedTree() -> void:
	print("-- the exported tree carries nothing of the editor --")
	var packed := ResourceLoader.load(SCRATCH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		_fail("could not load the exported scene")
		return
	var instance := packed.instantiate()
	var offenders: Array[String] = []
	_walk(instance, offenders)
	if not offenders.is_empty():
		_fail("editor content survived the export: %s" % ", ".join(offenders))
		instance.free()
		return
	instance.free()
	print("  ok    no editor script, camera, canvas layer or control anywhere in the tree")


func _walk(node: Node, offenders: Array[String]) -> void:
	var script: Variant = node.get_script()
	if script != null and str(script.resource_path).find("/worldmap/editor/") >= 0:
		offenders.append("%s has editor script %s" % [node.name, script.resource_path])
	if node is Camera3D or node is CanvasLayer or node is Control:
		offenders.append("%s is a %s" % [node.name, node.get_class()])
	for child in node.get_children():
		_walk(child, offenders)


## The terrain that ships is the terrain that was authored: the same extent the document declares
## (plus the fog margin the ground adds around it), and a material bound to the same bake.
func _checkTerrainMatchesTheSource() -> void:
	print("-- the exported terrain matches the source document --")
	var data := _load()
	var packed := ResourceLoader.load(SCRATCH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var instance := packed.instantiate()
	var ground := instance.get_node_or_null("Ground") as MeshInstance3D
	if ground == null:
		_fail("the exported scene has no Ground")
		instance.free()
		return

	var plane := ground.mesh as PlaneMesh
	if plane == null:
		_fail("Ground carries no PlaneMesh")
		instance.free()
		return
	# Built independently from the document rather than compared against a remembered number, so
	# this stays true if the fog margin rule ever changes.
	var reference := WorldMapGround.new()
	SceneExport.configureGround(reference, data, null, _framing())
	var expected := (reference.mesh as PlaneMesh).size
	reference.free()
	if not plane.size.is_equal_approx(expected):
		_fail("exported plane is %s, a freshly configured one is %s" % [plane.size, expected])
		instance.free()
		return

	var material := ground.material_override as ShaderMaterial
	if material == null:
		_fail("Ground carries no ShaderMaterial")
		instance.free()
		return
	var texture := material.get_shader_parameter(Uniforms.REGION_SAMPLERS[0]) as Texture2D
	if texture == null or texture.resource_path != Baker.generatedPathFor(AUTHORED):
		_fail("the material samples '%s', expected %s" % [
			"null" if texture == null else texture.resource_path, Baker.generatedPathFor(AUTHORED)
		])
		instance.free()
		return
	# Region extent reaches the shader as a uniform, and is what places the art in world space.
	var regionSize = material.get_shader_parameter(Uniforms.U_REGION_SIZE)
	if not (regionSize as Vector2).is_equal_approx(data.worldExtent()):
		_fail("region_size uniform is %s, the document's extent is %s" % [
			regionSize, data.worldExtent()
		])
		instance.free()
		return
	instance.free()
	print("  ok    plane %s, region_size %s, sampling the committed bake" % [plane.size, regionSize])


## `set_meta` rather than script variables, because only `@export`ed properties survive `pack()`
## and `WorldMapGround` exports none of its runtime state on purpose. This is what proves the
## choice actually round-trips.
func _checkMetadataSurvives() -> void:
	print("-- region metadata survives pack and reload --")
	var data := _load()
	var packed := ResourceLoader.load(SCRATCH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var instance := packed.instantiate()
	var expected := {
		SceneExport.META_REGION: data.region_name,
		SceneExport.META_LAYOUT: data.layout,
		SceneExport.META_CELLS: data.size_tiles,
		SceneExport.META_SOURCE: MapData.pathFor(data.region_name),
	}
	for key in expected:
		if not instance.has_meta(key):
			_fail("the exported root lost metadata '%s'" % key)
			instance.free()
			return
		if instance.get_meta(key) != expected[key]:
			_fail("metadata '%s' is %s, expected %s" % [
				key, instance.get_meta(key), expected[key]
			])
			instance.free()
			return
	if not (instance.get_meta(SceneExport.META_EXTENT) as Vector2).is_equal_approx(data.worldExtent()):
		_fail("metadata extent %s does not match %s" % [
			instance.get_meta(SceneExport.META_EXTENT), data.worldExtent()
		])
		instance.free()
		return
	instance.free()
	print("  ok    region, layout, cells, extent and source all round-trip")


## A scene that loads correctly and then breaks the moment a gameplay scene touches it is still a
## broken export. `WorldMapGround._material` is a plain variable and does not survive `pack()`, so
## a loaded map has a deserialised `material_override` and a null cache; `_ensureMaterial()`
## adopts the former rather than replacing it, and this is what proves that holds. Without the
## adopt, one `applyFraming()` -- the ordinary call for a gameplay scene choosing its own fog --
## silently swaps in a blank material and the map loses its texture, extent and colours.
func _checkLoadedSceneSurvivesBeingDrivenOn() -> void:
	print("-- a loaded map survives a gameplay scene driving it --")
	var packed := ResourceLoader.load(SCRATCH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var instance := packed.instantiate()
	var ground := instance.get_node_or_null("Ground") as WorldMapGround
	if ground == null:
		_fail("Ground is not a WorldMapGround in the loaded scene")
		instance.free()
		return
	# Proves the check is not vacuous: the adopt path only runs when the private cache is null,
	# so if a deserialised node somehow arrived WITH one, this check would pass for the wrong
	# reason and go on passing after the adopt was removed again.
	if ground.get("_material") != null:
		_fail("the loaded ground already has a _material cache; this check proves nothing")
		instance.free()
		return
	var before := ground.material_override as ShaderMaterial
	var textureBefore := before.get_shader_parameter(Uniforms.REGION_SAMPLERS[0]) as Texture2D

	ground.applyFraming(FramingCatalog.framingFor(FramingCatalog.CLOSER))

	var after := ground.material_override as ShaderMaterial
	if after != before:
		_fail("applyFraming() replaced the exported material instead of adopting it")
		instance.free()
		return
	var textureAfter := after.get_shader_parameter(Uniforms.REGION_SAMPLERS[0]) as Texture2D
	if textureAfter == null or textureAfter != textureBefore:
		_fail("the map lost its texture when a framing was applied")
		instance.free()
		return
	instance.free()
	print("  ok    applyFraming() kept the exported material and its bake")


## A document whose bake Godot cannot load must be REFUSED, not exported with a runtime texture:
## that fallback is the silent embedding this whole file exists to prevent. Uses a name nothing
## has ever baked, so the condition is genuine rather than simulated.
func _checkUnimportedBakeIsRefused() -> void:
	print("-- a map with no importable bake is refused, not embedded --")
	var data := MapData.create("_probe_export_never_baked", Vector2i(3, 2), MapData.LAYOUT_HEX_FLAT)
	var result := SceneExport.exportScene(data, _framing(), SCRATCH + ".refused")
	if bool(result.get("ok", false)):
		_fail("export succeeded for a map with no bake -- it must refuse instead")
		if FileAccess.file_exists(SCRATCH + ".refused"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH + ".refused"))
		return
	var reason := str(result.get("error", ""))
	if reason.find("no importable bake") < 0:
		_fail("refused for the wrong reason: %s" % reason)
		return
	if FileAccess.file_exists(SCRATCH + ".refused"):
		_fail("a refused export still wrote a file")
		return
	print("  ok    refused, named the bake it wanted, and wrote nothing")
