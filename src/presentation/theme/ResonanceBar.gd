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
	# NoggTheme's cell size and gap are already whole device pixels (they come
	# through `_scaled()`), so a whole-numbered index times a whole-numbered sum
	# keeps every cell's origin on a whole pixel too — nothing here needs its
	# own rounding.
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
			# Scaled rather than a hardcoded 1.0: a fixed line weight would read
			# as a heavier stroke at x1 than at x4 relative to the cell it
			# outlines, instead of tracking the same scale everything else does.
			draw_rect(
				cell_rect, NoggThemeScript.TEXT_DIM, false,
				NoggThemeScript.RESONANCE_CELL_BORDER, false
			)
