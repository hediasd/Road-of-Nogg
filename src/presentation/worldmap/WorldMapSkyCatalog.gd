## Available world map backdrops.
##
## Deliberately a flat list rather than a JSON catalog: there are two of them and they are
## chosen by eye in the debug scene. If skies ever become per-region or per-time-of-day this
## should move to `data/worldmap/` beside the regions, in the same shape.

class_name WorldMapSkyCatalog
extends RefCounted

const OFF := "off"
const SKIES2 := "skies2"
const TEMP2_SUNSET := "temp2_sunset"

const SKIES := [
	{
		"id": OFF,
		"label": "Off",
		"description": "No backdrop. Wherever the ground stops, the viewport's clear colour "
			+ "shows -- which is what the console references do, since their maps run off "
			+ "every edge of the frame and never reveal a horizon.",
		"texture": "",
	},
	{
		"id": SKIES2,
		"label": "Skies2 (original)",
		"description": "The source art unmodified: deep blue sky, an orange sun on the "
			+ "horizon, banded stripes, and an amber field below. Kept alongside the "
			+ "recolour so the two can be compared.",
		"texture": "res://assets/textures/Skies2.png",
	},
	{
		"id": TEMP2_SUNSET,
		"label": "Sunset (temp2 palette)",
		"description": "Skies2 recoloured onto region temp2's own seven colours: upper sky "
			+ "and muted bands to its dark teal, the bright band to its sea teal, the sun to "
			+ "its orange, the lower field to its sand. Every destination colour is one the "
			+ "region actually uses, so the backdrop cannot drift off-palette from the map "
			+ "in front of it.",
		"texture": "res://assets/worldmap/skies/temp2_sunset.png",
	},
]


static func ids() -> Array[String]:
	var result: Array[String] = []
	for sky in SKIES:
		result.append(str(sky["id"]))
	return result


static func labels() -> Array[String]:
	var result: Array[String] = []
	for sky in SKIES:
		result.append(str(sky["label"]))
	return result


static func has(skyID: String) -> bool:
	return ids().has(skyID)


static func textureFor(skyID: String) -> Texture2D:
	for sky in SKIES:
		if sky["id"] != skyID:
			continue
		var path := str(sky["texture"])
		if path.is_empty():
			return null
		return ResourceLoader.load(path) as Texture2D
	return null
