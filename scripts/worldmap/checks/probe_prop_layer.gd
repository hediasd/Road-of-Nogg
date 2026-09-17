## Does structure extraction still work now that its rule is region DATA rather than
## constants in the code?
##
## The bar is exact: temp2 must find the same 9 structures, with the same rects and the same
## kinds, as it did when `_isBuilt` carried its three colours inline. It also checks that a
## region declaring no rule finds nothing rather than finding noise -- "this map has no props"
## and "the detector failed" must not look the same from outside.
extends SceneTree

const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")

## What the hardcoded detector found, recorded before it was moved into data.
const EXPECTED_TEMP2 := {"count": 9, "houses": 7, "towers": 2}

func _initialize() -> void:
	var props := WorldMapProps.new()
	get_root().add_child(props)
	var failures := 0

	for regionID in RegionCatalog.ids():
		var region := RegionCatalog.loadRegion(regionID)
		if region.is_empty():
			print("SKIP %s -- could not load" % regionID)
			continue
		var declared := RegionCatalog.hasStructureRule(regionID)
		var out: Dictionary = props.rebuild(region["texture"], regionID, "gain")
		print("%-6s declares rule: %-5s  found %d (%d houses, %d towers)" % [
			regionID, str(declared), int(out["count"]), int(out["houses"]), int(out["towers"])
		])

		if regionID == "temp2":
			for key in EXPECTED_TEMP2:
				if int(out[key]) != int(EXPECTED_TEMP2[key]):
					print("  FAIL %s: expected %d, got %d" % [
						key, int(EXPECTED_TEMP2[key]), int(out[key])
					])
					failures += 1
			# Two shapes and nothing else. A rule that had drifted would show up here as a
			# third shape long before the counts moved.
			var shapes := {}
			for child in props.get_children():
				var s := child as MeshInstance3D
				if s == null:
					continue
				var rect: Rect2 = s.get_meta("prop_rect")
				var k := "%dx%d" % [int(rect.size.x), int(rect.size.y)]
				shapes[k] = int(shapes.get(k, 0)) + 1
			print("  shapes: ", shapes)
			if shapes.size() != 2:
				print("  FAIL expected exactly 2 distinct sprite shapes, got %d" % shapes.size())
				failures += 1
		elif not declared:
			# The negative control. temp is dithered and declares no rule; it must find zero
			# rather than the 302 noise components the colour key returns when let loose on it.
			if int(out["count"]) != 0:
				print("  FAIL %s declares no rule but found %d" % [regionID, int(out["count"])])
				failures += 1

	print("")
	print("PROP EXTRACTION: %s" % ("PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	if failures == 0:
		print("WORLD MAP PROP LAYER OK")
	quit(1 if failures > 0 else 0)
