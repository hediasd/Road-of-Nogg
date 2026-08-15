## Presentation-only registry for previewable spell effects.

class_name SpellVfxCatalog
extends RefCounted

const SpellCastAuraScript = preload("res://src/presentation/effects/SpellCastAura.gd")
const IceStormEffectScript = preload("res://src/presentation/effects/IceStormEffect.gd")
const FireStormEffectScript = preload("res://src/presentation/effects/FireStormEffect.gd")
const MagentaReductionEffectScript = preload(
		"res://src/presentation/effects/MagentaReductionEffect.gd")
const IceTargetEncasementEffectScript = preload(
		"res://src/presentation/effects/IceTargetEncasementEffect.gd")
const AuroraVeilEffectScript = preload(
		"res://src/presentation/effects/AuroraVeilEffect.gd")
const SolarStormEffectScript = preload(
		"res://src/presentation/effects/SolarStormEffect.gd")
const GENERIC_AURA_PROFILE_ID := SpellCastAuraProfile.PROFILE_ID


static func entries() -> Array[Dictionary]:
	return [
		{
			"profile_id": GENERIC_AURA_PROFILE_ID,
			"display_name": "Spell Cast Aura",
			"factory": Callable(SpellCastAuraScript, "createPlayback"),
			"action_hold_fraction": SpellCastAuraProfile.ACTION_HOLD_FRACTION,
			"max_live": SpellCastAuraProfile.MAX_LIVE_AURAS,
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
		{
			"profile_id": MagentaReductionProfile.PROFILE_ID,
			"display_name": "Magenta Reduction",
			"factory": Callable(MagentaReductionEffectScript, "createPlayback"),
			"action_hold_fraction": MagentaReductionProfile.ACTION_HOLD_FRACTION,
			"max_live": MagentaReductionProfile.MAX_LIVE_IMPLOSIONS,
		},
		{
			"profile_id": IceTargetEncasementProfile.PROFILE_ID,
			"display_name": "Ice Target Encasement",
			"factory": Callable(IceTargetEncasementEffectScript, "createPlayback"),
			"action_hold_fraction": IceTargetEncasementProfile.ACTION_HOLD_FRACTION,
			"max_live": IceTargetEncasementProfile.MAX_LIVE_ENCASEMENTS,
		},
		{
			"profile_id": AuroraVeilProfile.PROFILE_ID,
			"display_name": "Aurora Veil",
			"factory": Callable(AuroraVeilEffectScript, "createPlayback"),
			"action_hold_fraction": AuroraVeilProfile.ACTION_HOLD_FRACTION,
			"max_live": AuroraVeilProfile.MAX_LIVE_VEILS,
		},
		{
			"profile_id": SolarStormProfile.PROFILE_ID_V1,
			"display_name": "Solar Storm v1 (wave)",
			"factory": Callable(SolarStormEffectScript, "createV1"),
			"action_hold_fraction": SolarStormProfile.ACTION_HOLD_FRACTION,
			"max_live": SolarStormProfile.MAX_LIVE_STORMS,
		},
		{
			"profile_id": SolarStormProfile.PROFILE_ID_V2,
			"display_name": "Solar Storm v2 (pulse)",
			"factory": Callable(SolarStormEffectScript, "createV2"),
			"action_hold_fraction": SolarStormProfile.ACTION_HOLD_FRACTION,
			"max_live": SolarStormProfile.MAX_LIVE_STORMS,
		},
		{
			"profile_id": SolarStormProfile.PROFILE_ID_V2_1,
			"display_name": "Solar Storm v2.1 (+loops)",
			"factory": Callable(SolarStormEffectScript, "createV2_1"),
			"action_hold_fraction": SolarStormProfile.ACTION_HOLD_FRACTION,
			"max_live": SolarStormProfile.MAX_LIVE_STORMS,
		},
		{
			"profile_id": SolarStormProfile.PROFILE_ID_V2_2,
			"display_name": "Solar Storm v2.2 (+heat)",
			"factory": Callable(SolarStormEffectScript, "createV2_2"),
			"action_hold_fraction": SolarStormProfile.ACTION_HOLD_FRACTION,
			"max_live": SolarStormProfile.MAX_LIVE_STORMS,
		},
		{
			"profile_id": SolarStormProfile.PROFILE_ID_V2_3,
			"display_name": "Solar Storm v2.3 (+flare)",
			"factory": Callable(SolarStormEffectScript, "createV2_3"),
			"action_hold_fraction": SolarStormProfile.ACTION_HOLD_FRACTION,
			"max_live": SolarStormProfile.MAX_LIVE_STORMS,
		},
		{
			"profile_id": SolarStormProfile.PROFILE_ID,
			"display_name": "Solar Storm v2.4 (full)",
			"factory": Callable(SolarStormEffectScript, "createPlayback"),
			"action_hold_fraction": SolarStormProfile.ACTION_HOLD_FRACTION,
			"max_live": SolarStormProfile.MAX_LIVE_STORMS,
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
