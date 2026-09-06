## Named HUD layouts: how much screen the windows are allowed to take.
##
## A layout is a set of *fit* values, sitting on top of whatever the active skin
## says the windows look like. The two are orthogonal on purpose -- a skin
## decides the frame, the face and the fill; a layout decides the insets, the
## pitch, the widths and the docks -- so either can move without the other.
##
## **Why this exists.** `ui_scale` is now selectable, and it does not merely
## enlarge the HUD: it shrinks the screen measured in design units. At scale 2 a
## 1152x648 window is 576x324 design units, and at scale 3 it is 384x216. Every
## width in `roomy` was measured for the first of those and simply does not fit
## the second -- the prompt alone is 560 units against a 384-unit screen. So a
## bigger, still-pixel-sharp HUD is not a font change, it is a layout change,
## and `compact` is that layout.
##
## Shaped like `WindowSkinCatalog`, `WindowFrameFilterCatalog` and
## `RenderPresetCatalog`: id, label, description, values lookup, feeding the
## same `BattleGraphicsMenu._add_option()` helper.

class_name HudLayoutCatalog
extends RefCounted

const ROOMY := "roomy"
const COMPACT := "compact"

## Compact, because `ui_scale` now defaults to 3 and `roomy` does not fit there.
const DEFAULT := COMPACT

const SKINS_NOTE := "Layouts override skin widths; skins keep the look."

const LAYOUTS := [
	{
		"id": COMPACT,
		"label": "Compact (fits x3)",
		"description": "Tight column grid, 6-unit inset, 13-unit pitch, and a two-row prompt. Fits a 384x216 design-unit screen, which is what ui_scale 3 leaves."
	},
	{
		"id": ROOMY,
		"label": "Roomy (x2 and below)",
		"description": "The historical widths, measured for a 576x324 design-unit screen. Overflows at ui_scale 3 -- the prompt alone is 560 units wide."
	}
]


## Every layout-varying token. Widths are measured output, by the rule
## `docs/UI_DESIGN.md` §8 states: the worst real string, plus at least five
## design units of headroom, rounded up to a multiple of ten.
##
## `compact`'s were re-measured at `content_inset_units` 6 against the real
## monster and spell catalogs by `debug/measure_compact_layout.gd`, rebuilt from
## §8. Raw requirements were status 172, spell 325, prompt 285 across two rows,
## deep card 305, forecast 316.
const VALUES := {
	ROOMY: {
		"screen_margin_units": 10.0,
		"prompt_top_units": 34.0,
		"content_inset_units": 11.0,
		"row_height_units": 14.0,
		"status_cell_offset_units": [0.0, 96.0, 192.0],
		# One body cell, which is what this has always been.
		"status_cell_text_gap_units": 12.0,
		"command_width_units": 90.0,
		"spell_width_units": 340.0,
		"prompt_width_units": 560.0,
		"prompt_rows": 1,
		"forecast_width_units": 340.0,
		"status_window_width_units": 270.0,
		"pager_width_units": 100.0,
		"deep_card_width_units": 320.0,
		"deep_card_capacity": 11,
		"row_capacity_default": 8
	},
	COMPACT: {
		# 4 rather than 10: two status windows at 180 plus two 10-unit margins
		# is 380 of 384, which leaves nothing. At 4 they clear both edges and
		# each other.
		"screen_margin_units": 4.0,
		# The prompt docks under the turn rail, and at 216 units of height the
		# rail's own band is most of what 34 was reserving.
		"prompt_top_units": 4.0,
		"content_inset_units": 6.0,
		"row_height_units": 13.0,
		# Derived by §8's pairing rule against the rows the status window
		# ACTUALLY builds, which is the correction: every stat row carries an
		# element cell pinned to column 2 by `_append_resonance_cell()`, not
		# just the HP row. So column 2 must clear the ATK/SPD rows' column 1,
		# not merely the HP row's column 0. Deriving against the HP row alone
		# gave [0, 68, 108] and overlapped DEF's value by 20 units on screen.
		#
		# At a 4-unit label/value gap: column 0 ends at 52, so column 1 is 60;
		# column 1 ends at 112, so column 2 is 120.
		"status_cell_offset_units": [0.0, 60.0, 120.0],
		# 4, not one body cell. The gap sits inside every fixed cell, so it
		# multiplies across the row: at 12 it pushes column 2 to 136 and the
		# window to 200, and two 200-unit windows plus margins is 408 on a
		# 384-unit screen. This is the token that buys the fit back.
		"status_cell_text_gap_units": 4.0,
		"command_width_units": 80.0,
		"spell_width_units": 330.0,
		# Two rows, not one. The worst real prompt is the confirm line with the
		# longest monster name in it, which is 550 units on one row and 290
		# across two. Nothing marquees the prompt, so one row would clip.
		"prompt_width_units": 290.0,
		"prompt_rows": 2,
		# 330, not 320: the raw requirement is 316 and the rule is at least five
		# units of headroom rounded up to a ten. 320 left four and the width
		# harness rejected it.
		"forecast_width_units": 330.0,
		"status_window_width_units": 180.0,
		"pager_width_units": 90.0,
		"deep_card_width_units": 310.0,
		# Vertical fit, not taste. At pitch 13 and inset 6 the prompt occupies
		# 4..42, a six-row spell window 46..136, and the status windows
		# 148..212 -- which clears. A seven-row spell window ends at 149 and
		# collides with the status windows by a unit, so six is the ceiling.
		"deep_card_capacity": 9,
		"row_capacity_default": 6
	}
}


static func has_layout(id: String) -> bool:
	return VALUES.has(id)


## The token set for `id`, falling back to the default rather than erroring, for
## the same reason `WindowSkinCatalog.values_for()` does: a persisted settings
## file naming a layout that no longer exists should open the game.
static func values_for(id: String) -> Dictionary:
	if not VALUES.has(id):
		push_warning("HudLayoutCatalog: unknown layout '%s'; using '%s'." % [id, DEFAULT])
		return VALUES[DEFAULT]
	return VALUES[id]


static func labels() -> Array[String]:
	var result: Array[String] = []
	for entry in LAYOUTS:
		result.append(str(entry["label"]))
	return result


static func values() -> Array[String]:
	var result: Array[String] = []
	for entry in LAYOUTS:
		result.append(str(entry["id"]))
	return result


static func description(id: String) -> String:
	for entry in LAYOUTS:
		if str(entry["id"]) == id:
			return str(entry["description"])
	return description(DEFAULT)


## Whether `id` fits a design-unit screen of the given size.
##
## Two different constraints, because the windows dock two different ways and
## charging both the same way gets the answer wrong. The prompt, forecast, spell
## and deep card are **centred** -- `PlayerCommandMenu` places the prompt at
## `(screen.x - PROMPT_WIDTH) / 2` -- so they need only to be no wider than the
## screen; `SCREEN_MARGIN` is not theirs to pay. The two status windows are
## **edge-docked**, one against each side, so they pay it twice.
##
## Getting this wrong reported `roomy` as not fitting at ui_scale 2, which is
## the configuration it was measured for and has always shipped in.
static func fits(id: String, screen_units: Vector2) -> bool:
	var v: Dictionary = values_for(id)
	var centred: float = maxf(
		maxf(float(v["prompt_width_units"]), float(v["spell_width_units"])),
		maxf(float(v["forecast_width_units"]), float(v["deep_card_width_units"]))
	)
	if centred > screen_units.x:
		return false
	var margin := float(v["screen_margin_units"])
	return float(v["status_window_width_units"]) * 2.0 + margin * 2.0 <= screen_units.x
