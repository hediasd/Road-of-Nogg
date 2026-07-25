## ConsoleMapRenderer — Formats tactical-map snapshots for console output.

class_name ConsoleMapRenderer

var state: BattleState
var logLine: Callable


func _init(_state: BattleState, _logLine: Callable) -> void:
	state = _state
	logLine = _logLine

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

	lines.append("      #=Tree   ~=Abyss   >=Path")

	return { "chars": mon_chars, "lines": lines }


func printTacticalMap(roundPaths: Array, force: bool = false) -> void:
	if not force and roundPaths.is_empty():
		return

	var legend_data = _build_legend()
	var mon_chars = legend_data["chars"]
	var legend_lines = legend_data["lines"]

	logLine.call("")
	logLine.call(" ╭────────────────────────────── TACTICAL MAP ──────────────────────────────")
	logLine.call(" │")

	var grid = []
	for y in range(state.boardSize.y):
		var row = []
		for x in range(state.boardSize.x):
			if state.terrainBoard.at(Vector2i(x, y)) == 1:
				row.append("# ")
			elif state.terrainBoard.at(Vector2i(x, y)) == 2:
				row.append("~ ")
			else:
				row.append(". ")
		grid.append(row)

	for pData in roundPaths:
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

		logLine.call(rowStr)

	logLine.call(" ╰───────────────────────────────────────────────────────────────────────────")
