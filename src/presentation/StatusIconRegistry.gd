## Maps a status effect name to its authored icon texture.
##
## Empty until real art lands, exactly like `MonsterVisualRegistry` — and for the
## same reason: the lookup and its fallback are the part worth building ahead of
## the assets, so dropping the art in later is a table edit rather than a code
## change. `StatusEffectIcons` supplies a drawn placeholder for every name absent
## here, so an empty table is a working game rather than a blank row of squares.
##
## **Author icons at `SOURCE_PX` square.** That size is not arbitrary: a badge
## rests at half it and doubles on hover, so a hovered icon lands at exactly 1:1
## with its source and the player sees the art at native resolution at the moment
## they are actually looking at it. An icon authored at another size still works
## — it is scaled to fit — but loses that property.

class_name StatusIconRegistry
extends RefCounted

## The square each icon is authored at, in pixels. See the note above before
## changing it: `NoggTheme.STATUS_BADGE_HOVER_SCALE` is chosen against this.
const SOURCE_PX := 32

## effect name (lowercase) -> `res://` path of a square texture.
const ICON_PATHS := {}


## The authored texture for an effect, or `null` when none is registered and the
## caller should fall back to a drawn placeholder.
static func texture_for(effect_name: String) -> Texture2D:
	var path: String = ICON_PATHS.get(effect_name.to_lower(), "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource = load(path)
	return resource as Texture2D
