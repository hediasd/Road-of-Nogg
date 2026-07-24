class_name BattleSample

var monsterTeamCoordinatesList = []
var boardSize: Vector2i

func _init() -> void:
	var board_size_x = 8
	var board_size_y = 8
	boardSize = Vector2i(board_size_x, board_size_y)

	# Team 1: The Heroes
	monsterTeamCoordinatesList.append({
		"NAME" = "Defaultgon", # Melee
		"TEAM" = 1,
		"POS" = Vector2i(1, 1)
	})
	monsterTeamCoordinatesList.append({
		"NAME" = "Smoke Cloud", # fire/darkness
		"TEAM" = 1,
		"POS" = Vector2i(0, 0)
	})
	monsterTeamCoordinatesList.append({
		"NAME" = "Oracle of Megnos", # fire/light
		"TEAM" = 1,
		"POS" = Vector2i(2, 0)
	})

	# Team 2: The Villains
	monsterTeamCoordinatesList.append({
		"NAME" = "Magemornus", # Ranged/Darkness
		"TEAM" = 2,
		"POS" = Vector2i(6, 6)
	})
	monsterTeamCoordinatesList.append({
		"NAME" = "Megidos", # Brawler/Fire
		"TEAM" = 2,
		"POS" = Vector2i(5, 5)
	})
	monsterTeamCoordinatesList.append({
		"NAME" = "Dump", # Simple
		"TEAM" = 2,
		"POS" = Vector2i(7, 7)
	})
	monsterTeamCoordinatesList.append({
		"NAME" = "Dump", # Simple
		"TEAM" = 2,
		"POS" = Vector2i(7, 6)
	})
