# World map hex authoring

Opened 2026-09-06. The successor cycle to `worldmap-editor`, re-cut with the hex decision
settled. It replaces that file's provisional Phases C and D; Phases A and B are done and
committed (WME-1 through WME-9) and are **not** revisited.

Three things forced the re-cut, and they are recorded in `worldmap-editor.md`'s own dated
addendum rather than here:

1. A hands-on playtest found the scene is a working preview shell, not an editor: the document
   never loads into the tools, and two camera/focus defects make it awkward to drive.
2. The confirmed product is a 3D-oriented equivalent of Tiled — object placement and smooth
   terrain are **core workflow**, not deferred phases, and authored maps must export into
   gameplay scenes independently of the debug scene.
3. The grid is now **hexagonal**, decided 2026-09-06 after a measured prototype.

This is not a restart. Every foundation from Phases A and B survives the hex switch, most of it
untouched — see "What is already built".

## What is settled, and is not open here

**The hex.** Flat-top, and that is load-bearing rather than taste. A regular flat-top hex has
width:height of 2:√3, and the pitch-60 vertical squash is sin(60) = √3/2. They cancel, so a
flat-top hex pre-stretched to read regular on screen has a **square world footprint**. Pointy-top
gets no such property: it needs 3:4 frames and non-square world cells.

**The dimensions**, measured rather than chosen by feel:

| | value |
|---|---|
| Sheet frame | 32 × 32 px |
| Hex vertices in frame | (32,16) (24,32) (8,32) (0,16) (8,0) (24,0) — all whole pixels, every slanted edge a 1:2 slope |
| World width of one hex | **2 world units** (the 16 px world unit is unchanged) |
| Column advance | 1.5 units |
| Row advance | 2 units, odd columns dropped 1 unit |

Keeping the 16 px world unit and letting a hex span two of them is what lets the **existing
framing presets** work without redefining the tile law: `tile_exact` gives ~35 hexes across,
close to the ~34 the console reference used, with a 7.2 px slanted-edge run at 1920×1080.

**Sub-triangles replace cels.** Hexagons do not tile into smaller hexagons, so the four-cels-per-
tile rule has no hex translation. A hex fans into **6 triangles from its centre** with no
arbitrary diagonal choice — which is also the triangulation smooth terrain wants, so one
decision serves both.

**Buildings are placed objects, not ground pixels.** They come out of the ground texture and
back as instances with their own identity, position and height anchoring.

**The map is a square with a hex interior.** The author declares a square extent; the lattice is
inscribed in it; the remainder is margin. See WMH-2.

## What is already built, and must not be redone

Committed and load-bearing. An executing agent should read these rather than rebuild them:

- **The tile law** (`WORLDMAP_DESIGN.md` §1). 16 px world unit, and prop anchoring snaps to it.
- **Tileset identity** (`WorldMapTilesetCatalog`). Content hash plus an append-only `id → cell`
  ledger, five-pass reconciliation, palette validation at import. **Grid-agnostic**: a hex sheet
  is still a rectangular lattice of frames, and it imports unchanged.
- **`FRAME_PX`**, which separates a sheet's frame size from its grid kind. Added when a 32 px hex
  sheet was cut on the 16 px grid its kind implied and imported 300 quarter-hexes instead of 75.
- **The map format** (`WorldMapTileData`). `FORMAT_VERSION`, a migration hook, RLE one run per
  line, and — critically — **layer-agnostic**: a layer block declares its own storage kind, so
  adding heights, objects or water is a data change with no migration.
- **The baker** (`WorldMapBaker`). Deterministic, dirty-rect partial recomposition, full upload.
- **Stroke undo/redo** (`WorldMapEditHistory`). Delta-based, coalesced per stroke.
- **The surface solve** (`WorldMapSurfacePick.solveSmooth`). Ray against the curved paraboloid,
  closed form, near-tangency handled. **It returns a world point and knows nothing about grids**,
  so the hex switch touches only the final coordinate mapping.
- **The editor camera** (`WorldMapEditorCamera`). Orbit, unclamped pan, dolly, ortho, and a
  fixed-point curvature drop that agrees with the shipping rig to four decimals.

## Present-state facts an executing agent must not "fix"

- **The lattice is invisible over uniform terrain.** Adjacent hexes of one terrain merge into a
  blob; hex structure appears only at terrain boundaries and the map edge. This is a property of
  hexes, not a bug in the extraction — a square's silhouette carries no information, so the
  square tileset never had to answer it. The fix is art (per-cell edge treatment) or the grid
  overlay, and both are in scope below. Do not attempt to solve it by outlining every hex in the
  bake.

- **`temp2_hex32_ground` is 2× upscaled square art and is not the target look.** The source
  carries 16 px of information per tile; it was upscaled nearest so the *silhouette* has genuine
  32 px resolution over honestly-blocky content. It exists to settle geometry and framing. Do not
  tune anything visual against it.

- **Curvature is a rendering transform, not terrain.** `curvature_k` bends the world in view
  space and must never be stored in the map or baked into exported geometry. Terrain height is a
  separate, authored quantity.

- **The `temp2_authored` square map still bakes byte-exact against temp2's first 240 px.** That
  parity test is the sharpest validation in the programme. The square path stays working while
  the hex path grows beside it; do not delete or "migrate" it.

- **`probe_editor_input_dispatch` exists because handler-by-name tests lied.** An
  `_unhandled_input` override on a node inside the "World" `SubViewport` never receives real
  events. Any new input work is tested through `Input.parse_input_event()`, not by calling
  handlers directly.

- **Continuous heights are classifiable.** An earlier note in `worldmap-editor.md` claimed
  continuous heights make slope classification undecidable. That is false — an explicit slope
  threshold classifies them. Do not reintroduce quantised-only heights on that reasoning.

## Items

---

## Phase 1 — Repairs, and the hex foundation

### WMH-1 — Repair the camera fit and shortcut focus defects

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Two defects with a known cause each and a fully stated end state. The
aspect maths is given below and the focus fix is a property set on controls that already exist;
no boundary moves and nothing downstream depends on the internals.

**Depends on:** nothing.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapEditorCamera.gd`
- `src/presentation/worldmap/editor/WorldMapEditorController.gd`
- `debug/worldmap/probe_editor_input_dispatch.gd`

**End state:** `F` fits the whole region inside the actual display rect with a margin, in both
projections and at any camera orientation and window aspect. `Tab`, `Space` and `F` never also
activate a focused HUD control.

**Implementation:** `frameRegion()` currently uses `max(region.w, region.h) * 0.6` and ignores
aspect entirely, which is why it crops a portrait-shaped viewport. Fit **both** axes: project the
region's bounds into camera space, take the extent needed on each axis, and satisfy the binding
one — for orthographic that is `size` against the display rect's aspect, for perspective the
distance that contains both the vertical FOV and the horizontal FOV implied by aspect. Use
`_displaySize()`, not the window: the editor's map column is not the window.

Set `focus_mode = FOCUS_NONE` on the inherited debug HUD's controls **from the editor
controller, at build time** — not by editing `WorldMapDebugHud`, which the shipping debug scene
also uses and whose keyboard behaviour must not change.

**Risk:** Fitting to the binding axis is easy to get backwards, which crops instead of padding.
The probe checks that every region corner projects inside the display rect after a fit.

**Validation:**
- Self-contained: `probe_editor_input_dispatch.gd` gains a fit check (all four region corners
  inside the display rect, in both projections, at three window aspects including portrait) and
  a focus check (dispatch Tab/Space/F through `Input.parse_input_event()` with a HUD control
  focused; assert the camera acted and the control did not).
- Deferred: F, Tab and Space feel right after clicking around the HUD.

### WMH-2 — Hex coordinates, the square map, and hex picking

**Model:** Opus 5 / GPT Sol

**Model rationale:** The boundary every later item is written against. It fixes the coordinate
system, the map's shape, the neighbour set, and the rounding rule — and cube rounding is a
classic silent-failure: the naive round of three fractional coordinates violates the `x+y+z = 0`
invariant and lands one hex off along a seam, which looks like an off-by-one in the picker rather
than a coordinate bug. Wrong here is wrong everywhere downstream.

**Depends on:** nothing.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapHexGrid.gd` (new)
- `src/presentation/worldmap/editor/WorldMapSurfacePick.gd`
- `src/presentation/worldmap/editor/WorldMapTileData.gd`
- `debug/worldmap/probe_hex_grid.gd` (new)
- `debug/worldmap/probe_pick_accuracy.gd`
- `docs/WORLDMAP_EDITOR.md`

**End state:** `WorldMapHexGrid` owns axial↔world conversion, the 6 neighbours, hex distance,
cube rounding, and the square-map layout. `WorldMapSurfacePick` resolves a screen position to a
hex by replacing its `floor()` with that rounding; the ray solve is untouched.

**Implementation:** Flat-top, axial `(q, r)`, with the dimensions in "What is settled". Store
axial and convert to cube only inside rounding — cube exists for the maths, not as the storage.

**Round in cube space and reset the largest-delta component.** Rounding `q` and `r` independently
is wrong along every hex seam.

**THE SQUARE MAP.** A region declares a **square extent in world units**; the lattice is
inscribed in it, and the remainder is margin. The margin is a **bake concern, not data**: only
hexes exist as cells, and `WorldMapBaker` fills the leftover with the region's void colour.
Keeping the margin out of the data model is what stops "is this cell a hex or filler?" from
having to be answered everywhere downstream.

Exact-fit lattices exist where `3C = 4R + 1`, and are worth offering as suggested sizes:

| cols × rows | units | px | hexes |
|---|---|---|---|
| 7 × 5 | 11 × 11 | 176 | 35 |
| 15 × 11 | 23 × 23 | 368 | 165 |
| 31 × 23 | 47 × 47 | 752 | 713 |
| **103 × 77** | **155 × 155** | **2480** | **7931** |

The last is not arbitrary: 155 units is exactly the region width `WORLDMAP_DESIGN.md` §3 says the
reference framing demands before plane edges stop showing. A prototype may be far smaller and
show its edges, as `temp2` already does.

**Risk:** Odd-column offset conventions differ between references; picking one and not writing it
down produces a half-row shift that only shows at a map edge. The convention is: **odd columns
drop by one unit**, and the probe asserts it against explicit hand-computed positions.

**Validation:**
- Self-contained: `probe_hex_grid.gd` — axial→world→axial round-trips over the whole lattice;
  all 6 neighbours are at distance 1 and no other cell is; distance is symmetric and matches a
  hand table; rounding is exact for a dense sample of points including exact vertices and edge
  midpoints, which are where naive rounding fails. `probe_pick_accuracy.gd` gains a hex round
  trip at every framing and curvature, and under free orbit.
- Deferred: none.

### WMH-3 — The hex grid overlay

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** One shader function with a stated technique, behind a `grid_mode` uniform
that already exists and already defaults off, so the shipping path cannot be disturbed. The
decision about what the overlay is *for* was made in WME-8; this changes its shape.

**Depends on:** WMH-2.

**Touches:**
- `assets/shaders/worldmap_ground.gdshader`
- `src/presentation/worldmap/editor/WorldMapSurfacePick.gd`

**End state:** `grid_mode` draws a hex lattice rather than square lines, with the cursor
highlighting a hex. Sub-triangle lines appear only while a sub-triangle tool is active.

**Implementation:** The square version used `fract()` on world XZ, which has no hex analogue.
Use the standard hex distance field: fold the position into a half-cell, then take the maximum
of the distance to the vertical edge and to the two slanted edges. Keep the existing `fwidth`
screen-space width treatment — it is what stops the lattice aliasing into a moire at the far
edge of a pitch-60 frame, and that reasoning is unchanged by the shape.

**Risk:** A hex SDF that is subtly wrong reads as a plausible lattice that does not line up with
the cells picking returns. Assert alignment rather than eyeballing it: the cursor highlight and
the picked hex must be the same cell.

**Validation:**
- Self-contained: a probe renders the overlay with a known hex highlighted and asserts the
  highlighted region's centroid is the picked hex's world centre.
- Deferred: the lattice reads clearly at pitch 60 and does not shimmer.

### WMH-4 — Hex brushes

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A defined list of tools over a coordinate system, a history and a picker
that all exist by then. The geometry decisions are made here in the plan rather than left to the
executor.

**Depends on:** WMH-2.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapBrushes.gd`
- `debug/worldmap/probe_brushes.gd`

**End state:** Paint/erase, line, flood fill, eyedropper, stamp, scatter and replace-kind all
operate on hex cells. Each is one undo entry.

**Implementation:** The decisions, so they are not re-litigated:

- **Line** — cube lerp between endpoints, rounding each sample. Not Bresenham.
- **Flood fill** — 6 neighbours, bounded by the lattice and by terrain kind.
- **Rectangle becomes RANGE**, a hex disc of radius N around a centre. A rectangle has no
  natural hex meaning, and a parallelogram in axial space looks skewed on screen; a disc is what
  a user drawing on hexes expects.
- **Stamp** — patterns stored as axial offsets from an anchor, so a stamp is orientation-stable
  rather than depending on which column parity it lands on.
- **Scatter** — unchanged, and keeps its stored seed so a region re-bakes identically.

**Risk:** Column-parity bugs in offset arithmetic, which show only on odd columns. Every probe
case includes both parities.

**Validation:**
- Self-contained: `probe_brushes.gd` reworked for hex — each tool exercised on both column
  parities, one history entry per operation, flood fill respecting the 6-neighbour set, and a
  line whose every step is distance 1 from the last.
- Deferred: none.

### WMH-R1 — Gate 1: does hex authoring feel right?

**Model:** Opus 5 / GPT Sol

**Model rationale:** A judgement against a working tool, with the authority to re-cut the
remaining phases or end the programme. It also revisits a dimension -- whether 32 px is the right
hex size -- that everything after it is drawn against, so getting it wrong is expensive in art
rather than in code.

**Depends on:** WMH-1, WMH-2, WMH-3, WMH-4.

**Touches:**
- `docs/plans/reviews/worldmap-hex-gate-1.md` (new)

**End state:** A verdict of CONTINUE, REVISE or STOP with evidence, run against a real window.

**Implementation:** Paint a small hex map by hand and answer: is 32 px the right hex size at the
framing you actually use, or does it want to be 24 or 48? Does the overlay carry the lattice well
enough that uniform terrain is still navigable? Do the brushes behave as expected on both column
parities? Is the square-with-margin shape right, or does the margin want a terrain rather than the
void colour? A gate returning CONTINUE without naming one thing it would change was not run.

**Validation:**
- Deferred: this item is the check. Quiet tree, alone.

---

## Phase 2 — The document loop, and getting maps out

Provisional until Gate 1. Nothing here depends on objects or terrain, and the playtest was
explicit that the document loop is what turns a preview into an editor.

### WMH-5 — The document lifecycle

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A conventional new/open/save/save-as loop over a document model, a history
and a HUD that all already exist, with the one real design call -- hanging the dirty flag off the
history rather than off each tool -- made below. No boundary moves.

**Depends on:** WMH-4 (or Gate 1's re-cut).

**Touches:**
- `src/presentation/worldmap/editor/WorldMapEditorController.gd`
- `src/presentation/worldmap/editor/WorldMapEditorHud.gd`
- `debug/worldmap/probe_document_loop.gd` (new)

**End state:** New, open, save and save-as, with a visible dirty marker, a guard on discarding
unsaved changes, and honest layer rows — a layer shows as populated when it has data and empty
when it does not.

**Implementation:** The playtest found `_document` null while the HUD still offered Ground and
Overlay as editable; WME-9 connected loading, and this completes the loop around it. A new map
asks for its square extent and lattice size, offering the exact-fit table from WMH-2.

**Risk:** A dirty flag that misses a mutation path, so work is lost silently. Every mutation
already goes through `WorldMapEditHistory`; hang the flag off that rather than off each tool.

**Validation:**
- Self-contained: `probe_document_loop.gd` — new/edit/save/reopen reproduces the document
  exactly; the dirty flag is set by every brush and cleared only by a save; discarding is
  refused while dirty unless confirmed.
- Deferred: the flow is clear at the keyboard.

### WMH-5B — Bake a hex map

Inserted 2026-09-07, after WMH-5 found the gap by creating the first hex document there was ever
anything to bake. Numbered `5B` rather than renumbering WMH-6 through WMH-13, because those ids
are already referenced by committed `Plan-Item:` trailers, by
`docs/plans/reviews/worldmap-hex-gate-1.md` and by `docs/WORLDMAP_EDITOR.md` — a renumber would
invalidate all of them to buy nothing.

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Every geometric decision is settled below, each with the arithmetic that
makes it exact, and the one subtle failure has a byte-exact test written for it. What is left is
a careful edit to one file. No boundary moves and nothing downstream changes shape.

**Depends on:** WMH-2 (the lattice geometry). Scheduled after WMH-5 so there are real hex
documents to bake.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapBaker.gd`
- `debug/worldmap/probe_bake_parity.gd`
- `docs/WORLDMAP_EDITOR.md`

**End state:** A hex document bakes to a correct contiguous texture, a partial flush is
byte-identical to a full re-bake, and `temp2_authored`'s square byte-exact parity is unchanged.
WMH-5's "Ground render is provisional" status text comes back out.

**Implementation:** `WorldMapBaker` assumes a square lattice in three separate places, and each
has its own fix.

- **Canvas size.** `pixelSizeOf` returns `size_tiles * TILE_PIXELS`; on a hex document
  `size_tiles` is columns and rows, not world units. Use `data.worldExtent() * TILE_PIXELS` —
  WMH-2 already built it, and it returns `Vector2(size_tiles)` unchanged for a square map. It
  lands on whole pixels for every lattice, so there is no rounding decision to make:
  `x = 24(C−1) + 32`, `y = 32(R−1) + 48`.

- **Source frame size.** `_composeRect` takes its frame size from `gridPixels(GRID_KIND)` — 16 for
  `tile`, 8 for `cel`. The hex sheet's frames are **32 px**. Read `FRAME_PX` off the tileset
  reference `_loadSheets` already holds instead. This is the same `GRID_KIND`/`FRAME_PX`
  conflation that once cut a 32 px sheet on a 16 px grid and imported 300 quarter-hexes instead of
  75; `FRAME_PX` exists precisely to separate the two. A no-op for `temp2_ground`, whose
  `FRAME_PX` is 16 and whose grid kind also says 16.

- **Destination placement.** `to = cell * cellPx` is a square lattice. On hex use
  `WorldMapHexGrid.cellCentre(cell) * TILE_PIXELS − framePx / 2`, centring each frame on the cell
  it belongs to. Exact at both ends: cell (0,0)'s frame lands on the origin, and the last cell's
  frame ends on the canvas corner.

  Frames OVERLAP, and that is correct rather than something to design around — a 32 px frame on a
  24 px column pitch overlaps its neighbouring columns by 8 px. The sheet already carries the
  alpha that makes this work, measured rather than assumed: **0 of 320 frame corners in
  `temp2_hex32_ground` are opaque**. So `blend_rect`, which the composer already uses, composites
  hexagons that tile the plane exactly and never overwrite one another. Do not add a masking
  pass. In particular do **not** mask at import: that would change every content hash and break
  the append-only ledger `WorldMapTilesetCatalog` maintains. Assert the contract instead (see
  Validation), so a future hex sheet cut without its mask fails loudly rather than rendering as
  corner-shaped overwrite artifacts.

- **The dirty rect.** `markCellsDirty` converts cells to pixels with the same square multiply, and
  `_composeRect` inverts it to decide which cells a rect touches; both must go through the
  placement above. And because frames overlap, a partial recompose has to redraw every cell whose
  FRAME intersects the dirty rect, not every cell whose origin falls inside it — `_composeRect`
  clears to transparent before compositing, so getting this wrong does not merely leave a stale
  fringe, it ERASES an 8 px strip of up to four neighbours. Expand the marked pixel rect by one
  full frame on all sides before snapping; the parity check below is what proves that sufficient.

**Risk:** The overlap, in the partial-flush path specifically. A full bake can be perfectly
correct while every edit quietly eats a strip of its neighbours — and that appears only while
editing, never in a from-scratch bake, which is exactly what a naive test would check.

**Validation:**
- Self-contained: `probe_bake_parity.gd`, extended.
  - `temp2_authored`'s existing byte-exact assertion, untouched and still passing.
  - Canvas size equals `worldExtent × 16` exactly, across several lattices from
    `exactSquareLattices()`.
  - Cell (0,0)'s frame lands on the origin, every cell's frame lies inside the canvas, and the
    union of all frames equals the canvas exactly.
  - **Partial-flush parity:** bake fully, edit one cell, `markCellsDirty` + `flush`, and compare
    byte-for-byte against a from-scratch bake of the same data — once for a cell in an even
    column and once for an odd one. This is the assertion that catches the risk above.
  - Frame-corner alpha: every frame of a 32 px hex tileset is transparent at its four corners, so
    the overlap contract is checked rather than trusted.
- Deferred: a painted hex map renders as continuous hexagonal terrain, with no seams and no
  corner-shaped overwrite artifacts.

### WMH-6 — Export a gameplay scene

**Model:** Opus 5 / GPT Sol

**Model rationale:** This decides runtime ownership — what a shipped map *is*, separate from the
editor that made it. `PackedScene.pack()` only captures nodes it owns, and exported resource
dependencies are easy to get wrong in a way that loads fine in the editor and fails from a clean
project. It is also the first time authored data crosses out of presentation.

**Depends on:** WMH-5, WMH-5B. The export carries the baked terrain, so it cannot be judged
correct while the bake it exports is not.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapSceneExport.gd` (new)
- `scenes/worldmap/` (new)
- `debug/worldmap/probe_scene_export.gd` (new)
- `docs/WORLDMAP_EDITOR.md`

**End state:** An authored map exports to a reusable scene containing the terrain and placed
objects and **nothing** of the editor — no HUD, no editor camera, no debug controller. A
gameplay scene supplies its own camera and environment. Re-exporting updates generated content
without destroying hand-authored additions in a wrapper scene.

**Implementation:** One builder constructs the runtime hierarchy for **both** the editor preview
and the export, so what is authored and what ships cannot drift. Set `owner` explicitly on every
node that must survive `pack()`. Curvature stays a rendering transform and is never baked into
exported geometry.

**Risk:** A scene that loads in the editor and fails from a clean project because a resource was
referenced rather than saved. The probe loads the exported scene in a fresh `SceneTree` with the
editor scripts absent.

**Validation:**
- Self-contained: `probe_scene_export.gd` — export, reload in a fresh tree, assert the terrain
  and objects match the source and no editor class is present in the instantiated tree.
- Deferred: the exported scene renders correctly inside a gameplay scene.

### WMH-R2 — Gate 2: is a map usable outside the editor?

**Model:** Opus 5 / GPT Sol

**Model rationale:** Judges the first crossing out of the editor into the runtime, which is the
premise Phases 3 and 4 build on. If an exported map is not usable, adding objects and terrain to
the editor makes the problem larger rather than closer to solved.

**Depends on:** WMH-6.

**Touches:**
- `docs/plans/reviews/worldmap-hex-gate-2.md` (new)

**End state:** A verdict, with a map authored, saved, reopened, exported and instantiated in a
scene with the editor absent.

**Validation:**
- Deferred: this item is the check. Quiet tree, alone.

---

## Phase 3 — Objects and terrain

Provisional until Gate 2. This is where the tool stops being a tile painter.

### WMH-7 — The placed object layer

**Model:** Opus 5 / GPT Sol

**Model rationale:** Introduces a second kind of authored thing, with its own identity that
quests and save data will later reference. Anchoring an object to terrain that can move under it
is a real coupling, and `WORLDMAP_DESIGN.md` §9 records that moving a structure's *record* rather
than its sprite is the difference between a fix and a defect no probe catches.

**Depends on:** WMH-6 (or Gate 2's re-cut).

**Touches:**
- `src/presentation/worldmap/editor/WorldMapObjectLayer.gd` (new)
- `src/presentation/worldmap/editor/WorldMapTileData.gd`
- `src/presentation/worldmap/editor/WorldMapSceneExport.gd`
- `debug/worldmap/probe_object_layer.gd` (new)

**End state:** Objects are placed instances with a **deterministic id**, a hex position, an
orientation, a footprint and a height anchoring rule. They render as upright sprites or simple
models, and they export. temp2's nine structures are re-placed as objects rather than living in
the ground.

**Implementation:** A `list`-kind layer, which the format already supports. Ids are deterministic
per `AGENTS.md` — never `get_instance_id()`.

Objects stay upright by default. Anchoring is to the terrain surface **at the object's own
footprint**, so raising ground under a building lifts it rather than burying it.

**Risk:** An object and its shadow or lamp drifting apart, which is §9's documented invisible
failure. One record feeds every derived thing, as it does for the existing props.

**Validation:**
- Self-contained: `probe_object_layer.gd` — ids stable across edits and a save/reload; an object
  re-anchors when the terrain under it moves; objects survive export.
- Deferred: placed buildings read correctly at the shipping framing.

### WMH-8 — Smooth terrain on the hex vertex lattice

**Model:** Opus 5 / GPT Sol

**Model rationale:** Chooses the surface every other system must agree on — rendering, picking,
object anchoring and export all sample it, and a second interpolation anywhere means two surfaces
that disagree. It also adds a second displacement to a vertex stage that already carries
curvature.

**Depends on:** WMH-7.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapHeightField.gd` (new)
- `src/presentation/worldmap/editor/WorldMapTileData.gd`
- `src/presentation/worldmap/WorldMapGround.gd`
- `assets/shaders/worldmap_ground.gdshader`
- `debug/worldmap/probe_height_field.gd` (new)

**End state:** Heights live on the **hex vertex lattice**, shared between the three hexes meeting
at each vertex, with raise/lower/smooth/flatten tools. Hills, lake basins and riverbeds are
authorable. **One** interpolation, sampled identically by rendering, picking, anchoring and
export.

**Implementation:** A hex vertex is shared by **three** cells, not four, which is why the
triangulation is unambiguous: each hex fans into 6 triangles from its centre, and no diagonal has
to be chosen. That is the same fan the sub-triangle detail layer uses, so the two agree by
construction.

Heights are **continuous**, not quantised. Slope classification uses an explicit threshold —
the earlier claim that continuous heights make it undecidable is false and is not a reason to
quantise.

Height is applied in region space, curvature after — reversing them curves the heights. Curvature
must never be stored.

**Risk:** Picking and rendering sampling the surface differently, so the cursor sits off the
visible ground on a slope. `WorldMapSurfacePick`'s solve was written to take a height term as a
refinement seeded from the smooth root; use that rather than rewriting it.

**Validation:**
- Self-contained: `probe_height_field.gd` — a vertex edit moves exactly the three hexes sharing
  it; picking on a slope returns the hex the renderer draws there; a flat field renders
  identically to no height field at all.
- Deferred: a sculpted hill and basin read as terrain.

### WMH-9 — History for heights and objects

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** One file, widening a delta's value type from a tile-id string to also cover
floats and object records. The structure -- delta-based, coalesced per stroke, one stack -- is
already built and proven by a fuzz test; this extends what it carries, not how it works.

**Depends on:** WMH-8.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapEditHistory.gd`
- `debug/worldmap/probe_edit_history.gd`

**End state:** One user-facing undo history covers tile, height and object edits. Ctrl+Z after a
sculpt undoes the sculpt.

**Implementation:** The stack is already delta-based and coalesced per stroke; what changes is
that a delta's value is no longer always a tile-id `String`. Keep one stack — separate stacks per
edit kind would undo in an order the user never performed.

**Risk:** Float heights compared exactly, so a no-op sculpt still pushes an entry. Compare with a
tolerance, matching how `setCell` reports whether anything changed.

**Validation:**
- Self-contained: the existing fuzz extended to interleave tile, height and object strokes, still
  round-tripping to the exact starting state.
- Deferred: none.

### WMH-10 — The sub-triangle detail layer

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A new layer over a format that is already layer-agnostic, reusing the exact
triangulation WMH-8 establishes. The design decision that made cels hard on hex -- what replaces
them -- is settled at the top of this file, leaving a specified implementation.

**Depends on:** WMH-8.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapTileData.gd`
- `src/presentation/worldmap/editor/WorldMapBrushes.gd`
- `src/presentation/worldmap/editor/WorldMapBaker.gd`
- `debug/worldmap/probe_subtriangles.gd` (new)

**End state:** Each hex carries 6 triangular detail slots, paintable independently and composited
over the ground in the bake. Detail is art only — nothing an entity observes.

**Implementation:** The same fan WMH-8 triangulates with, so a detail slot and a terrain triangle
are the same region of the hex.

**Risk:** Detail becoming a second source of truth for terrain. It is art: no walkability, no
height, no collision.

**Validation:**
- Self-contained: `probe_subtriangles.gd` — 6 slots per hex resolve distinctly; painting detail
  leaves tile-grade layers untouched; the bake composites detail over ground.
- Deferred: none.

### WMH-R3 — Gate 3: is the authoring workflow complete?

**Model:** Opus 5 / GPT Sol

**Model rationale:** The last gate before water and the final validation, and the point where the
confirmed product -- paint, sculpt, place, save, export -- is either demonstrably there or not.
Deciding that is a judgement, and so is choosing to stop with it unfinished.

**Depends on:** WMH-9, WMH-10.

**Touches:**
- `docs/plans/reviews/worldmap-hex-gate-3.md` (new)

**End state:** A verdict, with a map carrying painted ground, detail, a sculpted hill and basin,
and placed buildings — authored, undone, redone, saved, reopened and exported.

**Validation:**
- Deferred: this item is the check. Quiet tree, alone.

---

## Phase 4 — Water, bridges, and proving the whole thing

Gate 3 ruled: continue as written, with one item inserted first. Phase 4 opens by making Phase 3
authorable, then adds water and bridges on top of a tool a person can actually drive.

### WMH-10B — The editor reaches the layers it stores

Inserted 2026-09-07 on the user's instruction, after Gate 3 found that the editor exposes ground
and overlay and nothing else — every part of that gate's authoring exercise which touched heights,
objects or detail had to be driven from a script. Numbered `10B` rather than renumbering WMH-11
through WMH-13, for the reason WMH-5B already gives: those ids are referenced by committed
`Plan-Item:` trailers, by three gate reviews and by `docs/WORLDMAP_EDITOR.md`.

**Model:** Opus 5 / GPT Sol

**Model rationale:** Every mechanism this item needs already exists and is proven — `paintHeight`,
`placeObject`, `paintTriangle`, the history, the bake. What does not exist is the decision of how
each one FEELS under a mouse: whether sculpting is a drag, a target height or a brush with a
radius; what a layer row means for a layer that has no tileset to pick from; whether a detail
click paints the triangle under the cursor or the whole hex. Those are three interaction models
decided at once, in the two files the whole tool is fronted by, and WMH-R1 is the record of how
contentious a feel decision in this tool can be. An item that cannot be written as a
specification is not a Sonnet item.

**Depends on:** WMH-9 (the history it routes through), WMH-10 (the detail slots it paints).

**Touches:**
- `src/presentation/worldmap/editor/WorldMapEditorController.gd`
- `src/presentation/worldmap/editor/WorldMapEditorHud.gd`
- `src/presentation/worldmap/editor/WorldMapBrushes.gd`
- `src/presentation/worldmap/editor/WorldMapHeightField.gd`
- `src/presentation/worldmap/editor/WorldMapEditHistory.gd` — added 2026-09-07 before execution,
  on the user's instruction. Omitted from the first draft of this list by mistake: the item's own
  End state requires detail edits to be undoable, and the history's public API (`paintCell`,
  `paintHeight`, `placeObject`) has no call that can carry a detail slot.
- `debug/worldmap/probe_editor_tools.gd` (new)

**End state:** A person with a mouse can sculpt terrain, place and remove a building, and paint a
sub-triangle — and undo any of it. The layer selector lists all four layers of an authored map,
honestly, including the ones that have no tileset.

**Implementation:** Three tools and the rows that make them reachable.

- **`_layerEditable` is the blocker, and it is one line.** It returns true only for
  `KIND_GRID` with a known tileset, so a height, list or detail layer can never become the active
  layer. It has to become kind-aware rather than grid-only, and everything that assumes the active
  layer has a tileset — `_refreshTileChoices` most of all — has to answer for a layer that has
  none. "Honest layer rows" (WMH-5) is the standard: a row says what it is, or says it is empty.
- **Detail painting routes through `WorldMapEditHistory`.** WMH-10 left `paintTriangle` as a
  direct mutator with no undo, named rather than hidden in `WORLDMAP_EDITOR.md` §16; a tool that a
  person can reach makes that gap a defect rather than a note. The history already carries three
  delta kinds; this is a fourth, and `_valuesEqual` already handles the String values it stores.
- **The fan test gets no third copy.** `WorldMapHeightField` owns `CORNER_OFFSETS` and the
  barycentric test in world space; `WorldMapBaker` deliberately duplicates it in pixel space. A
  click-to-triangle pick is a third caller, and it belongs beside the first — not as a new
  implementation of a shape that already has two.
- **The object tool decides placement, not art.** Buildings still ship as box placeholders (WMH-7);
  choosing a model is not this item's job. Placing, facing and removing one is.

**Out of scope, deliberately:** an object-kind palette beyond a fixed list, a footprint editor,
and hex routing for the Rectangle and Stamp tools (still square-only, named in
`WORLDMAP_EDITOR.md` §12, still not a blocker). This item is about reaching layers that are
currently unreachable, not about finishing every tool that touches them.

**Risk:** The item balloons. Three tools, two of the package's largest files, and a layer-row
rework is already the widest single item in this cycle; adding "and while we are here" work to it
is how it stops landing. The Out of scope list above is the boundary, and it is not advisory.

A second risk, smaller and specific: making `_layerEditable` kind-aware without also fixing what
reads the active layer's tileset produces a tool that silently paints nothing — the same class of
failure Gate 1 found in the picker, where an edit was refused with no word to the user.

**Validation:**
- Self-contained: `probe_editor_tools.gd` — each of the three tools, driven through the
  controller's own gesture entry points rather than by calling the modules underneath, changes the
  document and is undone by one undo; the layer selector offers all four layers of a map that has
  them; a click on a hex resolves to the triangle it landed in, not merely to the cell.
- Deferred: sculpting, placing and detail painting each feel right under a mouse, judged in a live
  editor session by the user.

### WMH-11 — Minimal water

**Model:** Opus 5 / GPT Sol

**Model rationale:** Decides a representation that terrain, objects and export all read, and
picks a visual language for something the game does not yet have. Representation is the hard
part; controls over it are not.

**Depends on:** WMH-10B — water is a fifth thing to author, and Gate 3's ruling was that it
should not arrive before the four that exist are authorable.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapWaterLayer.gd` (new)
- `src/presentation/worldmap/editor/WorldMapTileData.gd`
- `src/presentation/worldmap/editor/WorldMapSceneExport.gd`
- `debug/worldmap/probe_water_layer.gd` (new)

**End state:** Authored water **coverage** and **surface height** for lakes and simple river
sections, stored with the map and exported with it.

**Implementation:** A lowered basin is terrain, not water — water is a separate authored surface
at its own height. **No flow simulation.** The minimal appearance is agreed with the user before
implementation rather than imported from another game's look.

**Risk:** Water quietly becoming a terrain type, which makes a basin without water impossible to
express.

**Validation:**
- Self-contained: `probe_water_layer.gd` — coverage and height round-trip through save and
  export; a basin with no water stays dry.
- Deferred: water reads acceptably at the shipping framing.

### WMH-12 — Bridges

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** One additional object kind on a layer that already exists, whose only new
idea -- an authored deck height rather than a derived one -- is stated below. The clearance check
is arithmetic against surfaces WMH-8 and WMH-11 already expose.

**Depends on:** WMH-11.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapObjectLayer.gd`
- `debug/worldmap/probe_object_layer.gd`

**End state:** A bridge is a placed object with an authored **deck height**, so it spans a basin
or river rather than draping onto the riverbed.

**Implementation:** Deck height is authored, not derived — that is the whole difference between a
bridge and a road. Clearance against the water surface and the terrain under it is checked and
reported.

**Validation:**
- Self-contained: a bridge's deck stays at its authored height when the terrain beneath changes.
- Deferred: a bridge reads correctly over water.

### WMH-13 — Prove the whole workflow, and measure it

**Model:** Opus 5 / GPT Sol

**Model rationale:** Consolidates every deferred check in the cycle and makes the merge call, and
the acceptance is a judgement about whether the round trip preserved the map rather than a
pass/fail assertion. Design judgement in the acceptance forces standalone.

**Depends on:** WMH-12.

**Touches:**
- `docs/plans/reviews/worldmap-hex-validation.md` (new)
- `debug/worldmap/validation/hex/` (new)

**End state:** The acceptance example, end to end: create a map, paint hex ground, add
sub-triangle detail, sculpt a hill and a riverbed, place water, an upright building and a bridge,
undo and redo across all three edit kinds, save, reopen, export, and instantiate the result in a
gameplay scene with the editor absent. Verify appearance, terrain shape, object height and
resources survive the round trip.

Plus **measured timings** on a realistic full-size region — the 103 × 77 lattice from WMH-2 — for
representative strokes, a full bake, a partial rebake and navigation.

**Implementation:** Measure the implemented behaviour, which is partial CPU recomposition and a
full texture upload. Godot 4 has no partial 2D upload; do not report against the original plan's
promise of one.

**Validation:**
- Deferred: the whole item. Quiet tree, alone.

## Waves

Every wave below is legal: each item's dependencies are committed before it starts, and no two
items in one wave share a path. The predecessor cycle's wave table had two illegal waves — B1
paired WME-4 with its dependent WME-5 and gave both `docs/WORLDMAP_EDITOR.md`, and D4 paired
WME-18 with its dependent WME-19 — which is why this table is mostly single-item waves.

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | WMH-1, WMH-2 | camera/controller vs. hex grid and picking; no shared path |
| 2 | WMH-3, WMH-4 | ground shader + picker vs. brushes |
| 3 | **WMH-R1** | **gate, alone, quiet tree** |
| 4 | WMH-5 | controller and HUD |
| 5 | WMH-5B | baker and its probe; no path shared with WMH-5 |
| 6 | WMH-6 | export; new runtime boundary, alone |
| 7 | **WMH-R2** | **gate, alone, quiet tree** |
| 8 | WMH-7 | object layer; touches tile data and export |
| 9 | WMH-8 | height field; touches tile data, ground and the shader |
| 10 | WMH-9, WMH-10 | history vs. sub-triangles — **not** disjoint, both touch tile data; split if so |
| 11 | **WMH-R3** | **gate, alone, quiet tree** |
| 12 | WMH-10B | controller, HUD, brushes and the height field; alone |
| 13 | WMH-11 | water; touches tile data and export |
| 14 | WMH-12 | bridges |
| 15 | **WMH-13** | **validation, alone, quiet tree** |

WMH-5B is its own wave rather than sharing one with WMH-5: it depends on nothing WMH-5 adds, but
WMH-10 also touches the baker, so keeping the baker's own wave clean is what lets that later
pairing stay legible.

Wave 10 is flagged rather than asserted: WMH-9 touches only the history and its probe, WMH-10
touches tile data, brushes and the baker. They are disjoint **as listed**, but if WMH-9's height
deltas turn out to need a tile-data change, it becomes two waves. The gate before it decides,
with the code in front of it.

## Deliberately excluded

- **Autotiling.** Hex autotiling is genuinely cheaper than square — 6 edge-neighbours and no
  diagonal ambiguity, 2⁶ rather than 2⁸ — but it does not block proving the workflow, and the
  bootstrap art has no transition tiles to autotile with.
- **Elaborate cliffs and terrain self-shadowing.** Smooth hills and basins first; dedicated
  cliff art should not gate a hill prototype.
- **The travel graph, encounters and travel gameplay.** No gameplay rule is decided here.
- **Flow simulation.** Water is authored coverage and a height.
- **Pointy-top hexes.** Rejected on the square-world-footprint property; see "What is settled".
- **Quantised heights.** See the present-state facts.
- **Retiring the square path.** `temp`, `temp2` and `temp2_authored` keep working, and
  `temp2_authored`'s byte-exact bake parity stays the sharpest test in the programme.
- **Re-cutting `temp2_hex32_ground` as final art.** It is 2× upscaled square art for settling
  geometry. Hex-native art supersedes it, and Gate 1 is where its size is confirmed.
