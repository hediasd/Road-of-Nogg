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
## AUTHORED onset translation. The source sequence begins at CHARGE_END, so the
## uncaptured lead-in follows the user's explicit zero -> ring -> rising plume
## direction. The reveal front finishes above UV 1.0 so source state 1 is not
## attenuated at its top edge.
const FOOTPRINT_IGNITION_END := 0.018
const PLUME_EMISSION_START := 0.010
const PLUME_ROOT_IGNITION_END := 0.040
const PLUME_REVEAL_SOFTNESS := 0.080
const PLUME_REVEAL_END := 1.0 + PLUME_REVEAL_SOFTNESS
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
## TRANSLATED capture calibration. A 360-degree carrier does not project the
## measured 2D widths and heights uniformly, so the two material roles retain
## small keyed corrections instead of pretending one static shell fits all
## eleven silhouettes. Values interpolate under exact normalized seek.
const HAZE_WIDTH_SCALE_CURVE := [
	1.01, 0.96, 0.96, 0.80, 0.89, 1.08, 1.04, 1.05, 1.01, 0.89, 0.88,
]
const HAZE_HEIGHT_SCALE_CURVE := [
	1.09, 0.95, 0.89, 0.85, 0.86, 1.15, 1.06, 1.12, 1.04, 1.01, 0.85,
]
const RAY_WIDTH_SCALE_CURVE := [
	1.04, 1.07, 1.05, 1.02, 0.92, 1.00, 1.03, 1.00, 1.05, 1.04, 0.98,
]
const RAY_HEIGHT_SCALE_CURVE := [
	0.92, 0.87, 0.84, 0.91, 0.91, 1.04, 1.05, 0.98, 1.06, 1.01, 0.91,
]
const APERTURE_RADIUS_CURVE := [
	0.560, 0.555, 0.548, 0.538, 0.528, 0.518, 0.505, 0.548, 0.610, 0.675, 0.720,
]
const APERTURE_RIM_WIDTH_CURVE := [
	0.095, 0.094, 0.092, 0.090, 0.087, 0.084, 0.081, 0.077, 0.072, 0.067, 0.062,
]
const APERTURE_STRIATION_CURVE := [
	1.00, 0.98, 0.91, 0.82, 0.68, 0.52, 0.36, 0.20, 0.09, 0.02, 0.00,
]

## MEASURED/TRANSLATED from the eleven supplied frames. The lower source rim
## occupies roughly 37-46 px around the aperture and changes modestly rather
## than emitting separated rings. Values are normalized inside the footprint
## shader's authored outer radius.
const FOOTPRINT_PLANE_SIZE_U := 2.60
const FOOTPRINT_OUTER_RADIUS_U := 1.05
const APERTURE_RADIUS_START := APERTURE_RADIUS_CURVE[0]
const APERTURE_RADIUS_TROUGH := APERTURE_RADIUS_CURVE[6]
const APERTURE_RADIUS_END := APERTURE_RADIUS_CURVE[10]
const APERTURE_RIM_WIDTH := 0.090
const APERTURE_RIM_ALPHA := 0.035
const APERTURE_STRIATION_ALPHA := 0.06
const APERTURE_RIM_EMISSION_ENERGY := 0.015
const CENTER_DARKENING_ALPHA := 0.60
const FOOTPRINT_HEIGHT_U := 0.018
const FOOTPRINT_RENDER_PRIORITY := 2

## AUTHORED replica carrier split. Haze retains subtle deterministic atlas
## modulation while both material jobs own analytic fields, distinct blend
## modes, mesh profiles, and explicit parameters.
const PLUME_ATLAS_PIXEL_SIZE := Vector2(2816.0, 256.0)
const PLUME_SHELL_SEGMENTS := 64
const PLUME_SHELL_HEIGHT_BANDS := 96
const PLUME_BASE_HEIGHT_U := 0.025
const HAZE_BOTTOM_RADIUS_U := 0.72
const HAZE_MIDDLE_RADIUS_U := 1.05
const HAZE_TOP_RADIUS_U := 1.38
const HAZE_MIDDLE_HEIGHT_FRACTION := 0.50
const HAZE_HEIGHT_U := 1.09
const HAZE_UV_PHASE := 0.06
const HAZE_OPACITY := 0.85
const HAZE_EMISSION_ENERGY := 2.00
const RAY_BOTTOM_RADIUS_U := 0.78
const RAY_MIDDLE_RADIUS_U := 1.14
const RAY_TOP_RADIUS_U := 1.52
const RAY_MIDDLE_HEIGHT_FRACTION := 0.50
const RAY_HEIGHT_U := 1.36
const RAY_UV_PHASE := 0.20
const RAY_OPACITY := 0.55
const RAY_EMISSION_ENERGY := 4.20
## Haze can bridge authored atlas states. The analytic ray field uses continuous
## source-state position; its retained value keeps debug API parity only.
const HAZE_STATE_CROSSFADE := 0.55
const RAY_STATE_CROSSFADE := 0.18
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
