extends SceneTree

const FileDocument = preload("res://src/presentation/worldmap/editor/document/WorldMapFileDocument.gd")
const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const HeightField = preload("res://src/presentation/worldmap/editor/WorldMapHeightField.gd")

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_checkRoundTripAndIdentity()
	_checkLegacyAndRejects()
	_checkStructuralValidation()
	if not failures.is_empty():
		for failure in failures:
			printerr("HEX_FILE_DOCUMENT_FAILURE: %s" % failure)
		quit(1)
		return
	print("HEX FILE DOCUMENT PASS")
	quit(0)


func _document() -> WorldMapTileData:
	var data := MapData.create("Café hex", Vector2i(3, 2), MapData.LAYOUT_HEX_FLAT)
	data.description = "Unicode title survives: São Paulo"
	data.palette_region = "temp2"
	data.layers["ground"]["TILESET"] = "temp2_hex32_starter"
	data.setCell("ground", Vector2i(2, 1), "t014")
	data.addHeightLayer("heights")
	HeightField.setHeightAt(data, Vector3i(0, 0, 0), 1.25, "heights")
	data.addDetailLayer("detail", "temp2_hex32_starter")
	data.setDetail("detail", Vector2i(1, 1), 3, "t003")
	data.addWaterLayer("water")
	data.setWater("water", Vector2i(0, 1), "0.5")
	data.addListLayer("objects")
	data.layers["objects"]["NEXT_ID"] = 8
	data.layers["objects"]["ITEMS"] = [{"ID": "x7", "CUSTOM": {"RETAIN": true, "NOTE": "opaque"}}]
	return data


func _checkRoundTripAndIdentity() -> void:
	var record := FileDocument.createRecord(_document())
	_require(not record.is_empty(), "could not create a v1 hex record")
	_require(int(record["REVISION"]) == 0, "new record did not begin unsaved at revision 0")
	_require(FileDocument._isUUIDv4(str(record["DOCUMENT_ID"])), "new record did not have lowercase UUIDv4 identity")
	var decoded := FileDocument.decodeRecord(record)
	_require(bool(decoded["ok"]) and decoded["data"] != null, "valid v1 record did not decode")
	var content: Dictionary = (decoded["record"] as Dictionary)["CONTENT"]
	_require((content["LAYERS"] as Array).size() == 6, "round-trip did not retain every supported layer kind")
	var opaque: Dictionary = ((content["LAYERS"] as Array).filter(func(layer): return layer["ID"] == "objects")[0] as Dictionary)["ITEMS"][0]
	_require(bool((opaque["CUSTOM"] as Dictionary)["RETAIN"]), "opaque list properties were discarded")
	var firstText := FileDocument.canonicalText(decoded["record"])
	_require(firstText == FileDocument.canonicalText(decoded["record"]), "canonical text was unstable")
	_require(FileDocument.fingerprint(decoded["record"]) == FileDocument.fingerprint(decoded["record"]), "fingerprint was unstable")
	var before := (decoded["record"] as Dictionary).duplicate(true)
	var saved := FileDocument.nextSaveRecord(decoded["record"], false)
	_require(int(saved["REVISION"]) == 1 and saved["DOCUMENT_ID"] == before["DOCUMENT_ID"], "first normal save did not retain identity and set revision 1")
	_require(int((decoded["record"] as Dictionary)["REVISION"]) == 0, "nextSaveRecord mutated its input")
	var copied := FileDocument.nextSaveRecord(saved, true)
	_require(int(copied["REVISION"]) == 1 and copied["DOCUMENT_ID"] != saved["DOCUMENT_ID"], "Save As did not create an independent revision-1 identity")


func _checkLegacyAndRejects() -> void:
	var raw := _document().toDictionary()
	var imported := FileDocument.importLegacy(raw)
	_require(bool(imported["ok"]) and int((imported["record"] as Dictionary)["REVISION"]) == 0, "legacy hex import did not produce unsaved record")
	var square := MapData.create("old", Vector2i(2, 2), MapData.LAYOUT_SQUARE).toDictionary()
	_require(not bool(FileDocument.importLegacy(square)["ok"]), "legacy square content was accepted")
	var future := FileDocument.createRecord(_document())
	future["VERSION"] = 2
	_require(not bool(FileDocument.decodeRecord(future)["ok"]), "future envelope version was accepted")


func _checkStructuralValidation() -> void:
	var record := FileDocument.createRecord(_document())
	var zeroRun := record.duplicate(true)
	((zeroRun["CONTENT"] as Dictionary)["LAYERS"] as Array)[0]["RLE"] = ["0:-"]
	_require(not bool(FileDocument.decodeRecord(zeroRun)["ok"]), "zero-length RLE was accepted")
	var longRun := record.duplicate(true)
	((longRun["CONTENT"] as Dictionary)["LAYERS"] as Array)[0]["RLE"] = ["999:-"]
	_require(not bool(FileDocument.decodeRecord(longRun)["ok"]), "overlong RLE was accepted")
	var malformedRun := record.duplicate(true)
	((malformedRun["CONTENT"] as Dictionary)["LAYERS"] as Array)[0]["RLE"] = ["not-a-run"]
	_require(not bool(FileDocument.decodeRecord(malformedRun)["ok"]), "malformed RLE was accepted")
	var unknown := record.duplicate(true)
	(unknown["CONTENT"] as Dictionary)["EXTRA"] = true
	_require(not bool(FileDocument.decodeRecord(unknown)["ok"]), "unknown structural content field was accepted")
	var kind := record.duplicate(true)
	((kind["CONTENT"] as Dictionary)["LAYERS"] as Array)[0]["KIND"] = "future_kind"
	_require(not bool(FileDocument.decodeRecord(kind)["ok"]), "unknown layer kind was accepted")
	var duplicate := record.duplicate(true)
	((duplicate["CONTENT"] as Dictionary)["LAYERS"] as Array)[1]["ID"] = "ground"
	_require(not bool(FileDocument.decodeRecord(duplicate)["ok"]), "duplicate layer id was accepted")
	var malformed := record.duplicate(true)
	malformed["DOCUMENT_ID"] = "not-a-uuid"
	var failed := FileDocument.decodeRecord(malformed)
	_require(not bool(failed["ok"]) and (failed["record"] as Dictionary).is_empty() and failed["data"] == null and not str(failed["error"]).is_empty(), "failure returned partial document state")


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
