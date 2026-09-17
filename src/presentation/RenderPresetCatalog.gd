## Shared rendering preset metadata for setup and live graphics controls.
##
## Two looks and a custom state. Every finer choice -- low-res size, geometry, upscale, the look
## and CRT sliders -- lives in the battle's Debug drawer, so the list stays a starting point
## rather than a catalogue of finished styles.

class_name RenderPresetCatalog
extends RefCounted

const NONE := "none"
const SATURATED_CRT := "saturated_crt"
const CUSTOM := "custom"

const PRESETS := [
	{
		"id": NONE,
		"label": "None",
		"description": "Native, neutral rendering with no retro treatment."
	},
	{
		"id": SATURATED_CRT,
		"label": "CRT",
		"description": "Vivid color, scanlines and RGB bleed."
	},
	{
		"id": CUSTOM,
		"label": "Custom",
		"description": "One or more values differ from the selected preset."
	}
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
	return description(NONE)


## Ids a settings file may still name. The retired styles fall back to None rather than to CRT:
## most were low-res palette looks, and a quiet native render is the safer surprise.
static func normalize_legacy(presetID: String) -> String:
	match presetID:
		"crt":
			return SATURATED_CRT
		"clean", "retro_light", "ps1_soft", "ps1_classic", "dithered_horizon", "tactical_soft", 				"halftone_press", "tactics_classic", "weathered_stone", "foggy_survival", 				"tropical_color", "stealth_green":
			return NONE
	return presetID


static func has(presetID: String) -> bool:
	return values().has(presetID)
