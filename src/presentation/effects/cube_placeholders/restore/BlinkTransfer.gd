## Study 23, Blink transfer: eight cubes forming a body-sized cluster break
## apart at the caster, zip across in sequence, and rebuild at the target.
##
## Sketch:
##   for(i<8){q=smooth(phase(t,.2+i*.018,.51+i*.018)), z=(i%2-.5)*.34, y=.22+floor(i/2)*.34;
##     cube(mix(C,T,q),y+sin(q*PI)*.35,z+sin(q*PI)*(rnd(i)-.5)*1.4,
##       .28*sizeIn(t,0,.09)*tail(t,.86,.99),sin(q*PI)*5);}
##
## The cluster is two columns of four; ids alternate by column, so with two
## elements (a steel-and-wind spell) each column shows one colour.
extends "res://src/presentation/effects/cube_placeholders/restore/RestoreComposition.gd"


func profileID() -> String:
	return "cube_blink_transfer"


func displayName() -> String:
	return "Cube Blink Transfer"


func binding() -> String:
	return BINDING_TWO_ANCHOR


func beats() -> Array[Dictionary]:
	return [
		{"name": "Disassemble", "start": 0.0, "end": 0.2, "travel": false},
		{"name": "Cross in a streak", "start": 0.2, "end": 0.636, "travel": true},
		{"name": "Reform", "start": 0.636, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["cluster"]


func peakCubes() -> int:
	return 8


func impactTime() -> float:
	return 0.636


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	var lateral := pathScale(frame)
	for i: int in range(8):
		var q := smooth(phase(t, 0.2 + i * 0.018, 0.51 + i * 0.018))
		var arc := sin(q * PI)
		var z := (i % 2 - 0.5) * 0.34
		var y := 0.22 + floorf(i / 2.0) * 0.34
		var ground := frame.source.lerp(frame.target, q) + frame.side * (z * frame.unit + arc * (frame.rnd(i) - 0.5) * 1.4 * lateral)
		var position := ground + frame.up * ((y + arc * 0.35) * frame.unit)
		frame.cube(i, position, 0.28 * sizeIn(t, 0.0, 0.09) * tail(t, 0.86, 0.99), arc * 5.0, 0)
