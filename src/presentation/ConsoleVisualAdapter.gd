## ConsoleVisualAdapter — Writes an ASCII/Emoji battle log to ai/battle_log.txt
## Replaces standard console print with a detailed, stylized textual output.

class_name ConsoleVisualAdapter
extends IBattleVisualAdapter

const ConsoleRoundSummaryScript = preload("res://src/presentation/ConsoleRoundSummary.gd")
const ConsoleMapRendererScript = preload("res://src/presentation/ConsoleMapRenderer.gd")

var state: BattleState
var logFile: String = "res://docs/battle_log.txt"
var _roundEvents: Array = []
var _roundPaths: Array = []
var roundSummary
var mapRenderer


func _init(_state: BattleState) -> void:
	state = _state
	var logger = Callable(self, "_log")
	roundSummary = ConsoleRoundSummaryScript.new(logger)
	mapRenderer = ConsoleMapRendererScript.new(state, logger)


func _log(text: String, append: bool = true) -> void:
	print(text)
	var file
	if append:
		file = FileAccess.open(logFile, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(logFile, FileAccess.WRITE)
	
	if file != null:
		file.store_line(text)
		file.close()


func _getElementEmoji(element: String) -> String:
	return roundSummary.getElementEmoji(element)


func _on_battle_started(boardSize: Vector2i, _monsterList: Array) -> void:
	_log("", false) # clear file
	_log("╔══════════════════════════════════════════════════════════════╗")
	_log("║                    ⚔️ BATTLE START! ⚔️                      ║")
	_log("║    Board: %sx%s                                             ║" % [boardSize.x, boardSize.y])
	_log("╚══════════════════════════════════════════════════════════════╝")
	_log("")
	printBoardState()


func _on_battle_ended(winningTeam: int) -> void:
	_log("")
	_log("╔══════════════════════════════════════════════════════════════╗")
	_log("║             🏆 BATTLE OVER — TEAM %s WINS! 🏆               ║" % winningTeam)
	_log("╚══════════════════════════════════════════════════════════════╝")
	_log("")


func _on_round_started(roundNumber: int, turnOrderIDs: Array) -> void:
	_log("")
	_log("══════════════════════ 🔄 ROUND %s ══════════════════════" % roundNumber)
	var orderNames = []
	for id in turnOrderIDs:
		var mon = state.getMonster(id)
		if mon != null:
			orderNames.append("%s#%s" % [mon.name, id])
	_log("  Turn order: %s" % ", ".join(orderNames))
	_log("")


func _on_turn_started(monsterID: int, _roundNumber: int, turnNumber: int) -> void:
	var mon = state.getMonster(monsterID)
	var pos = state.getMonsterPosition(monsterID)
	_log("▶ Turn %s: %s #%s (Team %s) at %s | HP: ❤️ %s/%s" % [
		turnNumber, mon.name, monsterID, mon.team, pos, mon.hitpoints, mon.max_hitpoints
	])


func _on_monster_skipped_turn(monsterID: int, reason: String) -> void:
	var mon = state.getMonster(monsterID)
	_log("  💤 [SKIP] %s #%s skipped turn: %s" % [mon.name, monsterID, reason])
	_roundEvents.append({ "score": 0, "type": "skipped", "attacker": mon, "reason": reason })


func _on_turn_ended(_monsterID: int) -> void:
	pass


func _on_monster_spawned(monsterID: int, monsterName: String, team: int, pos: Vector2i, stats: Dictionary) -> void:
	_log("  ✨ [SPAWN] %s #%s at %s — Team %s (HP:%s ATK:%s DEF:%s SPD:%s MOV:%s)" % [
		monsterName, monsterID, pos, team,
		stats.get("hp", "?"), stats.get("atk", "?"), stats.get("def", "?"),
		stats.get("spd", "?"), stats.get("move", "?")
	])


func _on_monster_moved(monsterID: int, path: Array) -> void:
	var mon = state.getMonster(monsterID)
	if path.is_empty():
		return
	var pathStr = " 👣 ".join(path.map(func(p): return str(p)))
	_log("  [MOVE] %s #%s: %s" % [mon.name, monsterID, pathStr])
	
	_roundPaths.append({"id": monsterID, "path": path.duplicate()})


func _on_monster_attacked(
		attackerID: int,
		targetPos: Vector2i,
		targetID: int,
		damage: int,
		targetNewHP: int) -> void:
	var attacker = state.getMonster(attackerID)
	var target = state.getMonster(targetID)
	if target == null:
		_log("  [ATTACK] %s #%s misses at %s" % [attacker.name, attackerID, targetPos])
		_roundEvents.append({
			"score": 0,
			"type": "attack",
			"attacker": attacker,
			"target": null,
			"element": "",
			"defeated": false
		})
		return
	_log("  [ATTACK] %s #%s attacks %s #%s (%s dmg | HP %s)" % [
		attacker.name, attackerID, target.name, targetID, damage, targetNewHP
	])
	_roundEvents.append({
		"score": damage * 2,
		"type": "attack",
		"attacker": attacker,
		"target": target,
		"element": "",
		"defeated": targetNewHP <= 0
	})


func _on_spell_cast_started(
		casterID: int,
		centerPos: Vector2i,
		spellName: String,
		_element: String,
		targetsHit: int,
		_resolvedRadius: int,
		_areaShape: String) -> void:
	if targetsHit == 0:
		var caster = state.getMonster(casterID)
		_log("  [SPELL] %s #%s casts '%s' at %s; no units affected" % [
			caster.name, casterID, spellName, centerPos
		])


func _on_monster_cast_spell(
		casterID: int,
		_centerPos: Vector2i,
		targetID: int,
		spellName: String,
		damageLines: Array,
		targetNewHP: int) -> void:
	var caster = state.getMonster(casterID)
	var target = state.getMonster(targetID)
	var targetName = target.name if target != null else "???"
	var damageTexts = []
	var primaryElement = "none"
	var totalDamage = 0
	if damageLines.is_empty():
		damageTexts.append("0")
	else:
		primaryElement = damageLines[0].get("element", "none")
		for line in damageLines:
			var element = line.get("element", "none")
			var damage = line.get("damage", 0)
			totalDamage += damage
			damageTexts.append("%s %s" % [damage, str(element).to_upper()] if element != "none" else str(damage))
	var combinedDamage = " + ".join(damageTexts)
	if damageLines.size() > 1:
		combinedDamage += " = %s" % totalDamage
	combinedDamage += " dmg"
	var emoji = _getElementEmoji(primaryElement)
	_log("  [SPELL] %s #%s %s -> %s #%s with '%s' (%s | HP %s)" % [
		caster.name, casterID, emoji, targetName, targetID, spellName,
		combinedDamage, targetNewHP
	])
	_roundEvents.append({
		"score": totalDamage * 2 + 5,
		"type": "spell",
		"attacker": caster,
		"target": target,
		"element": primaryElement,
		"defeated": targetNewHP <= 0
	})


func _on_monster_healed(
		casterID: int,
		_centerPos: Vector2i,
		targetID: int,
		spellName: String,
		amount: int,
		targetNewHP: int) -> void:
	var caster = state.getMonster(casterID)
	var target = state.getMonster(targetID)
	var targetName = target.name if target != null else "???"
	_log("  [HEAL] %s #%s -> %s #%s with '%s' (+%s HP | HP %s)" % [
		caster.name, casterID, targetName, targetID, spellName, amount, targetNewHP
	])
	_roundEvents.append({
		"score": amount * 3,
		"type": "heal",
		"attacker": caster,
		"target": target,
		"element": "",
		"defeated": false
	})

func _on_status_damage_dealt(monsterID: int, effectName: String, damage: int, targetNewHP: int) -> void:
	var mon = state.getMonster(monsterID)
	_log("  [STATUS] %s #%s suffers %s damage from %s! (❤️ %s)" % [
		mon.name, monsterID, damage, effectName.to_upper(), targetNewHP
	])


func _on_monster_defeated(monsterID: int, killerID: int) -> void:
	var mon = state.getMonster(monsterID)
	var monName = mon.name if mon != null else "???"
	if killerID == -1:
		_log("  ☠️ [DEFEATED] %s #%s succumbed to their wounds!" % [monName, monsterID])
	else:
		var killer = state.getMonster(killerID)
		var killerName = killer.name if killer != null else "???"
		_log("  ☠️ [DEFEATED] %s #%s was struck down by %s #%s!" % [monName, monsterID, killerName, killerID])
		if _roundEvents.size() > 0:
			_roundEvents[_roundEvents.size() - 1].score += 100


func _on_effect_applied(monsterID: int, effectName: String, duration: int, _sourceMonsterID: int, _sourceSpellName: String) -> void:
	var mon = state.getMonster(monsterID)
	var emoji = "🔥" if effectName == "burn" else "🌀"
	var span = (
		"permanently" if BattleState.isPermanentDuration(duration)
		else "for %s turns" % duration
	)
	_log("  [EFFECT+] %s #%s gained %s '%s' %s" % [mon.name, monsterID, emoji, effectName.to_upper(), span])


func _on_effect_removed(monsterID: int, effectName: String) -> void:
	var mon = state.getMonster(monsterID)
	_log("  [EFFECT-] %s #%s lost effect '%s'" % [mon.name, monsterID, effectName.to_upper()])


func _on_effect_ticked(monsterID: int, effectName: String, remainingTurns: int) -> void:
	pass


func _on_resonance_changed(monsterID: int, element: String, oldCharge: int, newCharge: int, reason: String) -> void:
	var mon = state.getMonster(monsterID)
	var monName = mon.name if mon != null else "???"
	var emoji = _getElementEmoji(element)
	_log("  [RESONANCE] %s #%s %s %s: %s -> %s (%s)" % [
		monName, monsterID, emoji, element.to_upper(), oldCharge, newCharge, reason
	])


func _on_passive_triggered(monsterID: int, passiveName: String, trigger: String) -> void:
	var mon = state.getMonster(monsterID)
	var monName = mon.name if mon != null else "???"
	_log("  [PASSIVE] %s #%s — '%s' activated! (trigger: %s)" % [monName, monsterID, passiveName, trigger])


func _on_passive_aoe_damage(sourceID: int, passiveName: String, targetID: int, element: String, damage: int, targetNewHP: int) -> void:
	var src = state.getMonster(sourceID)
	var tgt = state.getMonster(targetID)
	var srcName = src.name if src != null else "???"
	var tgtName = tgt.name if tgt != null else "???"
	_log("  [PASSIVE AOE] '%s' from %s #%s hits %s #%s for %s %s dmg! (❤️ %s)" % [
		passiveName, srcName, sourceID, tgtName, targetID, damage, element.to_upper(), targetNewHP
	])


func _on_round_ended(roundNumber: int) -> void:
	roundSummary.printRoundSummary(roundNumber, _roundEvents)
	mapRenderer.printTacticalMap(_roundPaths)
	_roundPaths.clear()


func printBoardState() -> void:
	## Prints an ASCII map of the board state using the standard tactical map formatter.
	mapRenderer.printTacticalMap(_roundPaths, true)
	_log("")
