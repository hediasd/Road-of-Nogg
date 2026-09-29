## Comparison filters applied to a skin's frame art before it is scaled.
##
## These exist to answer one question in the real game rather than in a
## screenshot: how close can authored border art be pushed to the Brigandine
## reference by post-processing alone, and where does post-processing stop
## being able to help. Each entry is one of the variants measured in
## `docs/UI_DESIGN.md` §4a, expressed as data rather than as a branch.
##
## **This is a debug affordance, not a look.** The intended end state is that
## the art itself is redrawn and every window ships under `NONE`. A filter is a
## way to judge a change before committing to redrawing, not a substitute for
## drawing it -- a filtered file and the source it came from disagree forever,
## which is exactly the trap `window_fill` fell into when it was inherited
## rather than measured.
##
## Shaped like `WindowSkinCatalog` and `RenderPresetCatalog` on purpose: id,
## label, description, and a values lookup feeding the same
## `BattleGraphicsMenu._add_option()` helper. A second convention for the same
## job is the drift those two files already avoid.
##
## Skins with no frame art ignore all of this; the filter only ever touches
## `NoggTheme.WINDOW_FRAME_TEXTURE`.

class_name WindowFrameFilterCatalog
extends RefCounted

const NONE := "none"
const HARD := "hard"
const COARSE := "coarse"
const HARD_COARSE := "hard_coarse"
const DITHER := "dither"
const DEBURR := "deburr"
const LOSSY := "lossy"

const DEFAULT := NONE

## Dropdown metadata, in display order: the shipping look first, then the
## variants roughly in order of how much they change.
const FILTERS := [
	{
		"id": NONE,
		"label": "None (as drawn)",
		"description": "The art exactly as authored. What ships."
	},
	{
		"id": DEBURR,
		"label": "Deburr + coarsen",
		"description": "Drops the dark ring outside the border, keeps the grey antialiasing, coarsens x1.5 and thins the fill to the reference's 0.55. The closest a filter gets."
	},
	{
		"id": COARSE,
		"label": "Coarsen x1.5",
		"description": "Draws the art half again as large, so one art pixel covers what one reference pixel covers. Border weight only."
	},
	{
		"id": HARD,
		"label": "Hard edges",
		"description": "Snaps every pixel to border, fill or nothing, removing all antialiasing. Note the reference has antialiasing along its diagonal, so this moves away from it."
	},
	{
		"id": HARD_COARSE,
		"label": "Hard edges + coarsen",
		"description": "Both of the above together."
	},
	{
		"id": DITHER,
		"label": "Dither fill (broken)",
		"description": "Ordered 2x2 dither on the fill, as PS1 translucency was often done. Kept as a demonstration that it cannot work: a nine-patch stretches one middle column across the window, so the pattern smears into stripes."
	},
	{
		"id": LOSSY,
		"label": "Detail loss x1.5",
		"description": "Downscales the art with nearest sampling and draws it back up, as if it had been authored at the reference's resolution. Coarsens the corners and the straight edges alike."
	}
]


## What each filter does, as data.
##
##   `snap`       collapse every pixel to border / fill / nothing
##   `deburr`     drop only the dark opaque ring outside the border
##   `fill_alpha` re-alpha the translucent fill; negative leaves it alone
##   `dither`     +/- swing applied to the fill on a 2x2 grid; 0 is off
##   `downscale`  shrink the source by this factor before drawing it back up
##   `draw_scale` multiplies the point-scale factor the texture is drawn at
const VALUES := {
	NONE: {
		"snap": false, "deburr": false, "fill_alpha": -1.0,
		"dither": 0.0, "downscale": 1.0, "draw_scale": 1.0
	},
	DEBURR: {
		"snap": false, "deburr": true, "fill_alpha": 0.55,
		"dither": 0.0, "downscale": 1.0, "draw_scale": 1.5
	},
	COARSE: {
		"snap": false, "deburr": false, "fill_alpha": -1.0,
		"dither": 0.0, "downscale": 1.0, "draw_scale": 1.5
	},
	HARD: {
		"snap": true, "deburr": false, "fill_alpha": -1.0,
		"dither": 0.0, "downscale": 1.0, "draw_scale": 1.0
	},
	HARD_COARSE: {
		"snap": true, "deburr": false, "fill_alpha": -1.0,
		"dither": 0.0, "downscale": 1.0, "draw_scale": 1.5
	},
	DITHER: {
		"snap": true, "deburr": false, "fill_alpha": 0.55,
		"dither": 0.10, "downscale": 1.0, "draw_scale": 1.5
	},
	LOSSY: {
		"snap": false, "deburr": false, "fill_alpha": -1.0,
		"dither": 0.0, "downscale": 1.5, "draw_scale": 1.5
	}
}


static func has_filter(id: String) -> bool:
	return VALUES.has(id)


## The parameter set for `id`, falling back to the default rather than erroring,
## for the same reason `WindowSkinCatalog.values_for()` does: a persisted
## settings file naming a filter that no longer exists should open the game.
static func values_for(id: String) -> Dictionary:
	if not VALUES.has(id):
		push_warning("WindowFrameFilterCatalog: unknown filter '%s'; using '%s'." % [id, DEFAULT])
		return VALUES[DEFAULT]
	return VALUES[id]


static func labels() -> Array[String]:
	var result: Array[String] = []
	for entry in FILTERS:
		result.append(str(entry["label"]))
	return result


static func values() -> Array[String]:
	var result: Array[String] = []
	for entry in FILTERS:
		result.append(str(entry["id"]))
	return result


static func description(id: String) -> String:
	for entry in FILTERS:
		if str(entry["id"]) == id:
			return str(entry["description"])
	return description(DEFAULT)
