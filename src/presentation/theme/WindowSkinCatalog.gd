## The named window skins and the look tokens each one carries.
##
## A skin is a set of *look* values, not a second window system: both skins use
## the same `NoggWindow`, the same draw order, the same focus behaviour, and the
## same paging and marquee rules. See `docs/UI_DESIGN.md` §4a for the contract
## and for where each Brigandine Plate number was measured from.
##
## Shaped like `RenderPresetCatalog` on purpose — id, label, description, and a
## values lookup. That is already the file this project reaches for when a named
## presentation option needs to appear in a dropdown, and a second convention
## for the same job would be the drift this cycle exists to remove.
##
## **What belongs here and what does not.** A token varies per skin only if the
## reference speaks to it. Canvas layer numbers, text colour roles, tween
## durations, cursor geometry and marquee timings are shared and stay `const` in
## `NoggTheme`; the reference says nothing about any of them.

class_name WindowSkinCatalog
extends RefCounted

const NoggHeraldFontScript = preload("res://src/presentation/theme/NoggHeraldFont.gd")

const NOGG := "nogg"
const BRIGANDINE_PLATE := "brigandine_plate"

const DEFAULT := NOGG

## Dropdown metadata, in display order.
const SKINS := [
	{
		"id": NOGG,
		"label": "Nogg",
		"description": "The house look: rounded, haloed, Nogg Terminal on a near-opaque body."
	},
	{
		"id": BRIGANDINE_PLATE,
		"label": "Brigandine Plate",
		"description": "Square hairline plates, no halo, Nogg Herald over a transparent fill."
	}
]


## Every skin-varying token, by skin id.
##
## `body_size_units` must be a whole multiple of its face's nominal size — 12
## for Nogg Terminal, `NoggHeraldFont.NOMINAL_SIZE` for Herald. Both faces are
## bitmaps with baked atlases and resample visibly at any other size; the rule
## is stated in `docs/UI_DESIGN.md` §3 and `is_valid()` below enforces it rather
## than leaving it to a reviewer.
const VALUES := {
	NOGG: {
		"font_path": "res://assets/Fonts/NoggTerminal/NoggTerminal.res",
		"body_size_units": 12.0,
		"row_height_units": 13.0,
		"corner_radius_units": 3.0,
		"frame_ring_units": 1.0,
		"content_inset_units": 6.0,
		"window_fill": Color(0.075, 0.058, 0.042, 0.86),
		"frame_active": Color(0.902, 0.878, 1.0),
		"frame_inactive": Color(0.384, 0.357, 0.471),
		# A halo outset of zero is what "this skin has no halo" means; the
		# builder reads it and declines to construct the node at all.
		"halo_outset_units": 3.0,
		"halo_spread_units": 5.0,
		"halo_shadow_offset_units": Vector2(0.5, 1.0),
		"halo_fill": Color(0.0, 0.0, 0.0, 0.28),
		"halo_shadow": Color(0.0, 0.0, 0.0, 0.58),
		# The dark ring drawn just outside a turn-rail tile. It is the rail's
		# halo: the same job the window halo does, done by a different surface,
		# so it belongs to the skin for the same reason.
		"rail_ink": Color(0.0, 0.0, 0.0, 0.88),
		"status_cell_offset_units": [0.0, 96.0, 192.0],
		# `nogg`'s widths are its historical authored values, not fresh output from
		# `debug/measure_px4_widths.gd`. The skin is frozen for this cycle and
		# validation asserts it, so re-deriving numbers that already ship -- and
		# that carry more slack than the measurement alone would give them -- would
		# be a change nobody asked for dressed as a measurement.
		"command_width_units": 110.0,
		"spell_width_units": 340.0,
		"prompt_width_units": 470.0,
		"forecast_width_units": 340.0,
		"status_window_width_units": 270.0,
		"pager_width_units": 95.0,
		"deep_card_width_units": 310.0,
		"deep_card_capacity": 12
	},
	BRIGANDINE_PLATE: {
		"font_path": "res://assets/Fonts/NoggHerald/NoggHerald.res",
		"body_size_units": float(NoggHeraldFontScript.NOMINAL_SIZE),
		# 1.08 cells, the same ratio `nogg` carries. The reference's own pitch is
		# 2.10 cells and is deliberately not adopted: it is the pitch of a
		# two-line dialogue box, and at the deep card's twelve-row capacity it
		# would make the card taller than the screen. §4a records the arithmetic.
		"row_height_units": 14.0,
		"corner_radius_units": 0.0,
		"frame_ring_units": 1.5,
		"content_inset_units": 11.0,
		# 0.78 rather than the 0.55 the reference measures at. The reference is a
		# flat painted map, so its fill lets through tone; our board is a lit 3D
		# checkerboard, so the same fill lets through texture and the ground
		# under a row of text stops being stable. Both 0.55 and 0.65 were tried
		# in a real battle and are not legible. Still clearly more transparent
		# than nogg's 0.86. §4a records the full reasoning and the 0.70-0.82
		# band this may move within.
		"window_fill": Color(0.075, 0.058, 0.042, 0.78),
		"frame_active": Color(0.937, 0.937, 0.937),
		# Derived from the active tint at the same ratio `nogg` uses between its
		# own two, so "this window is not listening" reads the same in both.
		"frame_inactive": Color(0.399, 0.399, 0.399),
		"halo_outset_units": 0.0,
		"halo_spread_units": 0.0,
		"halo_shadow_offset_units": Vector2.ZERO,
		"halo_fill": Color(0.0, 0.0, 0.0, 0.0),
		"halo_shadow": Color(0.0, 0.0, 0.0, 0.0),
		# Fully transparent, for the same reason this skin builds no window
		# halo. A dark ring around every tile is a halo by another name, and
		# leaving it while removing the windows' would have made the rail the
		# one surface still wearing the look this skin replaced. The tile's
		# team-coloured frame is its edge.
		"rail_ink": Color(0.0, 0.0, 0.0, 0.0),
		# Derived from `debug/measure_px4_widths.gd`, which reports what each
		# column's content actually ends at. Column 1 must clear the widest
		# *paired* column-0 cell (58 under Herald) and column 2 must clear
		# column 1's end. Terminal's [0, 96, 192] satisfied both but left 38 and
		# 40 units of dead space respectively -- visible in a capture as a gap
		# between DEF and the element cell.
		"status_cell_offset_units": [0.0, 76.0, 152.0],
		# Every width below is measured output, by one stated rule: the worst real
		# string this skin can render, plus at least five design units of
		# headroom, rounded up to a multiple of ten. The headroom is not
		# decoration -- `PROMPT_WIDTH` once shipped 76 device pixels short of a
		# real status line, and a catalog gaining one longer monster name is all
		# it takes to truncate a window sized to its exact worst case.
		#
		# Measured: command 90, spell 248, prompt 332, forecast 267, status cell
		# 211, pager 63, card 240. Rerun `debug/measure_px4_widths.gd` and
		# `debug/measure_deep_card.gd` if the face, the body size, or the inset
		# changes -- each of the three moves every one of them.
		"command_width_units": 100.0,
		"spell_width_units": 260.0,
		"prompt_width_units": 340.0,
		"forecast_width_units": 280.0,
		"status_window_width_units": 220.0,
		# Measured for the first time here. `nogg`'s 95 was authored as openly
		# provisional because nothing in the catalog paged when it was written;
		# the deep card pages now, and "12 / 12" between two arrows needs 63.
		"pager_width_units": 70.0,
		"deep_card_width_units": 250.0,
		# Eleven, not twelve. The deep card docks below the prompt and must stop
		# short of the status windows, and this skin's taller row pitch and
		# larger inset leave room for one row fewer. The deepest unit in the
		# catalog is 16 rows, so it pages once under either skin.
		"deep_card_capacity": 11
	}
}


static func has_skin(id: String) -> bool:
	return VALUES.has(id)


## The token set for `id`, falling back to the default rather than erroring: a
## persisted settings file naming a skin that no longer exists should open the
## game, not stop it.
static func values_for(id: String) -> Dictionary:
	if not VALUES.has(id):
		push_warning("WindowSkinCatalog: unknown skin '%s'; using '%s'." % [id, DEFAULT])
		return VALUES[DEFAULT]
	return VALUES[id]


static func label_for(id: String) -> String:
	for skin in SKINS:
		if str(skin["id"]) == id:
			return str(skin["label"])
	return id


static func description_for(id: String) -> String:
	for skin in SKINS:
		if str(skin["id"]) == id:
			return str(skin["description"])
	return ""


## Fails loudly on a skin whose body size would resample its own face.
##
## Checked here rather than trusted, because the failure is silent on screen:
## a bitmap face at a fractional multiple of its nominal size does not error, it
## just renders soft, and "the new skin looks slightly wrong" is a much harder
## bug to find than a warning at startup.
static func is_valid(id: String) -> bool:
	if not VALUES.has(id):
		return false
	var values: Dictionary = VALUES[id]
	var nominal := _nominal_size_for(str(values["font_path"]))
	var size := float(values["body_size_units"])
	var multiple := size / float(nominal)
	if absf(multiple - round(multiple)) > 0.001 or multiple < 1.0:
		push_error(
			"WindowSkinCatalog: skin '%s' sets body size %.1f, which is not a whole multiple of its face's nominal %d." % [
				id, size, nominal
			]
		)
		return false
	return true


static func _nominal_size_for(font_path: String) -> int:
	return (
		NoggHeraldFontScript.NOMINAL_SIZE if font_path.contains("NoggHerald")
		else 12
	)
