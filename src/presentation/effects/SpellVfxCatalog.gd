## Presentation-only registry for previewable spell effects.

class_name SpellVfxCatalog
extends RefCounted

const SpellCastAuraScript = preload("res://src/presentation/effects/SpellCastAura.gd")
const IceStormEffectScript = preload("res://src/presentation/effects/IceStormEffect.gd")
const FireStormEffectScript = preload("res://src/presentation/effects/FireStormEffect.gd")
const GENERIC_AURA_PROFILE_ID := ""
const GENERIC_ACTION_HOLD_FRACTION := 0.6


static func entries() -> Array[Dictionary]:
	return [
		{
			"profile_id": GENERIC_AURA_PROFILE_ID,
			"display_name": "Spell Cast Aura",
			"factory": Callable(SpellCastAuraScript, "createPlayback"),
			"action_hold_fraction": GENERIC_ACTION_HOLD_FRACTION,
			"max_live": 0,
		},
		{
			"profile_id": IceStormProfile.PROFILE_ID,
			"display_name": "Ice Area Storm",
			"factory": Callable(IceStormEffectScript, "createPlayback"),
			"action_hold_fraction": IceStormProfile.ACTION_HOLD_FRACTION,
			"max_live": IceStormProfile.MAX_LIVE_STORMS,
		},
		{
			"profile_id": FireStormProfile.PROFILE_ID,
			"display_name": "Fire Area Storm",
			"factory": Callable(FireStormEffectScript, "createPlayback"),
			"action_hold_fraction": FireStormProfile.ACTION_HOLD_FRACTION,
			"max_live": FireStormProfile.MAX_LIVE_STORMS,
		},
	]


static func resolve(profile_id: String) -> Dictionary:
	var generic_entry: Dictionary = {}
	for entry: Dictionary in entries():
		if entry["profile_id"] == GENERIC_AURA_PROFILE_ID:
			generic_entry = entry
		if entry["profile_id"] == profile_id:
			return entry
	assert(not generic_entry.is_empty(), "Spell VFX catalog lacks its generic fallback.")
	return generic_entry


static func resolvedProfileId(profile_id: String) -> String:
	return str(resolve(profile_id)["profile_id"])


static func actionHoldFraction(profile_id: String) -> float:
	return float(resolve(profile_id)["action_hold_fraction"])


static func maxLive(profile_id: String) -> int:
	return int(resolve(profile_id)["max_live"])


static func create(
		profile_id: String,
		parent: Node3D,
		world_position: Vector3,
		color: Color) -> VfxPlayback:
	var entry := resolve(profile_id)
	return entry["factory"].call(parent, world_position, color) as VfxPlayback
