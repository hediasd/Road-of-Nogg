# World map editor

The authoring side of the world map. `WORLDMAP_DESIGN.md` covers how a region is **rendered**;
this note covers how one is **made**.

The editor is a **source-tree tool**. It never ships, it is not part of an exported build, and
several things below depend on that — see "Sheets are read as files" in §2.

The neutral startup, visual tilesheet picker, versioned file workflow and saved-snapshot battle
export described in §§6, 12 and 13 are implemented. A fresh-eyes interactive acceptance pass over
the complete workflow is still pending. Sections marked legacy describe older raw-region routes
that remain for existing fixtures; sections that explicitly say future or no authoring tool are
outside the current foundation.

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

Cutting from `temp2` specifically supplies an exact target: **an authored region reassembled
from these tiles should bake back to `temp2` pixel for pixel.**

`temp2` is 15.5 tiles wide (`WORLDMAP_DESIGN.md` §1), so its rightmost 8 px column is a cel-grade
remainder and is not represented in a tile-grade sheet. `cutSheet()` reports that remainder
rather than silently dropping it.

## 6. The editor scene

`scenes/debug/WorldMapEditorScene.tscn` is driven by `WorldMapEditorController` on the neutral
`WorldMapEditorFoundationStage`. Opening it starts an empty workspace: it does not load `temp2`,
does not run the old debug controller, and does not add clouds, sky, sun, lights or region-preview
controls. Those presentation features return later as an explicit editor-preview feature; their
game assets stay where they are in the meantime.

### The stage is an authoring surface, not a view of a world

The ground the editor draws stops at the document's own rectangle. A shipping ground extends one
fog length past its region so the haze can close before the art runs out, and paints the region's
void colour beyond that; on an authoring surface both would put a sea-coloured plane around the
map and invite the author to read it as somewhere. `WorldMapGround.authoring_surface` turns that
off: the plane is the document, off-map fragments are discarded, and what surrounds it is the
stage's own declared backdrop. The flag is set on the editor's ground instance and nowhere else,
so it cannot reach an exported scene -- `WorldMapSceneExport.buildRuntime()` makes its own ground,
which keeps the skirt and the void.

The stage also renders at **native** resolution rather than a shipping framing's reduced buffer.
The overlay is chrome measured in screen pixels, and drawing it into a smaller buffer and scaling
up is what turns a lattice into a dotted approximation of one.

### Workspace layout

The workspace has a palette column on the left, the map in the middle, and an inspector column on
the right. Either side column can collapse, leaving more room for the map without changing the
map's coordinate system.

**The top bar manages the document and nothing else**: New, Open, Open Recent, Save, Save As and
the two exports, beside the current document's title and dirty state. **Everything that changes
the map is in the left column**, under the tilesheet, as a menu in labelled sections -- Tools,
Brush, History, View -- plus the dropdown carrying the layer-specific tools. Which bar an action
appears on is decided by its group in `WorldMapWorkspaceActions`, not by where the chrome happens
to add it, so an action cannot end up on both or neither.

The menu is pinned and the tilesheet scrolls, not the other way round: together they want more
height than a 1280x720 window has, and a tool button reachable only by scrolling is a tool that
stops being used. The status line stays at the foot of the window.

The map column is its own display rect. Camera framing and render-buffer sizing use that rect rather
than the whole window, so a collapsed or resized panel cannot make a framed map overlap the chrome.
The foundation stage creates only the authored ground and editor camera inside that display.

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
| Frame the region | F, or **Frame** in the View section -- fits both axes at the display's own aspect |
| Show or hide the grid | **Grid** in the View section |
| Undo | Ctrl+Z |
| Redo | Ctrl+Y or Ctrl+Shift+Z |

The editor opens top-down and stays there. The shipping-preview framing, the projection toggle and
the off-contract badge that went with them are gone: they belonged to the explorer this stage
replaced, and an authoring view that can silently become a shipping view is a view an author
cannot trust for aiming.

When the map owns focus, the authoring shortcuts are **B** Paint, **E** Erase, **G** Fill and
**I** Pick; **Ctrl+S** saves and **Ctrl+Shift+E** runs Export Battle. **Ctrl+E** remains the legacy
standalone scene export described in §13. Text fields and modal dialogs deliberately own the
keyboard: their contents receive these keys and no map action runs. Click the map after closing a
dialog to return shortcut focus to it. **Tab is not an editor shortcut**: it stays available for
moving keyboard focus through the workspace's own controls.

### Palette, layers and first map

Select an active layer in the inspector before painting. The palette follows that layer: art grid
and detail layers show their complete tilesheet, while height, object and tactical layers show the
values their own tools accept. The visible sheet is authoritative for art selection; there is no
second tile-ID dropdown. It opens in **Fit**, with 1x, 2x and 4x available for inspection. A plain
click selects one frame, Ctrl-click adds or removes individual frames, and Shift-click selects a
rectangular range. The ordered multi-frame selection supplies the Stamp tool. Escape or clicking
blank sheet space clears the selection. The current-frame preview and selected frame IDs remain
visible. Paint, Fill, Stamp and Scatter refuse to alter an art layer while the selection is empty;
choose **Erase** when clearing cells is intended. Scatter seed controls appear only for Scatter.

Each layer also has visibility and lock controls. A locked or hidden layer refuses edits, and a
hidden art layer is removed only from the editor's displayed preview: it remains in the canonical
document, save and export. Some data layers have no separate visual representation, so their
visibility control explains that rather than pretending to hide something. Objects are hidden as a
preview group. With every art layer visible, ordinary edits keep the incremental bake path; hiding
art trades that for a full filtered preview bake after a committed stroke.

For a first map: choose **New**. The dialog defaults to a 19 by 14 flat-top hex lattice and the
`temp2_hex32_starter` tileset; the other exact-fit presets remain available. Give the document a
human title, then select a frame directly from the sheet. Paint with **B**, erase with **E**, or
flood-fill with **G**. A held drag paints as it moves rather than at the moment the button comes
up. Change brush radius with the Brush section's controls or `[` and `]`; a radius is a hex-disc
footprint, so the preview and committed stroke cover the same cells. Hide or lock a layer
to inspect the result, then undo and redo with **Ctrl+Z** and **Ctrl+Y** (or **Ctrl+Shift+Z**).
Use **Save As** to choose its first `.noggmap.json` path and **Export Battle** when the saved map is
ready for the runtime boundary.

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

### What this editor deliberately does not do yet

The foundation covers authoring a hex document, saving it as a versioned source file, recovering
unsaved work, and publishing a saved snapshot across the battle boundary. The following are later
increments rather than missing pieces, and nothing here should be read as claiming them:

- **Autotiling and transitions.** Edge and corner variants are chosen from the sheet by hand.
- **Selection and clipboard**, and a reusable multi-layer stamp library beyond the sheet's own
  ordered multi-frame selection.
- **Resizing a map**, and maps without a fixed lattice.
- **New sculpting, water, bridge and object tools.** The existing ones are preserved and reachable;
  they are not being extended here.
- **A tactical visualisation of its own.** The battlefield layer is authored and exported; what it
  looks like in battle belongs to the battle.
- **Importing TMX** and bundled asset interchange.
- **Deploying a battle scenario from the editor.** Export produces the map, not the encounter.
- **Crash recovery for a map saved outside the project.** A snapshot refuses a source path outside
  the source root and says so on the status line, so nothing is lost silently -- but such a map is
  not covered once it has a path.

Clouds, animated lighting and world atmosphere return as an explicit editor-preview feature later.
Their game assets are unaffected.

The reasoning behind the workspace's shape, and the two places the shipped editor deliberately
went further than the sketch it was designed from, is kept in
[the authoring workspace sketch](./sketches/2026-09-12-hex-editor-authoring-workspace.html).

### Checking the editor still works

The editor's probes live under `scripts/worldmap_editor/checks/`. Most run headless; the two that
judge layout, rendering and a live bake need a real window and take a client size. Each prints an
exact marker line, and a zero exit code alone is not evidence -- require the marker.

```powershell
./Godot_v4.4-stable_win64.exe --headless --path . --script scripts/worldmap_editor/checks/workspace/probe_workspace_contract.gd
./Godot_v4.4-stable_win64.exe --path . --script scripts/worldmap_editor/checks/acceptance/probe_foundation_acceptance.gd ++ 1280 720
```

The acceptance probe is the broad one: a fresh launch, New, the tilesheet, a painted drag, the
layer gates, the document lifecycle including recovery, and the battle export, all against the real
scene. Run it at both 1280x720 and 1920x1080; the first is the tight layout. It writes its fixtures
under `user://hxf_acceptance` and removes them, and never touches an authored map or a shipped
battle definition.

### Hex tools

Paint and Erase use the selected radius as a true hex disc. Line interpolates in hex space,
Rectangle selects actual offset-grid cells, and Stamp places the palette's multi-frame pattern by
axial offsets so it does not shift when its anchor crosses an odd/even column boundary. Fill,
Pick, Scatter and Replace operate on the active layer according to its kind. A single click, drag
or preview always identifies the same footprint; Escape abandons an open stroke and restores its
pre-stroke cells.

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
no migration and no version bump.** This reconciles two requirements that pointed different ways:
reserve the height layer's shape even though it stays empty, while the initial editor surface is
trimmed to ground and overlay on the user's
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

It is not yet listed in `regions.json`: it has no bake, and the bake workflow adds the entry when it can
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

### Hex baking

Everything above is the square path, and it is bit-for-bit what it always was — `temp2_authored`
still bakes byte-exact. Hex needed three separate fixes, because a square lattice's cells tile
edge to edge and a hex lattice's frames **overlap**.

**Canvas size** comes from `data.worldExtent()`, not `data.size_tiles` — on a hex document
`size_tiles` is columns and rows, and only `worldExtent()` (`WorldMapHexGrid.latticeExtent`)
converts that to world units. A no-op for a square document, where the two already agree.

**Frame size** comes from the tileset's own `FRAME_PX`, not `GRID_KIND` — the hex sheet's frames
are 32 px, where `GRID_KIND` alone would only ever say 16 or 8. This is the same conflation
`FRAME_PX` was added to fix once already, generalised: reading it uniformly costs nothing for a
square tileset, since `FRAME_PX` defaults to `gridPixels(GRID_KIND)` when a tileset never
declares its own.

**Placement** is `WorldMapHexGrid.cellCentre(cell) * TILE_PIXELS`, centred, rather than
`cell * framePx`. A hex frame is 32 px on a 24 px column pitch, so adjacent columns' frames
overlap by 8 px — and the sheet already carries the alpha that makes that correct: **0 of 320
frame corners in `temp2_hex32_ground` are opaque**, measured directly against the PNG. Asserted
by `probe_bake_parity.gd` rather than trusted, so a future hex sheet cut without its corner mask
fails loudly instead of rendering as square overwrite artifacts where hexagons should meet.

**The dirty-rect model needed the same overlap awareness**, and this is where the real risk
lived: `flush()` clears each rect to transparent before recomposing it, so a dirty rect that is
merely *close* does not leave a stale pixel the way it would on the square path — it **erases** a
strip of a neighbour that was never told to redraw, because that neighbour's frame reached into
the erased area and nothing repainted over it. This shows up only in the *partial*-flush path,
never in a from-scratch bake, which is exactly the case a test that only checks full bakes would
miss. `_cellsToPixelRect` (converting an edited cell range to the pixel rect to mark dirty) and
`_composeHexLayer` (converting a dirty pixel rect back to the cell range to recompose) are both
deliberately generous — padded by a full extra frame beyond the geometry actually requires —
rather than tight, because over-covering costs a handful of redundant blends and under-covering
corrupts the image. `probe_bake_parity.gd`'s headline hex check bakes a uniform field, edits one
cell on an even column and one on an odd column, and asserts a partial flush is byte-identical to
a full re-bake in both cases — the assertion that actually exercises the risk, not just the
reasoning for it.

## 10. Undo and redo

`WorldMapEditHistory` undoes and redoes at **stroke** granularity: a drag across forty cells is
one undo entry, not forty. It is decoupled from any particular document and carries a monotonically
advancing revision. The document save point records that identity, not merely an undo-stack depth,
so undoing to the saved content is clean while branching from it with a new edit is unsaved.
The workspace binds Undo to Ctrl+Z and Redo to Ctrl+Y or Ctrl+Shift+Z when the map has keyboard
focus.

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
six triangles a hex fans into. The grid overlay is no longer on this list — see below.

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

The risk that *a subtly wrong hex SDF reads as a plausible lattice that does not line up with the
cells picking returns* is why the cursor is drawn from
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
- **Brush radius → disc.** Paint and erase footprints are `discCells()`: every cell within
  `radius` steps of the picked centre, via standard cube-space disc enumeration (`3r² + 3r + 1`
  cells). This is the editor's radius control, not a renamed Rectangle tool.
- **Rectangle.** Rectangle deliberately selects a rectangle of stored offset cells. It is useful
  for block edits and previews the exact cells it will change; it does not claim to be a hex disc.
- **Stamp → `stampHex()`.** Its pattern maps an **axial** offset from the anchor to a tile id,
  not a row/col array. This is the one place parity actually bites: the same `(dx, dy)` offset
  delta lands on a different relative hex depending on whether the anchor sits on an odd or even
  column, while axial addition has no such seam — the exact reason `WorldMapHexGrid` keeps axial
  as its maths space even though it stores offset.

`line`, `floodFill` (its neighbour set, not its bounds check), brush radius and stamp select their
hex path from the document layout. The controller keeps that decision at the footprint boundary,
so preview and committed edits cannot disagree about which lattice they use.

`probe_brushes.gd` exercises all three at **both column parities** — an even- and an odd-column
origin for each — since column-parity bugs are, by construction, invisible from just one parity.
The flood-fill check is the one worth spelling out: it fills from a centre with a **hex ring**
(the cells at exactly distance 2) painted as a wall, and asserts the fill reaches every cell at
distance ≤ 1 and none beyond the ring. That specifically exercises hex adjacency rather than
square: a hex ring is a complete barrier because a hex has no diagonal neighbour to slip through,
where the same claim for a square ring depends on which connectivity rule (4- or 8-) the flood
fill uses.

## 12. The document lifecycle

New, Open, Open Recent, Save and Save As are direct workspace buttons. Starting the editor does not
open a document. **New** creates a pathless, unsaved map; its default is a 19 by 14 flat-top hex
lattice using `temp2_hex32_starter`, while the exact-fit lattice presets remain available. The
title entered in New is a human label and remains independent of the eventual filename.

**Open** uses the native filesystem dialog and accepts versioned `.noggmap.json` source files,
including files outside the project. Tileset references inside a document are still project
catalog IDs such as `temp2_hex32_starter`; opening a source file does not bundle external art.
**Open Recent** stores filesystem paths in `user://worldmap_editor/recent_maps.cfg`, omits paths
that no longer exist, and opens a map only after the author chooses it. It never restores a recent
map automatically at startup. TMX is not an interchange format for this foundation.

The complete source-envelope and identity contract lives in
[Hex map source format](./HEX_MAP_FORMAT.md). Keep schema details there rather than copying them
into this workflow guide.

### Dirty state and safe saves

Every earlier version of this tool had call sites set `_documentDirty = true` by hand after an
edit. The risk that killed that approach: a call site that mutates the document and forgets to
say so produces a document that silently loses work, and "remembered at every call site" is
exactly the kind of invariant that erodes the first time someone adds a new one under time
pressure.

The unsaved marker is derived from the history revision at the last successful save. Undoing to
that revision clears it; an edit made after undo is a new revision and remains dirty even if the
undo stack happens to return to an earlier depth. A failed save does not advance the save point or
change the active source path.

**Save writes source only.** It does not bake a PNG, publish a scene or export a battle definition.
The writer replaces the `.noggmap.json` through sibling `.tmp` and `.previous` files so a failed
replacement retains the last good source. An unchanged Save does not rewrite or increment the
document; a changed Save advances its revision. Before overwriting, Save compares the file on disk
with the fingerprint recorded when it was opened or last saved. If another program or session
changed it, Save refuses and tells the author to reopen or use Save As.

A new or recovered document has no destination, so Save opens **Save As**. Save As uses the native
filesystem dialog, writes a new document UUID at revision 1, and moves the active document to that
path only after the write succeeds. It keeps the human title separate from the filename. A failed
or cancelled Save As leaves the current document, path, identity and dirty state unchanged.


### Replacing or closing an unsaved document

New, Open, Open Recent and Close all ask what to do with unsaved work: **Save**, **Discard** or
**Cancel**. The window close button follows the same rule. Save continues the requested action only
after the document is saved; Discard continues without writing; Cancel leaves the current map
untouched.

Modal ownership is released when the dialog closes, so authoring shortcuts resume after returning
focus to the map.

### Recovery is an offer, never an overwrite

After 30 seconds of dirty, stroke-free idle time, the editor may write a recovery snapshot under
`user://worldmap_editor/recovery/`. Snapshots are outside the repository and source locations.
They are not saves: startup lists them for an explicit Recover or Discard decision. Recover opens
a fresh, pathless, unsaved document with fresh history; it never writes the snapshot back over
source. If the saved source changed, disappeared or has an invalid recorded path, the recovery row
says so before recovery. Discard removes only the selected snapshot. A successful save clears that
map's recovery snapshot.


## 13. Exporting a gameplay scene

**Export Battle** (`Ctrl+Shift+E`) is the foundation's runtime boundary. It publishes the whole
saved document, regardless of editor layer visibility. If the open document has unsaved changes at
an existing source path, the editor saves it first. If it has no path, the editor opens Save As and
stops the export; invoke Export Battle again after the save succeeds.

Every source document receives a stable artifact stem, `hex_<document UUID without hyphens>`.
One export writes four derived files:

| Product | Location |
|---|---|
| Baked texture resource | `assets/worldmap/regions/generated/<stem>.tres` |
| Reusable visual scene | `scenes/worldmap/generated/<stem>.tscn` |
| Battle definition | `data/battle/maps/<stem>.json` |
| Success receipt, written last | `data/battle/maps/<stem>.receipt.json` |

The scene and battle definition carry the same source UUID, saved revision and canonical source
fingerprint. The battle definition also names the visual scene and is checked through
`BattleMapFactory` before publication. The receipt is the completion marker; artifacts without a
matching receipt are an incomplete export. A `.noggmap.json` file is editor source and is never
loaded directly as a battle scenario.

The current tactical boundary is deliberately narrow: it exports one flat surface per playable
hex, requires an explicitly authored tactical layer, accepts integer elevations from 0 through 8
at 0.5 world-unit steps, and preserves authored terrain flags. It does not infer walkability,
elevation or combat meaning from tile art. Sloped playable cells and multiple walkable surfaces
such as bridges still require a later runtime-schema extension.

### Legacy standalone scene export

`WorldMapSceneExport` is the older standalone `Ctrl+E` path. It remains available to existing
workflows, but it is separate from Export Battle and still expects a previously baked, imported
PNG. The sections below document that legacy path. New foundation maps should use Export Battle,
whose saved `.tres` texture does not require a separate Godot import pass.

### What a shipped map is

A `Node3D` carrying region metadata, with one `Ground` (`WorldMapGround`) child holding a
`PlaneMesh` and a `ShaderMaterial` bound to the committed bake. **No camera, no sky, no clouds,
no HUD, no controller** — a gameplay scene supplies its own camera and environment, and the
exported scene supplies the place. Verified by rendering one in a bare `Node3D` + `Camera3D`
scene that touches no editor or debug class at all.

`WorldMapGround` stays on the exported node deliberately: it is the class the shipping rig
already uses, not editor code, so keeping it means the previewed ground and the shipped ground
are literally the same class rather than two that could drift.

Metadata rides on the root — region, layout, cells, extent, source path — because **only
`@export`ed properties survive `pack()`**, and `WorldMapGround` exports none of its runtime
state. `set_meta` does survive, so a gameplay scene can read a map's identity and extent without
loading the authored source to get them.

### One builder, so preview and export cannot drift

`configureGround()` is the single definition of how a document becomes a ground: which extent it
spans, which texture it samples, which fog and void colours it carries. The editor's live preview
calls it, and the export calls it. A map that previews at one size and ships at another is the
failure that shape rules out — and on a hex document it is a live risk, since `worldExtent()` and
`size_tiles` are genuinely different numbers there.

### The resource that must not be embedded

**Godot does not fail when a material points at a texture with no `resource_path` — it silently
embeds the whole image as base64.** Measured on a 64 × 64 red square while writing this item:

| material's texture | exported `.tscn` |
|---|---|
| loaded from disk (`res://…png`) | **1,728 bytes**, PNG as an `ext_resource` |
| created at runtime (no path) | **67,404 bytes**, image inlined as a `[sub_resource type="Image"]` |

On a real map that is megabytes of pixels duplicated into the scene file, thereafter diverging
from the PNG the baker keeps current — two copies of the same art, one of which nothing updates.
A scene like that loads perfectly and is quietly wrong, which is exactly what a "does it load?"
test passes. So `exportScene()` **refuses** a texture with no `resource_path` instead of falling
back to one, and `probe_scene_export.gd` asserts that no `Image` sub-resource ever appears, that
the PNG is present as an `ext_resource`, and that the whole scene stays under 8 KB.

The consequence is a real precondition: **the bake must be saved AND imported before an export
will run.** A freshly saved map in a running editor session has the file but not the import, so
`ResourceLoader.exists()` is false and the export says so, naming the path it wanted. There is no
fallback, because the only available fallback is the embedding above.

### Generated scenes are not committed, and the reason is measured

`ResourceSaver.save()` assigns **random id suffixes** (`id="1_23d0s"`) on every save, so exporting
identical content twice produces different bytes. That is the opposite of the baked PNG, which is
byte-deterministic and is therefore committed and byte-checked by `probe_bake_parity`. An
exported scene cannot be checked that way, and committing one would show a spurious diff on every
re-export — so exports land in `scenes/worldmap/generated/`, created on demand, and none is
committed by this item.

The two artifacts are treated differently because they genuinely differ in this property, not by
preference.

### The wrapper pattern

`scenes/worldmap/generated/<name>.tscn` is regenerated wholesale and must never be hand-edited —
the same rule `assets/worldmap/regions/generated/` already carries for baked art. Hand-authored
additions belong in a **wrapper scene** at `scenes/worldmap/<name>.tscn` that *instances* the
generated one. Re-exporting rewrites only the generated file; the wrapper is untouched and picks
up the new content on its next load. That is what "re-exporting updates generated content without
destroying hand-authored additions" means concretely.

### A scene that loads and then breaks is still broken

`WorldMapGround._material` is a plain variable, so it does not survive `pack()`: a loaded map has
a good deserialised `material_override` and a null cache. `_ensureMaterial()` therefore **adopts
an existing `material_override`** before making a new one. Without that, the first
`applyFraming()` — the ordinary call for a gameplay scene choosing its own fog — would swap in a
blank material and the map would lose its texture, extent and colours in one call.
`probe_scene_export.gd` drives exactly that sequence on a loaded scene, and first asserts the
cache really is null so the check cannot pass for the wrong reason.

## 14. Placed objects

`WorldMapObjectLayer` holds buildings, towers and whatever else stands **on** the map rather
than being part of it. A `list`-kind layer, which the format already supported: adding objects
was a data change with no migration and no version bump, which is what §7's layer-agnostic design
was for.

### An id is allocated, not derived

Quests, save data and triggers will reference object ids, so an id has to survive everything that
is not a deletion: moving the object, rotating it, re-anchoring it, saving and reloading, and any
number of other objects being placed or removed around it. A content hash of position and kind
survives none of those — moving a house would rename it. `get_instance_id()` is ruled out by
`AGENTS.md` and would differ between two loads of the same file anyway.

So `NEXT_ID` allocates (`o000`, `o001`, …), only ever rises, and **an id belonging to a removed
object is never reissued** — the same contract, for the same reason, as the tileset ledger's own
`NEXT_ID` (§3). `NEXT_ID` lives on the layer block rather than the document, so two list layers
cannot interleave their allocators; and when a file carries no `NEXT_ID` it is **derived from the
highest id present** rather than defaulted to zero, so a hand-edited or older file still cannot
reissue.

### What a record holds

| field | meaning |
|---|---|
| `ID` | allocated, never reissued |
| `KIND` | `"house"`, `"tower"` — a catalog reference later, a plain string now |
| `CELL` | `[col, row]` offset cell, an **array** because JSON has no `Vector2i` — the tileset ledger's own `CELL` convention |
| `FACING` | 0–5, an index into `WorldMapHexGrid.AXIAL_NEIGHBOURS`, so 0 is east |
| `FOOTPRINT` | hex radius: 0 is the anchor cell, 1 adds its six neighbours |
| `ANCHOR` | `terrain` (follow the ground) or `fixed` (stay at `HEIGHT`) |
| `HEIGHT` | absolute height when `fixed`, an offset above the anchored surface when `terrain` |

Six exact facings rather than free rotation, because a flat-top hex has exactly six edges to
face — and 0–5 is exact where degrees are not.

### Anchoring samples the footprint and takes the maximum

Raising ground under one corner of a building must **lift** the building, not push terrain through
its floor, so the surface it rests on is the highest cell it covers. A building floating over a
dip on one side reads as a building on uneven ground; one buried to its windows reads as a bug.

`anchorHeight()` takes the height **sampler** as an argument rather than reaching for a concrete
layer. Flat ground is the default and returns zero; the height layer passes the real sampler
without this file changing. `probe_object_layer.gd` supplies
its own sampler to prove an object rises with its footprint, ignores terrain outside it, and
ignores terrain entirely when its anchor is `fixed`.

### One record feeds every derived thing

`WORLDMAP_DESIGN.md` §9 records what happens when it does not: temp2's structures were once
re-anchored by moving the rendered quad instead of the record, which left every building standing
half a tile from its own shadow and its own pool of light — **a defect no probe could catch**,
because the mask and the record still agreed with each other perfectly.

So nothing here returns a position anything downstream is expected to adjust.
`worldPosition()` is *the* position, and a sprite, a shadow and a lamp all read it. The simple
box `WorldMapSceneExport._objectBody()` builds is explicitly a placeholder for the **look** and
exact about the **placement**; when object art arrives that is the one function that changes,
because nothing downstream reads the box.

### Objects in the exported scene

Each object becomes a `Node3D` under an `Objects` holder, **named by its own id**, so a gameplay
scene resolves `map.get_node("Objects/o003")` rather than searching. Kind and footprint ride as
metadata rather than as a name suffix, so the lookup stays exact and gameplay can ask what a
thing *is* without parsing its name.

### temp2's nine structures, re-placed

`temp2_hex32_authored` is the first authored **hex** document, and its nine structures are
objects rather than ground. That is possible because the hex tileset was cut with the houses and
towers deliberately excluded — so the ground carries patched terrain under each building and the
buildings stand on the object layer, which is a re-placement rather than a duplication.

The positions come from `WorldMapProps`' own extraction of temp2 — the same records §9's
anchoring rule already corrected — converted from map pixels to hex cells through the building's
**foot** (`x + w/2`, `y + h`), the only point that should decide which cell it stands in. temp2's
art is 2× in the hex region, so a temp2 world position doubles before being resolved.

Rebuilding the document also cross-validated hex baking: the authoring tool reads each cell at
`cellCentre × 16 − frame/2` and matched **200 of 200** cells against the ledger, which is only
possible if the baker's placement is the exact inverse of the original cut. The one catch worth
recording is that the cut must be **hex-masked** before hashing — a plain rectangular cut from
the composed region picks up the overlapping fringes of its neighbours in the frame's corners and
matches nothing.

### Known, not fixed: black notches at a hugging map's edge

`temp2_hex32_authored`'s canvas hugs its lattice exactly, so the sawtooth gaps between the top
and bottom rows of hexes are transparent texels **inside** the region rect rather than outside
it, and they render black instead of taking the void colour. The remedy is the square-with-margin
square-with-margin shape — this document is 30.5 × 21 units with no margin, because it was built from
the source art's own non-square extent — or making the void substitution alpha-aware. Named here
rather than fixed, since it is about the map's shape and the ground shader, not about objects.

## 15. Terrain height

`WorldMapHeightField` stores heights on the hex **vertex** lattice, and one interpolation
serves rendering, picking, object anchoring and export.

### Why vertices, and why that makes the triangulation unambiguous

A height per *cell* gives flat plateaus with a cliff at every edge — there is nowhere for a slope
to live. Heights on vertices make the surface continuous by construction, because neighbouring
hexes share the vertices between them and cannot disagree about the ground where they meet.

**Three hexes meet at a hex vertex, not four.** A square grid's vertex is shared by four cells, so
a quad must pick one of two diagonals and every system that samples it must pick the *same* one.
A hex has no such choice: each hex fans into six triangles from its own centre, and it is the same
fan the sub-triangle detail layer uses, so the two agree by construction rather than by
convention.

Six corners shared three ways is exactly **two vertices per hex**, so a vertex is addressed as
`(ownerCol, ownerRow, index)` with index 0 or 1. Measured before anything was built on it: 400
cells resolve to 880 distinct vertices, and across 600 vertices each sits exactly at the
**centroid** of its three cell centres — exact even for these pre-stretched hexes, because a
centroid survives any linear map.

Storage pads the owner range by one cell in each direction, since a hex on the lattice edge has
vertices owned by cells just outside it. It is a third block kind (`heights`) rather than a grid
layer, because the array is not one entry per cell and `layerSize()` would have to lie about it —
adding a kind is exactly what the layer-agnostic format was for. Values run-length encode as text
like ground cells do, so **a flat field is one run**.

### The rendered surface *is* the sampled surface

`buildSurfaceMesh()` emits the same interpolation `sample()` performs: each hex's six fan
triangles, every vertex at the height the field holds, every hex centre at the mean of its six.
So this item's stated risk — picking and rendering sampling the surface differently, leaving the
cursor off the visible ground on a slope — is closed **by construction** rather than by keeping
two formulas in step. `probe_height_field.gd` asserts every mesh vertex equals `sample()` at its
own XZ.

The alternative was a displacement-mapped plane, which would have needed exactly that agreement,
at a mesh density fine enough to resolve a one-unit feature across a plane hundreds of units wide.

**No shader change was needed.** The ground shader already takes `world_position` from `VERTEX`
*before* subtracting curvature, so height baked into the mesh lands in region space and curvature
applies after it — which is precisely the ordering this item requires. Curvature never reaches the
mesh, so it is never stored.

The mesh is built by editor code and handed to `WorldMapGround` as a finished `Mesh`, because that
file ships and the height field does not: an exported scene must carry geometry, not the code that
generated it.

### Picking: secant, not fixed-point

Adding a height term makes the ray/surface equation `h(U) − k·f(t)²`, and `h` is a lookup rather
than an expression, so there is no closed form. The smooth root is a good seed, and substituting
the sampled height back into the same quadratic is one correction step.

**Iterating that substitution is not enough**, and the measurement is worth keeping: it is a
fixed-point scheme whose convergence rate is the ratio of terrain slope to ray slope — fine for a
ray coming steeply down, barely convergent for the shallow rays near the top of the frame where
that ratio approaches one. On a ramp of slope 0.53 seen at pitch 60, four passes left a picked
point **2.25 units** off the surface, and every miss was near the horizon. Root-finding the
residual by secant instead converges superlinearly regardless of ray angle: the worst miss across
260 rays on that same slope is **0.00009 units**, where the flat solve would be off by 6.33.

### Known, not fixed: unshaded terrain shows no relief at the shipping framing

A sculpted hill and basin are unmistakable from an oblique angle, where the silhouette reveals
them — and essentially **invisible at the shipping pitch-60 framing**, because the ground shader
is unshaded by design (§4: flat colour is the look). Flat colour gives the eye no gradient, so
relief only reads where it breaks the silhouette.

The geometry is genuinely there — the probe proves every mesh vertex matches the field, and
objects visibly stand on the hill — so this is a *shading* gap, not a terrain one. The remedy is a
slope-derived cue on the ground, and the framing already carries a sun direction to derive it
from. Named here rather than fixed, since this item owns the surface and that is a question about
how the surface is lit.

## 16. Sub-triangle detail

`WorldMapTileData.KIND_DETAIL` stores six independent triangular slots per hex, the direct hex
equivalent of a cel: art only, painted independently, composited over the ground in the bake.
Nothing an entity observes reads this layer — no walkability, no height, no collision.

### The same fan, on purpose

A detail slot and a terrain triangle are the same region of the hex **by construction**: both use
the six triangles the height field fans from a hex's own centre to its six corners. The governing
design decision is that "a hex fans into six
triangles from its centre with no arbitrary diagonal choice — which is also the triangulation
smooth terrain wants, so one decision serves both" — and this item is the specified implementation
of the detail half of that sentence.

### A fourth storage kind, not a grid layer

A triangle's address has three components — `(col, row, slot 0–5)` — and a grid layer's
`getCell`/`setCell` only take two, the same reason heights needed their own kind rather than a
finer grid. Storage is dense, `cols × rows × 6` tile-id entries, **no padding**: unlike a height
vertex, a triangle belongs to exactly one hex and is never shared with a neighbour, so there is
nothing just outside the lattice that owns one. It serialises through the exact same
`encodeRLE`/`decodeRLE` a grid layer's own cells use — an unpainted detail layer is one run.

### Masked at bake time, not pre-masked in the art

There is no dedicated detail tileset yet — the probe reuses `temp2_hex32_ground`, the only hex
tileset in the catalog, the same bootstrap pattern already used for ground and
brushes. So the six slots cannot come from six pre-cut triangular art pieces; **the baker masks a
whole tileset frame down to one fan triangle at composite time**, per pixel, before blending it
in. A pixel's own local position (relative to the hex's own centre, in world units) is tested
against the same barycentric fan-triangle math `WorldMapHeightField` uses for terrain
sampling — deliberately **duplicated**, not called, since `WorldMapHeightField.gd` is not touched
by this item, the same reason `tool_author_hex32.gd` once had to mirror `tool_cut_hex32.gd`'s own
mask rather than import it.

This is what makes six independently-painted slots share one 32 px frame without overwriting each
other: `_maskToTriangle` builds a masked copy of the source frame, then `blend_rect`s only that
copy in, so a pixel outside the target triangle is simply never touched. `probe_subtriangles.gd`
proves this is not merely "the mask exists" but that it actually confines painting: slot 1 painted,
then slot 4 (the opposite side of the hex) painted with a different tile, and slot 1's own
well-inside pixels are asserted byte-identical before and after — the check that would fail first
if masking silently degraded to "the whole frame".

### Detail undo

The first detail implementation shipped `paintTriangle` as `data.setDetail(...)` directly — no
stroke, no coalescing, no undo — while every
sibling brush in `WorldMapBrushes.gd` was `(data, history, layerID, ...)`. Wiring a fourth kind
into the history was real work, and this item's Touches list did not include
`WorldMapEditHistory.gd`; rather than reach into a file outside its scope or ship an un-undoable
tool without saying so, **the deviation from every sibling's shape was itself the marker.**

Later work exposed these slots through a mouse tool, which turned the missing undo into a defect:
a person could now make edits they could not take
back. So detail is the history's fourth delta kind, `paintTriangle` has its siblings' signature,
and the anomaly is gone. See §17.

## 17. The tools that reach the other layers

Height, object and detail layers are selectable and use their own value rows and gestures. They
round-trip through history, saves and export rather than being data that can only be authored by a
script.

### Reachable and empty are different states

`_layerEditable` used to ask "is this a grid layer with a known tileset", which is why a height,
list or detail layer could never become the active one no matter what the map stored. It is now
kind-aware, and it is joined by `_layerPopulated`, because the two questions genuinely differ:

| | `_layerEditable` | `_layerPopulated` |
|---|---|---|
| gates | tool input, the grid overlay | the row's `(empty)` label and dimming |
| a fresh hex map's `heights` | **true** | **false** |
| the square `temp2_authored`'s `heights` | false — no hex lattice to sculpt | false |

The three authored layers are **created by their own first edit**, not conjured onto every
document that is opened. A height field or a detail fan on a square map would be storage for a
lattice that does not exist, and `temp2_authored` is square — so a load-time migration would have
been wrong for exactly the map the project already ships.

### One value row, per layer kind

The row that offered tile ids now offers whatever the active layer's tool takes: **Tile** over a
grid or detail layer, **Sculpt** over heights, **Object** over the object layer. `setValueChoices`
takes labels and values as a pair, because a sculpt step reads `Raise +0.50` and acts as `0.5`.

This is the half that made the kind-aware `_layerEditable` safe. The failure it avoids is a sculpt
reading a tile id off a row that has none and applying `float("")` — which is `0.0`,
a silent no-op, the same class of defect as Gate 1's picker refusing a click without a word.

Removing is a choice in that row rather than a tool of its own, matching `Erase (-)` on the tile
row.

The same reasoning gives `_toolFitsLayer`: the new rows made a mismatched tool reachable for the
first time, and `WorldMapTileData.setCell` already refuses a non-grid layer by returning `false`
— so a paint aimed at the height layer would do nothing and say nothing. **Nothing was ever in
danger; the silence was.** The guard exists for the message, which names both the tool's kind and
the layer's.

### Three gestures, chosen for what each edit is

- **Sculpt** is a drag, stepped. Both signs sit in the value row rather than behind a modifier, so
  lowering is exactly as discoverable as raising. Each vertex moves **at most once per stroke** —
  three hexes share every vertex on this lattice, so a drag across neighbours would otherwise
  raise the shared ones twice and leave a ridge along the drag. `Flatten to start` levels every
  cell a stroke crosses to the height of the cell it began on, sampled before the first step.
- **Place** is a click, and one click does all three verbs: an empty cell takes the selected kind,
  an occupied one **turns** by a facing step, `Remove` deletes. No modifier keys, no second
  control for facing.
- **Paint triangle** is a drag that follows the **pointer**, not the cell under it — dragging
  inside one hex crosses fan slots without ever changing cell, so following the cell would paint
  the first slot and then nothing.

### The fan test still has one definition

`WorldMapHeightField.fanTriangleOf` is now that definition in world space, extracted from inside
`sample()` so the picker and the sampler cannot disagree about which sixth of a hex a point is in.
`WorldMapBaker` keeps its deliberate second implementation in pixel space (§16). Two is already
one more than ideal; a third, added because the loop happened to live inside `sample`, is how the
terrain a click lands on and the triangle it paints start drifting apart.

### A sculpt that changes nothing on screen would be the real failure

Heights are geometry, not pixels, so a sculpt invalidates no part of the bake — which means the
ordinary `_afterCellsEdited` path does nothing for it. `_afterHeightsEdited` rebuilds the ground
**surface** through the same `configureGround` the export uses, then rebuilds the object preview,
because objects anchored to terrain have just moved with it. `probe_editor_tools.gd` asserts the
editor's ground is a real `ArrayMesh` after a sculpt rather than the flat `PlaneMesh` — the check
that fails first if the edit is recorded, undoable and invisible.

Objects are previewed through `WorldMapSceneExport.buildObjects` with a **null scene owner** — the
case that function already documented for a preview that is never packed — so the editor and the
export place a building by the same code rather than by two that agree today.

### Still out of scope

An object-kind palette beyond `house`/`tower`, a footprint editor, a smooth sculpt tool and a
raise-to-target sculpt tool are not part of this milestone. They are intentionally separate from
the working paint, rectangle and stamp routing described above.

## 18. Authored water

`WorldMapWaterLayer` over `WorldMapTileData.KIND_WATER` stores lakes and simple river sections:
which cells are wet, and what height each one's surface sits at. No flow, no simulation, no tide.

### Water is not a terrain type

The risk this item was written against, and the reason for every shape below. A lowered basin is
**terrain**; whether it holds water is a separate authored fact. Nothing in the water layer writes
a height, and `WorldMapHeightField` never reads the water layer — so a dry basin and a flooded one
differ in exactly one place, and an author can express both.

`probe_water_layer.gd` checks both halves separately, because only the pair is convincing: a
2.0-deep basin nobody flooded reports zero wet cells, **and** a cell flooded to exactly `0.0` over
flat ground reports wet.

### Dry is not height zero

The store is **text**, not floats. A dense float array cannot say "dry" without inventing a
sentinel, and a map whose ground sits at 0 would then be indistinguishable from one flooded to 0.
`EMPTY` (`-`) is already this format's word for "nothing here" — grid and detail layers both use
it — so dryness is spelled the way absence is spelled everywhere else, and it serialises through
the same `encodeRLE` an unpainted layer does: a dry map is one run.

### One value per cell, not per vertex

The terrain is a vertex lattice because a hillside is continuous. A water surface is not: it is
flat across a body and **steps** between bodies. So water is cell-addressed, and there is no
interpolation anywhere in this file — a surface that sloped between neighbouring cells could not
be flat by construction.

That gives both shapes the item asked for without tracking connected components: a lake is level
because every cell in it was given the same height, and a river descends because each cell was
given a lower one. The mesh does **not** share vertices between cells, so two cells at different
heights meet at a visible step rather than being smoothed into a ramp — the difference between a
river that descends and one that leaks uphill.

### The look is the region's own sea

Agreed with the user before implementation, per the item. `void_color` is already what lies beyond
the map's edge, and `WorldMapGroundUniforms` is explicit that it belongs to the *place* rather than
the framing — temp's sea is deep blue, temp2's teal. So an **authored lake is the same water as
the ocean past the edge**, and the shore tint is that colour carried `SHORE_MIX` of the way toward
the region's own `fog_color`. No colour was imported from anywhere.

The band rides in **vertex colours** — deep at `SHORE_DEPTH` or more, shore tint at the waterline —
read as albedo by an unshaded material. No shader, no texture, and the map stays unlit art rather
than gaining one surface that reacts to a sun nothing else knows about.

### The bug that only looking could find

The first build drew an authored lake visibly **paler** than the identical colour past the map's
edge. `void_color` and `fog_color` are sRGB — they arrive from the region catalog as hex — and a
vertex colour is taken as **linear** unless the material says otherwise, so the same value came out
brightened. Every colour assertion in the probe passed throughout: they check the stored value, and
the fault was in how it was interpreted.

`vertex_color_is_srgb = true` fixes it, and the probe now asserts that flag with the reason — a
render check cannot live in a headless probe, but the flag it depends on can.

### What the deferred check found, and did not fix

**Water is not fogged.** The ground hazes toward `fog_color` with distance inside
`worldmap_ground.gdshader`; the water is a plain unshaded material and does not. A distant lake
therefore stays crisp while the land around it fades. The project already has the answer for this
shape — `worldmap_prop.gdshader` "transcribes this file's fog" for exactly the same reason — but a
water shader is not in this item's Touches list and is its own piece of work.

**A steep-walled basin has no visible band.** The band is driven by depth, so it appears where
water is shallow; flatten a lake floor to −3.0 in one step and the water goes from shore to open
sea within a single cell. That is the specification behaving correctly, not a defect, but it means
a band is a property of the *terrain* an author sculpts rather than something water draws for
itself. A distance-to-shoreline band would behave differently and is the obvious alternative if
this reads wrong in use.

**No authoring tool.** Water is currently authored through the API, as heights, objects and detail
were before their workspace tools existed. §17's pattern makes adding one small; it remains future
editor work.


## 19. Bridges

`WorldMapObjectLayer.placeBridge` and `.clearance` model a bridge without a new record shape:
it is an ordinary placed object (§14) whose `HEIGHT` is a **deck height** and whose `ANCHOR` is
`ANCHOR_FIXED`. Nothing about the format changed; the item's whole content is that one field
combination getting a name, and a clearance check that compares it with authored water.

### Deck height is authored, not derived — and that was already expressible

An object anchored `ANCHOR_FIXED` ignores whatever sampler it is
given and returns its own `HEIGHT` unchanged (§14). That is already "authored, not derived" —
which means a bridge needed no new storage, no new anchor mode and no change to `anchorHeight()`
or `worldPosition()`. What it needed was **a call site that cannot get this wrong by accident**:
`placeBridge(data, kind, cell, deckHeight, ...)` bakes in `ANCHOR_FIXED` so a caller placing a
"bridge" kind object cannot pass `ANCHOR_TERRAIN` and silently get a bridge that drapes onto the
riverbed the moment the terrain under one corner changes — the exact failure the item's End state
describes.

### Clearance checks both surfaces, per cell, and reports the worst

The one genuinely new function. `clearance(record, terrainSampler, waterSampler)` walks every cell
of the bridge's footprint (§14's own `footprintCells`, unchanged) and compares the deck against
**both** the terrain and any authored water there, returning the smallest (possibly negative)
gap, which cell produced it, and which surface.

**Both surfaces, not the lower one alone**, is the part worth explaining. A deck that clears a
riverbed by a wide margin but sits at or below the *water surface* above that riverbed has cleared
nothing — it is a bridge sitting **in** the river. Reducing "clearance" to a single number per
cell by keeping only the deeper surface is exactly the shortcut that would hide that. So both are
checked at every cell, and the answer is the worst across the whole set.

### A dry cell's water sampler answers `null`, not `0.0`

`waterSampler` is a caller-supplied `Callable`, exactly like `terrainSampler` and `anchorHeight`'s
own sampler before it (§14) — this file still does not preload `WorldMapHeightField` or
`WorldMapWaterLayer`, keeping the decoupling those two already established. The contract for a dry
cell is `null`, not a height of `0.0`, carrying "dry is not height zero" one
layer up: a water sampler that answered `0.0` for a dry cell would make every bridge crossing dry
land on its way to a river report a false near-miss against phantom water at sea level.
`probe_object_layer.gd` checks this by comparing an always-dry sampler's result against no water
sampler at all — they must agree exactly, and a version that read `null` as `0.0` was confirmed to
fail that check before the fix landed.

### What the deferred check found

Rendered as a placeholder box (§14's own object body — bridges get no new art in this item), an
authored deck sits visibly above the water it spans rather than draped into it, matching the
clearance the same map's own `clearance()` call reported. The box is a poor stand-in for a span —
it has no rails, no deck plane wider than the object's footprint, and no visible connection to the
banks either side — but the **position** is the thing this item is answerable for, and the render
confirms it holds.

## 20. The tactical layer, and exporting a battle map

A region can carry a **battlefield**: which of its cells a battle is fought on, and what each of
those costs to cross. It exports beside the gameplay scene of §13 as the tactical map
`BattleSimulator` reads.

### It is a plain grid layer, and that is the whole design

`WorldMapTacticalLayer` stores terrain ids in an ordinary `grid` layer. It adds no storage kind,
no format version, and not one line to `WorldMapTileData` or `WorldMapEditHistory` — because the
document format is layer-agnostic on purpose, and its own class note names "walkability" as
exactly the kind of thing a later cycle should be able to add as *data*. So run-length encoding,
`paintCell`'s undo/redo, and save/reopen all already worked before this layer existed.

What it does need is three exceptions in `WorldMapEditorController`, all in one direction: the
tactical layer is a grid layer with **no tileset**, because its values are ledger ids rather than
tile art. `_layerEditable`, `_layerPopulated` and `_refreshValueChoices` each carry that exception
rather than the "a grid layer is painted from a tileset" assumption being loosened for ground and
overlay too.

### Tactical meaning is authored, never inferred from art

An empty cell on this layer means **not part of the battlefield** — not "clear ground". Deriving
the playable area from wherever ground tiles happen to sit would read a decorative decision as a
gameplay one, and on the existing hex document it would do visible harm: the cells under its nine
buildings carry no ground tile precisely *because* those buildings are objects, so inference would
delete exactly those cells from the board.

For the same reason a building does not block a cell until someone says it does. The fixture says
so explicitly — its nine buildings sit on `blocked` cells because that was painted, not because a
tower was detected.

An id outside the ledger is an **authoring error**, and refuses the export naming the cell. A typo
that silently became walkable ground is a balance change nobody made and nobody can see.

### What cannot be exported, and why refusing is the feature

The tactical model is one surface per cell at an integer elevation (`SURFACE_MODEL: "single"`).
Two authored things cannot be said in it, and both are refused by name and cell rather than
silently approximated:

| Refused | Why it cannot be represented |
|---|---|
| **Smooth terrain** | Heights live on the hex *vertex* lattice as continuous floats and nothing rounds them (§15). A cell whose vertices disagree is a slope, and flattening it to one integer puts the unit somewhere the ground is not. |
| **Bridges** | A fixed-anchor deck (§19) is a second walkable surface over a cell that already has one. Dropping it silently would hand the player a bridge they can see and cannot cross. |

**Authored water is not on that list.** Water here is decoration, it blocks nothing, and refusing
a map for having a lake in it would be the opposite of what §18 built.

A consequence worth stating plainly, because it constrains what a battle map can look like:
neighbouring hexes *share* their vertices, so the surface is continuous by construction. Two
adjacent **playable** cells therefore cannot sit at different elevations without a slope between
them. A battle map is flat across its playable area, or its elevation changes fall on cells that
are off the board — a cliff you cannot stand on. The fixture is flat at elevation 0.

### Exporting both products at once

`Ctrl+Shift+E` uses the saved-snapshot publication flow in §13. The visual scene and tactical
definition come from one versioned document in one action, carry its UUID, revision and fingerprint,
and use one stable UUID-derived stem. Exporting them separately would allow a scene to describe a
different source revision from the battle definition.

A refusal reaches the status line with the feature and the cell in it. "Unsupported" alone does
not tell an author which hill to flatten.

The earlier `hex_battle_fixture` and PNG-import workflow belongs to the legacy raw-region pipeline.
It remains useful for its existing fixtures, but it is not the creation path for a new foundation
map. New maps are saved as `.noggmap.json`, then published with Export Battle; Save never regenerates
derived art, and Export Battle writes a reloadable `.tres` texture directly.
