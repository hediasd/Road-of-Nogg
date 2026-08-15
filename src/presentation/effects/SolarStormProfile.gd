## Calibration constants for the Solar Storm coronagraph panel.
##
## Forked from `AuroraVeilProfile` under docs/VFX_DESIGN.md §4's sibling test:
## same billboarded-quad carrier, same four-beat timeline, same pixel snap, wave,
## radius response, and depth-resolved model lighting. The field is what differs.
## See the header of `solar_storm_field.gdshader`.

class_name SolarStormProfile

## DERIVED from the catalog row and the carrier spell's `VFX_PROFILE`. This is
## the full effect -- the v2.4 rung -- and the one the spell selects.
const PROFILE_ID := "solar_storm"

## The version ladder, exposed as separate catalog rows so each addition can be
## compared against the one before it in the debug scene. They are override sets
## on a single effect rather than forked files: every rung shares one field, and
## each step only switches a later feature off. Forking five copies to compare
## five values would guarantee they drift apart under exactly the tuning the
## comparison exists to inform.
##
## The rows are an authoring aid, not content. Nothing in `data/spells.json`
## points at them, and `PROFILE_ID` above stays the gameplay entry point.
const PROFILE_ID_V1 := "solar_storm_v1"
const PROFILE_ID_V2 := "solar_storm_v2"
const PROFILE_ID_V2_1 := "solar_storm_v2_1"
const PROFILE_ID_V2_2 := "solar_storm_v2_2"
const PROFILE_ID_V2_3 := "solar_storm_v2_3"

## v1: the lateral wave, before the motion changed. `WAVE_AMPLITUDE` is zero on
## every other rung, so v1 is the only row that switches the wobble on and the
## only reason the wave code still exists.
##
## One honest gap: v1 also carried a sign error that made the stream splay crawl
## back toward the occulter, and this row does not restore it. Reproducing an
## acknowledged bug would cost another flag to make a comparison worse.
const VARIANT_V1 := {
	"WAVE_AMPLITUDE": V1_WAVE_AMPLITUDE,
	"PULSE_AMPLITUDE": 0.0,
	"PULSE_INTENSITY": 0.0,
	"PROMINENCE_GAIN": 0.0,
	"HEAT_WASH_GAIN": 0.0,
	"FLARE_GAIN": 0.0,
	"FLAME_TURBULENCE": 0.0,
}
## v2: the radial pulse alone, replacing v1's lateral wave. Everything the later
## rungs add is switched off.
const VARIANT_V2 := {
	"PROMINENCE_GAIN": 0.0,
	"HEAT_WASH_GAIN": 0.0,
	"FLARE_GAIN": 0.0,
	"FLAME_TURBULENCE": 0.0,
}
## v2.1 adds the prominence arches.
const VARIANT_V2_1 := {
	"HEAT_WASH_GAIN": 0.0,
	"FLARE_GAIN": 0.0,
	"FLAME_TURBULENCE": 0.0,
}
## v2.2 adds the heat wash on the board.
const VARIANT_V2_2 := {
	"FLARE_GAIN": 0.0,
	"FLAME_TURBULENCE": 0.0,
}
## v2.3 adds the flare bloom at the launch beat.
const VARIANT_V2_3 := {
	"FLAME_TURBULENCE": 0.0,
}

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

## AUTHORED flame turbulence. Applied to the stream field's angular coordinate
## only, never to the panel UV -- UV is where the sibling's wobble lived, and
## displacing there is what made it read as a mirage. Confined to the streams it
## ripples their boundaries into fire tongues while the occulter, prominences,
## and front stay geometrically clean. `SCALE` is the tongue frequency, `SPEED`
## how fast they lick.
const FLAME_TURBULENCE := 0.0045
const FLAME_SCALE := 23.0
const FLAME_SPEED := 0.60

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

## AUTHORED flare bloom: a short whiteout at the launch beat, so the storm has a
## moment of release rather than a steady glow.
##
## Deliberately *not* a keyed curve like every other envelope here. The shared
## keys sit on the beat boundaries and interpolate linearly between them, so a
## peak authored at LAUNCH becomes a ramp climbing from 0.14 and decaying to
## 0.78 -- a swell across two thirds of the cast rather than a flash. A spike
## needs a width shorter than the gap between beats, so it is evaluated
## analytically as a narrow gaussian instead.
const FLARE_GAIN := 0.85
const FLARE_REACH := 0.45
const FLARE_CENTRE := 0.42
const FLARE_WIDTH := 0.045

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

## AUTHORED heat wash. Geometry under the storm takes its own warm glow, peaking
## as the ejection front passes rather than tracking overall brightness -- the
## board should feel the arrival, not the ambience. Bounded by the corona's
## falloff so the wash stops where the storm does.
const HEAT_TINT := Color(1.0, 0.42, 0.13)
const HEAT_WASH_GAIN := 1.20
const HEAT_WASH_CURVE := [0.0, 0.22, 0.85, 1.00, 0.15]

## AUTHORED occlusion response, inherited from the sibling.
const MODEL_BOOST := 3.0
const OCCLUSION_FEATHER := 0.18
const OCCLUSION_GAIN := 2.4

## AUTHORED v1 wave. `WAVE_AMPLITUDE` defaults to zero -- the wave exists only
## for the v1 comparison row; `V1_WAVE_AMPLITUDE` is the value v1 actually shipped.
const WAVE_AMPLITUDE := 0.0
const V1_WAVE_AMPLITUDE := 0.006
const WAVE_FREQUENCY := 3.5
const WAVE_SPEED := 2.0

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
