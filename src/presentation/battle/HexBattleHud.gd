## The battle's on-screen chrome: the party panel, a status line, and nothing else yet.
##
## HOSTS HXB-12's PANEL RATHER THAN REIMPLEMENTING IT. `HexPartyPanel` already renders a supplied
## view model and emits member selection and end-party; this places it, builds the model from
## authoritative state, and forwards its two signals on. The panel stays ignorant of BattleState,
## which is what lets it be tested without one.
##
## THERE IS NO TURN ORDER RAIL. The square battle showed a speed-ordered portrait rail, and under
## the approved activation model that rail would be lying: ordinary member speed no longer
## schedules anything, and members act in whatever order the player picks. Carrying it across
## "because it was there" would have been a forecast of an order that does not exist.

class_name HexBattleHud
extends CanvasLayer

const HexPartyPanelScript = preload("res://src/presentation/battle/ui/HexPartyPanel.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

signal member_selected(monsterID: int)
signal end_party_requested()

var partyPanel: HexPartyPanel
var _statusLabel: Label
var _root: Control


func _init() -> void:
	name = "HexBattleHud"
	# Native resolution, above the battle viewport: the board may render at a retro preset's
	# reduced scale, and HUD text downsampled with it would be unreadable. Same reason damage
	# numbers live outside the 3D viewport.
	layer = 1

	_root = Control.new()
	_root.name = "HudRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	partyPanel = HexPartyPanelScript.new()
	partyPanel.name = "PartyPanel"
	partyPanel.position = Vector2(
		NoggThemeScript.SCREEN_MARGIN, NoggThemeScript.SCREEN_MARGIN
	)
	_root.add_child(partyPanel)
	partyPanel.member_selected.connect(func(id: int): member_selected.emit(id))
	partyPanel.end_party_requested.connect(func(): end_party_requested.emit())

	_statusLabel = Label.new()
	_statusLabel.name = "StatusLine"
	_statusLabel.add_theme_color_override("font_color", NoggThemeScript.TEXT_PRIMARY)
	_statusLabel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_statusLabel.position = Vector2(
		NoggThemeScript.SCREEN_MARGIN, -NoggThemeScript.SCREEN_MARGIN * 2.0
	)
	_root.add_child(_statusLabel)


func setStatus(text: String) -> void:
	if _statusLabel != null:
		_statusLabel.text = text


## Builds the panel's view model from authoritative state.
##
## Eligibility is READ from the simulator, never derived here: HXB-6 owns which members may still
## act, and a HUD that recomputed it would be a second answer to a question with one owner.
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

	# A party has no authored display name -- HXB-5 deliberately did not invent commander
	# characters or titles for this cycle -- so the header is built from what it does have: its
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
