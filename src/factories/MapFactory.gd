class_name MapFactory

const _MapReferences = preload("res://src/factories/MapReferences.gd")
const _Map = preload("res://src/entities/Map.gd")
const MIN_HEIGHT := 0
const MAX_HEIGHT := 8


static func createMap(name: String):
	var ref = _MapReferences.getReference(name)
	var validation = validateReference(ref)
	assert(validation["success"], "Invalid map reference %s: %s" % [name, validation.get("reason", "unknown")])
	var map = _Map.new()
	map.name = ref["NAME"]
	map.revision = int(ref.get("REVISION", 1))
	map.boardSize = ref.get("SIZE", Vector2i(8, 8))
	map.layout = ref.get("LAYOUT", []).duplicate()
	map.heights = ref.get("HEIGHTS", _flatHeights(map.boardSize)).duplicate(true)
	return map


static func validateReference(ref: Dictionary) -> Dictionary:
	var size: Vector2i = ref.get("SIZE", Vector2i.ZERO)
	if size.x <= 0 or size.y <= 0:
		return {"success": false, "reason": "invalid_size"}
	var layout: Array = ref.get("LAYOUT", [])
	if layout.size() != size.y:
		return {"success": false, "reason": "layout_height_mismatch"}
	for rowValue in layout:
		if not rowValue is String or rowValue.length() != size.x:
			return {"success": false, "reason": "layout_width_mismatch"}
	var heights: Array = ref.get("HEIGHTS", _flatHeights(size))
	if heights.size() != size.y:
		return {"success": false, "reason": "height_row_count_mismatch"}
	for row in heights:
		if not row is Array or row.size() != size.x:
			return {"success": false, "reason": "height_column_count_mismatch"}
		for value in row:
			if not value is int or value < MIN_HEIGHT or value > MAX_HEIGHT:
				return {"success": false, "reason": "invalid_height"}
	if int(ref.get("REVISION", 1)) < 1:
		return {"success": false, "reason": "invalid_revision"}
	var deployment = ref.get("TEAM_1_SLOTS", []) + ref.get("TEAM_2_SLOTS", [])
	if not deployment.is_empty() and not _deploymentReachable(
		deployment, layout, heights, size
	):
		return {"success": false, "reason": "unreachable_deployment"}
	return {"success": true}


static func _deploymentReachable(
		slots: Array,
		layout: Array,
		heights: Array,
		size: Vector2i) -> bool:
	var unique: Dictionary = {}
	for slot in slots:
		if not slot is Vector2i:
			return false
		if slot.x < 0 or slot.y < 0 or slot.x >= size.x or slot.y >= size.y:
			return false
		if layout[slot.y][slot.x] != "." or unique.has(slot):
			return false
		unique[slot] = true
	var start: Vector2i = slots[0]
	var visited: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	var directions = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	while not frontier.is_empty():
		var current = frontier.pop_front()
		for direction in directions:
			var next = current + direction
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
				continue
			if visited.has(next) or layout[next.y][next.x] != ".":
				continue
			if abs(int(heights[next.y][next.x]) - int(heights[current.y][current.x])) > 1:
				continue
			visited[next] = true
			frontier.append(next)
	for slot in slots:
		if not visited.has(slot):
			return false
	return true

static func applyMapToState(map: Map, state: BattleState) -> void:
	state.mapName = map.name
	state.mapRevision = map.revision
	for y in range(map.boardSize.y):
		var row: String = map.layout[y]
		for x in range(map.boardSize.x):
			var char = row[x]
			var pos = Vector2i(x, y)
			if char == 'T' or char == '#':
				state.terrainBoard.set_at(BattleState.TERRAIN_OBSTACLE, pos)
			elif char == 'W' or char == '~':
				state.terrainBoard.set_at(BattleState.TERRAIN_ABYSS, pos)
			else:
				state.terrainBoard.set_at(BattleState.TERRAIN_CLEAR, pos)
			state.heightBoard.set_at(int(map.heights[y][x]), pos)


static func _flatHeights(size: Vector2i) -> Array:
	var rows: Array = []
	for _y in range(size.y):
		var row: Array = []
		row.resize(size.x)
		row.fill(0)
		rows.append(row)
	return rows