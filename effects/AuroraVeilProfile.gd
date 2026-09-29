## Calibration constants for the Aurora Veil iridescent panel.
##
## The effect owns exactly one Y-axis billboarded quad standing at the impact
## centre. It has no particles and no second layer: the reference is a single
## continuous field, and splitting it across carriers would only invent seams
## the source does not have. See the header of `aurora_veil_field.gdshader`.

class_name AuroraVeilProfile

## DERIVED from the catalog row and the carrier spell's `VFX_PROFILE`.
const PROFILE_ID := "aurora_veil"

## DERIVED from `data/spells.json`. The carrier is a radius-2 area spell, and
## one panel covers the whole footprint from its centre rather than one panel
## per body -- a radius-2 area holds several targets and overlapping additive
## panels would compound their grade instead of reading as several auras.
const CARRIER_RADIUS_TILES := 2

## AUTHORED duration and four-beat normalized timeline. The beats are named for
## what the veil is doing, not for a generic onset/decay split: the hold in
## `BREATHE` is the phase that reads as hallucination rather than as a flash.
const DURATION_SECONDS := 1.60
const INTRUSION_END := 0.15
const BLOOM_END := 0.45
const BREATHE_END := 0.70
const DISSOLVE_END := 1.0
const SETTLE_NORMALIZED_TIME := 0.92
const ACTION_HOLD_FRACTION := 0.50

## AUTHORED per-beat envelope. `VISIBILITY_CURVE` is sampled at the beat
## boundaries above and interpolated under exact normalized seek, so the shader
## receives one scalar rather than four overlapping envelopes.
const VISIBILITY_KEYS := [0.0, INTRUSION_END, BLOOM_END, BREATHE_END, DISSOLVE_END]
const VISIBILITY_CURVE := [0.0, 0.62, 1.00, 0.94, 0.0]

## AUTHORED grain persistence. The grain outlives the colour by a short tail so
## the veil leaves an artifact behind rather than simply switching off. Values
## are multipliers on `GRAIN_STRENGTH`, sampled on the same key positions.
const GRAIN_CURVE := [0.35, 1.00, 1.00, 1.00, 0.55]

## The colour sweep and the brightness envelope are separate ellipses; collapsing
## them into one is what makes the field read as a glowing ball instead of a veil.
##
## `CORE_OFFSET` is DERIVED per panel size from `CORE_HEIGHT_U`; the effect
## publishes it. The reference's 0.220 is superseded by that world-unit pin.
const BAND_RADIUS := Vector2(0.420, 0.300)
## AUTHORED curtain proportions, deliberately departed from the reference's
## near-circular envelope. `x` is capped by the panel: the field dies at the
## quad edge when `x` reaches 0.54, so this leaves margin for `EDGE_FADE`.
const ENVELOPE_RADIUS := Vector2(0.460, 0.245)
const FALLOFF_KNEE := 0.55
const FALLOFF_SOFT := 1.55
const BAND_SCALE := 0.78
const BAND_OFFSET := 0.0
const WARP_AMPLITUDE := 0.022
const BAND_WARP_AMPLITUDE := 0.045

## ESTIMATED reflection calibration. The reference's lower lobe is a waterline
## reflection: slightly compressed, slightly dimmer, horizontally smeared, and
## carrying ripple striations the upper lobe does not have.
const MIRROR_ANCHOR_HEIGHT := 0.50
const LOWER_BLEND := 0.060
const LOWER_COMPRESS := 4.0
const LOWER_DIM := 0.78
const LOWER_SMEAR := 0.010
const SEAM_WIDTH := 0.055
const SEAM_FLOOR := 0.86
const RIPPLE_FREQUENCY := 4.5
const RIPPLE_DEPTH := 0.040

## AUTHORED, and zero on purpose. The reference's mirror needs empty space below
## the waterline; a body standing on the ground has none, and the compression
## required to keep the lower lobe off the floor reduced it to a smear reading as
## a stray second blob rather than a reflection. Raising this restores the full
## reflection for framings that have room for it -- the machinery is intact.
const MIRROR_STRENGTH := 0.0

## ESTIMATED grade. `BLACK_LIFT` reproduces the reference's raised floor; the
## field never reaches true black inside its own footprint.
const INTENSITY := 0.90
const GRAIN_STRENGTH := 0.050
const BLACK_LIFT := 0.022

## AUTHORED grain cadence in hashed steps per second. Quantizing the frame index
## is what keeps animated grain compatible with exact normalized seek.
const GRAIN_HZ := 12.0

## AUTHORED band drift across the cast. Below one full period, so the veil
## breathes rather than visibly cycling.
const BAND_DRIFT_TURNS := 0.22

## AUTHORED panel geometry at the reference radius, in world units. Width covers
## the radius-2 footprint with margin; the curtain is centred horizontally so the
## panel focuses whatever stands at the impact centre.
const PANEL_WIDTH_U := 7.0
const PANEL_HEIGHT_U := 5.8
const PANEL_ASPECT := PANEL_WIDTH_U / PANEL_HEIGHT_U

## DERIVED footprint span at the reference radius, in tiles.
const REFERENCE_DIAMETER_TILES := CARRIER_RADIUS_TILES * 2 + 1

## AUTHORED radius response: the panel scales uniformly with the footprint.
##
## Non-uniform scaling is tempting here and wrong. The field is aspect-corrected,
## which makes its world width a product of `ENVELOPE_RADIUS.x` and the panel's
## *height*, not its width -- so holding height back while widening the quad
## grows the carrier without growing the curtain on it. Uniform scale keeps the
## tuned proportions exactly and makes the aspect constant across every radius.
const MIN_FOOTPRINT_RADIUS_TILES := 1

## AUTHORED anchor and core heights, in world units above the target's feet.
##
## These are world heights rather than UV fractions on purpose. Held as fractions
## they ride the panel upward as it scales, and by radius 5 the curtain floats
## clear above the units it is supposed to be affecting. Pinned in world units
## the curtain stays seated on the board at every radius and only its span grows.
## The effect converts both into UV against the live panel height.
const ANCHOR_HEIGHT_U := 0.93
const CORE_HEIGHT_U := 0.99

## AUTHORED carrier fit. The ESTIMATED radii above encode the reference's
## proportions; this single multiplier shrinks both ellipses together so the
## falloff reaches zero inside the quad. A clipped edge is the one failure that
## announces a panel instantly, so the value buys margin rather than coverage.
const FIELD_SCALE := 0.72

## AUTHORED border vanish, in panel UV. Belt-and-braces against a clipped edge.
const EDGE_FADE := 0.12

## AUTHORED occlusion response. `MODEL_BOOST` is how hard the curtain lights a
## model it passes in front of; the feather softens the depth comparison in world
## units so the hand-off follows the silhouette as a gradient rather than a cut.
const MODEL_BOOST := 3.0
const OCCLUSION_FEATHER := 0.18
## Coverage multiplier applied only where the curtain fronts geometry, so faint
## regions still light the whole silhouette rather than a few bright filaments.
const OCCLUSION_GAIN := 2.4

## AUTHORED wave displacement. Amplitude is panel UV, frequency is cycles across
## the panel, speed is cycles per second of playback. The wave is applied to the
## sampling coordinate *before* the cell snap, so the grid stays locked to the
## panel and the colour flows through it.
const WAVE_AMPLITUDE := 0.006
const WAVE_FREQUENCY := 3.5
const WAVE_SPEED := 2.0

## AUTHORED aurora curtain. `STRENGTH` is how deeply the filaments cut into the
## field, `DETAIL` their count across the panel, and the fold pair the sheet's
## lateral waviness and how much it shears with height. Drift is turns per second
## of playback, kept slow so the curtain breathes rather than scrolls.
const CURTAIN_STRENGTH := 0.88
const CURTAIN_DETAIL := 20.0
const CURTAIN_FOLD_FREQUENCY := 0.8
const CURTAIN_FOLD_DEPTH := 0.85
const CURTAIN_FOLD_SHEAR := 0.80
const CURTAIN_DRIFT_SPEED := 0.35

## AUTHORED cell count across the panel width. The vertical count is derived
## from `PANEL_ASPECT` so cells stay square in world units; zero disables the
## snap and returns the field to continuous sampling.
const PIXEL_CELLS := 56.0

## AUTHORED engineering ceiling: one billboarded quad, nothing else.
const EXPECTED_DRAW_CALLS := 1
const MAX_DRAW_CALLS := 1
const EXPECTED_GEOMETRY_INSTANCES := 1
const MAX_GEOMETRY_INSTANCES := 1
const MAX_EFFECT_NODES := 2

## AUTHORED. One panel per cast covers the whole footprint, so a second live
## copy on the same centre would only double the additive grade.
const MAX_LIVE_VEILS := 1
