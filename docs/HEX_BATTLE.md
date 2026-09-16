# Hex battle

How the hex battle screen is put together. This file grows as the battle
presentation settles; sections not written yet belong to later work.

## The board over authored terrain

A hex battle draws the map its author painted. The tactical hexes sit on top as
an overlay.

**Where the terrain comes from.** A battle map names its exported scene in
`SOURCE.VISUAL_SCENE_PATH`. When a battle starts, `HexBattleController` asks
`HexBattleStage.loadTerrain(map)` to instance that scene inside the stage's own
render world, as `BattleTerrain`. It is lit by the stage light and seen by the
stage camera, like the units.

**Alignment.** The scene goes in at the origin with no offset.
`HexBattleLayout.cellCenter` and the editor's `WorldMapHexGrid.cellCentre` put
every cell at the same X/Z, and the export lays its art out from the same
origin. If terrain ever looks shifted under the board, one of those two is
wrong. Do not add a correction in the battle.

**What the board looks like.**

- With terrain, the grey hex fill is hidden. It would sit flat on the ground,
  flicker against it and cover the art. One mesh of thin cell outlines is drawn
  instead: a dark edge with a pale inner line, so the lattice shows over light
  and dark art alike.
- Without terrain, the grey fill is drawn as before and there are no outlines.

**Markers.** Movement range, targets, threat, previews and the cursor are
translucent hex fills. Each also carries a rim in its own colour at nearly full
opacity, edged in dark. A translucent fill over painted art takes on the colour
under it; the rim keeps the hue readable.

**Picking.** Nothing about terrain changes picking. The controller picks a cell
by projecting cell centres through the stage, which already handles
letterboxing. The pick bodies stay on their own collision layer
(`HexBattleBoardView.PICK_COLLISION_LAYER`) and keep answering rays when the
fill is hidden. The exported scene carries no collision.

**Camera.** The camera frames the valid cells, not the art. The exported ground
runs far past the map as a fogged skirt, and framing that would shrink the
board.

**When the terrain cannot be drawn.** A battle still starts on the grey board.
`loadTerrain` reports one of these:

| Status | Meaning | Notice |
|---|---|---|
| `loaded` | The scene is in the world. | none |
| `headless_only` | The map declares no scene on purpose (technical maps). | none |
| `missing` | The scene file is not on disk. Generated scenes are gitignored, so a fresh checkout has none. | Re-export the map. |
| `unreadable` | The file is not an exported map scene. | Re-export the map. |
| `mismatched` | The scene was exported for a different lattice or source. | Re-export the map. |

The notice stays on the status line under whatever the battle is saying.

Known gap: `BattleMapFactory` still refuses to load a map whose declared scene
is not on disk (`missing_visual_resource`), so the `missing` case cannot yet be
reached from the setup screen. The stage handles it; the factory has to stop
refusing first.

To export a map's scene without the editor, see `DEVELOPMENT.md`, "Exporting a
map's battle products without the editor".

`scripts/hex_battle/probe_board_terrain.gd` (`HXB_BOARD_TERRAIN_OK`) checks the
structure. Whether the board reads well is a rendered check, not a probe.
