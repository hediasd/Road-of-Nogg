## HPR-6: tactical inspection and a truthful party HUD.
##
## What this proves, and what it cannot. It checks the HUD's view models against known fixtures
## and against the simulator and adapter they are supposed to read, that hover and inspection
## never change selection, aim, overlays or battle state, that forecasts and disabled rows say
## what the rules say, that GUI rows consume their clicks, and that the panels dock inside a
## 1280x720 screen without overlapping. It cannot judge whether any of it reads well. That is
## HPR-8's rendered check.
##
## Fixtures are built in memory from a shipping scenario. Nothing is written to disk.

extends SceneTree

const HexBattleControllerScript = preload("res://src/systems/hex_battle/HexBattleController.gd")
const HudScript = preload("res://src/presentation/battle/HexBattleHud.gd")
const MemberInputScript = preload("res://src/systems/hex_battle/HexBattleMemberInput.gd")
const PartyOrderPanelScript = preload("res://src/presentation/battle/ui/HexPartyOrderPanel.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const ElementReferencesScript = preload("res://src/factories/ElementReferences.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"
const SEED := 42
const SCREEN := Vector2i(1280, 720)
const CPU_FRAMES := 2400

var failures: Array[String] = []
var _controller: HexBattleController
var _panelRows: Dictionary = {}
var _menuRows: Dictionary = {}
var _evidence: Dictionary = {}


## A displayed-state reader the probe controls, so "shown" and "authoritative" can disagree on
## purpose.
class DisplayStub:
	var hp: Dictionary = {}
	var effects: Dictionary = {}
	var removed: Dictionary = {}

	func displayedHitpoints(monsterID: int) -> int:
		return int(hp.get(monsterID, -1))

	func displayedEffects(monsterID: int) -> Array:
		return (effects.get(monsterID, []) as Array).duplicate(true)

	func displayedRemovalReason(monsterID: int) -> String:
		return str(removed.get(monsterID, ""))


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	# Set after the first frame: a headless root assigned in _init comes back at its 64x64 default.
	root.size = SCREEN
	_checkPartyModel()
	_checkInspectionModel()
	_checkPartyOrderModel()
	_checkSpellDetails()
	_checkAimLines()
	await _checkLiveBattle()
	_report()


func _report() -> void:
	print("HPR_INSPECTION_EVIDENCE %s" % JSON.stringify(_evidence))
	if _controller != null:
		_controller.teardownBattle()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HPR_INSPECTION_FAILURE: %s" % failure)
		quit(1)
		return
	print("HPR_INSPECTION_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)


func _fixtureState() -> BattleState:
	var config: BattleSetupConfig = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIO
	config.seed = SEED
	var result := BattleSetupFactoryScript.createHexState(config)
	_require(bool(result.get("success", false)), "fixture state could not be built")
	return result.get("state")


# --- static models ------------------------------------------------------------

## Spent, fallen and withdrawn are three facts, and "ineligible" is none of them.
func _checkPartyModel() -> void:
	var state := _fixtureState()
	if state == null:
		return
	# Party 10: commander 100, member 101. Party 11: commander 102, member 103.
	state.activePartyID = 10
	state.roundCount = 1

	# Mid-turn: the simulator reports nobody eligible while 100 acts. Nobody is "done".
	var midTurn := HudScript.partyModel(state, [], 10, 100, true, null)
	var byID := _membersByID(midTurn)
	_require(bool(byID[100]["active"]) and bool(byID[100]["commander"]),
		"the acting commander was not marked active and commander")
	_require(not bool(byID[101]["spent"]),
		"a member who has not acted was called spent because nobody was eligible mid-turn")
	_require(not bool(midTurn["can_end_party"]),
		"End Party was offered while a member turn was open")

	# 101 has acted.
	state.spentMemberIDs[101] = true
	var afterAct := _membersByID(HudScript.partyModel(state, [100], 10, -1, true, null))
	_require(bool(afterAct[101]["spent"]) and not bool(afterAct[101]["eligible"]),
		"an acted member was not spent and ineligible")
	_require(bool(afterAct[100]["eligible"]) and not bool(afterAct[100]["spent"]),
		"an eligible member was misreported")

	# A different party's spent set is not this party's.
	var otherParty := _membersByID(HudScript.partyModel(state, [], 11, -1, false, null))
	_require(not bool(otherParty[103]["spent"]),
		"a member of an inactive party read the active party's spent set")

	# Displayed removal: shown fallen before the simulator agrees, and shown standing after it does.
	var display := DisplayStub.new()
	display.removed[101] = "defeated"
	var shown := _membersByID(HudScript.partyModel(state, [100], 10, -1, true, display))
	_require(bool(shown[101]["defeated"]) and not bool(shown[101]["withdrawn"]),
		"a member shown falling was not reported down")
	state.getMonster(100).hitpoints = 0
	var notYet := _membersByID(HudScript.partyModel(state, [], 10, -1, true, DisplayStub.new()))
	_require(not bool(notYet[100]["defeated"]),
		"a member was reported down before its fall was shown")
	state.getMonster(100).hitpoints = state.getMonster(100).max_hitpoints

	# Authoritative fallback, and withdrawal as its own word.
	state.withdrawMonster(103)
	var withdrawn := _membersByID(HudScript.partyModel(state, [], 11, -1, false, null))
	_require(bool(withdrawn[103]["withdrawn"]) and not bool(withdrawn[103]["defeated"]),
		"a withdrawn member was not reported withdrawn")

	# The panel's words for them.
	var panel := HexPartyPanel.new()
	_require(panel._memberStatus({"defeated": true, "spent": true}) == "DOWN",
		"a member who acted and then fell did not read DOWN")
	_require(panel._memberStatus({"withdrawn": true, "commander": true}) == "CMD OUT",
		"a withdrawn commander did not read CMD OUT")
	_require(panel._memberStatus({"spent": true}) == "DONE", "a spent member did not read DONE")
	panel.free()


func _membersByID(model: Dictionary) -> Dictionary:
	var result := {}
	for entry in model.get("members", []):
		result[int(entry["id"])] = entry
	return result


## HP and effects are the shown ones; the rest is the monster's.
func _checkInspectionModel() -> void:
	var state := _fixtureState()
	if state == null:
		return
	var monster = state.getMonster(102)
	var authoritative := HudScript.inspectionModel(state, null, 102)
	_require(int(authoritative["hp"]) == int(monster.hitpoints)
		and int(authoritative["max_hp"]) == int(monster.max_hitpoints),
		"authoritative inspection HP disagrees with the monster")
	_require(int(authoritative["level"]) == int(monster.level) and int(authoritative["level"]) == 4,
		"inspection level is not the scenario's level 4")
	_require(bool(authoritative["commander"]) and str(authoritative["side"]) == "Commander",
		"Mage Dragon was not shown as its party's commander")
	_require(str(authoritative["state"]) == "T1 PLAYER",
		"a standing player unit's state read %s" % authoritative["state"])
	_require(int(authoritative["atk"]) == int(monster.atk) and int(authoritative["def"]) == int(monster.def)
		and int(authoritative["speed"]) == int(monster.speed) and int(authoritative["move"]) == int(monster.move),
		"inspection stats disagree with the monster")
	var elements: Array = authoritative["elements"]
	_require(elements.size() == mini(monster.elements.size(), 3),
		"inspection element count disagrees with the monster")
	monster.resonance_bars[str(monster.elements[0])] = 2
	var charged := HudScript.inspectionModel(state, null, 102)
	var first: Dictionary = (charged["elements"] as Array)[0]
	_require(str(first["code"]) == ElementReferencesScript.code(str(monster.elements[0]))
		and int(first["charge"]) == 2,
		"inspection Resonance did not follow the monster's charge")

	var member := HudScript.inspectionModel(state, null, 103)
	_require(str(member["side"]) == "Mage Dragon's party" and not bool(member["commander"]),
		"a party member did not name its commander's party")

	var display := DisplayStub.new()
	display.hp[102] = int(monster.hitpoints) + 7
	display.effects[102] = [{"name": "burn", "remainingTurns": 2}]
	var shown := HudScript.inspectionModel(state, display, 102)
	_require(int(shown["hp"]) == int(monster.hitpoints) + 7,
		"inspection HP read authoritative state instead of the shown HP")
	var effects: Array = shown["effects"]
	_require(effects.size() == 1 and str(effects[0]["label"]) == "Burn"
		and int(effects[0]["turns"]) == 2,
		"inspection effects did not come from the shown effects")
	state.activeEffects[102] = [{"name": "poison", "remainingTurns": 5}]
	_require((HudScript.inspectionModel(state, display, 102)["effects"] as Array).size() == 1,
		"an effect not yet shown leaked into the readout")

	display.removed[203] = "withdrawn"
	_require(str(HudScript.inspectionModel(state, display, 203)["state"]) == "T2 OUT",
		"a shown withdrawal did not read OUT")
	display.removed[203] = "defeated"
	_require(str(HudScript.inspectionModel(state, display, 203)["state"]) == "T2 DOWN",
		"a shown defeat did not read DOWN")
	_require(HudScript.inspectionModel(state, display, 999).is_empty()
		and HudScript.inspectionModel(state, display, -1).is_empty(),
		"an unknown unit produced a readout")


## The round's order is the simulator's frozen order; the words say where each party stands.
func _checkPartyOrderModel() -> void:
	var state := _fixtureState()
	if state == null:
		return
	_require(HudScript.partyOrderModel(state, null).is_empty(),
		"a party order was shown before any round opened")
	state.roundCount = 3
	state.partyOrder = [11, 20, 10, 21]
	state.activePartyID = 20
	state.pendingPartyIDs = [10, 21]
	var model := HudScript.partyOrderModel(state, null)
	var statuses := _orderStatuses(model)
	_require(int(model["round"]) == 3, "the party order did not carry the round")
	_require(_orderIDs(model) == [11, 20, 10, 21], "the party order did not keep partyOrder")
	_require(statuses == ["DONE", "ACTIVE", "NEXT", "#2"],
		"party order statuses were %s" % [statuses])

	# Party 10's commander has fallen but its fall has not been shown: it keeps its place.
	state.getMonster(100).hitpoints = 0
	var display := DisplayStub.new()
	_require(_orderStatuses(HudScript.partyOrderModel(state, display)) == ["DONE", "ACTIVE", "NEXT", "#2"],
		"a party was shown out before its commander's fall played")
	display.removed[100] = "defeated"
	_require(_orderStatuses(HudScript.partyOrderModel(state, display)) == ["DONE", "ACTIVE", "OUT", "NEXT"],
		"a party whose commander was shown falling did not read OUT")


func _orderStatuses(model: Dictionary) -> Array:
	var result := []
	for entry in model.get("parties", []):
		result.append(str(entry["status"]))
	return result


func _orderIDs(model: Dictionary) -> Array:
	var result := []
	for entry in model.get("parties", []):
		result.append(int(entry["id"]))
	return result


## Every refusal `can_cast` makes gets its own word, and a castable row keeps its range.
func _checkSpellDetails() -> void:
	var state := _fixtureState()
	if state == null:
		return
	var monster = state.getMonster(102)
	var owned := str(monster.elements[0])
	var missing := ""
	for candidate in ["fire", "water", "wood", "ice", "light", "dark", "steel", "wind", "earth"]:
		if not monster.elements.has(candidate):
			missing = candidate
			break
	var ready := Spell.new({"NAME": "Probe Bolt", "ELEMENT": owned, "RANGE": 4, "DAMAGE": 3})
	var selfSpell := Spell.new({"NAME": "Probe Ward", "ELEMENT": owned, "RANGE": 0,
		"TARGET_TYPE": "self", "DAMAGE_LINES": []})
	var foreign := Spell.new({"NAME": "Probe Foreign", "ELEMENT": missing, "RANGE": 2, "DAMAGE": 3})
	var finale := Spell.new({"NAME": "Probe Finale", "ELEMENT": owned, "RANGE": 3, "DAMAGE": 9,
		"SEQUENCE_LEVEL": 4, "RESONANCE_ELEMENT": owned})

	_require(MemberInputScript.spellDetail(monster, ready) == "Rng 4", "a ready spell did not show its range")
	_require(MemberInputScript.spellDetail(monster, selfSpell) == "Self", "a self spell did not read Self")
	monster.spell_cooldowns["Probe Bolt"] = 2
	_require(not monster.can_cast(ready) and MemberInputScript.spellDetail(monster, ready) == "CD 2",
		"a cooling spell did not show its remaining cooldown")
	_require(not missing.is_empty() and not monster.can_cast(foreign)
		and MemberInputScript.spellDetail(monster, foreign) == "No element",
		"a spell of a missing element did not say so")
	monster.resonance_bars[owned] = 1
	_require(not monster.can_cast(finale) and MemberInputScript.spellDetail(monster, finale) == "Res 1/3",
		"a sequence-4 spell short of Resonance did not show the charge it needs")
	monster.resonance_bars[owned] = 3
	_require(monster.can_cast(finale) and MemberInputScript.spellDetail(monster, finale) == "Rng 3",
		"a charged sequence-4 spell was not shown ready")

	_require(MemberInputScript.forecastWithheldReason(ready) == "", "a single-line spell forecast was withheld")
	_require(MemberInputScript.forecastWithheldReason(
		Spell.new({"NAME": "Probe Mend", "HEALS": true, "DAMAGE": 0})) == "heal",
		"a heal was forecast as damage")
	_require(MemberInputScript.forecastWithheldReason(Spell.new({"NAME": "Probe Duo",
		"DAMAGE_LINES": [{"damage": 3, "element": "fire"}, {"damage": 3, "element": "wind"}]}))
		== "", "a multi-line spell forecast was withheld")


## The forecast says what it knows, and no more.
func _checkAimLines() -> void:
	var state := _fixtureState()
	if state == null:
		return
	var enemy := 200
	var exact := {"available": true, "minimum": 11, "maximum": 11, "critical_chance": 0.0,
		"exact": true, "target_hitpoints": 30, "lethal": false, "possibly_lethal": false,
		"reactive_risk": false}
	var lines := HudScript.aimLines(state, {"kind": "attack", "legal": true, "reason": "",
		"target_id": enemy, "forecast": exact, "withheld": ""})
	_require(lines == ["Attack on Oracle of Ages", "11 dmg", "Confirm to act"],
		"exact attack lines were %s" % [lines])

	var crit := exact.duplicate()
	crit.merge({"minimum": 8, "maximum": 12, "critical_chance": 0.05, "exact": false,
		"possibly_lethal": true, "reactive_risk": true}, true)
	_require(HudScript.damageText(crit) == "8 dmg, 12 crit (5%) KO on crit, reacts first",
		"conditional forecast read %s" % HudScript.damageText(crit))
	var lethal := exact.duplicate()
	lethal["lethal"] = true
	_require(HudScript.damageText(lethal) == "11 dmg KO", "a lethal forecast did not say KO")

	var illegal := HudScript.aimLines(state, {"kind": "spell", "spell": "Probe Bolt", "legal": false,
		"reason": "invalid_spell_target", "target_id": -1, "forecast": {"available": false},
		"withheld": ""})
	_require(illegal == ["Probe Bolt on empty cell", "Cannot cast there"],
		"an illegal empty-cell cast read %s" % [illegal])
	var heal := HudScript.aimLines(state, {"kind": "spell", "spell": "Probe Mend", "legal": true,
		"reason": "", "target_id": enemy, "forecast": {}, "withheld": "heal"})
	_require(heal.size() == 3 and heal[1] == "Heals; no damage forecast",
		"a heal aim did not withhold its damage forecast")
	var move := HudScript.aimLines(state, {"kind": "move", "legal": false, "reason": "unreachable"})
	_require(move == ["Cannot move there", "Out of reach"], "an unreachable move read %s" % [move])
	var petrified := HudScript.aimLines(state, {"kind": "attack", "legal": false, "reason": "petrify",
		"target_id": enemy, "forecast": exact, "withheld": ""})
	_require(petrified[petrified.size() - 1] == "Petrified", "a guard refusal was not named")
	_require(HudScript.aimLines(state, {}).is_empty(), "an empty aim produced forecast lines")


# --- the live battle ------------------------------------------------------------

func _checkLiveBattle() -> void:
	_controller = HexBattleControllerScript.new()
	root.add_child(_controller)
	await process_frame
	var started := _controller.startBattle(SCENARIO, SEED)
	if not bool(started.get("ok", false)):
		_require(false, "live battle did not start: %s" % str(started.get("error", "")))
		return
	_controller.hud.partyPanel._window.row_built.connect(
		func(row: Control, index: int): _panelRows[index] = row)
	_controller.hud.commandMenu._window.row_built.connect(_onMenuRowBuilt)
	_require(_controller.adapter._combat != null,
		"the live adapter has no combat resolver, so it cannot preview or forecast")

	if not await _awaitPlayerParty():
		_require(false, "no player activation opened")
		return
	await _frames(2)
	_checkWindowsHaveWidth()
	_checkPartyOrderLive()

	# Open the first member's turn through the panel.
	_clickRow(_panelRows.get(1))
	await _frames(2)
	if _controller.memberTurn == null:
		_require(false, "clicking the first member row did not open a turn")
		return
	var memberID := _controller.memberTurn.monsterID()
	await _frames(2)
	_require(_controller.hud.actorID() == memberID, "the acting member was not the committed actor")
	var actorModel = _controller.hud.inspection.drawnModel(_controller.hud.inspection.actorWindow)
	_require(int(actorModel.get("id", -1)) == memberID
		and int(actorModel.get("hp", -2)) == _controller.adapter.displayedHitpoints(memberID),
		"the actor readout did not show the acting member's shown HP")
	_checkPanelTruthMidTurn(memberID)
	_checkCommandRows(memberID)
	_checkLayout()
	await _checkHoverChangesNothing(memberID)
	await _checkAimForecast(memberID)
	_checkSpellForecastLines(memberID)
	await _checkGuiConsumesClicks()
	await _checkReadoutsFollowPlayback()


func _awaitPlayerParty() -> bool:
	for _frame in range(600):
		await process_frame
		var sim := _controller.sim
		if sim == null or sim.state.activePartyID == -1 or not _controller.playback.isIdle():
			continue
		var party = sim.state.parties.get(int(sim.state.activePartyID))
		if party != null and party.controller == "player":
			return true
	return false


func _checkWindowsHaveWidth() -> void:
	var window: NoggWindow = _controller.hud.partyPanel._window
	_require(window.size.x > 0.0, "the party panel window has no width, so every name is clipped")
	for width in window._row_available_widths:
		_require(float(width) > 0.0, "a party row label has no room to draw")


func _checkPartyOrderLive() -> void:
	var state := _controller.sim.state
	var drawn = _controller.hud.orderPanel._drawn
	_require(drawn is Dictionary and int(drawn.get("round", 0)) == state.roundCount,
		"the party order panel did not show the current round")
	var ids := _orderIDs(drawn if drawn is Dictionary else {})
	var expected := []
	for value in state.partyOrder:
		expected.append(int(value))
	_require(ids == expected, "the party order panel did not follow partyOrder")
	_evidence["round"] = state.roundCount
	_evidence["party_order"] = _orderStatuses(drawn if drawn is Dictionary else {})


func _checkPanelTruthMidTurn(memberID: int) -> void:
	var model: Dictionary = _controller.hud._partyModel
	var byID := _membersByID(model)
	var state := _controller.sim.state
	for id in byID:
		var entry: Dictionary = byID[id]
		_require(bool(entry["spent"]) == state.spentMemberIDs.has(int(id)),
			"the live party panel called member %d spent against the simulator" % int(id))
		_require(bool(entry["active"]) == (int(id) == memberID),
			"the live party panel misplaced the active member")


func _checkCommandRows(memberID: int) -> void:
	var monster = _controller.sim.state.getMonster(memberID)
	var model := _controller.memberInput.commandModel()
	var guard := _controller.memberTurn.phaseGuard()
	var spellRows := 0
	for entry in model.get("commands", []):
		var id := str(entry["id"])
		if not id.begins_with("spell:"):
			continue
		spellRows += 1
		var parts := id.split(":")
		var spell = monster.spellSets[int(parts[1])][int(parts[2])]
		var expected: bool = bool(guard["success"]) and _controller.memberTurn.canAct() \
			and monster.can_cast(spell)
		_require(bool(entry["enabled"]) == expected,
			"spell row %s enabled state disagrees with the rules" % spell.name)
		_require(str(entry["detail"]) == MemberInputScript.spellDetail(monster, spell),
			"spell row %s detail disagrees with its castability" % spell.name)
	_evidence["spell_rows"] = spellRows


## Every docked window lies inside 1280x720 and no two overlap.
func _checkLayout() -> void:
	var hud := _controller.hud
	var rects := {}
	rects["party"] = Rect2(hud.partyPanel.position, hud.partyPanel.windowSize())
	rects["order"] = Rect2(hud.orderPanel.position, hud.orderPanel.windowSize())
	rects["commands"] = Rect2(hud.commandMenu.position, hud.commandMenu.windowSize())
	var inspection = hud.inspection
	for window in [inspection.actorWindow, inspection.targetWindow, inspection.forecastWindow]:
		rects[window.name] = Rect2(window.position, Vector2(window.size.x, window.custom_minimum_size.y))
	var screen := Rect2(Vector2.ZERO, Vector2(SCREEN))
	var names := rects.keys()
	for name in names:
		var rect: Rect2 = rects[name]
		_require(rect.size.x > 0.0 and rect.size.y > 0.0, "HUD window %s has no size" % name)
		_require(screen.encloses(rect), "HUD window %s %s leaves the 1280x720 screen" % [name, rect])
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			var a: Rect2 = rects[names[i]]
			var b: Rect2 = rects[names[j]]
			_require(not a.intersects(b),
				"HUD windows %s and %s overlap at 1280x720" % [names[i], names[j]])
	_evidence["ui_scale"] = NoggThemeScript.ui_scale
	var serialized := {}
	for name in names:
		serialized[name] = str(rects[name])
	_evidence["layout_720p"] = serialized


## Hover changes the readout it routes to, and nothing else at all.
func _checkHoverChangesNothing(memberID: int) -> void:
	var hud := _controller.hud
	var enemyID := _pointableUnit(func(id: int): return int(_controller.sim.state.getMonster(id).team) != 1)
	var allyID := _pointableUnit(func(id: int): return int(_controller.sim.state.getMonster(id).team) == 1 and id != memberID)
	_require(enemyID >= 0, "no enemy unit could be pointed at on the board")
	if enemyID < 0:
		return
	var before := _battleFingerprint()
	var committedActor := hud.actorID()
	var committedTarget := hud.targetID()

	_pushMotion(_screenPointOf(enemyID))
	await _frames(2)
	_require(hud.hoverID() == enemyID, "pointing at an enemy did not hover it")
	_require(int(hud.inspection.drawnModel(hud.inspection.targetWindow).get("id", -1)) == enemyID,
		"a hovered enemy did not fill the target readout")
	_require(hud.actorID() == committedActor and hud.targetID() == committedTarget,
		"hover replaced a committed readout")
	_require(_battleFingerprint() == before, "hovering an enemy changed battle, cursor or overlay state")

	if allyID >= 0:
		_pushMotion(_screenPointOf(allyID))
		await _frames(2)
		_require(int(hud.inspection.drawnModel(hud.inspection.actorWindow).get("id", -1)) == allyID,
			"a hovered ally did not draw over the actor readout")
		_require(hud.actorID() == memberID, "hovering an ally replaced the committed actor")

	# Off the board: the readout returns to the committed member.
	_pushMotion(Vector2(2.0, float(SCREEN.y) * 0.5))
	await _frames(2)
	_require(hud.hoverID() == -1, "leaving the units did not clear hover")
	_require(int(hud.inspection.drawnModel(hud.inspection.actorWindow).get("id", -1)) == memberID,
		"the actor readout did not return to the committed member")
	_require(_battleFingerprint() == before, "a hover sweep changed battle, cursor or overlay state")
	_evidence["hovered_enemy"] = enemyID
	_evidence["hovered_ally"] = allyID


## Aiming shows the simulator's legality and the adapter's forecast; a hover mid-aim keeps the aim.
## A spell forecast prices every damage line with its own element under one critical roll, and
## refuses a heal. Probe spells are put on the member for the check and taken off again.
func _checkSpellForecastLines(memberID: int) -> void:
	var sim := _controller.sim
	var caster = sim.state.getMonster(memberID)
	var enemy := -1
	for value in sim.state.monsters:
		var candidate = sim.state.getMonster(int(value))
		if candidate != null and candidate.is_alive() and int(candidate.team) != int(caster.team):
			enemy = int(value)
			break
	if enemy < 0:
		_require(false, "no enemy to forecast a spell against")
		return
	var target = sim.state.getMonster(enemy)
	var targetPos: Vector2i = sim.state.getMonsterPosition(enemy)
	# The caster's own element on one line and none on the other, so `can_cast` admits it and the
	# two lines still price differently.
	var ownElement := str(caster.elements[0]) if not caster.elements.is_empty() else "none"
	var duo := Spell.new({"NAME": "Probe Duo",
		"DAMAGE_LINES": [{"damage": 3, "element": ownElement}, {"damage": 4, "element": "none"}]})
	var mend := Spell.new({"NAME": "Probe Mend", "HEALS": true, "DAMAGE": 5})
	caster.spellSets.append([duo, mend])
	var setIndex: int = caster.spellSets.size() - 1
	var expected := 0
	var expectedCritical := 0
	for line in duo.damage_lines:
		expected += sim.combatResolver.calculateSpellDamage(
			caster, target, int(line["damage"]), str(line["element"]), true, Vector2i(-1, -1), false)
		expectedCritical += sim.combatResolver.calculateSpellDamage(
			caster, target, int(line["damage"]), str(line["element"]), true, Vector2i(-1, -1), true)
	var forecast := _controller.adapter.forecastSpell(memberID, setIndex, 0, targetPos)
	var healForecast := _controller.adapter.forecastSpell(memberID, setIndex, 1, targetPos)
	caster.spellSets.pop_back()
	_require(bool(forecast.get("available", false))
		and int(forecast.get("minimum", -1)) == mini(expected, expectedCritical)
		and int(forecast.get("maximum", -1)) == maxi(expected, expectedCritical),
		"a two-line spell forecast %s is not the sum of its lines (%d, critical %d)" % [
			str(forecast), expected, expectedCritical])
	_require(not bool(healForecast.get("available", true)),
		"a heal was given a damage forecast: %s" % str(healForecast))
	_evidence["two_line_forecast"] = "%d-%d" % [int(forecast.get("minimum", -1)), int(forecast.get("maximum", -1))]


func _checkAimForecast(memberID: int) -> void:
	var input := _controller.memberInput
	_require(_chooseCommand("Attack"), "Attack was not offered to aim")
	await _frames(1)
	if input.phase() != HexBattleMemberInput.Phase.AIM_ATTACK:
		_require(false, "choosing Attack did not begin an aim")
		return
	var sim := _controller.sim
	var fromPos: Vector2i = sim.state.getMonsterPosition(memberID)
	var checkedCells := 0
	var sawIllegal := false
	for cell: Vector2i in _controller.map.validCells():
		if not input.aimAt(cell):
			continue
		var aim := input.aimModel()
		var legal: bool = sim.combatResolver.canBasicAttackPositionFrom(memberID, fromPos, cell)
		_require(bool(aim["legal"]) == legal, "aim legality at %s disagrees with the resolver" % cell)
		_require(aim["forecast"] == _controller.adapter.forecastAttack(memberID, cell),
			"aim forecast at %s is not the adapter's" % cell)
		sawIllegal = sawIllegal or not legal
		checkedCells += 1
		if checkedCells >= 12:
			break
	_require(sawIllegal, "no illegal attack cell was seen, so refusals were never shown")
	await _frames(2)
	var lines = _controller.hud.inspection.drawnModel(_controller.hud.inspection.forecastWindow)
	_require(lines == HudScript.aimLines(sim.state, input.aimModel()),
		"the forecast window did not draw the current aim")
	_require(_controller.hud.inspection.isRequestedOpen(_controller.hud.inspection.forecastWindow),
		"the forecast window was not open while aiming")

	var preview := _controller.adapter.previewCellCount()
	var reach := _controller.adapter.layerCellCount("reach")
	var enemyID := _pointableUnit(func(id: int): return int(sim.state.getMonster(id).team) != 1)
	if enemyID >= 0:
		_pushMotion(_screenPointOf(enemyID))
		await _frames(2)
		_require(input.phase() == HexBattleMemberInput.Phase.AIM_ATTACK, "a hover mid-aim cancelled the aim")
		_require(_controller.adapter.layerCellCount("reach") == reach,
			"a hover mid-aim erased the reach overlay")
		_require(_controller.adapter.previewCellCount() > 0 or preview == 0,
			"a hover mid-aim erased the preview overlay")
	_evidence["aim_cells_checked"] = checkedCells

	_pushKey(KEY_ESCAPE)
	await _frames(2)
	_require(input.phase() == HexBattleMemberInput.Phase.MENU, "escape did not end the aim")
	_require(not _controller.hud.inspection.isRequestedOpen(_controller.hud.inspection.forecastWindow),
		"the forecast stayed open after the aim ended")


## A click on a HUD row is the row's. It must not fall through to the board inspector.
func _checkGuiConsumesClicks() -> void:
	var hud := _controller.hud
	var row: Control = _panelRows.get(2)
	if row == null or not is_instance_valid(row):
		_require(false, "no party row to click through")
		return
	var sentinelActor := -77
	hud._actorID = sentinelActor
	hud._targetID = -78
	var centre := row.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = centre
	press.global_position = centre
	root.push_input(press)
	var release := press.duplicate()
	release.pressed = false
	root.push_input(release)
	await _frames(1)
	_require(hud._actorID == sentinelActor and hud._targetID == -78,
		"a click on a party row fell through to the board inspector")
	hud._actorID = _controller.memberTurn.monsterID() if _controller.memberTurn != null else -1
	hud._targetID = -1


## While CPU parties play, every readout shows displayed HP, never authoritative HP ahead of it.
func _checkReadoutsFollowPlayback() -> void:
	# End this member's turn and the party, then watch the CPU.
	if _controller.memberTurn != null:
		_chooseCommand("End turn")
		await _frames(2)
	var sim := _controller.sim
	var framesChecked := 0
	var aheadFrames := 0
	var removalsShown := 0
	for _frame in range(CPU_FRAMES):
		await process_frame
		if sim.state.battleOutcome != -1:
			break
		if _controller.memberTurn != null and not _controller.memberTurn.isFinished():
			_chooseCommand("End turn")
			continue
		if _isPlayerPartyWaiting():
			_controller.hud.end_party_requested.emit()
			continue
		for value in sim.state.monsters.keys():
			var id := int(value)
			var shownHP := _controller.adapter.displayedHitpoints(id)
			if shownHP < 0:
				continue
			var model := HudScript.inspectionModel(sim.state, _controller.adapter, id)
			_require(int(model["hp"]) == shownHP, "readout HP for %d is not the shown HP" % id)
			if shownHP != int(sim.state.getMonster(id).hitpoints):
				aheadFrames += 1
			if not _controller.adapter.displayedRemovalReason(id).is_empty():
				removalsShown += 1
		framesChecked += 1
		_controller.hud.refresh()
		var partyModel: Dictionary = _controller.hud._partyModel
		for entry in partyModel.get("members", []):
			var reason := _controller.adapter.displayedRemovalReason(int(entry["id"]))
			_require(bool(entry["defeated"]) == (reason == "defeated")
				and bool(entry["withdrawn"]) == (reason == "withdrawn"),
				"the party panel's down/out words disagree with what has been shown")
	_evidence["cpu_frames_checked"] = framesChecked
	_evidence["frames_authoritative_ahead_of_shown"] = aheadFrames
	_evidence["removal_samples"] = removalsShown
	_require(aheadFrames > 0,
		"authoritative HP never led the shown HP, so the probe never tested the difference")


func _isPlayerPartyWaiting() -> bool:
	var sim := _controller.sim
	if sim == null or sim.state.activePartyID == -1 or not _controller.playback.isIdle():
		return false
	var party = sim.state.parties.get(int(sim.state.activePartyID))
	return party != null and party.controller == "player"


# --- helpers ----------------------------------------------------------------------

## A shown unit whose cell is on screen, outside every HUD window, and picked back as itself.
func _pointableUnit(filter: Callable) -> int:
	for value in _controller.adapter.shownModelIDs():
		var id := int(value)
		if not filter.call(id):
			continue
		var point := _screenPointOf(id)
		if point.x < 0.0 or not Rect2(Vector2.ZERO, Vector2(SCREEN)).has_point(point):
			continue
		if _underHudWindow(point):
			continue
		if _controller._unitAtPoint(point) == id:
			return id
	return -1


func _underHudWindow(point: Vector2) -> bool:
	var hud := _controller.hud
	var rects := [
		Rect2(hud.partyPanel.position, hud.partyPanel.windowSize()),
		Rect2(hud.orderPanel.position, hud.orderPanel.windowSize()),
		Rect2(hud.commandMenu.position, hud.commandMenu.windowSize()),
	]
	for window in [hud.inspection.actorWindow, hud.inspection.targetWindow, hud.inspection.forecastWindow]:
		rects.append(Rect2(window.position, Vector2(window.size.x, window.custom_minimum_size.y)))
	for rect: Rect2 in rects:
		if rect.grow(4.0).has_point(point):
			return true
	return false


func _screenPointOf(monsterID: int) -> Vector2:
	var cell := _controller.adapter.displayedPosition(monsterID)
	return _controller._projectCell(cell)


func _battleFingerprint() -> String:
	var input := _controller.memberInput
	return JSON.stringify({
		"snapshot": _controller.sim.createReplaySnapshot(),
		"phase": input.phase() if input != null else -1,
		"cursor": str(input.cursorCell()) if input != null else "",
		"reach": _controller.adapter.layerCellCount("reach"),
		"hover_layer": _controller.adapter.layerCellCount("hover"),
		"threat": _controller.adapter.layerCellCount("threat"),
		"target": _controller.adapter.layerCellCount("target"),
		"preview": _controller.adapter.previewCellCount(),
		"owner": _controller.playback.owner(),
		"member": _controller.memberTurn.monsterID() if _controller.memberTurn != null else -1,
	})


func _pushMotion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event)


func _pushKey(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	root.push_input(event)


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _clickRow(row: Control) -> void:
	if row == null:
		return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	row.gui_input.emit(event)


func _onMenuRowBuilt(row: Control, index: int) -> void:
	if index == 0:
		_menuRows.clear()
	_menuRows[index] = row


func _chooseCommand(label: String) -> bool:
	for index in _menuRows:
		var row = _menuRows[index]
		if not is_instance_valid(row):
			continue
		var clip: Control = row.get_child(0)
		if clip.get_child_count() > 0 and str((clip.get_child(0) as Label).text) == label:
			_clickRow(row)
			return true
	return false
