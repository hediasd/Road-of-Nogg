## Study 04, Returning throw: one large cube sweeps around the target on a wide
## curve and returns along the other side to the caster.
##
## Sketch:
##   q=phase(t,.12,.89), out=q<.5, p=out?q*2:(q-.5)*2;
##   x=out?mix(C,T,smooth(p)):mix(T,C,smooth(p));
##   cube(x,.9+sin(p*PI)*.5,(out?-1:1)*sin(p*PI)*1.25,.43*sizeIn(t,.02,.12)*tail(t,.89,.98),t*14);
##   debris(t,.505,T,0,8,.8,.08,.2);
##
## The throw clips the target at q = 0.5, which is t = 0.505.
extends "res://src/presentation/effects/cube_placeholders/travel/TravelComposition.gd"


func profileID() -> String:
	return "cube_returning_throw"


func displayName() -> String:
	return "Cube Returning Throw"


## "Throw wide" and "Return" each have a still lead-in or tail around their
## flight; only the flight stretches with range.
func beats() -> Array[Dictionary]:
	return [
		{"name": "Throw wide", "start": 0.0, "end": 0.12, "travel": false},
		{"name": "Throw wide", "start": 0.12, "end": 0.505, "travel": true},
		{"name": "Clip target", "start": 0.505, "end": 0.52, "travel": false},
		{"name": "Return", "start": 0.52, "end": 0.89, "travel": true},
		{"name": "Return", "start": 0.89, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["blade", "chips"]


func peakCubes() -> int:
	return 9


func impactTime() -> float:
	return 0.505


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	var q := phase(t, 0.12, 0.89)
	var outbound := q < 0.5
	var p := q * 2.0 if outbound else (q - 0.5) * 2.0
	var progress := smooth(p) if outbound else 1.0 - smooth(p)
	var sway := sin(p * PI)
	var ground := pathPoint(frame, progress, (-1.0 if outbound else 1.0) * sway * 1.25)
	var position := ground + frame.up * (0.9 * frame.unit + sway * 0.5 * pathScale(frame))
	frame.cube(0, position, 0.43 * sizeIn(t, 0.02, 0.12) * tail(t, 0.89, 0.98), t * 14.0, 0)
	debris(frame, t, 0.505, targetPoint(frame), 8, 0.8, 0.08, 0.2, 100, 1)
