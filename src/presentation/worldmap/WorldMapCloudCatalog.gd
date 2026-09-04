## Available world map cloud sets.
##
## Deliberately a flat list rather than a JSON catalog, for the same reason `WorldMapSkyCatalog`
## is: there is one set and it is chosen by eye in the debug scene. If clouds ever become
## per-region this should move to `data/worldmap/` beside the regions, in the same shape.
##
## A CLOUD AND ITS SHADOW ARE ONE ENTRY, not two lists indexed in parallel. The artist drew each
## shadow separately from its cloud -- `shadow_a` is not `cloud_a` and `shadow_b` is a row
## shorter than `cloud_b`, because a shadow seen on the ground at this pitch is flatter than the
## thing casting it. Pairing them structurally is what stops a renderer scaling one shape into
## the other and losing the foreshortening the art already carries.
##
## THE ART IS DRAWN ON AN 8 PX BLOCK GRID with a 1 px outline over it: every piece resolves to
## 11x5 (or 11x4) cells of 8x8, and the only cells that are not one flat colour are the ten
## corner cells the outline steps through. Both facts pin the native scale at 1:1 against MAP
## pixels -- 88x40 px is 11x5 of temp2's 8 px tiles. Displayed at any other scale the 8 px
## blocks stop being square and the 1 px outline stops being 1 px. See `pieceTiles()`.

class_name WorldMapCloudCatalog
extends RefCounted

const TEMP2 := "temp2"

## Every piece is 8 px-block art. `tile_pixels` is the grid it was drawn against, and it is what
## makes `pieceTiles()` a whole number rather than a rounding.
const BLOCK_PIXELS := 8

const SETS := [
	{
		"id": TEMP2,
		"label": "temp2 clouds",
		"description": "Two blocky clouds and the two ground shadows drawn for them, on "
			+ "region temp2's own seven colours. The shadows are painted in the region's "
			+ "shadowed sea and shadowed sand -- the artist drew shadowed TERRAIN rather "
			+ "than a translucent overlay, which is the same answer the standing "
			+ "structures' shadows reached. Their colours are therefore a reference and not "
			+ "the output: a fixed-colour shadow sprite is only correct over the terrain it "
			+ "was painted for, so the renderer takes these pieces for their SHAPE.",
		"texture": "res://assets/worldmap/clouds/temp2_clouds.png",
		"pieces": [
			{"cloud": Rect2i(16, 16, 88, 40), "shadow": Rect2i(16, 64, 88, 40)},
			{"cloud": Rect2i(152, 16, 88, 40), "shadow": Rect2i(152, 72, 88, 32)},
		],
	},
]


static func ids() -> Array[String]:
	var result: Array[String] = []
	for entry in SETS:
		result.append(str(entry["id"]))
	return result


static func labels() -> Array[String]:
	var result: Array[String] = []
	for entry in SETS:
		result.append(str(entry["label"]))
	return result


static func has(setID: String) -> bool:
	return ids().has(setID)


static func textureFor(setID: String) -> Texture2D:
	var entry := _entry(setID)
	if entry.is_empty():
		return null
	return ResourceLoader.load(str(entry["texture"])) as Texture2D


## The set's pieces, each `{cloud: Rect2i, shadow: Rect2i}`. Empty for an unknown set.
static func pieces(setID: String) -> Array:
	var entry := _entry(setID)
	return [] if entry.is_empty() else (entry["pieces"] as Array)


static func pieceCount(setID: String) -> int:
	return pieces(setID).size()


## One piece by index, wrapped. Callers hold an index rather than a rect so a cloud and its
## shadow cannot drift apart.
static func pieceAt(setID: String, index: int) -> Dictionary:
	var list := pieces(setID)
	if list.is_empty():
		return {}
	return list[posmod(index, list.size())]


## A piece's cloud size in MAP PIXELS at its native 1:1 scale -- which is simply its rect size,
## stated as a function so callers stop reaching into the rect for it. The renderers size clouds
## from this rather than from a free width, because the art is 8 px blocks under a 1 px outline
## and neither survives a fractional scale. Divide by the REGION's `tile_pixels` for tiles; do
## not divide by `BLOCK_PIXELS`, which is the grid the art was drawn on and equals temp2's tile
## size only by coincidence.
static func pieceMapPixels(setID: String, index: int) -> Vector2i:
	var piece := pieceAt(setID, index)
	if piece.is_empty():
		return Vector2i.ZERO
	return (piece["cloud"] as Rect2i).size


static func _entry(setID: String) -> Dictionary:
	for entry in SETS:
		if entry["id"] == setID:
			return entry
	return {}
