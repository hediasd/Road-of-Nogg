## Presentation-only registry for previewable spell effects.

class_name SpellVfxCatalog
extends RefCounted

const SpellCastAuraScript = preload("res://src/presentation/effects/SpellCastAura.gd")
const GENERIC_AURA_PROFILE_ID := ""


static func entries() -> Array[Dictionary]:
	return [{
		"profile_id": GENERIC_AURA_PROFILE_ID,
		"display_name": "Spell Cast Aura",
		"factory": Callable(SpellCastAuraScript, "createPlayback")
	}]


static func create(
		profile_id: String,
		parent: Node3D,
		world_position: Vector3,
		color: Color) -> VfxPlayback:
	for entry: Dictionary in entries():
		if entry["profile_id"] == profile_id:
			return entry["factory"].call(parent, world_position, color) as VfxPlayback
	assert(false, "Unknown spell VFX profile: %s" % profile_id)
	return null
