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

### Hashing is mipmap-blind, and `hashCell()` is the only place that decides

`Image.get_region()` **preserves mipmaps**. A 16 px cell taken from an image carrying a mip
chain returns **1364 bytes, not 1024** — the region brings 256 + 64 + 16 + 4 + 1 pixels with it.
Region art imports with `mipmaps/generate=true` (§4 of `WORLDMAP_DESIGN.md` wants them for the
far field) while a sheet read from its PNG has none, so cutting the same tile from a region and
from a sheet produced two different hashes for byte-identical pixels.

That is not hypothetical: it made the first authored region match **0 of its 165 cells** against
a ledger built from its own art. The failure reads as impossible, because the bytes differ in
*length* rather than content — a byte-by-byte walk over the overlap reports zero differences.

So every hash of a cell goes through `hashCell()`, and every image being cut goes through
`normalise()` first: RGBA8, uncompressed, no mip chain. One definition of "a tile's bytes",
because two callers normalising differently is precisely how this bug happened.

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
| Frame the region | F -- fits both axes at the display's own aspect, in either projection |
| Undo | Ctrl+Z |
| Redo | Ctrl+Y or Ctrl+Shift+Z |

### Fitting a region: both axes, not the larger of two world numbers

`frameRegion()` originally fit only `max(region.width, region.height)`, against no aspect at
all, using a factor of 0.6 -- which is a *shrink*, not a margin, so it cropped a portrait-shaped
viewport on whichever axis the max didn't cover. Fixed to project the region's four corners onto
the camera's own screen-space right/up axes -- correct at any orbit orientation, since world
width/height do not track the camera once it turns -- and take the larger of the two resulting
extents.

**Perspective needed a second correction the first fix missed.** A flat region seen from an
oblique camera is not all at one depth: the near edge sits closer to the camera than the focus,
the far edge further. Measuring each corner's extent from the focus alone -- as the orthographic
branch correctly does, since parallel projection has no depth-dependent foreshortening -- silently
underestimates the distance the *nearer* corners need under perspective, where a fixed lateral
offset subtends a larger angle at a shorter depth. The escape this produced was small (a fraction
of a percent of the frame) and would not have been caught by eye; `probe_editor_input_dispatch.gd`'s
fit check, which asserts all four corners land inside the frame rather than merely looking framed,
caught it. The fix solves each corner's own required distance -- `lateral / tan(halfFov) -
depthOffset` -- and takes the maximum before applying one multiplicative margin, which is safe
because a larger distance strictly increases every corner's margin at once.

### Layers

`ground` and `overlay` only, both currently empty. Trimmed from eight at Gate 1 on request;
height, props, walkability, graph, lighting and annotations are deferred rather than cancelled
and return as their own items. Layers are declared as **data**, so adding one back is a table
entry rather than a code change — `probe_editor_shell.gd` iterates the table and needed no edit
when it went from eight rows to two.

A layer carries visibility and a lock. **Lock and `enabled` are different gates**: a lock refuses
the click outright, while `enabled` only governs whether a reached layer goes on to mutate
anything once there is something to mutate.

## 7. The authored region format

An authored region is a text file under `data/worldmap/authored/<name>.json`, read and written
by `WorldMapTileData`. Unlike the catalogs, that is a **live model** rather than a record:
brushes mutate it, the history stack records deltas of it, and the baker reads it.

```
FORMAT_VERSION  bumped only when a change cannot be read by the previous reader
NAME            the region id
DESCRIPTION     what this map is
SIZE_TILES      [w, h] in walk tiles
PALETTE_REGION  whose palette its tilesets must stay inside
FOG_COLOR       inherited by the place, per WORLDMAP_DESIGN.md section 4
VOID_COLOR
LAYERS          one block per layer -- see below
```

### The format does not enumerate layers

A layer block names itself and declares how it stores its contents: `KIND: "grid"` for a dense
lattice (run-length encoded, with its own `GRID_KIND` and `TILESET`) or `KIND: "list"` for
sparse placed things (`ITEMS`). `WorldMapTileData` can read a layer it has never heard of.

**Adding elevation, props, walkability or a travel graph later is therefore a data change with
no migration and no version bump.** This is what reconciles two instructions that pointed
different ways: the cycle file's WME-5 risk asks to "reserve the height layer's shape now even
though it stays empty", while Gate 1 trimmed the editor to ground and overlay on the user's
"can we add more as we go later". Writing an empty height block would satisfy the letter of the
first and contradict the second, and be speculative structure besides. Being *indifferent* to
the layer set gives the risk what it actually wanted — that Phase D cannot force a migration —
while adding nothing Gate 1 said not to build.

A grid layer's dimensions are derived, never stored: a tile-grade layer is `SIZE_TILES`, a
cel-grade one is that times the fixed ratio. That is the tile law's constant ratio paying off.

### RLE, one run per line

Runs are `"<count>:<id>"`, row-major, with `-` for an empty cell — spelled as a character rather
than an empty string so a run reads `12:-` in a diff instead of looking truncated.

Each run is its own array element, which `JSON.stringify` puts on its own line, so a diff shows
the runs that changed rather than one enormous altered string. The committed `temp2_authored`
ground layer is 99 runs for 165 cells.

A run list that does not add up to the layer's cell count is **refused**, not padded: a map
quietly missing its last row is worse than a map that fails to load.

### Versioning

`FORMAT_VERSION` and a `migrate()` hook exist from the first commit, because adding one after a
format has instances in the wild means writing the migration you did not keep the information to
write. A **future** version is refused outright — reading a newer file by ignoring the parts it
does not recognise is how data gets silently dropped.

### Determinism

A re-save with nothing changed produces a **byte-identical file**, asserted rather than assumed.
Runs are emitted in cell order, layers in declaration order, and `JSON.stringify` sorts keys
itself. Several sessions share one working tree; a file that reshuffles itself makes every save
a conflict that is not a real disagreement.

## 8. Painted and authored regions

`regions.json` declares `KIND: "painted" | "authored"`, defaulting to painted so every existing
entry keeps its behaviour untouched.

| | truth | PNG |
|---|---|---|
| **painted** | the PNG itself | hand-drawn art (`temp`, `temp2`) |
| **authored** | the tile data | a **build artifact**, baked, never hand-edited |

An authored region's baked PNG is committed, so a fresh checkout renders without running a bake
first; the linter is what flags one that disagrees with its source. An authored region whose bake
is missing fails to load with a message naming its source file and saying to run the baker —
a different problem from a painted region's art having gone missing, and worth saying so rather
than sending someone hunting for a PNG that was never meant to be committed by hand.

### The first authored region

`temp2_authored` is built by matching every 16 px cell of `temp2` against the `temp2_ground`
ledger: **165 of 165 cells matched**, 15 × 11 tiles.

`temp2` is 15.5 walk tiles wide, so this covers its first 15 whole columns — its rightmost 8 px
is a cel-grade remainder a tile-grade ground layer cannot hold. **The baker's parity target is
therefore temp2's first 240 px, not all 248.**

It is not yet listed in `regions.json`: it has no bake, and WME-6 adds the entry when it can
actually produce one. The catalog's authored path is exercised against a scratch catalog in
`probe_tile_format.gd` instead.

## 9. The bake

`WorldMapBaker` composes an authored region's tile data into the single texture the ground
shader samples. The bake **is** the render representation, not a compatibility shim — the
alternative (a tile-index texture plus an atlas sampled live in the shader) was rejected because
§4 of `WORLDMAP_DESIGN.md` keeps three sampler uniforms on one texture: an atlas cannot be
mipmapped without bleeding across tile borders, and nearest-filtered at magnification it is one
texel-rounding error from sampling its neighbour.

### One texture object, updated in place

`bake()` creates the `ImageTexture` once; every later flush calls `update()` on that same
object. The ground's samplers already point at it, so a re-bake needs **no call into
`WorldMapGround` at all** — and in particular not `configure()`, which would rebuild the mesh
for a change that is only pixels.

### Partial recomposition, full upload

**Godot 4 has no partial 2D texture upload.** `ImageTexture.update()` and
`RenderingServer.texture_2d_update()` both take a whole image; verified against 4.4 rather than
assumed. So the dirty-rect model governs the **composition** — the part whose cost scales with
region size, since a stroke on a 155-tile region otherwise re-blits ~24,000 tiles to change one
— while the upload is whole-texture regardless.

Flushing is therefore something to do once after a batch of edits, not once per cell.

Dirty rects are kept as a **list, not a union**: two edits at opposite corners of a map would
union into the whole map, which is the full rebuild the model exists to avoid. Each rect snaps
**out** to whole tiles, so a cel-grade edit always dirties the tile beneath it and a cel brush
cannot leave the ground under it stale. A mark already covered by an existing rect is absorbed,
so a drag across one tile does not accumulate a hundred identical entries.

`flush()` clears each dirty rect to transparent before recomposing it. Without that, a cell
whose tile was *erased* would keep showing its old pixels, since compositing draws over rather
than replaces.

Layers compose in declaration order, with `blend_rect` rather than `blit_rect` so an overlay
tile's transparent pixels let the ground beneath show through.

### Parity: an unusually exact acceptance test

Because the bootstrap tileset was cut out of `temp2` rather than drawn fresh, reassembling
`temp2_authored` from those tiles must reproduce `temp2` itself — **not "looks the same", the
same bytes.** It does: 240 × 176 baked, byte-identical to temp2's first 240 px.

That single assertion covers the whole chain at once: the sheet cut, the ledger hashes, the cell
ids the authoring pass resolved, and the compositing order and blend mode used here.

### The artifact's import settings

Godot's importer defaults are backwards for this rig. A freshly generated `.import` carries
`mipmaps/generate=false`; region art carries `true`, because §4 wants mips for the far field.
The baked artifact is patched to match, and `probe_bake_parity.gd` asserts it — comparing
against `temp2.png.import` itself rather than a remembered constant, so the check fails loudly
if region art's own settings ever change.

## 10. Undo and redo

`WorldMapEditHistory` undoes and redoes at **stroke** granularity: a drag across forty cells is
one undo entry, not forty. It is decoupled from any particular document -- it operates on
whatever `WorldMapTileData` it is handed -- so `WorldMapEditorController` owns one and wires
Ctrl+Z / Ctrl+Y now, even though nothing feeds it edits yet. Pressing them today correctly does
nothing, because there is no open document; a later item gives the editor one to edit and calls
`beginStroke` / `paintCell` / `endStroke` on it.

### Commands store the delta, not a snapshot

A full-region snapshot per stroke is unaffordable at real region sizes — a 155-tile region is
tens of thousands of cells, and most are untouched by any one stroke. A command carries
`{layerID, changes}`, where `changes` maps each touched cell to its `before` and `after` value.

### Coalescing is explicit, not inferred

`beginStroke` opens a command, `endStroke` closes it. Nothing guesses where a stroke starts or
ends from timing or mouse state — a drag tool opens on press and closes on release; a tool with
no release of its own (a flood fill triggered by one click) opens and closes within the same
call. Both are the same API used two different ways, which keeps a brush's shape uniform:
`beginStroke()`, some `paintCell()` calls, `endStroke()`.

### Repainting a cell within a stroke keeps the original `before`

A drag that crosses the same cell twice must undo to the value the cell held **before the
stroke**, not to an intermediate value from partway through it. `changes[cell].before` is
pinned on the cell's first write in the open stroke; `.after` advances on every write. A cell
whose net effect is zero — painted back to what it started as — is dropped when the stroke
closes, and a stroke that nets to nothing anywhere is not pushed at all, mirroring
`WorldMapTileData.setCell`'s own "returns whether anything changed" contract one level up.

### What undo and redo return

`{layerID, cells}` — exactly the cells a command touched, no more and no less. A caller uses
this to invalidate a renderer's cache for those cells and nothing else, which is what makes it
the same invalidation a forward edit would have triggered rather than a coarser guess. An undo
that invalidates less than the forward edit did leaves stale pixels with nothing to report it —
the same failure a skipped shadow-mask rebake is, in `WorldMapProps`'s own domain.

### The risk this file has to not have

A command capturing a reference rather than a copy, so undoing corrupts the history it undid
from. Every value stored is a `String` or a `Vector2i`, both value types in GDScript, and
`beginStroke` allocates a genuinely new `Dictionary` rather than clearing and reusing one —
reusing one across strokes would let a later stroke silently rewrite an earlier, already-pushed
command. Verified rather than reasoned about: `probe_edit_history.gd` fuzzes a hundred
randomised strokes against a real map, undoes every one, and asserts the data lands back on its
exact starting bytes — 92 of 100 strokes had a net effect in the committed run, and all 92
round-tripped exactly, forward and back.

## 11. The hex lattice

`WorldMapHexGrid` owns every piece of hex arithmetic in the project. That is not tidiness: the
one failure mode this geometry has is **column-parity bugs** — arithmetic that is right on even
columns and half a row out on odd ones — and the only reliable defence is that no caller anywhere
performs the parity step itself.

### Three coordinate spaces

| Space | Role |
|---|---|
| **Offset `(col, row)`** | Storage and the public API. A lattice is a plain `cols × rows` rectangle, which is what the dense RLE rows, the brushes, the history's `Vector2i` keys and the baker already index by. |
| **Axial `(q, r)`** | The maths. Neighbours and distance are trivial here and horrible in offset. |
| **Cube `(x, y, z)`, `x+y+z = 0`** | Only inside `roundAxial`, because correct rounding is only expressible there. |

The cycle file said to *store* axial. This stores offset and converts, reaching the same goal by
the other route: what that instruction protects against is parity arithmetic scattered through
callers, and centralising the conversion prevents that just as completely — while leaving the
dense array a rectangle and every existing `Vector2i` caller untouched.

### Geometry

Flat-top, pre-stretched so hexes read regular at pitch 60, which is what makes the world
footprint square. One hex is **2 × 2 world units**; columns advance **1.5**; rows advance **2**;
**odd** columns drop **1**. Cell `(0,0)` is centred at `(1, 1)` — its box starts at the origin.

That odd-vs-even convention is written down deliberately. Both exist in the wild, and picking one
silently is how a half-row shift turns up at a map edge months later.

### Rounding is the part that bites

Rounding each axial axis independently is correct in the middle of a hex and lands **one cell out
along every seam** — so it fails exactly where a user aims when being precise, and passes any
test that samples hex interiors. Measured against this implementation: naive rounding is wrong on
**33.3% of boundary points and 0% of interior points**.

The fix is to round in cube space and restore `x+y+z = 0` by recomputing the component that moved
*furthest* — the least trustworthy of the three.

### The square map

A region declares a **square extent**; `latticeForSquare()` inscribes the largest lattice that
fits; the remainder is **margin**. The margin is a **bake concern, not data** — only hexes exist
as cells, so nothing downstream ever asks whether a cell is a hex or filler.

Lattices fill a square exactly when `3C = 4R + 1`. `exactSquareLattices()` lists them for a "new
map" dialog:

| cols × rows | units |
|---|---|
| 7 × 5 | 11 |
| 15 × 11 | 23 |
| 31 × 23 | 47 |
| **103 × 77** | **155** |

The last is not a coincidence worth losing: **155 units is exactly the region width
`WORLDMAP_DESIGN.md` §3 says the reference framing needs** before the plane's own edges show. The
hex lattice and the framing constraint agree on the same number.

### Picking

`pickTile(..., hex)` switches only its final mapping from a square floor to hex rounding. The ray
solve is untouched — `surfacePoint()` returns a world point and knows nothing about grids, which
is why the hex switch cost one line there. `hex` defaults false, so the square path and
`temp2_authored`'s byte-exact bake parity are bit-for-bit unaffected.

One thing is still deliberately square and marked provisional in the source: **`pickCel` is
square-only**, because hexagons do not tile into smaller hexagons and hex sub-tile detail is the
six triangles a hex fans into (WMH-10). The grid overlay is no longer on this list — see below.

### The grid overlay

`fract()` on world XZ, the square lattice's whole trick, has no hex analogue — there is no
periodic tiling of the plane by a single `fract()` fold that reads as hexagons. The shader instead
resolves the *nearest hex centre* for every fragment and measures a signed distance to that one
hex's own edges, which is a small port of the CPU-side hex maths into GLSL rather than a new idea:

- `hex_nearest_axial()` is `WorldMapHexGrid.worldToCell()`'s cube-rounding, inlined — same
  independent-axis-rounding trap, same fix. Getting this step wrong reads as a lattice that is
  fine in the middle of every hex and one cell out along every seam, which is exactly the failure
  mode §"Rounding is the part that bites" above describes for the CPU side; the shader is not
  exempt from it just because it runs per-fragment.
- `hex_axial_centre()` is `WorldMapHexGrid.cellCentre()`, inlined the same way.
- `hex_edge_distance()` is the SDF: fold the local position into one quadrant with `abs()`, then
  take the max of the distance to the flat top edge and the distance to the slanted edge — the
  standard convex-hexagon SDF, sized to this hex's own `2×2` unit box.
- `hex_subtriangle_coverage()` folds further, to the two edges that survive `abs()`-folding all six
  spokes, and measures distance to each spoke as a clamped line segment (`distance_to_spoke`) —
  this is the sub-triangle fan, drawn only while `grid_mode == GRID_TILES_AND_CELS`, matching how
  the square path only draws cel lines at that same mode.

Two uniforms gate all of this: `grid_hex` (bool) picks hex geometry over square, and `hex_cursor`
(`vec3`, `xy` = the hex's own centre, `z > 0.5` = active) replaces `cursor_rect` for the hex path.
The **entire original square-path fragment code moved into an `else` branch, unmodified** — the
shipping square maps run the exact bytes they always did, provably rather than by inspection,
because nothing about them changed at all.

The risk WMH-3's own plan text named — *"a hex SDF that is subtly wrong reads as a plausible
lattice that does not line up with the cells picking returns"* — is why the cursor is drawn from
`hex_edge_distance` fed the same `WorldMapHexGrid.cellCentre` the picker uses, rather than from an
independent shape, and why `probe_hex_grid_overlay.gd` asserts the shader's ported functions agree
with `WorldMapHexGrid`'s own, across a dense sample **and** the boundary points that are the only
place a rounding bug shows.

### The lattice bound, and why the region is not it

**Gate 1 found this as a defect**, and it is worth stating as a rule rather than a fix: on a hex
map the **region and the lattice are different areas**. The author declares a square; the lattice
is inscribed in it; the leftover margin — up to 1.5 units on the right and 2.0 at the bottom — is
inside the region and outside the lattice.

Both the overlay and `pickTile` were bounded by the region, which was correct only while the two
were the same rectangle (they still are on a square map). On a hex map with margin the result was
that the overlay drew a column of hexes over the margin, the cursor highlighted them, picking
returned them as ordinary cells, and the brush then silently refused the paint with no feedback
anywhere — a hex you can point at, that lights up, and that does nothing.

Both now take a lattice size: `pickTile(..., hex, lattice)` returns `null` for a cell outside it,
and the shader's `hex_in_lattice()` gates every overlay line on the same test. `Vector2i.ZERO`
means unbounded, so the square path and any caller with no lattice to declare are unchanged.
The shader's port of `axialToOffset` is `row = r + floor(q * 0.5)`, which is exact rather than
approximate: `(q - (q & 1)) / 2` in integer arithmetic is `floor(q / 2)` for negative `q` as well
as positive. `probe_hex_grid_overlay.gd` checks the two agree across ~18,500 points, of which
~2,850 are genuinely in the margin — a bound that is never exercised is a bound that passes
vacuously.

One `--check-only` blind spot is worth naming since it cost real time here: GDScript's parser has
no knowledge of GLSL syntax, so a `.gdshader` file can pass `--check-only` on every `.gd` file that
references it while itself failing to compile — `float flat = ...` parsed fine as GDScript-adjacent
text but `flat` is a reserved GLSL interpolation qualifier, and the shader failed to compile with
`Expected an identifier or '[' after type`. The only way to catch this class of error is to force
an actual compile: load the shader into a live `ShaderMaterial`, attach it to a mesh inside a
`SubViewport`, and process a frame. There is no headless-only substitute for it.

### The map format

`WorldMapTileData` gains `LAYOUT`: `square` or `hex_flat`, defaulting to square so every existing
file loads with **no migration and no version bump** — which is what the format being
layer-agnostic was for. On a hex map `SIZE_TILES` means columns × rows, and every grid layer is
the lattice whatever its grid kind, because there is no finer hex lattice for a cel-grade layer to
mean.

### The hex brushes

`WorldMapBrushes` stores every cell in offset, hex or square, so five of its seven tools —
`point`, `floodFill`'s bounds check, `eyedropper`, `randomFromSet`, `replaceAllOfKind` — already
worked on a hex map without change: they only ever reason about individual offset cells or a raw
`Rect2i` of them, and offset storage is a plain `cols × rows` rectangle either way. Three tools
have genuinely different hex geometry, and each is why:

- **Line.** A hex has no diagonal neighbour the way a square does, so there is no "closest in
  each of two axes" step for Bresenham to generalise to. `lineCells(from, to, hex := true)`
  instead lerps the two endpoints' **cube** coordinates and rounds each of
  `WorldMapHexGrid.distance()`'s evenly-spaced samples — reusing `WorldMapHexGrid.roundAxial`
  rather than re-deriving it, so a drawn line and a pick agree on what "nearest hex" means.
- **Rectangle → disc, what the editor UI calls RANGE.** A rectangle has no natural hex meaning —
  a parallelogram in axial space reads skewed on screen — so the area tool on a hex map is
  `disc()`/`discCells()`: every cell within `radius` steps of a centre, via the standard
  cube-space disc enumeration (`3r² + 3r + 1` cells, each provably within radius by construction,
  not by a filter pass afterward).
- **Stamp → `stampHex()`.** Its pattern maps an **axial** offset from the anchor to a tile id,
  not a row/col array. This is the one place parity actually bites: the same `(dx, dy)` offset
  delta lands on a different relative hex depending on whether the anchor sits on an odd or even
  column, while axial addition has no such seam — the exact reason `WorldMapHexGrid` keeps axial
  as its maths space even though it stores offset.

`line`, `floodFill` (its neighbour set, not its bounds check) and `stamp` are otherwise unchanged
and remain what a square map uses; a caller picks the hex path by reading `data.layout` (`line`,
`floodFill`) or by calling the dedicated hex function (`disc`, `stampHex`), never by a caller-side
flag that could disagree with what the map itself declares.

`probe_brushes.gd` exercises all three at **both column parities** — an even- and an odd-column
origin for each — since column-parity bugs are, by construction, invisible from just one parity.
The flood-fill check is the one worth spelling out: it fills from a centre with a **hex ring**
(the cells at exactly distance 2) painted as a wall, and asserts the fill reaches every cell at
distance ≤ 1 and none beyond the ring. That specifically exercises hex adjacency rather than
square: a hex ring is a complete barrier because a hex has no diagonal neighbour to slip through,
where the same claim for a square ring depends on which connectivity rule (4- or 8-) the flood
fill uses.
