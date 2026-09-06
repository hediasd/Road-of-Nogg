# World map editor

The authoring side of the world map. `WORLDMAP_DESIGN.md` covers how a region is **rendered**;
this note covers how one is **made**. Opened with WME-4 (tileset import) and grown by each
later item of the `worldmap-editor` cycle.

The editor is a **source-tree tool**. It never ships, it is not part of an exported build, and
several things below depend on that — see "Sheets are read as files" in §2.

## 1. The two grids, restated

From `WORLDMAP_DESIGN.md` §1, because everything here is expressed in them:

| | pixels | world | owns |
|---|---|---|---|
| **Tile** | 16 | 1 unit | walking, collision, elevation, prop anchoring — everything an entity can observe |
| **Cel** | 8 | ½ unit | art detail, four to a tile, observable by nothing |

A tileset declares which grid it is cut on, as `GRID_KIND: "tile"` or `GRID_KIND: "cel"`. The
ratio is a constant, not a per-sheet property.

The key is `GRID_KIND` and not `GRID` deliberately: a **region** already has a `GRID`, and it is
a different thing — an integer pixel size for its art, the very quantity the tile law demoted
from being a world measurement. Two fields named `GRID` meaning a string kind in one file and a
pixel count in another is precisely how "tile" came to mean three separate things before the
tile law. `probe_tile_law.gd` enforces that only the region catalog reads a bare `GRID`, and it
caught this collision when the field was first written.

## 2. Tilesets

A tileset is **a PNG plus a descriptor**. The PNG lives under `assets/worldmap/tilesets/`; the
descriptor is an entry in `data/worldmap/tilesets.json`, following the same named-catalog shape
as `regions.json`.

```
NAME            catalog id
DESCRIPTION     what this sheet is and where it came from
SHEET           res:// path to the PNG
GRID_KIND       "tile" (16 px) or "cel" (8 px) -- see below on the name
PALETTE_REGION  the region whose palette this sheet must stay inside
NEXT_ID         the id allocator; only ever rises
TILES           the ledger -- see §3
```

Per tile, the ledger carries `ID`, `HASH`, `CELL`, `LABEL`, `TERRAIN`, `AUTOTILE`, `VARIANT`,
`WALKABLE` and `LIFTABLE`.

`WALKABLE` and `LIFTABLE` are **authored now and read by nothing yet**. Both describe the art —
`LIFTABLE` gates whether Phase D may raise a tile at all, since only flat top-down art may be
lifted (`WORLDMAP_DESIGN.md` §8) — so retrofitting them later means revisiting every sheet ever
drawn. Authoring them from the first import costs a default field and saves that.

### Blank cells are padding, not tiles

A fully transparent cell is skipped and never gets an id. A sheet holding a number of tiles that
is not a multiple of its column count *has* padding in its last row, unavoidably; giving each
blank cell an id would fill the ledger with entries carrying no art, churning every time a tile
is added and the padding moves. It also makes deletion read correctly: removing a tile leaves a
hole rather than shortening the sheet, and a blank-as-tile reading would report that hole as
`changed` — the slot repainted to nothing — instead of `removed`.

The count of skipped cells is reported, not dropped silently. **A sheet that wants a deliberate
do-nothing tile must give it a pixel**: transparency means "no tile here", and it cannot also
mean "a tile that does nothing".

### Sheets are read as files, not as resources

`loadSheetImage()` reads the authored PNG through `Image.load()` rather than `ResourceLoader`.
A tile's identity is the hash of its pixels, so those pixels must come from a source no setting
can quietly change. Through the import pipeline, flipping a compression preset — or Godot's own
`detect_3d` deciding a sheet is used in 3D and switching it to a lossy VRAM format — would alter
every hash at once and report an entire sheet as `changed` for a reason having nothing to do
with the art. The bootstrap sheet's own generated `.import` carries `detect_3d/compress_to=1`,
so this is a live hazard, not a hypothetical one.

Nothing samples a tileset in a shader, so this costs nothing: sheets are read on the CPU by the
importer and by the baker that composes them into a region texture. It is that **region**
texture, not the sheet, that carries the import settings `WORLDMAP_DESIGN.md` §4 cares about.

The constraint — `res://` PNGs are readable as files in the source tree and not in an exported
build — is checked rather than assumed: an export refuses loudly instead of returning an
inexplicable `null`.

## 3. Tile identity, and why it is not the cell index

**The problem.** The obvious identity for a tile is where it sits in the sheet: row 3, column 7,
so id 31. Then an artist inserts one tile near the front. Every index after it shifts by one, and
every authored region that referenced them silently repaints itself — no failed load, no error
at any layer, nothing to notice until someone opens a region they did not touch and finds it
changed. Making that impossible is the whole point of this subsystem.

**Neither half of the fix is sufficient alone**, which is worth stating because each looks like
it might be:

- A **content hash** alone cannot tell two identical tiles apart. A sheet may legitimately hold
  the same pixels twice meaning two different things, and a hash says they are one tile.
- A **ledger of `id → cell`** alone cannot survive the sheet being re-cut. Move every tile one
  column right and it maps every id to the wrong pixels, confidently.

So the ledger carries both, and `reconcile()` matches a freshly cut sheet against it in falling
order of confidence. Each pass consumes what it matches, so a weaker pass can never claim a tile
a stronger one already explained:

| Pass | Condition | Verdict | Id |
|---|---|---|---|
| 1 | same hash, same cell | `unchanged` | kept |
| 2 | same hash, different cell | `moved` | kept |
| 3 | same cell, different hash | `changed` | kept |
| 4 | ledger entry left over | `removed` | retired |
| 5 | sheet cell left over | `added` | **allocated** |

Pass 5 is the only pass that allocates. `NEXT_ID` only ever rises, so an id belonging to a
removed tile is **never reissued** to a different one.

Passes 1 and 2 are separate rather than one hash lookup precisely because of duplicates: with
two identical tiles in a sheet, pass 1 pins each to the cell it already occupied, and only what
genuinely relocated is left for pass 2.

### The limitation duplicates impose

What holds: the count is preserved and the id **set** is preserved — neither duplicate collapses
into the other, which is what a hash-only scheme would do.

What does not hold, and cannot: **which** id lands on which duplicate is not guaranteed across a
re-cut. Two pixel-identical tiles have nothing in the sheet to distinguish them, so a re-export
that shifts them may permute their ids. Nothing observable changes — the pixels are the same —
*unless per-tile metadata differs between them*, e.g. the same blank green labelled `grass` on
one and `filler` on the other, in which case the labels may swap.

**An artist who needs two visually identical tiles to mean different things must make them
differ by a pixel.** This is recorded as a limitation rather than papered over, and
`probe_tileset_ids.gd` asserts what is actually true rather than the stronger guarantee.

### The importer reports; it does not resolve

Every outcome that is not an exact match is surfaced for a human. An importer that silently
decided a `changed` tile was really the same tile would be back to renumbering by inference. An
artist who re-exports a sheet with a one-pixel difference and sees the whole sheet reported as
`changed` needs to be told that, not have it hidden.

`importSheet()` therefore writes nothing. It returns the reconciliation and its report;
`applyImport()` accepts it, and `save()` persists. A re-import that reports `removed` across a
whole sheet is exactly the moment a human should be looking rather than a file changing.

### Hash collisions are detected, not assumed away

Ids hash to 16 hex characters — 64 bits, far past the birthday bound for the few hundred tiles a
sheet holds. `cutSheet()` does not trust that anyway: whenever two cells hash alike it compares
the actual bytes, so a genuine collision (different pixels, same hash) is reported. Identical
pixels hashing alike is just a duplicate tile, which is ordinary.

## 4. Palette validation lives at import, and only there

The ground shader snaps shadows to a 16-entry `palette[]` uniform, and the backdrop recolour was
built so a sky cannot drift off the region's colours (`WORLDMAP_DESIGN.md` §4). Validating a
sheet against its region's palette **once, at import**, is what makes it impossible for any later
brush stroke to place an illegal colour — so no stroke ever pays for the check.

The comparison is an **exact RGB match**, not a tolerance. Unlike the structure extractor's
colour key — which compares against colours that round-tripped through PNG import and so must
allow drift (`WORLDMAP_DESIGN.md` §9) — both sides here are read from imported PNGs the same way,
so a mismatch is a real one. Fully transparent pixels have no colour and are skipped.

## 5. The bootstrap tileset

`temp2_ground` is generated by cutting region `temp2` on the 16 px tile grid and deduplicating:
**40 unique tiles from 165 cells**, laid out 8 columns wide.

It is a **bootstrap, not a pipeline** — the same standing as the structure extractor in
`WORLDMAP_DESIGN.md` §9. A tileset cut mechanically out of hand-painted art is not semantically
clean: a tile may hold half a house, and none of the `TERRAIN` / `AUTOTILE` / `VARIANT` fields are
filled in yet. What it *is* is real art in a real palette, which is what the importer and every
later phase need in order to be exercised against something other than a synthetic fixture.

Cutting from `temp2` specifically buys WME-6 an exact target: **an authored region reassembled
from these tiles should bake back to `temp2` pixel for pixel.**

`temp2` is 15.5 tiles wide (`WORLDMAP_DESIGN.md` §1), so its rightmost 8 px column is a cel-grade
remainder and is not represented in a tile-grade sheet. `cutSheet()` reports that remainder
rather than silently dropping it.

## 6. The editor scene

`scenes/debug/WorldMapEditorScene.tscn`, driven by `WorldMapEditorController`, which **extends**
`WorldMapDebugController` rather than forking it — every framing preset, region picker, sun,
cloud and shadow control is the debug scene's own, unmodified.

### Layout

Two fixed side panels with the map's viewport in its own column between them. Neither panel is
given a fixed pixel width: both dock to their edge and size to their content's natural minimum,
and the controller sets the display's offsets from each panel's **settled** size. It listens to
both panels' `resized` signal rather than measuring once, because a `PanelContainer` holding many
sections does not settle in a single deferred call, and a one-shot measurement taken mid-settle
produced a stale split with a gap on one side and an overlap on the other.

Everything that sizes the render buffer, the framing readout or the sky backdrop reads
`_displaySize()` rather than the window, because in this scene the two are different rects.
`WorldMapDebugController` supplies that as an overridable accessor defaulting to the window size,
so its own behaviour is unchanged.

### Input ownership

`WorldMapEditorCamera` sits **inside** the "World" `SubViewport`, which is displayed through a
plain `TextureRect` rather than a `SubViewportContainer` — so it never receives a real,
engine-dispatched mouse or key event. Every mouse gesture and navigation key is therefore read by
the **controller**, which is a sibling of that viewport and does receive them, and applied to the
camera through its plain methods.

This is a live trap, not a historical note: an `_unhandled_input` override on a node inside that
viewport does nothing under real input while still passing any test that calls it by name. It
shipped once and was caught only by dispatching through `Input.parse_input_event()`.
`probe_editor_input_dispatch.gd` exists to keep it caught.

| Action | Control |
|---|---|
| Orbit | middle-drag, or Q/E |
| Snap yaw to 45° | Shift on middle-drag release |
| Pan (unclamped) | right-drag, or WASD |
| Zoom (dolly, never FOV) | wheel |
| Top-down orthographic | Tab |
| **Back to the shipping framing** | Space |
| Frame the region | F |

### Layers

`ground` and `overlay` only, both currently empty. Trimmed from eight at Gate 1 on request;
height, props, walkability, graph, lighting and annotations are deferred rather than cancelled
and return as their own items. Layers are declared as **data**, so adding one back is a table
entry rather than a code change — `probe_editor_shell.gd` iterates the table and needed no edit
when it went from eight rows to two.

A layer carries visibility and a lock. **Lock and `enabled` are different gates**: a lock refuses
the click outright, while `enabled` only governs whether a reached layer goes on to mutate
anything once there is something to mutate.
