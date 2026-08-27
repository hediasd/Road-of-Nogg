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
