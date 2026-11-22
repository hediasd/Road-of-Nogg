## The cross-filter sparkle aura's row, in `SpellVfxCatalog.entries()` format.
## `SpellVfxCatalog.AUTHORED_CATALOGS` lists this script, so the row is in the
## active set and in the debug picker; Shine selects it as its placeholder.

extends RefCounted

const Effect = preload("res://effects/CrossFilterSparkleEffect.gd")
const Profile = preload("res://effects/CrossFilterSparkleProfile.gd")


static func entries() -> Array[Dictionary]:
	return [
		{
			"profile_id": Profile.PROFILE_ID,
			"display_name": Profile.DISPLAY_NAME,
			"factory": Callable(Effect, "create"),
			"action_hold_fraction": Profile.ACTION_HOLD_FRACTION,
			"max_live": Profile.MAX_LIVE_PLAYBACKS,
			"family": "authored",
			"binding": "body",
		},
	]
