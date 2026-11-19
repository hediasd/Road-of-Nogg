## Preview row for the cross-filter sparkle aura, in `SpellVfxCatalog.entries()`
## format. No spell selects this effect yet, so it is not in the gameplay
## registry; the debug scene loads it with
## `--catalog-script=res://effects/CrossFilterSparkleCatalog.gd`.

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
			"binding": "body",
		},
	]
