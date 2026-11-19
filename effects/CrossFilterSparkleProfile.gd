## Constants for the cross-filter sparkle aura.
##
## One sparkle type: a soft core with four thin rays, all at one shared screen
## angle, as a cross-screen camera filter marks every light in a frame the same
## way. A single brightness value per sparkle drives the core and the rays
## together, and the rays grow faster than the core, so a dim sparkle reads as
## a dot and a bright one as a star.
##
## Reference: three frames of a 1994 TV cel, studied on 2026-11-19. The palette
## was sampled from six stars on the black areas of a 942 px wide frame. The
## motion itself was settled in an interactive HTML sketch the same day, where
## 12 fps held drawings were chosen over 8 fps and smooth playback.
##
## Provenance labels follow docs/VFX_DESIGN.md §4.

extends RefCounted

const PROFILE_ID := "cross_filter_sparkles"
## Technical name for the picker; not a spell name.
const DISPLAY_NAME := "Cross-Filter Sparkles"

# --- Timeline ---------------------------------------------------------------

## AUTHORED. No carrier spell yet; long enough for an entrance and some idle.
const BATTLE_DURATION_SECONDS := 2.6
## AUTHORED. Reference mode runs longer so the idle can be judged on its own.
const REFERENCE_DURATION_SECONDS := 6.0
## AUTHORED.
const ACTION_HOLD_FRACTION := 0.5
## AUTHORED. Nothing is born in the last SETTLE_SECONDS and the whole field
## fades out over them. The first version only allowed sparkles that would
## finish before the end, which emptied the idle from about 1.2 s on.
const SETTLE_SECONDS := 0.5
const MAX_LIVE_PLAYBACKS := 4

## AUTHORED, chosen by the user from the sketch. The clock the shader sees is
## floored to this rate, so every sparkle holds between ticks like cels shot on
## twos. Zero means smooth.
const FRAME_RATE := 12.0

# --- Population -------------------------------------------------------------

## AUTHORED. Each group owns LANE_COUNT lanes of CHAIN_SLOTS slots: a leader
## plus CHAIN_SLOTS - 1 followers per lane.
const GROUP_COUNT := 30
## AUTHORED. Leader plus up to three followers, as in the reference's chains.
const CHAIN_SLOTS := 4
## AUTHORED. Consecutive cycles of a group alternate between lanes, so a new
## cycle can start while the last one's sparkles are still fading. With one
## lane the period had to hold a whole chain and the longest life, and in a
## 2.6 s battle playback every group fired once: the entrance burst, then
## nothing (first capture, 2026-11-19).
const LANE_COUNT := 2
## AUTHORED. Chance that a group's cycle shows anything at all once the
## entrance has passed.
const IDLE_ACTIVE_CHANCE := 0.85
## AUTHORED. Chance that an active leader brings followers.
const CHAIN_CHANCE := 0.3

## AUTHORED. Every group's first cycle starts inside this window, so the field
## opens with a coherent burst; unequal periods then pull the groups apart into
## an idle with no readable beat (docs/VFX_DESIGN.md, "Living motion").
const ENTRANCE_SPREAD_SECONDS := 0.35
## AUTHORED. Brightness boost on a group's first cycle, decaying with this time
## constant from the start of play.
const ENTRANCE_PEAK_GAIN := 0.6
const ENTRANCE_DECAY_SECONDS := 0.5

## AUTHORED. Lifetimes as in the sketch.
const LIFE_MIN_SECONDS := 0.55
const LIFE_MAX_SECONDS := 1.4
## AUTHORED. Time to reach full brightness.
const RISE_MIN_SECONDS := 0.05
const RISE_MAX_SECONDS := 0.12
## AUTHORED. Fall-off exponent over the life.
const FALL_EXPONENT := 1.3
## AUTHORED. Random delay of a leader inside its cycle.
const BIRTH_JITTER_SECONDS := 0.2
## AUTHORED. Delay between one chain member and the next: one to 2.2 ticks.
const CHAIN_STEP_MIN_SECONDS := 1.0 / 12.0
const CHAIN_STEP_MAX_SECONDS := 2.2 / 12.0
## DERIVED. LANE_COUNT cycles must hold the jitter, a full chain and the
## longest life, so that no slot is asked to show two sparkles at once.
const PERIOD_MIN_SECONDS := (BIRTH_JITTER_SECONDS
		+ (CHAIN_SLOTS - 1) * CHAIN_STEP_MAX_SECONDS + LIFE_MAX_SECONDS) / LANE_COUNT
## AUTHORED. Upper bound of a group's period.
const PERIOD_MAX_SECONDS := 1.6

## AUTHORED. Peak brightness is PEAK_MIN + (1 - PEAK_MIN) * h^PEAK_SKEW, so most
## sparkles are dim dots and a few are full stars.
const PEAK_MIN := 0.16
const PEAK_SKEW := 2.2
## AUTHORED. A follower's peak is its leader's times this range.
const CHAIN_PEAK_MIN := 0.7
const CHAIN_PEAK_MAX := 1.15

## AUTHORED. Flicker over the life: depth and angular rate range (rad/s).
const FLICKER_DEPTH := 0.2
const FLICKER_RATE_MIN := 9.0
const FLICKER_RATE_MAX := 18.0

# --- Placement --------------------------------------------------------------

## AUTHORED. Sparkles sit on an ellipse drawn round the body's outline in the
## camera's plane. 1.0 is the body's own half-width and half-height.
const EDGE_SCALE := 1.0
## AUTHORED. Spread across the edge, in world units. Positive offsets go
## outward, where the reference keeps most of its sparkles. Additive pink all
## but disappears over a bright body, so the bias keeps most of them outside.
const EDGE_SPREAD := 0.11
const EDGE_OUTWARD_BIAS := 0.1
## AUTHORED. World units per second.
const DRIFT_UP_MIN := 0.03
const DRIFT_UP_MAX := 0.12
const DRIFT_SIDE := 0.03
## AUTHORED. Chain spacing as a fraction of the leader's full ray length, so
## neighbouring rays cross as in the reference.
const CHAIN_GAP_FRACTION := 0.8

# --- Star shape -------------------------------------------------------------

## ESTIMATED from the reference: every ray in all three frames is diagonal.
const RAY_ANGLE_DEGREES := 45.0
## AUTHORED. Arm length at full brightness, world units. 0.18 read short next
## to the reference at native resolution (first capture).
const RAY_LENGTH := 0.26
## AUTHORED. Shortest arm, as a fraction of RAY_LENGTH, and how fast the arm
## grows with brightness.
const RAY_MIN_FRACTION := 0.15
const RAY_LENGTH_EXPONENT := 1.25
## AUTHORED. Ray energy is RAY_GAIN * brightness^RAY_EXPONENT, so rays fade out
## before the core does.
const RAY_GAIN := 0.95
const RAY_EXPONENT := 1.6
## AUTHORED. Taper along the arm.
const RAY_TAPER := 1.7
## AUTHORED. Ray half-width in world units, never below RAY_MIN_PIXELS screen
## pixels, so a ray never breaks into dashes at any render resolution.
const RAY_WIDTH := 0.004
const RAY_MIN_PIXELS := 0.55
## AUTHORED. Rays are wider at the root.
const RAY_ROOT_WIDEN := 0.9

## AUTHORED. Core gaussian: energy CORE_BASE + CORE_GAIN * brightness, sigma
## CORE_SIGMA * (CORE_SIGMA_MIN + CORE_SIGMA_GAIN * brightness), never below
## CORE_MIN_PIXELS screen pixels.
## CORE_GAIN was 0.95; bright cores clipped to flat white squares in the first
## capture, where the reference's stay pink-white.
const CORE_BASE := 0.28
const CORE_GAIN := 0.7
const CORE_SIGMA := 0.013
const CORE_SIGMA_MIN := 0.65
const CORE_SIGMA_GAIN := 0.55
const CORE_MIN_PIXELS := 1.1
## AUTHORED. Wide soft halo, the film's diffusion.
const HALO_GAIN := 0.3
const HALO_SIGMA_SCALE := 3.4

# --- Palette ----------------------------------------------------------------
# Energy-to-colour ramp. Stops at 0.30 and 1.00 and the 3 px ring are MEASURED
# from the reference (sRGB 102 28 48, 255 151 187, 200 98 126); the rest are
# AUTHORED to join them. Energy reaches 2.0 only in the brightest cores.

const RAMP_ENERGY: Array[float] = [0.0, 0.12, 0.30, 0.55, 0.80, 1.00, 1.45, 2.00]
const RAMP_COLORS: Array[Color] = [
	Color8(0, 0, 0),
	Color8(58, 6, 22),
	Color8(102, 28, 48),
	Color8(200, 70, 112),
	Color8(235, 110, 150),
	Color8(255, 151, 187),
	Color8(255, 212, 226),
	Color8(255, 244, 248),
]

# --- Budgets ----------------------------------------------------------------

const MAX_EFFECT_NODES := 2
const MAX_DRAW_CALLS := 1
const MAX_INSTANCES := 256
## Targets the shader can surround at once; extra targets share the last slot.
const MAX_BODIES := 8
