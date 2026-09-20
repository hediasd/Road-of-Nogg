## Produces and restores JSON-safe deterministic battle state.

class_name BattleStateSerializer

const CURRENT_VERSION := 8
const FIRST_HEX_VERSION := 7
const LEGACY_CURRENT_VERSION := 5
const MIN_SUPPORTED_VERSION := 2
const MAX_JSON_EXACT_INT := 9007199254740991
const LARGE_INT_TAG := "__nogg_int64__"
const HEX_GRID_KIND := "hex_flat"
const HEX_COORDINATE_CONVENTION := "odd_q_offset"
const HEX_RULESET_ID := "hex_side_turn_v1"

const MonsterFactoryScript = preload("res://src/factories/MonsterFactory.gd")
const BattleMapFactoryScript = preload("res://src/factories/BattleMapFactory.gd")
const BattlePartyScript = preload("res://src/entities/BattleParty.gd")


static func serialize(state: BattleState) -> Dictionary:
	return _serialize(state, 0)


## Only the history window that can still affect current combat rules is
## cloned for a one-command forecast. A full replay always uses serialize().
static func serializeForForecast(state: BattleState,
		includeHiddenRNG: bool = true) -> Dictionary:
	var firstRequired := state.history.size()
	for monsterID in state.monsters:
		firstRequired = mini(firstRequired,
			int(state.last_turn_start_index.get(monsterID, 0)))
	return _serialize(state, firstRequired, true, includeHiddenRNG)


## Semantic state for per-operation replay checks. Command outcomes and the
## branch ledger cover history; excluding it keeps fingerprint cost bounded.
static func serializeCore(state: BattleState) -> Dictionary:
	var result := _serialize(state, 0, false)
	result.erase("history")
	result.erase("historyBaseIndex")
	result.erase("lastTurnStartIndex")
	# Brain objects are runtime wiring reconstructed after deserialization;
	# they do not affect resolution of a submitted command.
	for monsterData in (result.get("monsters", {}) as Dictionary).values():
		monsterData.erase("brainClass")
	# The numeric pointers are drive-history dependent, but the damage facts they
	# select affect damage-reversal spells. Fingerprint the sufficient memory.
	var ruleDamageMemory: Dictionary = {}
	for monsterID in state.monsters:
		ruleDamageMemory[str(monsterID)] = _jsonSafe(
			state.get_events_for_actor_since_last_turn(monsterID, "damage"))
	result["ruleDamageMemory"] = ruleDamageMemory
	return normalizeSemanticNumbers(result)


## Godot parses ordinary JSON numbers as floats. For exact integral values in
## JSON's safe range, the type is a transport detail, not a gameplay change.
static func normalizeSemanticNumbers(value):
	if value is Dictionary:
		var normalized: Dictionary = {}
		for key in value:
			normalized[key] = normalizeSemanticNumbers(value[key])
		return normalized
	if value is Array:
		var normalized: Array = []
		for item in value:
			normalized.append(normalizeSemanticNumbers(item))
		return normalized
	if value is float and value >= -MAX_JSON_EXACT_INT and \
		value <= MAX_JSON_EXACT_INT and value == floor(value):
		return int(value)
	return value


static func _serialize(state: BattleState, historyStart: int,
		includeHistory: bool = true, includeHiddenRNG: bool = true) -> Dictionary:
	var isHexSideState := not state.parties.is_empty()
	var data := {
		"version": CURRENT_VERSION if isHexSideState else LEGACY_CURRENT_VERSION,
		"seed": state.battleSeed,
		"rngState": str(state.rng.state) if includeHiddenRNG else "0",
		"nextMonsterID": state.nextMonsterID,
		"mapName": state.mapName,
		"mapRevision": state.mapRevision,
		"boardSize": _vector(state.boardSize),
		"board": _matrix(state.board, state.boardSize),
		"heightBoard": _matrix(state.heightBoard, state.boardSize),
		"terrainBoard": _matrix(state.terrainBoard, state.boardSize),
		"movementCostBoard": _matrix(state.movementCostBoard, state.boardSize),
		"roundCount": state.roundCount,
		"turnCount": state.turnCount,
		"currentMonsterID": state.currentMonsterID,
		"monsterPositions": _positions(state.monsterPositions),
		"teamRosters": _stringKeyedDictionary(state.teamRosters),
		"activeEffects": _stringKeyedDictionary(state.activeEffects),
		"history": _jsonSafe(state.history.slice(historyStart)) if includeHistory else [],
		"historyBaseIndex": state.historyBaseIndex + historyStart,
		"lastTurnStartIndex": _stringKeyedDictionary(
			_adjustedHistoryIndices(state.last_turn_start_index, historyStart)),
		"monsters": _monsters(state.monsters)
	}
	if not isHexSideState:
		return _jsonSafe(data)
	assert(state.battleMap != null, "Hex party state requires a battle map definition.")
	assert(state.gridKind == HEX_GRID_KIND, "Hex party state has the wrong grid kind.")
	assert(state.coordinateConvention == HEX_COORDINATE_CONVENTION,
		"Hex party state has the wrong coordinate convention.")
	assert(state.rulesetID == HEX_RULESET_ID, "Hex party state has the wrong ruleset.")
	data.merge({
		"gridKind": state.gridKind,
		"coordinateConvention": state.coordinateConvention,
		"rulesetID": state.rulesetID,
		"scenarioID": state.scenarioID,
		"scenarioRevision": state.scenarioRevision,
		"scenarioPath": state.scenarioPath,
		"contentFingerprint": state.contentFingerprint,
		"battleMap": state.battleMap.toDictionary(),
		"parties": _parties(state.parties),
		"monsterPartyIDs": _stringKeyedDictionary(state.monsterPartyIDs),
		"teamPartyIDs": _stringKeyedDictionary(state.teamPartyIDs),
		"partyOrder": state.partyOrder.duplicate(),
		"sideOrder": state.sideOrder.duplicate(),
		"pendingSideIDs": state.pendingSideIDs.duplicate(),
		"activeSideID": state.activeSideID,
		"spentUnitIDs": _stringKeyedDictionary(state.spentUnitIDs),
		"pendingUnitTurns": _stringKeyedDictionary(state.pendingUnitTurns),
		"withdrawnPartyIDs": _stringKeyedDictionary(state.withdrawnPartyIDs),
		"withdrawnMonsterIDs": _stringKeyedDictionary(state.withdrawnMonsterIDs),
		"sideTurnCount": state.sideTurnCount,
		"sideTurnPhase": state.sideTurnPhase,
		"battleOutcome": state.battleOutcome,
	})
	return _jsonSafe(data)


static func jsonSafe(value):
	return _jsonSafe(value)


static func restoreJsonSafe(value):
	return _restoreLossless(value)


static func deserialize(data: Dictionary) -> BattleState:
	var compatibilityProblem := compatibilityError(data)
	assert(compatibilityProblem.is_empty(), compatibilityProblem)
	data = restoreJsonSafe(data)
	var version = int(data.get("version", MIN_SUPPORTED_VERSION))
	assert(
		version >= MIN_SUPPORTED_VERSION and version <= CURRENT_VERSION,
		"Unsupported battle state version %d; supported versions are %d-%d." % [
			version, MIN_SUPPORTED_VERSION, CURRENT_VERSION
		]
	)
	assert(version != 6,
		"Hex party-activation state version 6 is retired and cannot be loaded as side-turn state.")
	var state = BattleState.new(int(data.get("seed", 0)))
	var sizeData: Dictionary = data.get("boardSize", {"x": 0, "y": 0})
	var serializedSize := Vector2i(int(sizeData.get("x", 0)), int(sizeData.get("y", 0)))
	if version >= FIRST_HEX_VERSION:
		assert(str(data.get("gridKind", "")) == HEX_GRID_KIND,
			"Unsupported grid kind; use the frozen square reference for square state files.")
		assert(str(data.get("coordinateConvention", "")) == HEX_COORDINATE_CONVENTION,
			"Unsupported coordinate convention.")
		assert(str(data.get("rulesetID", "")) == HEX_RULESET_ID, "Unsupported hex ruleset.")
		var mapResult := BattleMapFactoryScript.fromDictionary(data.get("battleMap", {}))
		assert(mapResult["success"], "Invalid serialized battle map: %s" % mapResult.get("error", ""))
		state.setBattleMap(mapResult["definition"])
		assert(state.boardSize == serializedSize, "Serialized map and board sizes differ.")
	else:
		state.setup_board(serializedSize)
	_restoreMatrix(state.board, data.get("board", []))
	var heightRows: Array = data.get("heightBoard", [])
	if version == 2 and heightRows.is_empty():
		heightRows = _flatMatrix(state.boardSize)
	_validateHeightRows(heightRows, state.boardSize)
	_restoreMatrix(state.heightBoard, heightRows)
	_restoreMatrix(state.terrainBoard, data.get("terrainBoard", []))
	if version >= CURRENT_VERSION:
		var movementRows: Array = data.get("movementCostBoard", [])
		_validateMovementCostRows(movementRows, state.boardSize)
		_restoreMatrix(state.movementCostBoard, movementRows)
	state.mapName = str(data.get("mapName", ""))
	state.mapRevision = int(data.get("mapRevision", 1))

	state.battleSeed = int(data.get("seed", 0))
	state.rng.seed = state.battleSeed
	if version >= CURRENT_VERSION:
		assert(data.get("rngState") is String,
			"Version 8 RNG state must be a lossless decimal string.")
	state.rng.state = int(data.get("rngState", state.rng.state))
	state.nextMonsterID = int(data.get("nextMonsterID", 100))
	state.roundCount = int(data.get("roundCount", 0))
	state.turnCount = int(data.get("turnCount", 0))
	state.currentMonsterID = int(data.get("currentMonsterID", -1))
	state.monsterPositions = _restorePositions(data.get("monsterPositions", {}))
	state.teamRosters = _restoreTeamRosters(data.get("teamRosters", {}))
	state.activeEffects = _restoreIntKeyDictionary(data.get("activeEffects", {}))
	state.last_turn_start_index = _restoreIntValueDictionary(data.get("lastTurnStartIndex", {}))
	state.historyBaseIndex = int(data.get("historyBaseIndex", 0))
	state.history.assign(data.get("history", []).duplicate(true))
	if version >= FIRST_HEX_VERSION:
		state.gridKind = str(data.get("gridKind", ""))
		state.coordinateConvention = str(data.get("coordinateConvention", ""))
		state.rulesetID = str(data.get("rulesetID", ""))
		state.scenarioID = str(data.get("scenarioID", ""))
		state.scenarioRevision = int(data.get("scenarioRevision", 0))
		state.scenarioPath = str(data.get("scenarioPath", ""))
		state.contentFingerprint = str(data.get("contentFingerprint", ""))
		state.parties = _restoreParties(data.get("parties", {}))
		state.monsterPartyIDs = _restoreIntValueDictionary(data.get("monsterPartyIDs", {}))
		state.teamPartyIDs = _restoreTeamRosters(data.get("teamPartyIDs", {}))
		state.partyOrder = _intArray(data.get("partyOrder", []))
		state.sideOrder = _intArray(data.get("sideOrder", []))
		state.pendingSideIDs = _intArray(data.get("pendingSideIDs", []))
		state.activeSideID = int(data.get("activeSideID", -1))
		state.spentUnitIDs = _restoreBoolDictionary(data.get("spentUnitIDs", {}))
		state.pendingUnitTurns = _restorePendingUnitTurns(data.get("pendingUnitTurns", {}))
		state.withdrawnPartyIDs = _restoreBoolDictionary(data.get("withdrawnPartyIDs", {}))
		state.withdrawnMonsterIDs = _restoreBoolDictionary(data.get("withdrawnMonsterIDs", {}))
		state.sideTurnCount = int(data.get("sideTurnCount", 0))
		state.sideTurnPhase = str(data.get("sideTurnPhase", "idle"))
		state.battleOutcome = int(data.get("battleOutcome", -1))

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
		monster.species = str(monsterData.get("species", monster.species))
		monster.ascends_from = str(monsterData.get("ascendsFrom", monster.ascends_from))
		var restoredBars: Dictionary = monsterData.get("resonanceBars", {})
		if not restoredBars.is_empty():
			monster.resonance_bars.clear()
			for element in restoredBars:
				if monster.elements.has(str(element)):
					monster.resonance_bars[str(element)] = clampi(int(restoredBars[element]), 0, 3)
		monster.spell_cooldowns = monsterData.get("spellCooldowns", {}).duplicate(true)
		if version >= CURRENT_VERSION:
			assert(monsterData.has("spellRuntimeSets") and monsterData.has("passiveRuntime"),
				"Version 8 monster is missing runtime abilities.")
			monster.spellSets.clear()
			for setData in monsterData["spellRuntimeSets"]:
				var restoredSet: Array = []
				for spellData in setData:
					var spell = Spell.new({})
					spell.restoreRuntime(spellData)
					restoredSet.append(spell)
				monster.spellSets.append(restoredSet)
			monster.passives.clear()
			for passiveData in monsterData["passiveRuntime"]:
				var passive = PassiveSkill.new({})
				passive.restoreRuntime(passiveData)
				monster.passives.append(passive)
		monster.position = state.monsterPositions.get(monsterID, Vector2i(-1, -1))
		state.monsters[monsterID] = monster

	state.assertValidOccupancy()
	return state


static func compatibilityError(data: Dictionary) -> String:
	var version := int(data.get("version", MIN_SUPPORTED_VERSION))
	if version == FIRST_HEX_VERSION and data.get("rngState") is float:
		return "Hex state version 7 has numeric RNG state with unverifiable disk precision."
	if version >= CURRENT_VERSION and not data.get("rngState") is String:
		return "Hex state version 8 requires decimal-text RNG state."
	return ""


static func _validateHeightRows(rows: Array, size: Vector2i) -> void:
	assert(rows.size() == size.y, "Height board row count does not match board size.")
	for row in rows:
		assert(row is Array and row.size() == size.x, "Height board column count does not match board size.")
		for value in row:
			assert(int(value) >= 0 and int(value) <= 8, "Height values must be between 0 and 8.")


static func _validateMovementCostRows(rows: Array, size: Vector2i) -> void:
	assert(rows.size() == size.y, "Movement-cost row count does not match board size.")
	for row in rows:
		assert(row is Array and row.size() == size.x,
			"Movement-cost column count does not match board size.")
		for value in row:
			assert(int(value) >= 0, "Movement cost cannot be negative.")


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


static func _adjustedHistoryIndices(source: Dictionary, start: int) -> Dictionary:
	var result: Dictionary = {}
	for key in source:
		result[key] = maxi(0, int(source[key]) - start)
	return result


static func _restoreBoolDictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in source:
		if bool(source[key]):
			result[int(key)] = true
	return result


static func _restorePendingUnitTurns(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in source:
		var turn: Dictionary = source[key].duplicate(true)
		turn["origin"] = _vectorFrom(turn.get("origin", {}))
		var path: Array = []
		for step in turn.get("move_path", []):
			path.append(_vectorFrom(step))
		turn["move_path"] = path
		turn["target_pos"] = _vectorFrom(turn.get("target_pos", {}))
		result[int(key)] = turn
	return result


static func _vectorFrom(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Dictionary:
		return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-1, -1)


static func _intArray(source: Array) -> Array[int]:
	var result: Array[int] = []
	for value in source:
		result.append(int(value))
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


static func _parties(parties: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for partyID in parties:
		var party: BattleParty = parties[partyID]
		result[str(partyID)] = {
			"partyID": party.partyID,
			"teamID": party.teamID,
			"commanderID": party.commanderID,
			"controller": party.controller,
			"memberIDs": party.memberIDs.duplicate(),
			"monsterNames": _stringKeyedDictionary(party.monsterNames),
			"memberLevels": _stringKeyedDictionary(party.memberLevels),
			"startingCells": _stringKeyedDictionary(party.startingCells),
			"sourceData": _jsonSafe(party.sourceData),
		}
	return result


static func _restoreParties(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in source:
		var data: Dictionary = source[key]
		var party = BattlePartyScript.new()
		party.partyID = int(data.get("partyID", key))
		party.teamID = int(data.get("teamID", -1))
		party.commanderID = int(data.get("commanderID", -1))
		party.controller = str(data.get("controller", "cpu"))
		party.memberIDs = _intArray(data.get("memberIDs", []))
		party.monsterNames = _restoreStringValueDictionary(data.get("monsterNames", {}))
		party.memberLevels = _restoreIntValueDictionary(data.get("memberLevels", {}))
		party.startingCells = _restorePositions(data.get("startingCells", {}))
		party.sourceData = data.get("sourceData", {}).duplicate(true)
		result[party.partyID] = party
	return result


static func _restoreStringValueDictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in source:
		result[int(key)] = str(source[key])
	return result


static func _stringKeyedDictionary(source: Dictionary) -> Dictionary:
	var result = {}
	for key in source:
		result[str(key)] = _jsonSafe(source[key])
	return result


static func _jsonSafe(value):
	match typeof(value):
		TYPE_INT:
			if value > MAX_JSON_EXACT_INT or value < -MAX_JSON_EXACT_INT:
				return {LARGE_INT_TAG: str(value)}
			return value
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
			if value.size() == 1 and value.has(LARGE_INT_TAG):
				assert(value[LARGE_INT_TAG] is String and
					str(value[LARGE_INT_TAG]).is_valid_int() and
					str(int(value[LARGE_INT_TAG])) == str(value[LARGE_INT_TAG]),
					"Invalid lossless-integer marker in battle data.")
				return value.duplicate()
			var result = {}
			for key in value:
				result[str(key)] = _jsonSafe(value[key])
			return result
		_:
			return value


static func _restoreLossless(value):
	if value is float:
		assert(absf(value) <= float(MAX_JSON_EXACT_INT),
			"JSON number exceeds exact integer range; use a lossless integer marker.")
		return value
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_restoreLossless(item))
		return result
	if value is Dictionary:
		if value.size() == 1 and value.has(LARGE_INT_TAG):
			var textValue := str(value[LARGE_INT_TAG])
			assert(textValue.is_valid_int() and str(int(textValue)) == textValue,
				"Invalid lossless integer in battle snapshot.")
			return int(textValue)
		var result: Dictionary = {}
		for key in value:
			result[key] = _restoreLossless(value[key])
		return result
	return value


static func _vector(value: Vector2i) -> Dictionary:
	return {"x": value.x, "y": value.y}
