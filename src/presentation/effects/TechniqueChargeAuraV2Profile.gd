## Calibration constants for the debug-only polygonal technique-charge aura.
##
## AUTHORED from the supplied finishing-technique reference sequence. The
## implementation is original and owns every value and resource it consumes.

class_name TechniqueChargeAuraV2Profile

const PROFILE_ID := "technique_charge_aura_v2"

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
## Per-ring churn multiplier. Flares churn harder than the core, so the outer
## silhouette is the busiest part of the effect.
const RING_CHURN_SCALE := [1.0, 1.30, 1.55]

## AUTHORED idle. v1's breath ramped in as the entrance died and settled at
## plus or minus 7.5%; v2's churn does neither. It runs at full amplitude from
## the first frame to the last, because v2's statement is an aura that is never
## doing nothing rather than one that arrives and holds.
##
## The amplitude is nearly three times v1's, which is what forces faces to be
## drawn as discrete blades: v1 measured the corner gap at 0.0337u with its
## breath, and this amplitude with near-full per-blade independence would scale
## that to roughly 4px of visible notch at every corner on a continuous ring.
## BLADE_EDGE_SOFTNESS is the answer to that, not a smaller CHURN_AMPLITUDE.
const CHURN_AMPLITUDE := 0.20
## How much of the churn is the blade's own rather than shared by the whole
## ring. v1 held the equivalent at 0.45 to keep neighbouring panels close
## enough that the step between them stayed hidden; with blades drawn discrete
## that constraint is gone and they are free to disagree.
const CHURN_FACE_MIX := 0.85
## How far a blade's own azimuth offsets its churn sample. Large enough that
## adjacent blades decorrelate rather than drift together: at ten sides the
## azimuth steps by 0.628 rad, so this puts neighbours 3.58 apart in the noise
## field, well past its correlation length.
const CHURN_FACE_SPREAD := 5.7

## Two unrelated rates so the idle has no readable loop or countable beat.
## Faster than v1's 1.7/4.3: the blades should read as pumping, not shimmering.
const CHURN_RATE_SLOW := 3.1
const CHURN_RATE_FAST := 6.7

## Softness of the falloff at each blade's two vertical edges, in UV.x. This is
## what makes a face a blade rather than a panel of a continuous wall. The mask
## carries no side margin of its own (alpha ~253 in its edge columns, measured
## on v1), so without this the geometry's own edges are hard.
const BLADE_EDGE_SOFTNESS := 0.26

## At the battle camera's framing the whole aura is roughly forty pixels tall,
## so even plus or minus 20% of height is a handful of pixels. Coupling the same
## churn factor into brightness and into the top-edge flutter is what actually
## makes the idle carry: alpha swings roughly CHURN_BRIGHT_COUPLING times as far
## as height does, and brightness is legible at any size.
const CHURN_BRIGHT_COUPLING := 1.6
const CHURN_FLUTTER_COUPLING := 1.0

## AUTHORED spin. The stack turns around the caster, fast off the launch and
## easing back to a hold rate -- a constant rate reads mechanical, a rate with a
## history reads driven.
##
## These are properties of the effect, not a budget balanced against its
## duration. An earlier draft scaled them up to "recover" the turn that an
## earlier release cost; that was rejected, and the rejection is the rule: how
## fast the ring turns is what the effect is, and moving the release does not
## change it. At the 1.00s release the stack reaches roughly 265 degrees, three
## quarters of a revolution, and that is the correct amount.
##
## Direction is fixed across every cast -- no seed term. A telegraph should be
## recognised instantly, not appreciated for its variety.
const SPIN_LAUNCH_DEG_PER_SEC := 340.0
const SPIN_HOLD_DEG_PER_SEC := 230.0
## Time constant of the ease from launch rate to hold rate.
const SPIN_EASE_TAU_SECONDS := 0.34
## Per-ring multiplier. The rings turn at slightly different speeds so the stack
## shears instead of rotating as one rigid body; that differential is most of
## what makes it read as a vortex rather than a turntable.
const RING_SPIN_SCALE := [1.0, 1.15, 1.32]

## AUTHORED entrance spread around the ring, in seconds of lag. Both terms are
## sines of the angle, so the phase is periodic by construction: a lag that
## ramps linearly with the angle wraps once around the ring and tears at exactly
## one corner. Peak lag is about a sixth of the core's bounce period -- push it
## to half a period and opposite sides stop reading as one object.
const RING_PHASE_A1 := 0.045
const RING_PHASE_A2 := 0.022


## Absolute spin angle for one ring at an instant, in radians.
##
## Set from the clock, never accumulated. The rate eases exponentially from the
## launch rate to the hold rate, and this is that rate's integral in closed
## form:
##
##     rate(s)  = hold + (launch - hold) * exp(-s / tau)
##     angle(t) = hold * t + (launch - hold) * tau * (1 - exp(-t / tau))
##
## Writing `rotation.y += rate * delta` instead would look identical while
## playing and produce a different frame after a seek, because the accumulated
## value depends on the path taken rather than on the position reached. That is
## the one property this whole effect is built on not losing -- see
## docs/VFX_DESIGN.md section 3 -- and it is the reason this is a function
## rather than a counter.
static func spin_radians(index: int, seconds: float) -> float:
	if seconds <= 0.0:
		return 0.0
	var hold := deg_to_rad(SPIN_HOLD_DEG_PER_SEC)
	var launch := deg_to_rad(SPIN_LAUNCH_DEG_PER_SEC)
	var tau: float = maxf(SPIN_EASE_TAU_SECONDS, 0.0001)
	var angle := hold * seconds + (launch - hold) * tau * (1.0 - exp(-seconds / tau))
	return angle * float(RING_SPIN_SCALE[index])


## The extension each ring's geometry is built at, as a multiple of its resting
## length.
##
## Building at the ceiling is what lets the vertex stage scale by a factor that
## is always at or below 1: the mask can never be asked to cover geometry that
## does not exist, and no rebuild is needed when the ring overshoots. It has to
## account for the breath as well as the bounce, because both multiply.
static func ring_ceiling(index: int) -> float:
	return ring_ceiling_for(
		float(RING_OVERSHOOT[index]), CHURN_AMPLITUDE, float(RING_CHURN_SCALE[index])
	)


## The formula `ring_ceiling()` applies, taking its inputs explicitly.
##
## The debug panel's live Bounce and Breath tunables can move the very numbers
## `ring_ceiling()` reads, and the mesh has to be built at whatever ceiling
## those live values imply -- not at the authored default -- or an overshoot
## tuned upward would silently clip against geometry sized for the smaller,
## authored one. `_ringSpecs()` calls this directly with the live values so the
## built mesh and the ceiling uniform pushed alongside it can never disagree.
static func ring_ceiling_for(
		overshoot: float, churn_amplitude: float, churn_scale: float) -> float:
	return (1.0 + overshoot) * (1.0 + churn_amplitude * churn_scale)
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
