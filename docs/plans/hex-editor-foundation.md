# Hex editor foundation recovery

2026-09-10. Correct the unfinished hex editor against the accepted workspace
sketch and the user's clarified foundation requirements. This is a new cycle,
not an amendment to the executing `hex-editor-workspace.md`. Its audit baseline
is `15ff9d3`; implementation has not started in this cycle. Preserve useful
painting, history, geometry, recovery and export code. Fix the visible palette,
separate the editor from the legacy preview, and establish ordinary file use.

## Read first and dispatch safely

Read `../README.md`, the current AGENTS.md instructions, `../POLICIES.md`,
`../ARCHITECTURE.md`, `../DEVELOPMENT.md`, then
[the audit](reviews/hex-editor-foundation-audit.md). Follow the current user
AGENTS contract where older files still say one active cycle, plan branch,
clean-tree gate or quiet-tree launch. No such gate applies here.

The preceding cycle has seven implementation commits and no acceptance commit
at the audit baseline. Another session has uncommitted edits in
`WorldMapTilesetPicker.gd` and `workspace/WorldMapWorkspaceChrome.gd`.
Before claiming those paths, obtain an explicit session/user ownership handoff
and inspect its new commits/diff. This is a path conflict, not a reason to hold
unrelated items. Do not overwrite its fixes or dispatch both acceptance items.
After handoff, this cycle carries the preceding cycle's remaining relevant
acceptance; keep its frozen plan intact until the final closure item.

Resume from this file and commit bodies, never by editing status into the plan:

```powershell
git log --grep="Plan-Item: HXW-" --format="%h %s"
git log --grep="Plan-Item: HXF-" --format="%h %s"
git diff -- src/presentation/worldmap/editor/WorldMapTilesetPicker.gd src/presentation/worldmap/editor/workspace/WorldMapWorkspaceChrome.gd
```

At each item, state actual-model versus assigned-tier match or mismatch and
continue; the tier is a cost signal, not an approval gate. Own only Touches.
Commit each item by explicit paths, with evidence and the final trailer
`Plan-Item: HXF-N`. Run its self-contained checks before that commit. Record
deferred checks as implemented; pending validation. Do not push unasked.

## Outcome and retained materials

Opening `WorldMapEditorScene.tscn` presents a neutral welcome with New, Open
and Open Recent. No document or region opens automatically. New creates a
usefully framed hex document. The author chooses art directly from a visible
sheet, paints, undoes, saves, reopens, and explicitly exports a battle map.
Clouds, moving lights, sky, fog, legacy region selection and shipping-preview
controls are absent from the editor. Their shared resources remain available
to the game and old debug scenes.

The visual authority is [the preserved interactive reference](references/hex-editor-foundation-workspace.html).
Use its map-first hierarchy and palette, with the fresh welcome/File workflow
in this plan taking precedence over its old preview controls. This HTML is a
design reference, not a UI framework to embed in Godot.

Future sessions have all required art locally:

- [Authoring guide](../HEX_TILESET_AUTHORING.md).
- `assets/worldmap/tilesets/temp2_hex32_starter.png`: 160x96, 5x3 frames,
  stable IDs `t000` through `t014`, catalog ID `temp2_hex32_starter`.
- `assets/worldmap/tilesets/templates/hex32_guides.svg`: editable geometry.
- `scripts/worldmap_editor/build_hex_starter.gd` and `probe_hex_starter.gd`:
  reproducible generator and narrow verification.
- `data/worldmap/tilesets.json`: catalog, not a new per-map copy.

Retain Land `#FFD363`, Sea `#37AEAE`, Grass `#BDD106`. The word temp2 in the
asset ID identifies colour provenance; it does not authorize loading its map.
The 32x32 stretched flat-top art is deliberate project geometry. Rectangular
atlas packing is separate from odd-column map placement. Stable tile metadata
and shared external tilesets follow [Tiled's tileset conventions](https://doc.mapeditor.org/en/stable/manual/editing-tilesets/);
[Tiled's format](https://doc.mapeditor.org/en/stable/reference/tmx-map-format/)
documents map staggering separately. Neither source mandates our stretched
shape or zero-gutter nearest-filtered template. Do not label this an industry
certification or a complete autotile set.

## Decisions fixed for this cycle

### Authoring file, identity and compatibility

Use UTF-8 JSON with extension `.noggmap.json`. It is an application-owned
authoring format, not TMX interoperability and not the runtime battle schema.
Keep existing layer encoding inside a new envelope:

```json
{
  "FORMAT": "nogg.hexmap",
  "VERSION": 1,
  "DOCUMENT_ID": "550e8400-e29b-41d4-a716-446655440000",
  "REVISION": 1,
  "CONTENT": {
    "FORMAT_VERSION": 1,
    "NAME": "Untitled",
    "LAYOUT": "hex_flat"
  }
}
```

CONTENT above is abbreviated: actual records contain the complete existing
`WorldMapTileData.toDictionary()` payload, including size, layers and metadata.
New code validates before passing it to the existing permissive reader. Do
not change that reader's behaviour for its other callers.

- Envelope VERSION and content FORMAT_VERSION are independent. Support 1/1
  only. Reject unknown versions, layer kinds and unknown structural fields
  rather than opening a lossy editable approximation. Opaque list-item
  dictionaries remain intact; do not prune their custom properties.
- DOCUMENT_ID is a lowercase UUIDv4 generated for authoring, independent of
  filename and CONTENT.NAME. It is not an entity uniqueID or gameplay RNG.
- New/legacy-imported documents have in-memory revision 0. First successful
  source save writes revision 1; changed successful saves increment by one.
  Unchanged Save is a no-op. Failed writes change neither revision nor dirty
  checkpoint. No timestamps in the canonical payload.
- Save As to another path creates an independent copy with a new UUID and
  revision 1; success switches the active document to that copy. Same-path
  Save As behaves as Save. Explicit overwrite confirmation remains required.
- Store the current absolute source path only in editor session/recent/recovery
  state. A moved/renamed file keeps its identity; its human title need not match
  its filename. This format references project catalog assets; it does not
  bundle art and is not a self-contained asset interchange package.
- Explicit Import Legacy accepts raw v1 hex CONTENT and creates an unsaved
  new document. Reject square sources with a clear explanation; never silently
  convert temp2 or overwrite a legacy file. Old debug readers remain unchanged.
- Preserve all supported grid/list/heights/detail/water layers and their
  authored values even when controls are collapsed or visibility is disabled.
  Missing catalog assets block editing affected art with an actionable message;
  never substitute a tile or erase references. Legacy fog/void metadata is
  retained as data and ignored by the clean editor presentation.
- Coordinates remain flat-top `odd_q_offset`, size is columns x rows, row-major
  storage, world cell width/height 2/2 and steps 1.5/2 with odd-column drop 1.
  No geometry migration in this cycle.
- Canonical text is `JSON.stringify(record, "\t", true)`, no trailing newline;
  fingerprint is `sha256:` plus SHA-256 of its UTF-8 bytes, including identity
  and revision. Parsing and reserializing valid files yields that canonical form.

Save succeeds when authoring JSON is safely persisted. PNG/scene/battle output
belongs to explicit Export. Existing checks expecting bake failure to keep a
successfully saved source dirty must change deliberately, not be restored.

### UX acceptance contract

- Default New: title Untitled, hex_flat, existing supported 19x14 preset,
  starter tileset, empty paint layers, visible grid and Fit Map on creation.
  Keep the existing supported size presets; do not invent free resizing here.
- File menu: New, Open, Open Recent, Save, Save As, Import Legacy, Close.
  New/Open/Save are also plainly labelled buttons. Ctrl+N/O/S and Ctrl+Shift+S
  work outside text controls; Undo/Redo and tool shortcuts respect focus.
- Open/Save As use file dialogs with real paths, including locations outside
  the authored folder. Recent list holds 10 canonical-path-deduplicated entries
  persisted in user settings. Missing entries are marked unavailable/removable.
  Startup never auto-opens the last document, including recoverable documents.
- Visible palette: three thumbnail quick choices Land/Sea/Grass for the starter,
  the complete 5x3 sheet at Fit, compact selected preview/name, clear selection
  outline and count. No tile-ID dropdown for art selection. IDs may be secondary
  metadata. Scatter seed is visible only in Scatter mode.
- One authoritative selection state. Clicking a frame controls the next stamp.
  Ctrl toggles, Shift selects rectangles, Escape clears. Empty means no art
  painting, with an explanatory hint. Preserve multi-selection across unrelated
  refreshes; layer/tileset changes restore valid per-layer state or visibly
  select a valid default. Never invisibly reuse a stale value.
- Tool buttons, brush settings, Visible/Lock and document state remain legible
  at 1280x720 and 1920x1080, including host scaling. At smaller supported sizes,
  scroll/collapse panels instead of overlapping or silently clipping controls.
  The central map gets most of the space; layer labels can expand or tooltip.
- Keep brush/stamp/scatter, hex parity, stroke interpolation, one-gesture undo,
  interruption handling, Save checkpoint, recovery and view-only visibility.
  Move advanced authoring controls into appropriate collapsible sections without
  deleting their data. Neutral editor presentation may use editor-owned unshaded
  materials or constant illumination; no animated environmental rig.

## Items

### HXF-1 — Make the picker visibly usable

**Model:** Sonnet 5 / GPT Terra.

**Model rationale:** The failure and end state are concrete: container geometry,
compact preview and spatial selection. Public selection APIs already exist;
this is bounded component work, not a new application boundary.

**Depends on:** No new-cycle items; explicit handoff of the picker path first.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapTilesetPicker.gd`
- `scripts/worldmap_editor/probe_tileset_picker.gd`
- `scripts/worldmap_editor/checks/picker/**` (new probes and their UID sidecars)

**End state:** Keep `configure`, `selectTileIDs`, `selectedTileIDs`,
`primaryTileID`, `tileAtSheetPoint` and both signal signatures. Set PREVIEW_PX
to 48. Anchor PickerColumn full-rect inside the plain Control; give the sheet
scroll viewport a positive minimum height of 112 logical pixels. Fit is the
default zoom and displays the full starter sheet without horizontal scrolling;
retain explicit 1x/2x/4x nearest zoom with scrolling. The selected preview must
not consume the sheet's guaranteed space.

**Implementation:** Mirror existing SheetCanvas event/hit mapping. Calculate
Fit from available viewport and source dimensions and recompute on resize;
source-cell mapping must be independent of zoom/scroll. Arrow keys choose the
nearest populated CELL in that direction on the same row/column, do not wrap,
and leave selection unchanged if none exists. Preserve existing Ctrl/Shift
selection, signal semantics and silent programmatic synchronization. Add
Escape clearing with empty change signals. Add a 248x400 host geometry probe
that enters the tree, waits for container layout, and asserts positive sheet
viewport bounds and all 15 frame centres visible at Fit. Cover shuffled CELL
metadata, transparent/unassigned slots, zoom/scroll hit mapping and keyboard
row movement. Keep catalog loading, quick-choice chips and paint state in the
integration item; do not edit the HUD/controller/catalog or regenerate art.

**Risk:** A selection arithmetic probe can pass while the sheet is inaccessible;
layout assertions and later actual clicks are both required.

**Validation:**
- Self-contained: run `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/worldmap_editor/checks/picker/probe_visible_picker.gd -Marker "HEX PICKER GEOMETRY PASS"`; add that exact script/marker. Also run `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/worldmap_editor/probe_tileset_picker.gd -Marker "WORLD MAP TILESET PICKER OK"`. Inspect `git diff --check -- src/presentation/worldmap/editor/WorldMapTilesetPicker.gd scripts/worldmap_editor`.
- Deferred: click all sheet rows and exercise Fit/zoom/scroll/resize and keyboard selection in the real editor, consolidated in HXF-7.

### HXF-2 — Implement the specified authoring envelope

**Model:** Sonnet 5 / GPT Terra.

**Model rationale:** The schema, identity policy and compatibility decisions
are fixed above; this item implements and verifies a separate codec against
literal records without changing runtime or UI ownership.

**Depends on:** None; can execute while picker ownership is being handed off.

**Touches:**
- `src/presentation/worldmap/editor/document/**` (new codec and UID sidecars)
- `scripts/worldmap_editor/checks/format/**` (new fixtures/probes/UID sidecars)
- `docs/HEX_MAP_FORMAT.md`

**End state:** Add `document/WorldMapFileDocument.gd`, extending RefCounted,
with constants FORMAT = "nogg.hexmap", VERSION = 1, EXTENSION = ".noggmap.json".
Expose these static functions:

```gdscript
createRecord(data: WorldMapTileData) -> Dictionary
decodeRecord(raw: Dictionary) -> Dictionary
importLegacy(raw: Dictionary) -> Dictionary
canonicalText(record: Dictionary) -> String
fingerprint(record: Dictionary) -> String
nextSaveRecord(record: Dictionary, asCopy: bool) -> Dictionary
```

`createRecord` returns a validated envelope at revision 0 with a fresh UUID,
or an empty Dictionary on invalid content; callers must not proceed on empty.
`decodeRecord`/`importLegacy` return `{ok: bool, record: Dictionary,
data: WorldMapTileData, error: String}`; failures have empty record, null data
and nonempty error. No partial successful result. `decodeRecord` accepts
revision 0 for recovery; the source-file opener requires revision >= 1.
`nextSaveRecord` returns a deep copy with revision+1, or new UUID/revision 1
when asCopy=true; it performs no writes or mutation of the input.

**Implementation:** Use the complete current serialization in
`WorldMapTileData.gd` as the content contract, including RLE counts, padded
height-lattice length, detail slots and list NEXT_ID. Validate types, finite
numbers, positive integer sizes, duplicate IDs, exact decoded lengths and
supported structural keys before the permissive parser can discard content.
Reject negative/zero RLE counts and overlong runs before expansion. Do not
reinterpret opaque list item data. Generate UUIDv4 with Crypto random bytes,
setting UUID version/variant bits; never use gameplay RNG. Codec dependency
validation must not load textures or mutate the catalog. Implement all fixed
format decisions above and document a complete valid example, migration,
identity, project asset dependency and runtime-export boundary. Do not edit
WorldMapTileData, battle_sim, factories, the catalog or scene scripts.

**Risk:** Silently dropping unfamiliar data or treating the two version fields
as equivalent would corrupt files. A filename-dependent UUID would break imports.

**Validation:**
- Self-contained: add and run `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/worldmap_editor/checks/format/probe_file_document.gd -Marker "HEX FILE DOCUMENT PASS"`. Cover all supported layer kinds round-trip, Unicode title, deterministic fingerprint, changed revision/identity, input immutability, legacy hex import, square/unknown version rejection, malformed and overlong RLE, unknown structural fields and retained opaque list data. Run `git diff --check -- src/presentation/worldmap/editor/document scripts/worldmap_editor/checks/format docs/HEX_MAP_FORMAT.md`.

### HXF-3 — Give the editor its own clean stage and coherent palette

**Model:** Opus 5 / GPT Sol.

**Model rationale:** Removing debug-controller lifecycle ownership crosses
scene, camera, preview and input boundaries. Preserving mature painting while
changing the shell requires extraction judgement and visual hierarchy decisions.

**Depends on:** HXF-1, HXF-2; explicit handoff of current chrome/controller lane.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapEditorController.gd`
- `src/presentation/worldmap/editor/WorldMapEditorHud.gd`
- `src/presentation/worldmap/editor/WorldMapEditorCamera.gd`
- `src/presentation/worldmap/editor/workspace/**`
- `src/presentation/worldmap/editor/foundation/**` (new editor-owned stage/helpers)
- `scenes/debug/WorldMapEditorScene.tscn`
- `scripts/worldmap_editor/checks/workspace/**`
- `scripts/worldmap_editor/checks/painting/**`
- `scripts/worldmap_editor/checks/foundation/**`

**End state:** Fresh welcome and neutral canvas satisfy the UX contract.
The editor no longer runs the debug controller's environment setup/process
path or instantiates its clouds, sky and region-preview UI. New uses the
specified preset and framing. Full atlas, quick choices and brush preview
agree with a single authoritative selection, including empty state.

**Implementation:** Decide the smallest maintainable ownership split that
removes inherited shipping/debug lifecycle without rebuilding painting.
Inspect every inherited method/property the controller uses before extraction.
Keep donor `WorldMapDebugController`, WorldMap.tscn, shared ground materials,
factories and effects unchanged. Use new editor-owned stage helpers as needed.
Integrate the catalog's existing raw-sheet loader when an imported Texture2D
is unavailable; a missing dependency must show an error, not an ID dropdown.
Use catalog ID/CELL/metadata, never thumbnails inferred from packed ordering.
For the starter the quick choices are t000/t001/t002; other sheets use their
own metadata and never get falsely labelled with these starter IDs.

The judgement is where selection and stage state live and how to simplify the
shell while retaining focus routing, visible footprint parity, height/detail/
water/object data and painting interruption guarantees. The canvas can be
empty before a document exists. Do not expose unusable legacy preview widgets
as a compromise. Explain extraction decisions and any retired debug-only
behaviour in the commit body. This item prepares the clean workspace; the next
item completes file commands, so do not claim full File acceptance here.

**Risk:** Hidden inherited dependencies can break picking or brush interruption;
cosmetic hiding alone leaves the unwanted simulation running. Do not alter
shared rendering to compensate for an editor-only camera problem.

**Validation:**
- Self-contained: narrow load probe of the owned scene; verify the new scene/stage graph excludes environmental nodes and debug lifecycle calls; run affected existing workspace/painting probes with their markers. Add checks for palette empty/multiple state through refresh and raw-image fallback. Record commands/results and focused diff in the commit body.
- Deferred: real welcome/New framing, readable layout, all-frame selection-to-next-stamp, footprint parity, advanced-section availability and clean stage behaviour, consolidated in HXF-7.

### HXF-4 — Complete ordinary files, source-only Save and recovery

**Model:** Opus 5 / GPT Sol.

**Model rationale:** File identity, asynchronous dialogs, history checkpoints,
external writes and recovery form a state machine with destructive-transition
risks. Existing atomic I/O must be adapted without losing its guarantees.

**Depends on:** HXF-3.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapEditorController.gd`
- `src/presentation/worldmap/editor/WorldMapEditorHud.gd`
- `src/presentation/worldmap/editor/workspace/**`
- `src/presentation/worldmap/editor/foundation/**`
- `scripts/worldmap_editor/checks/documents/**`
- `scripts/worldmap_editor/checks/foundation/**`

**End state:** Every File command and shortcut in the fixed UX contract works
with the envelope codec. Save writes only source. Recent paths survive restart
without automatic opening. Save/discard/cancel protects New/Open/Recent/Close/
window close, and canceled or failed actions leave the current document intact.

**Implementation:** Decide how to adapt the existing SavePoint, DocumentIO,
Paths and Recovery helpers while separating human name, selected path, UUID,
revision and current history identity. Preserve sibling-temp/backup replacement
and injected-I/O failure coverage. Recognize external file changes before
overwriting. A recovered document is visibly unsaved and explicitly accepted;
it cannot overwrite a changed original without conflict handling. Offer recovery
from the welcome state, never automatically load it. Keep recovery available
for never-saved documents and retain the 30-second idle policy.

Design modal transitions so dialog input never paints and canceled Save As
never switches identity/path/checkpoint. Save As copy semantics are fixed,
but the session decides the internal state machine and error recovery strategy.
Keep source files outside res:// supported; asset references remain project
catalog references. Explain changed assumptions, especially obsolete bake-gated
Save assertions, in the commit body. Do not modify the format contract or donor
exporters; report an actual contract gap before expanding owned paths.

**Risk:** Marking a partial/failed write clean, changing identity before a
successful Save As, or restoring stale recovery over newer disk content.

**Validation:**
- Self-contained: adapt and run injected document-safety probes, covering first save/change/no-op, Save As copy/same-path/failure, canceled transitions, external conflict, incomplete atomic replacement, missing recent entries, recovery fingerprint and source success with bake unavailable. Record exact commands and markers.
- Deferred: real OS file dialogs, overwrite/cancel/close, restart recent list and explicit recovery with both unsaved and externally modified files, consolidated in HXF-7.

### HXF-5 — Export a saved authoring snapshot across the battle boundary

**Model:** Opus 5 / GPT Sol.

**Model rationale:** Source identity and publication consistency cross visual
scene and headless battle definitions. Existing exporters couple names/paths
and revision 1; an adapter must reconcile this without changing gameplay rules.

**Depends on:** HXF-4.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapEditorController.gd`
- `src/presentation/worldmap/editor/workspace/**`
- `src/presentation/worldmap/editor/foundation/**`
- `src/presentation/worldmap/editor/document_export/**` (new adapter/helpers)
- `scripts/worldmap_editor/checks/export/**` (new probes/fixtures)

**End state:** Explicit Export Battle Map produces matching baked art, runtime
visual scene and existing v1 battle-map definition from one saved snapshot.
Source Save stays independent. Runtime BattleMapFactory loads the definition;
source JSON itself is never mistaken for a battle scenario.

**Implementation:** Use existing `WorldMapSceneExport.buildRuntime` and
`WorldMapBattleExport.buildDefinition` as read-only boundaries where possible.
The adapter owns returned dictionaries/nodes and replaces their legacy source
identity metadata before persistence. Do not modify shared exporters, runtime
factory, BattleSimulator/BattleState or scenarios. Match SOURCE.ID to UUID,
SOURCE.REVISION and definition REVISION to saved revision, SOURCE.FINGERPRINT
to the canonical envelope hash. Use `hex_` + UUID without hyphens as the stable
generated stem in the existing generated-output directories. Keep title as a
label and remove legacy absolute/source-name path assumptions from new outputs.

Export requires a saved current snapshot: offer Save first, abort export if it
fails or is canceled. Include complete authored layers irrespective of view
visibility. Preserve explicit tactical flags and existing integer elevations
0..8 at 0.5 steps, flat single-surface restrictions and their refusal messages.
Art colours never imply walkability. The session decides staging/publish order
and failure reporting so a partial artifact set cannot be presented as a
successful current export. Establish a success receipt only after all artifacts
agree; retain the previous valid set or identify incomplete output precisely.
Do not create deployment rules, armies or a battle-launch UI. Record boundary
judgement and identity compatibility evidence in the commit body.

**Risk:** Visually correct exports can still refer to mismatched revisions,
hidden view copies or stale PNGs; runtime validation must use the emitted data.

**Validation:**
- Self-contained: add/run bounded adapter probes through the existing waited runner; export synthetic owned temporary fixtures, reload artifacts, pass emitted definition to BattleMapFactory, verify source identity/hash/path consistency and full-layer parity, and test invalid tactical surface plus partial I/O failure. Never overwrite authored user maps for a probe.
- Deferred: actual editor export of a saved/reopened painted map, load its emitted visual scene and confirm battle cells align with visuals; verify clear invalid-surface/failure feedback, consolidated in HXF-7.

### HXF-6 — Publish the foundation workflow and reusable materials

**Model:** Sonnet 5 / GPT Terra.

**Model rationale:** The preceding commits settle behaviour. This is a bounded
documentation update with exact destinations and an explicit completeness list.

**Depends on:** HXF-5.

**Touches:**
- `docs/WORLDMAP_EDITOR.md`
- `docs/HEX_TILESET_AUTHORING.md`
- `docs/README.md`

**End state:** The docs index links both editor workflow, tileset authoring and
`HEX_MAP_FORMAT.md`. The editor guide describes fresh startup, New defaults,
visual selection/modifiers, mode-only controls, file paths/recent list, Save As
identity, source-only Save, conflicts/recovery and explicit battle export.
It distinguishes implemented features from acceptance still pending and future
authoring scope. All assets/generator/catalog/guide paths above are discoverable
without task-scoped files or this conversation.

**Implementation:** Update those sections in place using the implementation
commits as evidence. Preserve exact palette, geometry, manual-edge limitation
and rebuilding command in the existing authoring guide. Link the new format
reference instead of duplicating schema. Explain project asset dependencies
and unsupported TMX interchange. Do not regenerate art, rewrite global policies,
change the format document or cite transient plan-item IDs in durable docs.

**Risk:** Describing a native file dialog or battle flow that the implementation
does not actually supply would repeat the earlier acceptance gap.

**Validation:**
- Self-contained: run `git diff --check -- docs/WORLDMAP_EDITOR.md docs/HEX_TILESET_AUTHORING.md docs/README.md`; run `rg -n "noggmap|Open Recent|Save As|HEX_MAP_FORMAT|temp2_hex32_starter|probe_hex_starter" docs/WORLDMAP_EDITOR.md docs/HEX_TILESET_AUTHORING.md docs/README.md`; resolve each added local link with `Test-Path` and compare stated commands and defaults against the committed symbols. Record results in the item commit.

### HXF-7 — Independently accept the foundation and close both handoffs

**Model:** Opus 5 / GPT Sol.

**Model rationale:** Acceptance includes visual hierarchy and usability judgement
against the sketch plus stateful flows spanning several subsystems. Use a fresh
session, separate from the implementing lane, for independent assessment.

**Depends on:** HXF-1 through HXF-6; old acceptance ownership transferred.

**Touches:**
- Union of HXF-1 through HXF-6 Touches, for observed integration defects only.
- `docs/plans/hex-editor-foundation.md` (delete on successful closure only)
- `docs/plans/hex-editor-workspace.md` (delete superseded cycle after handoff/acceptance only)
- `docs/plans/references/hex-editor-foundation-workspace.html` (promote then delete)
- `docs/plans/references/hex-editor-workspace.html` (retire duplicate after handoff)
- `docs/plans/reviews/hex-editor-foundation-audit.md` (retire dated audit on closure)
- `docs/sketches/2026-09-10-hex-editor-foundation.html` (new durable accepted reference)
- `docs/sketches/README.md`
- `assets/worldmap/regions/generated/hex_*.png*` (this item's disposable export fixtures only)
- `scenes/worldmap/generated/hex_*.tscn*` (matching disposable fixtures only)
- `data/battle/maps/hex_*.json` (matching disposable fixtures only)

**End state:** All deferred checks pass on a recorded revision and actual
observed client sizes/scaling. No acceptance inferred from minimum-size math
or from a successful parse. Fix defects within this owned set and rerun relevant
flows; an outside-path defect requires ownership coordination, not a silent edit.

**Implementation:** Read the reference and audit before seeing the result.
Exercise the following consolidated flow and record pass/fail evidence in the
commit body, including screenshots' location and the model's usability judgement:

1. Launch fresh at 1280x720 and 1920x1080; record actual client bounds/scaling.
   No temp2 canvas or environmental animation; recent/recovery affordances do
   not auto-load. New defaults to fitted 19x14 empty hex map with visible grid.
2. Verify all 15 frames visible at Fit and click across every row. Paint an edge
   variant, not just the base land tile. Quick choices, primary preview, outline
   and next map stamp agree. Exercise Ctrl/Shift/Escape, arrows, scroll/zoom,
   resize, layer/tileset refresh and empty selection. No stale tile paints.
3. Exercise radius brush, odd/even-column stamp parity, seeded scatter,
   fast-drag interpolation, off-canvas/toolbar/focus interruption and one-gesture
   undo/redo. Hover footprint matches changed cells. Hidden/locked layers
   cannot receive paint; hiding never deletes data or changes export contents.
4. Exercise New/Open/Recent/Close and window close with Save/Discard/Cancel;
   Save As inside/outside project, unchanged Save, overwrite, failed write and
   externally changed source. Reopen without name/path coupling or data loss.
   Verify source can save when bake/export is unavailable.
5. Restart to check MRU and explicit recovery. Use disposable owned fixtures
   for crash simulation, never kill unrelated engine processes. Recovery with
   a newer original must not overwrite silently; cancellation preserves work.
6. Export the reopened snapshot with explicit tactical data, inspect visuals
   against loaded BattleMapFactory cells, identity/revision/hash, hidden-layer
   parity and failure messages. Do not invent an actual battle scenario merely
   to turn this into a battle-launch feature. Run a narrow unchanged legacy
   square-source/export probe if touched presentation dependencies could affect
   it; square editing in the new foundation UI is deliberately not acceptance.

Record baseline revision and relevant unrelated in-flight changes at observation;
concurrent work does not prohibit launching. Attribute failures precisely.
Use unique fixture UUIDs, record their exact output paths before export, and
remove only those fixture files afterwards; never sweep these generated globs.
Save temporary source maps outside the authored catalog and do not commit test
exports as game content. The claimed output globs allow observing the actual
default export destination without altering existing battle assets.
Run affected probes only after a defect fix; don't repeat every unrelated check.
Old pending validation is covered by the relevant flows above; environmental
preview retention and square editing in the new shell were superseded. Do not
forge a historical acceptance trailer for the old cycle.

On success, promote the reference with its final document-flow annotations,
replace durable guide links, remove pending-acceptance wording, and delete this
cycle plus the handed-off superseded plan/reference and dated audit in the same
commit. Include a durable non-item-ID summary of exclusions in the editor guide.
Do not edit a frozen plan in place as a progress log. No branch operation is
required. If acceptance fails, retain the plans and report the concrete failure.

**Risk:** A successful synthetic export or a good-looking screenshot alone
cannot establish both usability and document safety.

**Validation:**
- Self-contained: check changed links, focused diffs and affected narrow probes after fixes; verify preserved starter PNG SHA-256 against the audit and no shared donor edits. Record commands/results.
- Deferred: the six integrated observations above are the consolidated acceptance; record their evidence in this item's commit rather than another status file.

## Excluded from foundation, still pending

Full hex autotiling/transitions, map selection/clipboard, reusable multi-layer
stamp library, free map resizing/infinite maps, new advanced sculpting/water/
bridge/object tools, independent tactical visualization, importing TMX, bundled
asset interchange and direct battle-scenario deployment UI are subsequent
increments. Preserve already-supported authored data and existing advanced
operations; do not claim those larger features are finished. Clouds, animated
lighting and world atmosphere return only after foundation acceptance as an
explicit later editor-preview feature. Do not delete their game assets now.

## Waves

| Wave | Items / suggested session | Why disjoint / validation form |
|---|---|---|
| 1 | HXF-1 and HXF-2, separate Sonnet 5 / GPT Terra sessions | Picker component versus new codec/format docs; HXF-2 need not wait for picker handoff. |
| 2 | HXF-3 -> HXF-4 -> HXF-5, one Opus 5 / GPT Sol lane, one commit each | Sequential ownership of controller/workspace; stage, document transitions and export boundary need architectural judgement. |
| 3 | HXF-6, Sonnet 5 / GPT Terra | Documentation of settled implementation; no implementation item remains active in its owned paths. |
| 4 | HXF-7, fresh Opus 5 / GPT Sol | **Validation: standalone.** Visual judgement and integrated checks span component and architectural work from different waves. |
