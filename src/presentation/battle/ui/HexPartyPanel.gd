## Bounded party-activation display: one NoggWindow rendering a supplied view
## model. Owns no scheduling or battle-flow logic -- BattleSimulator and
## whatever composes the model still decide who is eligible, who is active,
## and what "End Party" means; this node only shows what it is given and
## reports which row was clicked.
##
## Mirrors PlayerCommandMenu's ownership split -- content changes rebuild
## rows, and rebuilding is the only thing that changes what is shown -- but
## needs none of its cursor/paging machinery: a party this size needs no
## navigation model, only a click-through.

class_name HexPartyPanel
extends Control

## Carries the clicked member's id. Emitted only for a row that was both
## input_enabled and eligible at the time updateModel() built it.
signal member_selected(monsterID: int)
## The End Party row was clicked. Emitted only when both input_enabled and
## can_end_party were true at the time updateModel() built it.
signal end_party_requested()

const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")

const END_PARTY_LABEL := "End Party"

const KIND_HEADER := "header"
const KIND_MEMBER := "member"
const KIND_END_PARTY := "end_party"

var _window: NoggWindow

## Parallel to the descriptors handed to set_full_rows(): kind/id/enabled per
## row, looked up by row_built()'s full_index rather than re-derived from the
## rendered row -- the same split PlayerCommandMenu keeps between a row's
## metadata and its label/value/disabled text.
var _rowMeta: Array[Dictionary] = []


func _init() -> void:
	_window = NoggWindowScript.new()
	add_child(_window)
	_window.row_built.connect(_on_row_built)


## `model` keys: party_id (int, unused here -- this panel always shows
## whichever single party it is given), label (String), input_enabled
## (bool), can_end_party (bool), members (Array of Dictionaries with id,
## label, commander, eligible, active, spent). Rendered in supplied order;
## eligibility is read, never derived. A model with no members clears the
## panel to nothing rather than showing a header and an inert End Party row
## for a party that no longer exists -- that is what "clears stale
## selection" means for a component with no selection state of its own.
func updateModel(model: Dictionary) -> void:
	var members: Array = model.get("members", [])
	if members.is_empty():
		_rowMeta = []
		_window.set_row_capacity(1)
		_window.set_full_rows([])
		return

	var inputEnabled := bool(model.get("input_enabled", false))
	var canEndParty := bool(model.get("can_end_party", false))

	var descriptors: Array = []
	var meta: Array[Dictionary] = []

	descriptors.append({"label": str(model.get("label", "")), "value": "", "disabled": true})
	meta.append({"kind": KIND_HEADER, "enabled": false})

	for entry in members:
		var member: Dictionary = entry as Dictionary
		var eligible := bool(member.get("eligible", false))
		var enabled := inputEnabled and eligible
		descriptors.append({
			"label": str(member.get("label", "")),
			"value": _memberStatus(member),
			"disabled": not enabled,
		})
		meta.append({
			"kind": KIND_MEMBER, "id": int(member.get("id", -1)), "enabled": enabled
		})

	var endPartyEnabled := inputEnabled and canEndParty
	descriptors.append({
		"label": END_PARTY_LABEL, "value": "", "disabled": not endPartyEnabled
	})
	meta.append({"kind": KIND_END_PARTY, "enabled": endPartyEnabled})

	_rowMeta = meta
	_window.set_row_capacity(descriptors.size())
	_window.set_full_rows(descriptors)


## Commander, then whichever of active/spent applies -- a member can be both
## the commander and mid-activation, or both the commander and already
## spent, and both facts matter at once. Plain fixed words, not an icon: this
## item makes no art decision, and a disabled row's own dimming already
## carries "not selectable right now" for a spent, dead, or off-turn member.
func _memberStatus(member: Dictionary) -> String:
	var parts: Array[String] = []
	if bool(member.get("commander", false)):
		parts.append("CMD")
	if bool(member.get("active", false)):
		parts.append("ACTIVE")
	elif bool(member.get("spent", false)):
		parts.append("DONE")
	return " ".join(parts)


## Wired once per row NoggWindow builds -- fresh rows every updateModel()
## call, since set_full_rows() frees the previous generation first, so there
## is nothing here to disconnect and nothing that can double-wire.
func _on_row_built(row: Control, full_index: int) -> void:
	if full_index < 0 or full_index >= _rowMeta.size():
		return
	var entry: Dictionary = _rowMeta[full_index]
	if str(entry.get("kind", "")) == KIND_HEADER:
		return
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	if not bool(entry.get("enabled", false)):
		# Disabled rows stay visible and dim, but are inert to click -- and
		# still consume the event so it does not fall through to whatever is
		# behind this panel.
		return
	row.gui_input.connect(_on_row_gui_input.bind(full_index))


func _on_row_gui_input(event: InputEvent, full_index: int) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if full_index < 0 or full_index >= _rowMeta.size():
		return
	var entry: Dictionary = _rowMeta[full_index]
	match str(entry.get("kind", "")):
		KIND_MEMBER:
			member_selected.emit(int(entry.get("id", -1)))
		KIND_END_PARTY:
			end_party_requested.emit()
