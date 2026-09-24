## A spell's presentation-only VFX spec: which effect plays and how it adapts
## to the cast it is given.
##
## Authored as one nested object under `VFX` on a spell row in
## `data/spells.json`. Gameplay never reads it; `SpellReferences` passes the key
## through untouched because it does not know it. The legacy flat `VFX_PROFILE`
## string is still read, so a spell nobody has migrated keeps resolving.
##
## THE VOCABULARY IS DATA. `ASPECTS` below is the whole list of keys, their
## types, allowed values and defaults, and the parser is driven by it. Adding an
## aspect later — cast height, caster size, whatever the next question is — is
## one row there plus the effects that read it. Nothing between the spell data
## and the effect (adapter, bridge, catalog) needs to learn the new key, because
## they carry the spec object whole.
##
## A default of "" for an enum aspect means "the profile decides": an area-bound
## profile spreads over its footprint and a body-bound one does not, and a
## profile with travel beats stretches them with range. `resolved*` take the
## profile's own default for exactly that case.
##
## Errors are collected, never thrown and never silently repaired: an unknown
## key, a wrong type or a value outside the vocabulary is recorded in `errors`,
## and the aspect keeps its default so presentation still has something to play.
## The contract probe is what turns a recorded error into a failure.

class_name SpellVfxSpec
extends RefCounted

const KEY_BLOCK := "VFX"
const KEY_LEGACY_PROFILE := "VFX_PROFILE"

const KEY_PROFILE := "PROFILE"
const KEY_SPREAD := "SPREAD"
const KEY_ANCHOR := "ANCHOR"
const KEY_AREA_SCALING := "AREA_SCALING"
const KEY_RANGE_SCALING := "RANGE_SCALING"
const KEY_ELEMENTS := "ELEMENTS"

const SPREAD_CENTRE := "centre"
const SPREAD_EACH_TARGET := "each_target"
const ANCHOR_TARGET := "target"
const ANCHOR_CASTER_FRONT := "caster_front"
const AREA_SPREAD := "spread"
const AREA_NONE := "none"
const RANGE_TRAVEL := "travel"
const RANGE_FIXED := "fixed"

const TYPE_STRING := "string"
const TYPE_ENUM := "enum"
const TYPE_ELEMENTS := "elements"

## One row per aspect. `default` of "" (or an empty array) means the value is
## derived: from the catalog fallback for PROFILE, from the profile for the
## scaling enums, and from the spell's own element fields for ELEMENTS.
const ASPECTS: Array[Dictionary] = [
	{"key": KEY_PROFILE, "type": TYPE_STRING, "default": ""},
	{
		"key": KEY_SPREAD, "type": TYPE_ENUM,
		"values": [SPREAD_CENTRE, SPREAD_EACH_TARGET], "default": SPREAD_CENTRE,
	},
	{
		"key": KEY_ANCHOR, "type": TYPE_ENUM,
		"values": [ANCHOR_TARGET, ANCHOR_CASTER_FRONT], "default": ANCHOR_TARGET,
	},
	{
		"key": KEY_AREA_SCALING, "type": TYPE_ENUM,
		"values": [AREA_SPREAD, AREA_NONE], "default": "",
	},
	{
		"key": KEY_RANGE_SCALING, "type": TYPE_ENUM,
		"values": [RANGE_TRAVEL, RANGE_FIXED], "default": "",
	},
	{"key": KEY_ELEMENTS, "type": TYPE_ELEMENTS, "default": []},
]

## Every element name `BattleMeshFactory.elementColor` and the cube palettes
## know. `none` is legal: it is what a spell with no element resolves to.
const KNOWN_ELEMENTS: Array[String] = [
	"fire", "water", "ice", "wind", "earth", "wood",
	"thunder", "darkness", "light", "steel", "none",
]

## Aspect key -> value, defaults filled in.
var values: Dictionary = {}
## Aspect key -> true for every aspect the spell authored itself.
var explicit: Dictionary = {}
var errors: PackedStringArray = PackedStringArray()


## Parses a normalized spell reference. Never fails: problems land in `errors`.
static func fromReference(reference: Dictionary) -> SpellVfxSpec:
	var spec := SpellVfxSpec.new()
	spec._applyDefaults()
	var spellName := str(reference.get("NAME", "<unnamed spell>"))
	var legacyProfile := str(reference.get(KEY_LEGACY_PROFILE, "")).strip_edges()
	var hasBlock := reference.has(KEY_BLOCK) and reference[KEY_BLOCK] != null
	if hasBlock:
		var block = reference[KEY_BLOCK]
		if block is Dictionary:
			spec._applyBlock(block as Dictionary, spellName)
		else:
			spec.errors.append("%s: %s must be an object" % [spellName, KEY_BLOCK])
		if not legacyProfile.is_empty():
			spec.errors.append(
				"%s: author either %s or %s, not both" % [spellName, KEY_BLOCK, KEY_LEGACY_PROFILE]
			)
	elif not legacyProfile.is_empty():
		spec.values[KEY_PROFILE] = legacyProfile
		spec.explicit[KEY_PROFILE] = true
	if not spec.explicit.has(KEY_ELEMENTS):
		spec.values[KEY_ELEMENTS] = derivedElements(reference)
	return spec


## A spec with every default and nothing authored: what a caller with no spell
## reference at all (the debug scene previewing a bare profile) plays.
static func defaults(profileID: String = "", elementNames: Array[String] = []) -> SpellVfxSpec:
	var spec := SpellVfxSpec.new()
	spec._applyDefaults()
	spec.values[KEY_PROFILE] = profileID
	var names: Array[String] = []
	names.assign(elementNames if not elementNames.is_empty() else ["none"])
	spec.values[KEY_ELEMENTS] = names
	return spec


## ELEMENT when the spell names one, otherwise the distinct elements of its
## damage lines in order, otherwise `none`. This is what lets a dual-element
## spell such as a steel-and-wind strike show both colours without authoring it.
static func derivedElements(reference: Dictionary) -> Array[String]:
	var names: Array[String] = []
	var element := str(reference.get("ELEMENT", "none")).strip_edges().to_lower()
	if not element.is_empty() and element != "none":
		names.append(element)
		return names
	for rawLine in reference.get("DAMAGE_LINES", []):
		if not (rawLine is Dictionary):
			continue
		var lineElement := str((rawLine as Dictionary).get("element", "")).strip_edges().to_lower()
		if not lineElement.is_empty() and lineElement != "none" and not names.has(lineElement):
			names.append(lineElement)
	if names.is_empty():
		names.append("none")
	return names


func isValid() -> bool:
	return errors.is_empty()


func profileID() -> String:
	return str(values[KEY_PROFILE])


func spread() -> String:
	return str(values[KEY_SPREAD])


func anchor() -> String:
	return str(values[KEY_ANCHOR])


## The authored value, or the profile's own default when the spell left it open.
func resolvedAreaScaling(profileDefault: String) -> String:
	var value := str(values[KEY_AREA_SCALING])
	return value if not value.is_empty() else profileDefault


func resolvedRangeScaling(profileDefault: String) -> String:
	var value := str(values[KEY_RANGE_SCALING])
	return value if not value.is_empty() else profileDefault


func elements() -> Array[String]:
	var names: Array[String] = []
	names.assign(values[KEY_ELEMENTS])
	return names


## Plain data, for manifests, probes and logs.
func toDictionary() -> Dictionary:
	var result := {}
	for aspect: Dictionary in ASPECTS:
		var key := str(aspect["key"])
		var value = values[key]
		result[key] = (value as Array).duplicate() if value is Array else value
	return result


## Unit horizontal direction from `origin` toward the nearest candidate, ties
## broken by the lowest id. This is what "in front of" means for units that have
## no facing: the battle adapter passes living hostiles, the debug scene passes
## its one target, and both get the same answer from the same rule.
##
## With no candidate away from `origin`, `fallback` is used when it has a
## horizontal component, and world +X otherwise, so the result is always a
## usable direction and always the same for the same inputs.
static func frontToward(
		origin: Vector3,
		candidatePositions: Array[Vector3],
		candidateIDs: Array[int],
		fallback: Vector3 = Vector3.ZERO) -> Vector3:
	var bestIndex := -1
	var bestDistance := INF
	for index: int in range(candidatePositions.size()):
		var offset := candidatePositions[index] - origin
		offset.y = 0.0
		var distance := offset.length()
		if distance <= 0.001:
			continue
		var candidateID := candidateIDs[index] if index < candidateIDs.size() else index
		var bestID := (
			candidateIDs[bestIndex] if bestIndex >= 0 and bestIndex < candidateIDs.size()
			else bestIndex
		)
		if (
			distance < bestDistance - 0.0001
			or (absf(distance - bestDistance) <= 0.0001 and candidateID < bestID)
		):
			bestDistance = distance
			bestIndex = index
	if bestIndex >= 0:
		var toward := candidatePositions[bestIndex] - origin
		toward.y = 0.0
		return toward.normalized()
	var flat := Vector3(fallback.x, 0.0, fallback.z)
	if flat.length() > 0.001:
		return flat.normalized()
	return Vector3.RIGHT


func _applyDefaults() -> void:
	for aspect: Dictionary in ASPECTS:
		var fallback = aspect["default"]
		values[str(aspect["key"])] = (
			(fallback as Array).duplicate() if fallback is Array else fallback
		)


func _applyBlock(block: Dictionary, spellName: String) -> void:
	var known := {}
	for aspect: Dictionary in ASPECTS:
		known[str(aspect["key"])] = aspect
	for rawKey in block.keys():
		var key := str(rawKey)
		if not known.has(key):
			errors.append("%s: unknown %s key %s" % [spellName, KEY_BLOCK, key])
			continue
		var aspect: Dictionary = known[key]
		var problem := _problemWith(aspect, block[rawKey])
		if not problem.is_empty():
			errors.append("%s: %s.%s %s" % [spellName, KEY_BLOCK, key, problem])
			continue
		var value = block[rawKey]
		if str(aspect["type"]) == TYPE_ELEMENTS:
			var names: Array[String] = []
			for name in value:
				names.append(str(name).to_lower())
			values[key] = names
		else:
			values[key] = str(value)
		explicit[key] = true


## Why `value` is not legal for `aspect`, or empty when it is.
static func _problemWith(aspect: Dictionary, value) -> String:
	match str(aspect["type"]):
		TYPE_STRING:
			if not (value is String) or str(value).strip_edges().is_empty():
				return "must be a non-empty string"
		TYPE_ENUM:
			if not (value is String):
				return "must be a string"
			if not (aspect["values"] as Array).has(str(value)):
				return "is %s, expected one of %s" % [str(value), str(aspect["values"])]
		TYPE_ELEMENTS:
			if not (value is Array) or (value as Array).is_empty():
				return "must be a non-empty array of element names"
			var seen := {}
			for name in value:
				if not (name is String):
					return "must contain only strings"
				var lowered := str(name).to_lower()
				if not KNOWN_ELEMENTS.has(lowered):
					return "names unknown element %s" % str(name)
				if seen.has(lowered):
					return "names %s twice" % str(name)
				seen[lowered] = true
	return ""
