## Named world map framings, as diffs against `WorldMapGroundUniforms.DEFAULTS`.
##
## Mirrors `RenderPresetCatalog`'s shape: id constants, a `PRESETS` array of
## `{id, label, description}` dictionaries, and lookup helpers. The difference is that
## each entry also carries a `framing` sub-dictionary -- the keys it changes from
## `WorldMapGroundUniforms.DEFAULTS` -- because every preset here shares the same
## pitch/FOV/units-per-map-pixel and differs only in camera height (the zoom knob), the
## fog band scaled to match it, and render scale. Storing full framings would repeat
## fourteen keys seven times for one or two that actually change.
##
## `framingFor()` is the only thing callers should use; it merges a preset's diff over
## `WorldMapGroundUniforms.DEFAULTS` and always returns every framing key. Do not read
## `PRESETS[i]["framing"]` directly -- it is a diff, not a framing.
##
## Every entry here is a measurement from `debug/worldmap/worldmap-framing.html`, not a
## preference. See `docs/WORLDMAP_DESIGN.md` section 3 for how they were derived.

class_name WorldMapFramingCatalog
extends RefCounted

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

const FIT := "fit"
const TILE_EXACT := "tile_exact"
const CLOSER := "closer"
const CRT := "crt"
const OVERVIEW := "overview"
const WALKING := "walking"
const OVERLAND := "overland"
const FILTERED := "filtered"
const CUSTOM := "custom"

const PRESETS := [
	{
		"id": FIT,
		"label": "Fits This Region",
		"description": "Not a reference match -- the widest framing the loaded region can "
			+ "actually fill without showing its plane edge. At 48 tiles wide it supports "
			+ "~16 tiles across the bottom, about a third of the tile-exact framing, "
			+ "because the frame's far edge is ~2.9x wider than its near edge.",
		"framing": {
			Uniforms.K_HEIGHT: 20.0,
			Uniforms.K_FOG_START: 6.0,
			Uniforms.K_FOG_END: 35.0,
			Uniforms.K_RENDER_SCALE: 0.4,
		},
	},
	{
		"id": TILE_EXACT,
		"label": "Tile-Exact",
		"description": "Derived from the 16 px tile grid in the sharpest reference "
			+ "capture: ~53 tiles across, 7.5 buffer px per tile, ground minified ~2.1x. "
			+ "The most defensible of these -- every number is a count, not a judgement.",
		"framing": {
			Uniforms.K_HEIGHT: 66.0,
			Uniforms.K_FOG_START: 21.0,
			Uniforms.K_FOG_END: 116.0,
			Uniforms.K_RENDER_SCALE: 0.4,
		},
	},
	{
		"id": CLOSER,
		"label": "Closer Capture",
		"description": "Matches the 512x448 'FIGHT IT OUT' capture, where tiles land at "
			+ "~11 source px rather than 7.5 -- about 1.5x more zoomed in than "
			+ "Tile-Exact. Probably the travelling view: reads as a place, not a theatre.",
		"framing": {
			Uniforms.K_HEIGHT: 45.0,
			Uniforms.K_FOG_START: 14.0,
			Uniforms.K_FOG_END: 79.0,
			Uniforms.K_RENDER_SCALE: 0.4,
		},
	},
	{
		"id": CRT,
		"label": "CRT Photo",
		"description": "The photographed CRT shot: between Tile-Exact and Closer Capture "
			+ "in zoom, but with a much heavier and earlier haze on a coarser buffer. "
			+ "Some of that wash is the CRT rather than the game -- treat this fog as an "
			+ "upper bound, not a target.",
		"framing": {
			Uniforms.K_HEIGHT: 56.0,
			Uniforms.K_FOG_START: 12.0,
			Uniforms.K_FOG_END: 74.0,
			Uniforms.K_FOG_CURVE: 1.1,
			Uniforms.K_FOG_COLOR: Color("d8ecf2"),
			Uniforms.K_RENDER_SCALE: 0.333,
		},
	},
	{
		"id": OVERVIEW,
		"label": "Route Planning",
		"description": "Beyond any of the source captures: pulled back far enough to see "
			+ "a whole region at once. Not a reference match -- included because if "
			+ "travel time is a resource the player needs a view that shows where the "
			+ "roads go. The tile sparkle gets worse at this distance.",
		"framing": {
			Uniforms.K_HEIGHT: 105.0,
			Uniforms.K_FOG_START: 34.0,
			Uniforms.K_FOG_END: 185.0,
			Uniforms.K_RENDER_SCALE: 0.4,
		},
	},
	{
		"id": WALKING,
		"label": "Walking",
		"description": "Tighter than any source capture. Individual tiles are large and "
			+ "the party dominates the frame. Good for the moment a road is being "
			+ "walked, bad for deciding where to go next.",
		"framing": {
			Uniforms.K_HEIGHT: 30.0,
			Uniforms.K_FOG_START: 10.0,
			Uniforms.K_FOG_END: 53.0,
			Uniforms.K_RENDER_SCALE: 0.4,
		},
	},
	{
		"id": OVERLAND,
		"label": "Overland",
		"description": "Hand-tuned in the debug scene on 2026-09-01 and kept. Shallower "
			+ "pitch and narrower FOV than the reference framings, and the only preset that "
			+ "uses ground curvature, so the world falls away toward the top of the frame "
			+ "rather than running flat off it. Covers about the same 53 tiles as "
			+ "Tile-Exact but reads as standing in the landscape rather than surveying it.",
		"framing": {
			Uniforms.K_PITCH: 40.5,
			Uniforms.K_FOV: 20.0,
			Uniforms.K_HEIGHT: 62.5,
			Uniforms.K_CURVATURE: 0.0008,
			Uniforms.K_FOG_START: 62.5,
			Uniforms.K_FOG_END: 331.25,
		},
	},
	{
		"id": FILTERED,
		"label": "Tile-Exact, Filtered",
		"description": "Tile-Exact at native resolution with anisotropic filtering and "
			+ "cloud shadows on. The comparison, not a recommendation: it shows what the "
			+ "clean version costs. The ground stops being minified, the sparkle "
			+ "disappears, and it stops looking like the reference.",
		"framing": {
			Uniforms.K_HEIGHT: 66.0,
			Uniforms.K_FOG_START: 21.0,
			Uniforms.K_FOG_END: 116.0,
			Uniforms.K_RENDER_SCALE: 1.0,
			Uniforms.K_FILTER_MODE: Uniforms.FILTER_NEAREST_MIPMAP,
			Uniforms.K_CLOUD_STRENGTH: 0.28,
		},
	},
	{
		"id": CUSTOM,
		"label": "Custom",
		"description": "One or more values differ from the selected preset.",
		"framing": {},
	},
]


static func labels() -> Array[String]:
	var result: Array[String] = []
	for preset in PRESETS:
		result.append(preset["label"])
	return result


static func values() -> Array[String]:
	var result: Array[String] = []
	for preset in PRESETS:
		result.append(preset["id"])
	return result


static func description(presetID: String) -> String:
	for preset in PRESETS:
		if preset["id"] == presetID:
			return preset["description"]
	return description(TILE_EXACT)


## The only accessor callers should use: a preset's diff merged over
## `WorldMapGroundUniforms.DEFAULTS`, carrying every framing key.
static func framingFor(presetID: String) -> Dictionary:
	for preset in PRESETS:
		if preset["id"] == presetID:
			return Uniforms.complete(preset["framing"])
	return Uniforms.complete({})


static func has(presetID: String) -> bool:
	return values().has(presetID)
