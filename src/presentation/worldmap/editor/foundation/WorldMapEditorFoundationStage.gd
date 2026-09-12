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

## What surrounds the document once the plane stops at its own edge. The accepted workspace
## sketch's `--bg`, so the 3D stage and the chrome around it are the same surface rather than two
## opinions about what "empty" looks like. Declared on the stage's own `Environment` instead of
## left to the project's default clear colour: the backdrop of an authoring surface is a decision,
## and a global setting changed for some other scene must not silently restyle this one.
const STAGE_BACKDROP := Color("171e23")


static func build(viewport: SubViewport) -> Dictionary:
	var map := Node3D.new()
	map.name = "FoundationMap"
	viewport.add_child(map)

	var backdrop := WorldEnvironment.new()
	backdrop.name = "Backdrop"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = STAGE_BACKDROP
	# Ambient light is left OFF with the rest of the stage's lighting: the ground is unlit art and
	# a coloured background would otherwise tint it.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.BLACK
	environment.ambient_light_energy = 0.0
	backdrop.environment = environment
	map.add_child(backdrop)

	var framing := Uniforms.DEFAULTS.duplicate(true)
	framing[Uniforms.K_SKY] = Uniforms.SKY_OFF
	framing[Uniforms.K_CLOUDS] = Uniforms.CLOUDS_OFF
	framing[Uniforms.K_LAMP_MODE] = Uniforms.LAMP_OFF
	framing[Uniforms.K_SHADOW_STRENGTH] = 0.0
	framing[Uniforms.K_CURVATURE] = 0.0
	# NATIVE RESOLUTION, unlike every shipping framing. The explorer's 0.4 buffer is the retro
	# look; here it is a defect generator. The hex grid is a screen-space-constant 1.25 px line,
	# so at 0.4 it is drawn into a buffer with less than half a pixel of width per line and then
	# nearest-upscaled -- which is what makes a zoomed-out lattice read as dotted rather than
	# thin. An authoring surface is chrome as much as art, and chrome is drawn at the real size.
	framing[Uniforms.K_RENDER_SCALE] = 1.0

	var ground := WorldMapGround.new()
	ground.name = "Ground"
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Set BEFORE the first `configure()`, because it is read while the mesh is sized. This is the
	# only place it is ever set: the plane is then exactly the document's own rectangle, with the
	# editor's backdrop everywhere else instead of a region's sea colour stretched to the horizon.
	ground.authoring_surface = true
	map.add_child(ground)
	ground.configure(EMPTY_TILES, _neutralTexture(), framing, EMPTY_COLOR, EMPTY_COLOR)

	var camera: WorldMapEditorCamera = EditorCamera.new()
	camera.name = "Camera"
	camera.current = true
	map.add_child(camera)
	camera.applyFraming(framing)
	# The foundation is an authoring surface, not a shipping-preview shell. Start in the fixed
	# top-down orthographic mode the chrome names, with no hidden transition through contract view.
	camera.toggleOrtho()
	camera.rememberRegion(ground.regionRect())

	return {"map": map, "ground": ground, "camera": camera, "framing": framing}


static func _neutralTexture() -> ImageTexture:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, EMPTY_COLOR)
	return ImageTexture.create_from_image(image)
