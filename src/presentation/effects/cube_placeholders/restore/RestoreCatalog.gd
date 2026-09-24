## The restore and transform family's six profiles as catalog rows, in the
## `SpellVfxCatalog.entries()` format plus the binding metadata a caller needs
## to supply each one's anchors without a profile-name conditional.
##
## The debug scene loads this directly with
## `--catalog-script=res://src/presentation/effects/cube_placeholders/restore/RestoreCatalog.gd`.

extends RefCounted

const Effect = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderEffect.gd")
const Profile = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderProfile.gd")

const FAMILY := "restore"
const COMPOSITIONS: Array[Script] = [
	preload("res://src/presentation/effects/cube_placeholders/restore/RepairMend.gd"),
	preload("res://src/presentation/effects/cube_placeholders/restore/InterceptingGuard.gd"),
	preload("res://src/presentation/effects/cube_placeholders/restore/Siphon.gd"),
	preload("res://src/presentation/effects/cube_placeholders/restore/Cleanse.gd"),
	preload("res://src/presentation/effects/cube_placeholders/restore/BlinkTransfer.gd"),
	preload("res://src/presentation/effects/cube_placeholders/restore/ChargeRelease.gd"),
]


static func entries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for script: Script in COMPOSITIONS:
		rows.append(rowFor(script, FAMILY))
	return rows


## One catalog row for a composition script. `action_hold_fraction` is the
## impact beat at the reference distance; a playback reports its own warped
## hold through `get_action_hold_seconds()`.
static func rowFor(script: Script, family: String) -> Dictionary:
	var composition = script.new()
	return {
		"profile_id": composition.profileID(),
		"display_name": composition.displayName(),
		"factory": Callable(Effect, "create").bind(script),
		"action_hold_fraction": composition.impactTime(),
		"max_live": Profile.MAX_LIVE_PLAYBACKS,
		"family": family,
		"binding": composition.binding(),
		"composition": script,
	}
