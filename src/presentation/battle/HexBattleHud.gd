## The hex battle's on-screen chrome, composed: the party panel, the command rail, the prompt, the
## unit readout and its explanations, the status icons over units, and the STATUS sheet.
##
## ONE FRAME. Every box here is a `NoggWindow` under the active skin -- by default the Brigandine
## plate frame cut from `assets/ui/briganborders.png` -- and the game theme is applied once, at the
## root, so every label inherits the skin's face. Nothing here draws a frame of its own.
##
## WHERE THINGS LIVE, AND WHY THEY NEVER MOVE:
##   top-left      party panel -- who may act
##   top-right     command rail while a member is choosing; the prompt in the same corner otherwise
##                 (the two never coexist, so the right edge is always "what to do now")
##   bottom-left   readout of the selected unit, with effect explanations opening above it
##   centre        the STATUS sheet, modal
##   over units    status icon rows, projected
##
## READS STATE, NEVER WRITES IT. Unit facts come through `HexUnitFacts`, and the party model is still
## built here from authoritative state as it always was. Selection is presentation state: which
## unit the player is looking at changes nothing about the battle.
##
## THERE IS NO TURN ORDER RAIL. The square battle showed a speed-ordered portrait rail, and under
## the approved activation model that rail would be lying: ordinary member speed no longer
## schedules anything, and members act in whatever order the player picks.

class_name HexBattleHud
extends CanvasLayer

const HexPartyPanelScript = preload("res://src/presentation/battle/ui/HexPartyPanel.gd")
const HexCommandMenuScript = preload("res://src/presentation/battle/ui/HexCommandMenu.gd")
const HexTextBoxScript = preload("res://src/presentation/battle/ui/HexTextBox.gd")
const HexUnitReadoutScript = preload("res://src/presentation/battle/ui/HexUnitReadout.gd")
const HexCharacterStatusScript = preload("res://src/presentation/battle/ui/HexCharacterStatus.gd")
const HexStatusBadgeOverlayScript = preload(
	"res://src/presentation/battle/ui/HexStatusBadgeOverlay.gd")
const HexUnitFactsScript = preload("res://src/presentation/battle/ui/HexUnitFacts.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

signal member_selected(monsterID: int)
signal end_party_requested()
signal command_chosen(commandID: String)
signal command_cancelled()
## The selected unit is gone -- defeated or withdrawn -- and the HUD dropped it.
signal selection_lost(monsterID: int)
## The STATUS sheet opened or closed; the board must not take input while it is open.
signal modal_changed(open: bool)

const STATUS_COMMAND := "status"
const ITEM_COMMAND := "item"
## Seconds between re-reads of the selected unit's facts. Often enough that HP visibly ticks, rare
## enough that a battle full of effects is not rebuilding windows every frame.
const FACTS_REFRESH_SECONDS := 0.1

var partyPanel: HexPartyPanel
var commandMenu: HexCommandMenu
var prompt: HexTextBox
var readout: HexUnitReadout
var effectInfo: HexTextBox
var statusSheet: HexCharacterStatus
var badges: HexStatusBadgeOverlay
var _modalShade: ColorRect

var _root: Control
var _sim: BattleSimulator
var _anchorFor: Callable
var _selectedID := -1
var _promptText := ""
var _factsClock := 0.0
var _hoveredEffectKey := ""


func _init() -> void:
	name = "HexBattleHud"
	# Native resolution, above the battle viewport: the board may render at a retro preset's
	# reduced scale, and HUD text downsampled with it would be unreadable. Same reason damage
	# numbers live outside the 3D viewport.
	layer = 1
	# Before any child reads a token: every width and pitch below is a function of ui_scale.
	NoggThemeScript.configure_for_window_height(DisplayServer.window_get_size().y)

	_root = Control.new()
	_root.name = "HudRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = NoggThemeScript.build_game_theme()
	add_child(_root)

	badges = HexStatusBadgeOverlayScript.new()
	badges.name = "StatusBadges"
	_root.add_child(badges)

	partyPanel = HexPartyPanelScript.new()
	partyPanel.name = "PartyPanel"
	_root.add_child(partyPanel)
	partyPanel.member_selected.connect(func(id: int): member_selected.emit(id))
	partyPanel.end_party_requested.connect(func(): end_party_requested.emit())

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
	effectInfo.setWidth(NoggThemeScript.HEX_READOUT_WIDTH)
	get_viewport().size_changed.connect(_layout)
	_layout()


## `anchorFor(monsterID) -> Variant` answers the screen point just above a unit's head, or null when
## the unit has no model on screen. Handed in rather than looked up, so the HUD never holds the
## camera or the adapter.
func bindBattle(sim: BattleSimulator, anchorFor: Callable) -> void:
	_sim = sim
	_anchorFor = anchorFor


func _layout() -> void:
	if not is_inside_tree():
		return
	var screen := _root.get_viewport_rect().size
	var margin := NoggThemeScript.SCREEN_MARGIN
	partyPanel.position = Vector2(margin, margin)
	commandMenu.position = Vector2(screen.x - margin, margin)
	prompt.position = Vector2(screen.x - margin - prompt.boxSize().x, margin)
	readout.position = Vector2(margin, screen.y - margin - readout.boxSize().y)
	statusSheet.position = ((screen - statusSheet.sheetSize()) * 0.5).floor()
	_placeEffectInfo()


func _placeEffectInfo() -> void:
	effectInfo.position = Vector2(
		readout.position.x,
		readout.position.y - effectInfo.boxSize().y - NoggThemeScript.HEX_PLATE_GAP * 2.0
	)


# --- prompt -------------------------------------------------------------------

## Sentence-level instruction or refusal. Shown in the rail's corner whenever the rail is not up;
## while the rail is up the focused plate's own hint already says what to do.
func setStatus(text: String) -> void:
	_promptText = text
	_refreshPrompt()


func _refreshPrompt() -> void:
	if commandMenu.visible or _promptText.is_empty() or statusSheet.isOpen():
		prompt.hideBox()
		return
	prompt.showText(_promptText, "", "", 2)
	_layout()


# --- party --------------------------------------------------------------------

## Builds the panel's view model from authoritative state.
##
## Eligibility is READ from the simulator, never derived here: the simulator owns which members may
## still act, and a HUD that recomputed it would be a second answer to a question with one owner.
func showParty(
	sim: BattleSimulator, partyID: int, activeMemberID: int, inputEnabled: bool
) -> void:
	if sim == null or partyPanel == null:
		return
	var party = sim.state.parties.get(partyID)
	if party == null:
		partyPanel.updateModel({})
		return

	var eligible := sim.eligiblePartyMemberIDs()
	var members: Array = []
	for value in party.memberIDs:
		var monsterID := int(value)
		var monster = sim.state.getMonster(monsterID)
		if monster == null:
			continue
		var isEligible := eligible.has(monsterID)
		members.append({
			"id": monsterID,
			"label": str(monster.name),
			"commander": monsterID == int(party.commanderID),
			"eligible": isEligible,
			"active": monsterID == activeMemberID,
			# Spent is "alive, in the party, and no longer eligible" -- which is what the player
			# needs distinguished from a member who is simply not selectable right now.
			"spent": monster.is_alive() and not isEligible,
		})

	# A party has no authored display name, so the header is built from what it does have: its
	# commander, who is the one member the player already identifies the party by.
	var commander = sim.state.getMonster(int(party.commanderID))
	var label := (
		"%s's party" % str(commander.name) if commander != null else "Party %d" % partyID
	)
	partyPanel.updateModel({
		"party_id": partyID,
		"label": label,
		"input_enabled": inputEnabled,
		"can_end_party": inputEnabled and not eligible.is_empty(),
		"members": members,
	})


func clearParty() -> void:
	if partyPanel != null:
		partyPanel.updateModel({})
	hideCommands()


# --- command rail ---------------------------------------------------------------

## Shows the acting member's rail. The model is built by whoever knows the turn; this adds the two
## plates only the HUD gives meaning to -- STATUS, and the not-yet-real Item -- and the spell
## descriptions, and places it.
func showCommands(model: Dictionary) -> void:
	if commandMenu == null:
		return
	if model.is_empty():
		hideCommands()
		return
	commandMenu.updateModel(_decorate(model))
	commandMenu.visible = not statusSheet.isOpen()
	_refreshPrompt()


func hideCommands() -> void:
	if commandMenu == null:
		return
	commandMenu.updateModel({})
	commandMenu.hide()
	_refreshPrompt()


func _decorate(model: Dictionary) -> Dictionary:
	var decorated := model.duplicate(true)
	var commands: Array = decorated.get("commands", [])
	var monster = _sim.state.getMonster(int(model.get("monster_id", -1))) if _sim != null else null
	var result: Array = []
	for entry in commands:
		if str(entry.get("id", "")) == "magic" and monster != null:
			for child in entry.get("children", []):
				var spell = monster.spellSets[int(child.get("set_index", 0))][int(child.get("spell_index", 0))]
				child["hint"] = HexUnitFactsScript.spellSummary(spell)
		if str(entry.get("id", "")) == "undo":
			result.append({
				"id": STATUS_COMMAND, "label": "Status", "icon": STATUS_COMMAND, "enabled": true,
				"local": true, "hint": "Open the selected unit's full status.", "reason": "",
			})
		result.append(entry)
		if str(entry.get("id", "")) == "magic":
			result.append({
				"id": ITEM_COMMAND, "label": "Item", "icon": ITEM_COMMAND, "enabled": false,
				"local": true, "hint": "", "reason": "Items are not in battle yet.",
			})
	decorated["commands"] = result
	return decorated


func _onLocalCommand(commandID: String) -> void:
	if commandID == STATUS_COMMAND:
		openStatus(_selectedID)


# --- selection and inspection -----------------------------------------------------

func selectedUnit() -> int:
	return _selectedID


## Selects `monsterID` for the readout, or clears the selection with -1. Returns the id actually
## selected, which is -1 when the unit is not there to inspect.
func selectUnit(monsterID: int) -> int:
	var facts := HexUnitFactsScript.build(_sim, monsterID) if monsterID != -1 else {}
	_selectedID = monsterID if not facts.is_empty() else -1
	readout.showFacts(facts)
	effectInfo.hideBox()
	_hoveredEffectKey = ""
	_layout()
	return _selectedID


func openStatus(monsterID: int) -> bool:
	var facts := HexUnitFactsScript.build(_sim, monsterID)
	if facts.is_empty():
		return false
	_layout()
	_modalShade.visible = true
	effectInfo.hideBox()
	# The rail and the prompt step aside rather than sit dimmed under the sheet: every window fill
	# is translucent, so a box left under the sheet reads through its text as a ghost.
	commandMenu.visible = false
	badges.visible = false
	prompt.hideBox()
	statusSheet.openFor(facts)
	modal_changed.emit(true)
	return true


func _onSheetClosed() -> void:
	_modalShade.visible = false
	badges.visible = true
	# Back only if a turn still has a rail to show; the member may have finished while it was open.
	commandMenu.visible = commandMenu.plateCount() > 0
	_refreshPrompt()
	modal_changed.emit(false)


func isModalOpen() -> bool:
	return statusSheet.isOpen()


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


func _process(delta: float) -> void:
	if _sim == null:
		return
	_factsClock += delta
	if _factsClock >= FACTS_REFRESH_SECONDS:
		_factsClock = 0.0
		_refreshFacts()
	_syncBadges(delta)
	_syncEffectInfo()


func _refreshFacts() -> void:
	if _selectedID != -1:
		var facts := HexUnitFactsScript.build(_sim, _selectedID)
		if facts.is_empty():
			var lost := _selectedID
			selectUnit(-1)
			selection_lost.emit(lost)
		else:
			readout.showFacts(facts)
	if statusSheet.isOpen():
		var sheetFacts := HexUnitFactsScript.build(_sim, statusSheet.unitID())
		if sheetFacts.is_empty():
			statusSheet.close()
		else:
			statusSheet.refresh(sheetFacts)


func _syncBadges(delta: float) -> void:
	var entries: Array = []
	if _anchorFor.is_valid():
		for id in _sim.state.monsters:
			var monsterID := int(id)
			var effects: Array = _sim.state.getActiveEffects(monsterID)
			if effects.is_empty():
				continue
			var monster = _sim.state.getMonster(monsterID)
			if monster == null or not monster.is_alive():
				continue
			entries.append({"id": monsterID, "anchor": _anchorFor.call(monsterID), "effects": effects})
	badges.sync(entries, _root.get_viewport().get_mouse_position(), delta)


## Pointing at an effect on the readout explains it above the readout; pointing at `+N` lists what
## it hides. Polled rather than wired to mouse signals because the readout takes no mouse input.
func _syncEffectInfo() -> void:
	if statusSheet.isOpen():
		effectInfo.hideBox()
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
