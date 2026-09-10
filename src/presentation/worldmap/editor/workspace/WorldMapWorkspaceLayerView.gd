## Which layers the editor is currently SHOWING, and the filtered copy that shows them.
##
## THE AUTHORED DOCUMENT IS NEVER FILTERED. Hiding a layer must not be able to reach a save, a
## bake or an export -- that is the way a view control becomes data loss. So the controller keeps
## its real `WorldMapTileData` complete and untouched, and this hands back a SEPARATE deep copy
## with the hidden layers removed, purely to be baked for display. Save and export never see the
## copy, and the canonical baker never bakes it.
##
## WHAT CAN AND CANNOT BE HIDDEN, honestly. Ground, overlay and detail art are composited into the
## baked texture, so removing them from a copy and re-baking really does hide them. Objects are
## already an editor-only preview node, so hiding them is hiding that node. Terrain height is
## GEOMETRY, not art: there is no height overlay to switch off, and pretending to hide it would
## either flatten the terrain -- lying about the export -- or do nothing. The tactical layer has no
## visualization in this editor at all; its values are battle terrain ids that nothing draws.
## `canHide()` answers that question per layer, and the two that answer false get an explanation
## in the UI rather than a toggle that moves and changes nothing.
##
## THE COST, stated rather than hidden: a visibility change rebuilds the whole filtered copy and
## re-bakes it, and while any layer is hidden every committed stroke does the same. That is a full
## bake where the unfiltered path does a dirty-cell flush. It is paid only while a filter is
## actually on -- with everything visible, which is the normal state, the controller keeps its
## existing incremental path and this class costs nothing.

class_name WorldMapWorkspaceLayerView
extends RefCounted

const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")

## Layers whose art really is separable in the editor's view.
const HIDEABLE_ART := ["ground", "overlay", "detail"]

var _hidden: Dictionary = {}


## Whether this layer has an independent view the editor can switch off. See the class note; the
## caller shows an explanation instead of a toggle when this is false.
static func canHide(layerID: String, objectLayerID: String) -> bool:
	return HIDEABLE_ART.has(layerID) or layerID == objectLayerID


## Why a layer cannot be hidden, for the tooltip that replaces its toggle. "" when it can be.
static func whyNotHideable(layerID: String, objectLayerID: String, heightLayerID: String) -> String:
	if canHide(layerID, objectLayerID):
		return ""
	if layerID == heightLayerID:
		return (
			"Terrain height is geometry, not art. There are no height guides to switch off, and "
			+ "hiding it would either flatten the terrain or misrepresent what the export "
			+ "contains."
		)
	return (
		"This layer has no editor view of its own -- nothing draws it -- so there is nothing for "
		+ "a visibility control to switch off. It is still saved and exported."
	)


func setHidden(layerID: String, hidden: bool) -> void:
	if hidden:
		_hidden[layerID] = true
	else:
		_hidden.erase(layerID)


func isHidden(layerID: String) -> bool:
	return _hidden.has(layerID)


func hiddenLayerIDs() -> Array[String]:
	var result: Array[String] = []
	for layerID: String in _hidden:
		result.append(layerID)
	result.sort()
	return result


## True while anything is hidden -- the one question the controller asks to decide whether it is
## on the cheap incremental path or the filtered one.
func isFiltering() -> bool:
	return not _hidden.is_empty()


func anyArtHidden() -> bool:
	for layerID: String in _hidden:
		if HIDEABLE_ART.has(layerID):
			return true
	return false


func reset() -> void:
	_hidden.clear()


## A deep copy of `source` with the hidden ART layers removed, for display only. Round-tripped
## through the document's own serialization rather than copied field by field, so a layer kind
## this class has never heard of still survives the copy intact.
##
## Returns null when nothing is hidden: the caller should be showing the real document's own bake,
## and building an identical copy to display would be pure waste.
func filteredCopy(source: WorldMapTileData) -> WorldMapTileData:
	if source == null or not anyArtHidden():
		return null
	# Removed from the SERIALIZED form rather than by erasing `copy.layers` afterwards. A document
	# keeps its layer ORDER in a list beside the `layers` dictionary, and the baker walks that
	# list; erasing only the dictionary entry leaves the id in the order and the bake then indexes
	# a layer that is no longer there. Dropping the layer before the document is rebuilt keeps the
	# two halves consistent, whatever else a future layer kind stores.
	var raw := source.toDictionary()
	var kept: Array = []
	for entry in raw.get("LAYERS", []):
		var layerID := str((entry as Dictionary).get("ID", ""))
		if HIDEABLE_ART.has(layerID) and _hidden.has(layerID):
			continue
		kept.append(entry)
	raw["LAYERS"] = kept
	return MapDataScript.fromDictionary(raw)


## What the status line says about the current view, or "" when everything is showing. The editor
## must never be quietly filtered: if a layer is hidden, the workspace says so.
func describe() -> String:
	var hidden := hiddenLayerIDs()
	if hidden.is_empty():
		return ""
	return "Hidden in this view: %s. Saves and exports still contain every layer." % ", ".join(hidden)
