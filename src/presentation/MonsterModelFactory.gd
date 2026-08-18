## Builds the visual for one monster: team-coloured plinth, body, materials, and
## the two-element split configuration.
##
## **Extracted because two callers had diverged.** The board built its units one
## way and the turn rail's portrait renderer built its miniatures another, and
## the miniature path silently dropped the two-element half material — so a
## dual-element unit rendered split on the board and mono in its tile. A portrait
## that does not match its unit defeats the point of showing one, and the only
## durable fix is that both come from the same call rather than from two similar
## sequences maintained in parallel.
##
## Returns a container holding `ModelBase` and the body. Callers add whatever is
## specific to them - the board adds a selection collision body and positions the
## container on a tile; the portrait renderer parents it into a viewport.

class_name MonsterModelFactory
extends RefCounted

const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")
const MonsterVisualRegistryScript = preload("res://src/presentation/MonsterVisualRegistry.gd")
const MonsterReferencesScript = preload("res://src/factories/MonsterReferences.gd")

## Fallback body tint when a monster declares no elements at all.
const NEUTRAL_BODY := Color(0.6, 0.6, 0.6)


static func build(monsterName: String, teamColor: Color, elements: Array) -> Node3D:
	var container := Node3D.new()
	var tier: int = MonsterReferencesScript.ascensionTier(monsterName)
	container.add_child(BattleMeshFactoryScript.createModelBase(teamColor, tier))

	var material := bodyMaterial(elements)
	var body := MonsterVisualRegistryScript.instantiateVisual(monsterName)
	if body == null:
		body = buildPlaceholderBody(material)
	container.add_child(body)
	BattleMeshFactoryScript.prepareNodeMaterials(body)
	applySplitBounds(body, elements)
	return container


## A half material for two or more elements, a flat one for a single element.
## Only the first two elements colour the body; a third is carried by the docked
## status window's element cells, not by the model.
static func bodyMaterial(elements: Array) -> Material:
	if elements.size() >= 2:
		return BattleMeshFactoryScript.createHalfMaterial(
			BattleMeshFactoryScript.elementColor(str(elements[0])),
			BattleMeshFactoryScript.elementColor(str(elements[1]))
		)
	if elements.size() == 1:
		return BattleMeshFactoryScript.createMaterial(
			BattleMeshFactoryScript.elementColor(str(elements[0]))
		)
	return BattleMeshFactoryScript.createMaterial(NEUTRAL_BODY)


## The split shader needs the body's own bounds to know where to divide it, so
## this must run after `prepareNodeMaterials` has assigned the materials.
static func applySplitBounds(body: Node3D, elements: Array) -> void:
	if elements.size() < 2:
		return
	var accumulated := {"has_bounds": false, "bounds": AABB()}
	accumulateVisualBounds(body, Transform3D.IDENTITY, accumulated)
	if accumulated["has_bounds"]:
		BattleMeshFactoryScript.configureSplitBounds(body, accumulated["bounds"])


static func accumulateVisualBounds(
		node: Node,
		fromContainer: Transform3D,
		accumulated: Dictionary) -> void:
	for child in node.get_children():
		var childNode := child as Node3D
		if childNode == null:
			continue
		var childTransform := fromContainer * childNode.transform
		var meshInstance := childNode as MeshInstance3D
		if meshInstance != null and meshInstance.mesh != null:
			var childBounds: AABB = childTransform * meshInstance.get_aabb()
			if accumulated["has_bounds"]:
				accumulated["bounds"] = accumulated["bounds"].merge(childBounds)
			else:
				accumulated["bounds"] = childBounds
				accumulated["has_bounds"] = true
		accumulateVisualBounds(childNode, childTransform, accumulated)


## The stand-in every monster currently uses, because
## `MonsterVisualRegistry.VISUAL_PATHS` is still empty. Lives here rather than in
## either caller so both get the same silhouette.
static func buildPlaceholderBody(material: Material) -> Node3D:
	var body := Node3D.new()
	_addCoin(body, material, 0.2, 0.3, 0.35, 0.3)
	_addCoin(body, material, 0.05, 0.31, 0.31, 0.425)
	_addCoin(body, material, 0.6, 0.1, 0.25, 0.75)
	_addCoin(body, material, 0.05, 0.2, 0.2, 1.075)
	var head := BattleMeshFactoryScript.createMesh("shape_sphere", Color.WHITE)
	# `createMesh` hands back a 0.4-radius sphere. Left at that default the head
	# renders at twice its intended size and the figure reads as all head and no
	# body - which is exactly what it did in the turn rail before this was caught.
	head.mesh.radius = 0.2
	head.mesh.height = 0.4
	head.position.y = 1.3
	head.material_override = material
	body.add_child(head)
	return body


static func _addCoin(
		body: Node3D,
		material: Material,
		height: float,
		topRadius: float,
		bottomRadius: float,
		y: float) -> void:
	var coin := BattleMeshFactoryScript.createMesh("shape_coin", Color.WHITE)
	coin.mesh.height = height
	coin.mesh.top_radius = topRadius
	coin.mesh.bottom_radius = bottomRadius
	coin.position.y = y
	coin.material_override = material
	body.add_child(coin)
