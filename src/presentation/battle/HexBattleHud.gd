## The hex battle's on-screen chrome, composed: the party panel and the round's party order, the
## command rail, the prompt, the readout of the inspected unit, and the STATUS sheet. The session
## controls -- pause, speed, skip, restart -- are not here: they live in the battle's debug drawer,
## because driving playback is not part of playing a battle.
##
## ONE FRAME. Every box here is a `NoggWindow` under the active skin -- by default the Brigandine
## plate frame cut from `assets/ui/briganborders.png` -- and the game theme is applied once, at the
## root, so every label inherits the skin's face. Nothing here draws a frame of its own.
##
## HOSTS THE PANELS RATHER THAN REIMPLEMENTING THEM. Each panel renders a supplied view model and
## reports clicks. This file places them, builds their models, and forwards their signals. The
## panels stay ignorant of `BattleState`, which is what lets them be tested without one.
##
## TWO SOURCES, AND WHICH ANSWERS WHAT.
##   Displayed state (the adapter's `displayed*` readers): HP, effects, and whether a unit has been
##   shown falling or withdrawing. The simulation runs ahead of playback, so these must come from
##   what the screen has shown, or a readout drops HP before the hit lands.
##   Authoritative state (`BattleState`): who may be selected, the round's party order, levels,
##   stats, elements and Resonance. Eligibility is the input gate's question and has one owner.
##
## WHERE THINGS LIVE, AND WHY THEY NEVER MOVE:
##   top-left      party panel, with the round's party order under it
##   top-right     command rail while a member is choosing; the prompt in the same corner otherwise
##                 (the two never coexist, so the right edge is always "what to do now")
##   bottom-left   readout of the inspected unit, with effect explanations opening above it
##   centre        the STATUS sheet, modal, over a dimming shade
##   over units    status icon rows, projected by the adapter at playback time
##
## INSPECTION IS PRESENTATION STATE. A click selects a unit into the readout; hovering one draws
## over that selection without replacing it, and the readout returns to the selected unit when the
## pointer leaves. Nothing here selects a member, moves the cursor, cancels an aim or paints an
## overlay.
##
## THERE IS NO TURN ORDER RAIL. Ordinary member speed no longer schedules anything, so the square
## battle's speed rail would forecast an order that does not exist. `HexPartyOrderPanel` shows the
## order that does: parties, from `partyOrder` and `pendingPartyIDs`.

class_name HexBattleHud
extends CanvasLayer

const HexPartyPanelScript = preload("res://src/presentation/battle/ui/HexPartyPanel.gd")
const HexPartyOrderPanelScript = preload("res://src/presentation/battle/ui/HexPartyOrderPanel.gd")
const HexCommandMenuScript = preload("res://src/presentation/battle/ui/HexCommandMenu.gd")
const HexTextBoxScript = preload("res://src/presentation/battle/ui/HexTextBox.gd")
const HexUnitReadoutScript = preload("res://src/presentation/battle/ui/HexUnitReadout.gd")
const HexCharacterStatusScript = preload("res://src/presentation/battle/ui/HexCharacterStatus.gd")
const HexUnitFactsScript = preload("res://src/presentation/battle/ui/HexUnitFacts.gd")
const HexGraphicsPanelScript = preload("res://src/presentation/battle/ui/HexGraphicsPanel.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

signal member_selected(monsterID: int)
signal end_party_requested()
signal command_chosen(commandID: String)
signal command_cancelled()
## The inspected unit is gone -- defeated or withdrawn -- and the HUD dropped it.
signal selection_lost(monsterID: int)
## The STATUS sheet opened or closed; the board must not take input while it is open.
signal modal_changed(open: bool)

const REASON_DEFEATED := "defeated"
const REASON_WITHDRAWN := "withdrawn"

## Aim kinds, as `HexBattleMemberInput.aimModel` names them (its command ids). Spelled here rather
## than preloaded so presentation does not import the systems layer.
const AIM_MOVE := "move"
const AIM_ATTACK := "attack"
const AIM_SPELL := "spell"

## Plates the HUD gives meaning to itself. Neither is a battle command.
const STATUS_COMMAND := "status"
const ITEM_COMMAND := "item"

var partyPanel: HexPartyPanel
var commandMenu: HexCommandMenu
var prompt: HexTextBox
var readout: HexUnitReadout
var effectInfo: HexTextBox
var statusSheet: HexCharacterStatus
## Untyped: a brand-new `class_name` is not a usable bare type until the project rescans it
## (LEARNINGS, GDScript loading). The preloaded script constructs it.
var orderPanel

var _root: Control
var _modalShade: ColorRect

var _sim: BattleSimulator
## The displayed-state reader: anything with displayedHitpoints, displayedEffects and
## displayedRemovalReason. Untyped so probes can pass a stub; the battle passes its adapter.
var _display = null

var _partyID := -1
var _activeMemberID := -1
var _inputEnabled := false
var _selectedID := -1
var _hoverID := -1
var _aim: Dictionary = {}
var _promptText := ""
var _hoveredEffectKey := ""
## The party model last handed to the panel. The panel rebuilds its rows on every update, so the
## per-frame refresh only hands it a model that differs.
var _partyModel: Dictionary = {}
## The command model last supplied, kept so a pause can redraw it without input.
var _commandModel: Dictionary = {}
## True while playback is paused: every row that would issue a command draws disabled.
var _inputLocked := false


func _init() -> void:
	name = "HexBattleHud"
	# GAME_LAYER, the square battle's UI layer, so the whole stack holds: status badges (layer 0)
	# under damage numbers (WORLD_EFFECT_LAYER) under the HUD, with the CRT overlay's
	# "UI through CRT" layer just above. At layer 1 the HUD sat under the numbers.
	layer = NoggThemeScript.GAME_LAYER
	# Before any child reads a token: every width and pitch below is a function of ui_scale.
	NoggThemeScript.configure_for_window_height(DisplayServer.window_get_size().y)

	_root = Control.new()
	_root.name = "HudRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The themed root: the Nogg face and body size cascade to every window, and the bitmap faces
	# must be point-sampled or every glyph blurs (UI_DESIGN §4b).
	_root.theme = NoggThemeScript.build_game_theme()
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_root)

	partyPanel = HexPartyPanelScript.new()
	partyPanel.name = "PartyPanel"
	_root.add_child(partyPanel)
	partyPanel.member_selected.connect(func(id: int): member_selected.emit(id))
	partyPanel.end_party_requested.connect(func(): end_party_requested.emit())

	orderPanel = HexPartyOrderPanelScript.new()
	orderPanel.name = "PartyOrder"
	_root.add_child(orderPanel)

	commandMenu = HexCommandMenuScript.new()
	commandMenu.name = "CommandMenu"
	commandMenu.hide()
	_root.add_child(commandMenu)
	commandMenu.command_chosen.connect(func(id: String): command_chosen.emit(id))
	commandMenu.cancelled.connect(func(): command_cancelled.emit())
	commandMenu.local_requested.connect(_onLocalCommand)

	prompt = HexTextBoxScript.new()
	prompt.name = "Prompt"
	_root.add_child(prompt)

	readout = HexUnitReadoutScript.new()
	readout.name = "UnitReadout"
	_root.add_child(readout)

	effectInfo = HexTextBoxScript.new()
	effectInfo.name = "EffectInfo"
	_root.add_child(effectInfo)

	# Input-transparent on purpose: a click on the shade reaches the board handler, which is what
	# closes the sheet when the player clicks outside it.
	_modalShade = ColorRect.new()
	_modalShade.name = "ModalShade"
	_modalShade.color = NoggThemeScript.HEX_MODAL_SHADE
	_modalShade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modalShade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modalShade.visible = false
	_root.add_child(_modalShade)

	statusSheet = HexCharacterStatusScript.new()
	statusSheet.name = "StatusSheet"
	_root.add_child(statusSheet)
	statusSheet.closed.connect(_onSheetClosed)


func _ready() -> void:
	prompt.setWidth(NoggThemeScript.HEX_PROMPT_WIDTH)
	# The order panel sizes itself to the docked status width, which is narrower than this HUD's
	# party panel; stacked under it, the two read as one column and its rows stop colliding.
	orderPanel.window().size.x = NoggThemeScript.HEX_PARTY_WIDTH
	effectInfo.setWidth(NoggThemeScript.HEX_READOUT_WIDTH)
	get_viewport().size_changed.connect(_layout)
	_layout()


## The battle this HUD reads. `display` is the displayed-state reader; see `_display`.
func bind(sim: BattleSimulator, display) -> void:
	_sim = sim
	_display = display


# --- prompt -------------------------------------------------------------------

## Sentence-level instruction or refusal. Shown in the rail's corner whenever the rail is not up;
## while the rail is up, the focused plate's own hint already says what to do.
func setStatus(text: String) -> void:
	_promptText = text
	_refreshPrompt()


func statusText() -> String:
	return _promptText


func _refreshPrompt() -> void:
	if commandMenu.visible or statusSheet.isOpen():
		prompt.hideBox()
		return
	var lines := aimLines(_sim.state if _sim != null else null, _aim)
	var text := " ".join(lines) if not lines.is_empty() else _promptText
	if text.is_empty():
		prompt.hideBox()
		return
	prompt.showText(text, "", "", 3)
	_placePrompt()


# --- party ------------------------------------------------------------------

## Shows a party. Rendered immediately, and kept current by `refresh` afterwards.
func showParty(
	sim: BattleSimulator, partyID: int, activeMemberID: int, inputEnabled: bool
) -> void:
	if sim == null or partyPanel == null:
		return
	if _sim == null:
		_sim = sim
	_partyID = partyID
	_activeMemberID = activeMemberID
	_inputEnabled = inputEnabled
	_partyModel = partyModel(
		sim.state, sim.eligiblePartyMemberIDs(), partyID, activeMemberID,
		inputEnabled and not _inputLocked, _display)
	partyPanel.updateModel(_partyModel)
	_layout()


func clearParty() -> void:
	_partyID = -1
	_activeMemberID = -1
	_inputEnabled = false
	_partyModel = {}
	if partyPanel != null:
		partyPanel.updateModel({})
	hideCommands()
	_layout()


## Builds the party panel's model.
##
## Eligibility is READ (`eligible` is the simulator's list), never derived here. The status words
## are facts about each member, not guesses from eligibility: while a member's turn is open the
## simulator reports nobody eligible, and a HUD that called every ineligible member "done" would
## mark the whole party spent mid-turn. Spent comes from the activation's own spent set; fallen
## and withdrawn come from displayed state, so a member is not shown down before the blow lands.
static func partyModel(
	state: BattleState, eligible: Array, partyID: int, activeMemberID: int,
	inputEnabled: bool, display = null
) -> Dictionary:
	if state == null:
		return {}
	var party = state.parties.get(partyID)
	if party == null:
		return {}
	var members: Array = []
	for value in party.memberIDs:
		var monsterID := int(value)
		var monster = state.getMonster(monsterID)
		if monster == null:
			continue
		var removal := removalReason(state, display, monsterID)
		members.append({
			"id": monsterID,
			"label": str(monster.name),
			"commander": monsterID == int(party.commanderID),
			"eligible": eligible.has(monsterID),
			"active": monsterID == activeMemberID,
			"spent": partyID == state.activePartyID and state.spentMemberIDs.has(monsterID),
			"defeated": removal == REASON_DEFEATED,
			"withdrawn": removal == REASON_WITHDRAWN,
		})
	return {
		"party_id": partyID,
		"label": partyLabel(state, partyID),
		"input_enabled": inputEnabled,
		"can_end_party": inputEnabled and not eligible.is_empty(),
		"members": members,
	}


## A party has no authored display name -- HXB-5 deliberately did not invent commander characters
## or titles -- so it is named by its commander, the member the player already knows it by.
static func partyLabel(state: BattleState, partyID: int) -> String:
	var party = state.parties.get(partyID) if state != null else null
	if party == null:
		return "Party %d" % partyID
	var commander = state.getMonster(int(party.commanderID))
	return "%s's party" % str(commander.name) if commander != null else "Party %d" % partyID


## "defeated", "withdrawn" or "" -- as shown when a reader is given, authoritatively otherwise.
static func removalReason(state: BattleState, display, monsterID: int) -> String:
	if display != null:
		return str(display.displayedRemovalReason(monsterID))
	if state == null:
		return ""
	if state.isMonsterWithdrawn(monsterID):
		return REASON_WITHDRAWN
	var monster = state.getMonster(monsterID)
	if monster == null or not monster.is_alive():
		return REASON_DEFEATED
	return ""


## The round's party order. Parties come from `partyOrder`, frozen at round start. Each is
## ACTIVE, NEXT or "#n" while still pending, DONE once it has had its activation this round, or
## OUT once its commander has been shown falling or withdrawing.
static func partyOrderModel(state: BattleState, display = null) -> Dictionary:
	if state == null or state.roundCount <= 0 or state.partyOrder.is_empty():
		return {}
	var parties: Array = []
	var pendingSeen := 0
	for value in state.partyOrder:
		var partyID := int(value)
		var party = state.parties.get(partyID)
		if party == null:
			continue
		var status := ""
		if partyID == state.activePartyID:
			status = HexPartyOrderPanelScript.STATUS_ACTIVE
		elif not removalReason(state, display, int(party.commanderID)).is_empty():
			status = HexPartyOrderPanelScript.STATUS_OUT
		elif state.pendingPartyIDs.has(partyID):
			pendingSeen += 1
			status = HexPartyOrderPanelScript.STATUS_NEXT if pendingSeen == 1 \
				else "#%d" % pendingSeen
		else:
			status = HexPartyOrderPanelScript.STATUS_DONE
		var commander = state.getMonster(int(party.commanderID))
		parties.append({
			"id": partyID,
			"label": str(commander.name) if commander != null else "Party %d" % partyID,
			"team": int(party.teamID),
			"status": status,
		})
	return {"round": int(state.roundCount), "parties": parties}


# --- command rail -------------------------------------------------------------

## Shows the acting member's rail. The model is built by whoever knows the turn; this adds the two
## plates only the HUD gives meaning to -- STATUS, and the not-yet-real Item -- and the spell
## descriptions, and places it.
func showCommands(model: Dictionary) -> void:
	if commandMenu == null:
		return
	if model.is_empty():
		hideCommands()
		return
	_commandModel = model.duplicate(true)
	commandMenu.updateModel(_lockedCommands(_decorate(_commandModel)))
	commandMenu.visible = not statusSheet.isOpen()
	_refreshPrompt()
	_layout()


func hideCommands() -> void:
	if commandMenu == null:
		return
	_commandModel = {}
	commandMenu.updateModel({})
	commandMenu.hide()
	_refreshPrompt()


func _lockedCommands(model: Dictionary) -> Dictionary:
	if not _inputLocked or model.is_empty():
		return model
	var locked := model.duplicate(true)
	locked["input_enabled"] = false
	return locked


## Locks or unlocks every command row, and redraws the party panel and rail at once so the rows say
## so. Called by the controller when playback pauses or resumes. The lock is only what the rows
## show; the controller refuses the commands themselves.
func setInputLocked(locked: bool) -> void:
	if _inputLocked == locked:
		return
	_inputLocked = locked
	if _sim != null and _partyID != -1:
		showParty(_sim, _partyID, _activeMemberID, _inputEnabled)
	if commandMenu != null and not _commandModel.is_empty():
		commandMenu.updateModel(_lockedCommands(_decorate(_commandModel)))


func isInputLocked() -> bool:
	return _inputLocked


func _decorate(model: Dictionary) -> Dictionary:
	var decorated := model.duplicate(true)
	var commands: Array = decorated.get("commands", [])
	var monster = _sim.state.getMonster(int(model.get("monster_id", -1))) if _sim != null else null
	var result: Array = []
	for entry in commands:
		var id := str(entry.get("id", ""))
		if id == HexCommandMenuScript.MAGIC_GROUP and monster != null:
			for child in entry.get("children", []):
				var spell = monster.spellSets[int(child.get("set_index", 0))][
					int(child.get("spell_index", 0))]
				child["hint"] = HexUnitFactsScript.spellSummary(spell)
		if id == "undo":
			result.append({
				"id": STATUS_COMMAND, "label": "Status", "icon": STATUS_COMMAND, "enabled": true,
				"local": true, "hint": "Open the selected unit's full status.", "reason": "",
			})
		result.append(entry)
		if id == HexCommandMenuScript.MAGIC_GROUP:
			result.append({
				"id": ITEM_COMMAND, "label": "Item", "icon": ITEM_COMMAND, "enabled": false,
				"local": true, "hint": "", "reason": "Items are not in battle yet.",
			})
	decorated["commands"] = result
	return decorated


func _onLocalCommand(commandID: String) -> void:
	if commandID == STATUS_COMMAND:
		openStatus(shownUnit())


# --- inspection ---------------------------------------------------------------

## The unit the readout is committed to, or -1.
func selectedUnit() -> int:
	return _selectedID


## The unit under the pointer, or -1. Drawn over the committed selection; never replaces it.
func setHover(monsterID: int) -> void:
	if monsterID == _hoverID:
		return
	_hoverID = monsterID
	_refreshReadout()


func hoverID() -> int:
	return _hoverID


## Which unit the readout is showing this frame, after hover is applied.
func shownUnit() -> int:
	if _hoverID >= 0 and _sim != null and _sim.state.getMonster(_hoverID) != null:
		return _hoverID
	return _selectedID


## Selects `monsterID` into the readout, or clears the selection with -1. Returns the id actually
## selected, which is -1 when the unit is not there to inspect.
func selectUnit(monsterID: int) -> int:
	var facts := _facts(monsterID)
	_selectedID = monsterID if not facts.is_empty() else -1
	effectInfo.hideBox()
	_hoveredEffectKey = ""
	_refreshReadout()
	return _selectedID


## A click on the board while nobody is aiming, in the controller's words.
func commitInspection(monsterID: int) -> int:
	return selectUnit(monsterID)


## The aim model from `HexBattleMemberInput.aimModel`, or {} when not aiming. Its forecast is what
## the prompt says while aiming.
func showAim(model: Dictionary) -> void:
	_aim = model.duplicate(true)
	_refreshPrompt()


func openStatus(monsterID: int) -> bool:
	var facts := _facts(monsterID)
	if facts.is_empty():
		return false
	_layout()
	_modalShade.visible = true
	effectInfo.hideBox()
	# The rail and the prompt step aside rather than sit dimmed under the sheet: every window fill
	# is translucent, so a box left under the sheet reads through its text as a ghost.
	commandMenu.visible = false
	prompt.hideBox()
	statusSheet.openFor(facts)
	modal_changed.emit(true)
	return true


func isModalOpen() -> bool:
	return statusSheet.isOpen()


func _onSheetClosed() -> void:
	_modalShade.visible = false
	# Back only if a turn still has a rail to show; the member may have finished while it was open.
	commandMenu.visible = commandMenu.plateCount() > 0
	_refreshPrompt()
	modal_changed.emit(false)


## Keyboard, sheet first: while it is open every key is its. Then the rail, if it is up.
func handleKey(event: InputEventKey) -> bool:
	if statusSheet.isOpen():
		return statusSheet.handleKey(event)
	if commandMenu.visible:
		return commandMenu.handleKey(event)
	return false


## A board click or right click that the GUI did not take. Only the modal sheet claims those.
func handleBoardMouse(event: InputEventMouseButton) -> bool:
	if statusSheet.isOpen():
		return statusSheet.handleUnhandledMouse(event)
	return false


func _facts(monsterID: int) -> Dictionary:
	if monsterID < 0 or _sim == null:
		return {}
	return HexUnitFactsScript.build(_sim, monsterID, _display)


func _refreshReadout() -> void:
	var shown := shownUnit()
	var facts := _facts(shown)
	if facts.is_empty() and _selectedID != -1:
		var lost := _selectedID
		_selectedID = -1
		readout.hideReadout()
		selection_lost.emit(lost)
		_layout()
		return
	readout.showFacts(facts)
	_layout()


# --- forecast -----------------------------------------------------------------

## The prompt's lines for an aim model. At most three: what, how much, and whether it can be
## confirmed. Every number is the adapter's forecast; every refusal is the simulator's.
static func aimLines(state: BattleState, aim: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if aim.is_empty():
		return lines
	var kind := str(aim.get("kind", ""))
	var legal := bool(aim.get("legal", false))
	var reason := str(aim.get("reason", ""))

	if kind == AIM_MOVE:
		lines.append("Move here." if legal else "Cannot move there.")
		if not legal:
			lines.append(reasonText(reason) + ".")
		return lines

	var targetID := int(aim.get("target_id", -1))
	var target = state.getMonster(targetID) if state != null and targetID >= 0 else null
	var subject := str(aim.get("spell", "Attack")) if kind == AIM_SPELL else "Attack"
	lines.append("%s on %s." % [subject, str(target.name)] if target != null
		else "%s on empty cell." % subject)

	var withheld := str(aim.get("withheld", ""))
	var forecast: Dictionary = aim.get("forecast", {})
	if not withheld.is_empty():
		match withheld:
			"heal":
				lines.append("Heals; no damage forecast.")
			"no_damage":
				lines.append("Deals no damage.")
			"multi_line":
				lines.append("Several damage lines; not forecast.")
			_:
				lines.append("No forecast.")
	elif bool(forecast.get("available", false)):
		lines.append(damageText(forecast) + ".")
	elif target != null:
		lines.append("No forecast.")

	lines.append("Confirm to act." if legal else reasonText(reason) + ".")
	return lines


## One line for a forecast. An attack has no roll, so it is one exact number. A spell's only roll
## is its critical, so it is two numbers and a chance, never a range. Lethality is stated because
## it is known exactly; a retaliating target is flagged because it acts before the hit lands.
static func damageText(forecast: Dictionary) -> String:
	var minimum := int(forecast.get("minimum", 0))
	var maximum := int(forecast.get("maximum", 0))
	var text := ""
	if bool(forecast.get("exact", minimum == maximum)):
		text = "%d dmg" % minimum
	else:
		text = "%d dmg, %d crit (%d%%)" % [
			minimum, maximum, roundi(float(forecast.get("critical_chance", 0.0)) * 100.0)]
	if bool(forecast.get("lethal", false)):
		text += " KO"
	elif bool(forecast.get("possibly_lethal", false)):
		text += " KO on crit"
	if bool(forecast.get("reactive_risk", false)):
		text += ", reacts first"
	return text


static func reasonText(reason: String) -> String:
	match reason:
		"":
			return ""
		"unreachable":
			return "Out of reach"
		"invalid_attack_target":
			return "Not a target for an attack"
		"invalid_spell_target":
			return "Cannot cast there"
		"petrify":
			return "Petrified"
	return reason.replace("_", " ").capitalize()


# --- refresh ------------------------------------------------------------------

## Brings every panel up to date with the bound battle. Called every frame by the controller. Each
## panel redraws only when its model differs from the last one it drew.
func refresh() -> void:
	if _sim == null:
		return
	var state := _sim.state
	if _partyID != -1 and partyPanel != null:
		var model := partyModel(
			state, _sim.eligiblePartyMemberIDs(), _partyID, _activeMemberID,
			_inputEnabled and not _inputLocked, _display)
		if model != _partyModel:
			_partyModel = model
			partyPanel.updateModel(model)
	if commandMenu != null and not _commandModel.is_empty():
		commandMenu.visible = commandMenu.plateCount() > 0 and not statusSheet.isOpen() \
			and not _combatFeedbackPlaying()
	if orderPanel != null:
		orderPanel.updateModel(partyOrderModel(state, _display))
	_refreshReadout()
	if statusSheet.isOpen():
		var sheetFacts := _facts(statusSheet.unitID())
		if sheetFacts.is_empty():
			statusSheet.close()
		else:
			statusSheet.refresh(sheetFacts)
	_syncEffectInfo()


## Whether a hit, cast, heal or removal is queued or playing on the screen.
##
## The command menu steps aside while one is, so it never covers the impact, the number and the
## unit taking it. Movement has no feedback payload, so a move keeps the menu.
func _combatFeedbackPlaying() -> bool:
	if _display == null or not _display.has_method("pendingFeedbackPayloadCount"):
		return false
	return int(_display.pendingFeedbackPayloadCount()) > 0


## Pointing at an effect on the readout explains it above the readout; pointing at `+N` lists what
## it hides. Polled rather than wired to mouse signals because the readout takes no mouse input.
func _syncEffectInfo() -> void:
	if statusSheet.isOpen() or not readout.visible:
		effectInfo.hideBox()
		_hoveredEffectKey = ""
		return
	var cell := readout.effectAt(_root.get_viewport().get_mouse_position())
	var key := ""
	if cell.has("fact"):
		key = "fact:%s" % str(cell["fact"].get("name", ""))
	elif cell.has("overflow"):
		key = "overflow:%d" % (cell["overflow"] as Array).size()
	if key == _hoveredEffectKey:
		return
	_hoveredEffectKey = key
	if key.is_empty():
		effectInfo.hideBox()
		return
	if cell.has("fact"):
		var fact: Dictionary = cell["fact"]
		var turns := int(fact.get("turns", 0))
		effectInfo.showText(
			str(fact.get("text", "")), str(fact.get("label", "")),
			"%d turn%s" % [turns, "" if turns == 1 else "s"], 3
		)
	else:
		var names: Array[String] = []
		for fact in cell["overflow"]:
			names.append("%s %d" % [str(fact.get("label", "")), int(fact.get("turns", 0))])
		effectInfo.showText(", ".join(names) + ".", "%d more" % names.size(), "", 3)
	_placeEffectInfo()


# --- layout -------------------------------------------------------------------

## Docks every box from the viewport size alone. Left column: party panel, then the round's party
## order beneath it. Right column: the command rail, or the prompt when the rail is down. Bottom
## left: the readout, with effect explanations above it.
func _layout() -> void:
	if _root == null or not is_inside_tree():
		return
	var screen := _root.get_viewport_rect().size
	var margin := NoggThemeScript.HEX_SCREEN_MARGIN
	partyPanel.position = Vector2(margin, margin)
	var partySize: Vector2 = partyPanel.windowSize()
	var orderTop := margin
	if partySize.y > 0.0:
		orderTop = margin + partySize.y + NoggThemeScript.WINDOW_STACK_GAP
	orderPanel.position = Vector2(margin, orderTop)
	var railWidth: float = commandMenu.windowSize().x
	if railWidth <= 0.0:
		railWidth = NoggThemeScript.HEX_PLATE_WIDTH
	# Below the debug drawer's toggle, which owns the very corner.
	commandMenu.position = Vector2(
		screen.x - margin - railWidth,
		maxf(margin, HexGraphicsPanelScript.toggleClearance() + NoggThemeScript.WINDOW_STACK_GAP)
	)
	readout.position = Vector2(margin, screen.y - margin - readout.boxSize().y)
	statusSheet.position = ((screen - statusSheet.sheetSize()) * 0.5).floor()
	_placePrompt()
	_placeEffectInfo()


func _placePrompt() -> void:
	if _root == null or not is_inside_tree():
		return
	var screen := _root.get_viewport_rect().size
	prompt.position = Vector2(
		screen.x - NoggThemeScript.HEX_SCREEN_MARGIN - prompt.boxSize().x,
		maxf(
			NoggThemeScript.HEX_SCREEN_MARGIN,
			HexGraphicsPanelScript.toggleClearance() + NoggThemeScript.WINDOW_STACK_GAP
		)
	)


func _placeEffectInfo() -> void:
	effectInfo.position = Vector2(
		readout.position.x,
		readout.position.y - effectInfo.boxSize().y - NoggThemeScript.HEX_PLATE_GAP * 2.0
	)
