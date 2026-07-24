class_name MapFactory

const _MapReferences = preload("res://src/factories/MapReferences.gd")
const _Map = preload("res://src/entities/Map.gd")

static func createMap(name: String):
	var ref = _MapReferences.getReference(name)
	var map = _Map.new()
	map.name = ref["NAME"]
	map.boardSize = ref.get("SIZE", Vector2i(8, 8))
	map.layout = ref.get("LAYOUT", [])
	return map

static func applyMapToState(map: Map, state: BattleState) -> void:
	# Parse the layout grid and populate the state's terrain board
	for y in range(map.layout.size()):
		var row: String = map.layout[y]
		for x in range(row.length()):
			var char = row[x]
			var pos = Vector2i(x, y)
			
			if not state.withinBounds(pos):
				continue
				
			if char == 'T' or char == '#':
				state.terrainBoard.set_at(BattleState.TERRAIN_OBSTACLE, pos)
			elif char == 'W' or char == '~':
				state.terrainBoard.set_at(BattleState.TERRAIN_ABYSS, pos)
			else:
				# '.' or any other character defaults to clear terrain
				state.terrainBoard.set_at(BattleState.TERRAIN_CLEAR, pos)
