class_name MonsterVisualRegistry
extends RefCounted

const VISUAL_PATHS := {
	"Snowzilla": "res://scenes/entities/Monster.tscn"
}


static func instantiateVisual(monsterName: String) -> Node3D:
	var path: String = VISUAL_PATHS.get(monsterName, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var scene = load(path)
	if scene is PackedScene:
		var instance = scene.instantiate()
		if instance is Node3D:
			return instance
		instance.free()
	return null


static func getRegisteredNames() -> Array[String]:
	var names: Array[String] = []
	for monsterName in VISUAL_PATHS:
		names.append(monsterName)
	names.sort()
	return names
