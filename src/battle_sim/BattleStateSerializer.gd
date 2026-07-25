## Produces and restores JSON-safe deterministic battle state.

class_name BattleStateSerializer

const MonsterFactoryScript = preload("res://src/factories/MonsterFactory.gd")


static func serialize(state: BattleState) -> Dictionary:
	return {
		"version": 2,
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
		"activeEffects": _stringKeyedDictionary(state.activeEffects),
		"history": _jsonSafe(state.history),
		"lastTurnStartIndex": _stringKeyedDictionary(state.last_turn_start_index),
		"monsters": _monsters(state.monsters)
	}


static func jsonSafe(value):
	return _jsonSafe(value)


static func deserialize(data: Dictionary) -> BattleState:
	var state = BattleState.new(int(data.get("seed", 0)))
	var sizeData: Dictionary = data.get("boardSize", {"x": 0, "y": 0})
	state.setup_board(Vector2i(int(sizeData.get("x", 0)), int(sizeData.get("y", 0))))
	_restoreMatrix(state.board, data.get("board", []))
	_restoreMatrix(state.heightBoard, data.get("heightBoard", []))
	_restoreMatrix(state.terrainBoard, data.get("terrainBoard", []))

	state.battleSeed = int(data.get("seed", 0))
	state.rng.seed = state.battleSeed
	state.rng.state = int(data.get("rngState", state.rng.state))
	state.nextMonsterID = int(data.get("nextMonsterID", 100))
	state.roundCount = int(data.get("roundCount", 0))
	state.turnCount = int(data.get("turnCount", 0))
	state.currentMonsterID = int(data.get("currentMonsterID", -1))
	state.monsterPositions = _restorePositions(data.get("monsterPositions", {}))
	state.teamRosters = _restoreTeamRosters(data.get("teamRosters", {}))
	state.activeEffects = _restoreIntKeyDictionary(data.get("activeEffects", {}))
	state.last_turn_start_index = _restoreIntValueDictionary(data.get("lastTurnStartIndex", {}))
	state.history.assign(data.get("history", []).duplicate(true))

	state.monsters.clear()
	for key in data.get("monsters", {}):
		var monsterData: Dictionary = data["monsters"][key]
		var monsterID = int(key)
		var monster = MonsterFactoryScript.createMonster(monsterData.get("name", "Defaultgon"), monsterID)
		monster.team = int(monsterData.get("team", 0))
		monster.hitpoints = int(monsterData.get("hitpoints", monster.hitpoints))
		monster.max_hitpoints = int(monsterData.get("max_hitpoints", monster.max_hitpoints))
		monster.move = int(monsterData.get("move", monster.move))
		monster.atk = int(monsterData.get("atk", monster.atk))
		monster.def = int(monsterData.get("def", monster.def))
		monster.speed = int(monsterData.get("speed", monster.speed))
		monster.elements.assign(monsterData.get("elements", []))
		monster.race = monsterData.get("race", monster.race)
		monster.spell_cooldowns = monsterData.get("spellCooldowns", {}).duplicate(true)
		monster.position = state.monsterPositions.get(monsterID, Vector2i(-1, -1))
		state.monsters[monsterID] = monster

	state.assertValidOccupancy()
	return state


static func _restoreMatrix(matrix: Matrix, rows: Array) -> void:
	for y in range(min(rows.size(), matrix.max_y)):
		for x in range(min(rows[y].size(), matrix.max_x)):
			matrix.set_at(int(rows[y][x]), Vector2i(x, y))


static func _restorePositions(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in source:
		var value: Dictionary = source[key]
		result[int(key)] = Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))
	return result


static func _restoreIntKeyDictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in source:
		result[int(key)] = source[key].duplicate(true) if source[key] is Array or source[key] is Dictionary else source[key]
	return result


static func _restoreTeamRosters(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in source:
		var roster: Array[int] = []
		for monsterID in source[key]:
			roster.append(int(monsterID))
		result[int(key)] = roster
	return result


static func _restoreIntValueDictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in source:
		result[int(key)] = int(source[key])
	return result


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
			return {"x": value.x, "y": value.y}
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
	return {"x": value.x, "y": value.y}
