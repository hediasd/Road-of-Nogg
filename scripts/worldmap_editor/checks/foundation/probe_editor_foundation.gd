extends SceneTree

## Opens the real editor scene and asserts the foundation state is genuinely neutral. This is
## intentionally narrower than a visual test: it checks that no legacy debug-world dependency can
## silently put temp2, clouds, a sky, props or the old preview drawer back into a fresh editor.

const EditorScene = preload("res://scenes/debug/WorldMapEditorScene.tscn")
const Actions = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceActions.gd")
const EditorCamera = preload("res://src/presentation/worldmap/editor/WorldMapEditorCamera.gd")
const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var editor := EditorScene.instantiate()
	root.add_child(editor)
	await process_frame
	await process_frame

	_require(editor.get("_document") == null, "fresh editor opened an authored document")
	_require(editor.get_node_or_null("Ui/PanelContainer") == null, "legacy preview panel remains")
	_require(editor.get_node_or_null("World/FoundationMap/Ground") != null, "neutral ground missing")
	_require(editor.get_node_or_null("World/FoundationMap/Camera") != null, "editor camera missing")
	var camera := editor.get_node("World/FoundationMap/Camera") as WorldMapEditorCamera
	_require(camera.mode == EditorCamera.Mode.ORTHO, "foundation did not start in authoring view")
	var offContractBadge := editor.find_child("OffContractBadge", true, false) as Label
	_require(offContractBadge != null and not offContractBadge.visible,
		"authoring view exposes the legacy off-contract badge")
	_require(editor.get_node_or_null("World/FoundationMap/Ground/CloudShadows") == null,
		"fresh editor configured cloud shadows")
	_require(not Actions.has("view.previewSettings"), "legacy preview action remains reachable")
	for retired: String in ["view.editing", "view.shipping", "view.projection"]:
		_require(not Actions.has(retired), "%s remains reachable" % retired)

	var stage := editor.get_node("World/FoundationMap")
	for child in stage.get_children():
		var forbidden := str(child.name).to_lower()
		_require(
			forbidden not in ["sky", "clouds", "props", "sun", "light"],
			"fresh foundation contains legacy node %s" % child.name
		)

	var choices: Array[Vector2i] = editor.call("_newLatticeChoices")
	_require(not choices.is_empty() and choices[0] == Vector2i(19, 14),
		"New does not default to the 19 x 14 hex lattice")
	editor.call("_newDocument", Vector2i(19, 14), "Untitled", "temp2_hex32_starter")
	await process_frame
	var region: Rect2 = editor.get_node("World/FoundationMap/Ground").regionRect()
	_require(camera.focus.is_equal_approx(region.get_center()), "New did not centre the map")
	_require(camera.size > 0.0 and camera.size < 64.0, "New did not fit the map")
	editor.call("_updateGrid")
	var material := editor.get_node("World/FoundationMap/Ground").material_override as ShaderMaterial
	_require(
		int(material.get_shader_parameter(Uniforms.U_GRID_MODE)) == Uniforms.GRID_TILES,
		"New did not show the hex grid while Navigate remained selected"
	)

	editor.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			printerr("HXF_FOUNDATION_FAILURE: %s" % failure)
		quit(1)
		return
	print("HEX EDITOR FOUNDATION OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
