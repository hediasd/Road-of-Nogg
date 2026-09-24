## Presentation-only registry for active spell effects.
##
## The authored non-cube effects remain on disk while the spell VFX direction is
## being reconsidered, but they are deliberately absent from this registry.
## Gameplay and the debug picker therefore expose only the cube language: the
## two elemental cube rituals, which are the fallback for every spell without
## a cube profile, and the 24 cube placeholder profiles, which each family
## lists in its own catalog under `cube_placeholders/`.
##
## A spell chooses its effect, and how that effect adapts to the cast, through
## its presentation-only VFX spec (`SpellVfxSpec`). Cube placeholder rows carry
## generic metadata — `family`, `binding`, `composition` — so a caller supplies
## a profile's anchors, bounds and footprint from data, never from its name.

class_name SpellVfxCatalog
extends RefCounted

const ElementalCubeRitualEffectScript = preload(
		"res://src/presentation/effects/ElementalCubeRitualEffect.gd")
const ElementalCubeRitualProfileScript = preload(
		"res://src/presentation/effects/ElementalCubeRitualProfile.gd")
const SpellVfxSpecScript = preload("res://src/presentation/effects/SpellVfxSpec.gd")
const DEFAULT_PROFILE_ID := ElementalCubeRitualProfileScript.CROWNBURST_PROFILE_ID

## Each family's catalog script, whose static `entries()` returns its rows.
## Adding a family is one line here; adding a profile is one line in its
## family's catalog.
const CUBE_PLACEHOLDER_CATALOGS: Array[Script] = [
	preload("res://src/presentation/effects/cube_placeholders/travel/TravelCatalog.gd"),
	preload("res://src/presentation/effects/cube_placeholders/impact/ImpactCatalog.gd"),
	preload("res://src/presentation/effects/cube_placeholders/control/ControlCatalog.gd"),
	preload("res://src/presentation/effects/cube_placeholders/restore/RestoreCatalog.gd"),
]

## `binding` value for the two rituals: they draw on the caster and need
## neither a target body nor a footprint.
const BINDING_SOURCE := "source"

## Built once: the family catalogs instance a composition per row to read its
## metadata, and `resolve` runs on every cast. Holds only scripts, callables
## and plain values, so it owns no render resources to release at exit.
static var _entries: Array[Dictionary] = []


static func entries() -> Array[Dictionary]:
	if _entries.is_empty():
		_entries = _buildEntries()
	return _entries.duplicate()


static func _buildEntries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		{
			"profile_id": ElementalCubeRitualProfileScript.CROWNBURST_PROFILE_ID,
			"display_name": "Elemental Cube Crownburst",
			"factory": Callable(ElementalCubeRitualEffectScript, "createCrownburst"),
			"action_hold_fraction": ElementalCubeRitualProfileScript.ACTION_HOLD_FRACTION,
			"max_live": ElementalCubeRitualProfileScript.MAX_LIVE_RITUALS,
			"family": "ritual",
			"binding": BINDING_SOURCE,
		},
		{
			"profile_id": ElementalCubeRitualProfileScript.SPIRAL_PROFILE_ID,
			"display_name": "Elemental Cube Spiral Invocation",
			"factory": Callable(ElementalCubeRitualEffectScript, "createSpiral"),
			"action_hold_fraction": ElementalCubeRitualProfileScript.ACTION_HOLD_FRACTION,
			"max_live": ElementalCubeRitualProfileScript.MAX_LIVE_RITUALS,
			"family": "ritual",
			"binding": BINDING_SOURCE,
		},
	]
	for catalog: Script in CUBE_PLACEHOLDER_CATALOGS:
		for row: Dictionary in catalog.call("entries"):
			rows.append(row)
	return rows


## Resolves the presentation fallback for a normalized spell reference.
## An active profile named by the spell's spec (or its legacy `VFX_PROFILE`)
## is kept. Blank, unknown, and parked authored profiles use the cube rituals
## so the temporary direction remains entirely in presentation.
static func profileForSpell(reference: Dictionary) -> String:
	var explicitProfile := SpellVfxSpecScript.fromReference(reference).profileID()
	if isActiveProfile(explicitProfile):
		return explicitProfile
	return (
		ElementalCubeRitualProfileScript.CROWNBURST_PROFILE_ID
		if isOffensiveSpell(reference)
		else ElementalCubeRitualProfileScript.SPIRAL_PROFILE_ID
	)


## The spell's full presentation spec with its profile resolved to the one
## that will actually play. Errors the spell authored stay in `errors`.
static func specForSpell(reference: Dictionary) -> SpellVfxSpec:
	var spec := SpellVfxSpecScript.fromReference(reference)
	spec.values[SpellVfxSpecScript.KEY_PROFILE] = profileForSpell(reference)
	return spec


static func isActiveProfile(profile_id: String) -> bool:
	for entry: Dictionary in _cached():
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
	for entry: Dictionary in _cached():
		if entry["profile_id"] == profile_id:
			return entry
	for entry: Dictionary in _cached():
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


static func _cached() -> Array[Dictionary]:
	if _entries.is_empty():
		_entries = _buildEntries()
	return _entries


## How a resolved profile is bound to a cast: `source` for the rituals, else
## the composition's binding (`two_anchor`, `body`, `area` or `volume`).
static func bindingOf(profile_id: String) -> String:
	return str(resolve(profile_id).get("binding", BINDING_SOURCE))


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
