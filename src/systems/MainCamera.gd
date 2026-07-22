extends Node3D

class_name MainCamera

var draggingStartPosition: Vector3
var _moveCamera: bool = false;
var _rotCamera: bool = false;
var savedRotation
var savedPosition

var eventPosition
var lastDragPosition

func _ready() -> void:
	lastDragPosition = Vector3(0, 0, 0)
	savedRotation = rotation
	savedPosition = position

func _unhandled_input(event: InputEvent):

	eventPosition = Vector3(event.position.x, event.position.y, 0) / 1000;
	var x_bounds = abs(position.x) + 1
	var y_bounds = abs(position.y) + 1

	print("Event position ", eventPosition)

	if(event is InputEventMouseButton):
		#get_viewport().set_input_as_handled();
		draggingStartPosition = eventPosition;
		if(event.button_index == MOUSE_BUTTON_LEFT):
			if event.is_pressed():
				print("Clicking Left - dragging position updated to ", draggingStartPosition)
				_moveCamera = true;
			else:
				print("Unpressed Left")
				_moveCamera = false;
		elif(event.button_index == MOUSE_BUTTON_RIGHT):
			if event.is_pressed():
				print("Clicking Right - dragging position updated to ", draggingStartPosition)
				#_rotCamera = true;
			else:
				print("Unpressed Right")
				#_rotCamera = false;
		elif(event.button_index == MOUSE_BUTTON_WHEEL_UP):
			get_child(0).size -= .5
		elif(event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			get_child(0).size += .5

	elif (event is InputEventMouseMotion):

		print("Dragging from ", draggingStartPosition, " to ", eventPosition)
		#var draggingDifference: Vector3 = draggingStartPosition - eventPosition
		var currentDrag = eventPosition
		var draggingDifference = currentDrag - lastDragPosition

		var move = Vector3(0, 0, 0)

		if(_moveCamera):

			if(draggingDifference.x < -.004):
				move.x = -1
			elif(draggingDifference.x > .004):
				move.x = 1

			if(draggingDifference.y < -.004):
				move.y = -1
			elif(draggingDifference.y > .004):
				move.y = 1

			position += (move / 20)

		lastDragPosition = eventPosition
	#get_viewport().set_input_as_handled();
