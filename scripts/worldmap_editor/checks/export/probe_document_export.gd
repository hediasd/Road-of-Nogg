extends SceneTree

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const FileDocument = preload("res://src/presentation/worldmap/editor/document/WorldMapFileDocument.gd")
const Exporter = preload("res://src/presentation/worldmap/editor/document_export/WorldMapDocumentExport.gd")
const DocumentIO = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceDocumentIO.gd")
const BattleMapFactory = preload("res://src/factories/BattleMapFactory.gd")

var failures: Array[String] = []


class FailBattleIO extends DocumentIO:
	func writeTextAtomic(path: String, text: String) -> bool:
		if path.ends_with(".battle.json"):
			return false
		return super.writeTextAtomic(path, text)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var data := MapData.loadFrom(MapData.pathFor("hex_battle_fixture"))
	_require(data != null, "fixture document is missing")
	if data == null:
		_finish()
		return
	var record := FileDocument.nextSaveRecord(FileDocument.createRecord(data), false)
	var base := "user://hxf_document_export"
	var paths := {
		"texture": "%s/map.tres" % base,
		"scene": "%s/map.tscn" % base,
		"battle": "%s/map.json" % base,
		"receipt": "%s/map.receipt.json" % base,
	}
	var result := Exporter.publish(data, record, {}, DocumentIO.new(), paths)
	_require(bool(result.get("ok", false)), "matched publish failed: %s" % result.get("error", ""))
	if bool(result.get("ok", false)):
		var definition: Dictionary = result["definition"]
		var source: Dictionary = definition["SOURCE"]
		_require(str(source["ID"]) == str(record["DOCUMENT_ID"]), "source UUID was not exported")
		_require(int(source["REVISION"]) == int(record["REVISION"]), "source revision drifted")
		_require(str(source["FINGERPRINT"]) == FileDocument.fingerprint(record), "source hash drifted")
		_require(int(definition["REVISION"]) == int(record["REVISION"]), "battle revision drifted")
		_require(ResourceLoader.exists(str(paths["scene"])), "visual scene is not loadable")
		var loaded := BattleMapFactory.fromDictionary(definition)
		_require(bool(loaded.get("success", false)), "BattleMapFactory rejected emitted data")

	var changed := MapData.fromDictionary(data.toDictionary())
	changed.description += " dirty"
	var dirty := Exporter.publish(changed, record, {}, DocumentIO.new(), paths)
	_require(not bool(dirty.get("ok", false)), "unsaved document content was exported")

	var failedPaths := paths.duplicate(true)
	failedPaths["battle"] = "%s/failure.battle.json" % base
	failedPaths["receipt"] = "%s/failure.receipt.json" % base
	var partial := Exporter.publish(data, record, {}, FailBattleIO.new(), failedPaths)
	_require(not bool(partial.get("ok", false)), "partial I/O failure reported success")
	_require(not FileAccess.file_exists(str(failedPaths["receipt"])), "failed publish wrote a success receipt")
	_finish()


func _finish() -> void:
	if not failures.is_empty():
		for failure in failures:
			printerr("HXF_EXPORT_FAILURE: %s" % failure)
		quit(1)
		return
	print("HEX DOCUMENT EXPORT PASS")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
