## HBP-4 reproducer for the exit-time access violation.
##
## READ THE POLARITY BEFORE CHANGING ANYTHING: this probe PASSES WHILE THE BUG IS PRESENT.
##
## It builds the object mix that provokes the fault, asserts its own work completed, and prints
## its marker. The process then dies during engine cleanup with Windows access-violation code
## -1073741819, AFTER the marker and after every assertion, so the launcher reports a non-zero
## exit for a run in which nothing this file checked went wrong.
##
## That inversion is deliberate. The alternative -- a probe that fails while the bug exists --
## would be a permanently red check that everyone learns to ignore, and it would not notice the
## day the crash stops. Run it as:
##
##     marker present + non-zero exit  ->  the bug is still here, as documented
##     marker present + exit 0         ->  THE BUG IS GONE. Delete this probe, close the
##                                         BACKLOG_CRITICAL entry, and say what fixed it.
##     marker absent                   ->  a real failure; read the assertions below.
##
## WHAT IS ESTABLISHED, measured over repeated runs rather than single ones:
##
##   * It is DETERMINISTIC PER CONFIGURATION. This probe's default mix crashed 13 of 13 runs;
##     a donor-only build crashed 0 of 5; a variant loading MORE hex code and building MORE
##     playbacks crashed 0 of 3. Earlier single-run results looked unstable only because the
##     configuration had changed between them.
##   * It needs the hex effect path. Donors alone are clean, including at 42 effects.
##   * It is NOT "more hex code is worse". The clean 0-of-3 variant loads every hex effect script
##     explicitly and builds all fourteen profiles; this crashing one loads fewer and builds nine.
##     The trigger is a particular COMPOSITION of the loaded graph, not its size.
##
## WHAT IS NOT ESTABLISHED: which object retains which, and why that retention outlives the
## resource system. HBP-4 did not get there. The next step is the leak dump, which needs
## Godot's output captured through a redirect that survives the fault -- the crash takes the
## report with it, and `--verbose` into a shell redirect produced an empty file here.
##
## `HXB_SHUTDOWN_HEX` and `HXB_SHUTDOWN_BODY` narrow the mix for bisection; `HXB_SHUTDOWN_ALL`
## uses every catalog profile rather than one per hex class, and `HXB_SHUTDOWN_FOOTPRINT` adds a
## real footprint and its ground wash. Unset, they reproduce the 13-of-13 configuration.
extends SceneTree

const BridgeScript = preload("res://src/presentation/battle/effects/HexBattleVfxBridge.gd")
const FootprintScript = preload("res://src/presentation/battle/effects/HexVfxFootprint.gd")
const BattleMapDefinitionScript = preload("res://src/entities/BattleMapDefinition.gd")
const HexGridScript = preload("res://src/board/HexGrid.gd")

var failures: Array[String] = []
var _root: Node3D


func _init() -> void:
	_root = Node3D.new()
	root.add_child(_root)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


## Profiles the bridge serves through a hex subclass, and those it serves with the donor itself.
func _split() -> Dictionary:
	var area: Array[String] = []
	var body: Array[String] = []
	for row: Dictionary in BridgeScript.coverage():
		if str(row["binding"]) == BridgeScript.BINDING_AREA:
			area.append(str(row["profile_id"]))
		else:
			body.append(str(row["profile_id"]))
	return {"area": area, "body": body}


## One profile per hex class, so a mix names classes rather than repeating Solar Storm six times.
func _oneAreaProfilePerClass(area: Array[String]) -> Array[String]:
	var seen := {}
	var picked: Array[String] = []
	for profileID: String in area:
		var hexClass := ""
		for row: Dictionary in BridgeScript.coverage():
			if str(row["profile_id"]) == profileID:
				hexClass = str(row["hex_class"])
		if hexClass.is_empty() or seen.has(hexClass):
			continue
		seen[hexClass] = true
		picked.append(profileID)
	return picked


func _selected(environmentKey: String, available: Array[String]) -> Array[String]:
	var raw := OS.get_environment(environmentKey)
	if raw.is_empty():
		return available
	if raw == "none":
		return []
	var wanted: Array[String] = []
	for token in raw.split(","):
		var name := str(token).strip_edges()
		for profileID: String in available:
			if profileID.contains(name):
				wanted.append(profileID)
	return wanted


func _run() -> void:
	var split := _split()
	# ALL profiles, not one per class, when asked: Solar Storm alone maps six catalog ids onto
	# one class, and whether that repetition matters is exactly what bisection has to answer.
	var area: Array[String] = split["area"] if not OS.get_environment("HXB_SHUTDOWN_ALL").is_empty() else _oneAreaProfilePerClass(split["area"])
	var body: Array[String] = split["body"]

	var chosenArea := _selected("HXB_SHUTDOWN_HEX", area)
	var chosenBody := _selected("HXB_SHUTDOWN_BODY", body)

	var footprint = _footprint() if not OS.get_environment("HXB_SHUTDOWN_FOOTPRINT").is_empty() else null
	var built := 0
	for profileID: String in chosenArea + chosenBody:
		var playback: VfxPlayback = BridgeScript.createPlayback(
			profileID, _root, Vector3.ZERO, Color.WHITE, footprint, null, {}
		)
		if playback == null:
			failures.append("the bridge served nothing for '%s'" % profileID)
			continue
		playback.play(1, VfxPlayback.MODE_BATTLE)
		playback.skip_to_settle()
		playback.dispose()
		built += 1

	print("mix: %d hex-served + %d donor-served, footprint=%s" % [
		chosenArea.size(), chosenBody.size(), footprint != null
	])
	print("hex:   %s" % [chosenArea])
	print("donor: %s" % [chosenBody])
	_require(built == chosenArea.size() + chosenBody.size(),
		"built %d playbacks for %d profiles" % [built, chosenArea.size() + chosenBody.size()])

	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_SHUTDOWN_FAILURE: %s" % failure)
		quit(1)
		return
	# Measured before quit, because the fault happens during cleanup and takes the leak report
	# with it -- these counters are the only view of the retained graph that survives.
	print("alive at quit: objects=%d resources=%d nodes=%d orphans=%d" % [
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	])
	# Everything this probe checks has passed. What happens after quit() is the bug.
	print("HXB_SHUTDOWN_OK")
	quit(0)


func _footprint() -> HexVfxFootprint:
	var map: BattleMapDefinition = BattleMapDefinitionScript.new()
	map.boardSize = Vector2i(21, 21)
	map.terrainDefinitions = {"clear": {"traversable": true, "stoppable": true, "movement_cost": 1}}
	var cells: Array[Vector2i] = []
	var data := {}
	for y in range(21):
		for x in range(21):
			cells.append(Vector2i(x, y))
			data[Vector2i(x, y)] = {"terrain": "clear", "height": 0}
	map.configureCells(cells, data)
	return FootprintScript.fromCells(HexGridScript.disc(Vector2i(10, 10), 2), map)
