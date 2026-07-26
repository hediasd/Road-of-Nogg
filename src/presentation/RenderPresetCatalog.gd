## Shared rendering preset metadata for setup and live graphics controls.

class_name RenderPresetCatalog
extends RefCounted

const NONE := "none"
const DITHERED_HORIZON := "dithered_horizon"
const TACTICAL_SOFT := "tactical_soft"
const SATURATED_CRT := "saturated_crt"
const TACTICS_CLASSIC := "tactics_classic"
const WEATHERED_STONE := "weathered_stone"
const FOGGY_SURVIVAL := "foggy_survival"
const TROPICAL_COLOR := "tropical_color"
const STEALTH_GREEN := "stealth_green"
const CUSTOM := "custom"

const PRESETS := [
	{
		"id": NONE,
		"label": "None",
		"description": "Native, neutral rendering with no retro treatment."
	},
	{
		"id": DITHERED_HORIZON,
		"label": "Dithered Horizon",
		"description": "Hard pixels, restrained color and coarse dithering like the first reference."
	},
	{
		"id": TACTICAL_SOFT,
		"label": "Tactical Soft",
		"description": "Soft low-resolution tactics presentation like the second reference."
	},
	{
		"id": SATURATED_CRT,
		"label": "Saturated CRT",
		"description": "Vivid color, scanlines and RGB bleed like the third reference."
	},
	{
		"id": TACTICS_CLASSIC,
		"label": "Final Fantasy Tactics-Inspired",
		"description": "A crisp, gently dithered late-1990s tactical RPG treatment."
	},
	{
		"id": WEATHERED_STONE,
		"label": "Vagrant Story-Inspired",
		"description": "Muted, high-contrast low-poly drama inspired by darker PS1 RPGs."
	},
	{
		"id": FOGGY_SURVIVAL,
		"label": "Silent Hill-Inspired",
		"description": "Dim, desaturated screen treatment inspired by survival horror."
	},
	{
		"id": TROPICAL_COLOR,
		"label": "Chrono Cross-Inspired",
		"description": "Smooth, bright and richly saturated late-era PS1 color."
	},
	{
		"id": STEALTH_GREEN,
		"label": "Metal Gear Solid-Inspired",
		"description": "Sharp, subdued low-color presentation inspired by stealth games."
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


static func normalize_legacy(presetID: String) -> String:
	match presetID:
		"clean":
			return NONE
		"retro_light", "ps1_soft":
			return TACTICAL_SOFT
		"ps1_classic":
			return DITHERED_HORIZON
		"crt":
			return SATURATED_CRT
	return presetID


static func has(presetID: String) -> bool:
	return values().has(presetID)
