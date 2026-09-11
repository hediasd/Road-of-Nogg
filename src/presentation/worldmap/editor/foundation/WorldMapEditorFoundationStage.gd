## Builds the editor's neutral 3D stage without importing the world-map debug rig.
##
## This deliberately owns only a camera and a blank `WorldMapGround`. The debug controller also
## brings regions, a sky, cloud simulation, lights, props and its legacy region picker; those
## are presentation experiments rather than prerequisites for authoring a hex document.

class_name WorldMapEditorFoundationStage
extends RefCounted

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const EditorCamera = preload("res://src/presentation/worldmap/editor/WorldMapEditorCamera.gd")

const EMPTY_TILES := Vector2(2.0, 2.0)
const EMPTY_COLOR := Color("25303a")


static func build(viewport: SubViewport) -> Dictionary:
	var map := Node3D.new()
	map.name = "FoundationMap"
	viewport.add_child(map)

	var framing := Uniforms.DEFAULTS.duplicate(true)
	framing[Uniforms.K_SKY] = Uniforms.SKY_OFF
	framing[Uniforms.K_CLOUDS] = Uniforms.CLOUDS_OFF
	framing[Uniforms.K_LAMP_MODE] = Uniforms.LAMP_OFF
	framing[Uniforms.K_SHADOW_STRENGTH] = 0.0
	framing[Uniforms.K_CURVATURE] = 0.0

	var ground := WorldMapGround.new()
	ground.name = "Ground"
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	map.add_child(ground)
	ground.configure(EMPTY_TILES, _neutralTexture(), framing, EMPTY_COLOR, EMPTY_COLOR)

	var camera: WorldMapEditorCamera = EditorCamera.new()
	camera.name = "Camera"
	camera.current = true
	map.add_child(camera)
	camera.applyFraming(framing)
	camera.rememberRegion(ground.regionRect())

	return {"map": map, "ground": ground, "camera": camera, "framing": framing}


static func _neutralTexture() -> ImageTexture:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, EMPTY_COLOR)
	return ImageTexture.create_from_image(image)
