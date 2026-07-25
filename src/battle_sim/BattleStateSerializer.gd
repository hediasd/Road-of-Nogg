## BattleStateSerializer — Produces JSON-safe deterministic battle snapshots.

class_name BattleStateSerializer


static func serialize(state: BattleState) -> Dictionary:
	return {
		"version": 1,
		"seed": state.battleSeed,
		"rngState": state.rng.state,
		"nextMonsterID": state.nextMonsterID,
		"boardSize": _vector(state.boardSize),
		"board": _matrix(state.board, state.boardSize),
		"heightBoard": _matrix(state.heightBoard, state.boardSize),
		"terrainBoard": _matrix(state.terrainBoard, state.boardSize),
		"roundCount": state.roundCount,
		"turnCount": state.turnCount,
		"currentMonsterID": state.currentMonsterID,
		"monsterPositions": _positions(state.monsterPositions),
		"teamRosters": _stringKeyedDictionary(state.teamRosters),
		"activeEffects": _jsonSafe(state.activeEffects),
		"history": _jsonSafe(state.history),
		"lastTurnStartIndex": _stringKeyedDictionary(state.last_turn_start_index),
		"monsters": _monsters(state.monsters)
	}


static func _matrix(matrix: Matrix, size: Vector2i) -> Array:
	var rows = []
	for y in range(size.y):
		var row = []
		for x in range(size.x):
			row.append(matrix.at(Vector2i(x, y)))
		rows.append(row)
	return rows


static func _positions(positions: Dictionary) -> Dictionary:
	var result = {}
	for monsterID in positions:
		result[str(monsterID)] = _vector(positions[monsterID])
	return result


static func _monsters(monsters: Dictionary) -> Dictionary:
	var result = {}
	for monsterID in monsters:
		result[str(monsterID)] = monsters[monsterID].serialize()
	return result


static func _stringKeyedDictionary(source: Dictionary) -> Dictionary:
	var result = {}
	for key in source:
		result[str(key)] = _jsonSafe(source[key])
	return result


static func _jsonSafe(value):
	match typeof(value):
		TYPE_VECTOR2I:
			return _vector(value)
		TYPE_VECTOR2:
			return { "x": value.x, "y": value.y }
		TYPE_ARRAY:
			var result = []
			for item in value:
				result.append(_jsonSafe(item))
			return result
		TYPE_DICTIONARY:
			var result = {}
			for key in value:
				result[str(key)] = _jsonSafe(value[key])
			return result
		_:
			return value


static func _vector(value: Vector2i) -> Dictionary:
	return { "x": value.x, "y": value.y }
