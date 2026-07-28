## Produces and restores JSON-safe deterministic battle state.

class_name BattleStateSerializer

const CURRENT_VERSION := 5
const MIN_SUPPORTED_VERSION := 2

const MonsterFactoryScript = preload("res://src/factories/MonsterFactory.gd")


static func serialize(state: BattleState) -> Dictionary:
	return {
		"version": CURRENT_VERSION,
		"seed": state.battleSeed,
		"rngState": state.rng.state,
		"nextMonsterID": state.nextMonsterID,
		"mapName": state.mapName,
		"mapRevision": state.mapRevision,
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
	var version = int(data.get("version", MIN_SUPPORTED_VERSION))
	assert(
		version >= MIN_SUPPORTED_VERSION and version <= CURRENT_VERSION,
		"Unsupported battle state version %d; supported versions are %d-%d." % [
			version, MIN_SUPPORTED_VERSION, CURRENT_VERSION
		]
	)
	var state = BattleState.new(int(data.get("seed", 0)))
	var sizeData: Dictionary = data.get("boardSize", {"x": 0, "y": 0})
	state.setup_board(Vector2i(int(sizeData.get("x", 0)), int(sizeData.get("y", 0))))
	_restoreMatrix(state.board, data.get("board", []))
	var heightRows: Array = data.get("heightBoard", [])
	if version == 2 and heightRows.is_empty():
		heightRows = _flatMatrix(state.boardSize)
	_validateHeightRows(heightRows, state.boardSize)
	_restoreMatrix(state.heightBoard, heightRows)
	_restoreMatrix(state.terrainBoard, data.get("terrainBoard", []))
	state.mapName = str(data.get("mapName", ""))
	state.mapRevision = int(data.get("mapRevision", 1))

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
		var monster = MonsterFactoryScript.createMonster(
			monsterData.get("name", "Defaultgon"),
			monsterID,
			int(monsterData.get("level", 1))
		)
		monster.team = int(monsterData.get("team", 0))
		monster.hitpoints = int(monsterData.get("hitpoints", monster.hitpoints))
		monster.max_hitpoints = int(monsterData.get("max_hitpoints", monster.max_hitpoints))
		monster.move = int(monsterData.get("move", monster.move))
		monster.atk = int(monsterData.get("atk", monster.atk))
		monster.def = int(monsterData.get("def", monster.def))
		monster.speed = int(monsterData.get("speed", monster.speed))
		monster.luck = maxi(0, int(monsterData.get("luck", monster.luck)))
		monster.level = maxi(1, int(monsterData.get("level", 1)))
		monster.jump = maxi(0, int(monsterData.get("jump", 1)))
		monster.base_hitpoints = int(monsterData.get("base_hitpoints", monster.max_hitpoints))
		monster.base_atk = int(monsterData.get("base_atk", monster.atk))
		monster.base_def = int(monsterData.get("base_def", monster.def))
		monster.hp_growth = maxi(0, int(monsterData.get("hp_growth", 0)))
		monster.atk_growth = maxi(0, int(monsterData.get("atk_growth", 0)))
		monster.def_growth = maxi(0, int(monsterData.get("def_growth", 0)))
		monster.elements.assign(monsterData.get("elements", []))
		monster.race = monsterData.get("race", monster.race)
		monster.family = str(monsterData.get("family", monster.family))
		monster.ascends_from = str(monsterData.get("ascendsFrom", monster.ascends_from))
		var restoredBars: Dictionary = monsterData.get("resonanceBars", {})
		if not restoredBars.is_empty():
			monster.resonance_bars.clear()
			for element in restoredBars:
				if monster.elements.has(str(element)):
					monster.resonance_bars[str(element)] = clampi(int(restoredBars[element]), 0, 3)
		monster.spell_cooldowns = monsterData.get("spellCooldowns", {}).duplicate(true)
		monster.position = state.monsterPositions.get(monsterID, Vector2i(-1, -1))
		state.monsters[monsterID] = monster

	state.assertValidOccupancy()
	return state


static func _validateHeightRows(rows: Array, size: Vector2i) -> void:
	assert(rows.size() == size.y, "Height board row count does not match board size.")
	for row in rows:
		assert(row is Array and row.size() == size.x, "Height board column count does not match board size.")
		for value in row:
			assert(int(value) >= 0 and int(value) <= 8, "Height values must be between 0 and 8.")


static func _flatMatrix(size: Vector2i) -> Array:
	var rows: Array = []
	for _y in range(size.y):
		var row: Array = []
		row.resize(size.x)
		row.fill(0)
		rows.append(row)
	return rows

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
