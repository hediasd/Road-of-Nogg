## WMC-1: the cloud sheet is on temp2's palette, and the catalog describes the art that is
## actually in the file.
##
## Every assertion here keys on what is being looked FOR rather than on a list of exclusions.
## The last cycle lost three measurements to classifiers phrased as "not X and not Y".

extends SceneTree

const CloudCatalog = preload("res://src/presentation/worldmap/WorldMapCloudCatalog.gd")
const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")

const SET := "temp2"
const SHEET := "res://assets/worldmap/clouds/temp2_clouds.png"
const REGION := "res://assets/worldmap/regions/temp2.png"

## Opaque pixels per piece, measured from the source before conversion. A piece that loses or
## gains a pixel has been resampled, and resampling is the failure this whole item exists to
## prevent.
const EXPECTED_OPAQUE := [2560, 2432, 2560, 2112]

var _failures: Array[String] = []


func _check(label: String, ok: bool, detail: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label + "  " + detail)
	if not ok:
		_failures.append(label)


func _palette(img: Image) -> Dictionary:
	var counts := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var key := Color(c.r, c.g, c.b).to_html(false)
			counts[key] = int(counts.get(key, 0)) + 1
	return counts


## Cells of BLOCK_PIXELS square that are not one flat colour. The art is blocks with a 1 px
## outline stepped over their corners, so this counts the outline's footprint and nothing else.
func _mixedCells(sheet: Image, rect: Rect2i) -> int:
	var mixed := 0
	for cy in rect.size.y / CloudCatalog.BLOCK_PIXELS:
		for cx in rect.size.x / CloudCatalog.BLOCK_PIXELS:
			var ox := rect.position.x + cx * CloudCatalog.BLOCK_PIXELS
			var oy := rect.position.y + cy * CloudCatalog.BLOCK_PIXELS
			var first := sheet.get_pixel(ox, oy)
			var uniform := true
			for y in CloudCatalog.BLOCK_PIXELS:
				for x in CloudCatalog.BLOCK_PIXELS:
					if sheet.get_pixel(ox + x, oy + y) != first:
						uniform = false
			if not uniform:
				mixed += 1
	return mixed


func _initialize() -> void:
	var region := Image.load_from_file(REGION)
	var sheet := Image.load_from_file(SHEET)
	var regionPalette := _palette(region)
	var sheetPalette := _palette(sheet)

	print("probe_cloud_art")
	print("  region palette: %s" % [regionPalette.keys()])
	print("  sheet palette:  %s" % [sheetPalette.keys()])

	_check("region has seven colours", regionPalette.size() == 7, "%d" % regionPalette.size())

	var offPalette := 0
	for key in sheetPalette.keys():
		if not regionPalette.has(key):
			offPalette += int(sheetPalette[key])
	_check("no sheet pixel is off temp2's palette", offPalette == 0, "%d px" % offPalette)

	var partial := 0
	var clear := 0
	var opaque := 0
	for y in sheet.get_height():
		for x in sheet.get_width():
			var a := sheet.get_pixel(x, y).a
			if a <= 0.0:
				clear += 1
			elif a >= 1.0:
				opaque += 1
			else:
				partial += 1
	_check("alpha is binary", partial == 0, "clear=%d opaque=%d partial=%d" % [clear, opaque, partial])

	# Four pieces, at the rects the catalog names, each with the opaque count it had before
	# conversion. Counting inside the declared rect and separately over the whole sheet is what
	# catches a piece that moved: the totals agree only if nothing lives outside the rects.
	var declared := 0
	var pieces := CloudCatalog.pieces(SET)
	_check("catalog declares two pairs", pieces.size() == 2, "%d" % pieces.size())
	var index := 0
	for piece in pieces:
		for role in ["cloud", "shadow"]:
			var rect: Rect2i = piece[role]
			var count := 0
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					if sheet.get_pixel(x, y).a > 0.0:
						count += 1
			declared += count
			var want: int = EXPECTED_OPAQUE[index]
			_check("piece %d %s intact" % [index / 2, role], count == want,
				"%s  %d px (want %d)" % [rect, count, want])
			index += 1
	_check("no opaque pixel lies outside a declared rect", declared == opaque,
		"in rects %d, in sheet %d" % [declared, opaque])

	# The art is 8 px blocks under a 1 px outline. Only the ten cells the outline steps through
	# are mixed; if that count moves, the sheet has been rescaled or filtered.
	for piece in pieces:
		for role in ["cloud", "shadow"]:
			var rect: Rect2i = piece[role]
			_check("%s is a whole number of 8 px blocks" % role,
				rect.size.x % CloudCatalog.BLOCK_PIXELS == 0
					and rect.size.y % CloudCatalog.BLOCK_PIXELS == 0,
				"%s" % rect.size)
			_check("%s outline touches few cells" % role, _mixedCells(sheet, rect) <= 10,
				"%d mixed cells" % _mixedCells(sheet, rect))

	# The shadow is not the cloud rescaled. If these ever match, someone has replaced the
	# artist's foreshortened shadow with a copy of the silhouette.
	for piece in pieces:
		var cloudRect: Rect2i = piece["cloud"]
		var shadowRect: Rect2i = piece["shadow"]
		var same := true
		if cloudRect.size != shadowRect.size:
			same = false
		else:
			for y in cloudRect.size.y:
				for x in cloudRect.size.x:
					var a := sheet.get_pixel(cloudRect.position.x + x, cloudRect.position.y + y).a
					var b := sheet.get_pixel(shadowRect.position.x + x, shadowRect.position.y + y).a
					if (a > 0.0) != (b > 0.0):
						same = false
		_check("shadow is drawn, not copied from its cloud", not same,
			"cloud %s shadow %s" % [cloudRect.size, shadowRect.size])

	_check("catalog resolves its texture", CloudCatalog.textureFor(SET) != null, SHEET)
	_check("piece lookup wraps", CloudCatalog.pieceAt(SET, 5) == CloudCatalog.pieceAt(SET, 1), "5 -> 1")
	_check("native size is the cloud's rect", CloudCatalog.pieceMapPixels(SET, 0) == Vector2i(88, 40),
		"%s" % CloudCatalog.pieceMapPixels(SET, 0))

	# temp2 is 8 px tiles, so 88x40 map pixels is 11x5 tiles. Stated so the number a renderer
	# needs is recorded rather than re-derived.
	var tilePixels := Uniforms.TILE_PIXELS
	print("  native cloud size: %d x %d map px = %d x %d tiles at %d px/tile"
		% [88, 40, 88 / tilePixels, 40 / tilePixels, tilePixels])

	print("probe_cloud_art: %s (%d failures)"
		% ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	if _failures.is_empty():
		print("WORLD MAP CLOUD ART OK")
	quit(0 if _failures.is_empty() else 1)
