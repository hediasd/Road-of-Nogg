## Turns an authored document into a reusable gameplay scene: the terrain, and nothing of the
## editor that made it.
##
## WHAT A SHIPPED MAP IS. A `Node3D` carrying region metadata, with one `Ground`
## (`WorldMapGround`) child holding a `PlaneMesh` and a `ShaderMaterial` bound to the committed
## bake. No camera, no sky, no clouds, no HUD, no controller -- a gameplay scene supplies its own
## camera and environment, and this supplies the place. `WorldMapGround` itself is not editor
## code (it is the class the shipping rig already uses), which is what lets the export keep it
## rather than needing a second, parallel ground class that could drift from the previewed one.
##
## ONE BUILDER, SO PREVIEW AND EXPORT CANNOT DRIFT. `configureGround()` is the single definition
## of how a document becomes a ground -- which extent it spans, which texture it samples, which
## fog and void colours it carries. `WorldMapEditorController` calls it to build what you look at
## while authoring, and `buildRuntime()` calls it to build what ships. A map that previews at one
## size and exports at another is exactly the failure that shape rules out.
##
## THE RESOURCE THE EXPORT MUST NOT EMBED, AND WHY IT IS MEASURED RATHER THAN ASSUMED. A
## `ShaderMaterial` parameter pointing at a texture with a real `resource_path` serialises as an
## `ext_resource` -- an external dependency, the committed PNG, one copy. A texture created at
## runtime has no path, and Godot does not fail on it: it silently embeds the entire image as a
## base64 `[sub_resource type="Image"]`. Measured on a 64 x 64 red square: 1,728 bytes with the
## on-disk texture, 67,404 bytes with the runtime one. On a real map that is megabytes of pixels
## duplicated into the scene file, permanently diverging from the PNG the baker maintains and
## updates -- two copies of the same art, one of which nothing keeps current. So `exportScene()`
## REFUSES a texture with no `resource_path` rather than producing a scene that loads fine and is
## quietly wrong, and `probe_scene_export.gd` asserts no `Image` sub-resource ever appears.
##
## GENERATED SCENES ARE NOT BYTE-DETERMINISTIC, WHICH IS WHY THEY ARE NOT TREATED LIKE THE BAKE.
## `ResourceSaver.save()` assigns random id suffixes (`id="1_23d0s"`) on every save, so exporting
## identical content twice produces different bytes -- measured, not assumed. The baked PNG is
## byte-deterministic and is therefore committed and byte-checked (`probe_bake_parity`); an
## exported scene cannot be checked that way, and committing one would show a spurious diff on
## every re-export. See `docs/WORLDMAP_EDITOR.md` section 13 for the wrapper-scene pattern that
## follows from this.

class_name WorldMapSceneExport
extends RefCounted

const Baker = preload("res://src/presentation/worldmap/editor/WorldMapBaker.gd")
const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const ObjectLayer = preload("res://src/presentation/worldmap/editor/WorldMapObjectLayer.gd")
const HeightField = preload("res://src/presentation/worldmap/editor/WorldMapHeightField.gd")
const WaterLayer = preload("res://src/presentation/worldmap/editor/WorldMapWaterLayer.gd")
const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

## Where an exported scene lands. Separated from hand-authored scenes on purpose, the same way
## `WorldMapBaker.GENERATED_DIR` separates baked art from painted art: everything under here is
## regenerated wholesale by an export and nothing in it should ever be edited by hand -- a
## wrapper scene that instances one of these is where hand-authored additions belong.
const GENERATED_DIR := "res://scenes/worldmap/generated"

## Metadata stamped on the exported root. A gameplay scene needs the map's identity and extent
## without having to load the authored source to get them, and `set_meta` survives `pack()` where
## a plain script variable does not (only `@export`ed properties serialise, and `WorldMapGround`
## deliberately exports none of its runtime state).
const META_REGION := "worldmap_region"
const META_LAYOUT := "worldmap_layout"
const META_CELLS := "worldmap_cells"
const META_EXTENT := "worldmap_extent"
const META_SOURCE := "worldmap_source"


static func generatedPathFor(regionName: String) -> String:
	return "%s/%s.tscn" % [GENERATED_DIR, regionName]


## THE one definition of how a document becomes a ground. Both the editor's live preview and the
## exported scene go through this, so the map you look at while authoring and the map that ships
## cannot disagree about extent, texture or the region's own colours.
##
## `worldExtent()` rather than `size_tiles`: on a hex document those are different things --
## columns and rows versus world units -- and getting it wrong ships a differently sized map than
## the one that was authored.
## A sculpted document hands the ground a prebuilt surface -- the hex triangulation with heights
## baked into its vertices -- while a flat one keeps the plane it always had. Both the preview and
## the export come through here, so terrain cannot look one way while authoring and another way
## once shipped.
static func configureGround(
	ground: WorldMapGround, data: WorldMapTileData, texture: Texture2D, framing: Dictionary
) -> void:
	var extent := data.worldExtent()
	var surface: Mesh = null
	if HeightField.has(data):
		var margin: float = float(
			Uniforms.completeForRegion(framing, data.fog_color, data.void_color)[Uniforms.K_FOG_END]
		)
		surface = HeightField.buildSurfaceMesh(data, extent + Vector2(margin, margin) * 2.0)
	ground.configure(extent, texture, framing, data.fog_color, data.void_color, surface)


## Builds the runtime hierarchy, with `owner` set on every node that must survive `pack()` --
## `PackedScene` captures only what the root owns, and a child with no owner is silently dropped
## rather than reported.
static func buildRuntime(
	data: WorldMapTileData, texture: Texture2D, framing: Dictionary
) -> Node3D:
	var mapRoot := Node3D.new()
	mapRoot.name = data.region_name.validate_node_name()

	var ground := WorldMapGround.new()
	ground.name = "Ground"
	# Matching `WorldMap.tscn`'s own Ground: the map is unlit art, so it neither casts shadows
	# nor contributes to global illumination.
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mapRoot.add_child(ground)
	ground.owner = mapRoot
	configureGround(ground, data, texture, framing)
	buildWater(mapRoot, data, mapRoot)
	# The sampler is what makes a building stand ON a hill rather than at zero underneath it, and
	# it is the same `HeightField.sample` the surface mesh was built from -- so an object cannot
	# rest on a surface the renderer does not draw.
	buildObjects(
		mapRoot, data, mapRoot,
		HeightField.samplerFor(data) if HeightField.has(data) else Callable()
	)

	mapRoot.set_meta(META_REGION, data.region_name)
	mapRoot.set_meta(META_LAYOUT, data.layout)
	mapRoot.set_meta(META_CELLS, data.size_tiles)
	mapRoot.set_meta(META_EXTENT, data.worldExtent())
	mapRoot.set_meta(META_SOURCE, MapData.pathFor(data.region_name))
	return mapRoot


## The authored water surface, or nothing at all when the map has no wet cell -- WMH-11. A dry
## map exports exactly what it exported before this item, node for node, which is the shape of
## "water is not a terrain type" at the scene level: a map without water does not carry an empty
## water plane at height zero.
##
## `owner` is set for the same reason every other node here sets it: `PackedScene` captures only
## what the root owns. Pass `null` as `sceneOwner` for a live preview that is never packed.
static func buildWater(parent: Node3D, data: WorldMapTileData, sceneOwner: Node) -> MeshInstance3D:
	var mesh := WaterLayer.buildSurfaceMesh(data)
	if mesh == null:
		return null
	var surface := MeshInstance3D.new()
	surface.name = "Water"
	surface.mesh = mesh
	surface.material_override = WaterLayer.buildMaterial()
	# Matching Ground: the map is unlit art, so water neither casts shadows nor lights anything.
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(surface)
	if sceneOwner != null:
		surface.owner = sceneOwner
	return surface


## Builds a node per placed object under `parent`, named by the object's own id so a gameplay
## scene can find one by the id a quest or a save file references -- `map.get_node("Objects/o003")`
## rather than a search. `owner` is set on everything so `pack()` captures it; pass `null` as
## `sceneOwner` when building for a live preview that is never packed.
##
## UPRIGHT BY DEFAULT. Each object is a `Node3D` positioned by `ObjectLayer.worldPosition`
## and yawed by its facing -- no pitch, no roll. What hangs under that node (a billboarded sprite
## now, a model later) is deliberately not decided here: the POSITION is the contract every
## derived thing reads, and section 9's lesson is that the position must have exactly one
## definition. `WorldMapProps` remains the painted-region extractor and is untouched; this is the
## authored path, where a building is a record rather than pixels to be found again.
static func buildObjects(
	parent: Node3D, data: WorldMapTileData, sceneOwner: Node, sampler := Callable()
) -> Node3D:
	if ObjectLayer.count(data) == 0:
		return null
	var holder := Node3D.new()
	holder.name = "Objects"
	parent.add_child(holder)
	if sceneOwner != null:
		holder.owner = sceneOwner
	for record in ObjectLayer.items(data):
		var entry: Dictionary = record
		var node := Node3D.new()
		node.name = str(entry.get(ObjectLayer.K_ID, "object"))
		node.position = ObjectLayer.worldPosition(data, entry, sampler)
		node.rotation = Vector3(0.0, ObjectLayer.facingRadians(entry), 0.0)
		# The kind rides as metadata rather than as a name suffix, so a lookup by id stays exact
		# and gameplay can ask what a thing IS without parsing its name.
		node.set_meta(ObjectLayer.K_KIND, str(entry.get(ObjectLayer.K_KIND, "")))
		node.set_meta(
			ObjectLayer.K_FOOTPRINT, int(entry.get(ObjectLayer.K_FOOTPRINT, 0))
		)
		var body := _objectBody(entry)
		node.add_child(body)
		holder.add_child(node)
		if sceneOwner != null:
			node.owner = sceneOwner
			body.owner = sceneOwner
	return holder


## A SIMPLE MODEL, which is the half of "upright sprites or simple models" that can be built
## before object art exists. A box footprint-wide and standing on the anchor, unshaded so it is
## visible in a gameplay scene that has not set up lighting yet -- the ground shader is unshaded
## for the same reason.
##
## It is deliberately a placeholder for the LOOK and exact about the PLACEMENT: its base sits on
## `y = 0` in the object's own local space, so it stands on whatever height the record anchored
## to rather than floating at the node's centre. When object art arrives this is the one function
## that changes; nothing downstream reads the box, because everything reads the record.
static func _objectBody(record: Dictionary) -> MeshInstance3D:
	var footprint := int(record.get(ObjectLayer.K_FOOTPRINT, 0))
	# A radius-0 object covers one hex, which is two world units across.
	var across := 2.0 * (1.0 + float(footprint))
	var tall := 3.0 if str(record.get(ObjectLayer.K_KIND, "")) == "tower" else 2.0

	var box := BoxMesh.new()
	box.size = Vector3(across * 0.6, tall, across * 0.6)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = box
	body.position = Vector3(0.0, tall * 0.5, 0.0)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = (
		Color("8d6b94") if str(record.get(ObjectLayer.K_KIND, "")) == "tower"
		else Color("d9a066")
	)
	body.material_override = material
	return body


## Exports `data` to a packed scene. Returns `{ok, path}` on success and `{ok, error}` on any
## failure, so a caller tests one key rather than distinguishing five error paths -- the shape
## `WorldMapRegionCatalog.loadRegion` already uses.
##
## THE BAKE MUST BE COMMITTED AND IMPORTED FIRST, and this refuses rather than working around it.
## The exported material points at the PNG `WorldMapBaker` writes, which means that PNG must be a
## loadable resource: saved to disk AND imported by Godot. A freshly saved map in a running
## editor session has the file but not the import, so `ResourceLoader.exists()` is false and the
## export says so plainly. The alternative -- falling back to a runtime `ImageTexture` -- is
## exactly the silent embedding the class note rules out, so there is no fallback.
static func exportScene(
	data: WorldMapTileData, framing: Dictionary, destination := ""
) -> Dictionary:
	if data == null:
		return {"ok": false, "error": "no document is open"}
	if data.region_name.is_empty():
		return {"ok": false, "error": "the document has no name"}

	var texturePath := Baker.generatedPathFor(data.region_name)
	if not ResourceLoader.exists(texturePath):
		return {
			"ok": false,
			"error": (
				"no importable bake at %s -- save the document, then let Godot import the "
				+ "generated texture before exporting"
			) % texturePath,
		}
	var texture := ResourceLoader.load(texturePath) as Texture2D
	if texture == null:
		return {"ok": false, "error": "could not load the bake at %s" % texturePath}
	if texture.resource_path.is_empty():
		# Cannot happen through the path above, and checked anyway: this is the one condition
		# that turns a correct-looking export into megabytes of embedded base64.
		return {"ok": false, "error": "the bake has no resource path and would embed"}

	var mapRoot := buildRuntime(data, texture, framing)
	var packed := PackedScene.new()
	var packError := packed.pack(mapRoot)
	mapRoot.free()
	if packError != OK:
		return {"ok": false, "error": "pack() failed with error %d" % packError}

	var path := destination if not destination.is_empty() else generatedPathFor(data.region_name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var saveError := ResourceSaver.save(packed, path)
	if saveError != OK:
		return {"ok": false, "error": "could not write %s (error %d)" % [path, saveError]}
	return {"ok": true, "path": path}
