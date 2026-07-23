#!/usr/bin/env -S godot --headless --script
extends SceneTree

var games = {
	"Master of Monsters / Nectaris": ["PC Engine", 1989],
	"Fire Emblem Series": ["Famicom", 1990],
	"Langrisser / Der Langrisser": ["Mega Drive", 1991],
	"Langrisser Series": ["Mega Drive", 1991],
	"Super Robot Wars Series": ["Game Boy", 1991],
	"Shining Force Series": ["Genesis", 1992],
	"Ogre Battle / Ogre Battle 64": ["SNES", 1993],
	"Ogre Battle Series": ["SNES", 1993],
	"Ogre Battle 64": ["N64", 1999],
	"Phantasy Star Series (specifically PS IV)": ["Genesis", 1993],
	"Phantasy Star Series": ["Genesis", 1993],
	"Breath of Fire Series (BoF 1–4)": ["SNES", 1993],
	"Breath of Fire Series": ["SNES", 1993],
	"Energy Breaker & Feda: Emblem of Justice": ["SNES", 1994],
	"Energy Breaker": ["SNES", 1996],
	"Feda: Emblem of Justice": ["SNES", 1994],
	"Chrono Trigger": ["SNES", 1995],
	"Tactics Ogre: Let Us Cling Together / Reborn": ["SNES", 1995],
	"Tactics Ogre": ["SNES", 1995],
	"Suikoden Series & Suikoden Tactics": ["PS1", 1995],
	"Suikoden Series": ["PS1", 1995],
	"Vandal Hearts Series": ["PS1", 1996],
	"Treasure of the Rudras (Rudra no Hidou)": ["SNES", 1996],
	"Treasure of the Rudras": ["SNES", 1996],
	"Pokémon Series (Mainline & Mystery Dungeon / Conquest)": ["Game Boy", 1996],
	"Pokémon Series": ["Game Boy", 1996],
	"Pokemon Series": ["Game Boy", 1996],
	"Popolocrois Series": ["PS1", 1996],
	"Sakura Wars": ["Saturn", 1996],
	"Bahamut Lagoon": ["SNES", 1996],
	"Final Fantasy Tactics (FFT)": ["PS1", 1997],
	"Final Fantasy Tactics": ["PS1", 1997],
	"Grandia Series & Octopath Traveler": ["Saturn", 1997],
	"Grandia Series": ["Saturn", 1997],
	"Panzer Dragoon Saga": ["Saturn", 1998],
	"Threads of Fate (Dewprism)": ["PS1", 1999],
	"Threads of Fate": ["PS1", 1999],
	"Vagrant Story": ["PS1", 2000],
	"Hoshigami: Ruining Blue Earth": ["PS1", 2001],
	"TearRing Saga & Berwick Saga": ["PS1", 2001],
	"Advance Wars Series": ["GBA", 2001],
	"Advance Wars": ["GBA", 2001],
	"Digimon World 3": ["PS1", 2002],
	"Ragnarok Online": ["PC", 2002],
	"Disgaea Series": ["PS2", 2003],
	"MapleStory": ["PC", 2003],
	"Final Fantasy Tactics Advance (FFTA) / FFTA2": ["GBA", 2003],
	"Final Fantasy Tactics Advance (FFTA)": ["GBA", 2003],
	"Final Fantasy Tactics Advance": ["GBA", 2003],
	"FFTA": ["GBA", 2003],
	"Dofus & Wakfu": ["PC", 2004],
	"Phantom Brave / Makai Kingdom": ["PS2", 2004],
	"Stella Deus: The Gate of Eternity": ["PS2", 2004],
	"World of Warcraft": ["PC", 2004],
	"Yggdra Union": ["GBA", 2006],
	"Wild Arms XF": ["PSP", 2007],
	"Knights in the Nightmare": ["NDS", 2008],
	"Dragon Quest 9": ["NDS", 2009],
	"XCOM / XCOM 2": ["PC", 2012],
	"Divinity: Original Sin 1 & 2": ["PC", 2014],
	"Divinity: OS 2": ["PC", 2014],
	"Mario + Rabbids Kingdom Battle": ["Switch", 2017],
	"Mario + Rabbids": ["Switch", 2017],
	"Into the Breach": ["PC", 2018],
	"Octopath Traveler": ["Switch", 2018],
	"Triangle Strategy": ["Switch", 2022],
	"Road of Nogg": ["PC", 2026],
	"Road of Nogg (Current)": ["PC", 2026]
}

func get_sort_key(name: String) -> Array:
	var clean = name.replace("*", "").strip_edges()
	var regex = RegEx.new()
	regex.compile("\\s*\\([^)]*\\)")
	clean = regex.sub(clean, "").strip_edges()
	
	if games.has(name): return [games[name][1], name.to_lower()]
	if games.has(clean): return [games[clean][1], clean.to_lower()]
	
	for k in games.keys():
		if k in name or name in k:
			return [games[k][1], name.to_lower()]
			
	return [9999, name.to_lower()]

func custom_sort(a: String, b: String) -> bool:
	var key_a = get_sort_key(a)
	var key_b = get_sort_key(b)
	if key_a[0] != key_b[0]:
		return key_a[0] < key_b[0]
	return key_a[1] < key_b[1]

func _init():
	print("Starting gamerefs update...")
	var dir = DirAccess.open("res://gamerefs")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".md") and file_name.begins_with("trpg_"):
				process_file("res://gamerefs/" + file_name)
			file_name = dir.get_next()
	
	process_master_index("res://gamerefs/tactical_rpg_turn_systems.md")
	print("Done!")
	quit()

func process_file(filepath: String):
	var file = FileAccess.open(filepath, FileAccess.READ)
	if not file: return
	
	var lines = []
	while not file.eof_reached():
		lines.append(file.get_line())
	file.close()
	if lines.size() > 0 and lines[-1] == "": lines.pop_back()
	
	var out_lines = []
	var i = 0
	var in_checklist = false
	var checklist_buffer = []
	
	while i < lines.size():
		var line = lines[i]
		
		if line.begins_with("* **Games Following This Approach:**"):
			var prefix = "* **Games Following This Approach:** *"
			var games_str = line.substr(prefix.length()).strip_edges()
			if games_str.ends_with("*"):
				games_str = games_str.substr(0, games_str.length() - 1)
			
			var games_list = Array(games_str.split(","))
			for j in range(games_list.size()):
				games_list[j] = games_list[j].strip_edges()
				
			games_list.sort_custom(custom_sort)
			
			var tagged_games = []
			for g in games_list:
				var clean_g = g.replace("*", "").strip_edges()
				var key = get_sort_key(clean_g)
				if key[0] != 9999:
					var found = false
					for gk in games.keys():
						if gk in clean_g or clean_g in gk:
							var tag = " (" + str(games[gk][0]) + ", " + str(games[gk][1]) + ")"
							if not tag in clean_g:
								tagged_games.append(clean_g + tag)
							else:
								tagged_games.append(clean_g)
							found = true
							break
					if not found: tagged_games.append(clean_g)
				else:
					tagged_games.append(clean_g)
			
			out_lines.append("* **Games Following This Approach:** *" + ", ".join(tagged_games) + "*")
			i += 1
			continue
			
		if line.strip_edges().begins_with("*(Ensuring all"):
			in_checklist = true
			out_lines.append(line)
			i += 1
			continue
			
		if in_checklist:
			if line.begins_with("- "):
				checklist_buffer.append(line)
			else:
				checklist_buffer.sort_custom(custom_sort)
				var regex = RegEx.new()
				regex.compile("- (.*?) \\(")
				for j in range(checklist_buffer.size()):
					var match = regex.search(checklist_buffer[j])
					if match:
						var gname = match.get_string(1).strip_edges()
						for gk in games.keys():
							if gk == gname:
								var tag = " (" + str(games[gk][0]) + ", " + str(games[gk][1]) + ")"
								if not tag in checklist_buffer[j]:
									checklist_buffer[j] = checklist_buffer[j].replace(gname, gname + tag)
								break
				out_lines.append_array(checklist_buffer)
				checklist_buffer.clear()
				in_checklist = false
				out_lines.append(line)
			i += 1
			continue
			
		out_lines.append(line)
		i += 1
		
	if in_checklist and checklist_buffer.size() > 0:
		checklist_buffer.sort_custom(custom_sort)
		var regex = RegEx.new()
		regex.compile("- (.*?) \\(")
		for j in range(checklist_buffer.size()):
			var match = regex.search(checklist_buffer[j])
			if match:
				var gname = match.get_string(1).strip_edges()
				for gk in games.keys():
					if gk == gname:
						var tag = " (" + str(games[gk][0]) + ", " + str(games[gk][1]) + ")"
						if not tag in checklist_buffer[j]:
							checklist_buffer[j] = checklist_buffer[j].replace(gname, gname + tag)
						break
		out_lines.append_array(checklist_buffer)
		
	file = FileAccess.open(filepath, FileAccess.WRITE)
	for l in out_lines:
		file.store_line(l)
	file.close()

func process_master_index(filepath: String):
	var file = FileAccess.open(filepath, FileAccess.READ)
	if not file: return
	var lines = []
	while not file.eof_reached():
		lines.append(file.get_line())
	file.close()
	if lines.size() > 0 and lines[-1] == "": lines.pop_back()
	
	var out_lines = []
	var i = 0
	var in_numbered = false
	var numbered_buffer = []
	var num_regex = RegEx.new()
	num_regex.compile("^\\d+\\.\\s+\\*\\*")
	
	var in_matrix = false
	var matrix_buffer = []
	
	while i < lines.size():
		var line = lines[i]
		
		if num_regex.search(line):
			in_numbered = true
			numbered_buffer.append(line)
			i += 1
			continue
		elif in_numbered and line.strip_edges() == "":
			numbered_buffer.sort_custom(custom_sort)
			var nregex2 = RegEx.new()
			nregex2.compile("\\*\\*(.*?)\\*\\*")
			var prefix_regex = RegEx.new()
			prefix_regex.compile("^\\d+\\.\\s+")
			for j in range(numbered_buffer.size()):
				var match = nregex2.search(numbered_buffer[j])
				if match:
					var gname = match.get_string(1)
					var tag = ""
					for gk in games.keys():
						if gk == gname or gk in gname:
							tag = " (" + str(games[gk][0]) + ", " + str(games[gk][1]) + ")"
							break
					var clean_line = prefix_regex.sub(numbered_buffer[j], "")
					if tag != "" and not tag in clean_line:
						clean_line = clean_line.replace("**" + gname + "**", "**" + gname + "**" + tag)
					out_lines.append(str(j+1) + ". " + clean_line)
			in_numbered = false
			numbered_buffer.clear()
			out_lines.append(line)
			i += 1
			continue
			
		if line.begins_with("| **"):
			in_matrix = true
			matrix_buffer.append(line)
			i += 1
			continue
		elif in_matrix and not line.begins_with("|"):
			matrix_buffer.sort_custom(custom_sort)
			var mregex = RegEx.new()
			mregex.compile("\\|\\s*\\*\\*(.*?)\\*\\*")
			for j in range(matrix_buffer.size()):
				var match = mregex.search(matrix_buffer[j])
				if match:
					var gname = match.get_string(1)
					var tag = ""
					for gk in games.keys():
						if gk == gname:
							tag = " (" + str(games[gk][0]) + ", " + str(games[gk][1]) + ")"
							break
					if tag != "" and not tag in matrix_buffer[j]:
						matrix_buffer[j] = matrix_buffer[j].replace("**" + gname + "**", "**" + gname + "**" + tag)
			out_lines.append_array(matrix_buffer)
			in_matrix = false
			matrix_buffer.clear()
			out_lines.append(line)
			i += 1
			continue
			
		out_lines.append(line)
		i += 1
		
	file = FileAccess.open(filepath, FileAccess.WRITE)
	for l in out_lines:
		file.store_line(l)
	file.close()
