## Versioned source record for the clean hex-map editor.
##
## `WorldMapTileData` remains the mutable, layer-agnostic model used by the old
## editor and exporters. This codec is deliberately outside it: a new source
## file must reject unsupported structure before the older permissive reader has
## a chance to normalise or omit it. The envelope supplies identity and revision
## without making a display name or filesystem path part of gameplay content.

class_name WorldMapFileDocument
extends RefCounted

const FORMAT := "nogg.hexmap"
const VERSION := 1
const EXTENSION := ".noggmap.json"

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const Tilesets = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")

const ENVELOPE_KEYS := ["FORMAT", "VERSION", "DOCUMENT_ID", "REVISION", "CONTENT"]
const CONTENT_KEYS := [
	"FORMAT_VERSION", "NAME", "DESCRIPTION", "SIZE_TILES", "LAYOUT", "PALETTE_REGION",
	"FOG_COLOR", "VOID_COLOR", "LAYERS",
]


## A new record is unsaved at revision 0. The first successful source save uses
## `nextSaveRecord(record, false)` and therefore persists revision 1.
static func createRecord(data: WorldMapTileData) -> Dictionary:
	if data == null:
		return {}
	var content := data.toDictionary()
	var contentError := _validateContent(content)
	if not contentError.is_empty():
		push_warning("WorldMapFileDocument: cannot create record: %s" % contentError)
		return {}
	var documentID := _newUUIDv4()
	if documentID.is_empty():
		push_warning("WorldMapFileDocument: cryptographic UUID generation failed")
		return {}
	return {
		"FORMAT": FORMAT,
		"VERSION": VERSION,
		"DOCUMENT_ID": documentID,
		"REVISION": 0,
		"CONTENT": content,
	}


## Decodes a v1 envelope into both an immutable-style record copy and the live
## editor model. Failure deliberately has no partial record or model.
static func decodeRecord(raw: Dictionary) -> Dictionary:
	var envelopeError := _validateEnvelope(raw)
	if not envelopeError.is_empty():
		return _failure(envelopeError)
	var content: Dictionary = raw["CONTENT"]
	var contentError := _validateContent(content)
	if not contentError.is_empty():
		return _failure(contentError)
	var data := MapData.fromDictionary(content)
	if data == null:
		return _failure("CONTENT could not be read as WorldMapTileData")
	var normalized := raw.duplicate(true)
	normalized["CONTENT"] = data.toDictionary()
	return _success(normalized, data)


## Old raw v1 hex content may be imported explicitly. It is never treated as a
## saved new-format file, and old square maps stay with the legacy editor.
static func importLegacy(raw: Dictionary) -> Dictionary:
	var contentError := _validateContent(raw)
	if not contentError.is_empty():
		return _failure("legacy import refused: %s" % contentError)
	var data := MapData.fromDictionary(raw)
	if data == null:
		return _failure("legacy import refused: content could not be read")
	var documentID := _newUUIDv4()
	if documentID.is_empty():
		return _failure("legacy import refused: cryptographic UUID generation failed")
	var record := {
		"FORMAT": FORMAT,
		"VERSION": VERSION,
		"DOCUMENT_ID": documentID,
		"REVISION": 0,
		"CONTENT": data.toDictionary(),
	}
	return _success(record, data)


## Canonical source text has sorted keys, tab indentation and no trailing
## newline. The same bytes back the map fingerprint used by later export code.
static func canonicalText(record: Dictionary) -> String:
	return JSON.stringify(record, "\t", true)


static func fingerprint(record: Dictionary) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(canonicalText(record).to_utf8_buffer())
	return "sha256:%s" % context.finish().hex_encode()


## Produces the record a successful source write would persist. It does not
## mutate or write the supplied record. A copy starts a distinct document at 1.
static func nextSaveRecord(record: Dictionary, asCopy: bool) -> Dictionary:
	var decoded := decodeRecord(record)
	if not bool(decoded["ok"]):
		return {}
	var next: Dictionary = (decoded["record"] as Dictionary).duplicate(true)
	if asCopy:
		var documentID := _newUUIDv4()
		if documentID.is_empty():
			return {}
		next["DOCUMENT_ID"] = documentID
		next["REVISION"] = 1
	else:
		next["REVISION"] = int(next["REVISION"]) + 1
	return next


static func _success(record: Dictionary, data: WorldMapTileData) -> Dictionary:
	return {"ok": true, "record": record, "data": data, "error": ""}


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "record": {}, "data": null, "error": error}


static func _validateEnvelope(raw: Dictionary) -> String:
	if not _hasExactlyKeys(raw, ENVELOPE_KEYS):
		return "record must contain exactly %s" % ", ".join(ENVELOPE_KEYS)
	if str(raw["FORMAT"]) != FORMAT:
		return "FORMAT must be '%s'" % FORMAT
	if not _isExactInteger(raw["VERSION"]) or int(raw["VERSION"]) != VERSION:
		return "VERSION %s is unsupported" % str(raw["VERSION"])
	if not raw["DOCUMENT_ID"] is String or not _isUUIDv4(str(raw["DOCUMENT_ID"])):
		return "DOCUMENT_ID must be a lowercase UUIDv4"
	if not _isExactInteger(raw["REVISION"]) or int(raw["REVISION"]) < 0:
		return "REVISION must be a non-negative integer"
	if not raw["CONTENT"] is Dictionary:
		return "CONTENT must be an object"
	return ""


static func _validateContent(content: Dictionary) -> String:
	if not _hasExactlyKeys(content, CONTENT_KEYS):
		return "CONTENT has unsupported or missing structural fields"
	if not _isExactInteger(content["FORMAT_VERSION"]) or int(content["FORMAT_VERSION"]) != MapData.FORMAT_VERSION:
		return "CONTENT.FORMAT_VERSION is unsupported"
	for key in ["NAME", "DESCRIPTION", "PALETTE_REGION", "FOG_COLOR", "VOID_COLOR"]:
		if not content[key] is String:
			return "CONTENT.%s must be a string" % key
	if not _isHexColour(str(content["FOG_COLOR"])) or not _isHexColour(str(content["VOID_COLOR"])):
		return "CONTENT fog and void colours must be six-digit RGB hex"
	var size = content["SIZE_TILES"]
	if not size is Array or (size as Array).size() != 2:
		return "CONTENT.SIZE_TILES must contain [columns, rows]"
	if not _isExactInteger(size[0]) or not _isExactInteger(size[1]) or int(size[0]) <= 0 or int(size[1]) <= 0:
		return "CONTENT.SIZE_TILES must contain positive integers"
	if str(content["LAYOUT"]) != MapData.LAYOUT_HEX_FLAT:
		return "only flat-top hex content can be opened by this editor"
	if not content["LAYERS"] is Array:
		return "CONTENT.LAYERS must be an array"
	var seen: Dictionary = {}
	for entry in content["LAYERS"]:
		if not entry is Dictionary:
			return "every layer must be an object"
		var layerError := _validateLayer(entry as Dictionary, Vector2i(int(size[0]), int(size[1])), seen)
		if not layerError.is_empty():
			return layerError
	return ""


static func _validateLayer(layer: Dictionary, size: Vector2i, seen: Dictionary) -> String:
	if not layer.has("ID") or not layer["ID"] is String or str(layer["ID"]).is_empty():
		return "layer ID must be a nonempty string"
	var id := str(layer["ID"])
	if seen.has(id):
		return "duplicate layer ID '%s'" % id
	seen[id] = true
	if not layer.has("KIND") or not layer["KIND"] is String:
		return "layer '%s' has no KIND" % id
	var kind := str(layer["KIND"])
	var expectedKeys: Array[String] = []
	var expectedCells := 0
	match kind:
		MapData.KIND_GRID:
			expectedKeys = ["ID", "KIND", "GRID_KIND", "TILESET", "RLE"]
			if not layer.has("GRID_KIND") or not layer["GRID_KIND"] is String:
				return "grid layer '%s' needs GRID_KIND" % id
			var gridKind := str(layer["GRID_KIND"])
			if gridKind != Tilesets.GRID_TILE and gridKind != Tilesets.GRID_CEL:
				return "grid layer '%s' has unsupported GRID_KIND '%s'" % [id, gridKind]
			expectedCells = size.x * size.y
		MapData.KIND_HEIGHTS:
			expectedKeys = ["ID", "KIND", "RLE"]
			expectedCells = (size.x + 2) * (size.y + 2) * 2
		MapData.KIND_WATER:
			expectedKeys = ["ID", "KIND", "RLE"]
			expectedCells = size.x * size.y
		MapData.KIND_DETAIL:
			expectedKeys = ["ID", "KIND", "GRID_KIND", "TILESET", "RLE"]
			if str(layer.get("GRID_KIND", "")) != Tilesets.GRID_TILE:
				return "detail layer '%s' must use tile GRID_KIND" % id
			expectedCells = size.x * size.y * MapData.DETAIL_SLOTS_PER_CELL
		MapData.KIND_LIST:
			expectedKeys = ["ID", "KIND", "NEXT_ID", "ITEMS"]
			if not _isExactInteger(layer.get("NEXT_ID", null)) or int(layer["NEXT_ID"]) < 0:
				return "list layer '%s' needs non-negative integer NEXT_ID" % id
			if not layer.get("ITEMS", null) is Array:
				return "list layer '%s' needs ITEMS array" % id
		_:
			return "layer '%s' has unsupported KIND '%s'" % [id, kind]
	if not _hasExactlyKeys(layer, expectedKeys):
		return "layer '%s' has unsupported or missing structural fields" % id
	if kind == MapData.KIND_GRID or kind == MapData.KIND_DETAIL:
		if not layer["TILESET"] is String:
			return "art layer '%s' needs string TILESET" % id
	if kind != MapData.KIND_LIST:
		return _validateRLE(layer["RLE"], expectedCells, kind, id)
	return ""


static func _validateRLE(rawRuns, expected: int, kind: String, layerID: String) -> String:
	if not rawRuns is Array or (rawRuns as Array).is_empty():
		return "layer '%s' needs nonempty RLE" % layerID
	var total := 0
	for run in rawRuns:
		if not run is String:
			return "layer '%s' has non-string RLE entry" % layerID
		var parts := str(run).split(":", true, 1)
		if parts.size() != 2 or not parts[0].is_valid_int():
			return "layer '%s' has malformed RLE entry '%s'" % [layerID, str(run)]
		var count := int(parts[0])
		if count <= 0:
			return "layer '%s' has non-positive RLE count" % layerID
		if count > expected - total:
			return "layer '%s' RLE exceeds expected cell count" % layerID
		var value := parts[1]
		if kind == MapData.KIND_HEIGHTS or kind == MapData.KIND_WATER:
			if value != MapData.EMPTY and (not value.is_valid_float() or not is_finite(float(value))):
				return "layer '%s' has non-finite numeric RLE value" % layerID
		total += count
	if total != expected:
		return "layer '%s' RLE has %d values, expected %d" % [layerID, total, expected]
	return ""


static func _hasExactlyKeys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true


static func _isExactInteger(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))


static func _isHexColour(value: String) -> bool:
	if value.length() != 6:
		return false
	for index in value.length():
		if not (value[index].to_lower() in "0123456789abcdef"):
			return false
	return true


static func _newUUIDv4() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	if bytes.size() != 16:
		return ""
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


static func _isUUIDv4(value: String) -> bool:
	if value.length() != 36 or value[8] != "-" or value[13] != "-" or value[18] != "-" or value[23] != "-":
		return false
	if value[14] != "4" or not (value[19] in "89ab"):
		return false
	for index in value.length():
		if index in [8, 13, 18, 23]:
			continue
		if not (value[index] in "0123456789abcdef"):
			return false
	return true
