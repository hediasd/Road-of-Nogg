## Publishes one saved editor envelope as a matched visual/battle artifact set.
class_name WorldMapDocumentExport
extends RefCounted

const FileDocument = preload("res://src/presentation/worldmap/editor/document/WorldMapFileDocument.gd")
const Baker = preload("res://src/presentation/worldmap/editor/WorldMapBaker.gd")
const SceneExport = preload("res://src/presentation/worldmap/editor/WorldMapSceneExport.gd")
const BattleExport = preload("res://src/presentation/worldmap/editor/WorldMapBattleExport.gd")
const TacticalLayer = preload("res://src/presentation/worldmap/editor/WorldMapTacticalLayer.gd")
const BattleMapFactory = preload("res://src/factories/BattleMapFactory.gd")


static func publish(data: WorldMapTileData, record: Dictionary, framing: Dictionary, io,
		paths := {}) -> Dictionary:
	var decoded := FileDocument.decodeRecord(record)
	if data == null or not bool(decoded.get("ok", false)):
		return _failure("no valid saved source snapshot is open")
	var saved: Dictionary = decoded["record"]
	var revision := int(saved["REVISION"])
	if revision < 1:
		return _failure("save the source document before exporting")
	if FileDocument.canonicalText(saved["CONTENT"] as Dictionary) != FileDocument.canonicalText(data.toDictionary()):
		return _failure("the open document has changes that are not in the saved snapshot")

	var documentID := str(saved["DOCUMENT_ID"])
	var stem := "hex_%s" % documentID.replace("-", "")
	var resolved := _paths(stem, paths)
	var built := BattleExport.buildDefinition(data, str(resolved["scene"]), TacticalLayer.DEFAULT_LAYER, stem)
	if not bool(built.get("ok", false)):
		return built

	var identity := {
		"ID": documentID,
		"REVISION": revision,
		"FINGERPRINT": FileDocument.fingerprint(saved),
		"VISUAL_SCENE_PATH": str(resolved["scene"]),
		"HEADLESS_ONLY": false,
	}
	var definition: Dictionary = (built["definition"] as Dictionary).duplicate(true)
	definition["NAME"] = stem
	definition["REVISION"] = revision
	definition["SOURCE"] = identity.duplicate(true)

	var baker := Baker.new()
	var texture := baker.bake(data)
	if texture == null or not io.saveResource(texture, str(resolved["texture"])):
		return _failure("baked art could not be written", resolved)
	var externalTexture: Texture2D = io.loadTexture(str(resolved["texture"]))
	if externalTexture == null:
		return _failure("baked art was written but could not be reloaded", resolved)

	var mapRoot := SceneExport.buildRuntime(data, externalTexture, framing)
	mapRoot.set_meta(SceneExport.META_SOURCE, identity.duplicate(true))
	var packed := PackedScene.new()
	var packError := packed.pack(mapRoot)
	mapRoot.free()
	if packError != OK or not io.saveResource(packed, str(resolved["scene"])):
		return _failure("visual scene could not be published", resolved)

	var runtimeCheck := BattleMapFactory.fromDictionary(definition)
	if not bool(runtimeCheck.get("success", false)):
		return _failure("battle definition failed runtime validation: %s" % runtimeCheck.get("error", ""), resolved)
	if not io.writeTextAtomic(str(resolved["battle"]), JSON.stringify([definition], "\t") + "\n"):
		return _failure("battle definition could not be published", resolved)

	var receipt := {
		"SOURCE": identity,
		"TEXTURE": resolved["texture"],
		"VISUAL_SCENE": resolved["scene"],
		"BATTLE_MAP": resolved["battle"],
	}
	if not io.writeTextAtomic(str(resolved["receipt"]), JSON.stringify(receipt, "\t") + "\n"):
		return _failure("artifacts were written but the success receipt was not", resolved)
	return {"ok": true, "stem": stem, "paths": resolved, "definition": definition, "receipt": receipt}


static func _paths(stem: String, overrides: Dictionary) -> Dictionary:
	return {
		"texture": str(overrides.get("texture", "%s/%s.tres" % [Baker.GENERATED_DIR, stem])),
		"scene": str(overrides.get("scene", "%s/%s.tscn" % [SceneExport.GENERATED_DIR, stem])),
		"battle": str(overrides.get("battle", "%s/%s.json" % [BattleExport.GENERATED_DIR, stem])),
		"receipt": str(overrides.get("receipt", "%s/%s.receipt.json" % [BattleExport.GENERATED_DIR, stem])),
	}


static func _failure(error: String, paths := {}) -> Dictionary:
	return {"ok": false, "error": error, "paths": paths}
