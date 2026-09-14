## The battle's on-screen chrome: the party panel, the party order, the command menu, the actor
## and target readouts, the aim forecast, and a status line.
##
## HOSTS THE PANELS RATHER THAN REIMPLEMENTING THEM. Each panel renders a supplied view model and
## reports clicks. This file places them, builds their models, and forwards their signals. The
## panels stay ignorant of BattleState, which is what lets them be tested without one.
##
## TWO SOURCES, AND WHICH ANSWERS WHAT.
##   Displayed state (the adapter's `displayed*` readers): HP, effects, and whether a unit has
##   been shown falling or withdrawing. The simulation runs ahead of playback, so these must come
##   from what the screen has shown, or a readout drops HP before the hit lands.
##   Authoritative state (BattleState): who may be selected, the round's party order, levels,
##   stats, elements and Resonance. Eligibility is the input gate's question and has one owner.
##   Stats and Resonance are not part of the displayed state HPR-4 built; they are read live and
##   can lead playback by one action during a CPU turn. See the commit for why that is accepted.
##
## THERE IS NO TURN ORDER RAIL. Ordinary member speed no longer schedules anything, so the square
## battle's speed rail would forecast an order that does not exist. `HexPartyOrderPanel` shows the
## order that does: parties, from `partyOrder` and `pendingPartyIDs`.
##
## INSPECTION PRECEDENCE, mirrored from the square battle's docked readouts:
##   - Committed actor: the member whose turn is open (player or CPU), or a unit clicked on the
##     board while nobody is aiming.
##   - Committed target: the unit under the aim cursor while aiming, or a clicked unit.
##   - Hover draws OVER the committed unit in whichever window it routes to, and never replaces
##     it. When the pointer leaves, the window returns to the committed unit as it is now.
##   - Routing: a unit on the active party's team goes to the actor window, any other unit to the
##     target window. With no party active, everything goes to the actor window.
## Hover and click here change only what the readouts show. They never select a member, move the
## cursor, cancel an aim or paint an overlay.

class_name HexBattleHud
extends CanvasLayer

const HexPartyPanelScript = preload("res://src/presentation/battle/ui/HexPartyPanel.gd")
const HexCommandMenuScript = preload("res://src/presentation/battle/ui/HexCommandMenu.gd")
const HexInspectionPanelScript = preload("res://src/presentation/battle/ui/HexInspectionPanel.gd")
const HexPartyOrderPanelScript = preload("res://src/presentation/battle/ui/HexPartyOrderPanel.gd")
const HexBattleSessionPanelScript = preload(
	"res://src/presentation/battle/ui/HexBattleSessionPanel.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const ElementReferencesScript = preload("res://src/factories/ElementReferences.gd")
const HexGraphicsPanelScript = preload("res://src/presentation/battle/ui/HexGraphicsPanel.gd")

const REASON_DEFEATED := "defeated"
const REASON_WITHDRAWN := "withdrawn"

## Aim kinds, as `HexBattleMemberInput.aimModel` names them (its command ids). Spelled here rather
## than preloaded so presentation does not import the systems layer.
const AIM_MOVE := "move"
const AIM_ATTACK := "attack"
const AIM_SPELL := "spell"

signal member_selected(monsterID: int)
signal end_party_requested()
signal command_chosen(commandID: String)
signal command_cancelled()
## A session row was clicked: one of HexBattleSessionPanel's command ids.
signal session_command(commandID: String)

var partyPanel: HexPartyPanel
var commandMenu: HexCommandMenu
## Untyped: a brand-new `class_name` is not a usable bare type until the project rescans it
## (LEARNINGS, GDScript loading). The preloaded scripts construct them.
var orderPanel
var inspection
var sessionPanel
var _statusLabel: Label
var _root: Control

var _sim: BattleSimulator
## The displayed-state reader: anything with displayedHitpoints, displayedEffects and
## displayedRemovalReason. Untyped so probes can pass a stub; the battle passes its adapter.
var _display = null

var _partyID := -1
var _activeMemberID := -1
var _inputEnabled := false
var _actorID := -1
var _targetID := -1
var _hoverID := -1
var _aim: Dictionary = {}
## The party model last handed to the panel. The panel rebuilds its rows on every update, so the
## per-frame refresh only hands it a model that differs.
var _partyModel: Dictionary = {}
## The command model last supplied, kept so a pause can redraw it without input.
var _commandModel: Dictionary = {}
## True while playback is paused: every row that would issue a command draws disabled.
var _inputLocked := false


func _init() -> void:
	name = "HexBattleHud"
	# Native resolution, above the battle viewport: the board may render at a retro preset's
	# reduced scale, and HUD text downsampled with it would be unreadable. Same reason damage
	# numbers live outside the 3D viewport.
	#
	# GAME_LAYER, the square battle's UI layer, so the square battle's whole stack holds again:
	# status badges (layer 0) under damage numbers (WORLD_EFFECT_LAYER, 9) under the HUD (10), and
	# the CRT overlay's "UI through CRT" layer (GAME_LAYER + 1) is again just above the HUD. At
	# layer 1 the HUD sat under the numbers, so a hit number drew over the panels.
	layer = NoggThemeScript.GAME_LAYER

	_root = Control.new()
	_root.name = "HudRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The square HUD's themed root: the Nogg face and body size cascade to every window, and the
	# bitmap faces must be point-sampled or every glyph blurs (UI_DESIGN §4b).
	_root.theme = NoggThemeScript.build_game_theme()
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_root)

	partyPanel = HexPartyPanelScript.new()
	partyPanel.name = "PartyPanel"
	_root.add_child(partyPanel)
	partyPanel.member_selected.connect(func(id: int): member_selected.emit(id))
	partyPanel.end_party_requested.connect(func(): end_party_requested.emit())

	orderPanel = HexPartyOrderPanelScript.new()
	_root.add_child(orderPanel)

	# Opposite corner from the party panel: the panel says who may act, the menu says what the one
	# who is acting may do, and the two are read at different moments.
	commandMenu = HexCommandMenuScript.new()
	commandMenu.name = "CommandMenu"
	commandMenu.hide()
	_root.add_child(commandMenu)
	commandMenu.command_chosen.connect(func(id: String): command_chosen.emit(id))
	commandMenu.cancelled.connect(func(): command_cancelled.emit())

	inspection = HexInspectionPanelScript.new()
	_root.add_child(inspection)

	sessionPanel = HexBattleSessionPanelScript.new()
	_root.add_child(sessionPanel)
	sessionPanel.command_chosen.connect(func(id: String): session_command.emit(id))

	_statusLabel = Label.new()
	_statusLabel.name = "StatusLine"
	_statusLabel.add_theme_color_override("font_color", NoggThemeScript.TEXT_PRIMARY)
	_statusLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_statusLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_statusLabel)


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	_layout()


func setStatus(text: String) -> void:
	if _statusLabel != null:
		_statusLabel.text = text
		_layout()


func statusText() -> String:
	return _statusLabel.text if _statusLabel != null else ""


## The battle this HUD reads. `display` is the displayed-state reader; see `_display`.
func bind(sim: BattleSimulator, display) -> void:
	_sim = sim
	_display = display


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
## OUT once its commander has been shown falling or withdrawing. A pending party whose commander
## has fallen but not yet been shown keeps its place until the fall plays.
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


# --- commands ---------------------------------------------------------------

## Shows the acting member's commands. The model is built by whoever knows the turn; this places
## it and nothing more, exactly as the party panel is treated.
func showCommands(model: Dictionary) -> void:
	if commandMenu == null:
		return
	_commandModel = model.duplicate(true)
	commandMenu.updateModel(_lockedCommands(model))
	commandMenu.visible = not model.is_empty()
	_layout()


func hideCommands() -> void:
	if commandMenu == null:
		return
	_commandModel = {}
	commandMenu.updateModel({})
	commandMenu.hide()


func _lockedCommands(model: Dictionary) -> Dictionary:
	if not _inputLocked or model.is_empty():
		return model
	var locked := model.duplicate(true)
	locked["input_enabled"] = false
	return locked


## Locks or unlocks every command row, and redraws the party panel and command menu at once so
## the rows say so. Called by the controller when playback pauses or resumes. The lock is only
## what the rows show; the controller refuses the commands themselves.
func setInputLocked(locked: bool) -> void:
	if _inputLocked == locked:
		return
	_inputLocked = locked
	if _sim != null and _partyID != -1:
		showParty(_sim, _partyID, _activeMemberID, _inputEnabled)
	if commandMenu != null and not _commandModel.is_empty():
		commandMenu.updateModel(_lockedCommands(_commandModel))


func isInputLocked() -> bool:
	return _inputLocked


# --- session -----------------------------------------------------------------

## `session` keys: phase ("battle", "ending" or "complete"), paused (bool), speed (float),
## can_skip (bool), aiming (bool), result (String), rounds (int). Built by the controller, which
## owns them.
func setSession(session: Dictionary) -> void:
	if sessionPanel != null:
		sessionPanel.updateModel(sessionModel(session))


## The session rows. While the battle plays: its state, then Pause or Resume, the speed, Skip, and
## Setup, then the camera keys as a help row. Once it is complete: the result, Restart and Setup.
## Each value column is the key for that row.
static func sessionModel(session: Dictionary) -> Dictionary:
	if session.is_empty():
		return {}
	# Steps aside while the player aims, as the command menu does. The window takes the pointer, and
	# at the bottom centre it sits over the near edge of the board, exactly where a cell may need
	# pointing at. P, F and Enter still work; the rows return when the aim ends.
	if bool(session.get("aiming", false)):
		return {}
	var phase := str(session.get("phase", ""))
	if phase == "complete":
		return {
			"title": str(session.get("result", "")),
			"rows": [
				{"id": "", "label": "After %d rounds" % int(session.get("rounds", 0)),
					"value": "", "enabled": false},
				{"id": HexBattleSessionPanelScript.RESTART, "label": "Restart", "value": "R",
					"enabled": true},
				{"id": HexBattleSessionPanelScript.SETUP, "label": "Setup", "value": "", "enabled": true},
				{"id": "", "label": "Q/E turn, wheel zoom", "value": "", "enabled": false},
			],
		}
	var paused := bool(session.get("paused", false))
	var title := "Paused" if paused else ("Finishing" if phase == "ending" else "Playing")
	return {
		"title": title,
		"rows": [
			{"id": HexBattleSessionPanelScript.PAUSE, "label": "Resume" if paused else "Pause",
				"value": "P", "enabled": true},
			{"id": HexBattleSessionPanelScript.SPEED,
				"label": "Speed %s" % speedText(float(session.get("speed", 1.0))),
				"value": "F", "enabled": true},
			{"id": HexBattleSessionPanelScript.SKIP, "label": "Skip", "value": "Enter",
				"enabled": bool(session.get("can_skip", false))},
			{"id": HexBattleSessionPanelScript.SETUP, "label": "Setup", "value": "", "enabled": true},
			{"id": "", "label": "Q/E turn, wheel zoom", "value": "", "enabled": false},
		],
	}


static func speedText(speed: float) -> String:
	if is_equal_approx(speed, roundf(speed)):
		return "%dx" % roundi(speed)
	return "%.1fx" % speed


# --- inspection -------------------------------------------------------------

func setActor(monsterID: int) -> void:
	_actorID = monsterID


func setTarget(monsterID: int) -> void:
	_targetID = monsterID


## The unit under the pointer, or -1. Draws over the committed readout; never replaces it.
func setHover(monsterID: int) -> void:
	_hoverID = monsterID


## A click on the board while nobody is aiming. Commits the unit to whichever window it routes to;
## a click on bare ground (-1) clears both committed readouts.
func commitInspection(monsterID: int) -> void:
	if monsterID < 0:
		_actorID = -1
		_targetID = -1
		return
	if _routesToTarget(monsterID):
		_targetID = monsterID
	else:
		_actorID = monsterID


## The aim model from `HexBattleMemberInput.aimModel`, or {} when not aiming. An attack or spell
## aim commits the unit under the cursor as the target; a move aim leaves the target alone.
func showAim(model: Dictionary) -> void:
	_aim = model.duplicate(true)
	var kind := str(model.get("kind", ""))
	if kind == AIM_ATTACK \
			or kind == AIM_SPELL:
		_targetID = int(model.get("target_id", -1))


func hoverID() -> int:
	return _hoverID


func actorID() -> int:
	return _actorID


func targetID() -> int:
	return _targetID


## Which unit each window is showing this frame, after hover is applied.
func shownInspection() -> Dictionary:
	var actor := _actorID
	var target := _targetID
	if _hoverID >= 0 and _sim != null and _sim.state.getMonster(_hoverID) != null:
		if _routesToTarget(_hoverID):
			target = _hoverID
		else:
			actor = _hoverID
	return {"actor": actor, "target": target}


func _routesToTarget(monsterID: int) -> bool:
	if _sim == null:
		return false
	var monster = _sim.state.getMonster(monsterID)
	var party = _sim.state.parties.get(int(_sim.state.activePartyID))
	if monster == null or party == null:
		return false
	return int(monster.team) != int(party.teamID)


## A unit's readout model.
##
## HP and effects are what the screen has shown, falling back to authoritative state only when no
## reader is given. The remaining fields have no displayed counterpart and are read live.
static func inspectionModel(state: BattleState, display, monsterID: int) -> Dictionary:
	if state == null or monsterID < 0:
		return {}
	var monster = state.getMonster(monsterID)
	if monster == null:
		return {}
	var hp := int(monster.hitpoints)
	var effectRows: Array = state.getActiveEffects(monsterID)
	if display != null:
		var shownHP := int(display.displayedHitpoints(monsterID))
		if shownHP >= 0:
			hp = shownHP
		effectRows = display.displayedEffects(monsterID)
	var removal := removalReason(state, display, monsterID)

	var party = state.partyForMember(monsterID)
	var commander := party != null and int(party.commanderID) == monsterID
	var side := "Commander" if commander else (
		partyLabel(state, int(party.partyID)) if party != null else "No party")
	var controllerWord := "CPU"
	if party != null and str(party.controller) == "player":
		controllerWord = "PLAYER"
	var stateWord := controllerWord
	if removal == REASON_DEFEATED:
		stateWord = "DOWN"
	elif removal == REASON_WITHDRAWN:
		stateWord = "OUT"

	var elements: Array = []
	for index in mini(monster.elements.size(), NoggThemeScript.STATUS_CELL_OFFSETS.size()):
		var element := str(monster.elements[index])
		elements.append({
			"element": element,
			"code": ElementReferencesScript.code(element),
			"charge": int(monster.get_resonance(element)),
		})

	var effects: Array = []
	for entry in effectRows:
		var row: Dictionary = entry
		effects.append({
			"name": str(row.get("name", "")),
			"label": str(row.get("name", "")).capitalize(),
			"turns": int(row.get("remainingTurns", -1)),
		})

	return {
		"id": monsterID,
		"name": str(monster.name),
		"level": int(monster.level),
		"team": int(monster.team),
		"commander": commander,
		"side": side,
		"state": "T%d %s" % [int(monster.team), stateWord],
		"removed": removal,
		"hp": hp,
		"max_hp": int(monster.max_hitpoints),
		"atk": int(monster.atk),
		"def": int(monster.def),
		"speed": int(monster.speed),
		"move": int(monster.move),
		"elements": elements,
		"effects": effects,
	}


## The forecast window's lines for an aim model. At most three: what, how much, and whether it
## can be confirmed. Every number is the adapter's forecast; every refusal is the simulator's.
static func aimLines(state: BattleState, aim: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if aim.is_empty():
		return lines
	var kind := str(aim.get("kind", ""))
	var legal := bool(aim.get("legal", false))
	var reason := str(aim.get("reason", ""))

	if kind == AIM_MOVE:
		lines.append("Move here" if legal else "Cannot move there")
		if not legal:
			lines.append(reasonText(reason))
		return lines

	var targetID := int(aim.get("target_id", -1))
	var target = state.getMonster(targetID) if state != null and targetID >= 0 else null
	var subject := str(aim.get("spell", "Attack")) if kind == AIM_SPELL \
		else "Attack"
	lines.append("%s on %s" % [subject, str(target.name)] if target != null
		else "%s on empty cell" % subject)

	var withheld := str(aim.get("withheld", ""))
	var forecast: Dictionary = aim.get("forecast", {})
	if not withheld.is_empty():
		match withheld:
			"heal":
				lines.append("Heals; no damage forecast")
			"no_damage":
				lines.append("Deals no damage")
			_:
				lines.append("No forecast")
	elif bool(forecast.get("available", false)):
		lines.append(damageText(forecast))
	elif target != null:
		lines.append("No forecast")

	lines.append("Confirm to act" if legal else reasonText(reason))
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


# --- refresh ----------------------------------------------------------------

## Brings every panel up to date with the bound battle. Called every frame by the controller.
## Each panel redraws only when its model differs from the last one it drew.
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
		commandMenu.visible = not _combatFeedbackPlaying()
	if orderPanel != null:
		orderPanel.updateModel(partyOrderModel(state, _display))
	if inspection != null:
		var shown := shownInspection()
		inspection.showActor(inspectionModel(state, _display, int(shown["actor"])))
		inspection.showTarget(inspectionModel(state, _display, int(shown["target"])))
		inspection.showForecast(aimLines(state, _aim))
	_layout()


## Whether a hit, cast, heal or removal is queued or playing on the screen.
##
## The command menu steps aside while one is. It is docked top-right, over the far side of the
## board where the enemy usually stands, and it returns the moment an attack or spell resolves
## because the member still has a move. Left up, it covered the impact, the number and the unit
## taking it. Movement has no feedback payload, so a move keeps the menu, as it always has.
func _combatFeedbackPlaying() -> bool:
	if _display == null or not _display.has_method("pendingFeedbackPayloadCount"):
		return false
	return int(_display.pendingFeedbackPayloadCount()) > 0


## Docks every panel from the viewport size alone.
##
## At 1280x720 the UI scale is 2 and the compact layout gives a 640x360 design-unit screen. Left
## column: party panel, then the party order beneath it. Right column: the command menu. Bottom
## corners: actor and target readouts, with the forecast above the target. The status line is
## centred at the top between the two columns.
func _layout() -> void:
	if _root == null or not is_inside_tree():
		return
	var viewportSize := get_viewport().get_visible_rect().size
	var margin: float = NoggThemeScript.SCREEN_MARGIN
	partyPanel.position = Vector2(margin, margin)
	var partySize := partyPanel.windowSize()
	var orderTop := margin
	if partySize.y > 0.0:
		orderTop = margin + partySize.y + NoggThemeScript.WINDOW_STACK_GAP
	orderPanel.position = Vector2(margin, orderTop)
	# Below the status line and the graphics toggle. At the top margin the menu's first rows ran
	# under both: the centred prompt read "Choose a command" through the menu's title row, and the
	# toggle, on a higher layer, covered the right end of the title.
	var statusBottom := margin + _statusLabel.get_minimum_size().y
	var toggleBottom: float = HexGraphicsPanelScript.TOGGLE_TOP + HexGraphicsPanelScript.TOGGLE_HEIGHT
	var commandTop := maxf(statusBottom, toggleBottom) + NoggThemeScript.WINDOW_STACK_GAP
	commandMenu.position = Vector2(
		viewportSize.x - NoggThemeScript.SPELL_WIDTH - margin, commandTop)
	inspection.layoutFor(viewportSize)
	if sessionPanel != null:
		var sessionSize: Vector2 = sessionPanel.windowSize()
		sessionPanel.position = Vector2(
			round((viewportSize.x - NoggThemeScript.STATUS_WINDOW_WIDTH) * 0.5),
			viewportSize.y - sessionSize.y - margin)
	var statusWidth := _statusLabel.get_minimum_size().x
	_statusLabel.size = _statusLabel.get_minimum_size()
	_statusLabel.position = Vector2(round((viewportSize.x - statusWidth) * 0.5), margin)
