extends Node3D


var rotationY = 0
var sometimes = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	#rotationY += 0.000001
	sometimes += 1

	if sometimes >= 5:
		sometimes = 0
		rotate_y(0.02)

	return
