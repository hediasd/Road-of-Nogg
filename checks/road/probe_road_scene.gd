extends SceneTree

## What this proves: the road scene works end to end through its real nodes. It opens on the road
## with the company panel and markers; a click on a stop's drawn position picks that stop; a locked
## stop refuses travel; travelling to the open stop walks the token, hides the map and runs an
## embedded battle (the CPU plays the company's side here); its completion pays Belief, saves, and
## shows the result; continuing frees the battle and brings the map back; a fresh scene resumes
## from the save exactly; and leaving a battle early pays nothing.
##
## What it cannot prove: that any of it reads well. That is Henri's playthrough.

const RoadSaveScript = preload("res://road/RoadSave.gd")

const ROAD_SCENE := "res://scenes/Road.tscn"
const SAVE_DIR := "user://road_scene_probe"
const MAX_FRAMES := 60000
const MARKER := "ROAD_SCENE_OK"

var failures: Array[String] = []
var opened: Array[int] = []
var closed: Array[Dictionary] = []


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_clearSaves()
	var road = await _openRoad()
	if road != null:
		await _checkOpening(road)
		await _checkBattle(road)
		var saved: Dictionary = road.state.toDictionary()
		road.queue_free()
		await _frames(3)
		var resumed = await _openRoad()
		if resumed != null:
			_require(resumed.state.toDictionary() == saved, "a fresh road scene did not resume from the save exactly")
			await _checkLeaving(resumed)
			resumed.queue_free()
			await _frames(3)
	_clearSaves()
	for failure in failures:
		printerr("ROAD_SCENE_FAILURE: %s" % failure)
	if failures.is_empty():
		print(MARKER)
	quit(0 if failures.is_empty() else 1)


func _openRoad():
	var road = load(ROAD_SCENE).instantiate()
	road.saveDirectory = SAVE_DIR
	road.autoplay = true
	road.battle_opened.connect(func(stopIndex: int) -> void: opened.append(stopIndex))
	road.battle_closed.connect(func(report: Dictionary) -> void: closed.append(report))
	root.add_child(road)
	await _frames(3)
	_require(not road.road.is_empty(), "the road did not load: %s" % road._notice)
	return road if not road.road.is_empty() else null


func _checkOpening(road) -> void:
	_require((road.road["stops"] as Array).size() == 4, "the road scene should show four stops")
	_require(road.markers.stopWorldPositions().size() == 4, "the markers should draw four stops")
	_require(road.markers.find_child("CompanyToken", true, false) != null, "the company token is missing")
	_require(road.panel.find_child("TravelButton", true, false) != null, "the panel has no travel action")
	_require(road.panel.find_child("Slot0", true, false) != null and road.panel.find_child("Slot5", true, false) != null,
		"the panel does not list the whole company")
	for index in range(4):
		_require(road.stopAtScreen(road.stopScreenPosition(index)) == index,
			"clicking where stop %d is drawn does not pick it" % (index + 1))
	road.travelTo(1)
	await _frames(2)
	_require(road.battle == null and opened.is_empty(), "a locked stop let the company travel")


func _checkBattle(road) -> void:
	var beliefBefore := _fieldedBelief(road)
	road.travelTo(0)
	var frames := 0
	while road.battle == null:
		frames += 1
		if frames > 600:
			failures.append("travelling to the open stop never opened a battle: %s" % road._notice)
			return
		await process_frame
	_require(opened == [0], "battle_opened reported %s" % str(opened))
	_require(not road._display.visible and not road.panel._root.visible, "the map and panel stayed up during the battle")
	_require(road._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "the map kept rendering under the battle")
	road.battle.playback.setSpeed(4.0)
	while not road.panel.isShowingResult():
		frames += 1
		if frames > MAX_FRAMES:
			failures.append("the road battle never reported a result")
			return
		if road.battle != null:
			road.battle.skipAnimation()
		await process_frame
	var report: Dictionary = road.state.lastReport
	_require(str(report.get("outcome", "")) in ["won", "lost", "draw"], "the road battle reported %s" % str(report))
	_require(_fieldedBelief(road) > beliefBefore, "the road battle paid no Belief")
	var saved: Dictionary = RoadSaveScript.read(road.road, SAVE_DIR)
	_require(bool(saved["found"]) and bool(saved["ok"]) and saved["state"].toDictionary() == road.state.toDictionary(),
		"the paid battle was not saved")
	_require(road.panel.find_child("ContinueButton", true, false) != null, "the result has no way on")
	road.panel.result_closed.emit()
	await _frames(3)
	_require(road.battle == null, "continuing did not free the battle")
	_require(road._display.visible and road.panel._root.visible, "continuing did not bring the map back")
	_require(closed.size() == 1 and str(closed[0].get("outcome", "")) == str(report["outcome"]),
		"battle_closed reported %s" % str(closed))
	if str(report["outcome"]) == "won":
		_require(road.state.clearedCount == 1 and road.selectedStop == 1, "winning stop 1 did not open stop 2")
	print("road scene battle: %s at stop 1 in %d frames; fielded Belief %d -> %d" % [
		str(report["outcome"]), frames, beliefBefore, _fieldedBelief(road)])


func _checkLeaving(road) -> void:
	var beliefBefore := _fieldedBelief(road)
	opened.clear()
	closed.clear()
	road.travelTo(0)
	var frames := 0
	while road.battle == null:
		frames += 1
		if frames > 600:
			failures.append("the second journey never opened a battle")
			return
		await process_frame
	await _frames(5)
	road.battle.requestLeave()
	await _frames(3)
	_require(road.battle == null and road._display.visible, "leaving did not return to the map")
	_require(_fieldedBelief(road) == beliefBefore, "leaving early paid Belief")
	_require(closed.size() == 1 and closed[0].is_empty(), "leaving early reported a result: %s" % str(closed))
	_require(road._notice.contains("Nothing was earned"), "leaving early did not say so")


func _fieldedBelief(road) -> int:
	var total := 0
	for slot in road.state.fielded:
		total += road.state.beliefOf(slot)
	return total


func _clearSaves() -> void:
	var directory := ProjectSettings.globalize_path(SAVE_DIR)
	if not DirAccess.dir_exists_absolute(directory):
		return
	for fileName in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(fileName))
	DirAccess.remove_absolute(directory)


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
