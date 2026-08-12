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

## AUTHORED shell dimensions, in world units, where a tile is 1.0 u and the
## standard body proxy is about 1.6 u tall. The reference burst is a cup: a
## narrow seat opening into a rim a couple of tiles across, standing several
## times the caster's height. Discrete blades were tried first and retired —
## the rays in the reference are striations on this wall, not free-standing
## shapes, and its points are the wall's ragged top edge.
const SHELL_BASE_RADIUS_U := 0.78
const SHELL_RIM_RADIUS_U := 1.28
const SHELL_HEIGHT_U := 3.60
## AUTHORED: the rim's ellipse must not read as a polygon at the retro
## viewport's native resolution, and the wall needs enough rows for its
## vertical ramp to interpolate cleanly.
const SHELL_RADIAL_SEGMENTS := 40
const SHELL_VERTICAL_SEGMENTS := 4
## AUTHORED: how tight the shell is before it opens. Starting at zero makes the
## eruption a point rather than a mouth.
const SHELL_OPEN_START := 0.42

## AUTHORED striations. These are the rays. Their count is what makes them
## countable, their width spread is what keeps them from reading as a printed
## pattern, and their hard band edges are what keep them rays rather than glow.
const STRIPE_COUNT := 22.0
const STRIPE_WIDTH_MIN := 0.30
const STRIPE_WIDTH_MAX := 0.86
const STRIPE_ALPHA := 0.30
## AUTHORED: a dim wash between the bands. Without it the wall is a picket
## fence; too much of it and the striations disappear into a cone of fog.
const WALL_GLOW_ALPHA := 0.24

## AUTHORED ragged rim. Each stripe stops at its own height between these
## bounds, which is where the effect's pointed ends come from.
const TOOTH_MIN := 0.52
const TOOTH_MAX := 1.0
const TOOTH_SOFT := 0.20

## AUTHORED silhouette brightening. A shell only reads as a volume if its
## edge-on flanks are brighter than the wall facing the camera.
const EDGE_GAIN := 1.7
const EDGE_POWER := 2.5

## AUTHORED: extra weight where the shell meets the ground, which is the
## hottest part of the reference frame.
const SEAT_GLOW_HEIGHT := 0.34

## AUTHORED palette derivation, as a three-stop vertical ramp. Every colour
## still comes from the caller's element tint: the seat is pushed nearly to
## white, the body keeps the hue lightened, and the rim deepens it so the top
## edge stays legible against bright terrain. The reference runs warm at the
## bottom and coloured at the top, and this is that structure without inventing
## a second hue the element palette does not have.
const BASE_WHITE_MIX := 0.88
const BODY_WHITE_MIX := 0.34
const RIM_DEEPEN := 0.85
const BODY_GRADIENT_END := 0.35
const RIM_GRADIENT_START := 0.45
## AUTHORED: emission energy stays low because overlap, not energy, is where
## the white-hot core is meant to come from.
const EMISSION_ENERGY := 2.3

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

## AUTHORED: late enough that skipping lands on an almost-cleared crown, rather
## than cutting a full-height flash off the screen.
const SETTLE_NORMALIZED_TIME := 0.90

## AUTHORED: the visual queue holds through the eruption and the completed
## crown, then releases while the tail fades. Deliberately shorter than the
## 0.6 the catalog previously hard-coded, because the new shape reaches its
## full read much earlier than the old expanding ring did.
const ACTION_HOLD_FRACTION := 0.45

## AUTHORED render priority. The shell draws after the ground layer so the
## additive cup is never cut by the decal it grows out of.
const RAY_RENDER_PRIORITY := 4

## AUTHORED engineering ceilings, asserted at build time. The shell is one mesh
## in one draw call, so the population that used to cost 28 instances now costs
## none at all.
const MAX_SUPPORT_INSTANCES := 10
const MAX_EFFECT_NODES := 8
const MAX_DRAW_CALLS := 6
## DERIVED: the generic profile is the fallback for every unprofiled spell, so
## it must never evict itself.
const MAX_LIVE_AURAS := 0
