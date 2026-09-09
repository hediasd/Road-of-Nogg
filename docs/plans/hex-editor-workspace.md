# Hex editor workspace

2026-09-09. This cycle turns `WorldMapEditorScene` into a usable first hex-map
authoring workspace: visible editing buttons, an integrated tilesheet picker,
a clean temp2-colour starter sheet, reliable brush feedback, and trustworthy
document saving/recovery. The user accepted the interactive workspace proposal
and requested instructions tailored to Opus 5 / GPT Sol and Sonnet 5 / GPT
Terra. This file is the execution specification for that first milestone; the
larger Tiled-like programme remains staged rather than silently bundled here.

## Opening and execution status

**Authored, not executing.** This planning turn does not open a cycle, switch
branches, launch Godot, or claim implementation completion. Planning files may
be committed to the current branch under the regular-work rule.

The opener must first establish that no other cycle is executing and obtain
the user's confirmation that the shared tree is quiet. Then create
`plan/hex-editor-workspace` from the agreed current state and run the branch
hygiene audit in `AGENTS.md`. Do not switch branches to work around another
session. The older `worldmap-editor.md` and `worldmap-hex-authoring.md` files
are historical context, not additional dispatch queues for these same paths.
If one of those cycles is actually still executing, this one waits.

Freeze this file when execution starts. Findings and changed assumptions go
in one commit per item, ending with `Plan-Item: HXW-<number>`; never edit this
file to record progress. Resume with:

```powershell
git log --grep="Plan-Item: HXW-" --format="%h %s"
git log --grep="Plan-Item: HXW-4" -1
```

Before each item, compare its Model field with the actual running model and
state the result. A mismatch is a cost signal, not a stop condition. The user
dispatches the sessions in the wave table; this plan does not ask a session to
spawn agents. Read only the context needed for the assigned item.

## Outcome and acceptance

A user can open the editor, create a named hex map, choose a tileset, select
actual tiles visually, paint/erase/fill with visible footprints, undo/redo,
hide/lock layers, save/reopen, recover unsaved work, and export through the
existing scene and tactical exporters without hand-editing JSON. Existing
height, object, triangle-detail and tactical tools remain reachable. The
editor's UI no longer makes the shipping rig's debug controls the main menu.

The accepted layout reference is
[`references/hex-editor-workspace.html`](references/hex-editor-workspace.html).
It is self-contained and opens from disk. It settles button-first interaction,
the integrated sheet, visible tool selection and workspace hierarchy. It is
not Godot code, a production map format, a new visual theme for the game, or
evidence of runtime acceptance. The browser prototype's **F = Fill** conflicts
with the existing editor's **F = Frame**; preserve Frame and use **G = Fill**.
All construction facts needed for the starter appear below; no item requires
the planning session's machine-local scratch files or an image generator.

## Present-state facts an executing agent must not "fix"

- `WorldMapEditorController.gd` extends `WorldMapDebugController.gd`. The
  editor swaps its own camera into the shipping rig. Its `World` SubViewport
  is displayed by a TextureRect, not a SubViewportContainer. Input therefore
  belongs to the outer controller; adding input code only to the inner camera
  cannot fix routing. Panel resizing also changes the display/picking extent.
- `LAYERS`' initial `enabled = false` fields do not prove there is no data.
  Runtime availability is resolved by `_layerEditable` and `_layerPopulated`.
  There are ground, overlay, heights, objects, detail and tactical rows. Water
  and bridge infrastructure exists but completing its controls is later work.
- `_onLayerVisibilityToggled` is currently a no-op. Stamp patterns and scatter
  sets have no useful user selection workflow. Do not preserve these defects
  for apparent compatibility or leave working-looking dead controls.
- `_isDocumentDirty()` compares undo depth with the saved depth. Branching
  history at the same depth, or reaching the history capacity, can make edited
  content appear saved. New documents can also appear saved before first write.
- The authored source is `WorldMapTileData`; saved source, preview textures,
  visibility masks, editor preferences and runtime exports have different
  ownership. A hidden layer must never disappear from source or export.
- `HexGrid` owns headless hex arithmetic; `WorldMapHexGrid` supplies the
  editor geometry. Reuse these conversions rather than repeating odd/even
  column arithmetic in brushes. Existing `stampHex` already translates axial
  patterns; do not replace it with offset addition.
- Flat-top frames are **32 x 32**, deliberately stretched for the shipping
  camera. World cells are 2 x 2 units, column step 1.5, row step 2, odd column
  drop 1. A regular flat-top hex has aspect 2:sqrt(3); changing to that overhead
  shape would change the renderer/grid contract and is outside this cycle.
- The source sheet uses rectangular frames, not staggered packing. Existing
  baking indexes `CELL * FRAME_PX`; margin and spacing remain zero. Adding
  gutters would require a separate shared-contract migration.
- The catalog's stable tile IDs use `t<number>`, independent of sheet position.
  `GRID_KIND = tile` does not imply a 16px frame: `FRAME_PX` is independent.
- The current temp2 hex sheet was extracted/upscaled from a painted map. Its
  75 tiles and existing IDs are compatibility data, not the new template.
- Tactical meaning remains explicit, never inferred from visible art or
  objects. Keep the single-surface/integer-elevation battle export refusals.
  Do not add terrain rules, balance, lore or travel semantics.
- Existing ground, sky, clouds, shaders, materials, factories, theme tokens,
  debug scene and runtime export builders are read-only dependencies here.
  Own editor-only overlays/copies as needed; do not retune shared rendering.

## Reading and verification contract

Start at `docs/README.md`, then `AGENTS.md`, `docs/POLICIES.md` and the relevant
sections of `docs/WORLDMAP_EDITOR.md`. For UI/input/preview work consult
`docs/LEARNINGS.md`'s Cursor event semantics, Render isolation and Elevation
presentation entries. For source/export boundaries read `docs/ARCHITECTURE.md`
under Shared hex lattice and Hex battle map and scenario boundary.

Every Touches entry is an exclusive write claim while the item runs. An exact
`.gd` entry also lists its `.uid` sidecar where creation/import may write it.
`workspace/**` and `checks/**` below are deliberately bounded new namespaces,
not permission to edit siblings. Source references elsewhere are read-only.
Stage/commit explicit paths only. Run focused `git diff HEAD -- <owned paths>`
and `git diff --check -- <owned paths>` at each item boundary.

Self-contained probes are narrow checks, not a new general test suite. Keep
them under the tracked `scripts/worldmap_editor/` directory; `/debug/` is
gitignored and cannot be the only durable verification source. Each new probe
must assert its own invariants, print its exact marker only after passing,
and exit nonzero on failure. Use explicit script preloads so freshly created
classes do not depend on an editor-wide import during concurrent work.

Run the existing bounded Windows launcher from the repository root:

```powershell
powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/worldmap_editor/<probe>.gd -Marker "<EXACT MARKER>"
```

The item commands below supply literal probe paths and markers. This runner
accepts arbitrary script paths; do not add another runner or modify it. It
uses the bundled `Godot_v4.4-stable_win64.exe`, waits for the exact process and
checks the marker. Do not confuse a process exit code with visual acceptance.
Probe scripts must not open the full editor scene in concurrent waves.
If global discovery reports an error outside owned paths, report it without
repairing another session's files; distinguish that interruption from proof of
your own check. Full import, scene loading and manual acceptance run only in
the final quiet-tree validation session.

## Items

### HXW-1 — Give history an identity independent of stack depth

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** One existing data class receives a precisely defined
revision API without changing its mutation model; adversarial sequences below
fully specify the correctness requirement.

**Depends on:** None.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapEditHistory.gd`
- `scripts/worldmap_editor/probe_history_revision.gd`
- `scripts/worldmap_editor/probe_history_revision.gd.uid`

**End state:** `currentRevision() -> int` identifies the current history state.
Two different committed states never share a revision within one history
object's lifetime, even after undo-branching, eviction or `clear()`. Existing
stroke APIs and undo/redo touched-region return values remain compatible.

**Implementation:** Add `_currentRevision: int = 0` and
`_nextRevision: int = 1`. A successful nonempty `endStroke()` stores
`beforeRevision` and a freshly allocated `afterRevision` on the command;
advance the current revision to the latter. Undo restores `beforeRevision`;
redo restores `afterRevision`. A net-zero stroke allocates no revision.
`clear()` clears existing command state and allocates a fresh current revision
without resetting `_nextRevision`. Expose `currentRevision()` as a getter.
Leave `maxDepth`, `undoCount`, `redoCount`, delta coalescing and all tile,
height, detail and object mutations intact. Do not add saving, document paths,
autosave, UI code or multi-layer commands here. Controller integration belongs
to HXW-4/HXW-6.

**Risk:** Accidentally treating undo as a fresh edit or recycling an evicted
revision would make return-to-save or divergent-history detection incorrect.

**Validation:**
- Self-contained: Run `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/worldmap_editor/probe_history_revision.gd -Marker "WORLD MAP HISTORY REVISION OK"`. Probe a saved revision, undo back to it, redo away, undo then make a different edit at the old saved depth, more edits than `maxDepth = 2`, net-zero strokes, and clear/new-document history. Assert restored document values and the existing touched-region outputs, not only counter values. No Deferred check: this additive API is verified in its own commit; UI integration is a later item's responsibility.

### HXW-2 — Build and register the temp2-colour hex starter

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Geometry, palette, atlas order and metadata are settled.
This is reproducible asset/data construction against an existing catalog, not
an art-direction or renderer decision.

**Depends on:** None.

**Touches:**
- `assets/worldmap/tilesets/temp2_hex32_starter.png`
- `assets/worldmap/tilesets/temp2_hex32_starter.png.import`
- `assets/worldmap/tilesets/templates/hex32_guides.svg`
- `assets/worldmap/tilesets/templates/hex32_guides.svg.import`
- `data/worldmap/tilesets.json`
- `scripts/worldmap_editor/build_hex_starter.gd`
- `scripts/worldmap_editor/build_hex_starter.gd.uid`
- `scripts/worldmap_editor/probe_hex_starter.gd`
- `scripts/worldmap_editor/probe_hex_starter.gd.uid`
- `docs/HEX_TILESET_AUTHORING.md`

**End state:** Catalog entry `temp2_hex32_starter` points at a 160 x 96 RGBA PNG
with 15 frames, 5 columns, 3 rows, `FRAME_PX = 32`, `GRID_KIND = "tile"`,
`PALETTE_REGION = "temp2"`, and `NEXT_ID = 15`. Existing entries retain their
IDs, values and order. An editable SVG guide and exact generation recipe make
the new sheet reproducible independently of the browser proposal.

**Implementation:** Mirror `WorldMapTilesetCatalog.hashCell()` for identity
hashing and `loadSheetImage()` for raw sheet reading; do not fork these helpers.
Generate geometric pixel fills without resampling/cutting donor terrain.
Verify the colours occur in `assets/worldmap/regions/temp2.png`:
land `#FFD363`, sea `#37AEAE`, grass `#BDD106`. The source has 11569, 27200 and
3654 pixels respectively; if it has changed, fail with the measured difference
rather than quietly choosing new colours.

Use vertices `(32,16),(24,32),(8,32),(0,16),(8,0),(24,0)` in image coordinates.
For each integer raster coordinate `(x,y)`, set `py=y+0.5`,
`left=8-py*0.5` when `py<=16`, else `(py-16)*0.5`. Pixels whose centres satisfy
`left <= x+0.5 <= 32-left` are inside. Outside pixels are RGBA `(0,0,0,0)`;
inside alpha is 255. No antialiasing, outlines, extrusions or shadows.

Assign row-major `CELL = [i % 5, floor(i / 5)]`, `ID = "t%03d" % i`:

| Frames | Fill | Edge band | Order |
|---|---|---|---|
| 0, 1, 2 | Land, sea, grass | None | Three solid bases |
| 3–8 | Land | Sea | Edges 0–5 |
| 9–14 | Grass | Land | Edges 0–5 |

Edge `e` joins vertex `e` to `(e+1)%6`; its band covers inside pixels whose
centre is at perpendicular distance **less than 4px** from that edge's line.
Edge names in order: lower-right, bottom, lower-left, upper-left, top,
upper-right. This is sprite-edge ordering, not the gameplay neighbour enum.
Set human-readable `LABEL`, base material `TERRAIN` (`land`, `sea`, `grass`),
`VARIANT` (`base` or `<border>_edge_<e>`), `AUTOTILE = ""`,
`WALKABLE = ""`, `LIFTABLE = false`. Do not infer gameplay from these labels.
Compute `HASH` through the catalog helper for each exact frame. Upsert only
this new entry; rebuilding must leave all other entries semantically unchanged.

The guide is a 160 x 96 SVG with separately named `guides` group containing
frame rectangles, the same polygons and centre crosses; no guide pixels in the
PNG. Document hiding guides before export. Keep margin/spacing zero. Mirror
the sibling PNG's lossless/no-mipmap import policy, with fresh resource identity;
do not copy a donor UID or `.godot` cache path. Full import is HXW-8's job.

`build_hex_starter.gd` generates/upserts only its owned outputs and prints
`WORLD MAP HEX STARTER BUILT` on success. `probe_hex_starter.gd` is read-only
apart from temp diagnostics; it never rewrites the catalog to make a test pass.
The guide documents packing versus map staggering (24px column step, 32px row
step, odd columns down 16px), stable IDs, transparency/filtering, and all six
edges/vertices. Cite the sources under Technical references. State explicitly:
these are **manual edge examples, not a complete autotile/Wang set**; the
32px stretched geometry is project-specific, not an industry certification.

**Risk:** Wrong alpha causes seams; gutters break current indexing; replacing
old catalog data changes existing maps. Complete transition automation needs
additional junction/corner artwork and is not hidden inside this item.

**Validation:**
- Self-contained: Run `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/worldmap_editor/build_hex_starter.gd -Marker "WORLD MAP HEX STARTER BUILT"`, then `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/worldmap_editor/probe_hex_starter.gd -Marker "WORLD MAP HEX STARTER OK"`. Assert dimensions, IDs/cells/hashes, exact palette/alpha/masks, unchanged donor catalog records, reproducibility, and exactly one covering hex per interior pixel in a repeated 6-column/5-row composition spanning both parities. Compare old catalog records to the pre-edit HEAD, excluding only the new entry.
- Deferred: Inspect the selected frames and repeated terrain at editing and shipping scale, including edges/vertices, and confirm existing maps keep their original appearance.

### HXW-3 — Implement the integrated tilesheet picker component

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A bounded UI component has an explicit interface and
selection rules; it can be built independently of the controller redesign and
tested against synthetic sheets without resolving application ownership.

**Depends on:** None.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapTilesetPicker.gd`
- `src/presentation/worldmap/editor/WorldMapTilesetPicker.gd.uid`
- `scripts/worldmap_editor/probe_tileset_picker.gd`
- `scripts/worldmap_editor/probe_tileset_picker.gd.uid`

**End state:** A `Control` component displays a rectangular sheet with nearest
filtering, a visible selected-frame outline and enlarged primary tile preview.
It selects stable IDs from actual `CELL` metadata, supports multi-selection,
and exposes no document/camera/catalog mutation.

**Implementation:** Create `WorldMapTilesetPicker` with this public API:

```gdscript
signal primaryTileChanged(tilesetID: String, tileID: String)
signal selectionChanged(tilesetID: String, tileIDs: Array[String])
func configure(tilesetID: String, sheet: Texture2D, framePx: int, tiles: Array[Dictionary]) -> void
func selectTileIDs(tileIDs: Array[String]) -> void
func selectedTileIDs() -> Array[String]
func primaryTileID() -> String
func tileAtSheetPoint(point: Vector2) -> String
```

`tiles` carries the catalog-normalized `ID`, `CELL: Vector2i`, `LABEL`,
`TERRAIN`, `VARIANT` fields. Frame positions, never array positions, locate art.
`tileAtSheetPoint` receives unzoomed image pixels; padding, invalid/negative
coordinates and missing frames return `""`. Blank sheet slots are not tiles.
Emit no user-change signals during `configure` or `selectTileIDs`; those are
controller-driven synchronization. Return a duplicate of selection arrays.

Plain left click replaces the selection and primary. Ctrl-click toggles a
frame; the clicked selected frame becomes primary, or the first remaining
row-major frame when removed. Shift-click selects the inclusive rectangular
sheet region from the last plain-click anchor, skipping missing entries.
Multi-selections are returned in `(CELL.y,CELL.x,ID)` order. If empty, primary
is `""`; otherwise it must belong to the selection. Reconfigure clears stale
IDs, retaining only valid selections when the tileset ID is unchanged.
Each user gesture emits at most one of each change signal, only when changed.

Use visible `−`/`+` buttons for **1x, 2x, 4x** palette zoom (default 2x), a
ScrollContainer for overflow, and show primary label/ID plus frame coordinates.
Stop palette pointer/wheel events from reaching the map; scrolling the sheet
must not dolly the camera. Expose tiles and controls with names/tooltips; keep
the content usable with keyboard focus. Build local styling only, using the
accepted proposal as hierarchy reference. Do not create an atlas importer,
tileset editor, resource cache or global theme. HXW-4 owns window integration.

**Risk:** Atlas coordinates can be confused with selected-array indices or map
coordinates. Zoomed hit tests and focus propagation are common failure points.

**Validation:**
- Self-contained: Run `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/worldmap_editor/probe_tileset_picker.gd -Marker "WORLD MAP TILESET PICKER OK"`. Instantiate only this component with an in-memory synthetic texture and shuffled sparse metadata. Assert hit mapping/bounds at each zoom, plain/Ctrl/Shift selection, signal counts, primary consistency, empty slots, defensive array copies and reconfiguration. Do not load the full editor.
- Deferred: Verify visible outlines/preview, sheet zoom/scroll, focus and selection gestures in the integrated workspace at 1280x720 and 1920x1080.

### HXW-4 — Rebuild the workspace and its input ownership

**Model:** Opus 5 / GPT Sol

**Model rationale:** Replacing the menu-heavy shell crosses Godot layout,
focus, viewport/picking transforms and inherited debug-controller ownership.
The accepted interaction direction leaves component boundaries and migration
strategy to the executing session's judgment.

**Depends on:** HXW-1, HXW-2, HXW-3.

**Touches:**
- `scenes/debug/WorldMapEditorScene.tscn`
- `src/presentation/worldmap/editor/WorldMapEditorController.gd`
- `src/presentation/worldmap/editor/WorldMapEditorHud.gd`
- `src/presentation/worldmap/editor/WorldMapEditorCamera.gd`
- `src/presentation/worldmap/editor/WorldMapTilesetPicker.gd`
- `src/presentation/worldmap/editor/workspace/**` (new editor-only components/resources and sidecars)
- `scripts/worldmap_editor/checks/workspace/**` (new narrow probes and sidecars)

**End state:** The accepted button-first workspace operates on real documents
and the integrated picker. New/Open/Save/Save As, Undo/Redo, scene export and
battle export have visible named buttons. Frequent tools are buttons with
selected states and contextual options. The central map remains usable at
1280x720 and 1920x1080. Debug preview settings are collapsed by default.

**Implementation brief:** The current inheritance preserves the shipping rig,
but also couples UI building, document management and gestures inside one long
controller. Decide the smallest editor-only extraction that makes the new
workspace maintainable without rewriting the donor. You own the bounded
`workspace/` namespace for that decision; record the chosen boundaries and
why they preserve the shipping/debug scene in the commit body.

Keep the toolbar/palette/map/layers hierarchy from the proposal. Layout should
measure actual panel and toolbar bounds, support practical resizing/collapse,
and leave the map unoccluded; do not hardcode yesterday's viewport rectangle.
Build an explicit editing view and a shipping-preview action using the existing
camera contract. Keep Navigate, Inspect, existing layer-specific tools and all
existing exports reachable; retain the off-contract indicator where needed.
Height/object/tactical values need appropriate controls, not texture thumbnails
pretending they are art. Fix direct HUD `OptionButton` assumptions in owned
controller code rather than keeping invisible dummy menus to satisfy them.

New-map creation offers a tileset choice, defaulting to `temp2_hex32_starter`;
open maps retain their stored tileset IDs. Palette content follows the active
layer's actual catalog entry. Never silently change a populated layer's tileset
or remap IDs. General tileset replacement is later work. Keep the HXW-3 public
API stable; any required corrections must preserve its contract/probe.

Resolve input as an ownership problem. Buttons, text fields, dialogs and the
sheet consume their events; clicking/dragging them never paints/pans behind
them. UI focus supports keyboard use. Camera movement belongs to map gestures;
the nested camera is not expected to receive outer viewport events. Keep
F = Frame, Space = shipping camera, and existing Ctrl+S/Ctrl+E combinations
outside editable text/modal focus. Add B = Paint, E = Erase, G = Fill,
I = Eyedropper where applicable. Preserve existing camera mouse gestures.
Keyboard Tab should traverse controls; provide the orthographic/perspective
toggle visibly rather than retaining Tab as a global focus-stealing shortcut.
An explicit Erase button may map to the existing erase value internally.

Integrate HXW-1 revision identity immediately, replacing all saved-depth
comparisons. Track never-saved documents separately; preserve dirty/discard
protection while HXW-6 completes failure/recovery behaviour. Do not leave New
documents labelled saved. Finish/resolve a stroke before tool/layer/document
changes or export; mid-gesture ownership must not switch to another layer.
HXW-5 owns full brush preview/interpolation/visibility semantics, not a redesign
of this shell. Do not claim those later end states in this commit.

**Risk:** A polished toolbar can mask broken picking, duplicated shortcuts,
lost strokes or changed debug presentation. Integration must exercise real
controller state, not only the existence of new Control nodes.

**Validation:**
- Self-contained: Add/run a bounded probe in `checks/workspace/` through the documented runner, with marker `WORLD MAP WORKSPACE CONTRACT OK`, covering editor-only action availability, focus gating decisions, layout-to-display transforms and history checkpoint wiring without opening the full game. Record the exact command and chosen probe path in the commit body. Audit that donor/debug scripts, shared resources and exports are untouched; confirm HXW-3's probe still passes if its component changed.
- Deferred: Exercise the actual scene's buttons, shortcuts, text entry, dialogs, palette scrolling and map picking in both target window sizes and view modes, including preservation of every previously functional editor tool.

### HXW-5 — Make painting predictable and layer controls truthful

**Model:** Opus 5 / GPT Sol

**Model rationale:** Brush previews must agree with commits across hex geometry,
terrain picking, history and editor-only rendering. Layer visibility requires
judgment because several authored layers are composited into one ground view.

**Depends on:** HXW-4.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapEditorController.gd`
- `src/presentation/worldmap/editor/WorldMapEditorHud.gd`
- `src/presentation/worldmap/editor/WorldMapBrushes.gd`
- `src/presentation/worldmap/editor/workspace/**`
- `scripts/worldmap_editor/checks/painting/**` (new narrow probes and sidecars)

**End state:** Paint/erase strokes have hex-disc radius controls and exact
footprint previews; line/rectangle/stamp show the cells they will change.
Fast drags do not leave skipped cells. Multi-selected sheet tiles feed usable
stamp/scatter tools. Layer visibility/lock affect the editor view honestly,
and source/saves/exports retain every authored layer regardless of view state.

**Implementation brief:** Reuse existing brush math and shared hex arithmetic.
Choose an editor-only preview representation that remains correct over heights
and camera changes without editing shared shaders/materials. Preview and apply
must consume the same computed target-cell set, clipped to the document, rather
than independently approximating each other's shape. No baked preview pixels
may enter the document or exported texture.

Radius counts hex rings: zero edits one cell; display that as “1 hex”. Make
radius available for ground/tactical paint and erase; do not apply it silently
to triangle/object/height tools with different semantics. Interpolate between
pointer samples with the existing hex line path. One continuous gesture is one
history entry regardless of distance, repeated cells or brush radius. Define
and document the stroke policy for pointer capture/release outside the canvas,
focus loss, Escape and tool/layer changes; no stuck-open or half-recorded stroke.

Keep rectangle as a clearly named offset-cell rectangle with a truthful
preview, not a promise of a hex disc. Define sheet multi-selection placement
in a local virtual odd-q lattice, convert positions to axial offsets, and call
the existing hex stamp path. The same stamp must keep its shape when its map
anchor moves between odd/even columns; don't treat rectangular atlas spacing
as map spacing. Empty/unselected sheet slots are holes in a stamp. No stamp
library, map-region clipboard, rotation or multi-layer transaction is required.
Scatter uses the ordered selected ID set and visible seed; identical inputs
give identical committed IDs. Do not add weights or reroll saved maps on bake.

Implement visibility as editor view state: independently hide ground art,
overlay art, detail, objects and the tactical visualization. Height visibility
must be labelled as showing/hiding height guides, not flattening geometry or
lying about the export. A hidden or locked active layer refuses edits with a
clear indication. If a layer has no independent view, show an explanation
rather than a working-looking toggle. Preserve actual terrain for picking and
object anchoring when hiding its art.

Choose how to separate the composited editor image from the canonical baked
document. An editor-only filtered copy/preview builder is allowed; changes to
`WorldMapBaker`, `WorldMapSceneExport`, shared shaders or ground factories are
not. Canonical save/export must rebuild from the full authored source even
when the preview currently hides layers. Record the ownership decision and
its costs in the commit body. Avoid silent full-world rebuilding on every
mouse event where the existing dirty-cell path can be retained.

**Risk:** Visibility can leak into exports; preview/apply mismatch can corrupt
the author's intent; offset stamps can change shape at parity boundaries.

**Validation:**
- Self-contained: Add/run a bounded probe under `checks/painting/`, marker `WORLD MAP PAINTING CONTRACT OK`, asserting disc/line interpolation, clipping, preview/apply target equality, one undo per gesture, two-parity stamp translation, deterministic multi-ID scatter and source serialization unchanged by visibility/lock changes. Verify full canonical bakes remain identical for all visibility combinations using in-memory documents/raw sheet loads. Record its exact runner command in the commit body.
- Deferred: Paint quickly in both views, preview/apply line/rectangle/stamp across both parities, scatter multiple selected tiles, exercise gesture interruption and verify hide/lock behaviour plus full-content save/export while layers are hidden.

### HXW-6 — Complete safe document saving and recovery

**Model:** Opus 5 / GPT Sol

**Model rationale:** Source files, generated textures, document identity,
recovery and view state have different lifetimes. Failure handling must protect
the current document without redesigning shared export formats.

**Depends on:** HXW-5.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapEditorController.gd`
- `src/presentation/worldmap/editor/WorldMapEditorHud.gd`
- `src/presentation/worldmap/editor/workspace/**`
- `scripts/worldmap_editor/checks/documents/**` (new narrow probes and sidecars)

**End state:** New/Open/Save/Save As/close have coherent saved/unsaved states
and actionable failures. Recovery snapshots cannot overwrite authored maps.
Recovered content is offered explicitly and must be deliberately saved.
Scene and battle export buttons report the existing exporter result accurately.

**Implementation brief:** Extend the save-point integration from HXW-4, using
HXW-1 state identity rather than stack depth. A failed source write, failed
canonical bake write or failed Save As must not advance the save checkpoint
or silently change the active source path. Loading a malformed/missing map
must leave the current document/history recoverable. Resolve open strokes
before any snapshot or file action. Validate names/path containment; authored
output stays under the existing authored/generated roots, never an arbitrary
path supplied as a map name. This is tool behaviour, not a migration of the
runtime serialization API.

Offer Save / Discard / Cancel for document-replacing actions; cancellation
restores the picker/title/selection state. Window close must follow the same
protection as New/Open. Multi-file source/bake operations can fail partway:
record the actual outcome honestly, retain unsaved state and a retry route,
and never promise atomicity across multiple files without implementing it.

Recovery uses `user://worldmap_editor/recovery/`, separate from canonical
source and generated assets. Write an atomic replaceable snapshot after 30
seconds of dirty idle time with no active stroke, and on focus loss where
safe; no periodic writes for unchanged/saved documents. Store the document,
source identity/path, source fingerprint and timestamp sufficient to detect
a source modified since the snapshot. On reopen offer recovery explicitly;
never auto-load over newer source or silently save recovered content back.
Recover as an unsaved document with a fresh history/save identity. Keep
recoveries for other documents intact; deletion/discard operates only on the
selected recovery. Do not persist scratch paths into tracked data or exports.

Persist only editor preferences separately if needed by this workflow. No
cloud sync, file watcher, external editor integration or source-control UI.
Use injectable I/O boundaries in the editor-only implementation so failures
can be exercised without touching real maps. Record the chosen failure and
recovery semantics in the commit body for the documentation item.

**Risk:** Autosave can become data loss if it writes the source; failed Open
or Save As can discard the only live document; preview visibility can taint
saved textures if HXW-5's boundary is bypassed.

**Validation:**
- Self-contained: Add/run a bounded probe under `checks/documents/`, marker `WORLD MAP DOCUMENT SAFETY OK`, using a temp root/injected I/O. Exercise never-saved maps, same-depth history divergence, eviction, source/bake failure independently, malformed Open, failed Save As, traversal names, recoveries with unchanged/newer/missing source, and no writes while unchanged or in a stroke. Assert preserved document/path/checkpoint and recovery containment. Record exact runner command and outcomes in the commit body.
- Deferred: Perform the real New/Open/Save/Save As/close and recovery dialogs, cancel/discard paths, source/bake error feedback, and export buttons; recover an unsaved edit after terminating only the validation-owned game process.

### HXW-7 — Document the shipped authoring workflow

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Implementation and its decisions are already committed.
This item reconciles named sections and writes a literal workflow from that
evidence; it must not design new behaviour or alter code.

**Depends on:** HXW-6.

**Touches:**
- `docs/WORLDMAP_EDITOR.md`
- `docs/README.md`

**End state:** The documentation index links the editor and hex tileset
authoring guides. The editor guide describes the implemented workspace,
shortcuts, palette selection, brush semantics, visibility, saving/recovery and
export workflow with no requirement to read a transient cycle file.

**Implementation:** Read the HXW implementation commit bodies, then reconcile
the existing sections “Tilesets”, “The editor scene”, “Undo and redo”, “The hex
brushes”, “The document lifecycle” and “The tools that reach the other three
layers”. Remove obsolete Phase A/depth-based dirty-state/unreachable-tool
claims in the sections being changed. Preserve unrelated geometry and runtime
export documentation, but correct direct contradictions with verified source.
Link `HEX_TILESET_AUTHORING.md` for the palette/geometry recipe rather than
duplicating it. Add a short first-map walkthrough matching the Outcome:
New → choose starter → select sheet frame → paint/erase/fill → hide/lock →
undo/redo → Save As → reopen → preview → export. List B/E/G/I, F, Space,
Ctrl+S, Ctrl+E, Ctrl+Shift+E, Ctrl+Z and redo combinations exactly as shipped;
explain focus/modal behaviour and Tab navigation. Describe multi-frame sheet
selection and stamp placement, and label missing advanced capabilities as
outside this first milestone. Record save failure and recovery choices.

In `docs/README.md`, add rows for “World map editor” and “Hex tileset
authoring” pointing to their owning documents. No backlog updates, new plan
requirements outside `docs/plans/`, runtime edits or speculative features.
Do not state manual acceptance passed before HXW-8; describe behaviour from
source/self-contained evidence and leave acceptance to that commit.

**Risk:** Copying historical plan prose can reintroduce stale square-grid or
tool-state assumptions. The live implementation and commit evidence win.

**Validation:**
- Self-contained: Run `git diff --check -- docs/WORLDMAP_EDITOR.md docs/README.md`; run `rg -n 'HEX_TILESET_AUTHORING|WORLDMAP_EDITOR' docs/README.md docs/WORLDMAP_EDITOR.md`; verify each newly added local link resolves; run `rg -n 'HXW-|hex-editor-workspace' docs/WORLDMAP_EDITOR.md docs/README.md` and require no transient-cycle dependency. Compare the walkthrough/shortcuts to current action bindings. No Deferred check: the documentation edit is verified in its own commit.

### HXW-8 — Validate the workspace independently and close the cycle

**Model:** Opus 5 / GPT Sol

**Model rationale:** Acceptance includes usability and visual judgment across
the workspace, art, preview and document boundary. A fresh validation session
must assess the integrated result rather than the implementing session merely
confirming its own layout.

**Depends on:** HXW-1, HXW-2, HXW-3, HXW-4, HXW-5, HXW-6, HXW-7.

**Touches:**
- All exact paths and bounded new namespaces named in HXW-1 through HXW-7, solely for validation fixes and their documentation
- `docs/plans/hex-editor-workspace.md` (delete on successful closure only; never annotate during execution)
- `docs/plans/references/hex-editor-workspace.html` (promote then delete on successful closure)
- `docs/sketches/2026-09-09-hex-editor-workspace.html`
- `docs/sketches/README.md`
- `BACKLOG_CRITICAL.md`
- `BACKLOG_LONGTERM.md`
- `data/worldmap/authored/hxw_validation*.json` (temporary acceptance documents; remove only this session's files before committing)
- `assets/worldmap/regions/generated/hxw_validation*.png` and matching `.png.import` files (temporary acceptance bakes)
- `scenes/worldmap/generated/hxw_validation*.tscn` (temporary, already ignored exports)
- `data/battle/maps/hxw_validation*.json` (temporary tactical exports)

Use the reserved `hxw_validation` / `hxw_validation_save_as` document names
for acceptance. Check that those paths do not already belong to another
session before writing. Track the exact files this session creates and remove
only those by explicit path after the checks; never bulk-delete by the glob.
The temporary files are write-authorized for acceptance, not commit artifacts.
Recovery/process logs remain in the dedicated user/temp locations above.

**End state:** Every deferred check below passes in a user-confirmed quiet
tree. The independent commit records the evidence, fixes and actual limitations.
The cycle closes, merges and is cleaned up in this same session.

**Implementation brief:** Start only after all dependencies are committed and
the user confirms no session is editing. Read their commit evidence once;
reuse passing self-contained results unless changes/failures justify reruns.
Use `docs/DEVELOPMENT.md` for the full waited import and manual launch. The
existing project supports narrow probes despite older “no suite” prose; don't
invent a broad runner. Import new assets before loading the scene and stage
only import sidecars listed in the footprint. Any generated cache changes
outside the footprint are not yours to commit.

Execute one integrated flow, keeping screenshots/logs as scratch evidence:

1. Open `WorldMapEditorScene.tscn` at 1280x720 and 1920x1080. Verify the canvas
   is usable, text and buttons fit, selected states are obvious, and the author
   can discover common actions without opening debug settings. Compare the
   accepted proposal's interaction hierarchy, not browser pixel positions.
2. New a named starter map. Click all three fills and several edge frames;
   verify sheet coordinates, primary/multi-selection, zoom/scroll and previews.
   Paint/erase/fill; radius 0/1/2; fast drags; line/rectangle; stamps on both
   parities; seeded scatter. Undo and redo each whole gesture. Check grid and
   footprint on flat and sculpted terrain, in editing and shipping views.
3. Edit a name and numeric values, traverse controls with Tab, use shortcuts,
   operate dialogs and resize/collapse panels. Confirm no map paint or camera
   movement leaks through controls. Release a stroke outside the canvas and
   interrupt it with focus/tool/layer changes. No stuck gesture or lost edit.
4. Verify ground/overlay/detail/object/tactical view controls and height-guide
   semantics. Hidden/locked layers refuse edits. Save/export while hidden,
   restore visibility and reopen: the full authored content is still present.
5. Exercise never-saved state, successful Save/Save As, undo to save, divergent
   history at the same depth, eviction, cancelled Open/close, and failed writes
   using a validation-owned path. Close/relaunch and recover unsaved content;
   terminate only the exact process this session launched for the crash case.
6. Preserve compatibility: open `temp2_authored` (square),
   `temp2_hex32_authored` and `hex_battle_fixture`; select their original art,
   exercise previously functional height/object/detail/tactical tools and
   discard temporary changes. Compare donor map appearance and camera/framing
   with their baseline. Use clones under the reserved acceptance names for
   source/export exercises, or temp space where the API accepts a destination;
   do not add catalog entries or change shipped fixtures.
7. Run scene and tactical export on a suitable validation-owned map. Load the
   scene without editor chrome and load the tactical definition through the
   existing headless map factory. Unsupported elevation/stacked surfaces still
   refuse correctly. Compare source IDs/geometry/art and full hidden-layer
   content across outputs. Check `WorldMapDebugScene.tscn` separately for its
   original controls, rendering and camera behaviour; no donor regression.
8. Evaluate the starter at native and actual shipping scale. Check the three
   exact colours, all six joins/vertices and parity transitions. Manual edge
   examples must not be advertised as complete autotiling. Record noticeable
   paint/preview lag using the same map/view as a before/after comparison;
   do not invent a passing FPS score or broaden into renderer optimization.

Usability acceptance requires naming concrete problems found and either fixing
them within the owned footprint or declaring validation failed. A “pass” that
only says the buttons exist is insufficient. Re-run the relevant consolidated
checks after fixes. A needed shared dependency change is a separate scope
decision: do not make it under this validation item's broad ownership list.

On success, reconcile guide text for validation fixes. Promote the accepted
reference to the dated `docs/sketches/` file as a self-contained HTML document
with a one-paragraph explanation of the decision it settled; link it in that
index. It preserves the approved workflow judgment, not proof output. Delete
this cycle file and its temporary reference in the closure commit. Do not
delete unrelated historical plan files. If a durable out-of-scope defect was
found, append it once to the appropriate backlog, by explicit path and with
evidence; don't duplicate the intentionally excluded programme below. A defect
that fails this cycle's acceptance cannot be backlogged to justify a pass.

Commit validation evidence/fixes with `Plan-Item: HXW-8`; a separate closure
commit may carry plan deletion/promotion/backlog housekeeping. In the same
turn, while still quiet, merge `plan/hex-editor-workspace` to `main` with
`--no-ff`, push `main`, and safely sweep merged local branches under
`AGENTS.md`. Push each wave boundary as required. Offer remote branch deletion
unless the user explicitly authorized it; do not infer permission to delete
unrelated remote branches. Run/report the full branch/worktree audit, including
every unmerged branch and its commit count or an explicit none result. Never
leave a successfully validated cycle at “pending merge”.

**Risk:** A UI-only review misses export/data loss; an implementing session
rubber-stamps its own design; validation can accidentally commit other work.

**Validation:**
- Self-contained: Focused diff/path audit, relevant changed probes, final guide/link consistency, and branch/worktree audit at closure. Record exact commands/outcomes in the commit body.
- Deferred: The single quiet-tree integrated flow above is the union of HXW-2 through HXW-6's visual and runtime checks; it is the cycle's only acceptance launch session.

## Technical references

These explain conventions, not permission to change project contracts:

- [Tiled: Editing tilesets](https://docs.mapeditor.org/en/stable/manual/editing-tilesets/) — image-sheet frames, margin and spacing; filtered atlas padding must match the importer.
- [Tiled: TMX map format](https://docs.mapeditor.org/en/latest/reference/tmx-map-format/) — hex side length and staggering are map metadata separate from atlas packing.
- [Red Blob: Hex grid implementation](https://www.redblobgames.com/grids/hexagons/implementation.html) — axial/cube conversions, layouts and deliberate stretched geometry.
- [Tiled: Automapping](https://doc.mapeditor.org/en/latest/manual/automapping/) — its documented hex limitation is why this cycle does not promise Tiled-compatible automapping.

## Deliberately excluded from this cycle

The larger approved direction remains: map-region selection/clipboard and
multi-layer stamp libraries; object/footprint inspectors; smooth/set-height
sculpting; complete water/bridge controls; full terrain transition automation;
gameplay validation overlays. Those are separate increments after the basic
workspace proves usable. They are not cancelled, pre-approved shared-contract
migrations, or unfinished acceptance requirements of this first milestone.

Also excluded: arbitrary populated-layer tileset remapping, infinite maps,
custom world sizes beyond existing supported lattices, TMX import/export,
scripting/plugins, procedural worlds, gameplay/balance/lore changes, a shared
theme redesign, and donor renderer/camera/grid rewrites. No new art style beyond
the accepted flat-colour starter.

## Waves

| Wave | Items / suggested sessions | Why disjoint / validation form |
|---|---|---|
| 1 | HXW-1, HXW-2, HXW-3 — three Sonnet 5 / GPT Terra sessions | History + its probe; starter assets/catalog/guide + its probes; picker + its probe. No shared write path and no full scene launch. A single Terra session may run these sequentially if preferred. |
| 2 | HXW-4 → HXW-5 → HXW-6 — one Opus 5 / GPT Sol lane, one commit per item | Dependency-consecutive editor integration work with overlapping controller/HUD/workspace ownership. Keep it in one session to reuse context and avoid shared-file collisions. |
| 3 | HXW-7 — one Sonnet 5 / GPT Terra session | Documentation only, after behaviour and decisions are committed. |
| 4 | HXW-8 — one fresh Opus 5 / GPT Sol session | **Validation: standalone, alone, quiet tree.** Appearance/usability judgment and cross-component exports make folding inappropriate. The session also closes/merges the cycle. |
