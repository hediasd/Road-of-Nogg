## WME-4's self-contained validation: a tile's identity survives its sheet being re-exported.
##
## The defect this guards is silent and unrecoverable. If a tile's id were its position in the
## sheet, inserting one tile near the front would shift every index after it and repaint every
## authored region that referenced them -- no failed load, no error, nothing to notice until
## someone opens a region they did not touch and finds it changed. So the assertions below are
## mostly about ids NOT moving.
##
## Tests drive `cutSheet` and `reconcile` on synthetic in-memory sheets rather than
## `importSheet`, which is only file IO around those two. Synthetic sheets keep the checks
## deterministic and let a re-export be simulated exactly; the real committed tileset is checked
## separately at the end.

extends SceneTree

const TilesetCatalog = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")
const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")
const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

const GRID := 16

var _failures := 0


func _initialize() -> void:
	_checkStableUnderNoChange()
	_checkInsertionPreservesIds()
	_checkRepaintKeepsId()
	_checkRemovalRetiresId()
	_checkDuplicateTilesKeepTheirCount()
	_checkPaletteValidation()
	_checkRealTileset()

	print("")
	print("probe_tileset_ids: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	if _failures == 0:
		print("WORLD MAP TILESET IDS OK")
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


## A sheet of solid-colour tiles, one per entry in `colours`, laid out row-major `columns` wide.
## Solid colours make every tile trivially distinct and every hash trivially stable.
func _sheet(colours: Array, columns: int) -> Image:
	var rows := int(ceil(float(colours.size()) / float(columns)))
	var image := Image.create(columns * GRID, rows * GRID, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for i in colours.size():
		var target := Rect2i((i % columns) * GRID, (i / columns) * GRID, GRID, GRID)
		image.fill_rect(target, colours[i])
	return image


func _cells(image: Image) -> Array:
	return TilesetCatalog.cutSheet(image, GRID)["cells"]


## Ids in the order the reconciled ledger holds them, for set comparisons.
func _idsOf(tiles: Array) -> Array:
	var out: Array = []
	for tile in tiles:
		out.append(str((tile as Dictionary)["ID"]))
	out.sort()
	return out


## A ledger built by importing a sheet from scratch, which is what pass 5 does for every cell.
func _freshLedger(image: Image) -> Dictionary:
	return TilesetCatalog.reconcile([], _cells(image), 0)


func _palette(colours: Array) -> PackedColorArray:
	var out := PackedColorArray()
	for colour in colours:
		out.append(colour)
	return out


const RED := Color8(200, 40, 40)
const GREEN := Color8(40, 200, 40)
const BLUE := Color8(40, 40, 200)
const YELLOW := Color8(220, 220, 40)
const PURPLE := Color8(160, 40, 200)


func _checkStableUnderNoChange() -> void:
	print("-- re-importing an unchanged sheet changes nothing --")
	var sheet := _sheet([RED, GREEN, BLUE, YELLOW], 2)
	var first := _freshLedger(sheet)
	var second := TilesetCatalog.reconcile(first["tiles"], _cells(sheet), int(first["next_id"]))
	if _idsOf(first["tiles"]) != _idsOf(second["tiles"]):
		_fail("ids changed across an identical re-import")
		return
	var report: Dictionary = second["report"]
	for verdict in [TilesetCatalog.ADDED, TilesetCatalog.MOVED, TilesetCatalog.CHANGED, TilesetCatalog.REMOVED]:
		if not (report[verdict] as Array).is_empty():
			_fail("identical re-import reported %s: %s" % [verdict, report[verdict]])
			return
	if int(second["next_id"]) != int(first["next_id"]):
		_fail("identical re-import advanced next_id")
		return
	print("  ok    4 tiles, all unchanged, next_id held at %d" % int(second["next_id"]))


## The headline case: an artist inserts a tile at the front and every later tile shifts one cell.
## Positional ids would renumber all of them; content-hashed ids must not.
func _checkInsertionPreservesIds() -> void:
	print("-- inserting a tile at the front renumbers nothing --")
	var before := _sheet([RED, GREEN, BLUE, YELLOW], 2)
	var first := _freshLedger(before)
	var originalIds := _idsOf(first["tiles"])

	var after := _sheet([PURPLE, RED, GREEN, BLUE, YELLOW], 2)
	var second := TilesetCatalog.reconcile(first["tiles"], _cells(after), int(first["next_id"]))
	var report: Dictionary = second["report"]

	for id in originalIds:
		if not _idsOf(second["tiles"]).has(id):
			_fail("id %s vanished after an insertion" % id)
			return
	if (report[TilesetCatalog.ADDED] as Array).size() != 1:
		_fail("expected exactly 1 added, got %s" % [report[TilesetCatalog.ADDED]])
		return
	if not (report[TilesetCatalog.REMOVED] as Array).is_empty():
		_fail("insertion reported a removal: %s" % [report[TilesetCatalog.REMOVED]])
		return
	if not (report[TilesetCatalog.CHANGED] as Array).is_empty():
		_fail("insertion reported a repaint: %s" % [report[TilesetCatalog.CHANGED]])
		return
	print("  ok    all %d original ids kept, 1 added, %d moved, 0 changed, 0 removed" % [
		originalIds.size(), (report[TilesetCatalog.MOVED] as Array).size()
	])


func _checkRepaintKeepsId() -> void:
	print("-- repainting a cell keeps that cell's id --")
	var before := _sheet([RED, GREEN, BLUE, YELLOW], 2)
	var first := _freshLedger(before)
	var after := _sheet([RED, GREEN, PURPLE, YELLOW], 2)
	var second := TilesetCatalog.reconcile(first["tiles"], _cells(after), int(first["next_id"]))
	var report: Dictionary = second["report"]
	if _idsOf(first["tiles"]) != _idsOf(second["tiles"]):
		_fail("a repaint changed the id set")
		return
	if (report[TilesetCatalog.CHANGED] as Array).size() != 1:
		_fail("expected exactly 1 changed, got %s" % [report[TilesetCatalog.CHANGED]])
		return
	print("  ok    id set intact, reported: %s" % [report[TilesetCatalog.CHANGED]])


## A removed tile's id is retired, and `next_id` never walks backwards -- so the id cannot be
## reissued to a different tile by a later import.
func _checkRemovalRetiresId() -> void:
	print("-- a removed tile's id is retired, never reissued --")
	var before := _sheet([RED, GREEN, BLUE, YELLOW], 2)
	var first := _freshLedger(before)
	var after := _sheet([RED, GREEN, BLUE], 2)
	var second := TilesetCatalog.reconcile(first["tiles"], _cells(after), int(first["next_id"]))
	var report: Dictionary = second["report"]
	if (report[TilesetCatalog.REMOVED] as Array).size() != 1:
		_fail("expected exactly 1 removed, got %s" % [report[TilesetCatalog.REMOVED]])
		return
	if int(second["next_id"]) < int(first["next_id"]):
		_fail("next_id walked backwards after a removal")
		return
	# Add a different tile back and confirm it gets a NEW id, not the retired one.
	var third := TilesetCatalog.reconcile(
		second["tiles"], _cells(_sheet([RED, GREEN, BLUE, PURPLE], 2)), int(second["next_id"])
	)
	var retired := str((report[TilesetCatalog.REMOVED] as Array)[0]).split(" ")[0]
	for line in third["report"][TilesetCatalog.ADDED]:
		if str(line).begins_with(retired + " "):
			_fail("retired id %s was reissued to a new tile" % retired)
			return
	print("  ok    %s retired; the replacement got a fresh id" % retired)


## Two cells with identical pixels. This is the case a content hash alone cannot resolve, and it
## is worth being precise about what the ledger does and does not promise.
##
## What holds: the COUNT is preserved and the id SET is preserved -- neither duplicate collapses
## into the other, which is what a hash-only scheme would do.
##
## What does not hold, and cannot: WHICH id lands on which duplicate is not guaranteed across a
## re-cut. The two tiles are pixel-identical, so nothing in the sheet distinguishes them; if a
## re-export shifts them, the ledger may permute their ids. Nothing observable changes -- the
## pixels are the same -- unless per-tile METADATA differs between them, e.g. the same blank
## green labelled "grass" on one and "filler" on the other. An artist who needs two visually
## identical tiles to mean different things must make them differ by a pixel, and this probe
## records that limitation rather than asserting a guarantee the design cannot make.
func _checkDuplicateTilesKeepTheirCount() -> void:
	print("-- identical tiles stay distinct entries --")
	var sheet := _sheet([RED, RED, GREEN, BLUE], 2)
	var first := _freshLedger(sheet)
	if (first["tiles"] as Array).size() != 4:
		_fail("4 cells with a duplicate produced %d ledger entries" % (first["tiles"] as Array).size())
		return
	var second := TilesetCatalog.reconcile(first["tiles"], _cells(sheet), int(first["next_id"]))
	if _idsOf(first["tiles"]) != _idsOf(second["tiles"]):
		_fail("the id set changed across a re-import of a sheet with duplicates")
		return
	if (second["report"][TilesetCatalog.ADDED] as Array).size() != 0:
		_fail("duplicates caused a spurious allocation")
		return
	print("  ok    4 entries for 4 cells with a duplicate pair; id set stable")


func _checkPaletteValidation() -> void:
	print("-- palette validation catches an off-palette colour --")
	var clean := _sheet([RED, GREEN], 2)
	var offending := TilesetCatalog.offPaletteColours(clean, _palette([RED, GREEN]))
	if not offending.is_empty():
		_fail("an in-palette sheet reported %s" % [offending])
		return
	var dirty := _sheet([RED, PURPLE], 2)
	offending = TilesetCatalog.offPaletteColours(dirty, _palette([RED, GREEN]))
	if offending.size() != 1:
		_fail("expected exactly 1 off-palette colour, got %s" % [offending])
		return
	print("  ok    clean sheet reports nothing; dirty sheet reports %s" % [offending])


## The committed bootstrap tileset, against the palette of the region it was cut from. Cut from
## temp2's own art, so a single off-palette colour here would mean the cutter or the reader is
## wrong rather than the art.
func _checkRealTileset() -> void:
	print("-- the committed temp2_ground tileset --")
	if not TilesetCatalog.has("temp2_ground"):
		_fail("temp2_ground is not in the catalog")
		return
	var reference: Dictionary = TilesetCatalog.tilesetFor("temp2_ground")
	var image := TilesetCatalog.loadSheetImage(str(reference["SHEET"]))
	if image == null:
		_fail("could not read the committed sheet")
		return
	var region := RegionCatalog.loadRegion(str(reference["PALETTE_REGION"]))
	if region.is_empty():
		_fail("could not load the palette region")
		return
	var regionImage: Image = (region["texture"] as Texture2D).get_image()
	if regionImage.is_compressed():
		regionImage.decompress()
	regionImage.convert(Image.FORMAT_RGBA8)

	var palette := PackedColorArray()
	var tally := {}
	for y in regionImage.get_height():
		for x in regionImage.get_width():
			var c := regionImage.get_pixel(x, y)
			tally[(int(c.r * 255.0) << 16) | (int(c.g * 255.0) << 8) | int(c.b * 255.0)] = true
	for key in tally:
		palette.append(Color8((int(key) >> 16) & 255, (int(key) >> 8) & 255, int(key) & 255))

	var offending := TilesetCatalog.offPaletteColours(image, palette)
	if not offending.is_empty():
		_fail("the committed sheet is off its own region's palette: %s" % [offending])
		return
	var ledger: Array = reference["TILES"]
	if ledger.size() != 40:
		_fail("expected 40 ledger entries, found %d" % ledger.size())
		return
	# Re-importing the committed sheet against its committed ledger must be a no-op.
	var again := TilesetCatalog.reconcile(ledger, _cells(image), int(reference["NEXT_ID"]))
	var report: Dictionary = again["report"]
	for verdict in [TilesetCatalog.ADDED, TilesetCatalog.MOVED, TilesetCatalog.CHANGED, TilesetCatalog.REMOVED]:
		if not (report[verdict] as Array).is_empty():
			_fail("re-importing the committed sheet reported %s: %s" % [verdict, report[verdict]])
			return
	print("  ok    40 tiles, %d region colours, nothing off-palette, re-import is a no-op" % palette.size())
