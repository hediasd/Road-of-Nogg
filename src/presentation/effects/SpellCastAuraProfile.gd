## Calibration constants for the generic spell-cast aura.
##
## The effect is four owned layers: an irregular dark ground vortex, a soft
## tapered core, a fan of feathered light shafts, and rising mist. The isolated
## 2026-08-12 aura frame is the authored visual reference. Values labelled
## AUTHORED were chosen by eye against that frame; no pixel measurement is
## claimed.

class_name SpellCastAuraProfile

## DERIVED from the catalog's generic fallback entry.
const PROFILE_ID := ""

## AUTHORED duration and shared normalized timeline.
const DURATION_SECONDS := 1.15
const CHARGE_END := 0.08
const ERUPTION_START := 0.03
const ERUPTION_END := 0.30
const HOLD_END := 0.50
const DECAY_END := 0.90
const SETTLE_NORMALIZED_TIME := 0.92
const ACTION_HOLD_FRACTION := 0.48

## AUTHORED ground vortex. A world-horizontal plane becomes elliptical through
## the orthographic battle camera's pitch, matching the reference without
## baking a view-specific ellipse into the texture space.
const VORTEX_PLANE_SIZE_U := 2.80
const VORTEX_OUTER_RADIUS_U := 1.16
const VORTEX_INNER_DARK_ALPHA := 0.72
const VORTEX_RING_ALPHA := 0.26
const VORTEX_RIM_ALPHA := 0.34
const VORTEX_RIM_EMISSION_ENERGY := 1.10
const VORTEX_HEIGHT_U := 0.018

## AUTHORED tapered core. Six short world-space cards sit around the vortex
## circumference rather than intersecting the body proxy, keeping the volume
## visible around the silhouette while the camera moves.
const CORE_CARD_COUNT := 6
const CORE_SEAT_RADIUS_U := 0.52
const CORE_WIDTH_U := 1.02
const CORE_HEIGHT_U := 1.12
const CORE_PEAK_ALPHA := 0.34
const CORE_WHITE_MIX := 0.00
const CORE_EMISSION_ENERGY := 1.08
const CORE_NOISE_SCALE := 8.0
const CORE_TURBULENCE := 0.38

## AUTHORED world-space ray ribbons. Each is a real radial plane leaning out
## from the vortex, rather than one camera-facing fan behind the model.
const RAY_COUNT := 18
const RAY_HEIGHT_MIN_U := 0.72
const RAY_HEIGHT_MAX_U := 1.44
const RAY_WIDTH_MIN_U := 0.12
const RAY_WIDTH_MAX_U := 0.30
const RAY_SEAT_RADIUS_MIN_U := 0.08
const RAY_SEAT_RADIUS_MAX_U := 0.58
const RAY_LEAN_MIN := 0.16
const RAY_LEAN_MAX := 0.70
const RAY_STAGGER_SPAN := 0.14
const RAY_PEAK_ALPHA := 0.21
const RAY_WHITE_MIX := 0.00
const RAY_EMISSION_ENERGY := 1.24
const RAY_FLICKER_CYCLES := 2.6

## DERIVED mathematical distribution constant; jitter is authored in the
## layout pass so seeded rays do not form a perfect sunflower pattern.
const PHI := 1.618033988749895
const GOLDEN_ANGLE_RADIANS := TAU / (PHI * PHI)

## AUTHORED rising mist. The neutral shared puff supplies shape only; all tint,
## size, motion, blending, and lifetime remain effect-owned.
const WISP_COUNT := 12
const WISP_LIFETIME_SECONDS := 0.86
const WISP_EMISSION_RADIUS_U := 0.74
const WISP_EMISSION_INNER_RADIUS_U := 0.12
const WISP_SPRITE_WIDTH_U := 0.34
const WISP_SPRITE_HEIGHT_U := 0.58
const WISP_VELOCITY_MIN_U := 0.55
const WISP_VELOCITY_MAX_U := 1.30
const WISP_PEAK_ALPHA := 0.42
const WISP_EMISSION_ENERGY := 1.70

## AUTHORED render order. The dark mixed vortex establishes the seat first;
## additive rays, core, and mist build above it.
const VORTEX_RENDER_PRIORITY := 2
const RAY_RENDER_PRIORITY := 3
const CORE_RENDER_PRIORITY := 4
const WISP_RENDER_PRIORITY := 5

## AUTHORED engineering ceilings, asserted when the effect is constructed.
const EXPECTED_DRAW_CALLS := 4
const MAX_DRAW_CALLS := 4
const MAX_EFFECT_NODES := 8
const MAX_GEOMETRY_INSTANCES := 25

## DERIVED: the generic fallback must never evict itself.
const MAX_LIVE_AURAS := 0
