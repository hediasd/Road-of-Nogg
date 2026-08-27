## Calibration constants for the debug-only polygonal technique-charge aura.
##
## AUTHORED from the supplied finishing-technique reference sequence. The
## implementation is original and owns every value and resource it consumes.

class_name TechniqueChargeAuraProfile

const PROFILE_ID := "technique_charge_aura"

## AUTHORED static-preview duration. AURA-2 owns the final beat timing.
const DURATION_SECONDS := 1.60
const SETTLE_NORMALIZED_TIME := 0.88
const ACTION_HOLD_FRACTION := 0.55

## AUTHORED world-space carrier: a compact decagonal wall around one model.
const WALL_SIDES := 10
const WALL_RADIUS_U := 0.74
const WALL_HEIGHT_U := 1.62
## AURA-5: the wall now renders both faces (cull_disabled), so the near and far
## halves overlap wherever the silhouette shows one wall in the old cull_back
## render. blend_mix integrates two stacked layers at alpha a to 1-(1-a)^2, so
## this holds the prior single-wall peak of 0.72 at that overlap.
const WALL_OPACITY := 0.47
const WALL_EMISSION_ENERGY := 0.34
const WALL_RENDER_PRIORITY := 2

## AUTHORED yellow-white grade from the reference's charged lower band.
const AURA_COLOR := Color("fff08a")

## AUTHORED ground contact. The plane is larger than the wall so its bright rim
## remains visible outside the model and wall at the battle-camera pitch.
const GROUND_DIAMETER_U := 1.86
const GROUND_HEIGHT_U := 0.025
const GROUND_INNER_RADIUS_UV := 0.36
const GROUND_OUTER_RADIUS_UV := 0.49
const GROUND_EDGE_SOFTNESS_UV := 0.025
const GROUND_FILL_ALPHA := 0.16
const GROUND_OPACITY := 0.78
const GROUND_EMISSION_ENERGY := 0.52
const GROUND_RENDER_PRIORITY := 1

## AUTHORED safety ceilings: root + two MeshInstance3D children, two surfaces.
const MAX_LIVE_AURAS := 3
const MAX_EFFECT_NODES := 3
const MAX_GEOMETRY_INSTANCES := 2
const MAX_DRAW_CALLS := 2
