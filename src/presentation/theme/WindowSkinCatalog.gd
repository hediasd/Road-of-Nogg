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
		"status_cell_offset_units": [0.0, 96.0, 192.0]
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
		# Provisional: measured against Nogg Terminal at a 6-unit inset, so both
		# terms are wrong for this skin. Re-measured once Herald is actually
		# under the HUD.
		"status_cell_offset_units": [0.0, 96.0, 192.0]
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
