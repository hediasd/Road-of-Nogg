## Calibration constants for the Solar Storm coronagraph panel.
##
## Forked from `AuroraVeilProfile` under docs/VFX_DESIGN.md §4's sibling test:
## same billboarded-quad carrier, same four-beat timeline, same pixel snap, wave,
## radius response, and depth-resolved model lighting. The field is what differs.
## See the header of `solar_storm_field.gdshader`.

class_name SolarStormProfile

## DERIVED from the catalog row and the carrier spell's `VFX_PROFILE`.
const PROFILE_ID := "solar_storm"

## DERIVED from `data/spells.json`.
const CARRIER_RADIUS_TILES := 3

## AUTHORED duration and four-beat timeline. Longer than the veil's: an ejection
## needs a visible launch, and the front's travel is the effect's main event
## rather than a grade change.
const DURATION_SECONDS := 2.10
const IGNITION_END := 0.14
const LAUNCH_END := 0.42
const EXPANSION_END := 0.78
const DISSIPATE_END := 1.0
const SETTLE_NORMALIZED_TIME := 0.90
const ACTION_HOLD_FRACTION := 0.46

## AUTHORED per-beat envelope, sampled at the beat boundaries and interpolated
## under exact normalized seek.
const VISIBILITY_KEYS := [0.0, IGNITION_END, LAUNCH_END, EXPANSION_END, DISSIPATE_END]
const VISIBILITY_CURVE := [0.0, 0.88, 1.00, 0.86, 0.0]

## AUTHORED front travel across the beats, as a multiplier on `ARC_RADIUS`. The
## front starts buried at the occulter and is still climbing when the corona
## begins to fade, so the storm reads as an ejection leaving rather than a ring
## that pulses in place.
const FRONT_PROGRESS_CURVE := [0.05, 0.16, 0.55, 0.94, 1.12]

## AUTHORED grain persistence, as multipliers on `GRAIN_STRENGTH`. The grain
## outlives the light so the instrument noise is the last thing to go.
const GRAIN_CURVE := [0.40, 1.00, 1.00, 1.00, 0.60]

## AUTHORED occulter geometry, in panel UV against the field's own scale. The
## anchor is off-centre on purpose -- left of the midline and high. A disk dead
## centre reads as a targeting reticle rather than an instrument's occultation.
const STORM_ANCHOR := Vector2(0.440, 0.400)
const OCCULTER_RADIUS := 0.115
const OCCULTER_EDGE := 0.010
const LIMB_RADIUS := 0.076
const LIMB_WIDTH := 0.011
const LIMB_GAIN := 1.00

## ESTIMATED corona grade from the source frame. The falloff is deliberately long
## and the field-of-view feather wide: the source's red does not stop, it thins
## across most of the frame before the instrument's circular boundary takes it.
const CORONA_FALLOFF := 0.78
const CORONA_GAIN := 0.66
const FOV_RADIUS := 0.78
const FOV_EDGE := 0.26

## ESTIMATED stream character. `BROAD` mixes the two octave groups, `THRESHOLD`
## sets where streams separate from background and therefore how wide they run,
## and `SHARPNESS` how hard their edges are. Threshold is the parameter to move
## first -- it changes stream width without dimming them, which exponentiating
## cannot do.
const STREAMER_BROAD := 0.62
const STREAMER_THRESHOLD := 0.40
const STREAMER_SHARPNESS := 1.50
const STREAMER_GAIN := 1.10
const STREAMER_REACH := 0.55
const STREAMER_WARP := 0.018
const STREAMER_DRIFT := 0.20

## ESTIMATED ejection front. Narrow and bright: the source's loop is filamentary,
## and widening it turns the storm into a blown-out band.
const ARC_RADIUS := 0.44
const ARC_WIDTH := 0.028
const ARC_GAIN := 1.05
const ARC_WARP := 0.075
const ARC_SPAN := 0.62

## AUTHORED prominences: plasma loops anchored at two limb points each, arching
## out and back. Centres are turns around the occulter, widths are angular half-
## extents, heights are crown rise above the limb. Three loops at different
## scales read as a star with activity rather than one decorative arc.
const PROMINENCE_CENTRE := Vector3(0.62, 0.90, 0.28)
const PROMINENCE_WIDTH := Vector3(0.085, 0.060, 0.045)
const PROMINENCE_HEIGHT := Vector3(0.230, 0.165, 0.120)
const PROMINENCE_WEIGHT := Vector3(1.00, 0.80, 0.65)
const PROMINENCE_THICKNESS := 0.012
const PROMINENCE_GAIN := 0.60

## AUTHORED prominence rise across the beats. Loops grow out of the limb during
## ignition, stand through the launch, and subside as the corona fades.
const PROMINENCE_RISE_CURVE := [0.10, 0.72, 1.00, 0.88, 0.35]

## ESTIMATED grade.
const EXPOSURE := 1.0
const GRAIN_STRENGTH := 0.055
const BLACK_LIFT := 0.012
const GRAIN_HZ := 12.0

## AUTHORED panel geometry at the reference radius, in world units.
const PANEL_WIDTH_U := 11.0
const PANEL_HEIGHT_U := 6.0

## DERIVED footprint span at the reference radius, in tiles.
const REFERENCE_DIAMETER_TILES := CARRIER_RADIUS_TILES * 2 + 1
const MIN_FOOTPRINT_RADIUS_TILES := 1

## AUTHORED: the anchor is a UV fraction, and *not* a world height -- the
## opposite of the sibling's choice, for a reason worth stating.
##
## `AuroraVeilProfile` pins its anchor in world units because the curtain is a
## local effect that has to stay seated on the units it affects. The storm is the
## opposite kind of thing: a backdrop-scale phenomenon whose whole composition is
## the subject, occulter high with the corona blooming down across the board. A
## world-unit pin drags the occulter toward the panel's base as the panel grows
## and shears off the entire lower hemisphere. Holding the fraction scales the
## composition intact at every radius.
##
## `STORM_ANCHOR` above is that fraction; nothing further is needed here.

## AUTHORED carrier fit and border vanish.
const FIELD_SCALE := 0.85
const EDGE_FADE := 0.12

## AUTHORED occlusion response, inherited from the sibling.
const MODEL_BOOST := 3.0
const OCCLUSION_FEATHER := 0.18
const OCCLUSION_GAIN := 2.4

## AUTHORED radial pulse, replacing the sibling's lateral wave. The sibling's
## wobble is a mirage shimmer, which is the right motion for a hallucination and
## the wrong one for an invocation: this travels outward from the occulter to the
## edges instead, displacing and brightening along the field's own radial axis.
## `INTENSITY` is the half that reads as energy leaving the star; displacement
## alone only nudges geometry.
const PULSE_AMPLITUDE := 0.010
const PULSE_FREQUENCY := 4.0
const PULSE_SPEED := 1.1
const PULSE_INTENSITY := 0.22
const PIXEL_CELLS := 64.0

## AUTHORED engineering ceiling: one billboarded quad, nothing else.
const EXPECTED_DRAW_CALLS := 1
const MAX_DRAW_CALLS := 1
const EXPECTED_GEOMETRY_INSTANCES := 1
const MAX_GEOMETRY_INSTANCES := 1
const MAX_EFFECT_NODES := 2

## AUTHORED. One panel per cast covers the whole footprint.
const MAX_LIVE_STORMS := 1
