# Hex tileset authoring

`temp2_hex32_starter` is the project's small, clean starter sheet for flat-top hex editing. It is a reference for authoring and picker work, not a terrain system or a complete transition set.

## Rebuild the starter

From the repository root, run:

```powershell
powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/worldmap_editor/build_hex_starter.gd -Marker "WORLD MAP HEX STARTER BUILT"
```

Verify the generated sheet, catalog entry, exact colours, frame hashes and lattice geometry with:

```powershell
powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/worldmap_editor/probe_hex_starter.gd -Marker "WORLD MAP HEX STARTER OK"
```

The generator reads `temp2.png` through `WorldMapTilesetCatalog.loadSheetImage()` and refuses to use substitute colours. Its three exact RGB inputs are land `#FFD363`, sea `#37AEAE`, and grass `#BDD106`; their expected source counts are 11,569, 27,200, and 3,654 respectively. It writes `temp2_hex32_starter.png`, upserts only its catalog record, and writes the editable guide. The PNG is an RGBA 160 × 96 sheet with 15 32 × 32 frames in five columns and three rows. It has zero margin and spacing, no gutters, no resampling, and no donor terrain pixels.

The guide file is deliberately not production art. Its named `guides` group contains frame rectangles, the same hex polygons, and centre crosses. Hide that group before exporting art: no guide pixels belong in the PNG.

## Geometry and packing

Each frame has vertices `(32,16)`, `(24,32)`, `(8,32)`, `(0,16)`, `(8,0)`, `(24,0)`. The full 32 × 32 frame is intentionally a stretched flat-top hex used by this project’s shipping camera; it is not a claim about regular hex proportions or an industry certification. Sheet packing is rectangular. Map placement is separate: adjacent world columns step 24 px, rows step 32 px, and odd columns are dropped 16 px.

The transparent corners are required. Alpha is either 0 outside the hex or 255 inside it; there are no outlines, shadows, extrusions, or antialiasing. Use nearest filtering. `GRID_KIND: "tile"` describes the game grid, while `FRAME_PX: 32` describes the art frame; neither changes the other.

## Frames and edges

Frames are row-major and use stable IDs `t000` through `t014`. Frames 0–2 are solid land, sea, and grass. Frames 3–8 are land with one sea edge; frames 9–14 are grass with one land edge. Edge indices are: 0 lower-right, 1 bottom, 2 lower-left, 3 upper-left, 4 top, and 5 upper-right. Edge `e` joins vertex `e` to vertex `(e + 1) % 6`; its colour band is the inside pixels less than four pixels from that segment.

These are manual edge examples, **not a complete autotile or Wang set**. Junctions, corners, transitions, and gameplay rules must be authored in a later, explicitly scoped increment. Tile labels and `TERRAIN` fields describe the visible example only: no walkability, elevation, combat, or travel meaning is inferred from art.

## Use in the editor

The generated source sheet is
`assets/worldmap/tilesets/temp2_hex32_starter.png`; its editable geometry guide is
`assets/worldmap/tilesets/templates/hex32_guides.svg`; and its stable frame IDs live in
`data/worldmap/tilesets/temp2_hex32_starter.json`. Keep those three artifacts aligned when
deriving a future sheet.

In the [World map editor](./WORLDMAP_EDITOR.md), choose `temp2_hex32_starter` when creating a map,
then select art directly from the visible tilesheet. The source map stores stable tileset and tile
IDs rather than embedded pixels; see [Hex map source format](./HEX_MAP_FORMAT.md). Battle meaning
belongs to explicit authored data and is added only through Export Battle.

## Technical references

- [Tiled: Editing tilesets](https://docs.mapeditor.org/en/stable/manual/editing-tilesets/) explains image-sheet frames, margin, and spacing.
- [Tiled: TMX map format](https://docs.mapeditor.org/en/latest/reference/tmx-map-format/) distinguishes hex map staggering from atlas packing.
- [Red Blob Games: Hexagonal Grids](https://www.redblobgames.com/grids/hexagons/implementation.html) documents axial/cube layouts and deliberately chosen geometry.
- [Tiled: Automapping](https://doc.mapeditor.org/en/latest/manual/automapping/) documents its hex limitation, one reason this starter does not promise automation.
