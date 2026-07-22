extends Node

var speed = 400
var vec3
var input_direction = 1

func get_input():
	input_direction = Input.get_vector("left", "right", "up", "down")
	vec3 = Vector3(input_direction.x * 10, input_direction.y * 10, 0)

func _input(event):
	
	if event is InputEventKey:
		print(event.as_text())
	
	if event is InputEventKey and event.pressed:
		if(event.as_text() == "Right"):
			translate(Vector3(1, 0, 0))
		elif(event.as_text() == "Left"):
			translate(Vector3(-1, 0, 0))
		elif(event.as_text() == "Up"):
			translate(Vector3(0, 0, -1))
		elif(event.as_text() == "Down"):
			translate(Vector3(0, 0, 1))


func _physics_process(delta):
	pass
	
