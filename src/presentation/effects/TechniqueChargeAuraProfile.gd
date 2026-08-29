## Calibration constants for the debug-only polygonal technique-charge aura.
##
## AUTHORED from the supplied finishing-technique reference sequence. The
## implementation is original and owns every value and resource it consumes.

class_name TechniqueChargeAuraProfile

const PROFILE_ID := "technique_charge_aura"

## AUTHORED beat timing.
##
## The bounce and the breath both work in real seconds (RING_LAUNCH_SECONDS and
## friends), so this is the one place a longer or shorter duration would still
## need to be felt: the wall's own alpha envelope and the settle point below.
const DURATION_SECONDS := 2.00

## Nothing is ever fully still once the breath is running, so there is no exact
## "settled" frame to define this as. 1.20s is where the core ring's bounce
## has decayed under the breath's own amplitude -- the handoff AURA-5C's
## breath_amplitude() computes -- so it is the first moment that is
## representative of the hold rather than of the entrance.
##
## This is deliberately no longer RELEASE_START_NORMALIZED, unlike the shipped
## AURA-2 envelope where the two were the same constant by construction. With a
## real hold between them, `skip_to_settle()` landing at the release point would
## put every debug preview one frame from vanishing instead of mid-charge.
const SETTLE_NORMALIZED_TIME := 0.60
## The action beat -- whatever external cue (camera, sound) times itself to the
## charge -- shares the settle point for the same reason: it is the first frame
## that reads as "charged" rather than "arriving."
const ACTION_HOLD_FRACTION := SETTLE_NORMALIZED_TIME

## Ignition/hold/release envelope for the wall's own alpha. The ring geometry's
## bounce (RING_RISE_SECONDS[0] = 0.16s) already carries the silhouette growing
## in, so this only has to get the wall's opacity to full quickly rather than
## reproduce that motion a second time: 0.06s, a third of the core's rise.
## Release begins well after the breath has taken over from the bounce, so the
## fade always starts from the idle rather than cutting the entrance short.
const IGNITE_END_NORMALIZED := 0.03
const RELEASE_START_NORMALIZED := 0.89
## The ground ignites faster than the wall -- roughly a third of the wall's own
## ignite -- so the floor visibly lights an instant before the ring above it
## does, rather than the two appearing together. It shares the wall's release
## timing, so the two layers still vanish as one source.
const GROUND_IGNITE_LEAD_NORMALIZED := 0.01

## How strongly the ground layer's brightness tracks the core ring's own
## bounce, and the floor below which it will not drop even during the deepest
## dip. A wall that bounces off a completely unlit floor stops reading as one
## source with its own ground contact.
const GROUND_PULSE_STRENGTH := 0.55
const GROUND_PULSE_FLOOR := 0.55

## Motion. Every amplitude here is deliberately restrained: the source
## reference charges rather than burns, and the failure modes are specific —
## large displacement reads as flame, fast high-contrast noise reads as static.
const NOISE_SCALE_COARSE := 3.0
const NOISE_SCALE_FINE := 11.0
const NOISE_RISE_SPEED := 0.55
const FLICKER_AMOUNT := 0.16
const DISPLACEMENT_U := 0.075

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

## At the battle camera's framing the whole aura is roughly forty pixels tall,
## so plus or minus 7.5% of height is two or three pixels -- present, but not
## the thing that reads. Coupling the same breath factor into brightness and
## into the top-edge flutter is what actually makes the idle visible: alpha
## swings roughly BREATH_BRIGHT_COUPLING times as far as height does, and
## brightness is legible at any size.
const BREATH_BRIGHT_COUPLING := 1.6
const BREATH_FLUTTER_COUPLING := 1.0

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

## Per-ring opacity and grade. The core keeps the shipped base-faint curve --
## dim at the foot, strong at the top, controlled by WALL_BOTTOM_STRENGTH. The
## flares invert that: they are near-zero where they meet the floor and
## brightest through their leading third, because a bright leading edge reads
## as motion and piling three rings' density at the foot would build exactly
## the solid collar WALL_BOTTOM_STRENGTH exists to prevent. RING_TIP_BRIGHT is
## a blend weight (0 or 1 here) rather than a bool because uniform arrays in
## this shader are float only.
const RING_OPACITY := [WALL_OPACITY, 0.32, 0.22]
const RING_TIP_BRIGHT := [0.0, 1.0, 1.0]

## AUTHORED yellow-white grade from the reference's charged lower band.
const AURA_COLOR := Color("fff08a")

## AUTHORED ground contact. The plane is larger than the ring stack so its
## bright rim remains visible outside the model at the battle-camera pitch.
##
## Sized against the outer flare's BUILT radius (1.3375u, from
## RING_BASE_RADIUS_U[2] + RING_LENGTH_U[2] * ring_ceiling(2) * cos(40deg)), not
## its resting one (1.1605u) -- the flare reaches the larger figure during its
## own launch, and AURA-5C found that a plane sized against the resting radius
## leaves the flare's peak sitting outside its own light. At 2.90u the built
## radius lands at UV 0.4612, inside GROUND_SPILL_OUTER_UV with room to spare,
## and the resting radius lands at 0.4002 -- close to the roughly-0.80-of-outer
## placement the shipped single wall held its own line at.
const GROUND_DIAMETER_U := 2.90
const GROUND_HEIGHT_U := 0.025
## The ground is a radial spill centred on the source, not an annulus: a bright
## ring already means "this area is affected" elsewhere in this project's
## vocabulary (danger zones, movement range), which misstates a non-area
## effect. Held to zero by 0.50 so the square plane's corners never show.
##
## GROUND_SPILL_ALPHA comes down from the shipped 0.30 because the flares now
## light the floor themselves wherever they reach; the ground layer's own spill
## only has to carry the space between and beyond them, not the whole reveal.
const GROUND_SPILL_INNER_UV := 0.18
const GROUND_SPILL_OUTER_UV := 0.50
const GROUND_SPILL_ALPHA := 0.22
const GROUND_OPACITY := 0.78
const GROUND_EMISSION_ENERGY := 0.52
const GROUND_RENDER_PRIORITY := 1

## AUTHORED safety ceilings: root + two MeshInstance3D children, two surfaces.
const MAX_LIVE_AURAS := 3
const MAX_EFFECT_NODES := 3
const MAX_GEOMETRY_INSTANCES := 2
const MAX_DRAW_CALLS := 2
