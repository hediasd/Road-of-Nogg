# Hex tileset folder discovery

Opened 2026-09-13, revised the same day. This cycle makes the Hex Map Editor treat every PNG in
the world-map tileset folder as an available sheet, gives each sheet its own config file that is
created the first time the sheet is selected, and lets the author see and change the sheet's
frame size and each tile's walkability from inside the editor. It also makes the lines between the
editor's panels draggable. It does not redesign tilesheet art, move assets, change the map file
format, or support non-square frames.

## Outcome

- Every PNG directly under `assets/worldmap/tilesets/` is offered by filename stem when a new hex
  map is created.
- Each tileset's settings and tile ledger live in its own file,
  `data/worldmap/tilesets/<ID>.json`. The shared `data/worldmap/tilesets.json` is gone; its three
  entries were split into three files with their tiles unchanged.
- A sheet with no config file gets defaults (32 × 32 frames, every tile walkable). Its config file
  is written the first time the sheet is selected: chosen for a new map, or shown in the palette
  for an opened map. Once written, the file is the authority and is never overwritten by defaults.
- The palette shows a **Tileset properties** block: sheet size, frame size (editable), tile count,
  and a **Walkable** checkbox for the selected tile. Every change is written to that tileset's
  config file straight away.
- The picker marks tiles that are not walkable.
- The two vertical lines between the palette, the map and the inspector, and the line between the
  tilesheet and the map menu, can be dragged to resize those areas.

## Present-state facts an executing agent must not "fix"

- `temp2_ground.png` is a legacy 128 × 80 square sheet with a stored `FRAME_PX` of 16. After
  HTD-1 it is offered in the New dialog like every other PNG, and its stored 16 wins over the
  32 default. The properties block shows a warning for it. Do not move, alter, or hide it.
- `temp2_hex32_starter_v2.png` and its `.import` file are untracked user-owned files. No item may
  edit, stage, or commit them, and no item may create `data/worldmap/tilesets/temp2_hex32_starter_v2.json`.
  That file appears only when Henri selects the sheet in the editor.
- Loading the catalog never reconciles a sheet that already has a config file. Stored `TILES` are
  used exactly as written. Reconciliation against changed art stays with the existing
  `importSheet()` / `applyImport()` path, where a human reads the report. This is on purpose (see
  the note above `importSheet`).
- Maps store per-frame IDs such as `t000`, not sheet coordinates.
- An unset `WALKABLE` value reads as walkable. Preserve that default.
- Changing walkability does not rewrite a map's tactical layer. The author runs **Fill from art**
  or **Reset to art** to adopt it.
- Hex maps are built for 32 × 32 frames (see `docs/HEX_TILESET_AUTHORING.md`). Other frame sizes
  are allowed and saved, but a hex map drawn from them will not line up. That is the reason for
  the warning, not a bug to fix.

## Items

### HTD-1 — Store each tileset in its own config file and discover sheets from the folder

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Every decision is made in this item: file location and shape, which values
win, when cutting happens, and the exact new functions and their behaviour. The work is one
catalog file, a data migration checked byte for byte against git, two script path updates, and a
probe. None of it needs architectural or visual judgement.

**Depends on:** None.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd`
- `data/worldmap/tilesets.json` (delete)
- `data/worldmap/tilesets/temp2_ground.json` (new)
- `data/worldmap/tilesets/temp2_hex32_ground.json` (new)
- `data/worldmap/tilesets/temp2_hex32_starter.json` (new)
- `scripts/worldmap_editor/build_hex_starter.gd`
- `scripts/worldmap_editor/probe_hex_starter.gd`
- `scripts/worldmap_editor/checks/tilesets/probe_tileset_configs.gd` (new)
- `docs/HEX_TILESET_AUTHORING.md`

**End state:**

- Constants in `WorldMapTilesetCatalog.gd`:
  `CONFIG_DIR := "res://data/worldmap/tilesets"`, `SHEET_DIR := "res://assets/worldmap/tilesets"`,
  `DEFAULT_FRAME_PX := 32`, `DEFAULT_PALETTE_REGION := "temp2"`, `MIN_FRAME_PX := 8`,
  `MAX_FRAME_PX := 256`. `JSON_PATH` is removed.
- `reloadCatalog(configDir := CONFIG_DIR, sheetDir := SHEET_DIR) -> bool` remembers both
  directories in private statics used by every later write. It then does two passes:
  1. **Configs.** Each `*.json` directly in `configDir` is one tileset. Its ID is the filename
     stem. The file holds one JSON object with the same fields the old `save()` wrote per entry:
     `NAME, DESCRIPTION, SHEET, GRID_KIND, FRAME_PX, PALETTE_REGION, NEXT_ID, TILES`. A file that
     does not parse, is not an object, has `NAME` different from its stem, or fails the existing
     `SHEET` / `GRID_KIND` / `FRAME_PX` checks gets one `push_warning` and is skipped. Other files
     still load. Valid entries are normalised exactly as `reloadCatalog` does now
     (`_normaliseTiles`, `NEXT_ID` held above the highest ID). **No cutting or reconciling
     happens here.** A missing `configDir` means zero configs, not an error.
  2. **Sheets.** Each file directly in `sheetDir` whose extension is `png` (case-insensitive) is
     recorded by stem. No image is decoded. A stem with no config gets an in-memory default entry:
     `NAME` = stem, `DESCRIPTION` = `""`, `SHEET` = `"<sheetDir>/<stem>.png"`,
     `GRID_KIND` = `GRID_TILE`, `FRAME_PX` = `DEFAULT_FRAME_PX`,
     `PALETTE_REGION` = `DEFAULT_PALETTE_REGION`, `NEXT_ID` = 0, `TILES` = `[]`. It is marked
     *uncut*.
- `list` holds every entry sorted by ID, and `ids()` returns the same order.
- `has(id)` is true for configured and discovered IDs and never cuts.
- `tilesetFor(id)` cuts an *uncut* entry on first call: `loadSheetImage(SHEET)`, then
  `cutSheet(image, FRAME_PX)`, then `reconcile([], cut["cells"], 0)`. The result's tiles and
  `next_id` are stored and the uncut mark is cleared. An unreadable sheet stays with empty `TILES`,
  warns once, and still clears the mark.
- New public statics:
  - `sheetIDs() -> Array[String]`: the sorted stems found in pass 2. Configs without a PNG are not
    included.
  - `hasConfigFile(id: String) -> bool`: true once a config exists on disk for that ID, whether it
    was loaded or written this session.
  - `configPathFor(id: String) -> String`: `"<configDir>/<id>.json"`.
  - `serialise(reference: Dictionary) -> String`: the entry as `JSON.stringify(obj, "\t") + "\n"`.
    `obj` is built with the same keys and per-tile fields the old `save()` used. `CELL` is written
    as `[x, y]` whether it holds a `Vector2i` or an array.
  - `saveTileset(id: String) -> bool`: makes `configDir` if needed and writes
    `serialise(tilesetFor(id))` to `configPathFor(id)`. It marks the config as existing and returns
    `false` (with a warning) for an unknown ID or a failed write. It writes only that one file.
  - `ensureConfig(id: String) -> bool`: returns `false` for an unknown ID, `true` if a config
    already exists (without writing), and otherwise returns `saveTileset(id)`.
  - `setWalkable(tilesetID: String, tileID: String, walkable: bool) -> bool`: sets that tile's
    `WALKABLE` to `"true"` or `"false"` in memory. Returns `false` for an unknown tileset or tile.
    Does not write.
  - `setFrameSize(tilesetID: String, framePx: int) -> Dictionary`: returns
    `{success, changed, retired, added, error}`.
    - Unknown ID, or `framePx` outside `MIN_FRAME_PX..MAX_FRAME_PX`: fails.
    - Same as the current size: succeeds with `changed = false`.
    - Unreadable sheet: fails.
    - Otherwise it cuts at `framePx` and reconciles against an **empty** ledger starting at the
      current `NEXT_ID`, so every old ID is retired and never reissued. Reconciling against the
      old ledger is forbidden: pass 3 would keep `t000` on cell (0,0) even though that cell now
      holds different art. On success it replaces `TILES`, `FRAME_PX` and `NEXT_ID`, sets
      `retired` to the old tile count and `added` to the new tile count, and does not write.
- The old `save(path)` is removed. `importSheet`, `applyImport`, `walkableFor`, `isWalkable`,
  `cutSheet`, `reconcile`, `hashCell` and `loadSheetImage` keep their current signatures and
  behaviour.
- `data/worldmap/tilesets.json` is deleted. `data/worldmap/tilesets/<NAME>.json` exists for each of
  its three entries, and every field and tile matches the old entry.
- `build_hex_starter.gd` writes its record to `data/worldmap/tilesets/temp2_hex32_starter.json`
  through `Catalog.serialise(record)`, replacing its read-and-upsert of the shared file.
  `probe_hex_starter.gd` reads that file as a single object instead of searching an array. Both
  keep their existing assertions and markers.
- `docs/HEX_TILESET_AUTHORING.md` names `data/worldmap/tilesets/temp2_hex32_starter.json` wherever
  it named `data/worldmap/tilesets.json`.

**Implementation:**

- Do the migration with the catalog itself before deleting anything. Load the old file with the
  current code, then write each entry with `serialise()`. Commit the three files and the deletion
  together.
- Use `DirAccess.get_files_at()` for both passes and sort the results.
- Write `probe_tileset_configs.gd` as a self-cleaning `SceneTree` probe. Mirror the structure of
  `scripts/worldmap_editor/checks/workspace/probe_workspace_contract.gd`: a `failures` array,
  `_require`, print `WORLD MAP TILESET CONFIGS OK`, and `quit(0)` / `quit(1)`. Work in one unique
  `user://htd1_<ticks>/` directory with `configs/` and `sheets/` inside. Write a 64 × 32 opaque
  PNG `alpha.png`, a 32 × 32 fully transparent `blank.png`, a 64 × 48 opaque `odd.png`, and a
  config `legacy.json` (FRAME_PX 16, two tiles) with its 32 × 32 PNG `legacy.png`. Assert:
  - `sheetIDs() == ["alpha", "blank", "legacy", "odd"]`;
  - loading decodes nothing: `alpha` is uncut until `tilesetFor`;
  - `alpha` has defaults and cuts to `t000`, `t001`; `blank` cuts to zero tiles; `odd` cuts to two
    tiles (the 16 px remainder row is ignored);
  - `legacy` keeps FRAME_PX 16 and its two stored tiles byte for byte, and reload does not
    reconcile it;
  - `ensureConfig("alpha")` creates `configs/alpha.json`, a second call leaves the file
    byte-identical, and after `reloadCatalog` the entry loads from the file;
  - `setWalkable` → `saveTileset` → reload persists `"false"`; an unset tile still reads
    walkable; unknown tileset or tile IDs return `false`;
  - `setFrameSize("alpha", 16)` retires 2, adds 8, allocates `t002`–`t009`, and reuses no old ID;
    sizes 7 and 257 fail;
  - a `bad.json` whose `NAME` differs from its stem is skipped while the others load.

  Then call `reloadCatalog()` with defaults, remove only that scratch directory, and assert the
  production catalog again lists the three migrated IDs.
- Do not touch `WorldMapEditorController.gd`, `WorldMapEditorHud.gd`, `WorldMapTilesetPicker.gd`,
  `WorldMapBaker.gd`, `WorldMapTacticalLayer.gd`, `docs/WORLDMAP_EDITOR.md`, any PNG or `.import`
  file, or any map document. Do not add a UI.

**Risk:** A migration slip would renumber tiles and repaint every authored map; the byte comparison
below catches it. Decoding at load would slow every script that preloads the catalog, including
the tactical layer and the baker; the "uncut until asked" assertion catches it.

**Validation:**

- Self-contained:
  `./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --script res://scripts/worldmap_editor/checks/tilesets/probe_tileset_configs.gd --rendering-method gl_compatibility --audio-driver Dummy`
  must print `WORLD MAP TILESET CONFIGS OK` and exit 0. Also run
  `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/worldmap_editor/probe_hex_starter.gd -Marker "WORLD MAP HEX STARTER OK"`.
  Then check the migration against the last committed file:
  `git show HEAD:data/worldmap/tilesets.json | python -c "import json,sys; old={e['NAME']:e for e in json.load(sys.stdin)}; [print(n, json.load(open(f'data/worldmap/tilesets/{n}.json')) == old[n]) for n in old]"`
  must print `True` for all three. Finish with `git status --short`: the only changes allowed are
  this item's Touches paths plus Henri's existing untracked files.

### HTD-3 — Make the lines between editor panels draggable

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** One chrome file and its existing probe. The container tree, node names,
minimum sizes, collapse behaviour and assertions are all specified. The one engine fact that could
be wrong (Godot 4.4 draws a split's drag handle as its own internal control) is checked by the
probe, with a stop rule if it fails, so nothing is left to guess.

**Depends on:** None.

**Touches:**
- `src/presentation/worldmap/editor/workspace/WorldMapWorkspaceChrome.gd`
- `scripts/worldmap_editor/checks/workspace/probe_workspace_contract.gd`
- `docs/WORLDMAP_EDITOR.md` (§6 "Workspace layout" only)

**End state:**

- Under `WorkspaceBody` there is one `HSplitContainer` named `PaletteSplit` with children
  `[PalettePanel, InspectorSplit]`. `InspectorSplit` is an `HSplitContainer` with children
  `[map column, InspectorPanel]`. Both splits use `SIZE_EXPAND_FILL` horizontally and vertically
  and `MOUSE_FILTER_IGNORE`, so clicks on the map still reach the controller.
- Inside `PalettePanel`, the `HSeparator` between `PaletteScroll` and `MapMenu` is replaced by a
  `VSplitContainer` named `PaletteMenuSplit` with children `[PaletteScroll, MapMenu]` and
  `MOUSE_FILTER_IGNORE`. `PaletteScroll` expands vertically and has a minimum height of 96.
  `MapMenu` does not expand, so its full minimum height is always kept and no menu row can be
  dragged out of view.
- The map column has `custom_minimum_size.x = MAP_MIN_WIDTH` (new constant, `360.0`).
  `PALETTE_WIDTH` and `INSPECTOR_WIDTH` remain the minimum widths of their panels.
- Dragging `PaletteSplit` widens or narrows the palette. Dragging `InspectorSplit` widens or
  narrows the inspector. Dragging `PaletteMenuSplit` trades height between the tilesheet and the
  menu. The map's `stageResized` signal fires on each change, as it already does for collapse and
  window resize.
- `_collapseButton(nodeName, panel, width, contentsOf, split: SplitContainer)`:
  - **Collapse:** saves `split.split_offset` in a private `Dictionary` keyed by `nodeName`, then
    sets `split.collapsed = true` and
    `split.dragger_visibility = SplitContainer.DRAGGER_HIDDEN_COLLAPSED`.
  - **Expand:** sets `collapsed = false` and `DRAGGER_VISIBLE`, and restores the saved offset.

  The palette passes `PaletteSplit` and the inspector passes `InspectorSplit`. The palette's
  collapse list is `[PaletteMenuSplit]`, replacing `[_paletteScroll, mapMenuColumn]`. The existing
  width and text/tooltip behaviour stays.
- Drag positions are not saved between sessions.

**Implementation:**

- Change only `build()`, `_buildPalette()`, `_buildInspector()` and `_collapseButton()`. Leave
  theme constants at Godot defaults.
- Probe updates in `probe_workspace_contract.gd`:
  - Change the palette panel path to `Workspace/WorkspaceBody/PaletteSplit/PalettePanel`.
  - In `_checkFitsTargetWindows`, replace `chrome.stage.get_parent().get_parent().get_parent()`
    with `chrome.root.get_node("Workspace")`.
  - Add `_checkDividers(chrome)` after the fit check, at 1280 × 720. For each of the three splits,
    find it by name and assert its `mouse_filter` is `MOUSE_FILTER_IGNORE`. Assert that among
    `get_children(true)` there is a visible internal control whose `mouse_filter` is not
    `MOUSE_FILTER_IGNORE` and whose rect has non-zero size. That control is the drag handle.
  - Set `PaletteSplit.split_offset += 120`, wait two frames, and assert the palette panel grew by
    120 ± 2 px and `chrome.stageRect().size.x` shrank by 120 ± 2 px.
  - Set `InspectorSplit.split_offset -= 80` and assert the inspector grew by 80 ± 2 px.
  - Set `PaletteMenuSplit.split_offset = -10000` and assert the map menu's height is still at
    least its combined minimum height and the menu is still below the scroll.
  - Press `PaletteCollapse` and assert the palette is `COLLAPSED_WIDTH` wide and
    `PaletteSplit.collapsed`. Press it again and assert the pre-collapse width returned (± 2 px).
  - Keep every existing assertion.
- **Stop rule:** if the drag-handle assertion fails because Godot 4.4 has no separate handle
  control, stop and report it in the commit body. Do not work around it by setting the splits to
  `MOUSE_FILTER_PASS` or `STOP`, because that would make map clicks stop reaching the controller.
- Add two or three sentences to `docs/WORLDMAP_EDITOR.md` §6 "Workspace layout": the three draggable
  lines, the menu that can't be squeezed, the map minimum width, and collapse remembering the width.
- Do not touch `WorldMapEditorHud.gd`, the controller, any tileset file, the header, the footer,
  or the action list.

**Risk:** An ignoring split whose handle does not take the mouse would leave the lines visible but
dead, which the handle assertion catches. A split that takes the mouse would block painting, which
the existing stage `MOUSE_FILTER_IGNORE` assertion plus the new split filter assertions catch.

**Validation:**

- Self-contained:
  `./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --script res://scripts/worldmap_editor/checks/workspace/probe_workspace_contract.gd --rendering-method gl_compatibility --audio-driver Dummy`
  must print `WORLD MAP WORKSPACE CONTRACT OK` and exit 0.
- Deferred: open the editor at 1280 × 720, drag each of the three lines, collapse and expand both
  panels, and paint one stroke on the map to confirm clicks still reach it.

### HTD-2 — Show and edit tileset properties in the Hex Map Editor

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** The catalog API it calls is finished by HTD-1. The controls, node names,
texts, the refusal rule for frame-size changes and the save and revert paths are all written out
here. It spans the controller, HUD and picker, but each change is small and named, and no layout or
design decision remains.

**Depends on:** HTD-1, HTD-3 (shares `docs/WORLDMAP_EDITOR.md`).

**Touches:**
- `src/presentation/worldmap/editor/WorldMapEditorController.gd`
- `src/presentation/worldmap/editor/WorldMapEditorHud.gd`
- `src/presentation/worldmap/editor/WorldMapTilesetPicker.gd`
- `scripts/worldmap_editor/checks/tilesets/probe_tileset_properties.gd` (new)
- `docs/WORLDMAP_EDITOR.md` (§2 "Tilesets" and §6 "Palette, layers and first map")
- `docs/plans/hex-tileset-folder-discovery.md` (delete when the cycle closes)

**End state:**

- **Choosing a tileset.** `WorldMapEditorController._hexTilesetChoices()` returns
  `Tilesets.sheetIDs()`, falling back to `[DEFAULT_HEX_TILESET]` only if that is empty. The
  `FRAME_PX >= 32` filter is gone.
- **Config creation on selection.** `_newDocument` calls `Tilesets.ensureConfig(chosen)` right
  after picking `chosen`. `_refreshPalette` calls `Tilesets.ensureConfig(tilesetID)` just before
  `Tilesets.tilesetFor(tilesetID)`. If the file did not exist before, success sets the status
  `Created tileset config data/worldmap/tilesets/<ID>.json.` Failure sets
  `Could not create data/worldmap/tilesets/<ID>.json; tileset changes will not be saved.` and
  editing carries on.
- **Properties block.** `WorldMapEditorHud._buildPalette()` adds a `VBoxContainer` named
  `TilesetProperties` right after `PaletteHint` and before the `HSeparator`. It contains, in order:
  - `Label` `TilesetSheetSize`: `Sheet: <w> × <h> px` from the sheet texture, or
    `Sheet: not readable`.
  - `HBoxContainer` with a `Label` "Frame size", a `SpinBox` `TilesetFrameSize` (min
    `MIN_FRAME_PX`, max `MAX_FRAME_PX`, step 1, suffix `px`), and a `Button` `TilesetFrameApply`
    "Apply". The button is disabled while the spin value equals the current frame size.
  - `Label` `TilesetFrameWarning`, autowrap, orange like `OffContractBadge`, visible only when the
    frame size is not 32: `Hex maps expect 32 × 32 frames. This sheet uses <n> × <n>.`
  - `Label` `TilesetTileCount`: `<n> tiles`.
  - `CheckBox` `TileWalkable`, text `Walkable`, with tooltip
    `Whether the selected tile can be walked on. Applies to the primary tile only. Maps pick this up through Fill from art.`
    It is disabled when the picker has no primary tile. It shows checked unless that tile's
    `WALKABLE` is `"false"`.
- **When the block shows.** `configurePalette()` fills and shows the block using the `framePx`,
  `sheet` and `tiles` it already receives, with no signature change. `_onPickerPrimaryChanged` and
  `setTileChoices` re-sync the checkbox. `showValueOnlyPalette` hides the block. Every
  programmatic change uses `set_pressed_no_signal` / `set_value_no_signal`, so picking a tile never
  triggers a write.
- **HUD callbacks.** `WorldMapEditorHud.build(...)` gains two trailing parameters with defaults:
  `onWalkableToggled: Callable = Callable()`, called as `(tilesetID, tileID, walkable)`, and
  `onFrameSizeRequested: Callable = Callable()`, called as `(tilesetID, framePx)`. Pressing Apply
  when the tileset has at least one tile opens a `ConfirmationDialog` added under `chrome.root`
  with the text
  `Changing the frame size re-cuts the sheet and retires all <n> tile IDs. Other saved maps that use <ID> will lose their art. Continue?`
  Confirming calls the callback. With zero tiles, Apply calls it directly. Cancelling resets the
  spin box.
- **HUD update method.** New `setTileWalkable(tileID: String, walkable: bool)` updates the HUD's
  cached value, the checkbox if that tile is primary, and the picker marker.
- **Picker marker.** `WorldMapTilesetPicker` reads each tile's `WALKABLE` in `configure()` and adds
  `setTileWalkable(tileID: String, walkable: bool)`. In `_drawSheet`, after the frame outlines, each
  tile whose value is `"false"` gets a 2 px red (`Color("ff5a5a")`) X drawn corner to corner inside
  `_zoomedFrameRect(id).grow(-6.0)`. Nothing else in the picker changes.
- **Walkable handler.** `_buildEditorUi` passes `_onTileWalkableToggled` and
  `_onTilesetFrameSizeRequested`.
  - `_onTileWalkableToggled`: calls `Tilesets.setWalkable`. On `false`, it sets the status
    `Unknown tile <tileID>.` and calls `_editorHud.setTileWalkable(tileID, Tilesets.isWalkable(...))`.
    On `true`, it calls `Tilesets.saveTileset(tilesetID)`.
  - If the save fails, it sets the tile back with `setWalkable(..., not walkable)`, calls
    `setTileWalkable` with the old value, and sets the status `Could not write <configPathFor>.`
  - On success, it calls `setTileWalkable` and sets the status
    `<tileID> is now walkable.` or `<tileID> is now not walkable.`, each followed by
    ` Maps pick this up through Fill from art.`
- **Frame-size handler.** `_onTilesetFrameSizeRequested`:
  - If `_documentUsesTileset(tilesetID)`, it refuses with the status
    `Frame size can't change while this map has tiles painted from <ID>. Erase them or start a new map first.`
    and calls `_refreshPalette()`.
  - Otherwise it calls `Tilesets.setFrameSize`. On failure it shows the result's `error`. With
    `changed == false` it does nothing.
  - Otherwise it calls `saveTileset`. If that fails, it calls `Tilesets.reloadCatalog()` to go back
    to the file on disk and shows `Could not write <path>.`
  - On success it calls `_refreshPalette()` and shows
    `Frame size is now <n> × <n>. <retired> old tile IDs retired, <added> tiles cut.`
- **`_documentUsesTileset(id: String) -> bool`.** True when any layer in `_document.layerIDs()`
  whose block `KIND` is `KIND_GRID` or `KIND_DETAIL` and whose `TILESET` equals `id` has a `CELLS`
  entry that is not `MapDataScript.EMPTY`.
- **Docs.** `docs/WORLDMAP_EDITOR.md` §2 describes the per-tileset config files, folder discovery,
  creation on first selection, stored values winning over defaults, and loading never reconciling.
  §6 describes the properties block, the Walkable checkbox and its Fill-from-art note, the
  frame-size refusal and confirmation, and the 32 × 32 warning. Every mention of
  `data/worldmap/tilesets.json` is replaced.

**Implementation:**

- Mirror the existing `PaletteHint` / `_valueRow` construction style in `WorldMapEditorHud.gd`.
- Store the HUD's walkable cache as `_walkableByTileID: Dictionary`, filled in `configurePalette`.
- Write `probe_tileset_properties.gd` as a `SceneTree` probe. Build the chrome and HUD the way
  `probe_workspace_contract.gd::_checkChromeBuilds` does, passing recording callables for the two
  new callbacks. Point the catalog at a unique `user://htd2_<ticks>/` with
  `reloadCatalog(configs, sheets)`, containing a 64 × 32 opaque `alpha.png` and no configs. Assert:
  - after `configurePalette` for `alpha`: the block is visible, the sheet reads `64 × 32`, the frame
    size is 32, there is no warning, and the tile count is 2;
  - selecting `t001` in the picker leaves the recorded walkable callback empty and writes no config
    file;
  - toggling `TileWalkable` records `("alpha", "t001", false)`;
  - `setTileWalkable("t001", false)` leaves the box unchecked;
  - a spin value of 16 enables Apply, and 32 disables it;
  - with a frame size of 16 the warning is visible;
  - `showValueOnlyPalette` hides the block.

  Then instantiate nothing from the controller. Test `_documentUsesTileset` through a
  `WorldMapTileData.create(...)` document with one painted ground cell by calling it on a bare
  `WorldMapEditorController.new()` with `_document` set, and free it. Restore with
  `reloadCatalog()`, remove only the scratch directory, and print
  `WORLD MAP TILESET PROPERTIES OK`.
- Do not add these edits to the undo stack, `WorldMapTileData`, map save or recovery, or battle
  simulation. Do not touch `WorldMapTilesetCatalog.gd` or `WorldMapWorkspaceChrome.gd`. Do not
  change quick-choice labels or picker gestures.

**Risk:** A missed no-signal setter would write a config file whenever a tile is merely selected;
the probe's "no callback, no file" assertion catches it. Changing the frame size under a painted
map would silently repaint it; `_documentUsesTileset` refuses that, and the probe covers the
helper.

**Validation:**

- Self-contained:
  `./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --script res://scripts/worldmap_editor/checks/tilesets/probe_tileset_properties.gd --rendering-method gl_compatibility --audio-driver Dummy`
  must print `WORLD MAP TILESET PROPERTIES OK`. Also rerun HTD-1's and HTD-3's probe commands.
  All three must exit 0, and `git status --short` must show no new `data/worldmap/tilesets/*.json`.
- Deferred: in the editor, create a new map from `temp2_hex32_starter_v2`, and confirm
  `data/worldmap/tilesets/temp2_hex32_starter_v2.json` appears. Untick Walkable on one tile and
  confirm the red X and the file change. Reopen the editor and confirm the value persisted. Then
  delete that generated JSON unless Henri wants to keep it.

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | HTD-1, HTD-3 | HTD-1 owns the catalog, tileset data and starter scripts; HTD-3 owns the workspace chrome, its probe and §6 "Workspace layout". No shared paths. Validation for both is inline. |
| 2 | HTD-2 | Needs HTD-1's catalog API and edits `docs/WORLDMAP_EDITOR.md` after HTD-3. Its deferred check is the cycle's in-editor pass and folds into the same session. |

## Deliberately excluded

- Non-square frames, margins, and spacing. Frame size is one number used for width and height.
- Editing `TERRAIN`, `AUTOTILE`, `VARIANT`, labels, liftability, palette region, or description in
  the UI.
- Undo for tileset property edits. They are saved immediately and are not part of the map's history.
- Automatically rewriting tactical layers or other saved maps after a walkability or frame-size
  change.
- Remembering dragged panel sizes between sessions.
- Nested sheet directories and non-PNG sheets.
- Moving existing art, or committing `temp2_hex32_starter_v2.png` or its config.
