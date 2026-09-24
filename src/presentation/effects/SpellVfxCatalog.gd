## Presentation-only registry for active spell effects.
##
## The authored non-cube effects remain on disk while the spell VFX direction is
## being reconsidered, but they are deliberately absent from this registry.
## Gameplay and the debug picker therefore expose only the cube language.

class_name SpellVfxCatalog
extends RefCounted

const ElementalCubeRitualEffectScript = preload(
		"res://src/presentation/effects/ElementalCubeRitualEffect.gd")
const ElementalCubeRitualProfileScript = preload(
		"res://src/presentation/effects/ElementalCubeRitualProfile.gd")
const DEFAULT_PROFILE_ID := ElementalCubeRitualProfileScript.CROWNBURST_PROFILE_ID


static func entries() -> Array[Dictionary]:
	return [
		{
			"profile_id": ElementalCubeRitualProfileScript.CROWNBURST_PROFILE_ID,
			"display_name": "Elemental Cube Crownburst",
			"factory": Callable(ElementalCubeRitualEffectScript, "createCrownburst"),
			"action_hold_fraction": ElementalCubeRitualProfileScript.ACTION_HOLD_FRACTION,
			"max_live": ElementalCubeRitualProfileScript.MAX_LIVE_RITUALS,
		},
		{
			"profile_id": ElementalCubeRitualProfileScript.SPIRAL_PROFILE_ID,
			"display_name": "Elemental Cube Spiral Invocation",
			"factory": Callable(ElementalCubeRitualEffectScript, "createSpiral"),
			"action_hold_fraction": ElementalCubeRitualProfileScript.ACTION_HOLD_FRACTION,
			"max_live": ElementalCubeRitualProfileScript.MAX_LIVE_RITUALS,
		},
	]


## Resolves the presentation fallback for a normalized spell reference.
## Only active cube profiles are preserved. Blank, unknown, and parked authored
## profiles use the cube rituals so the temporary direction remains entirely in
## presentation and does not require rewriting spell data.
static func profileForSpell(reference: Dictionary) -> String:
	var explicitProfile := str(reference.get("VFX_PROFILE", "")).strip_edges()
	if isActiveProfile(explicitProfile):
		return explicitProfile
	return (
		ElementalCubeRitualProfileScript.CROWNBURST_PROFILE_ID
		if isOffensiveSpell(reference)
		else ElementalCubeRitualProfileScript.SPIRAL_PROFILE_ID
	)


static func isActiveProfile(profile_id: String) -> bool:
	for entry: Dictionary in entries():
		if str(entry["profile_id"]) == profile_id:
			return true
	return false


static func isOffensiveSpell(reference: Dictionary) -> bool:
	if int(reference.get("DAMAGE", 0)) > 0:
		return true
	for rawLine in reference.get("DAMAGE_LINES", []):
		if rawLine is Dictionary and int(rawLine.get("damage", 0)) > 0:
			return true
	if not str(reference.get("INFLICTS_STATUS", "")).strip_edges().is_empty():
		return true
	for rawEffect in reference.get("EFFECTS", []):
		if rawEffect is Dictionary and bool(rawEffect.get("NEGATIVE", false)):
			return true
	var targetType := str(reference.get("TARGET_TYPE", "single")).to_lower()
	return targetType != "self" and not bool(reference.get("HEALS", false))


static func resolve(profile_id: String) -> Dictionary:
	for entry: Dictionary in entries():
		if entry["profile_id"] == profile_id:
			return entry
	for entry: Dictionary in entries():
		if entry["profile_id"] == DEFAULT_PROFILE_ID:
			return entry
	assert(false, "Spell VFX catalog lacks its cube fallback.")
	return {}


static func resolvedProfileId(profile_id: String) -> String:
	return str(resolve(profile_id)["profile_id"])


static func actionHoldFraction(profile_id: String) -> float:
	return float(resolve(profile_id)["action_hold_fraction"])


static func maxLive(profile_id: String) -> int:
	return int(resolve(profile_id)["max_live"])


## `overrides` are live-authoring tunables from the VFX debug scene, empty for
## every gameplay caller. They are passed to the factory rather than applied
## afterwards because effects build their geometry inside `createPlayback`; a
## value handed over later would be consumed by nothing.
static func create(
		profile_id: String,
		parent: Node3D,
		world_position: Vector3,
		color: Color,
		overrides: Dictionary = {}) -> VfxPlayback:
	var entry := resolve(profile_id)
	return entry["factory"].call(
		parent, world_position, color, overrides
	) as VfxPlayback
