## Renders and caches a small model miniature per monster, for the turn-order
## rail's portrait tiles.
##
## **One viewport per distinct name, team and ascension tier — not per unit.**
## Two Gigasaurus on the same team share one portrait, because they look
## identical; keying on identity instead would render the same image twice and
## hold two textures for it.
##
## **Each viewport carries its own light and environment.** The battle
## `DirectionalLight3D` lives under `RetroRenderController.world_root` and does
## not reach a separate `SubViewport`, so a portrait viewport without lighting of
## its own renders black. This is the way this feature fails first, and the
## reason the light is built here rather than borrowed.
##
## **Rendered once, then cached.** Eight continuously updating viewports cost
## real frame time; eight one-shot renders cost almost nothing. A portrait only
## changes when the model does, which for a given key it never does.
##
## The portrait is framed square and centred. The bust crop the rail wants —
## head centre-right, base bleeding off the bottom-right corner — is applied by
## the tile when it *draws* this texture, not here. Keeping the 3D setup neutral
## means the crop can be tuned in two dimensions without re-rendering anything.

class_name PortraitRenderer
extends RefCounted

const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")
const BattleEnvironmentFactoryScript = preload("res://src/presentation/BattleEnvironmentFactory.gd")
const MonsterVisualRegistryScript = preload("res://src/presentation/MonsterVisualRegistry.gd")
const MonsterReferencesScript = preload("res://src/factories/MonsterReferences.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## Matches the battle camera's angle, not its position. That camera is
## orthogonal at `(6, 15, 14)` looking at the board centre, so its view direction
## has a y:z ratio of roughly 15:8 — reproduced here so a portrait reads as the
## same object the player sees on the board. A portrait shot from a different
## angle defeats the recognition the rail exists to provide.
const VIEW_DIRECTION := Vector3(0.0, 1.875, 1.0)
const VIEW_DISTANCE := 4.0
## Framed a little above the model's origin, so the body sits low in the square
## and the head lands where the tile's crop wants it.
const LOOK_HEIGHT := 0.64
const ORTHO_SIZE := 1.25

var _root: Node3D
var _cache: Dictionary = {}


func _init(parent: Node) -> void:
	_root = Node3D.new()
	_root.name = "PortraitViewports"
	# The viewports render on demand and are never seen directly; hiding the
	# container keeps its contents out of the battle scene's own camera.
	_root.visible = false
	parent.add_child(_root)


static func key_for(monsterName: String, team: int, tier: int) -> String:
	return "%s|%d|%d" % [monsterName, team, tier]


## The portrait for one monster, rendering it on first request. Returns null only
## if the renderer has been torn down.
func texture_for(monsterName: String, team: int) -> Texture2D:
	if not is_instance_valid(_root):
		return null
	var tier: int = MonsterReferencesScript.ascensionTier(monsterName)
	var key := key_for(monsterName, team, tier)
	if _cache.has(key):
		return _cache[key]
	var texture := _render(monsterName, team, tier)
	_cache[key] = texture
	return texture


func _render(monsterName: String, team: int, tier: int) -> Texture2D:
	var side: int = int(NoggThemeScript.TURN_RAIL_PORTRAIT_PX)
	var viewport := SubViewport.new()
	viewport.name = "Portrait_%s_%d_%d" % [monsterName, team, tier]
	viewport.size = Vector2i(side, side)
	viewport.transparent_bg = true
	viewport.disable_3d = false
	# Rendered exactly once. `UPDATE_ONCE` reverts itself to `UPDATE_DISABLED`
	# after the next frame, so this costs one render for the life of the battle.
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.own_world_3d = true
	_root.add_child(viewport)

	var environment := WorldEnvironment.new()
	var env := BattleEnvironmentFactoryScript.createBattleEnvironment()
	# The battle environment draws the sky canvas as its background; a portrait
	# needs the tile behind it instead, so this one clears to nothing.
	env.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment = env
	viewport.add_child(environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	light.shadow_enabled = false
	light.light_energy = 1.0
	viewport.add_child(light)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ORTHO_SIZE
	var look_at := Vector3(0.0, LOOK_HEIGHT, 0.0)
	camera.position = look_at + VIEW_DIRECTION.normalized() * VIEW_DISTANCE
	viewport.add_child(camera)
	camera.look_at(look_at, Vector3.UP)

	viewport.add_child(_build_model(monsterName, team, tier))
	return viewport.get_texture()


## Built through the same factory calls the board uses, so a portrait cannot
## drift from the unit it depicts. Every monster currently falls back to the
## procedural placeholder body, because `MonsterVisualRegistry.VISUAL_PATHS` is
## still empty — the rail is built ahead of the art deliberately, and improves on
## its own as real models land.
func _build_model(monsterName: String, team: int, tier: int) -> Node3D:
	var container := Node3D.new()
	container.name = "PortraitModel"
	container.add_child(
		BattleMeshFactoryScript.createModelBase(NoggThemeScript.team_color(team), tier)
	)
	var body := MonsterVisualRegistryScript.instantiateVisual(monsterName)
	if body == null:
		body = _placeholder_body(monsterName)
	container.add_child(body)
	BattleMeshFactoryScript.prepareNodeMaterials(body)
	return container


## Mirrors `GodotVisualAdapter._buildPlaceholderBody`'s silhouette. Deliberately
## a local copy rather than a call into the adapter: that method is private to a
## class this one must not depend on, and the placeholder is temporary by
## definition. When real visuals land, `instantiateVisual` returns them and this
## stops being reached at all.
func _placeholder_body(monsterName: String) -> Node3D:
	var body := Node3D.new()
	var material := BattleMeshFactoryScript.createMaterial(
		BattleMeshFactoryScript.elementColor(_first_element(monsterName))
	)
	var bulb := BattleMeshFactoryScript.createMesh("shape_coin", Color.WHITE)
	bulb.mesh.height = 0.2
	bulb.mesh.top_radius = 0.3
	bulb.mesh.bottom_radius = 0.35
	bulb.position.y = 0.3
	bulb.material_override = material
	body.add_child(bulb)
	var ring := BattleMeshFactoryScript.createMesh("shape_coin", Color.WHITE)
	ring.mesh.height = 0.05
	ring.mesh.top_radius = 0.31
	ring.mesh.bottom_radius = 0.31
	ring.position.y = 0.425
	ring.material_override = material
	body.add_child(ring)
	var stem := BattleMeshFactoryScript.createMesh("shape_coin", Color.WHITE)
	stem.mesh.height = 0.6
	stem.mesh.top_radius = 0.1
	stem.mesh.bottom_radius = 0.25
	stem.position.y = 0.75
	stem.material_override = material
	body.add_child(stem)
	var head := BattleMeshFactoryScript.createMesh("shape_sphere", Color.WHITE)
	head.position.y = 1.05
	head.material_override = material
	body.add_child(head)
	return body


func _first_element(monsterName: String) -> String:
	var reference: Dictionary = MonsterReferencesScript.getReference(monsterName)
	var elements = reference.get("ELEMENTS", [])
	if elements is Array and not elements.is_empty():
		return str(elements[0])
	return "neutral"


func clear() -> void:
	_cache.clear()
	if is_instance_valid(_root):
		_root.queue_free()
