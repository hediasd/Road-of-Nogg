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

const BattleEnvironmentFactoryScript = preload("res://src/presentation/BattleEnvironmentFactory.gd")
const MonsterModelFactoryScript = preload("res://src/presentation/MonsterModelFactory.gd")
const MonsterReferencesScript = preload("res://src/factories/MonsterReferences.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## A three-quarter view at roughly 25 degrees of elevation, yawed about 37
## degrees off axis.
##
## **Deliberately not the battle camera's angle.** Matching it was the first
## approach, on the reasoning that a portrait should read as the same object the
## player sees on the board. But that camera looks down at close to 62 degrees,
## and at portrait size the result is the top of a head and a plinth — almost no
## silhouette. A lower three-quarter view is not merely the more flattering
## choice, it is the more *recognisable* one, because silhouette is what the eye
## identifies a unit by. The yaw exists for the same reason: it shows two faces
## of a model rather than one flat elevation.
const VIEW_DIRECTION := Vector3(0.55, 0.42, 0.72)
const VIEW_DISTANCE := 4.0
## Framed a little above the model's origin, so the body sits low in the square
## and the head lands where the tile's crop wants it.
const LOOK_HEIGHT := 0.72
## Framed so the unit fills the tile without touching its edges. Half way back
## from the tight 1.25 crop, which cut the model off, and half way in from 1.75,
## which left it a distant blob.
const ORTHO_SIZE := 1.5

## Frustum offsets that push the model to the lower-right of its square.
##
## **The offset has to happen here, not in the tile.** Anchoring the rendered
## square to the tile's corner does not move the model, because the model is
## centred inside that square — the first attempt did exactly that and the unit
## still read as centred. Shifting the camera's view window is what actually
## moves the subject within the image.
##
## Signs are inverted relative to the result: a positive `h_offset` moves the
## view window right, which moves the subject left. In world units against
## `ORTHO_SIZE`.
const FRAME_OFFSET := Vector2(-0.42, 0.08)

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
	camera.h_offset = FRAME_OFFSET.x
	camera.v_offset = FRAME_OFFSET.y

	viewport.add_child(_build_model(monsterName, team))
	return viewport.get_texture()


## Built through `MonsterModelFactory`, the same call the board uses, so a
## portrait cannot drift from the unit it depicts. Two-element units get their
## half material and split bounds here exactly as they do on the board — an
## earlier version of this file built its own single-colour body and silently
## dropped the second element.
func _build_model(monsterName: String, team: int) -> Node3D:
	var reference: Dictionary = MonsterReferencesScript.getReference(monsterName)
	var elements = reference.get("ELEMENTS", [])
	return MonsterModelFactoryScript.build(
		monsterName,
		NoggThemeScript.team_color(team),
		elements if elements is Array else []
	)


func clear() -> void:
	_cache.clear()
	if is_instance_valid(_root):
		_root.queue_free()
