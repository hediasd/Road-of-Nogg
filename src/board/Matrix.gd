class_name Matrix

var max_x: int
var max_y: int
var inner_array = []


func _init(x, y):
	max_x = x
	max_y = y

	for i in max_x:
		inner_array.append([])
		for j in max_y:
			inner_array[i].append(0)

func set_at(value: int, pos: Vector2i):
	inner_array[pos[0]][pos[1]] = value
	pass

func at_xy(x, y):
	return inner_array[x][y]


func at(pos):
	return at_xy(pos[0], pos[1])
