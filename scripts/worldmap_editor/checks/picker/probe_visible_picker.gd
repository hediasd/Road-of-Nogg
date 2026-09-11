extends SceneTree

const PickerScript = preload("res://src/presentation/worldmap/editor/WorldMapTilesetPicker.gd")

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var picker = PickerScript.new()
	picker.size = Vector2(248.0, 400.0)
	root.add_child(picker)
	await process_frame
	await process_frame
	var image := Image.create(160, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var tiles: Array[Dictionary] = []
	for row in 3:
		for column in 5:
			tiles.append({"ID": "t%03d" % (row * 5 + column), "CELL": Vector2i(column, row)})
	picker.configure("starter", ImageTexture.create_from_image(image), 32, tiles)
	await process_frame
	await process_frame
	var scroll := picker.get_node("PickerColumn/TilesheetScroll") as ScrollContainer
	var canvas := picker.get_node("PickerColumn/TilesheetScroll/TilesheetCanvas") as Control
	_require(scroll != null and scroll.size.y >= PickerScript.SHEET_VIEWPORT_MIN_HEIGHT, "sheet viewport did not receive its guaranteed minimum height")
	_require(canvas != null and canvas.size.x > 0.0 and canvas.size.y > 0.0, "sheet canvas had no laid-out bounds")
	_require(canvas.custom_minimum_size.x <= scroll.size.x + 0.1 and canvas.custom_minimum_size.y <= scroll.size.y + 0.1, "Fit did not keep the complete starter sheet inside the viewport")
	for tile: Dictionary in tiles:
		var centre := picker._zoomedFrameRect(str(tile["ID"])).get_center()
		_require(Rect2(Vector2.ZERO, scroll.size).has_point(centre), "Fit hid frame %s" % str(tile["ID"]))
	if not failures.is_empty():
		for failure in failures:
			printerr("HEX_PICKER_GEOMETRY_FAILURE: %s" % failure)
		quit(1)
		return
	print("HEX PICKER GEOMETRY PASS")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
