## ConsoleVisualAdapter — Writes an ASCII/Emoji battle log to ai/battle_log.txt
## Replaces standard console print with a detailed, stylized textual output.

class_name ConsoleVisualAdapter
extends IBattleVisualAdapter

var state: BattleState
var logFile: String = "res://ai/battle_log.txt"
var _roundEvents: Array = []
var _roundPaths: Array = []


func _init(_state: BattleState) -> void:
	state = _state


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


func _build_legend() -> Dictionary:
	var t1_idx = 0
	var t2_idx = 0
	var mon_chars = {}
	var t1_list = []
	var t2_list = []
	
	for id in state.getAliveMonsterIDs():
		var mon = state.getMonster(id)
		if mon.team == 1:
			var c = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[t1_idx % 26]
			t1_idx += 1
			mon_chars[id] = c + " "
			t1_list.append("%s=%s" % [c, mon.name.substr(0,10)])
		else:
			var c = "abcdefghijklmnopqrstuvwxyz"[t2_idx % 26]
			t2_idx += 1
			mon_chars[id] = c + " "
			t2_list.append("%s=%s" % [c, mon.name.substr(0,10)])
			
	var lines = []
	var max_len = max(t1_list.size(), t2_list.size())
	for i in range(max_len):
		var p1 = (t1_list[i] + " (T1)").rpad(20) if i < t1_list.size() else "".rpad(20)
		var p2 = (t2_list[i] + " (T2)") if i < t2_list.size() else ""
		lines.append("      " + p1 + p2)
		
	lines.append("      #=Tree              >=Path")
	
	return { "chars": mon_chars, "lines": lines }


func _visual_length(text: String) -> int:
	var vlen = 0
	for i in range(text.length()):
		var c = text.unicode_at(i)
		if c == 0xFE0F:
			pass
		elif (c >= 0x2600 and c <= 0x27BF) or c >= 0x1F000:
			vlen += 2
		else:
			vlen += 1
	return vlen


func _pad_right_visual(text: String, total_width: int) -> String:
	var vlen = _visual_length(text)
	if vlen < total_width:
		return text + " ".repeat(total_width - vlen)
	return text


func _getElementEmoji(element: String) -> String:
	match element.to_lower():
		"fire": return "🔥"
		"water": return "💧"
		"earth": return "🪨"
		"wood": return "🌿"
		"steel": return "⚙️"
		"ice": return "❄️"
		"light": return "✨"
		"darkness": return "🌑"
		_: return "💥"


func _getSymbol(mon: Monster) -> String:
	if mon == null: return "[ ? ]"
	var n = mon.name.to_lower()
	if "mage" in n: return "< M >"
	if "emagnus" in n: return "( H )"
	if "megidos" in n: return "{ B }"
	return "[ D ]"


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


func _on_monster_attacked(attackerID: int, targetID: int, damage: int, targetNewHP: int) -> void:
	var attacker = state.getMonster(attackerID)
	var target = state.getMonster(targetID)
	var targetName = target.name if target != null else "???"
	
	_log("  [ATTACK] %s #%s  👊━━━▶  %s #%s (💥 %s dmg | ❤️ %s)" % [
		attacker.name, attackerID, targetName, targetID, damage, targetNewHP
	])
	
	_roundEvents.append({
		"score": damage * 2,
		"type": "attack",
		"attacker": attacker,
		"target": target,
		"element": "",
		"defeated": targetNewHP <= 0
	})


func _on_monster_cast_spell(casterID: int, targetID: int, spellName: String, element: String, damage: int, targetNewHP: int) -> void:
	var caster = state.getMonster(casterID)
	var target = state.getMonster(targetID)
	var targetName = target.name if target != null else "???"
	var emoji = _getElementEmoji(element)
	
	_log("  [SPELL] %s #%s  %s━━━▶  %s #%s with '%s' (💥 %s dmg | ❤️ %s)" % [
		caster.name, casterID, emoji, targetName, targetID, spellName, damage, targetNewHP
	])
	
	_roundEvents.append({
		"score": damage * 2 + 5,
		"type": "spell",
		"attacker": caster,
		"target": target,
		"element": element,
		"defeated": targetNewHP <= 0
	})


func _on_monster_healed(casterID: int, targetID: int, spellName: String, amount: int, targetNewHP: int) -> void:
	var caster = state.getMonster(casterID)
	var target = state.getMonster(targetID)
	var targetName = target.name if target != null else "???"
	
	_log("  [HEAL] %s #%s  ❤️━━━▶  %s #%s with '%s' (+%s HP | ❤️ %s)" % [
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
	_log("  [EFFECT+] %s #%s gained %s '%s' for %s turns" % [mon.name, monsterID, emoji, effectName.to_upper(), duration])


func _on_effect_removed(monsterID: int, effectName: String) -> void:
	var mon = state.getMonster(monsterID)
	_log("  [EFFECT-] %s #%s lost effect '%s'" % [mon.name, monsterID, effectName.to_upper()])


func _on_effect_ticked(monsterID: int, effectName: String, remainingTurns: int) -> void:
	pass


func _on_round_ended(roundNumber: int) -> void:
	if not _roundEvents.is_empty():
		_roundEvents.sort_custom(func(a, b): return a.score > b.score)
		
		_log("")
		_log(" ╭───────────────────────── 🌟 ROUND %s HIGHLIGHT 🌟 ─────────────────────────" % roundNumber)
		_log(" │                                                                           ")
		
		var main = _roundEvents[0]
		var aSym = _getSymbol(main.attacker)
		var tSym = _getSymbol(main.target)
		var aName = main.attacker.name.rpad(14) if main.attacker != null else "???".rpad(14)
		var tName = main.target.name.lpad(14) if main.target != null else "???".lpad(14)
		
		if main.type == "attack":
			_log(" │                      %s 🗡️ ━━━━━━━▶ 💥 %s" % [aSym, tSym])
			_log(" │                     ═══════                   ═══════")
			_log(" │                   %s                 %s" % [aName, tName])
			if main.defeated:
				_log(" │                                            ☠️ DEFEATED!")
				
		elif main.type == "spell":
			var emj = _getElementEmoji(main.element)
			_log(" │                      %s %s ━━━━━━━▶ 💥 %s" % [aSym, emj, tSym])
			_log(" │                     ═══════                   ═══════")
			_log(" │                   %s                 %s" % [aName, tName])
			if main.defeated:
				_log(" │                                            ☠️ DEFEATED!")
				
		elif main.type == "heal":
			_log(" │                      %s ✨ ━━━━━━━▶ 💖 %s" % [aSym, tSym])
			_log(" │                     ═══════                   ═══════")
			_log(" │                   %s                 %s" % [aName, tName])
			
		elif main.type == "skipped":
			_log(" │                                 💤 %s" % main.reason.to_upper())
			_log(" │                     ═══════                   ")
			_log(" │                   %s                 " % aName)

		_log(" │                                                                           ")
		_log(" │ ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈ ")
		_log(" │  MINOR CLASHES:                                                           ")
		
		var minorLine1 = " │ "
		var minorLine2 = " │ "
		var minorLine3 = " │ "
		
		var maxMinors = min(_roundEvents.size() - 1, 2)
		if maxMinors > 0:
			for mIdx in range(1, maxMinors + 1):
				var m = _roundEvents[mIdx]
				var maSym = _getSymbol(m.attacker)
				var mtSym = _getSymbol(m.target)
				
				var str1 = ""
				if m.type == "attack": str1 = "    %s 🗡️━━▶ 💥 %s" % [maSym, mtSym]
				elif m.type == "spell": str1 = "    %s %s━━▶ 💥 %s" % [maSym, _getElementEmoji(m.element), mtSym]
				elif m.type == "heal": str1 = "    %s ✨━━▶ 💖 %s" % [maSym, mtSym]
				
				minorLine1 += _pad_right_visual(str1, 36)
				minorLine2 += _pad_right_visual("   ══════        ══════", 36)
				var mn1 = m.attacker.name.substr(0,8) if m.attacker != null else "???"
				var mn2 = m.target.name.substr(0,8) if m.target != null else "???"
				minorLine3 += _pad_right_visual("   " + mn1.rpad(8) + "      " + mn2.rpad(8), 36)
				
			_log(minorLine1)
			_log(minorLine2)
			_log(minorLine3)
		else:
			_log(" │  (None)")
			
		_log(" ╰───────────────────────────────────────────────────────────────────────────")
		_roundEvents.clear()

	_print_tactical_map()
	_roundPaths.clear()


func _print_tactical_map() -> void:
	if _roundPaths.is_empty():
		return
		
	var legend_data = _build_legend()
	var mon_chars = legend_data["chars"]
	var legend_lines = legend_data["lines"]
		
	_log("")
	_log(" ╭────────────────────────────── TACTICAL MAP ──────────────────────────────")
	_log(" │")
	
	var grid = []
	for y in range(state.boardSize.y):
		var row = []
		for x in range(state.boardSize.x):
			if state.terrainBoard.at(Vector2i(x, y)) == 1:
				row.append("# ")
			else:
				row.append(". ")
		grid.append(row)
		
	for pData in _roundPaths:
		var path = pData.path
		for i in range(path.size() - 1):
			var curr = path[i]
			var nxt = path[i+1]
			var prev = path[i-1] if i > 0 else null
			
			var char_str = "+ "
			if i == path.size() - 2:
				var d_out = nxt - curr
				if d_out == Vector2i(1,0): char_str = "> "
				elif d_out == Vector2i(-1,0): char_str = "< "
				elif d_out == Vector2i(0,1): char_str = "v "
				elif d_out == Vector2i(0,-1): char_str = "^ "
			else:
				if prev == null:
					if nxt.x != curr.x: char_str = "- "
					else: char_str = "| "
				else:
					var d_in = curr - prev
					var d_out = nxt - curr
					
					if d_in.y == 0 and d_out.y == 0: char_str = "- "
					elif d_in.x == 0 and d_out.x == 0: char_str = "| "
					else: char_str = "+ "
			
			grid[curr.y][curr.x] = char_str
			
	for id in state.getAliveMonsterIDs():
		var pos = state.getMonsterPosition(id)
		if mon_chars.has(id):
			grid[pos.y][pos.x] = mon_chars[id]
		
	for y in range(state.boardSize.y):
		var rowStr = " │     " # padding on left
		for x in range(state.boardSize.x):
			rowStr += grid[y][x]
			
		if y < legend_lines.size():
			rowStr += legend_lines[y]
			
		_log(rowStr)
		
	_log(" ╰───────────────────────────────────────────────────────────────────────────")


func printBoardState() -> void:
	## Prints an ASCII map of the board state.
	var legend_data = _build_legend()
	var mon_chars = legend_data["chars"]
	var legend_lines = legend_data["lines"]
	
	_log("")
	_log("    " + " ".join(range(state.boardSize.x).map(func(i): return str(i % 10))))
	_log("  ┌" + "─".repeat(state.boardSize.x * 2 + 1) + "┐")
	
	for y in range(state.boardSize.y):
		var rowStr = str(y).lpad(2) + " │ "
		for x in range(state.boardSize.x):
			if state.terrainBoard.at(Vector2i(x, y)) == 1:
				rowStr += "# "
				continue
				
			var id = state.board.at(Vector2i(x, y))
			if id == 0:
				rowStr += ". "
			else:
				if mon_chars.has(id):
					rowStr += mon_chars[id]
				else:
					rowStr += "? "
		rowStr += "│"
		
		if y < legend_lines.size():
			rowStr += legend_lines[y]
			
		_log(rowStr)
		
	_log("  └" + "─".repeat(state.boardSize.x * 2 + 1) + "┘")
	_log("")
