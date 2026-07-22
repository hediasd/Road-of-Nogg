extends Node3D

var draggingStartPosition: Vector3
var _moveCamera: bool = false;
var _rotCamera: bool = false;
var savedRotation
var savedPosition

func _ready() -> void:
	savedRotation = rotation
	savedPosition = position

func _unhandled_input(event: InputEvent):

	var eventPosition = Vector3(event.position.x, event.position.y, 0) / 1000;
	var x_bounds = abs(position.x) + 1
	var y_bounds = abs(position.y) + 1

	print("Event position ", eventPosition)

	if(event is InputEventMouseButton):

		draggingStartPosition = eventPosition;
		if(event.button_index == MOUSE_BUTTON_RIGHT):
			if event.is_pressed():
				print("Clicking Right - dragging position updated to ", draggingStartPosition)
				_rotCamera = true;
			else:
				print("Unpressed Right")
				_rotCamera = false;
	elif (event is InputEventMouseMotion):

		print("Dragging from ", draggingStartPosition, " to ", eventPosition)
		var draggingDifference: Vector3 = draggingStartPosition - eventPosition

		var move = Vector3(0, 0, 0)

		if(_rotCamera):

			if(draggingDifference.x < -.1):
				move.y = -1
			elif(draggingDifference.x > .1):
				move.y = 1

			rotation += (move / 100)

	#get_viewport().set_input_as_handled();
