## Calibration constants for the reference-locked generic spell-cast aura.
##
## The effect owns one footprint aperture and two continuous plume shells.

class_name SpellCastAuraProfile

## DERIVED from the catalog's generic fallback entry.
const PROFILE_ID := ""

## AUTHORED duration and normalized playback contract, retained for callers.
const DURATION_SECONDS := 1.15
const CHARGE_END := 0.08
const DECAY_END := 0.90
const SETTLE_NORMALIZED_TIME := 0.92
const ACTION_HOLD_FRACTION := 0.48

## MEASURED/TRANSLATED from the eleven supplied frames. The lower source rim
## occupies roughly 37-46 px around the aperture and changes modestly rather
## than emitting separated rings. Values are normalized inside the footprint
## shader's authored outer radius.
const FOOTPRINT_PLANE_SIZE_U := 2.80
const FOOTPRINT_OUTER_RADIUS_U := 1.16
const APERTURE_RADIUS_START := 0.43
const APERTURE_RADIUS_TROUGH := 0.39
const APERTURE_RADIUS_END := 0.53
const APERTURE_RIM_WIDTH := 0.105
const APERTURE_RIM_ALPHA := 0.34
const APERTURE_STRIATION_ALPHA := 0.22
const APERTURE_RIM_EMISSION_ENERGY := 0.82
const CENTER_DARKENING_ALPHA := 0.34
const FOOTPRINT_HEIGHT_U := 0.018
const FOOTPRINT_RENDER_PRIORITY := 2

## AUTHORED continuous far-side plume curtain. Both shells use the same original
## eleven-state 704x64 atlas but differ in flare, height, phase, and opacity.
const PLUME_ATLAS_PIXEL_SIZE := Vector2(704.0, 64.0)
const PLUME_SHELL_SEGMENTS := 64
const PLUME_SHELL_HEIGHT_BANDS := 8
const PLUME_BASE_HEIGHT_U := 0.025
const PLUME_INNER_BOTTOM_RADIUS_U := 0.44
const PLUME_INNER_TOP_RADIUS_U := 0.88
const PLUME_INNER_HEIGHT_U := 1.32
const PLUME_INNER_UV_PHASE := 0.06
const PLUME_INNER_OPACITY := 0.65
const PLUME_INNER_EMISSION_ENERGY := 2.80
const PLUME_OUTER_BOTTOM_RADIUS_U := 0.53
const PLUME_OUTER_TOP_RADIUS_U := 1.18
const PLUME_OUTER_HEIGHT_U := 1.68
const PLUME_OUTER_UV_PHASE := 0.41
const PLUME_OUTER_OPACITY := 0.45
const PLUME_OUTER_EMISSION_ENERGY := 2.00
const PLUME_STATE_CROSSFADE := 1.0
const PLUME_INNER_RENDER_PRIORITY := 3
const PLUME_OUTER_RENDER_PRIORITY := 4

## AUTHORED final engineering ceiling: footprint plus two plume calls, with no
## particles or billboards.
const EXPECTED_DRAW_CALLS := 3
const MAX_DRAW_CALLS := 3
const EXPECTED_GEOMETRY_INSTANCES := 3
const MAX_GEOMETRY_INSTANCES := 3
const MAX_EFFECT_NODES := 4

## DERIVED: the generic fallback must never evict itself.
const MAX_LIVE_AURAS := 0
