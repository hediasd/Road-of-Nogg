## ConsoleRoundSummary — Formats end-of-round battle highlights.

class_name ConsoleRoundSummary

var logLine: Callable


func _init(_logLine: Callable) -> void:
	logLine = _logLine

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


func getElementEmoji(element: String) -> String:
	match element.to_lower():
		"fire": return "🔥"
		"water": return "💧"
		"wind": return "WIND"
		"earth": return "🪨"
		"wood": return "🌿"
		"steel": return "⚙️"
		"ice": return "❄️"
		"light": return "✨"
		"darkness": return "🌑"
		_: return "💥"


func _getSymbol(mon: Monster) -> String:
	if mon == null: return "[ ? ]"
	var n = mon.name.substr(0, 1).to_upper()
	return "[ %s ]" % n


func _split_name(name: String, max_len: int) -> Array:
	if name.length() <= max_len:
		return [name, ""]
	var space_idx = name.rfind(" ", max_len)
	if space_idx > 0:
		var part1 = name.substr(0, space_idx)
		var part2 = name.substr(space_idx + 1, max_len)
		return [part1, part2]
	else:
		return [name.substr(0, max_len), name.substr(max_len, max_len)]


func printRoundSummary(roundNumber: int, roundEvents: Array) -> void:
	if not roundEvents.is_empty():
		roundEvents.sort_custom(func(a, b): return a.score > b.score)

		logLine.call("")
		logLine.call(" ╭───────────────────────── 🌟 ROUND %s HIGHLIGHT 🌟 ─────────────────────────" % roundNumber)
		logLine.call(" │                                                                           ")

		var main = roundEvents[0]
		var aSym = _getSymbol(main.attacker)
		var tSym = _getSymbol(main.target)
		var aNameFull = main.attacker.name if main.attacker != null else "???"
		var tNameFull = main.target.name if main.target != null else "???"
		var aParts = _split_name(aNameFull, 14)
		var tParts = _split_name(tNameFull, 14)

		var aName = aParts[0].rpad(14)
		var tName = tParts[0].lpad(14)
		var aName2 = aParts[1].rpad(14)
		var tName2 = tParts[1].lpad(14)
		var has_second_line = (aParts[1] != "" or tParts[1] != "")

		if main.type == "attack":
			logLine.call(" │                      %s 🗡️ ━━━━━━━▶ 💥 %s" % [aSym, tSym])
			logLine.call(" │                     ═══════                   ═══════")
			logLine.call(" │                   %s                 %s" % [aName, tName])
			if has_second_line:
				logLine.call(" │                   %s                 %s" % [aName2, tName2])
			if main.defeated:
				logLine.call(" │                                            ☠️ DEFEATED!")

		elif main.type == "spell":
			var emj = getElementEmoji(main.element)
			logLine.call(" │                      %s %s ━━━━━━━▶ 💥 %s" % [aSym, emj, tSym])
			logLine.call(" │                     ═══════                   ═══════")
			logLine.call(" │                   %s                 %s" % [aName, tName])
			if has_second_line:
				logLine.call(" │                   %s                 %s" % [aName2, tName2])
			if main.defeated:
				logLine.call(" │                                            ☠️ DEFEATED!")

		elif main.type == "heal":
			logLine.call(" │                      %s ✨ ━━━━━━━▶ 💖 %s" % [aSym, tSym])
			logLine.call(" │                     ═══════                   ═══════")
			logLine.call(" │                   %s                 %s" % [aName, tName])
			if has_second_line:
				logLine.call(" │                   %s                 %s" % [aName2, tName2])

		elif main.type == "skipped":
			logLine.call(" │                                 💤 %s" % main.reason.to_upper())
			logLine.call(" │                     ═══════                   ")
			logLine.call(" │                   %s                 " % aName)
			if has_second_line:
				logLine.call(" │                   %s                 " % aName2)

		logLine.call(" │                                                                           ")
		logLine.call(" │ ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈ ")
		logLine.call(" │  MINOR CLASHES:                                                           ")

		var minorLine1 = " │ "
		var minorLine2 = " │ "
		var minorLine3 = " │ "
		var minorLine4 = " │ "
		var has_minor_line4 = false

		var maxMinors = min(roundEvents.size() - 1, 2)
		if maxMinors > 0:
			for mIdx in range(1, maxMinors + 1):
				var m = roundEvents[mIdx]
				var maSym = _getSymbol(m.attacker)
				var mtSym = _getSymbol(m.target)

				var str1 = ""
				if m.type == "attack": str1 = "    %s 🗡️━━▶ 💥 %s" % [maSym, mtSym]
				elif m.type == "spell": str1 = "    %s %s━━▶ 💥 %s" % [maSym, getElementEmoji(m.element), mtSym]
				elif m.type == "heal": str1 = "    %s ✨━━▶ 💖 %s" % [maSym, mtSym]

				minorLine1 += _pad_right_visual(str1, 36)
				minorLine2 += _pad_right_visual("   ══════        ══════", 36)

				var maNameFull = m.attacker.name if m.attacker != null else "???"
				var mtNameFull = m.target.name if m.target != null else "???"
				var maParts = _split_name(maNameFull, 8)
				var mtParts = _split_name(mtNameFull, 8)

				var mn1 = maParts[0]
				var mn2 = mtParts[0]
				minorLine3 += _pad_right_visual("   " + mn1.rpad(8) + "      " + mn2.rpad(8), 36)

				if maParts[1] != "" or mtParts[1] != "":
					has_minor_line4 = true

				var mn1_p2 = maParts[1]
				var mn2_p2 = mtParts[1]
				minorLine4 += _pad_right_visual("   " + mn1_p2.rpad(8) + "      " + mn2_p2.rpad(8), 36)

			logLine.call(minorLine1)
			logLine.call(minorLine2)
			logLine.call(minorLine3)
			if has_minor_line4:
				logLine.call(minorLine4)
		else:
			logLine.call(" │  (None)")

		logLine.call(" ╰───────────────────────────────────────────────────────────────────────────")
		roundEvents.clear()
