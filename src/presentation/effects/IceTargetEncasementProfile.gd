## Authored geometry and engineering limits for target-bound ice encasement.

class_name IceTargetEncasementProfile

const PROFILE_ID := "ice_target_encasement"

## AUTHORED normalized timeline. The windows meet exactly so every transform is
## a pure function of normalized playback time and can be scrubbed in either
## direction without accumulated state.
const REFERENCE_DURATION_SECONDS := 3.4
const BATTLE_DURATION_SECONDS := 1.9
const ACTION_HOLD_FRACTION := 0.72
const ARRIVAL_START_FRACTION := 0.00
const ARRIVAL_END_FRACTION := 0.08
const LOWER_SIDE_FORMATION_START_FRACTION := ARRIVAL_END_FRACTION
const LOWER_SIDE_FORMATION_END_FRACTION := 0.31
const FRONT_CAP_CLOSURE_START_FRACTION := 0.23
const FRONT_CAP_CLOSURE_END_FRACTION := 0.48
const COMPLETED_HOLD_START_FRACTION := FRONT_CAP_CLOSURE_END_FRACTION
const COMPLETED_HOLD_END_FRACTION := 0.68
const FRACTURE_IMPULSE_START_FRACTION := COMPLETED_HOLD_END_FRACTION
const FRACTURE_IMPULSE_END_FRACTION := 0.76
const OUTWARD_TUMBLE_START_FRACTION := FRACTURE_IMPULSE_END_FRACTION
const OUTWARD_TUMBLE_END_FRACTION := 0.92
const SETTLE_START_FRACTION := OUTWARD_TUMBLE_END_FRACTION
const SETTLE_END_FRACTION := 1.00

const FORMATION_COMPRESSED_SCALE := 0.015
const FORMATION_INWARD_FRACTION := 0.28
const FRACTURE_IMPULSE_PATH_FRACTION := 0.20
const FRACTURE_SCALE_PULSE := 0.10
const TUMBLE_ROTATION_STEPS := 7
const SETTLE_SCALE_FRACTION := 0.72
const SETTLE_DROP_U := 0.12
const CORE_FORMATION_START_FRACTION := 0.14
const CORE_FORMATION_END_FRACTION := 0.38
const CORE_BREAK_END_FRACTION := 0.84

## AUTHORED shell dimensions and seeded variation in local body-bound units.
const SHELL_CLEARANCE_U := 0.055
const MIN_CHUNK_THICKNESS_U := 0.18
const THICKNESS_BODY_FRACTION := 0.34
const POSITION_JITTER_FRACTION := 0.035
const ROTATION_JITTER_RADIANS := 0.12
const SCALE_JITTER_MIN := 0.92
const SCALE_JITTER_MAX := 1.08
const BREAK_DISTANCE_MIN_U := 0.85
const BREAK_DISTANCE_MAX_U := 1.45
const BREAK_LIFT_MIN_U := 0.25
const BREAK_LIFT_MAX_U := 0.85

## AUTHORED small, mostly opaque blue-white palette. Each spatial group has a
## distinct value range so overlapping chunks remain countable under the retro
## renderer rather than merging into one flat cyan plate.
const REAR_COLOR := Color(0.24, 0.48, 0.72, 1.0)
const SIDE_COLOR := Color(0.34, 0.66, 0.88, 1.0)
const FRONT_COLOR := Color(0.56, 0.82, 0.98, 1.0)
const CAP_COLOR := Color(0.78, 0.92, 1.0, 1.0)
const CORE_COLOR := Color(0.74, 0.94, 1.0, 1.0)
const SHADOW_COLOR := Color(0.10, 0.24, 0.42, 1.0)
const CORE_SCALE_FRACTION := 0.58

## DERIVED from 4 rear + 4 side + 4 front + 3 cap chunks.
const CHUNK_COUNT := 15
const MAX_CHUNKS := 18
const MAX_DRAW_CALLS := 13
const MAX_EFFECT_NODES := 20
const MAX_LIVE_ENCASEMENTS := 2

const LAYER_RENDER_PRIORITIES := {
	"shell_rear": -6,
	"shell_sides": -2,
	"shell_front": 4,
	"shell_cap": 2,
	"ice_core": -4,
}
