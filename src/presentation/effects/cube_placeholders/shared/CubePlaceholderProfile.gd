## Authored constants for the cube placeholder spell library's shared
## substrate: the fake-3D cube sprite, the palettes, the world scale the
## sketch's diagram units map to, range scaling, and the render budget.
##
## The sprite source frame and the element palettes are COPIED from
## `ElementalCubeRitualProfile`, not referenced: the two surviving rituals are a
## compatibility surface, and a library that read their constants would make
## every future tweak here a change to them. The copy is deliberate duplication.

class_name CubePlaceholderProfile
extends RefCounted

## AUTHORED sprite treatment, identical to the ritual cubes: a 32x32 source
## pose and eleven reconstructed quarter-turn frames.
const SPRITE_FRAME_SIZE_PX := 32
const SPRITE_ROTATION_FRAMES := 12

## AUTHORED from the retained motion sketch. `C` and `T` are where the sketch
## draws its neutral caster and target reference actors on its x axis.
const SKETCH_C := -2.25
const SKETCH_T := 1.25

## MEASURED world units per sketch unit. The sketch's reference actor is two
## stacked cubes 0.84 sketch units tall and 0.45 wide; the standard target
## body is 1.30 tall above a 0.20 base and 0.70 wide. Height gives 1.79 and
## width 1.56; 1.6 keeps a medium sketch cube at the same share of a target
## body's width that the sketch shows. Lateral and vertical offsets use this
## scale everywhere; along a source-to-target path the live anchors decide.
const UNIT_U := 1.6
## AUTHORED quad size per unit of cube edge. The painted sprite fills its
## whole 32px frame with the cube's silhouette, which is wider than the cube's
## edge: an isometric cube of edge 1 spans about 1.35 on screen.
const QUAD_PER_EDGE := 1.35
## The standard target body the sketch's actor corresponds to. A body-bound
## composition scales uniformly by how much larger the real body is.
const STANDARD_BODY_WIDTH_U := 0.70
const STANDARD_BODY_TOP_U := 1.50

## AUTHORED range scaling. Distance is measured in battle cells, one cell being
## the hex lattice's row pitch, and the travel beats of a `travel` profile last
## `clamp(cells / REFERENCE_DISTANCE_CELLS, MIN, MAX)` times their reference
## length. PROVISIONAL: the plan allows these to be retuned during the cycle's
## final validation only.
const CELL_PITCH_U := 2.0
const REFERENCE_DISTANCE_CELLS := 4.0
const RANGE_STRETCH_MIN := 0.75
const RANGE_STRETCH_MAX := 1.5

## The reference configuration's source separation in world units: the
## distance at which every normalized beat boundary matches the sketch.
const REFERENCE_DISTANCE_U := CELL_PITCH_U * REFERENCE_DISTANCE_CELLS

## AUTHORED budget. One MultiMesh draws every cube of a playback, whatever its
## element count or anchor count, so these ceilings are far above what the
## substrate uses; they exist to fail loudly if a family ever adds nodes.
const MIN_CAPACITY_PER_COMPOSITION := 48
const MAX_RENDER_NODES := 4
const MAX_DRAW_CALLS := 4
const MAX_LIVE_PLAYBACKS := 4

## AUTHORED minimum visible cube, in sketch units, matching the sketch's own
## `s > .003` cull.
const MIN_VISIBLE_SIZE := 0.003
const MIN_VISIBLE_OPACITY := 0.01

## AUTHORED exact 32x32 Wind cube, copied from the ritual profile. Each
## character is one source pixel: direct, middle, shadow, or transparent.
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

## AUTHORED element palettes (direct, middle, shadow), copied from the ritual
## profile, plus the reference colours `BattleMeshFactory.elementColor` returns
## so a Color-only caller still resolves the right palette.
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
## The neutral grey `BattleMeshFactory.elementColor` gives an element-less spell.
const NONE_COLOR := Color(0.5, 0.5, 0.5)


## The palette an element name draws with. `none` and unknown names use the
## lightened/darkened neutral, the same construction the rituals use for a
## colour they do not recognise.
static func paletteForElement(elementName: String) -> Array[Color]:
	var key := elementName.to_lower()
	if ELEMENT_PALETTES.has(key):
		var matched: Array[Color] = []
		matched.assign(ELEMENT_PALETTES[key])
		return matched
	return _derivedPalette(NONE_COLOR)


## The palette for a bare colour, by nearest reference colour, exactly as the
## rituals resolve it. Used when a caller supplied only a Color.
static func paletteForColor(elementColor: Color) -> Array[Color]:
	var closestKey := ""
	var closestDistance := INF
	for key: String in ELEMENT_REFERENCE_COLORS:
		var reference: Color = ELEMENT_REFERENCE_COLORS[key]
		var deltaR := elementColor.r - reference.r
		var deltaG := elementColor.g - reference.g
		var deltaB := elementColor.b - reference.b
		var distance := deltaR * deltaR + deltaG * deltaG + deltaB * deltaB
		if distance < closestDistance:
			closestDistance = distance
			closestKey = key
	# A colour nearer the neutral grey than any element is an element-less
	# spell, and must not borrow the nearest element's identity.
	var noneDistance := (
		pow(elementColor.r - NONE_COLOR.r, 2.0)
		+ pow(elementColor.g - NONE_COLOR.g, 2.0)
		+ pow(elementColor.b - NONE_COLOR.b, 2.0)
	)
	if noneDistance < closestDistance:
		return _derivedPalette(elementColor)
	return paletteForElement(closestKey)


static func _derivedPalette(elementColor: Color) -> Array[Color]:
	return [elementColor.lightened(0.28), elementColor, elementColor.darkened(0.42)]


## The travel-beat stretch for a source-to-target distance in world units.
static func rangeStretch(distanceU: float) -> float:
	var cells := distanceU / CELL_PITCH_U
	return clampf(cells / REFERENCE_DISTANCE_CELLS, RANGE_STRETCH_MIN, RANGE_STRETCH_MAX)
