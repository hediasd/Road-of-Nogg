# Hex map source format

The clean World Map Editor saves source maps as UTF-8 JSON files ending in
`.noggmap.json`. This is the editor's authoring format. It is not TMX, a
portable asset bundle or the battle-runtime map schema.

```json
{
	"CONTENT": {
		"DESCRIPTION": "First battlefield draft",
		"FORMAT_VERSION": 1,
		"LAYERS": [],
		"LAYOUT": "hex_flat",
		"NAME": "River pass",
		"PALETTE_REGION": "temp2",
		"SIZE_TILES": [19, 14]
	},
	"DOCUMENT_ID": "550e8400-e29b-41d4-a716-446655440000",
	"FORMAT": "nogg.hexmap",
	"REVISION": 1,
	"VERSION": 1
}
```

The example omits `FOG_COLOR` and `VOID_COLOR` only to stay short; real v1
CONTENT includes every field produced by `WorldMapTileData.toDictionary()`.
The complete `CONTENT` is its existing format-version-1 data: name,
description, size, `hex_flat` layout, palette metadata and ordered RLE layers.
It supports `grid`, `list`, `heights`, `detail` and `water` layers. Existing
layer documentation defines those values; this wrapper owns document identity
and compatibility.

`FORMAT` and envelope `VERSION` identify this wrapper. `CONTENT.FORMAT_VERSION`
identifies the legacy layer encoding and is independently versioned. Version 1
requires both values to be 1. The reader rejects unknown versions, layer kinds,
duplicate IDs, malformed RLE, invalid dimensions and extra structural fields.
It never opens an unsupported map as a lossy approximation. Opaque dictionaries
inside `list` `ITEMS` are retained unchanged by the layer model.

`DOCUMENT_ID` is a lowercase UUIDv4 generated when a new map or Save As copy is
created. It is stable across rename and move, and is unrelated to gameplay
entity IDs. `NAME` is the human label; it is independent of both ID and
filename. A fresh or explicitly imported legacy hex map has revision 0 in
memory. Its first successful source save writes revision 1. Each changed
successful Save increments it; an unchanged Save does not write or increment.
Save As writes a new UUID at revision 1 and switches the editor to that copy
only after the write succeeds.

The canonical source text is `JSON.stringify(record, "\t", true)` with no
trailing newline. The source fingerprint is `sha256:` plus SHA-256 of those
UTF-8 bytes, including document ID and revision. Paths, recent-file state and
recovery metadata belong to the editor session, not to this JSON.

Map cells use the existing flat-top `odd_q_offset` coordinates: size is columns
by rows, layer storage is row-major, each cell is 2 by 2 world units, columns
step 1.5 units, rows step 2 units, and odd columns drop 1 unit.

Every border of a map is **outward**: the long odd columns stick out past their
even neighbours at both the top and the bottom. So row 0 of every even column is
not a cell. Layer storage stays the full `columns × rows` rectangle, but those
slots are always `-`: they read as empty, refuse paint, get no ground surface
and are `0` in an exported `VALID_MASK`. A file that still carries paint there
opens with it cleared, and the editor says how many values it cleared. New maps
use an odd column count, so both side columns are the short kind; every size
the New Map dialog offers already is. Tile art is a
project catalog dependency, represented by stable catalog tile and tileset IDs;
source maps do not embed or copy texture files. A missing project asset is an
actionable editing dependency, not a reason to replace or erase its IDs.

Legacy raw `WorldMapTileData` version-1 hex JSON can be brought in through the
explicit Import Legacy command. It becomes a new unsaved `.noggmap.json`
record; the original stays unchanged. Legacy square maps are refused by this
foundation editor rather than converted automatically.

Saving source does not generate a texture, scene or battle map. Explicit battle
export builds those derived artifacts from a saved source snapshot and carries
the source ID, revision and fingerprint across the existing runtime boundary.
