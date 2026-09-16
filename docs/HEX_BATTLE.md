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
  flicker against it and cover the art. The terrain instance receives a
  battle-only material which clips transparent texels and draws a one-screen-
  pixel, low-opacity lattice. The shared world-map material is not changed.
- Without terrain, the grey fill is drawn as the fallback tactical surface.
- Both looks sit in a recessed bed inside a substantial floating game board.
  Its broad Mossstone rim rises slightly above the terrain, then breaks through
  a sloped outer shoulder into a deep wall. The muted olive-grey top is warmer
  than the animated blue sky and less saturated than the cyan, lime and yellow
  terrain, so the tiles remain the focus. A flat exported terrain plane is
  cropped to its painted region; a sculpted export may keep geometry outside
  the region, but the battle material discards it.

The alpha cutout matters. Exported terrain sheets deliberately contain clear
pixels between the staggered edge hexes. Sampling their RGB as opaque colour
turns those pixels into black saw teeth; discarding them reveals the recessed
Mossstone bed instead.

**Markers.** Movement range, targets, threat, previews and the cursor are
translucent hex fills. Each also carries a rim in its own colour at nearly full
opacity, edged in dark. A translucent fill over painted art takes on the colour
under it; the rim keeps the hue readable.

An ordinary mouse hover gets one quiet amber wash and rim on the cell under the
pointer. It disappears while tactical aim or camera dragging owns the pointer,
so it never competes with actionable range and target markers.

**Units.** Every battle model carries a small flattened translucent contact
shadow. It follows the model during movement and grounds the piece without
enabling real-time stage shadows. Units are enlarged uniformly to 112% in the
hex battle, and their plinth alone widens another 6% across the board plane,
putting it just over half a cell's width; cell geometry and shared portrait
models do not change. A dual-element body uses one normalized model-space
diagonal from foot to opposite shoulder, continuous across all of its component
meshes; the same model factory keeps battle pieces and portraits consistent.
The lowest deterministic party-commander ID on each team is presented as that
team's single captain. Its existing base keeps the same geometry and footprint
as its teammates; only the top base layer receives a small warm-metal tint and
finish shift. The simulator's per-party commander ownership does not change.
These hex-only presentation treatments belong to
`HexBattleVisualAdapter`, so portraits and other `MonsterModelFactory` callers
keep their existing scale and base appearance.

**Picking.** Nothing about terrain changes picking. The controller picks a cell
by projecting cell centres through the stage, which already handles
letterboxing. The pick bodies stay on their own collision layer
(`HexBattleBoardView.PICK_COLLISION_LAYER`) and keep answering rays when the
fill is hidden. The exported scene carries no collision.

**Camera.** The camera frames the valid cells, not the art, and reserves extra
space for the left and lower-right HUD stacks. Mouse wheel zooms; middle drag
orbits and pitches; right drag pans; double middle-click eases back to the
opening frame. Q and E still move by exact sixty-degree detents, but ease into
the final angle. Orthographic is the default. The Graphics panel can switch to
perspective without moving the board focus or visibly jumping its scale;
Graphics Reset returns to orthographic. Orthographic zoom changes the visible
size while its physical camera remains well behind the rotating board, so a
near corner cannot cross the near clipping plane. Mouse camera events are
consumed before hover and tactical input so a drag cannot accidentally aim or
inspect. Raw mouse deltas are coalesced and applied once per rendered frame;
high-polling mice must not force the SubViewport camera to rebuild for every
input packet.

**CPU playback.** CPU deliberation runs as a low-priority worker task, separate
from the main thread that renders the sky, board, UI and combat effects. The
worker reads a fixed battle state and returns a command; only the main thread
may apply it. Pausing prevents application, and returning to setup retires the
old task so its result cannot enter a restarted battle.

**Backdrop.** The battle retains the animated sky shader's original blue
gradient, bright clouds, density and speed. The compact slab supplies the
board's silhouette; the sky is not darkened to do that job.

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

To export a map's scene without the editor, see `DEVELOPMENT.md`, "Exporting a
map's battle products without the editor".

`scripts/hex_battle/probe_board_terrain.gd` (`HXB_BOARD_TERRAIN_OK`) checks the
structure, decorators and camera gesture contract. Whether the one-pixel grid,
slab margin, shadows and captain finish read well is a rendered check, not a
probe.
