## Calibration constants for the debug-only polygonal technique-charge aura.
##
## AUTHORED from the supplied finishing-technique reference sequence. The
## implementation is original and owns every value and resource it consumes.

class_name TechniqueChargeAuraProfile

const PROFILE_ID := "technique_charge_aura"

## AUTHORED beat timing.
const DURATION_SECONDS := 1.60
const SETTLE_NORMALIZED_TIME := 0.88
const ACTION_HOLD_FRACTION := 0.55

## Ignition/hold/release envelope. Ignition ends where the charge is fully lit;
## hold carries the action beat at ACTION_HOLD_FRACTION; release begins exactly
## at the settle point, which makes `skip_to_settle()` land on the last
## fully-charged frame rather than somewhere inside the fade.
const IGNITE_END_NORMALIZED := 0.20
const RELEASE_START_NORMALIZED := SETTLE_NORMALIZED_TIME

## Motion. Every amplitude here is deliberately restrained: the source
## reference charges rather than burns, and the failure modes are specific —
## large displacement reads as flame, fast high-contrast noise reads as static.
const NOISE_SCALE_COARSE := 3.0
const NOISE_SCALE_FINE := 11.0
const NOISE_RISE_SPEED := 0.55
const FLICKER_AMOUNT := 0.16
const DISPLACEMENT_U := 0.055

## Density multiplier at the wall's base. The mask is at its most opaque there,
## so this is the control that decides whether the foot of the wall reads as
## light or as a solid collar.
const WALL_BOTTOM_STRENGTH := 0.38

## AUTHORED world-space carrier: a compact decagonal wall around one model.
const WALL_SIDES := 10
const WALL_RADIUS_U := 0.74
const WALL_HEIGHT_U := 1.62

## AUTHORED ring stack. Index 0 is the vertical core wall the effect shipped
## with; 1 and 2 are flares that lean outward off the floor. One wall reads as
## a caster standing in light, which is not the statement -- the flares are
## what make the effect read as something coming up out of the ground.
##
## Lean is measured from the ground plane, so 90 degrees is the vertical core
## and 40 degrees is the shallow outer splash. All three rings share WALL_SIDES
## and are built into one surface, so the stack costs no extra draw call.
const RING_COUNT := 3
const RING_LEAN_DEGREES := [90.0, 62.0, 40.0]
const RING_BASE_RADIUS_U := [WALL_RADIUS_U, 0.78, 0.90]
## Resting length along the lean, not the length the geometry is built at --
## see `ring_ceiling()`.
const RING_LENGTH_U := [WALL_HEIGHT_U, 0.52, 0.34]

## AUTHORED ring motion. Every ring runs the same damped-spring entrance with
## its own constants: a launch to peak, then an oscillation that falls below the
## resting length and decays away. The dip below rest is the beat that makes the
## entrance read as energy rather than as a bar filling up.
##
## The flares are shorter, lighter, faster and more damped than the core, so
## they flick where the core swings. Launches are staggered outward, which reads
## as a splash crown rather than as three rings appearing at once. Reversing the
## stagger reads as energy being gathered inward instead; it is one line here.
const RING_LAUNCH_SECONDS := [0.00, 0.04, 0.08]
const RING_RISE_SECONDS := [0.16, 0.11, 0.09]
const RING_BOUNCE_PERIOD_SECONDS := [0.42, 0.32, 0.26]
const RING_BOUNCE_DECAY := [2.43, 3.40, 4.20]
const RING_OVERSHOOT := [0.30, 0.40, 0.48]
const RING_BREATH_SCALE := [1.0, 1.4, 1.8]

## AUTHORED idle. The aura is never static: the breath runs from its first frame
## to its last, and its amplitude grows from BREATH_MIN to BREATH_MAX on the
## core ring's own decay term. It therefore never competes with the entrance and
## arrives exactly where the aura would otherwise go still -- the handoff falls
## out of the arithmetic instead of being scheduled.
##
## At the battle camera's framing the whole aura is around forty pixels tall, so
## the earlier plus or minus 3.5% was one pixel and effectively invisible. The
## amplitude that fixes that is not the height alone; it is the height coupled
## to brightness, which is legible at any size (AURA-5D).
const BREATH_MIN := 0.030
const BREATH_MAX := 0.075
## How much of the breath is the face's own rather than shared by the whole
## ring. Panels butt together with no side margin in the mask, so the step at a
## shared corner has only the ragged top edge hiding it; this is what bounds it.
const BREATH_FACE_MIX := 0.45

## AUTHORED entrance spread around the ring, in seconds of lag. Both terms are
## sines of the angle, so the phase is periodic by construction: a lag that
## ramps linearly with the angle wraps once around the ring and tears at exactly
## one corner. Peak lag is about a sixth of the core's bounce period -- push it
## to half a period and opposite sides stop reading as one object.
const RING_PHASE_A1 := 0.045
const RING_PHASE_A2 := 0.022


## The extension each ring's geometry is built at, as a multiple of its resting
## length.
##
## Building at the ceiling is what lets the vertex stage scale by a factor that
## is always at or below 1: the mask can never be asked to cover geometry that
## does not exist, and no rebuild is needed when the ring overshoots. It has to
## account for the breath as well as the bounce, because both multiply.
static func ring_ceiling(index: int) -> float:
	return (1.0 + float(RING_OVERSHOOT[index])) * (
		1.0 + BREATH_MAX * float(RING_BREATH_SCALE[index])
	)
## The wall renders both faces (cull_disabled), so the near and far halves
## overlap wherever the silhouette shows a single wall face when only one side
## is culled. blend_mix integrates two stacked layers at per-face alpha a to
## 1-(1-a)^2, so this holds a single-face peak of 0.72 at that overlap.
const WALL_OPACITY := 0.47
const WALL_EMISSION_ENERGY := 0.34
const WALL_RENDER_PRIORITY := 2

## AUTHORED yellow-white grade from the reference's charged lower band.
const AURA_COLOR := Color("fff08a")

## AUTHORED ground contact. The plane is larger than the wall so its bright rim
## remains visible outside the model and wall at the battle-camera pitch.
const GROUND_DIAMETER_U := 1.86
const GROUND_HEIGHT_U := 0.025
## The ground is a radial spill centred on the source, not an annulus: a bright
## ring already means "this area is affected" elsewhere in this project's
## vocabulary (danger zones, movement range), which misstates a non-area
## effect. In plane UV, the 1.86u plane's edge midpoint is 0.50 and the 0.74u
## wall line falls at 0.398. Held to zero by 0.50 so the square plane's corners
## never show; still carrying about a quarter of peak at the wall line, because
## at the real battle framing the whole aura is roughly forty pixels tall and a
## falloff that dies inside the wall disappears at that scale.
const GROUND_SPILL_INNER_UV := 0.18
const GROUND_SPILL_OUTER_UV := 0.50
const GROUND_SPILL_ALPHA := 0.30
const GROUND_OPACITY := 0.78
const GROUND_EMISSION_ENERGY := 0.52
const GROUND_RENDER_PRIORITY := 1

## AUTHORED safety ceilings: root + two MeshInstance3D children, two surfaces.
const MAX_LIVE_AURAS := 3
const MAX_EFFECT_NODES := 3
const MAX_GEOMETRY_INSTANCES := 2
const MAX_DRAW_CALLS := 2
