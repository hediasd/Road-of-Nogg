## Maps a player command's id to its authored icon texture.
##
## Mirrors `StatusIconRegistry`: empty until real art lands, with a drawn
## placeholder (`ActionIcons`) filling every id absent here, so an empty table
## is a working action ring rather than a row of blank squares. Dropping the
## art in later is a table edit, not a code change.
##
## Keyed by `PlayerTurnController`'s own entry ids (`move`, `undo_move`,
## `attack`, `magic`, `pass`) rather than a second vocabulary — the ring reads
## `menuEntries()` directly, so there is exactly one name for each command.
##
## **Author icons at `SOURCE_PX` square**, for the same reason `StatusIconRegistry`
## gives: whatever hover/rest scale the ring ends up using, an icon authored at
## this size lands on an exact device-pixel multiple at the moment it matters.

class_name ActionIconRegistry
extends RefCounted

const SOURCE_PX := 32

## action id -> `res://` path of a square texture.
const ICON_PATHS := {}


## The authored texture for an action, or `null` when none is registered and
## the caller should fall back to a drawn placeholder.
static func texture_for(action_id: String) -> Texture2D:
	var path: String = ICON_PATHS.get(action_id.to_lower(), "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource = load(path)
	return resource as Texture2D
