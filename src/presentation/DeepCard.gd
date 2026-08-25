## The held-key reference readout for the unit under the pointer
## (docs/UI_DESIGN.md §8).
##
## Everything here is material the rest of the HUD never shows. The docked
## status windows carry HP, ATK/DEF, SPD/MOV, elements and Resonance; this card
## deliberately repeats none of it and instead carries what has no surface
## anywhere else: the full spell list with live cooldowns, passives, JUMP, LUCK
## with its derived critical chance, the race elemental matchup, and how many
## basic attacks the acting unit needs to remove this one.
##
## The race matchup is the reason the card exists rather than being a
## convenience. It swings damage by +/-20% and is fully live in
## `RaceReferences.getDamageMultiplier()`, so before this a player watching a
## spell land for noticeably more or less than expected had nothing anywhere in
## the UI that explained why.
##
## **A separate window, not a taller docked one.** Trait 6 fixes the docked
## readouts' size precisely so their values cannot jitter the layout, and that
## rule is worth more than the rows it costs. This window is transient and
## nothing reflows off it, which is what lets it size to its content the way the
## spell list already does.

class_name DeepCard
extends Control

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const PlayerCommandMenuScript = preload("res://src/presentation/PlayerCommandMenu.gd")
const RaceReferencesScript = preload("res://src/factories/RaceReferences.gd")

## Shown when a value exists but is empty — no weaknesses, no race, no
## resistances. A dash rather than a blank, so the row still reads as answered.
const EMPTY_VALUE := "-"

var _window: NoggWindow
var _open := false
## Which unit the card is currently rendering, so a mouse motion that resolves
## to the same unit does not rebuild every row.
var _monster_id := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_window = NoggWindowScript.new()
	_window.name = "DeepCardWindow"
	add_child(_window)
	# Readout only. The card is centred over the board, so a Control consuming
	# clicks here would make the units it is describing unselectable — and the
	# board pick that decides *which* unit the card shows runs off mouse motion
	# reaching `_unhandled_input`, which a STOP filter would swallow outright.
	_window.set_input_transparent(true)
	_window.visible = false


## Renders `monster` and opens the card if it is not already open.
##
## `spell_entries` comes from `PlayerTurnController.spellEntriesFor()` and
## `kill_forecast` from the controller's own `CombatResolver` read, rather than
## being gathered here: no other file under `src/presentation/` reaches into
## `src/systems/` or into a resolver, and this card is not the place to start.
## The caller reports facts; this file decides how they are worded.
func show_for(monster, spell_entries: Array, kill_forecast: Dictionary) -> void:
	if monster == null:
		hide_card()
		return
	var rows := _rows_for(monster, spell_entries, kill_forecast)
	# Capacity is the page size AND the window height (trait 6), so a short
	# card is a short window and a long one pages, exactly as the spell list
	# already behaves (§8). Set before `set_full_rows()`, which slices against
	# it, and before the width, which `add_row()` measures its label clip from.
	_window.size.x = NoggThemeScript.DEEP_CARD_WIDTH
	_window.set_row_capacity(mini(rows.size(), NoggThemeScript.DEEP_CARD_CAPACITY))
	_window.set_full_rows(rows)
	_layout()
	_monster_id = int(monster.uniqueID)
	if not _open:
		_open = true
		_window.open()


func hide_card() -> void:
	_monster_id = -1
	if not _open:
		return
	_open = false
	_window.close()


func is_open() -> bool:
	return _open


func shown_monster_id() -> int:
	return _monster_id if _open else -1


## Turns a page. Inert on a single-page card, which is the common case, so the
## caller can route the wheel here unconditionally while the card is up.
func turn_page(direction: int) -> void:
	if not _open or _window.page_count() <= 1:
		return
	if direction > 0:
		_window.next_page()
	else:
		_window.prev_page()
	_layout()


## Horizontally centred with a **fixed top edge**, so a card that changes height
## as the pointer sweeps from a one-spell unit to a seven-spell one grows
## downward instead of re-centring and visibly jumping under a still pointer.
##
## The band from `DEEP_CARD_TOP` down is the one horizontal strip nothing else
## docks in: the rail and the prompt own the top, the status windows own the
## bottom corners, and the action row is clamped out of the docked windows'
## band. Being centred over the board is acceptable here in a way it would not
## be for a persistent element — the card exists only while its key is held.
func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	_window.position = Vector2(
		round((viewport_size.x - _window.size.x) * 0.5), NoggThemeScript.DEEP_CARD_TOP
	)


func _rows_for(monster, spell_entries: Array, kill_forecast: Dictionary) -> Array:
	var rows: Array = []
	rows.append({"label": str(monster.name), "value": _race_text(monster)})
	# JUMP and LUCK share a row rather than taking one each: neither is a
	# number the player watches change, and the card's height is its cost.
	# The critical chance is spelled out beside LUCK because LUCK's only
	# gameplay meaning is that percentage — `Monster.get_critical_chance()`
	# is luck/100, capped at 15%, and nothing else reads the stat.
	rows.append({
		"label": "JUMP %d" % int(monster.jump),
		"value": "LUCK %d (crit %d%%)" % [
			int(monster.luck), roundi(monster.get_critical_chance() * 100.0)
		]
	})

	rows.append({"label": "HITS TO KILL", "value": _kill_value(monster, kill_forecast)})
	# The assumption travels with the number rather than being left implied.
	# Hits-to-kill is derived and will be read as a promise, so the number
	# carries the elevation modifier it was computed under and the row beneath
	# it names the unit doing the attacking.
	var caption := _kill_caption(kill_forecast)
	caption["disabled"] = true
	rows.append(caption)

	var matchup := _matchup_text(monster)
	rows.append({"label": "WEAK", "value": matchup["weak"]})
	rows.append({"label": "RESIST", "value": matchup["resist"]})

	rows.append({"label": "SPELLS", "disabled": true})
	if spell_entries.is_empty():
		rows.append({"label": "  none", "disabled": true})
	for entry in spell_entries:
		# Same value column the spell list draws, from the same function, so
		# a cooldown can never read one way in the menu and another here.
		rows.append({
			"label": str(entry["name"]),
			"value": PlayerCommandMenuScript.spell_value(entry),
			"disabled": not bool(entry["ready"])
		})

	rows.append({"label": "PASSIVES", "disabled": true})
	if monster.passives.is_empty():
		rows.append({"label": "  none", "disabled": true})
	for passive in monster.passives:
		rows.append({"label": str(passive.name), "value": _passive_text(passive)})
	return rows


func _race_text(monster) -> String:
	var race := str(monster.race)
	return EMPTY_VALUE if race.is_empty() or race == "none" else race


## The race's resistance table split into the two things it can say. Presented
## as two grouped rows rather than one row per element: the table has at most
## four entries and they only ever carry two distinct multipliers, so grouping
## costs no information and saves the card three rows.
func _matchup_text(monster) -> Dictionary:
	var weak: Array[String] = []
	var resist: Array[String] = []
	var resistances: Dictionary = RaceReferencesScript.getReference(str(monster.race)).get(
		"RESISTANCES", {}
	)
	var elements: Array = resistances.keys()
	elements.sort()
	for element in elements:
		var multiplier := float(resistances[element])
		if multiplier > 1.0:
			weak.append(str(element))
		elif multiplier < 1.0:
			resist.append(str(element))
	return {
		"weak": EMPTY_VALUE if weak.is_empty() else ", ".join(weak),
		"resist": EMPTY_VALUE if resist.is_empty() else ", ".join(resist)
	}


## The elevation modifier rides along with the count rather than being left to
## a vaguer "at current positions": it is the one part of the calculation that
## changes the moment either unit moves, it is the reason the same attacker
## needs a different number of hits from a different tile, and it is already how
## the aiming forecast words the same modifier (`%d%% elevation`). Omitted at
## 100%, where there is no modifier to disclose.
func _kill_value(monster, kill_forecast: Dictionary) -> String:
	var damage := int(kill_forecast.get("damage", 0))
	if damage <= 0:
		return EMPTY_VALUE
	var hits := ceili(float(monster.hitpoints) / float(damage))
	var elevation := int(kill_forecast.get("elevation", 100))
	if elevation == 100:
		return str(hits)
	return "%d at %d%% elev" % [hits, elevation]


## The attacker goes in the value column like every other value on the card,
## which is also what keeps the row inside `DEEP_CARD_WIDTH`: the longest
## monster name in the catalog plus a spelled-out sentence does not fit on one
## side of it.
func _kill_caption(kill_forecast: Dictionary) -> Dictionary:
	var attacker := str(kill_forecast.get("attacker", ""))
	match str(kill_forecast.get("reason", "")):
		"no_actor":
			return {"label": "  no unit is acting", "value": ""}
		"is_actor":
			return {"label": "  this unit is acting", "value": ""}
		"same_team":
			return {"label": "  ally of", "value": attacker}
	return {"label": "  basic attack by", "value": attacker}


## Trigger first, then the effect, because the trigger is what decides whether
## the effect is something the player can play around.
##
## Assembled from parts and joined rather than formatted in one string: a
## passive with no element (`Tough Skin`) would otherwise render its blank
## where the element goes, and a stray space inside a right-aligned value is
## visible as the value sitting off the frame's inner edge.
func _passive_text(passive) -> String:
	var parts: Array[String] = [_trigger_text(str(passive.trigger))]
	match str(passive.effect_type):
		"damage_reduction":
			parts.append("-%d%%" % roundi(float(passive.value) * 100.0))
		"aoe_damage":
			parts.append(str(roundi(float(passive.value))))
			parts.append(_element_text(passive))
			parts.append("r%d" % int(passive.radius))
		"retaliate_damage":
			parts.append(str(roundi(float(passive.value))))
			parts.append(_element_text(passive))
		_:
			parts.append(str(passive.effect_type))
	var kept: Array[String] = []
	for part in parts:
		if not part.is_empty():
			kept.append(part)
	return " ".join(kept)


## `ON_DAMAGE_TAKEN` -> `on damage taken`. Derived rather than table-mapped so a
## trigger added to the passive catalog reads sensibly here without this file
## having to learn about it first.
func _trigger_text(trigger: String) -> String:
	if trigger.is_empty():
		return ""
	return trigger.trim_prefix("ON_").replace("_", " ").to_lower()


## The element's own name, not its two-character code. The codes exist for the
## docked status cells, which have a fixed column to fit; here the WEAK/RESIST
## rows already spell elements out and a passive reading `15 IC r3` beside them
## would be the card using two vocabularies for one thing.
func _element_text(passive) -> String:
	var element := str(passive.element)
	return "" if element.is_empty() or element == "none" else element
