## PassiveSkillResolver — Handles all passive skill logic.
## Resolves damage modifiers (ON_DAMAGE_TAKEN) and fires event-triggered passives
## (ON_TURN_END, ON_DEATH, etc.).
## Also absorbs status effect damage ticking (previously in CombatResolver).
## Pure logic, no Node dependency.

class_name PassiveSkillResolver

const ShapeCaster = preload("res://src/algorithms/ShapeCaster.gd")

var state: BattleState
var events: BattleEvents

## Trigger constants
const ON_TURN_END  = "ON_TURN_END"
const ON_DEATH     = "ON_DEATH"
const ON_DAMAGE_TAKEN = "ON_DAMAGE_TAKEN"
const ON_TARGETED  = "ON_TARGETED"


func _init(_state: BattleState, _events: BattleEvents) -> void:
	state = _state
	events = _events


# ─── Damage Modifier Hook ─────────────────────────────────────────────────────

func applyDamageModifiers(rawDamage: int, targetID: int, is_simulation: bool = false) -> int:
	## Called by CombatResolver before applying any damage to targetID.
	## Iterates the target's passives and reduces damage for "damage_reduction" passives.
	var mon = state.getMonster(targetID)
	if mon == null:
		return rawDamage

	var finalDamage = rawDamage
	for passive in mon.passives:
		if passive.trigger == ON_DAMAGE_TAKEN and passive.effect_type == "damage_reduction":
			var reduction = int(float(finalDamage) * passive.value)
			finalDamage = max(1, finalDamage - reduction)
			if not is_simulation:
				events.passive_triggered.emit(targetID, passive.name, ON_DAMAGE_TAKEN)

	return finalDamage


# ─── Event Trigger Dispatcher ─────────────────────────────────────────────────

func fireEvent(trigger: String, sourceID: int) -> void:
	## Fires all effects and passives associated with the given trigger on sourceID.
	match trigger:
		ON_TURN_END:
			_onTurnEnd(sourceID)
		ON_DEATH:
			_onDeath(sourceID)
		_:
			pass  # Future triggers handled here


func _onTurnEnd(monsterID: int) -> void:
	## Handles all ON_TURN_END logic:
	## 1. Status effect damage ticks (burn, poison, etc.)
	## 2. ON_TURN_END passive effects (future use)
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return

	# --- Status effect damage (absorbed from CombatResolver) ---
	var effects = state.getActiveEffects(monsterID)
	for effect in effects:
		var dmg = effect.get("damagePerTurn", 0)
		if dmg <= 0:
			continue
		var actualDamage = mon.take_damage(dmg)
		events.status_damage_dealt.emit(monsterID, effect["name"], actualDamage, mon.hitpoints)
		if not mon.is_alive():
			var sourceID = effect.get("sourceMonsterID", -1)
			_handleDefeat(monsterID, sourceID)
			return

	# --- ON_TURN_END passives (future: e.g. regeneration) ---
	for passive in mon.passives:
		if passive.trigger == ON_TURN_END:
			events.passive_triggered.emit(monsterID, passive.name, ON_TURN_END)
			# Future: handle regeneration, etc.


func _onDeath(monsterID: int) -> void:
	## Fires all ON_DEATH passives for the dying entity.
	## Called by CombatResolver._handleDefeat() BEFORE removing the monster from state.
	var mon = state.getMonster(monsterID)
	if mon == null:
		return

	var monPos = state.getMonsterPosition(monsterID)

	for passive in mon.passives:
		if passive.trigger != ON_DEATH:
			continue

		events.passive_triggered.emit(monsterID, passive.name, ON_DEATH)

		if passive.effect_type == "aoe_damage":
			var affectedTiles = ShapeCaster.getCircle(monPos, passive.radius)
			for tile in affectedTiles:
				if not state.withinBounds(tile):
					continue
				var occupantID = state.board.at(tile)
				if occupantID == 0 or occupantID == monsterID:
					continue  # Skip empty tiles and the dying monster itself
				var target = state.getMonster(occupantID)
				if target == null or not target.is_alive():
					continue
				# Friendly fire: hits everyone in radius
				var damage = int(passive.value)
				var actualDamage = target.take_damage(damage)
				events.passive_aoe_damage.emit(monsterID, passive.name, occupantID, passive.element, actualDamage, target.hitpoints)
				if not target.is_alive():
					_handleDefeat(occupantID, monsterID)

func fireOnTargeted(targetID: int, attackerID: int) -> void:
	var target = state.getMonster(targetID)
	var attacker = state.getMonster(attackerID)
	if target == null or attacker == null or not attacker.is_alive() or not target.is_alive():
		return

	for passive in target.passives:
		if passive.trigger == ON_TARGETED:
			events.passive_triggered.emit(targetID, passive.name, ON_TARGETED)
			if passive.effect_type == "retaliate_damage":
				var damage = int(passive.value)
				var actualDamage = attacker.take_damage(damage)
				# Use a generic retaliate event or just emit the damage
				events.passive_aoe_damage.emit(targetID, passive.name, attackerID, passive.element, actualDamage, attacker.hitpoints)
				if not attacker.is_alive():
					_handleDefeat(attackerID, targetID)

func _handleDefeat(defeatedID: int, killerID: int) -> void:
	events.monster_defeated.emit(defeatedID, killerID)
	state.removeMonster(defeatedID)
