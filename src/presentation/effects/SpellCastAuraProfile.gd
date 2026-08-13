## Calibration constants for the reference-locked generic spell-cast aura.
##
## This implementation item owns only the single footprint aperture. The next
## item adds two continuous plume shells without changing this carrier.

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

## AUTHORED interim engineering ceilings. Two plume calls are reserved by the
## final ceiling; this item itself creates only the footprint carrier.
const EXPECTED_DRAW_CALLS := 1
const MAX_DRAW_CALLS := 3
const EXPECTED_GEOMETRY_INSTANCES := 1
const MAX_GEOMETRY_INSTANCES := 3
const MAX_EFFECT_NODES := 4

## DERIVED: the generic fallback must never evict itself.
const MAX_LIVE_AURAS := 0
