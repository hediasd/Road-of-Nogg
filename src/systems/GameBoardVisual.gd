extends Node

class_name GameBoardVisual

var board
var monsterSpriteList = []
const monsterBase = preload("res://scenes/entities/Monster.tscn")

func _init() -> void:
	pass

func _process(delta: float) -> void:
	pass

func _ready():
		#print(newMonster.transform.global_transform.origin())
	pass

func spawnMonster(newMonster: Monster, referencePos: Vector2i):

	var newMonsterSpriteInstance = monsterBase.instantiate()
	#var offset = Vector3(referencePos[0], 0, referencePos[1])

	#newMonsterSpriteInstance.set_position(offset)
	monsterSpriteList.append(newMonsterSpriteInstance)

	add_child(newMonsterSpriteInstance)

	print(get_child_count(), " " , newMonsterSpriteInstance.is_visible_in_tree())

	pass

func runTurnDecision(runTurnDecision):
	pass
