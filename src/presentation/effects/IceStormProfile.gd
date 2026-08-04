## Shared calibration constants for the data-selected ice-area storm effect.
##
## Provenance rule: S2 governs battlefield scale, opacity, negative space, and
## the deliberately crisp low-resolution character. S1 governs layer anatomy,
## hue relationships, and hard shard silhouettes only. The inspected Zeoh
## footage is post-Renewal and RagnarokZero is secondary; on 2026-08-03 the
## user explicitly authorized using those clips for estimated motion timing.
## Nothing below claims to be a frame measurement from a classic client.

class_name IceStormProfile

## ESTIMATED from the plan's data-boundary decision; presentation metadata only.
const PROFILE_ID := "ice_area_storm"

## ESTIMATED animation duration from classic wiki mechanics; not frame-measured.
const REFERENCE_DURATION_SECONDS := 4.5
## ESTIMATED Road of Nogg pacing target; final validation still owns approval.
const BATTLE_DURATION_SECONDS := 2.2
## ESTIMATED from ten visible/mechanical beats across the 4.5 s reference span.
const REFERENCE_PULSE_INTERVAL_SECONDS := 0.45
## ESTIMATED to preserve the authorized secondary-footage rhythm in battle mode.
const BATTLE_PULSE_INTERVAL_SECONDS := 0.44
## ESTIMATED from S2's already-dense onset and the inspected secondary footage.
const ONSET_FRACTION := 0.08
## ESTIMATED from the sustained-field structure in S2 and wiki duration.
const SUSTAIN_FRACTION := 0.74
## ESTIMATED because no qualifying classic footage exposes the full settle.
const SETTLE_FRACTION := 0.18
## ESTIMATED derivative of onset plus sustain; the stagger begins at this phase.
const SETTLE_START_FRACTION := 0.82
## ESTIMATED from the queue-pacing decision to hold onset plus two early pulses.
const ACTION_HOLD_FRACTION := 0.45
## ESTIMATED short accent window around each pulse, judged from secondary motion.
const PULSE_ACCENT_FRACTION := 0.18

## MEASURED from S2 against tile = 1.0 u and unit height approximately 1.0 u.
const REFERENCE_UNIT_HEIGHT_U := 1.0
## MEASURED from the selected radius-two carrier's authored footprint.
const REFERENCE_CARRIER_RADIUS_TILES := 2
## MEASURED from radius * 2 + 1 at tile width 1.0 u.
const REFERENCE_FOOTPRINT_DIAMETER_U := 5.0
## ESTIMATED from S2's roughly four-character-height storm volume.
const STORM_VOLUME_HEIGHT_U := 3.8
## ESTIMATED from S2; the canopy stays well above one-unit silhouettes.
const CANOPY_MIN_HEIGHT_U := 2.5
## ESTIMATED from S2 and S1's structural upper cloud extent.
const CANOPY_MAX_HEIGHT_U := 3.5
## MEASURED from S2; the canopy spans approximately the full ground footprint.
const CANOPY_WIDTH_SCALE := 1.0

## MEASURED from S1's two-to-three overlapping cloud masses; upper bound chosen.
const CANOPY_QUAD_COUNT := 3
## ESTIMATED from S1's slow drift relative to a five-unit footprint.
const CANOPY_DRIFT_DISTANCE_U := 0.24
## ESTIMATED from S1's restrained breathing rather than modern volumetric swell.
const CANOPY_SCALE_BREATH_FRACTION := 0.06
## MEASURED from S1's single branching frost-vein backdrop.
const VEIN_LAYER_COUNT := 1

## ESTIMATED from S2's dense-but-gappy field under the 220-particle hard budget.
const FLURRY_PARTICLE_AMOUNT := 180
## ESTIMATED from S2's 2-5 px specks relative to approximately one-unit bodies.
const FLAKE_MIN_SIZE_U := 0.04
## ESTIMATED from S2's largest short streaks while remaining below shard scale.
const FLAKE_MAX_SIZE_U := 0.11
## ESTIMATED from the inspected secondary descent across the vertical volume.
const FLAKE_MIN_DOWN_SPEED_U_PER_SECOND := 1.1
## ESTIMATED from the fastest visible secondary-footage streaks.
const FLAKE_MAX_DOWN_SPEED_U_PER_SECOND := 2.2
## ESTIMATED from S2's strong horizontal smear and secondary motion.
const FLAKE_LATERAL_SPEED_U_PER_SECOND := 2.4
## ESTIMATED from S1/S2 banding: mostly lateral with a shallow depth component.
const GUST_DIRECTION_XZ := Vector2(0.97, 0.24)
## ESTIMATED to align one travelling band with each authorized pulse beat.
const GUST_BAND_PERIOD_SECONDS := 0.45
## ESTIMATED from S1's broad curved density bands across the footprint.
const GUST_BAND_WIDTH_FRACTION := 0.30

## MEASURED acceptance cap from S1/S2: hero silhouettes remain countable.
const HERO_SHARD_MAX_VISIBLE := 8
## MEASURED from S1 against unit height approximately 1.0 u.
const HERO_SHARD_MIN_SIZE_U := 0.15
## MEASURED from S1 against unit height approximately 1.0 u.
const HERO_SHARD_MAX_SIZE_U := 0.30
## ESTIMATED to show about eight shards across the 4.5 s reference sequence.
const HERO_SHARD_SPAWN_RATE_PER_SECOND := 1.8
## ESTIMATED from the secondary footage's individually brief shard silhouettes.
const HERO_SHARD_LIFETIME_SECONDS := 1.25
## ESTIMATED from S1's clearly tumbling, not rapidly spinning, polygons.
const HERO_SHARD_MIN_TURNS_PER_LIFETIME := 0.55
## ESTIMATED from S1's varied shard orientations.
const HERO_SHARD_MAX_TURNS_PER_LIFETIME := 1.25

## ESTIMATED RGB from S2 luminosity with S1 supplying only the hue relationship.
const CANOPY_CORE_COLOR := Color(0.96, 0.985, 1.0, 0.68)
## ESTIMATED RGB from S2's restrained edge opacity and S1's grey-blue edge hue.
const CANOPY_EDGE_COLOR := Color(0.64, 0.76, 0.88, 0.28)
## ESTIMATED RGB from S2's cold-white specks and preserved negative space.
const FLAKE_COLOR := Color(0.90, 0.96, 1.0, 0.62)
## ESTIMATED RGB from S1's blue-violet veins, with S2 governing low alpha.
const VEIN_COLOR := Color(0.27, 0.34, 0.72, 0.16)
## ESTIMATED RGB from S1's near-opaque white hero polygons.
const SHARD_WHITE_COLOR := Color(0.97, 0.99, 1.0, 0.94)
## ESTIMATED RGB from S1's faint blue shard variation.
const SHARD_BLUE_COLOR := Color(0.72, 0.87, 1.0, 0.86)
## ESTIMATED RGB from S2's translucent cold floor response.
const GROUND_WASH_COLOR := Color(0.52, 0.74, 0.94, 0.18)
## ESTIMATED from S2's restrained bright core without environment glow.
const PULSE_BRIGHTNESS_MULTIPLIER := 1.22

## MEASURED acceptance ceiling from S2; at least forty percent remains readable.
const MAX_FULLY_OBSCURED_FRACTION := 0.60
## ESTIMATED tuning target below the hard ceiling to preserve obvious gaps.
const TARGET_FILLED_FRACTION := 0.48
## ESTIMATED engineering ceiling recorded in the plan for one storm.
const MAX_LIVE_PARTICLES := 220
## ESTIMATED reference-faithful cap settled by the plan for live storms.
const MAX_LIVE_STORMS := 2
## ESTIMATED engineering draw-call ceiling recorded in the plan.
const MAX_DRAW_CALLS := 14
## ESTIMATED engineering node-count ceiling recorded in the plan.
const MAX_EFFECT_NODES := 12

## Source: authorized decomposition and secondary motion; final visual validation
## ESTIMATED checkpoints may change only with recorded replacement evidence.
const COMPARISON_CHECKPOINTS := [0.08, 0.25, 0.50, 0.75, 0.95]
