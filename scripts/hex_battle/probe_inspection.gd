## Inspection on the hex board, end to end through the real controller: every deployed unit has a
## model, picking a unit's projected body selects that unit by its uniqueID, the readout shows its
## effects with their turns and collapses overflow, a selection whose unit leaves falls back to the
## acting member, and the STATUS sheet is modal and closes on Escape.
extends SceneTree

const HexBattleControllerScript = preload("res://src/systems/hex_battle/HexBattleController.gd")
const HexUnitFactsScript = preload("res://src/presentation/battle/ui/HexUnitFacts.gd")
const HexTextBoxScript = preload("res://src/presentation/battle/ui/HexTextBox.gd")

const SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"
const SEED := 42

## Presentation files that must only ever read battle state.
const READ_ONLY_FILES := [
	"res://src/presentation/battle/HexBattleHud.gd",
	"res://src/presentation/battle/ui/HexUnitFacts.gd",
	"res://src/presentation/battle/ui/HexUnitReadout.gd",
	"res://src/presentation/battle/ui/HexCharacterStatus.gd",
	"res://src/presentation/battle/ui/HexCommandMenu.gd",
	"res://src/presentation/battle/ui/HexCommandPlate.gd",
	"res://src/presentation/battle/ui/HexTextBox.gd",
]
const FORBIDDEN := [
	"get_instance_id(", "addEffect(", "removeEffect(", ".hitpoints =", "setMonsterPosition(",
	"Details", "MOVE ready", "ACTION ready",
]

var failures: Array[String] = []
var _controller: HexBattleController


func _init() -> void:
	_controller = HexBattleControllerScript.new()
	root.add_child(_controller)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_checkReadOnlySources()
	_checkFactsWording()

	var started := _controller.startBattle(SCENARIO, SEED)
	if not bool(started.get("ok", false)):
		failures.append("battle did not start: %s" % str(started.get("error", "")))
		return _report()
	await _frames(2)

	_checkEveryUnitHasAModel()
	if not await _openPlayerTurn():
		failures.append("no player member turn opened")
		return _report()
	await _checkPickingSelectsByID()
	await _checkEffectsAndOverflow()
	await _checkLostSelectionFallsBack()
	await _checkSheetIsModal()
	_report()


func _report() -> void:
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_INSPECT_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_INSPECT_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


## The controller refreshes the HUD once a frame; a couple of frames is enough for a change in
## state to reach the readout.
func _afterRefresh() -> void:
	await _frames(4)


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


# --- checks -----------------------------------------------------------------

func _checkReadOnlySources() -> void:
	for path in READ_ONLY_FILES:
		var source := FileAccess.get_file_as_string(path)
		_require(not source.is_empty(), "could not read %s" % path)
		for needle in FORBIDDEN:
			_require(not source.contains(needle), "%s contains '%s'" % [path, needle])


func _checkFactsWording() -> void:
	var guard := HexUnitFactsScript.effectFacts({
		"name": "guard", "remainingTurns": 2, "damage_multiplier": 0.5,
	})
	_require(str(guard["text"]).contains("x0.5"), "guard facts did not state its multiplier: %s" % guard["text"])
	_require(int(guard["turns"]) == 2, "guard facts lost its turns")
	var burn := HexUnitFactsScript.effectFacts({"name": "burn", "remainingTurns": 3, "damagePerTurn": 2})
	_require(bool(burn["negative"]), "burn was not read as harmful")
	_require(str(burn["text"]).contains("2 HP"), "burn facts did not state its damage: %s" % burn["text"])
	_require(HexUnitFactsScript.displayName("spd_debuff") == "Spd debuff", "effect names are not humanised")
	var lines := HexTextBoxScript.wrapText(
		"one two three four five six", 40.0, ThemeDB.fallback_font, 16
	)
	_require(lines.size() > 1, "a narrow wrap did not break the line")
	_require(" ".join(lines) == "one two three four five six", "wrapping lost or reordered words")


func _checkEveryUnitHasAModel() -> void:
	var alive := 0
	for id in _controller.sim.state.monsters:
		if _controller.sim.state.monsters[id].is_alive():
			alive += 1
			_require(_controller.adapter.modelFor(int(id)) != null, "unit %d has no model" % int(id))
	_require(alive > 0, "the scenario deployed no units")


func _openPlayerTurn() -> bool:
	for _attempt in range(300):
		await _frames(1)
		var sideID := int(_controller.sim.state.activeSideID)
		if sideID == -1:
			continue
		if _controller._sideController(sideID) != "player" or not _controller.playback.isIdle():
			continue
		var eligible := _controller.sim.eligibleSideUnitIDs()
		if eligible.is_empty():
			continue
		_controller._onHudMemberSelected(int(eligible[0]))
		await _frames(1)
		return _controller.memberTurn != null
	return false


func _checkPickingSelectsByID() -> void:
	var memberID := _controller.memberTurn.monsterID()
	_require(_controller.hud.selectedUnit() == memberID, "opening a turn did not select the acting member")
	_require(_controller.adapter.selectedUnit() == memberID, "the board ring is not on the acting member")

	var other := _otherUnit(memberID)
	if other == -1:
		failures.append("no second unit to pick")
		return
	var model: Node3D = _controller.adapter.modelFor(other)
	var base: Vector3 = model.global_position
	var head: Vector3 = base + Vector3.UP * HexBattleUnitBadges.anchorHeight(model)
	var point := _controller.stage.projectWorldToScreen(base.lerp(head, 0.4))
	var picked := _controller.adapter.unitAtScreenPoint(
		point, _controller.stage.projectWorldToScreen)
	_require(picked == other, "picking unit %d's body answered %d" % [other, picked])

	_controller._selectUnit(other)
	await _frames(1)
	_require(_controller.hud.selectedUnit() == other, "selecting %d left the HUD on %d" % [other, _controller.hud.selectedUnit()])
	_require(_controller.hud.readout.unitID() == other, "the readout is not showing unit %d" % other)
	_require(_controller.adapter.selectedUnit() == other, "the ring did not follow the selection")
	_controller.adapter.setHoveredUnit(other)
	_require(_controller.adapter.hoveredUnit() == other, "hover did not take unit %d" % other)
	_require(_controller.adapter.selectedUnit() == other, "hovering disturbed the selection")


func _checkEffectsAndOverflow() -> void:
	var target := _controller.hud.selectedUnit()
	# Probe-only setup: effects added straight into state to have something to display.
	var names := ["burn", "poison", "chill", "petrify", "guard", "focus", "atk_buff", "def_buff"]
	for index in range(names.size()):
		_controller.sim.state.addEffect(target, names[index], index + 1)
	# The readout reads DISPLAYED effects, which only change when playback shows them; this probe
	# writes straight to state, so the adapter is told to re-read what is there.
	_controller.adapter._displayState.recover(_controller.sim.state)
	_controller.adapter.statusBadges().refreshAll()
	await _afterRefresh()
	var facts := _controller.hud.readout.facts()
	var effects: Array = facts.get("effects", [])
	_require(effects.size() == names.size(), "readout facts carry %d effects, expected %d" % [effects.size(), names.size()])
	for fact in effects:
		var expectedTurns := names.find(str(fact.get("name", ""))) + 1
		_require(int(fact.get("turns", -1)) == expectedTurns,
			"%s shows %d turns, expected %d" % [fact.get("name", ""), int(fact.get("turns", -1)), expectedTurns])
	var cells: Array = _controller.hud.readout._effectCells
	var shown := 0
	var hidden := 0
	for cell in cells:
		if cell.has("fact"):
			shown += 1
		elif cell.has("overflow"):
			hidden += (cell["overflow"] as Array).size()
	_require(shown + hidden == names.size(), "readout shows %d and hides %d of %d effects" % [shown, hidden, names.size()])
	_require(hidden > 0, "eight effects did not overflow the readout's one row")
	_require(_controller.adapter.statusBadges().rowCount() >= 1,
		"no status icon row over the affected unit")


func _checkLostSelectionFallsBack() -> void:
	var gone := _controller.hud.selectedUnit()
	var memberID := _controller.memberTurn.monsterID()
	if gone == memberID:
		failures.append("expected a non-acting unit to be selected")
		return
	# Probe-only: the unit leaves the way PLAYBACK removes it. A defeat event only queues the
	# removal -- the readout follows displayed state, so a unit the screen has not yet shown falling
	# is still a unit worth reading out.
	_controller.sim.state.getMonster(gone).hitpoints = 0
	_controller.adapter._displayState.markRemoved(gone, "defeated")
	_controller.adapter.removeDisplayedModel(gone)
	await _afterRefresh()
	_require(_controller.hud.selectedUnit() == memberID,
		"a lost selection went to %d, not back to the acting member %d" % [_controller.hud.selectedUnit(), memberID])
	_require(_controller.adapter.selectedUnit() == memberID, "the ring did not return to the acting member")


func _checkSheetIsModal() -> void:
	var memberID := _controller.memberTurn.monsterID()
	_require(_controller.hud.openStatus(memberID), "STATUS did not open for the acting member")
	_require(_controller.hud.isModalOpen(), "the sheet did not report itself modal")
	var phase := _controller.memberInput.phase()
	_pushKey(KEY_DOWN)
	_pushKey(KEY_ENTER)
	await _frames(1)
	_require(_controller.memberInput.phase() == phase, "keys reached the member turn through the open sheet")
	_require(_controller.hud.statusSheet.unitID() == memberID, "the sheet is not showing the acting member")
	_pushKey(KEY_RIGHT)
	await _frames(1)
	_require(_controller.hud.statusSheet.currentTab() == 1, "Right did not change the sheet's tab")
	_pushKey(KEY_ESCAPE)
	await _frames(1)
	_require(not _controller.hud.isModalOpen(), "Escape did not close the sheet")
	_require(not _controller.hud.commandMenu.visible and _controller.sideCues._arc.visible,
		"closing STATUS did not return to the side-turn action arc")


func _otherUnit(except: int) -> int:
	for id in _controller.sim.state.monsters:
		if int(id) != except and _controller.sim.state.monsters[id].is_alive():
			return int(id)
	return -1


func _pushKey(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	root.push_input(event)
