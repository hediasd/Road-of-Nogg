## Study 24, Charge and release: sixteen tiny cubes spiral into a heavy cube
## near the caster. After a short held charge, it fires toward the target and
## shatters.
##
## Sketch:
##   if(t<.4)for(i<16){q=phase(t,.02+i*.006,.36), a=i*2.4+q*4, r=(1-q)*1.15;
##     cube(C+cos(a)*r,.95+sin(a)*r*.4,sin(a)*r,.11*sizeIn(t,0,.05),q*5+i);}
##   if(t>=.19&&t<.76){q=pow(phase(t,.55,.76),2), s=.6*sizeIn(t,.19,.42);
##     cube(mix(C,T,q),1.05,0,s*(1+.025*sin(t*55)),t<.55?t*2:q*5);}
##   debris(t,.76,T,0,24,1.7,.12,.22);
##
## The hold is the point: from .42, fully grown, to .55 the heavy cube stays
## put above the caster, only trembling in size, before it fires. Gather and
## fire are never one continuous travel.
extends "res://src/presentation/effects/cube_placeholders/restore/RestoreComposition.gd"

const HOLD_START := 0.42
const FIRE_START := 0.55
const FIRE_END := 0.76


func profileID() -> String:
	return "cube_charge_release"


func displayName() -> String:
	return "Cube Charge Release"


func binding() -> String:
	return BINDING_TWO_ANCHOR


func beats() -> Array[Dictionary]:
	return [
		{"name": "Gather power", "start": 0.0, "end": HOLD_START, "travel": false},
		{"name": "Hold weight", "start": HOLD_START, "end": FIRE_START, "travel": false},
		{"name": "Fire", "start": FIRE_START, "end": FIRE_END, "travel": true},
		{"name": "Fire", "start": FIRE_END, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["gather", "charge", "chips"]


func peakCubes() -> int:
	return 24


func impactTime() -> float:
	return FIRE_END


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	if t < 0.4:
		for i: int in range(16):
			var q := phase(t, 0.02 + i * 0.006, 0.36)
			var a := i * 2.4 + q * 4.0
			var r := (1.0 - q) * 1.15
			var position := local(frame, frame.source, frame.forward, cos(a) * r, 0.95 + sin(a) * r * 0.4, sin(a) * r, frame.unit)
			frame.cube(i, position, 0.11 * sizeIn(t, 0.0, 0.05), q * 5.0 + i, 0)
	if t >= 0.19 and t < FIRE_END:
		var q := pow(phase(t, FIRE_START, FIRE_END), 2.0)
		var size := 0.6 * sizeIn(t, 0.19, HOLD_START) * (1.0 + 0.025 * sin(t * 55.0))
		var position := frame.source.lerp(frame.target, q) + frame.up * (1.05 * frame.unit)
		frame.cube(20, position, size, t * 2.0 if t < FIRE_START else q * 5.0, 1)
	debris(frame, t, FIRE_END, frame.target, 24, 1.7, 0.12, 0.22, 100, 2)
