## The one place a hex battle turns a resolved cast into a playing effect.
##
## WHAT IT IS FOR. `SpellVfxCatalog.create(profile, parent, position, colour, overrides)` is the
## square path's entry point, and it takes a single world position -- everything about WHERE the
## spell landed beyond that comes later, through `setFootprint(radiusInTiles, ...)`, which is the
## call that cannot survive the move to hex. This bridge is the hex entry point: it takes the
## resolved cells themselves and hands each profile whichever of the two shapes it can actually
## use.
##
## EVERY REACHABLE PROFILE IS DISPATCHED, AND NONE IS SILENTLY DOWNGRADED. `SpellVfxCatalog` lists
## fourteen profile ids across nine effect classes. Nine of the fourteen are Solar Storm's own
## version ladder, which all share one class. Each id resolves here to either its donor, unchanged,
## or to the hex subclass of its donor -- never to a generic flash and never to nothing, which the
## item text forbids in as many words. `coverage()` reports that mapping as data so the probe can
## assert it rather than trust it.
##
## THE CLASSIFICATION, AND WHAT DECIDES IT. An effect is AREA-BOUND if it declares `setFootprint`
## -- that is not a guess about what an effect looks like, it is the literal question "does this
## effect size itself from a tile radius", and a tile radius is the only thing hex breaks. Every
## other effect is BODY-BOUND: it draws on a caster or a target through `configure_cast_context`,
## which carries world positions and model bounds that were never tile-scaled and are correct on
## either topology. So body-bound effects are reused with no hex variant at all, which is why
## there are five subclasses and not nine.
##
## WHAT THE BRIDGE DOES NOT TOUCH. It writes to no donor, no shared texture, no shared material,
## no theme token and no mesh factory. It constructs, configures and returns; the caller owns the
## playback's lifecycle exactly as `SpellVfxCatalog`'s caller already does.

class_name HexBattleVfxBridge
extends RefCounted

const HexIceStormEffectScript = preload(
	"res://src/presentation/battle/effects/HexIceStormEffect.gd")
const HexFireStormEffectScript = preload(
	"res://src/presentation/battle/effects/HexFireStormEffect.gd")
const HexMagentaReductionEffectScript = preload(
	"res://src/presentation/battle/effects/HexMagentaReductionEffect.gd")
const HexSolarStormEffectScript = preload(
	"res://src/presentation/battle/effects/HexSolarStormEffect.gd")
const HexAuroraVeilEffectScript = preload(
	"res://src/presentation/battle/effects/HexAuroraVeilEffect.gd")
const HexVfxFootprintScript = preload(
	"res://src/presentation/battle/effects/HexVfxFootprint.gd")

## How a profile is served.
const BINDING_AREA := "area"
const BINDING_BODY := "body"

## Profile id -> the hex factory that serves it. Keyed by the donor class each profile resolves
## to, since Solar Storm's six ids all share one.
const AREA_FACTORIES := {
	"IceStormEffect": "createHexPlayback",
	"FireStormEffect": "createHexPlayback",
	"MagentaReductionEffect": "createHexPlayback",
	"SolarStormEffect": "createHexPlayback",
	"AuroraVeilEffect": "createHexPlayback",
}


## Every catalog profile, with how this bridge serves it. Data rather than a code path, so the
## probe can assert coverage over the catalog as it stands rather than over a list written here
## that could fall behind it.
static func coverage() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry: Dictionary in SpellVfxCatalog.entries():
		var profileID := str(entry["profile_id"])
		rows.append({
			"profile_id": profileID,
			"display_name": str(entry["display_name"]),
			"binding": BINDING_AREA if _isAreaProfile(profileID) else BINDING_BODY,
			"hex_class": _hexClassNameFor(profileID),
		})
	return rows


static func servesProfile(profileID: String) -> bool:
	for entry: Dictionary in SpellVfxCatalog.entries():
		if str(entry["profile_id"]) == profileID:
			return true
	return false


## Whether a profile sizes itself from a tile radius, and so needs the hex footprint rather than
## just a position. Answered by asking the donor, not by a list kept here.
static func _isAreaProfile(profileID: String) -> bool:
	return not _hexClassNameFor(profileID).is_empty()


static func _hexClassNameFor(profileID: String) -> String:
	var entry := SpellVfxCatalog.resolve(profileID)
	if entry.is_empty():
		return ""
	var factory: Callable = entry["factory"]
	var donor = factory.get_object()
	if donor == null:
		return ""
	var donorPath := str((donor as Script).resource_path)
	var donorName := donorPath.get_file().get_basename()
	if not AREA_FACTORIES.has(donorName):
		return ""
	return "Hex%s" % donorName


## Builds the playback for a resolved cast.
##
## `footprint` is the affected cells including the empty ones -- passing only the cells that held a
## target is the failure this whole item exists to prevent. It may be null for a profile with no
## area, and is ignored by every body-bound one.
##
## The returned playback has been given its cast context and its footprint but has NOT been
## played: seeding and mode are the caller's, exactly as with `SpellVfxCatalog.create`.
static func createPlayback(
	profileID: String,
	parent: Node3D,
	worldPosition: Vector3,
	color: Color,
	footprint: HexVfxFootprint = null,
	context: VfxCastContext = null,
	overrides: Dictionary = {},
	groundSpan := 0.0,
	areaShape := "circle"
) -> VfxPlayback:
	var hexClass := _hexClassNameFor(profileID)
	var playback: VfxPlayback = null
	if hexClass.is_empty():
		# Body-bound: the donor is already correct on a hex board, so it is used unchanged.
		playback = SpellVfxCatalog.create(profileID, parent, worldPosition, color, overrides)
	else:
		playback = _createHexPlayback(hexClass, parent, worldPosition, color, overrides)

	if playback == null:
		return null
	if context != null:
		playback.configure_cast_context(context)
	if footprint != null and not footprint.isEmpty() and playback.has_method("setHexFootprint"):
		playback.call("setHexFootprint", footprint, groundSpan, areaShape)
	return playback


static func _createHexPlayback(
	hexClass: String, parent: Node3D, worldPosition: Vector3, color: Color, overrides: Dictionary
) -> VfxPlayback:
	match hexClass:
		"HexIceStormEffect":
			return HexIceStormEffectScript.createHexPlayback(parent, worldPosition, color, overrides)
		"HexFireStormEffect":
			return HexFireStormEffectScript.createHexPlayback(parent, worldPosition, color, overrides)
		"HexMagentaReductionEffect":
			return HexMagentaReductionEffectScript.createHexPlayback(
				parent, worldPosition, color, overrides)
		"HexSolarStormEffect":
			return HexSolarStormEffectScript.createHexPlayback(parent, worldPosition, color, overrides)
		"HexAuroraVeilEffect":
			return HexAuroraVeilEffectScript.createHexPlayback(parent, worldPosition, color, overrides)
	return null


## Convenience for a caller holding cells and a map rather than a built footprint.
static func footprintFor(cells: Array, map: BattleMapDefinition) -> HexVfxFootprint:
	return HexVfxFootprintScript.fromCells(cells, map)
