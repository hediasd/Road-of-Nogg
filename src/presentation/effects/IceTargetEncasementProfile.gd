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

## AUTHORED subordinate delivery/contact timing. The trail head reaches the
## body once at ARRIVAL_END_FRACTION, then its frozen taper clears while the
## first shell pieces grow. Contact squares and the flash are brief impact cues
## and never replace the enclosing geometry.
const TRAIL_START_FRACTION := ARRIVAL_START_FRACTION
const TRAIL_IMPACT_FRACTION := ARRIVAL_END_FRACTION
const TRAIL_FADE_END_FRACTION := 0.20
const TRAIL_FADE_IN_FRACTION := 0.018
const TRAIL_INSTANCE_COUNT := 7
const TRAIL_SEGMENT_PROGRESS_SPACING := 0.075
const TRAIL_SOURCE_HEIGHT_U := 0.62
const TRAIL_HEAD_WIDTH_U := 0.115
const TRAIL_TAIL_WIDTH_U := 0.045
const TRAIL_SEGMENT_LENGTH_U := 0.32

const CONTACT_START_FRACTION := 0.065
const CONTACT_STAGGER_FRACTION := 0.012
const CONTACT_DURATION_FRACTION := 0.11
const CONTACT_INSTANCE_COUNT := 8
const CONTACT_SIZE_BODY_FRACTION := 0.28
const CONTACT_SIZE_MIN_U := 0.16
const CONTACT_SIZE_MAX_U := 0.22
const CONTACT_OUTWARD_DISTANCE_U := 0.42

const IMPACT_FLASH_START_FRACTION := 0.075
const IMPACT_FLASH_END_FRACTION := 0.25
const IMPACT_FLASH_SCALE_FRACTION := 0.38
const IMPACT_FLASH_MAX_ALPHA := 0.28

## AUTHORED shell dimensions and restrained seeded variation in local body-bound
## units. The spatial layout itself is deliberately asymmetric; jitter keeps
## repeated casts alive without erasing the large PS1-readable forms.
const SHELL_CLEARANCE_U := 0.055
const MIN_CHUNK_THICKNESS_U := 0.18
const THICKNESS_BODY_FRACTION := 0.40
const POSITION_JITTER_FRACTION := 0.025
const ROTATION_JITTER_RADIANS := 0.085
const SCALE_JITTER_MIN := 0.95
const SCALE_JITTER_MAX := 1.05
const BREAK_DISTANCE_MIN_U := 0.85
const BREAK_DISTANCE_MAX_U := 1.45
const BREAK_LIFT_MIN_U := 0.25
const BREAK_LIFT_MAX_U := 0.85

## AUTHORED asymmetric hero layout. Positions are fractions of body width,
## height, and depth from its centre. Scales use width/height/thickness for
## front/rear, thickness/height/depth for sides, and width/thickness/depth for
## caps. Kind values follow IceChunkMeshFactory.Kind: block, wedge, crystal.
const HERO_LAYOUT := [
	{
		"role": "rear_left_mass", "layer": "shell_rear", "kind": 0,
		"position": Vector3(-0.22, -0.08, -0.58),
		"scale": Vector3(0.76, 0.82, 1.05),
		"rotation": Vector3(0.05, -0.12, -0.12),
		"formation": Vector2(0.08, 0.25),
	},
	{
		"role": "rear_right_crown", "layer": "shell_rear", "kind": 2,
		"position": Vector3(0.28, 0.18, -0.55),
		"scale": Vector3(0.62, 0.72, 1.08),
		"rotation": Vector3(-0.08, 0.14, 0.18),
		"formation": Vector2(0.11, 0.30),
	},
	{
		"role": "left_lower_wall", "layer": "shell_sides", "kind": 1,
		"position": Vector3(-0.58, -0.12, -0.06),
		"scale": Vector3(1.05, 0.88, 0.96),
		"rotation": Vector3(0.08, -0.12, -0.16),
		"formation": Vector2(0.10, 0.27),
	},
	{
		"role": "right_main_wall", "layer": "shell_sides", "kind": 0,
		"position": Vector3(0.58, 0.05, 0.09),
		"scale": Vector3(1.00, 0.82, 0.90),
		"rotation": Vector3(-0.06, 0.11, 0.10),
		"formation": Vector2(0.13, 0.31),
	},
	{
		"role": "left_upper_shard", "layer": "shell_sides", "kind": 2,
		"position": Vector3(-0.56, 0.34, 0.12),
		"scale": Vector3(0.82, 0.46, 0.68),
		"rotation": Vector3(0.12, 0.18, -0.20),
		"formation": Vector2(0.20, 0.36),
	},
	{
		"role": "front_lower_slab", "layer": "shell_front", "kind": 1,
		"position": Vector3(-0.08, -0.32, 0.59),
		"scale": Vector3(1.12, 0.46, 1.08),
		"rotation": Vector3(-0.08, 0.04, -0.09),
		"formation": Vector2(0.20, 0.35),
	},
	{
		"role": "front_diagonal_plate", "layer": "shell_front", "kind": 0,
		"position": Vector3(0.06, 0.02, 0.61),
		"scale": Vector3(0.88, 0.72, 1.00),
		"rotation": Vector3(0.12, -0.05, -0.22),
		"formation": Vector2(0.24, 0.42),
	},
	{
		"role": "front_upper_shard", "layer": "shell_front", "kind": 2,
		"position": Vector3(-0.32, 0.30, 0.58),
		"scale": Vector3(0.50, 0.56, 1.04),
		"rotation": Vector3(-0.16, 0.11, 0.22),
		"formation": Vector2(0.30, 0.46),
	},
	{
		"role": "front_right_block", "layer": "shell_front", "kind": 0,
		"position": Vector3(0.39, -0.19, 0.63),
		"scale": Vector3(0.44, 0.40, 0.92),
		"rotation": Vector3(0.06, -0.18, 0.12),
		"formation": Vector2(0.26, 0.40),
	},
	{
		"role": "cap_swept_slab", "layer": "shell_cap", "kind": 1,
		"position": Vector3(-0.14, 0.58, -0.05),
		"scale": Vector3(0.80, 1.15, 0.88),
		"rotation": Vector3(0.04, -0.08, -0.08),
		"formation": Vector2(0.34, 0.46),
	},
	{
		"role": "cap_right_crystal", "layer": "shell_cap", "kind": 2,
		"position": Vector3(0.34, 0.60, 0.12),
		"scale": Vector3(0.45, 0.90, 0.70),
		"rotation": Vector3(0.12, 0.18, 0.16),
		"formation": Vector2(0.38, 0.48),
	},
]

## AUTHORED transparent-cyan palette. Pale front/cap faces create the white-cyan
## overlap read while dark facets keep adjacent forms countable. Explicit layer
## priorities and an alpha depth prepass keep the translucent volume ordered.
const REAR_COLOR := Color(0.12, 0.62, 0.72, 1.0)
const SIDE_COLOR := Color(0.24, 0.80, 0.88, 1.0)
const FRONT_COLOR := Color(0.54, 0.93, 0.98, 1.0)
const CAP_COLOR := Color(0.70, 0.97, 1.0, 1.0)
const CORE_COLOR := Color(0.78, 0.98, 1.0, 1.0)
const TRAIL_COLOR := Color(0.32, 0.68, 0.94, 1.0)
const CONTACT_COLOR := Color(0.18, 0.30, 0.96, 1.0)
const IMPACT_FLASH_COLOR := Color(0.62, 0.90, 1.0, 1.0)
const SHADOW_COLOR := Color(0.08, 0.36, 0.44, 1.0)
const CORE_SCALE_FRACTION := 0.58

const REAR_OPACITY := 0.50
const SIDE_OPACITY := 0.62
const FRONT_OPACITY := 0.70
const CAP_OPACITY := 0.58
const CORE_OPACITY := 0.44
const TRAIL_OPACITY := 0.72
const SHELL_EMISSION_STRENGTH := 0.16
const CORE_EMISSION_STRENGTH := 0.28
const TRAIL_EMISSION_STRENGTH := 0.12

## DERIVED from 2 rear + 3 side + 4 front + 2 cap hero forms.
const CHUNK_COUNT := 11
const MAX_CHUNKS := 18
const SUPPORTING_INSTANCE_COUNT := TRAIL_INSTANCE_COUNT + CONTACT_INSTANCE_COUNT
const MAX_SUPPORTING_INSTANCES := 16
const TOTAL_GEOMETRY_INSTANCE_COUNT := CHUNK_COUNT + SUPPORTING_INSTANCE_COUNT + 1
const MAX_DRAW_CALLS := 16
const MAX_EFFECT_NODES := 26
const MAX_LIVE_ENCASEMENTS := 2

const LAYER_RENDER_PRIORITIES := {
	"shell_rear": -6,
	"shell_sides": -2,
	"shell_front": 4,
	"shell_cap": 2,
	"ice_core": -4,
	"delivery_trail": -1,
	"contact_accents": 6,
	"impact_flash": 5,
}
