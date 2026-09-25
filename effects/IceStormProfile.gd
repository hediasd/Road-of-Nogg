## Calibration constants for the data-selected ice-area storm effect.
##
## The remodel deliberately assigns each mathematical family one job:
## TAU owns directions and periodic motion, exp() owns energy envelopes, and
## the golden angle owns progressive spatial coverage. The result is quantized
## afterwards; none of these constants is a claim that a ratio is inherently
## beautiful.

class_name IceStormProfile

## DERIVED from the spell catalog's selected VFX profile id.
const PROFILE_ID := "ice_area_storm"

## DERIVED unchanged from the validated pre-remodel timing contract.
const REFERENCE_DURATION_SECONDS := 4.5
const BATTLE_DURATION_SECONDS := 2.2
const REFERENCE_PULSE_INTERVAL_SECONDS := 0.45
const BATTLE_PULSE_INTERVAL_SECONDS := 0.44
const ACTION_HOLD_FRACTION := 0.45

## Four readable beats: floor charge, canopy break, full squall, then settle.
## AUTHORED from the Magenta Reduction phase-language comparison.
const CHARGE_END_FRACTION := 0.14
const CANOPY_REVEAL_START_FRACTION := 0.10
const CANOPY_REVEAL_END_FRACTION := 0.30
const SQUALL_START_FRACTION := 0.22
const SQUALL_FULL_FRACTION := 0.50
const SETTLE_START_FRACTION := 0.82
const ENERGY_RISE_HALF_LIFE_FRACTION := 0.035
const SETTLE_HALF_LIFE_FRACTION := 0.055
const PULSE_ACCENT_FRACTION := 0.16

## The active Ice Plow carrier is radius four. Buff validation additionally
## covers +2 and a larger stress radius; the carrier value is only the density
## baseline, never an authored-size lock.
## MEASURED from `data/spells.json`; tile count DERIVED from A(R).
const REFERENCE_CARRIER_RADIUS_TILES := 4
const REFERENCE_DIAMOND_TILE_COUNT := 41.0

## Counts grow with sqrt(occupied tile area), then cap. This preserves presence
## without doubling density when radius 4 grows from 41 tiles to radius 6's 85.
## AUTHORED against radii 1/4/6/8 under the inherited 220-particle ceiling.
const FLURRY_REFERENCE_AMOUNT := 120
const FLURRY_MIN_AMOUNT := 46
const MAX_LIVE_PARTICLES := 220
const HERO_SHARD_REFERENCE_COUNT := 10
const HERO_SHARD_MIN_COUNT := 4
const HERO_SHARD_MAX_COUNT := 16
const HERO_SHARD_VARIANT_COUNT := 4
const HERO_SHARDS_PER_VARIANT := 4

## AUTHORED footprint-relative storm and canopy proportions.
const REFERENCE_STORM_HEIGHT_U := 4.8
const STORM_HEIGHT_RADIUS_EXPONENT := 0.65
const MIN_STORM_HEIGHT_SCALE := 0.65
const MAX_STORM_HEIGHT_SCALE := 1.55
const CANOPY_WIDTH_MIN_SCALE := 0.30
const CANOPY_WIDTH_STEP_SCALE := 0.04
const CANOPY_HEIGHT_BASE_FRACTION := 0.28
const CANOPY_HEIGHT_STEP_FRACTION := 0.015
## Places the cloud's opaque lower half around the flurry ceiling, so no snow
## can appear above an independently positioned canopy.
const CANOPY_CENTER_ABOVE_SNOW_FRACTION := 0.68
const CANOPY_VERTICAL_JITTER_FRACTION := 0.03
const CANOPY_QUAD_COUNT := 5
const CANOPY_SPREAD_FRACTION := 0.56
const CANOPY_DRIFT_DISTANCE_FRACTION := 0.018
const CANOPY_SCALE_BREATH_FRACTION := 0.035
const CANOPY_SQUALL_RECESS_FRACTION := 0.45
const GROUND_SQUALL_RECESS_FRACTION := 0.68
const FROST_SQUALL_RECESS_FRACTION := 0.82
const FROST_HEIGHT_FRACTION := 0.76

## AUTHORED hard-flake scale, descent, and gust behavior.
const FLAKE_MIN_SIZE_U := 0.09
const FLAKE_MAX_SIZE_U := 0.16
## Authored atlas selection, smallest to largest. The final 0.04 remainder is
## the eight-pixel flake: rare enough to punctuate without dominating.
const SNOW_TINY_WEIGHT := 0.52
const SNOW_SMALL_WEIGHT := 0.30
const SNOW_MEDIUM_WEIGHT := 0.14
const FLAKE_MIN_DOWN_SPEED_U_PER_SECOND := 1.25
const FLAKE_MAX_DOWN_SPEED_U_PER_SECOND := 2.55
const FLAKE_LATERAL_SPEED_U_PER_SECOND := 2.65
const GUST_DIRECTION_XZ := Vector2(0.97, 0.24)
const GUST_BAND_PERIOD_SECONDS := 0.44
const GUST_BAND_WIDTH_FRACTION := 0.22
const GUST_MIN_DENSITY := 0.42

## Golden-angle sampling is progressive: increasing the count fills gaps
## instead of replacing the whole layout. A small deterministic angular jitter
## prevents the familiar sunflower spiral becoming a visible motif.
## DERIVED mathematical constants; jitter AUTHORED to hide the spiral motif.
const PHI := 1.618033988749895
const GOLDEN_ANGLE_RADIANS := TAU / (PHI * PHI)
const GOLDEN_ANGLE_JITTER_FRACTION := 0.16

## PS1 character is imposed after the continuous distribution and motion.
## AUTHORED from the Magenta Reduction quantization vocabulary.
const TEMPORAL_SAMPLE_RATE_HZ := 15.0
const POSITION_QUANTUM_U := 0.0625
const GUST_HEADING_STEPS := 8.0

## AUTHORED hero-shard size, lifetime, population schedule, and palette split.
const HERO_SHARD_MIN_SIZE_U := 0.16
const HERO_SHARD_MAX_SIZE_U := 0.34
const HERO_SHARD_LIFETIME_FRACTION := 0.30
const HERO_SHARD_MIN_TURNS_PER_LIFETIME := 0.35
const HERO_SHARD_MAX_TURNS_PER_LIFETIME := 0.85
const HERO_SHARD_SPAWN_START_FRACTION := 0.18
const HERO_SHARD_SPAWN_END_FRACTION := 0.66
const HERO_SHARD_MIN_HEIGHT_FRACTION := 0.72
const HERO_SHARD_MAX_HEIGHT_FRACTION := 0.98
const HERO_SHARD_DOWN_DISTANCE_FRACTION := 0.82
const HERO_SHARD_MIN_DRIFT_U := 0.65
const HERO_SHARD_MAX_DRIFT_U := 1.20
const HERO_SHARD_BLUE_CHANCE := 0.38

## Lower canopy alpha and harder, countable flakes leave negative space. The
## previous cold-white additive overlap was the main source of fog.
## AUTHORED from the remodel contact-sheet pass.
const CANOPY_CORE_COLOR := Color(0.63, 0.76, 0.90, 0.44)
const CANOPY_EDGE_COLOR := Color(0.28, 0.42, 0.62, 0.22)
## White preserves snow_strip.png's palette; alpha alone controls visibility.
const FLAKE_COLOR := Color(1.0, 1.0, 1.0, 0.88)
const VEIN_COLOR := Color(0.30, 0.43, 0.88, 0.24)
const SHARD_WHITE_COLOR := Color(0.97, 0.99, 1.0, 0.96)
const SHARD_BLUE_COLOR := Color(0.55, 0.79, 1.0, 0.90)
const GROUND_WASH_COLOR := Color(0.35, 0.62, 0.92, 0.09)
const PULSE_BRIGHTNESS_MULTIPLIER := 1.18

## DERIVED unchanged from the pre-remodel engineering ceilings.
const MAX_LIVE_STORMS := 2
const MAX_DRAW_CALLS := 14
const MAX_EFFECT_NODES := 14
