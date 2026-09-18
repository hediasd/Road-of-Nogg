## Authored constants for the two elemental-cube placeholder rituals.
##
## Both profiles depict the same source-bound channeling language and differ
## only in choreography. Crownburst is the hostile cast fallback; Spiral
## Invocation is the support and utility fallback. Explicit spell profiles
## always win over either placeholder.

class_name ElementalCubeRitualProfile
extends RefCounted

const CROWNBURST_PROFILE_ID := "elemental_cube_crownburst"
const SPIRAL_PROFILE_ID := "elemental_cube_spiral"

## AUTHORED from the accepted interactive choreography sketch. Reference mode
## preserves the sketch's full timing; battle mode keeps the same normalized
## beats while fitting the tactical action queue.
const REFERENCE_DURATION_SECONDS := 5.20
const BATTLE_DURATION_SECONDS := 2.10
const SETTLE_NORMALIZED_TIME := 0.76
const ACTION_HOLD_FRACTION := 0.76

## AUTHORED shared carrier and motion values. The four motion values are the
## accepted maximum slider settings from the sketch.
const CUBE_COUNT := 8
const CUBE_SIZE_U := 0.24
const SPRITE_FRAME_SIZE_PX := 32
const SPRITE_ROTATION_FRAMES := 12
const SPRITE_PIXEL_SIZE_U := CUBE_SIZE_U / float(SPRITE_FRAME_SIZE_PX)
const ORBIT_TURNS := 2.40
const SPIN_TURNS := 3.20
const ACCELERATION := 2.80
const DISSIPATION := 2.40

## AUTHORED exact 32x32 Wind cube cropped from `element cubes.png`. Each
## character is one source pixel: direct, middle, shadow, or transparent. This
## is frame zero of the quarter-turn atlas; the other eleven frames reconstruct
## only the rotation between exact source poses and use the same three roles.
const SOURCE_FRAME_ROWS: Array[String] = [
	".............MDDDDM.............",
	"...........MDDDDDDDDM...........",
	".........MDDDDDDDDDDDDM.........",
	".......MDDDDDDDDDDDDDDDDM.......",
	".....MDDDDDDDDDDDDDDDDDDDDM.....",
	"...MDDDDDDDDDDDDDDDDDDDDDDDDM...",
	".MDDDDDDDDDDDDDDDDDDDDDDDDDDDDM.",
	"DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDM",
	"SMDDDDDDDDDDDDDDDDDDDDDDDDDDDDMM",
	"MSSMDDDDDDDDDDDDDDDDDDDDDDDDMMMM",
	"MSSSSSMDDDDDDDDDDDDDDDDDDMMMMMMM",
	"SSSSSSSSMDDDDDDDDDDDDDDMMMMMMMMM",
	"MSSSSSSSSSSMDDDDDDDDMMMMMMMMMMMM",
	"SSSSSSSSSSSSSMDDDDMMMMMMMMMMMMMM",
	"SSSSSSSSSSSSSSSMMMMMMMMMMMMMMMMM",
	"SSSSSSSSSSSSSSSSMMMMMMMMMMMMMMMM",
	"SSSSSSSSSSSSSSSSMMMMMMMMMMMMMMMM",
	"SSSSSSSSSSSSSSSSMMMMMMMMMMMMMMMM",
	"SSSSSSSSSSSSSSSSMMMMMMMMMMMMMMMM",
	"SSSSSSSSSSSSSSSSMMMMMMMMMMMMMMMM",
	"SSSSSSSSSSSSSSSSMMMMMMMMMMMMMMMM",
	"MSSSSSSSSSSSSSSSMMMMMMMMMMMMMMMM",
	"MSSSSSSSSSSSSSSSMMMMMMMMMMMMMMMM",
	"SSSSSSSSSSSSSSSSMMMMMMMMMMMMMMMM",
	"MSSSSSSSSSSSSSSSMMMMMMMMMMMMMMMS",
	"..MSSSSSSSSSSSSSMMMMMMMMMMMMMS..",
	"....MSSSSSSSSSSSMMMMMMMMMMMS....",
	"......MSSSSSSSSSMMMMMMMMMS......",
	"........MSSSSSSSMMMMMMMS........",
	"..........MSSSSSMMMMMS..........",
	"............MSSSMMMS............",
	"..............SSMS..............",
]

## AUTHORED Crownburst path.
const CROWN_INNER_RADIUS_U := 0.26
const CROWN_RADIUS_U := 1.02
const CROWN_RELEASE_DISTANCE_U := 1.55
const CROWN_START_HEIGHT_U := 0.90
const CROWN_HEIGHT_U := 1.18
const CROWN_FALL_DISTANCE_U := 0.50
const CROWN_BREATH_U := 0.025
const CROWN_MANIFEST_START := 0.02
const CROWN_MANIFEST_END := 0.17
const CROWN_ARRIVAL_START := 0.04
const CROWN_ARRIVAL_END := 0.36
const CROWN_RELEASE_START := 0.72
const CROWN_RELEASE_END := 0.99
const CROWN_DISSOLVE_START := 0.76
const CROWN_DISSOLVE_END := 0.95

## AUTHORED Spiral Invocation train. A 0.04 progress gap makes each cube use
## almost exactly the path vacated by the one ahead without visually grouping.
const SPIRAL_LINE_GAP := 0.04
const SPIRAL_EXIT_WINDOW := 0.18
const SPIRAL_MANIFEST_WINDOW := 0.07
const SPIRAL_INNER_RADIUS_U := 0.34
const SPIRAL_RADIUS_U := 0.86
const SPIRAL_RADIUS_SETTLE_PROGRESS := 0.22
const SPIRAL_HEIGHT_U := 1.55
const SPIRAL_BASE_HEIGHT_U := 0.04

## AUTHORED element palettes accepted in the cube sketch: direct, middle,
## shadow. Reference colours mirror BattleMeshFactory.elementColor() and let
## the factory's existing Color-only effect boundary stay unchanged.
const ELEMENT_REFERENCE_COLORS := {
	"fire": Color(0.9, 0.2, 0.2),
	"water": Color(0.1, 0.4, 0.9),
	"ice": Color(0.6, 0.9, 0.9),
	"wind": Color(0.55, 0.9, 0.78),
	"earth": Color(0.6, 0.4, 0.2),
	"wood": Color(0.2, 0.7, 0.2),
	"thunder": Color(0.9, 0.9, 0.1),
	"darkness": Color(0.4, 0.1, 0.6),
	"light": Color(0.9, 0.9, 0.8),
	"steel": Color(0.6, 0.6, 0.75),
}
const ELEMENT_PALETTES := {
	"wind": [Color("99e550"), Color("6abe30"), Color("37946e")],
	"fire": [Color("d95763"), Color("ac3232"), Color("76428a")],
	"ice": [Color("ffffff"), Color("cbdbfc"), Color("5fcde4")],
	"water": [Color("5fcde4"), Color("639bff"), Color("3f3f74")],
	"wood": [Color("d9a066"), Color("8f563b"), Color("4b692f")],
	"earth": [Color("eec39a"), Color("8a6f30"), Color("45283c")],
	"steel": [Color("cbdbfc"), Color("9badb7"), Color("3f3f74")],
	"darkness": [Color("d77bba"), Color("76428a"), Color("323c39")],
	"light": [Color("ffffff"), Color("fbf236"), Color("d9a066")],
	"thunder": [Color("fbf236"), Color("df7126"), Color("3f3f74")],
}

## AUTHORED safety ceilings: one root and eight Sprite3D instances sharing one
## generated 12-frame atlas. No particles, lights, timers, or per-cube textures.
const MAX_LIVE_RITUALS := 4
const MAX_EFFECT_NODES := 9
const MAX_GEOMETRY_INSTANCES := 8
const MAX_DRAW_CALLS := 8


static func paletteFor(elementColor: Color) -> Array[Color]:
	var closestKey := ""
	var closestDistance := INF
	for key: String in ELEMENT_REFERENCE_COLORS:
		var reference: Color = ELEMENT_REFERENCE_COLORS[key]
		var deltaR := elementColor.r - reference.r
		var deltaG := elementColor.g - reference.g
		var deltaB := elementColor.b - reference.b
		var distance := (
			deltaR * deltaR
			+ deltaG * deltaG
			+ deltaB * deltaB
		)
		if distance < closestDistance:
			closestDistance = distance
			closestKey = key
	if ELEMENT_PALETTES.has(closestKey):
		var matched: Array[Color] = []
		matched.assign(ELEMENT_PALETTES[closestKey])
		return matched
	return [elementColor.lightened(0.28), elementColor, elementColor.darkened(0.42)]


static func tunedEnd(start: float, finish: float) -> float:
	return minf(0.98, start + (finish - start) / DISSIPATION)
