## Calibration constants for the reference-locked generic spell-cast aura.
##
## The effect owns one restrained footprint aperture, one alpha-mixed body haze,
## and one additive far-side ghost-ray shell, all in world space.

class_name SpellCastAuraProfile

## DERIVED from the catalog's generic fallback entry.
const PROFILE_ID := ""

## AUTHORED duration and normalized playback contract, retained for callers.
const DURATION_SECONDS := 1.15
const CHARGE_END := 0.08
const DECAY_END := 0.90
const SETTLE_NORMALIZED_TIME := 0.92
const ACTION_HOLD_FRACTION := 0.48

## MEASURED/TRANSLATED eleven-state source timeline. State times are the exact
## normalized checkpoints used for comparison. Independent curves prevent the
## atlas reorganization, plume strength, aperture, and rim texture from being
## collapsed into one monotonic shader envelope.
const SOURCE_STATE_PROGRESS := [
	0.08, 0.15, 0.22, 0.29, 0.36, 0.43, 0.50, 0.57, 0.64, 0.72, 0.82,
]
const PLUME_ENERGY_CURVE := [
	1.00, 1.13, 1.11, 0.96, 0.79, 0.64, 0.61, 0.76, 0.82, 0.85, 0.70,
]
const APERTURE_RADIUS_CURVE := [
	0.43, 0.425, 0.420, 0.413, 0.405, 0.397, 0.390, 0.420, 0.458, 0.500, 0.530,
]
const APERTURE_RIM_WIDTH_CURVE := [
	0.115, 0.113, 0.111, 0.109, 0.106, 0.103, 0.100, 0.096, 0.091, 0.085, 0.078,
]
const APERTURE_STRIATION_CURVE := [
	1.00, 0.98, 0.91, 0.82, 0.68, 0.52, 0.36, 0.20, 0.09, 0.02, 0.00,
]

## MEASURED/TRANSLATED from the eleven supplied frames. The lower source rim
## occupies roughly 37-46 px around the aperture and changes modestly rather
## than emitting separated rings. Values are normalized inside the footprint
## shader's authored outer radius.
const FOOTPRINT_PLANE_SIZE_U := 2.30
const FOOTPRINT_OUTER_RADIUS_U := 0.92
const APERTURE_RADIUS_START := APERTURE_RADIUS_CURVE[0]
const APERTURE_RADIUS_TROUGH := APERTURE_RADIUS_CURVE[6]
const APERTURE_RADIUS_END := APERTURE_RADIUS_CURVE[10]
const APERTURE_RIM_WIDTH := 0.105
const APERTURE_RIM_ALPHA := 0.20
const APERTURE_STRIATION_ALPHA := 0.08
const APERTURE_RIM_EMISSION_ENERGY := 0.58
const CENTER_DARKENING_ALPHA := 0.42
const FOOTPRINT_HEIGHT_U := 0.018
const FOOTPRINT_RENDER_PRIORITY := 2

## AUTHORED replica carrier split. Haze and rays sample the same deterministic
## eleven-state atlas during the structural item, but own distinct shaders,
## blend modes, mesh profiles, and explicit parameters.
const PLUME_ATLAS_PIXEL_SIZE := Vector2(704.0, 64.0)
const PLUME_SHELL_SEGMENTS := 64
const PLUME_SHELL_HEIGHT_BANDS := 24
const PLUME_BASE_HEIGHT_U := 0.025
const HAZE_BOTTOM_RADIUS_U := 0.48
const HAZE_MIDDLE_RADIUS_U := 1.08
const HAZE_TOP_RADIUS_U := 0.96
const HAZE_MIDDLE_HEIGHT_FRACTION := 0.42
const HAZE_HEIGHT_U := 1.32
const HAZE_UV_PHASE := 0.06
const HAZE_OPACITY := 0.46
const HAZE_EMISSION_ENERGY := 0.24
const RAY_BOTTOM_RADIUS_U := 0.52
const RAY_MIDDLE_RADIUS_U := 1.18
const RAY_TOP_RADIUS_U := 1.42
const RAY_MIDDLE_HEIGHT_FRACTION := 0.55
const RAY_HEIGHT_U := 1.72
const RAY_UV_PHASE := 0.20
const RAY_OPACITY := 0.28
const RAY_EMISSION_ENERGY := 0.92
## Literal state comparisons retain more of the source's frame-specific plume
## grouping than cross-fading, which blurs adjacent silhouettes into haze.
const PLUME_STATE_CROSSFADE := 0.0
const HAZE_RENDER_PRIORITY := 3
const RAY_RENDER_PRIORITY := 4

## AUTHORED final engineering ceiling: footprint plus two plume calls, with no
## particles or billboards.
const EXPECTED_DRAW_CALLS := 3
const MAX_DRAW_CALLS := 3
const EXPECTED_GEOMETRY_INSTANCES := 3
const MAX_GEOMETRY_INSTANCES := 3
const MAX_EFFECT_NODES := 4

## DERIVED: the generic fallback must never evict itself.
const MAX_LIVE_AURAS := 0
