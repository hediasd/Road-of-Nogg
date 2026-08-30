## Calibration constants for the debug-only polygonal technique-charge aura.
##
## AUTHORED from the supplied finishing-technique reference sequence. The
## implementation is original and owns every value and resource it consumes.

class_name TechniqueChargeAuraV2Profile

const PROFILE_ID := "technique_charge_aura_v2"

## AUTHORED beat timing, in seconds.
##
## The release time and the release window are the two authored numbers; the
## effect's total length is their sum, not a runtime the release stretches to
## fill. Stretching a 0.50s dispersal to hold some other end goes limp, so if
## the release moves, the effect simply ends earlier.
const RELEASE_SECONDS := 1.00
const RELEASE_WINDOW_SECONDS := 0.50
const DURATION_SECONDS := RELEASE_SECONDS + RELEASE_WINDOW_SECONDS

## Nothing is ever still in v2 -- the churn runs at full amplitude throughout --
## so there is no settled frame to point at. This is mid-charge: past the point
## where the entrance stopped being the dominant motion, and well before the
## release. It is what `skip_to_settle()` lands on, so it has to be the frame
## that best represents "charged".
const SETTLE_NORMALIZED_TIME := 0.55
## The action beat -- whatever external cue times itself to the charge --
## shares it, for the same reason.
const ACTION_HOLD_FRACTION := SETTLE_NORMALIZED_TIME

## The wall's own opacity ramp. The blades' bounce already carries the
## silhouette growing in, so this only has to reach full quickly rather than
## reproduce that motion a second time. It has no release term: the release is
## per blade (BLADE_FADE_SECONDS below), because blades go out in a wave rather
## than together.
const IGNITE_SECONDS := 0.06
## The ground lights first, so the floor is visibly lit an instant before the
## blades above it rather than the two appearing together.
const GROUND_IGNITE_SECONDS := 0.02

## AUTHORED release. Everything here starts at RELEASE_SECONDS and finishes
## inside RELEASE_WINDOW_SECONDS.
##
## The flash comes first and alone: brightness rises and falls before any alpha
## is taken off, so the release has an onset instead of merely starting to be
## less. Without it the eye has nothing to catch.
const FLASH_SECONDS := 0.06
const FLASH_PEAK := 1.35

## Each blade fades over BLADE_FADE_SECONDS, and their starts are spread across
## BLADE_SWEEP_SECONDS by blade angle, so the ring unzips in the spin's own
## direction rather than thirty blades vanishing at once. The last thing on
## screen is motion, not a shape dimming. Last blade out at
## RELEASE + FLASH + SWEEP + FADE = 1.44s.
const BLADE_FADE_SECONDS := 0.22
const BLADE_SWEEP_SECONDS := 0.16
## The ground trails the blades and is the final thing to go dark, at 1.50s. A
## simultaneous cut on both layers reads as a dropped frame.
const GROUND_LAG_SECONDS := 0.18

## The whip: the spin accelerates through the release, so the blades spiral
## outward rather than travelling straight out.
const SPIN_RELEASE_MULTIPLIER := 2.2

## Direction of the dispersal: +1 expands, -1 collapses. Signed rather than
## branched so the decision stays one constant. Expand was chosen on
## 2026-08-29; collapse is kept reachable because the risk it answers -- an
## outward release competing with the spell that fires immediately after -- can
## only be judged against a real cast.
const RELEASE_DIRECTION := 1.0
const RELEASE_RADIUS_GAIN := 0.70
## Both directions flatten. The flatten is what separates a charge dispersing
## along the floor from a second spell going off a beat before the real one: a
## tall outward burst competes, a fast low spreading ring does not.
const RELEASE_HEIGHT_DROP := 0.45

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
## Explicit parameters, defaulted to the authored constants, so a live tunable
## override and the authored default call through exactly the same arithmetic
## -- the same discipline `ring_ceiling()` / `ring_ceiling_for()` already
## established: one formula, callable either way, never two.
static func spin_radians(
		index: int, seconds: float,
		hold_deg: float = SPIN_HOLD_DEG_PER_SEC,
		launch_deg: float = SPIN_LAUNCH_DEG_PER_SEC,
		ease_tau: float = SPIN_EASE_TAU_SECONDS,
		differential: float = 1.0,
		release_seconds: float = RELEASE_SECONDS,
		release_window: float = RELEASE_WINDOW_SECONDS,
		release_multiplier: float = SPIN_RELEASE_MULTIPLIER) -> float:
	if seconds <= 0.0:
		return 0.0
	var hold := deg_to_rad(hold_deg)
	var launch := deg_to_rad(launch_deg)
	var tau: float = maxf(ease_tau, 0.0001)
	var angle := hold * seconds + (launch - hold) * tau * (1.0 - exp(-seconds / tau))
	angle += _whip_radians(
		seconds, hold, launch - hold, tau,
		release_seconds, release_window, release_multiplier
	)
	# `differential` scales how far this ring's rate deviates from the core's,
	# not the rate itself -- at differential 0 every ring spins at the core's
	# rate and the stack stops shearing; at 1 it is the authored RING_SPIN_SCALE.
	var scale := 1.0 + (float(RING_SPIN_SCALE[index]) - 1.0) * differential
	return angle * scale


## The extra angle the release's whip adds, in radians.
##
## Through the release the rate is multiplied by 1 + (M-1) * p, where p runs 0
## to 1 across the window, so the blades spiral outward instead of travelling
## straight out. This is the integral of that extra term alone -- exactly, not
## approximately, because an approximation here is a closed form that quietly
## disagrees with the constant it claims to implement, and the next person to
## check the whip against the release multiplier would find it short.
##
##     extra(s) = [hold + A e^(-s/tau)] * k * (s - R),   k = (M - 1) / window
##
## The hold part integrates to hold * k * x^2 / 2 with x = s - R. The eased part
## uses the standard result for u * e^(-u/tau):
##
##     integral of u e^(-u/tau) from 0 to x = tau^2 - e^(-x/tau) (tau x + tau^2)
static func _whip_radians(
		seconds: float, hold: float, eased: float, tau: float,
		release_seconds: float, release_window: float,
		release_multiplier: float) -> float:
	var x := seconds - release_seconds
	if x <= 0.0:
		return 0.0
	x = minf(x, release_window)
	var k: float = (release_multiplier - 1.0) / maxf(release_window, 0.0001)
	var from_hold := hold * k * x * x * 0.5
	var ramp := tau * tau - exp(-x / tau) * (tau * x + tau * tau)
	var from_eased := eased * k * exp(-release_seconds / tau) * ramp
	# Past the window the rate returns to its unwhipped value, so the angle the
	# whip contributed stays constant rather than continuing to grow.
	return from_hold + from_eased


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
##
## **The flares are switched off (2026-08-29, AURA2-F).** v1's verification
## found they read as flat terraced plates at the battle camera's 55.8-degree
## pitch; v2 kept them on the hypothesis that spin would rescue that. It does
## not. Captured at six camera yaws half a face apart and at three points in
## the timeline, they read as a segmented flat ring at every one -- which is
## *closer* to an area marker than v1's continuous version was, because the
## blade gaps make it look like a deliberately drawn circle. The core alone
## reads as light rising around the caster, which is the statement.
##
## The cause is geometric, not a tuning miss: a surface leaning 40 or 62
## degrees off the ground presents nearly face-on to a camera pitched 55.8
## degrees down, so it projects as a plate however it is graded or dimmed.
## Reviving the idea needs different geometry -- a much steeper lean, or a
## different carrier entirely -- not a pass over these numbers.
##
## Restoring them is this one line: [WALL_OPACITY, 0.32, 0.22]. The geometry is
## still built (the shader's uniform arrays are sized 3, and the ring identity
## baked into vertex colour divides by RING_COUNT - 1), so this is the whole
## switch and nothing downstream needs to change.
const RING_OPACITY := [WALL_OPACITY, 0.0, 0.0]
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
