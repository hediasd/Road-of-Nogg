## Drawn three-step charge indicator for one owned element.
##
## Uses rectangles instead of typed symbols because the shipping font has no
## suitable filled/empty square pair. The owner supplies the catalog element
## and already-clamped Resonance charge.

class_name ResonanceBar
extends Control

const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

var _element: String
var _charge: int


func _init(element: String, charge: int) -> void:
	_element = element
	_charge = clampi(charge, 0, NoggThemeScript.RESONANCE_BAR_CELLS)
	custom_minimum_size = Vector2(NoggThemeScript.RESONANCE_BAR_WIDTH, NoggThemeScript.RESONANCE_CELL_SIZE)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	for index in NoggThemeScript.RESONANCE_BAR_CELLS:
		var cell_rect := Rect2(
			index * (NoggThemeScript.RESONANCE_CELL_SIZE + NoggThemeScript.RESONANCE_CELL_GAP),
			0.0,
			NoggThemeScript.RESONANCE_CELL_SIZE,
			NoggThemeScript.RESONANCE_CELL_SIZE
		)
		if index < _charge:
			draw_rect(cell_rect, BattleMeshFactoryScript.elementColor(_element))
		else:
			draw_rect(cell_rect, NoggThemeScript.TEXT_DIM, false, 1.0, false)
