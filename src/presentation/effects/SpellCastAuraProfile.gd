## Calibration constants for the generic spell-cast ray burst.
##
## The effect is a crown of pointed, translucent light blades erupting out of
## the ground under the caster. Two properties drive every number here:
##
## - a blade is *geometry*, not a stretched sprite. Its point comes from the
##   silhouette the mesh is authored with, and its crispness from standing on
##   the world's up axis under an orthographic, zero-roll camera.
## - a blade is *faint on its own*. Additive blending is what makes crossing
##   blades pile up into the white-hot seat; the per-blade peak alpha is
##   therefore deliberately low, and brightness is bought with overlap rather
##   than with emission energy.

class_name SpellCastAuraProfile

## DERIVED from the catalog's fallback entry, which carries the empty id.
const PROFILE_ID := ""

## AUTHORED population bounds. Fewer than the floor and the crown reads as a
## handful of stray shards; more than the ceiling and the rays stop being
## legible as separate rays inside the cup. All of them live in one MultiMesh,
## so population costs instances, not draw calls.
const MIN_BLADE_COUNT := 20
const MAX_BLADE_COUNT := 32

## AUTHORED: clear of z-fighting with the ground plane at the shipping camera
## distance, without floating visibly above it.
const SEAT_HEIGHT_U := 0.02

## AUTHORED ring composition. The reference burst is not a bouquet of separate
## spikes: it is a flared cup of light, wide as a couple of tiles and several
## times the caster's height, whose individual rays are legible *inside* a
## filled silhouette. Two rings produce that. The inner ring is short, wide and
## barely leaned — it is the wall of the cup — and the outer ring is tall,
## narrow and strongly leaned, giving the rim its spikes and its flare.
##
## Every dimension is in world units, where a tile is 1.0 u and the standard
## body proxy is about 1.6 u tall. Widths are fixed rather than derived from
## anything, because a sharp line is defined in pixels.
const RING_INNER := {
	"count": 12,
	"hero_count": 0,
	"seat_radius_min": 0.16,
	"seat_radius_max": 0.46,
	"height_min": 1.30,
	"height_max": 2.30,
	"hero_height_min": 0.0,
	"hero_height_max": 0.0,
	"width_min": 0.34,
	"width_max": 0.62,
	"hero_width_min": 0.0,
	"hero_width_max": 0.0,
	"lean_min": 0.18,
	"lean_max": 0.55,
	# Held below the outer ring: twelve wide blades stacking additively at the
	# centre is exactly how a cup of light becomes a white blob.
	"alpha_multiplier": 0.72,
}
const RING_OUTER := {
	"count": 16,
	# Five hero blades carry the silhouette and reach well past the caster.
	# Without the split the rim reads as one uniform bristle.
	"hero_count": 5,
	"seat_radius_min": 0.52,
	"seat_radius_max": 1.00,
	"height_min": 2.40,
	"height_max": 3.70,
	"hero_height_min": 4.20,
	"hero_height_max": 5.60,
	"width_min": 0.28,
	"width_max": 0.50,
	"hero_width_min": 0.56,
	"hero_width_max": 0.82,
	"lean_min": 0.60,
	"lean_max": 1.85,
	"alpha_multiplier": 1.0,
}
## Inner first, so the wall is already standing when the rim spikes arrive.
const RINGS := [RING_INNER, RING_OUTER]

## DERIVED from the ring counts above; asserted against them at build time.
const BLADE_COUNT := 28

## DERIVED extremes across both rings, used to normalize the eruption delay and
## to size the culling box.
const CROWN_SEAT_RADIUS_MIN_U := 0.16
const CROWN_SEAT_RADIUS_MAX_U := 1.00
const CROWN_REACH_U := 3.10
const CROWN_HEIGHT_U := 5.60

## AUTHORED: lean applies on a mildly super-linear height curve. Squaring it
## bent the blades into whiskers; this keeps them straight rays that splay
## outward as a cone.
const LEAN_HEIGHT_EXPONENT := 1.35

## AUTHORED blade silhouette, in fractions of width and height. A broad seat,
## shoulders at roughly two thirds, then a single sharp apex.
const SILHOUETTE_SHOULDER_HEIGHT := 0.62
const SILHOUETTE_SHOULDER_WIDTH := 0.42
const SILHOUETTE_SEAT_WIDTH := 1.0

## AUTHORED azimuth distribution. The golden angle spreads blades progressively
## rather than in a repeating pattern; the jitter keeps the spiral from
## becoming a visible motif, exactly as in the storm profiles.
## DERIVED mathematical constant; jitter AUTHORED.
const PHI := 1.618033988749895
const GOLDEN_ANGLE_RADIANS := TAU / (PHI * PHI)
const AZIMUTH_JITTER_FRACTION := 0.22

## AUTHORED cross-width alpha profile. Quantizing the ramp into whole steps is
## what keeps the edge hard: a smooth falloff under additive blending is a
## glow, and a glow is the opposite of a ray.
## Peak alpha came down when the population went from 17 blades to 28: the
## same per-blade value that read as translucent in a sparse bouquet stacks
## into an opaque white cup once the inner ring is filling the middle.
const EDGE_ALPHA_STEPS := 3.0
const CORE_WIDTH_FRACTION := 0.34
const PEAK_ALPHA := 0.46
const HERO_ALPHA_MULTIPLIER := 1.15

## AUTHORED vertical falloff. The tip fades just short of the apex so the point
## stays a point instead of ending in a cut-off bar.
const TIP_FADE_START := 0.88
const SEAT_GLOW_HEIGHT := 0.26

## AUTHORED palette derivation. Every colour comes from the caller's element
## tint: the seat is pushed most of the way to white, the body keeps the hue,
## and the tip deepens it so the fringe stays legible against bright terrain.
const SEAT_WHITE_MIX := 0.76
const BODY_WHITE_MIX := 0.22
const TIP_DEEPEN := 0.78
const BODY_GRADIENT_END := 0.34
const TIP_GRADIENT_START := 0.40
## AUTHORED: emission energy stays low because overlap, not energy, is where
## the white-hot core is meant to come from.
const EMISSION_ENERGY := 2.3

## AUTHORED per-blade brightness spread, so a crown of identical blades does
## not read as one printed shape.
const BRIGHTNESS_MIN := 0.72
const BRIGHTNESS_MAX := 1.0

## AUTHORED duration. This is a flash, not an animation the player waits
## through: the whole event is over inside a second, and the queue releases
## before the tail has finished clearing.
const DURATION_SECONDS := 1.0

## AUTHORED timeline, in normalized time. Five named windows:
##
##   0.00 - 0.07  charge   the ground brightens; no blade has broken out yet
##   0.03 - 0.35  eruption blades punch up, staggered from the seat outward
##   0.35 - 0.44  hold     the full crown stands
##   0.44 - 0.88  decay    blades stretch upward and fade
##   0.88 - 1.00  clear    nothing remains
##
## The eruption window overlaps the charge deliberately: the first blade leaves
## the ground while the rupture is still brightening, so the two read as one
## event rather than a cue followed by a payoff.
const CHARGE_END := 0.07
const ERUPTION_START := 0.03
## Per-blade growth length, and the spread of per-blade start delays. Their sum
## is when the last blade finishes, so they are what the hold window waits for.
const ERUPTION_SPAN := 0.16
const ERUPTION_STAGGER_SPAN := 0.16
const HOLD_END := 0.44
const DECAY_END := 0.88

## AUTHORED: a blade overshoots its height near the middle of its own growth
## window and returns to exactly its authored height by the end of it, so the
## eruption has a snap without any endpoint drift.
const OVERSHOOT_AMOUNT := 0.16
## AUTHORED: during decay the blades keep travelling upward as they fade, which
## reads as energy escaping rather than as a light being switched off.
const DECAY_STRETCH := 0.14

## AUTHORED stagger weighting. Most of a blade's delay comes from how far out
## it is seated, so the eruption reads as a wave travelling outward; the jitter
## keeps the wave from arriving as a clean expanding ring.
const DELAY_RADIUS_WEIGHT := 0.78
const DELAY_JITTER_FRACTION := 0.26

## AUTHORED: late enough that skipping lands on an almost-cleared crown, rather
## than cutting a full-height flash off the screen.
const SETTLE_NORMALIZED_TIME := 0.90

## AUTHORED: the visual queue holds through the eruption and the completed
## crown, then releases while the tail fades. Deliberately shorter than the
## 0.6 the catalog previously hard-coded, because the new shape reaches its
## full read much earlier than the old expanding ring did.
const ACTION_HOLD_FRACTION := 0.45

## AUTHORED render priority. The blades draw after the ground layer so the
## additive crown is never cut by the decal it grows out of.
const RAY_RENDER_PRIORITY := 4

## AUTHORED engineering ceilings, asserted at build time.
const MAX_SUPPORT_INSTANCES := 10
const MAX_EFFECT_NODES := 10
const MAX_DRAW_CALLS := 8
## DERIVED: the generic profile is the fallback for every unprofiled spell, so
## it must never evict itself.
const MAX_LIVE_AURAS := 0
