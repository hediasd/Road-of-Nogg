## Shared calibration constants for the data-selected fire-area storm effect.
##
## Provenance rule: unlike `IceStormProfile`, nothing here is measured against
## reference footage. This profile was derived from the ice storm's structure
## and then authored by eye, which is a deliberate scope decision recorded in
## the plan that created it — a recolour-and-remotion of a proven effect did
## not justify a second footage-decomposition pass. Constants therefore carry
## only two labels:
##
##   DERIVED  — carried over from `IceStormProfile`, unchanged or rescaled,
##              inheriting whatever provenance that constant already had.
##   AUTHORED — chosen by eye for this effect. No external source is claimed.
##
## Do not upgrade an AUTHORED label to MEASURED without actually recording the
## evidence; the ice profile's labels mean something and these must not dilute
## them.

class_name FireStormProfile

## AUTHORED presentation metadata only; matches the catalog registration.
const PROFILE_ID := "fire_area_storm"

## DERIVED from the ice storm's reference-mode span, kept identical so both
## effects scrub on the same timeline in the debug harness.
const REFERENCE_DURATION_SECONDS := 4.5
## AUTHORED slightly longer than the ice storm's 2.2 s: a column has to be seen
## to *climb*, and the extra beat is what lets the ascent read before the
## settle begins.
const BATTLE_DURATION_SECONDS := 2.4
## AUTHORED slow breath rather than the ice storm's sharp pulse — fire swells,
## it does not tick.
const REFERENCE_PULSE_INTERVAL_SECONDS := 0.62
## AUTHORED to match the reference interval; fire's breath does not compress
## with the shorter battle timeline the way the ice storm's beat did.
const BATTLE_PULSE_INTERVAL_SECONDS := 0.62
## AUTHORED wider and softer than the ice storm's 0.18 accent window, so the
## brightness swell reads as breathing rather than as a strobe.
const PULSE_ACCENT_FRACTION := 0.35
## AUTHORED restrained swell; the embers already carry the visual energy.
const PULSE_BRIGHTNESS_MULTIPLIER := 1.18
## AUTHORED marginally later than the ice storm's 0.08: the column needs a
## moment of ground glow before embers appear, or it reads as popping in.
const ONSET_FRACTION := 0.10
## DERIVED unchanged from the ice storm.
const SETTLE_START_FRACTION := 0.82
## DERIVED unchanged from the ice storm's queue-pacing decision.
const ACTION_HOLD_FRACTION := 0.45

## AUTHORED from the only fire area carrier, `Smoke Tower` (radius 1). This is
## a default for previews only — the real radius arrives via `setFootprint()`.
const REFERENCE_CARRIER_RADIUS_TILES := 1
## AUTHORED a little shorter than the ice storm's 3.8 u volume: a narrow column
## reads taller than a wide field at the same height, and the crown has to stay
## inside the battle camera's framing.
const COLUMN_HEIGHT_U := 3.4

## AUTHORED so the smoke sits just above the embers' visible die-off.
const CROWN_MIN_HEIGHT_U := 2.4
## AUTHORED to keep the crown under the column's full height.
const CROWN_MAX_HEIGHT_U := 3.2
## AUTHORED narrower than the ice canopy's full-footprint span: smoke off a
## column is tighter than a storm's cloud deck.
const CROWN_WIDTH_SCALE := 0.85
## AUTHORED two quads rather than the ice storm's three — a tighter plume needs
## less overlap, and it keeps the node budget clear for the second ember layer.
const CROWN_QUAD_COUNT := 2
## DERIVED from the ice canopy, widened slightly for a lazier smoke drift.
const CROWN_DRIFT_DISTANCE_U := 0.28
## DERIVED from the ice canopy, deepened slightly so smoke breathes more than
## a rigid cloud.
const CROWN_SCALE_BREATH_FRACTION := 0.08

## AUTHORED inner column count. Deliberately well under the ice storm's 180
## despite the same budget: a column concentrates its particles into a fraction
## of the volume a flat storm field spreads them across, so matching ice's count
## produced a continuous haze in which no individual ember — and therefore no
## spiral — was legible. Density here is a readability constraint, not a
## performance one.
const EMBER_COLUMN_PARTICLE_AMOUNT := 80
## AUTHORED sparse outer layer of larger, slower embers, purely for depth —
## without it the column reads as one flat sheet of identical specks.
const EMBER_MOTE_PARTICLE_AMOUNT := 24
## AUTHORED near the ice flake floor; embers are specks, not sprites.
const EMBER_MIN_SIZE_U := 0.045
## AUTHORED just above the ice flake ceiling.
const EMBER_MAX_SIZE_U := 0.115
## AUTHORED roughly double the column embers so the depth layer reads as nearer.
const MOTE_MIN_SIZE_U := 0.09
## AUTHORED upper bound for the depth layer, still below unit-silhouette scale.
const MOTE_MAX_SIZE_U := 0.17

## AUTHORED so a fast ember crosses the column in a little over a second.
const EMBER_MIN_RISE_SPEED := 1.15
## AUTHORED upper bound; the spread is what stops the column pulsing in unison.
const EMBER_MAX_RISE_SPEED := 2.05
## AUTHORED slower than the column: large embers hanging longer reads as
## parallax against the fast inner core.
const MOTE_MIN_RISE_SPEED := 0.65
## AUTHORED upper bound for the depth layer.
const MOTE_MAX_RISE_SPEED := 1.10

## AUTHORED: embers fill most of the footprint at the base without touching
## its edge, which would read as a hard cut.
const BASE_RADIUS_FRACTION := 0.85
## AUTHORED tighter than the column so the depth layer sits inside it.
const MOTE_BASE_RADIUS_FRACTION := 0.62
## AUTHORED funnel strength: the crown is about a third of the base radius.
const CROWN_TAPER := 0.34
## AUTHORED angular speed at the floor, in radians per second.
const SWIRL_BASE := 2.30
## AUTHORED angular speed at the crown. The gap between this and SWIRL_BASE is
## what makes the spiral *wind*; collapsing them to one value turns the column
## into a rigid rotation and loses the effect's whole character.
const SWIRL_CROWN := 0.95
## AUTHORED global multiplier, exposed so the swirl can be tuned or disabled
## without touching the base/crown relationship.
const SWIRL_SPEED := 1.0
## AUTHORED: an ember ends at about a third of its starting size.
const EMBER_SHRINK := 0.35
## AUTHORED fast shimmer for the inner column.
const FLICKER_RATE := 11.0
## AUTHORED slower shimmer for the depth layer, so the two do not beat in sync.
const MOTE_FLICKER_RATE := 6.5
## AUTHORED flicker depth. Much above this and the column reads as noisy rather
## than alive.
const FLICKER_DEPTH := 0.28
## AUTHORED quadratic lean across the full height.
const LEAN_OFFSET := 0.16

## AUTHORED peak per-ember opacity, and the value to reach for first if the
## column saturates. These layers blend additively and a column concentrates
## its particles into a much smaller volume than the ice storm's field spreads
## them across, so many more overlap per pixel: at the ice flake's 0.62 the
## core clipped to flat white and the whole hot-to-cool gradient was invisible.
## Lower this rather than the colours below, which carry only hue.
const EMBER_ALPHA := 0.34
## AUTHORED near-white hot core at the column base. RGB only — the alpha
## component of this and the two below is ignored in favour of EMBER_ALPHA.
const EMBER_HOT_COLOR := Color(1.0, 0.94, 0.72, 1.0)
## AUTHORED mid-climb orange. RGB only; see EMBER_ALPHA.
const EMBER_MID_COLOR := Color(1.0, 0.55, 0.16, 1.0)
## AUTHORED cooled deep red at the crown. RGB only; see EMBER_ALPHA.
const EMBER_COOL_COLOR := Color(0.72, 0.16, 0.09, 1.0)
## AUTHORED warm-grey smoke core, kept dim so it never competes with the embers.
const SMOKE_CROWN_CORE_COLOR := Color(0.30, 0.24, 0.22, 0.34)
## AUTHORED darker, thinner smoke edge.
const SMOKE_CROWN_EDGE_COLOR := Color(0.16, 0.13, 0.13, 0.16)
## AUTHORED warm floor response. Kept below the ice storm's 0.18 despite
## firelight being the brighter idea: the column already spills its own glow
## onto the ground, and a stronger wash on top of that flattened the whole
## footprint into one orange sheet with the embers invisible against it.
const GROUND_WASH_COLOR := Color(1.0, 0.48, 0.20, 0.13)

## DERIVED unchanged from the ice storm. Enforced at build time in
## `FireStormEffect._buildLayers()` against the summed emitter amounts.
const MAX_LIVE_PARTICLES := 220
## DERIVED unchanged from the ice storm.
const MAX_LIVE_STORMS := 2
## DERIVED unchanged from the ice storm.
const MAX_DRAW_CALLS := 14
## DERIVED unchanged from the ice storm.
const MAX_EFFECT_NODES := 12
