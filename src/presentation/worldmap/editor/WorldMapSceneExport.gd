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
static func configureGround(
	ground: WorldMapGround, data: WorldMapTileData, texture: Texture2D, framing: Dictionary
) -> void:
	ground.configure(data.worldExtent(), texture, framing, data.fog_color, data.void_color)


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

	mapRoot.set_meta(META_REGION, data.region_name)
	mapRoot.set_meta(META_LAYOUT, data.layout)
	mapRoot.set_meta(META_CELLS, data.size_tiles)
	mapRoot.set_meta(META_EXTENT, data.worldExtent())
	mapRoot.set_meta(META_SOURCE, MapData.pathFor(data.region_name))
	return mapRoot


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
