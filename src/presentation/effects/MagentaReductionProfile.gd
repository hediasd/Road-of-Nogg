## Shared calibration constants for the data-selected magenta implosion effect.
##
## Why this is a third forked profile rather than the shared `SpellVfxProfile`
## resource that `docs/VFX_DESIGN.md` §4 schedules for the third elemental
## effect: the trigger counted files, but the shape the first two share is the
## shape of a *storm* — an outward, upward particle field under a crown, on one
## continuous arc from onset to settle. This effect is the opposite motion. It
## pulls inward, runs a four-beat timeline whose third beat deliberately holds
## before anything is released, and it carries a core and a discharge layer that
## neither storm has while dropping the crown that both do. Abstracting a
## resource from three files where the third barely fits would have fixed the
## wrong shape for every effect after it. Declined with the user 2026-08-08 and
## recorded in `BACKLOG_LONGTERM.md`, with the trigger restated as the next
## effect that is structurally a storm.
##
## Provenance, following `FireStormProfile`: no reference footage was
## decomposed for this effect either, so only two labels appear.
##
##   DERIVED  — carried over from `FireStormProfile` or `IceStormProfile`,
##              unchanged or rescaled, inheriting that constant's provenance.
##   AUTHORED — chosen by eye for this effect. No external source is claimed.
##
## Do not upgrade an AUTHORED label to MEASURED without recording the evidence.
##
## Every value here is forwarded to `magenta_implosion.gdshader` as a uniform or
## consumed by `MagentaReductionEffect`; nothing about the look is a literal in
## either file. That is §4's standing rule, and the test it sets is whether a
## later session can retune this effect by editing this file alone.

class_name MagentaReductionProfile

## AUTHORED presentation metadata only; matches the catalog registration.
const PROFILE_ID := "magenta_reduction"

# ---------------------------------------------------------------------------
# Timeline
# ---------------------------------------------------------------------------

## AUTHORED, and deliberately longer than the 4.5 s both storms share. That
## shared figure existed so the two would scrub on one harness timeline, which
## is worth less here than the charge beat is: the wind-up is this effect's
## identity, and at 4.5 s the hold reads as a hesitation rather than as a
## deliberate gathering. `CHARGE_END_FRACTION - SPIRAL_END_FRACTION` of this is
## the beat's real duration — currently about 2.2 s.
const REFERENCE_DURATION_SECONDS := 5.6
## AUTHORED a full second past the fire storm's 2.4 s, for the same reason. An
## implosion that releases before the player has registered it gathering is just
## a flash.
const BATTLE_DURATION_SECONDS := 3.4
## DERIVED unchanged from both storms' queue-pacing decision.
const ACTION_HOLD_FRACTION := 0.45
## AUTHORED past the discharge rather than at the storms' 0.82: skipping an
## action here must not cut the release, which is the whole payoff.
const SETTLE_START_FRACTION := 0.90
## AUTHORED faster than the fire storm's 0.10. Motes are sparse and arrive on
## the boundary a few at a time anyway, so a long global fade-in only makes the
## gather beat look empty for longer.
const ONSET_FRACTION := 0.06

# ---------------------------------------------------------------------------
# Beat boundaries
#
# The four beats as normalized fractions of the timeline, so the charge beat can
# be lengthened or shortened without touching any motion code. Each boundary is
# where the previous beat ends: gather 0 -> GATHER_END, spiral GATHER_END ->
# SPIRAL_END, charge SPIRAL_END -> CHARGE_END, discharge CHARGE_END -> 1.
# ---------------------------------------------------------------------------

## AUTHORED short. The gather only has to establish that something is appearing
## on the boundary and that the centre is empty.
const GATHER_END_FRACTION := 0.18
## AUTHORED. The spiral is the travel beat and needs long enough for the
## acceleration to be visible as acceleration rather than as a jump.
const SPIRAL_END_FRACTION := 0.44
## AUTHORED to give the charge the largest single share of the timeline. This is
## the beat the effect is *for*; shortening it is the first thing that will be
## tempting and the first thing that will kill the look.
const CHARGE_END_FRACTION := 0.84
## AUTHORED: the discharge gets the remaining 0.16, which is the point. A lance
## that lingers is not a lance.

# ---------------------------------------------------------------------------
# Footprint
# ---------------------------------------------------------------------------

## AUTHORED from the carrier, `Magenta Reduction` (radius 3). A default for
## previews only — the real radius arrives via `setFootprint()`.
const REFERENCE_CARRIER_RADIUS_TILES := 3

## AUTHORED radius the particle field swirls on, as a fraction of the
## footprint's world half-extent.
##
## **This effect swirls on a circle, not on the Manhattan diamond the spell
## actually hits, and that is a deliberate exception** requested 2026-08-09
## after seeing the diamond-traced version: the wound-up field reads better as a
## ring than as a rotating quad shape, and the difference from the true
## footprint was judged not to matter.
##
## What that costs, stated plainly because `docs/VFX_DESIGN.md` §4 calls an
## over-claiming effect a real defect: at 0.707 the circle is inscribed in the
## diamond and claims strictly less than the spell hits, which is the safe
## direction. Above that it starts crossing the diamond's edges near the
## diagonals — at this value the field reaches about a quarter-tile past them
## while staying well inside the diamond's vertices. The **ground wash still
## draws the true diamond underneath**, so the authoritative read on the
## footprint is unchanged and only the particles are stylized. Drop this to
## SQRT1_2 (0.7071) to make the field strictly conservative again.
const FIELD_CIRCLE_RADIUS_FRACTION := 0.88
## DERIVED: the inscribed circle, used for `cross` and `line` carriers, whose
## real footprints are much smaller than a diamond of the same radius. Those
## keep the conservative radius rather than the stylized one — the exception
## above was granted for the diamond case that the carrier actually uses.
const FIELD_CIRCLE_CONSERVATIVE_FRACTION := 0.70710678
## AUTHORED. This field is near-planar rather than a column: motes hover just
## off the ground and sink as they converge, so the silhouette stays legible
## against tiles rather than climbing out of the camera's framing the way the
## fire column does.
##
## Expressed as a fraction of the footprint's world half-extent rather than in
## world units. The first build used absolute 0.14–0.86 u, tuned at the
## carrier's radius 3, and the radius-1 sweep caught exactly the failure §4
## predicts for a constant offset: at radius 1 the footprint only reaches 1.5 u,
## so a mote hovering 0.86 u up projected clear of the tile and the gather read
## as a cloud floating beside the target rather than a ring on it. The XZ clamp
## was never violated — this was the height alone.
const MOTE_HEIGHT_MIN_FRACTION := 0.04
## AUTHORED ceiling for the hovering band, as a fraction of the footprint's
## world half-extent. Reproduces the tuned 0.86 u at the carrier's radius 3.
const MOTE_HEIGHT_MAX_FRACTION := 0.25
## AUTHORED fraction of its starting height a mote retains at full convergence.
## Below 1.0 the field visibly sinks into the core as it winds in, which is what
## sells the pull as a pull rather than as a shrink.
const MOTE_SINK_FRACTION := 0.35
## AUTHORED floor for the visibility AABB's height, covering the core halo at
## small radii where the mote band alone would not. Culling only, not a look
## value — `MagentaReductionEffect._footprintAabb()` takes the larger of this and
## the band's own ceiling, so a large radius cannot outgrow it.
const FIELD_HEIGHT_U := 1.6

# ---------------------------------------------------------------------------
# Spiral
#
# Three separate values, deliberately not collapsed. SPIRAL_TURNS is how far a
# mote sweeps in total, INWARD_ACCEL_EXPONENT is how its radius falls over time,
# and WINDUP_EXPONENT is how its angular rate rises as that radius falls. They
# are independent because the wind-up is the relationship *between* the last two
# — folding them into one "spiral speed" produces a field that rotates rigidly
# while it shrinks, which is the same failure the fire storm's SWIRL_BASE /
# SWIRL_CROWN pair exists to avoid.
# ---------------------------------------------------------------------------

## AUTHORED angular speed during the gather, in radians per second. Slow: the
## motes are meant to be drifting, not yet being pulled.
const SWIRL_GATHER_RATE := 0.9
## AUTHORED angular speed the field reaches and holds through the charge, in
## radians per second.
const SWIRL_CHARGE_RATE := 5.2
## AUTHORED normalized time the acceleration between those two rates begins.
## AUTHORED normalized time it completes. The gap between the two *is* the
## smoothness of the wind-up: widen it and the field accelerates more gradually,
## narrow it and the speed-up becomes a lurch.
##
## The shader ramps angular velocity smoothstep-wise across this window and
## takes that ramp's exact integral for the swept angle, so speed is continuous
## everywhere. The earlier version accumulated angle from the *radius* and added
## a separate constant charge-beat spin on top, which left a step in angular
## velocity right at the beat boundary — the field visibly lurched as the spiral
## beat handed over. Coupling the rate to time rather than radius costs nothing
## visually, because the window is aligned to the radius fall anyway.
const WINDUP_START_FRACTION := 0.14
const WINDUP_END_FRACTION := 0.58
## AUTHORED radius-versus-time curve for the spiral beat. Above 1.0 the mote
## leaves the boundary slowly and accelerates as it closes; at 1.0 it travels at
## a constant rate and the beat reads as mechanical. Independent of the angular
## wind-up above, which is what keeps the spiral a spiral rather than a
## shrinking rigid rotation.
const INWARD_ACCEL_EXPONENT := 2.2
## AUTHORED. How far in a mote drifts during the gather beat, as a fraction of
## its spawn radius. Small on purpose: "drifting barely inward".
const GATHER_DRIFT_FRACTION := 0.07
## AUTHORED radius a mote reaches at the end of the spiral beat, as a fraction
## of its spawn radius.
##
## Retuned up from 0.20 after the first charge-beat capture. At 0.20 the field
## closed to roughly 0.7 u at the carrier's radius 3 and the entire charge beat
## rendered as a single clipped white dot — not a spiral being held under
## tension, just a point. The charge beat has to stay a *legible swirl*, so this
## is set from the area 44 motes need in order to still read as 44 motes, the
## same volume-first reasoning §4 records for the fire column's count.
const CHARGE_RADIUS_FRACTION := 0.42
## AUTHORED radius at the end of the charge beat. The gap to
## CHARGE_RADIUS_FRACTION is the compression the charge beat performs; setting
## the two equal makes the charge a pure hold. Raised alongside it, keeping the
## same ratio, so the compression is still visible without closing to a point.
const CHARGE_COMPRESS_FRACTION := 0.26

# ---------------------------------------------------------------------------
# Mote spawn band
# ---------------------------------------------------------------------------

## AUTHORED inner edge of the spawn band, as a fraction of the diamond limit at
## each mote's angle. Motes spawn between this and the boundary itself, so the
## gather reads as an outline rather than as a filled disc. Lowering it thickens
## the band; at 1.0 every mote starts exactly on the edge, which reads as a
## drawn ring rather than as motes appearing.
const MOTE_BAND_INNER_FRACTION := 0.85
## AUTHORED per-mote stagger in the fade-in, as a fraction of the timeline. This
## is why motes appear "a few at a time" during the gather rather than all at
## once. It offsets appearance only — every mote runs the same beat boundaries,
## so the spiral and the charge stay crisp.
const MOTE_PHASE_SPREAD := 0.20

# ---------------------------------------------------------------------------
# Motes: count, alpha, size
#
# Retuned from this geometry before anything else was built on top, per §4.
# ---------------------------------------------------------------------------

## AUTHORED, and well under the fire storm's 104 across its two layers. This
## geometry funnels every particle into the centre by the charge beat, which is
## a far smaller volume than even the fire column's — the count has to be set
## from the *tightest* moment of the effect, not from the widest. The gather
## beat looks sparse at this number and is supposed to. Readability constraint,
## not a performance one: do not raise it toward MAX_LIVE_PARTICLES.
## Raised from 44 alongside the twinkle: at a deep twinkle a mote spends most of
## its cycle dim, so the count that read correctly as a steady field leaves
## visible holes in a glittering one. The *peak* density is what saturates and
## it has not changed much — the extra motes are dark at any given instant.
##
## Raised again to 84 when the motes became hard dots. A dot puts far less area
## on screen than the star sprite it replaced, so the field could carry more of
## them before the charge beat saturates, and it needed to: the whole point of
## the change was a field you can count.
const MOTE_PARTICLE_AMOUNT := 84
## AUTHORED, and well under the fire storm's 0.34 for the same reason. These
## layers blend additively and the charge beat stacks the entire field into a
## few tiles, so the core clips to white far sooner than a column does. Lower
## this before touching the colours, which carry only hue.
##
## Retuned down from 0.20 against the same capture that moved
## CHARGE_RADIUS_FRACTION: widening the charge ring removed most of the
## overlap, but the convergence still stacks every mote in the frame into one
## small area, and at 0.20 the centre was white rather than fuchsia through the
## whole back half of the timeline. The palette is the thing being protected
## here — a magenta spell that renders white is not a recoverable look.
##
## Raised from 0.13 to 0.22 with the switch to hard dots. That earlier ceiling
## was set by the soft sprite's wide overlapping halo; a two-level dot with a
## hard edge covers a fraction of the area, so the same visual density costs far
## less additive stacking and the motes can afford to be genuinely bright.
const MOTE_ALPHA := 0.17
## AUTHORED floor. Motes are specks that resolve individually — the gather beat
## fails if they read as a haze.
## Small: these are dots, and a dot that grows stops being one. Reduced from
## 0.05/0.13 when the sprite changed — a hard-edged sprite reads as larger than
## a soft one of the same nominal size, because its edge is where you think it is.
## Reduced again to 0.026/0.052 after the first pixel capture: `pixelDot()` is
## opaque across most of its 8x8 grid, unlike the radial flake whose bright part
## was only the middle, so the *drawn* size jumped even though the number had
## not. At the earlier figures neighbouring motes merged into a solid magenta
## mass — the opposite of a field you can count.
const MOTE_MIN_SIZE_U := 0.026
## AUTHORED ceiling, kept modest so the compressed core stays a core rather
## than a cluster of visible sprites.
const MOTE_MAX_SIZE_U := 0.052
## AUTHORED. A mote shrinks slightly as it converges, so the compressing field
## loses area faster than its radius alone would suggest and the core stays
## readable underneath it.
const MOTE_SHRINK := 0.72
## AUTHORED. How far into the discharge beat the motes take to disappear, as a
## fraction of that beat. "All remaining motes dissipate with it" — they go with
## the release rather than outlasting it, but not so fast that the field appears
## to be switched off one frame before the lance leaves.
## Shortened from 0.55 for the same reason as CORE_FLASH_DECAY_FRACTION: motes
## lingering at the centre while the lances travel is extra mass exactly where
## the frame needs to be clearing.
const MOTE_DISSIPATE_FRACTION := 0.35

# ---------------------------------------------------------------------------
# Twinkle
#
# What turns the field from a grade of identical specks into brights and dots.
# Two independent ideas: every mote pulses on its own rate and phase, and a
# minority of them are simply bigger and brighter than the rest.
# ---------------------------------------------------------------------------

## AUTHORED slowest and fastest per-mote pulse, in radians per second. The
## spread matters more than either value — motes sharing a rate beat visibly in
## and out of sync with each other and read as one flashing object.
const TWINKLE_RATE_MIN := 3.5
const TWINKLE_RATE_MAX := 9.0
## AUTHORED. Exponent on the 0..1 sine driving each pulse. This is what makes it
## a *twinkle*: at 1.0 the mote throbs evenly, and raising it spends most of the
## cycle dim with a brief spike, which is what a glint looks like.
const TWINKLE_SHARPNESS := 4.0
## AUTHORED depth of the brightness pulse, 0 for none and 1 for full extinction
## between spikes.
## Reduced from 0.75: at that depth a mote was invisible for most of its cycle,
## which is why the field was hard to see at all. Still a twinkle, but one that
## dips rather than extinguishes.
const TWINKLE_DEPTH := 0.45
## AUTHORED how much of the pulse also drives size. Small: a mote that changes
## size as much as it changes brightness reads as approaching, not glinting.
const TWINKLE_SIZE_DEPTH := 0.35
## AUTHORED share of motes that are brights rather than dots.
const MOTE_BRIGHT_FRACTION := 0.22
## AUTHORED size and opacity multipliers for that minority.
const MOTE_BRIGHT_SIZE_SCALE := 1.6
const MOTE_BRIGHT_ALPHA_SCALE := 1.7

# ---------------------------------------------------------------------------
# Core
# ---------------------------------------------------------------------------

## AUTHORED, and deliberately **not** a function of the footprint. The core is
## the thing the player reads the charge off, and it has to stay the same
## readable size whether the spell covers one tile or a wide field. §4 asks for
## exactly this decision to be stated rather than left as a silent literal.
const CORE_BASE_SIZE_U := 0.40
## AUTHORED mild footprint-proportional term on top of the fixed size, so a
## radius-5 cast does not read as the radius-1 core sitting in an empty field.
## Kept small; the fixed term dominates by design.
const CORE_FOOTPRINT_SIZE_FRACTION := 0.09
## AUTHORED outer halo as a multiple of the core quad. Two quads rather than
## the fire storm's crown pair — same node cost, different job.
const CORE_HALO_SCALE := 2.3
## AUTHORED quad count: the core proper plus one halo.
const CORE_QUAD_COUNT := 2
## AUTHORED height off the ground, as a fraction of the footprint's world
## half-extent, inside the mote band so the field converges onto the core rather
## than through it. Unlike CORE_BASE_SIZE_U this one *does* scale: the core's
## size has to stay readable at every radius, but a core still floating at a
## radius-3 height above a radius-1 tile detaches from the footprint.
const CORE_HEIGHT_FRACTION := 0.12
## AUTHORED brightness at the end of the gather beat. Zero: the centre is empty,
## which is what makes the gather read as a gather.
const CORE_GATHER_BRIGHTNESS := 0.0
## AUTHORED brightness reached by the end of the charge beat.
const CORE_CHARGE_BRIGHTNESS := 0.80
## AUTHORED peak at the release. Above 1.0 on purpose — this is the blow-out
## toward white that the reference language calls for, and the only moment the
## effect is allowed to clip.
const CORE_DISCHARGE_BRIGHTNESS := 1.55
## AUTHORED curve shape for the charge ramp. Above 1.0 holds the core dim for
## most of the beat and brightens late, so the release feels earned rather than
## telegraphed from the start.
const CORE_BRIGHTNESS_EXPONENT := 2.4
## AUTHORED fuchsia the core carries while it is charging. RGB drives both
## albedo and emission; alpha is the layer's peak opacity.
const CORE_COLOR := Color(1.0, 0.30, 0.90, 0.55)
## AUTHORED yellow-white the core blows out to at the release. Reached only at
## the discharge, which is what keeps the palette reading as magenta.
const CORE_HOT_COLOR := Color(1.0, 0.96, 0.86, 0.75)
## AUTHORED. How far before the release the core starts shifting from fuchsia
## toward the hot colour, as a fraction of the timeline. Non-zero so the blow-out
## is anticipated by a frame or two rather than switching on the same instant the
## lances leave.
const CORE_HOT_ONSET_FRACTION := 0.10
## AUTHORED. How far into the discharge beat the core reaches
## CORE_DISCHARGE_BRIGHTNESS, as a fraction of that beat. Short: the flash is the
## release, and a slow rise reads as a swell.
const CORE_FLASH_RISE_FRACTION := 0.12
## AUTHORED. How far into the discharge beat the core has decayed to nothing, as
## a fraction of that beat. Shortened from 0.85: the core was still at roughly
## three quarters brightness while the lances were crossing the footprint, so
## the release read as one bright mass at the centre rather than as something
## leaving it. The core's job ends when the discharge starts travelling.
const CORE_FLASH_DECAY_FRACTION := 0.55

# ---------------------------------------------------------------------------
# Discharge
# ---------------------------------------------------------------------------

## AUTHORED lance count. Raised from 8 as part of making the release less
## diagrammatic: with the curl and the per-lance variance below, more lances
## read as a burst rather than as a denser wheel. Still nowhere near filling the
## field, which is what would turn it into the dome the look rules out.
const DISCHARGE_LANCE_COUNT := 14
## AUTHORED per-lance length variation, as the fraction by which the shortest
## lance falls short of the longest. Identical lengths are the other half of
## what made the first version read as a diagram.
const DISCHARGE_LENGTH_VARIANCE := 0.45
## AUTHORED per-lance opacity variation, on the same principle.
const DISCHARGE_ALPHA_VARIANCE := 0.40
## AUTHORED per-lance height scatter, as a fraction of the footprint's world
## half-extent, so the lances do not all lie in one perfectly flat plane.
const DISCHARGE_HEIGHT_VARIANCE := 0.05

# ---------------------------------------------------------------------------
# Bolt path
#
# Each bolt is a chain of segment quads rather than one stretched lance, which
# is what lets it be jagged. The shader walks the chain from INDEX alone, so
# segment N always begins exactly where N-1 ended with no shared state.
# ---------------------------------------------------------------------------

## AUTHORED segments per bolt. The shader's accumulation loop is bounded at 8 at
## compile time, so this must not exceed that. More segments buy a finer jag and
## cost a particle per bolt each.
const BOLT_SEGMENTS := 5
## AUTHORED probability that a joint turns at all, rather than continuing
## straight. Each turn is exactly one BOLT_ANGLE_STEPS notch, never more.
##
## Turning in whole notches replaced an earlier continuous-kink-then-snap scheme
## that quietly cancelled itself: kinks of about 31 degrees against a
## 22.5-degree half-step rounded back to the original heading roughly seven times
## in ten, and the bolts rendered as straight rays with the jag apparently
## missing. Choosing the turn already in the quantized domain is what makes every
## intended bend survive.
##
## At 0 the chain is a straight lance again; at 1 every joint turns and the bolt
## folds back on itself instead of travelling outward.
const BOLT_TURN_CHANCE := 0.65
## AUTHORED strength of the pull back toward a bolt's launch heading, per notch
## of accumulated drift.
##
## Without it the chain is an unbiased random walk, and a random walk does not
## preserve a direction: the bolts curled around and folded back instead of
## radiating, bunching the whole burst to one side of the core. This is what
## makes a bolt jag hard and still arrive somewhere — the roll supplies the jag,
## this supplies the heading. At 0 they wander; at 1 a single notch of drift is
## corrected immediately and the jag flattens into a straight line with jitter.
const BOLT_STRAIGHTEN := 0.55
## AUTHORED multiplier on a bolt's total path length.
##
## A jagged path covers far less *radial* distance than its own arc length,
## because every kink spends some of it sideways. At 1.0 the bolts visibly fell
## short — reaching roughly half the field radius while nominally being as long
## as it — so this buys that back. It is a function of BOLT_JAG: raise the jag
## and this has to rise with it, or the bolts retreat toward the core again.
## Raised again from 1.45 to 1.9 to push the bolts further out; at this value
## their tips run past the mote ring rather than stopping short of it, which is
## what makes the release read as escaping the field rather than filling it.
const BOLT_LENGTH_OVERSHOOT := 1.9
## AUTHORED exponent biasing where a bolt turns from the hot colour to the cool
## one along its chain. Below 1.0 the yellow-white is confined to the first
## segment or two and the rest of the bolt is fuchsia, which is what keeps the
## release reading as magenta; at 1.0 the gradient is even and, because most of
## a bolt's mass sits near the core where the segments converge, the whole
## discharge washed out to white.
const BOLT_COLOR_BIAS := 0.45
## AUTHORED width at the tip as a fraction of the width at the base, so a bolt
## thins as it strikes out rather than reading as uniform rope.
const BOLT_TIP_WIDTH_FRACTION := 0.35
## AUTHORED strobe rate in radians per second, its sharpening exponent, and its
## depth. Lightning does not fade evenly — it stutters — and this is most of
## what separates it from a drawn ray. Depth is deliberately partial: at 1.0 the
## bolts blink fully out and the release reads as dropped frames.
const BOLT_STROBE_RATE := 26.0
const BOLT_STROBE_SHARPNESS := 2.2
## Reduced from 0.45: a deeper strobe cost more visibility than it bought
## character, and the bolts had to be noticeable first.
const BOLT_STROBE_DEPTH := 0.30
## AUTHORED number of forked child bolts, each branching off a randomly chosen
## parent partway along it. After the jag itself this is the strongest "that is
## lightning" cue; set it to 0 and the release is still jagged, just plainer.
const BOLT_FORK_COUNT := 6
## AUTHORED fork length as a fraction of a parent's, and its width as a fraction
## of the parent's width. A fork that matches its parent reads as a second bolt
## rather than as a branch.
const BOLT_FORK_LENGTH_FRACTION := 0.45
const BOLT_FORK_WIDTH_FRACTION := 0.65
## AUTHORED angle a fork leaves its parent at, in radians. Applied to whichever
## side a per-fork hash picks, so branches do not all lean the same way.
const BOLT_FORK_DEVIATION := 0.8
## DERIVED total bolts and the emitter amount they need. Asserted at build time
## in `MagentaReductionEffect._buildLayers()`, because the shader splits INDEX
## into a bolt and a segment and a mismatch would leave a partial chain dangling.
const BOLT_TOTAL_COUNT := DISCHARGE_LANCE_COUNT + BOLT_FORK_COUNT
const DISCHARGE_PARTICLE_AMOUNT := BOLT_TOTAL_COUNT * BOLT_SEGMENTS

# ---------------------------------------------------------------------------
# Sparks
#
# Star glints thrown across the field as the bolts strike. Scattered rather
# than attached to a bolt, so they read as the air lighting up.
# ---------------------------------------------------------------------------

## AUTHORED spark count.
const SPARK_PARTICLE_AMOUNT := 32
## AUTHORED how far a spark strays from the bolt path it was born on, as a
## fraction of the footprint's world half-extent.
##
## Sparks are placed *along the bolts* rather than scattered over the field, and
## are born at the moment their bolt's tip reaches them, so what is left behind
## is a trail of glints marking where the lightning went. This value only breaks
## them off the exact centreline — at 0 they read as beads threaded on a wire.
const SPARK_SCATTER := 0.06
## AUTHORED spark size range, as fractions of the footprint's world half-extent.
## The spread is what produces the mix of large stars and small dots.
## Raised back to 0.10/0.28 after the pixel capture. A four-point star needs
## enough screen area for its spikes to survive: below roughly ten pixels the
## posterized spikes fall under a texel and the sprite collapses to a plain
## square, which is the mote's job, not the spark's. Sparks are the layer that
## has to read *as stars*.
const SPARK_MIN_SIZE_FRACTION := 0.10
const SPARK_MAX_SIZE_FRACTION := 0.28
## AUTHORED peak spark opacity. Lower than it wants to be, and the first value
## to drop further if the release saturates: sparks land on exactly the frames
## where the core is already blowing out.
const SPARK_ALPHA := 0.50
## AUTHORED how much of the discharge beat sparks keep appearing over, as a
## fraction of it. Non-zero so they arrive in a scatter rather than all at once.
const SPARK_SPAWN_WINDOW := 0.50
## AUTHORED how long a spark lives, as a fraction of the discharge beat.
const SPARK_LIFE_FRACTION := 0.55
## AUTHORED spark height band, as fractions of the footprint's world half-extent.
const SPARK_HEIGHT_MIN_FRACTION := 0.02
const SPARK_HEIGHT_MAX_FRACTION := 0.22
## AUTHORED, and white on purpose.
##
## Unlike every other palette value here, the sparks' colour is **not** owned by
## the shader — `VfxTextures.sparkleFrames()` is hand-drawn art carrying its own
## four-tone shading (white core, warm mid, cool rim), and that shading is the
## reason to use drawn art instead of a generated mask. This multiplies it, so
## white leaves the strip exactly as authored. It exists so a later session can
## push the sparkles toward another hue without repainting the source.
const SPARK_TINT := Color(1.0, 1.0, 1.0, 1.0)
## DERIVED: one particle per lance. Each lance is a single quad carrying
## `VfxTextures.lanceStreak()`, which has a direction of its own.
##
## Three earlier builds, and the history is worth keeping straight because the
## first diagnosis was wrong.
##
##   1. A single quad stretching `VfxTextures.neutralSoftDisc()`. Rendered nothing.
##   2. A trail of five square billboarded sprites. Visible, but read as a row
##      of soft puffs — a sprite large enough to see is about as large as the
##      gap between sprites, so the trail closes into a sausage.
##   3. A single quad with the new streak texture. Rendered nothing *again*.
##
## Build 3 is what identified the real fault: the oriented basis was
## left-handed, so every lance was backface-culled from above. That was present
## in build 1 too and is sufficient on its own to explain it — the radial
## texture was never the proven cause, only assumed to be. Build 2 worked
## because billboarding replaces the basis entirely and hid the bug.
##
## The radial texture is still unsuitable, by inspection rather than by
## experiment: a radial gradient's alpha falls to zero at both ends of a
## stretched quad, so it can only ever produce a soft blob in the middle of a
## lance. Both faults were real; only one of them was the reason for the blank
## frame.
##
## The single-quad lance was itself superseded on 2026-08-09 by the segmented
## bolt chain below, which needs several particles per bolt — see
## DISCHARGE_PARTICLE_AMOUNT under "Bolt path". `lanceStreak()` is no longer
## used by this effect but stays in `VfxTextures` as a general-purpose sprite.
## AUTHORED peak opacity, above the motes' because the discharge is brief and
## has to land in a fraction of a second. Raised from 0.52 with the move to
## bolts: the strobe spends part of every cycle dim, and a chain of thin
## segments puts far less area on screen than the solid lances did.
## Raised again to 0.85 alongside thinning the bolts: brightness is what buys
## back the presence that width gave up, and a thin bright filament reads as
## more electric than a wide dim one.
const DISCHARGE_ALPHA := 0.85
## AUTHORED lance length along its travel direction, as a fraction of the
## footprint's world half-extent. Reproduces the tuned 1.05 u at the carrier's
## radius 3.
##
## Proportional rather than absolute, and for the same reason the heights are:
## the first pass authored 1.05 u flat, and at radius 1 that is 70% of the whole
## footprint, so the rosette swamped the tile it was supposed to be leaving. The
## tips still land exactly on the boundary either way — the reach subtracts the
## half-length — but landing on the boundary having barely travelled is not the
## same effect.
const DISCHARGE_LENGTH_FRACTION := 0.30
## AUTHORED bolt thickness in world units, and deliberately **not** a fraction
## of the footprint — the one dimension here that must not scale.
##
## A sharp line is defined in *pixels*, not in world units: the whole point is
## that it lands on a small whole number of them. Scaling thickness with the
## footprint made a radius-5 bolt three times heavier than a radius-1 one, so
## only one radius could ever be the crisp one. At the debug harness's
## representative camera size this is a little under four pixels, of which
## `_BOLT_CORE_FRACTION` draws about 80%.
##
## The caveat worth knowing: the shipping camera size varies with board size, so
## "four pixels" holds for a given board rather than universally. A constant
## world width is still much closer to constant screen width than a footprint
## fraction was.
const DISCHARGE_WIDTH_U := 0.075
## AUTHORED number of directions a bolt segment may point, spread evenly around
## the circle. Eight gives the axis-aligned and 45-degree runs that hand-drawn
## pixel lightning is made of.
##
## This is the single change that makes the discharge read as *drawn* rather
## than rendered, and it only works because the bolts are built in the camera's
## plane: quantizing in world space and then projecting through an isometric
## camera lands the segments back off the pixel grid at uneven angles. Raise it
## for a smoother, less deliberately pixelated bolt; 16 still reads as drawn,
## 32 does not.
const BOLT_ANGLE_STEPS := 8
## AUTHORED travel-rate multiplier over the discharge beat. Above 1.0 the streak
## reaches the boundary before the timeline ends and the tail has room to fade,
## which is what makes it read as fast. Raised from 1.35 so the lances clear the
## core's own flash instead of being read against it.
const DISCHARGE_SPEED := 1.8
## AUTHORED angular jitter in radians, breaking the even radial spacing so the
## release reads as a burst rather than as a drawn wheel.
const DISCHARGE_ANGULAR_JITTER := 0.16
## AUTHORED per-streak stagger as a fraction of the discharge beat, so the
## lances do not all leave the core on the same frame.
const DISCHARGE_STAGGER_FRACTION := 0.12
## AUTHORED height off the ground, as a fraction of the footprint's world
## half-extent. Scaled rather than absolute for the same reason as
## MOTE_HEIGHT_MIN_FRACTION.
##
## Raised from 0.06 — the original "skims the floor" reading was wrong for a
## board with elevation. The lances are flat quads with depth *writing* off but
## depth *testing* still on, so at 0.21 u the ones crossing a raised tile were
## inside it and vanished: at the carrier's radius only three of eight ever
## reached the screen, and which three depended on the terrain rather than on
## the effect. This clears the board's elevation steps while staying under the
## mote band, so the release still reads as leaving the ground.
const DISCHARGE_HEIGHT_FRACTION := 0.17
## AUTHORED yellow-white at the core end of the streak's travel. RGB only; the
## alpha component is ignored in favour of DISCHARGE_ALPHA.
const DISCHARGE_CORE_COLOR := Color(1.0, 0.97, 0.84, 1.0)
## AUTHORED fuchsia the streak cools to as it reaches the boundary. RGB only;
## see DISCHARGE_ALPHA.
const DISCHARGE_EDGE_COLOR := Color(1.0, 0.22, 0.86, 1.0)

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------

## AUTHORED deep fuchsia a mote carries out on the boundary. RGB only; the alpha
## component of this and MOTE_INNER_COLOR is ignored in favour of MOTE_ALPHA.
##
## The carrier's elements are water and fire, and this palette deliberately does
## not depict either. Splitting the field into a blue half and an orange half
## would read as two spells overlapping; the spell is named for the colour its
## reaction produces, so magenta is the whole palette and yellow-white appears
## only at the core and in the discharge.
const MOTE_OUTER_COLOR := Color(0.82, 0.14, 0.70, 1.0)
## AUTHORED brighter fuchsia a mote reaches at full convergence. RGB only; see
## MOTE_OUTER_COLOR.
const MOTE_INNER_COLOR := Color(1.0, 0.44, 0.95, 1.0)
## AUTHORED floor response, near the fire storm's 0.13. The wash marks the
## footprint the motes spawn on; any stronger and the sparse gather beat is
## competing with its own ground decal.
const GROUND_WASH_COLOR := Color(0.78, 0.16, 0.72, 0.12)
## AUTHORED. The wash brightens with the core through the charge and flares at
## the release, so the floor participates in the discharge instead of sitting
## flat under it.
const GROUND_WASH_FLARE_MULTIPLIER := 1.9
## AUTHORED normalized time the wash begins fading out. After the discharge has
## left the core, so the footprint is still marked while the lances cross it.
const WASH_FADE_START_FRACTION := 0.90
## AUTHORED normalized time the wash has fully faded.
const WASH_FADE_END_FRACTION := 1.0

# ---------------------------------------------------------------------------
# Budgets, asserted at build time in `MagentaReductionEffect._buildLayers()`
# ---------------------------------------------------------------------------

## DERIVED unchanged from both storms. Note how far under it this effect sits
## (68 of 220) — see MOTE_PARTICLE_AMOUNT for why that headroom is not spare
## capacity.
const MAX_LIVE_PARTICLES := 220
## DERIVED unchanged from both storms.
const MAX_LIVE_IMPLOSIONS := 2
## DERIVED unchanged from both storms.
const MAX_DRAW_CALLS := 14
## DERIVED unchanged from both storms.
const MAX_EFFECT_NODES := 12
