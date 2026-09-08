## Typed, headless tactical map definition for a flat-top hex battle.

class_name BattleMapDefinition
extends RefCounted

var formatVersion: int = 1
var mapID: String = ""
var revision: int = 1
var gridKind: String = "hex_flat"
var coordinateConvention: String = "odd_q_offset"
var boardSize: Vector2i = Vector2i.ZERO
var visualScenePath: String = ""
var sourceID: String = ""
var sourceRevision: int = 1
var sourceFingerprint: String = ""
var headlessOnly: bool = false
var cellWidth: float = 2.0
var cellHeight: float = 2.0
var heightStep: float = 0.5
var terrainDefinitions: Dictionary = {}
var sourceData: Dictionary = {}

var _validCells: Array[Vector2i] = []
var _validCellLookup: Dictionary = {}
var _cellData: Dictionary = {}


func configureCells(cells: Array[Vector2i], cellData: Dictionary) -> void:
	_validCells = cells.duplicate()
	_validCellLookup.clear()
	for cell: Vector2i in _validCells:
		_validCellLookup[cell] = true
	_cellData = cellData.duplicate(true)


func validCells() -> Array[Vector2i]:
	return _validCells.duplicate()


func containsCell(cell: Vector2i) -> bool:
	return _validCellLookup.has(cell)


func heightAt(cell: Vector2i) -> int:
	if not containsCell(cell):
		return -1
	return int((_cellData[cell] as Dictionary).get("height", 0))


func terrainAt(cell: Vector2i) -> String:
	if not containsCell(cell):
		return ""
	return str((_cellData[cell] as Dictionary).get("terrain", ""))


func terrainDefinitionAt(cell: Vector2i) -> Dictionary:
	return terrainDefinitions.get(terrainAt(cell), {}).duplicate(true)


func movementCostAt(cell: Vector2i) -> int:
	if not containsCell(cell):
		return 0
	var data: Dictionary = _cellData[cell]
	if data.has("movement_cost"):
		return int(data["movement_cost"])
	return int(terrainDefinitions.get(terrainAt(cell), {}).get("movement_cost", 0))


func isTraversable(cell: Vector2i) -> bool:
	return bool(terrainDefinitions.get(terrainAt(cell), {}).get("traversable", false))


func isStoppable(cell: Vector2i) -> bool:
	return bool(terrainDefinitions.get(terrainAt(cell), {}).get("stoppable", false))


func blocksLineOfSight(cell: Vector2i) -> bool:
	return bool(terrainDefinitions.get(terrainAt(cell), {}).get("blocks_los", false))


func terrainStateCodeAt(cell: Vector2i) -> int:
	return int(terrainDefinitions.get(terrainAt(cell), {}).get("state_code", 0))


func toDictionary() -> Dictionary:
	return sourceData.duplicate(true)
