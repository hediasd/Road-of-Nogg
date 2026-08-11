## Authored geometry and engineering limits for target-bound ice encasement.

class_name IceTargetEncasementProfile

const PROFILE_ID := "ice_target_encasement"

## Temporary static-hold timing for the geometry checkpoint. The next
## choreography item replaces this with the authored formation/break timeline.
const REFERENCE_DURATION_SECONDS := 3.4
const BATTLE_DURATION_SECONDS := 1.9
const ACTION_HOLD_FRACTION := 0.72
const SETTLE_START_FRACTION := 0.86

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
