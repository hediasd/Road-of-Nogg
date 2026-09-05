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

## The skin a fresh install opens in, and the fallback whenever a requested
## id is unknown. Brigandine Plate is the look this project is aiming at, so
## it is what a player who never opens the dropdown should see; `nogg` stays
## selectable rather than becoming dead weight.
const DEFAULT := BRIGANDINE_PLATE

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
		# Terminal, not Herald. The reference's text face has a one-pixel
		# stroke -- an ink run-length histogram over its dialogue panel is 469
		# runs of one pixel against 21 of two -- and `NoggHeraldFont`'s own
		# header describes Herald as the *display* face, "two pixels of stroke",
		# for "big outlined text over the board". Matching the reference's
		# proportional widths cost a doubled stroke weight, and weight is what
		# the eye reads first: the skin came out chunky where the reference is
		# fine. Terminal is monospaced rather than proportional, so it is not
		# the reference's face either, but it is the one this repo has whose
		# stroke matches. §4a records the trade.
		"font_path": "res://assets/Fonts/NoggTerminal/NoggTerminal.res",
		"body_size_units": 12.0,
		# Unchanged at 14: the pitch is measured off the reference and does not
		# follow the face. It now sits on a 12-unit cell rather than a 13-unit
		# one, so the leading grows from one unit to two.
		"row_height_units": 14.0,
		"corner_radius_units": 0.0,
		"frame_ring_units": 1.5,
		"content_inset_units": 11.0,
		# Neutral black at the reference's measured 0.55, replacing a warm brown
		# at 0.78. The RGB was the defect: it was byte-identical to `nogg`'s
		# (0.075, 0.058, 0.042), inherited rather than measured, so the skin
		# carried the house look's warmth into a panel that has none. Sampling
		# straight down through the reference panel's top border, the map under
		# it goes (0.067, 0.455, 0.165) to (0.035, 0.196, 0.098) -- the same hue,
		# roughly halved. The reference panel is a neutral tint over the map,
		# not a slab with a colour of its own.
		#
		# The alpha returns to the measured value too. A previous pass raised it
		# to 0.78 for legibility over a lit 3D board and judged 0.55 unreadable,
		# which was a real finding -- but it was made against a warm fill, and
		# hue and alpha were never varied independently. If text over the board
		# is unstable again, this is the token to move, not the hue.
		"window_fill": Color(0.0, 0.0, 0.0, 0.55),
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
		# Back to Terminal's offsets, because the face is Terminal again. The
		# [0, 76, 152] these replace were derived for Herald's proportional
		# advances and are too tight for a monospaced cell: the offsets are a
		# function of the face and nothing else, so the two skins sharing a face
		# share these.
		"status_cell_offset_units": [0.0, 96.0, 192.0],
		# Every width below is measured output, by one stated rule: the worst real
		# string this skin can render, plus at least five design units of
		# headroom, rounded up to a multiple of ten. The headroom is not
		# decoration -- `PROMPT_WIDTH` once shipped 76 device pixels short of a
		# real status line, and a catalog gaining one longer monster name is all
		# it takes to truncate a window sized to its exact worst case.
		#
		# Re-measured for Terminal at 12 by the harness UI_DESIGN 8 describes,
		# rebuilt from that section. Raw requirements: command 84, spell 328,
		# prompt 550, forecast 326, status 258, pager 94, card 314.
		#
		# The prompt is the one that moved hardest -- 340 to 560 -- and it is
		# the same trap 4a already records. The worst real prompt is not the
		# obvious "Choose an action, or Pass to end the turn." (358) but
		# `PlayerTurnController`'s confirm line with the longest monster name
		# substituted in: "Confirm Attack at Polar Weather Wizard, or cancel to
		# choose again." at 550. Nothing marquees it -- the overflow marquee in
		# NoggWindow 7b is for cursor-focused *list rows* -- so a short prompt
		# window clips instead of scrolling.
		"command_width_units": 90.0,
		"spell_width_units": 340.0,
		"prompt_width_units": 560.0,
		"forecast_width_units": 340.0,
		"status_window_width_units": 270.0,
		# "12 / 12" between two arrows, under Terminal, needs 94.
		"pager_width_units": 100.0,
		"deep_card_width_units": 320.0,
		# Still eleven. Capacity is a function of `content_inset_units` and
		# `row_height_units` only -- `window_height_units()` is inset * 2 +
		# rows * pitch -- and the face change moved neither, so the card's
		# vertical fit below the prompt is exactly what it was.
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


## Matches `RenderPresetCatalog.labels()`/`.values()`/`.description()`'s exact
## shape and naming, rather than the `label_for`/`description_for` this file
## used before anything called it: the two catalogs feed the same
## `BattleGraphicsMenu._add_option()` helper, and a second naming convention
## for one job is the drift this project's own dropdown-building code already
## avoids elsewhere.
static func labels() -> Array[String]:
	var result: Array[String] = []
	for skin in SKINS:
		result.append(str(skin["label"]))
	return result


static func values() -> Array[String]:
	var result: Array[String] = []
	for skin in SKINS:
		result.append(str(skin["id"]))
	return result


static func description(id: String) -> String:
	for skin in SKINS:
		if str(skin["id"]) == id:
			return str(skin["description"])
	return description(DEFAULT)


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
