## Study 05, Skipping stone: a cube makes three distinct bounces through a small
## group, scattering chips at each contact.
##
## Sketch:
##   nodes=[[C,-.2],[-.65,-.7],[.55,.7],[T+.55,-.3]], starts=[.12,.34,.56];
##   for(i<3){if(t>=starts[i]&&t<starts[i]+.22){q=phase(t,starts[i],starts[i]+.22);
##     cube(mix(nodes[i][0],nodes[i+1][0],q),.25+sin(q*PI)*1.1,mix(nodes[i][1],nodes[i+1][1],q),.35,t*12);}
##     debris(t,starts[i]+.22,nodes[i+1][0],nodes[i+1][1],6,.65,.075,.18);}
##
## The two middle contacts sit at their sketch positions along the path; the
## last lands beyond the target by a target-relative offset. The contacts are
## at t = 0.34, 0.56 and 0.78.
extends "res://src/presentation/effects/cube_placeholders/travel/TravelComposition.gd"

const CONTACT_STARTS: Array[float] = [0.12, 0.34, 0.56]
const HOP := 0.22


func profileID() -> String:
	return "cube_skipping_stone"


func displayName() -> String:
	return "Cube Skipping Stone"


func beats() -> Array[Dictionary]:
	return [
		{"name": "Launch", "start": 0.0, "end": 0.12, "travel": false},
		{"name": "Launch", "start": 0.12, "end": 0.34, "travel": true},
		{"name": "Hop → hop", "start": 0.34, "end": 0.78, "travel": true},
		{"name": "Last impact", "start": 0.78, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["stone", "chips"]


func peakCubes() -> int:
	return 7


func impactTime() -> float:
	return 0.78


## The contact the stone makes at the end of hop `index` (0-2).
func contactTime(index: int) -> float:
	return CONTACT_STARTS[index] + HOP


func nodes(frame: CubePlaceholderFrame) -> Array[Vector3]:
	return [
		sourcePoint(frame, -0.2),
		pathPoint(frame, CubePlaceholderFrame.progressOfSketchX(-0.65), -0.7),
		pathPoint(frame, CubePlaceholderFrame.progressOfSketchX(0.55), 0.7),
		targetPoint(frame, 0.55, -0.3),
	]


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	var points := nodes(frame)
	for i: int in range(3):
		var start := CONTACT_STARTS[i]
		if t >= start and t < start + HOP:
			var q := phase(t, start, start + HOP)
			var ground := points[i].lerp(points[i + 1], q)
			var position := ground + frame.up * (0.25 * frame.unit + sin(q * PI) * 1.1 * pathScale(frame))
			frame.cube(0, position, 0.35, t * 12.0, 0)
		debris(frame, t, start + HOP, points[i + 1], 6, 0.65, 0.075, 0.18, 100 + i * 10, 1)
