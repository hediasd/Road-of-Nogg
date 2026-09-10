# Hex editor foundation audit

2026-09-10. Read-only implementation audit requested by the user after trying
the unfinished editor. Baseline HEAD: `15ff9d31541697dbfd24bc0a982b5b42c37e642e`.
The accepted reference is the 2026-09-09 interactive workspace sketch. The
follow-up now explicitly requires fresh startup, removal of environmental
clutter, File New/Open/Open Recent/Save/Save As, and a defined authoring format
that can produce battle maps.

## Evidence and limits

Inspected the source, focused working diff, and implementation commit bodies.
Launched `scenes/debug/WorldMapEditorScene.tscn` at requested 1280x720 with the
bundled Godot 4.4. The captured Windows image was approximately 1034x611 under
host scaling; do not confuse that capture size with a second configured game
resolution. Observed startup, New, the default new-map dialog, and the starter
palette after creating an unsaved map named `audit_hex_20260910_c7e6`.
No source map was saved or exported, no painting acceptance was performed, and
only the audit-owned engine process was stopped. No matching recovery file was
found afterwards. This audit is not the missing integrated acceptance pass.

Concurrent changes observed at launch:

- `WorldMapTilesetPicker.gd`: preview metadata changed from horizontal to
  vertical layout; empty/no-selection preview hidden (7 additions, 2 removals).
- `WorldMapWorkspaceChrome.gd`: a minimum-width floor added to action buttons
  to address collapsed labels (4 additions).

These edits are another session's work and were neither changed nor committed
by this audit. Their presence is evidence of fixes in progress, not proof of
their completion or ownership transfer. Audit conclusions below include them.
No `Plan-Item: HXW-8` commit was found. Re-read history and the focused diff
before dispatch: this is a dated snapshot, not a live status tracker.

The normal sandboxed engine launch crashed before the scene. The same existing
engine ran outside the sandbox. That environment failure is not attributed to
editor code. The first hidden audit launch was stopped before relaunching the
visible inspection window; no unrelated process was stopped.

## Proximity to the sketch

The data/interaction foundation is substantially implemented. The visible
first-use experience is still far from the accepted sketch in its two most
important jobs: showing the author a clean workspace and presenting tiles to
choose. Seven implementation commits are not seven-eighths of a usable editor.

| Area | What exists | Gap / severity / evidence |
|---|---|---|
| Document startup | Title correctly reports no authored document | **P1, observed:** temp2 painted region and animated clouds still fill the canvas. `_ready()` calls `super._ready()` then `_openDocumentForRegion(_regionID)`. This is a painted legacy preview, not a loaded editable square document; both the title and status confirm the contradiction. |
| Tilesheet picker | Real stable-ID selection, Ctrl/Shift selection, zoom and selected-frame drawing code | **P1, observed:** after New, only the enlarged land tile and its metadata are visible; the selectable sheet is absent from the allocated area. `_ensureUi()` adds `PickerColumn` beneath a plain Control without anchoring/sizing it to the parent. The ScrollContainer has no guaranteed positive height. This is the leading source-backed layout diagnosis; geometry instrumentation must confirm it during the fix. |
| Import resilience | Catalog raw-sheet loader already exists | **P1, source:** controller uses ResourceLoader/load for palette images and offers a tile-ID dropdown fallback when an image is not imported. It can degrade a primary feature to a debugging control instead of using the source image. In this audit the primary preview rendered, so missing import alone does not explain the observed collapsed sheet. |
| Selection authority | Picker primary relays into `tileOption`; paint reads the OptionButton | **P1, source:** the dropdown remains the real selection source. Empty picker primary changes are ignored, leaving the last paint value active; clearing selection can still paint a stale tile. `_syncPickerToValue` also replaces selection with a singleton. Cover both empty selection and mode/layer refresh transitions in regression checks. |
| New-map defaults | Starter tileset correctly selected | **P2, observed:** smallest preset, 3x2, is selected by default; the resulting tiny dark patch is surrounded by clouds/sea. New does not automatically present a useful fitted editing view. |
| Buttons/layout | Named document/tool buttons are present; in-flight width fixes improve visibility | **P2, observed:** dense dark strips, technical labels and clipped layer names remain. The rightmost layer controls are not legible in the captured narrow interface. Fix real bounds, not only combined minimum-size assertions. |
| Palette hierarchy | Atlas identity and selected preview exist | **P2, observed/source:** sketch's Land/Sea/Grass quick choices are absent; the selected preview dominates the sheet; tile-ID dropdown and scatter seed consume space even for ordinary painting. |
| File operations | New/Open/Save/Save As, dirty/history/recovery infrastructure | **P1 against clarified requirement:** no Open Recent action; Open enumerates authored-folder filenames into a choice list, not a normal file picker. Filenames, map names and export paths are coupled. Save requires both source and bake success. |
| Painting/history | Revision identity, footprints, interpolation, axial stamps, seeded scatter, visibility copy, save-point and recovery code | Preserve. Commit bodies report passing narrow checks, but full hands-on acceptance is pending. Do not rewrite these because the shell is poor. |
| Environment/tools | Shipping rig preserved; preview drawer collapsed | The original plan permitted this compromise. The user's new requirement changes it: clouds, lights, sky, legacy region picker and shipping-preview chrome must be absent from the foundation editor. Their runtime assets and donor tools remain intact. |
| Battle boundary | Existing scene export and headless tactical definition export | Preserve runtime schema, explicit tactical meaning and single-surface restrictions. New source-document identity/path semantics require a dedicated export adapter; raw source JSON is not automatically a battle scenario. |

## Existing implementation and pending work

| Prior item | Commit / status at audit | Carry forward |
|---|---|---|
| HXW-1 history | `d50839f`; original self-contained run was environment-blocked, later HXW-4/HXW-6 bodies report passing | Keep revision API; recheck only when affected. |
| HXW-2 starter | `4fab781`; generated asset/catalog and probe committed | Reuse the existing 15-frame sheet and generator; no art regeneration cycle. |
| HXW-3 picker | `2d03758`; component logic committed, layout fixes currently uncommitted | Fix actual sheet layout/import/selection integration; require path handoff. |
| HXW-4 workspace | `1b9b764`; shell committed, action sizing currently uncommitted | Replace debug-driven startup and presentation; retain useful action/focus/geometry helpers. |
| HXW-5 painting | `3deddbd`; narrow checks reported passing | Carry all pending real brush/parity/interruption/hidden-layer export checks. Height/tactical visualization was not delivered as an independently hideable view. |
| HXW-6 document safety | `36d3a0a`; injected-I/O checks reported passing | Carry real dialog/close/crash/recovery verification; revise source-versus-bake save policy deliberately. |
| HXW-7 docs | `15ff9d3`; implemented-behaviour documentation | Update again after the clarified foundation/file changes; do not treat prose as visual acceptance. |
| HXW-8 acceptance | No commit | Its relevant checks transfer to the new final acceptance after an explicit ownership handoff. The current session's exact remaining activity is not inferable solely from uncommitted edits. |

Not started in this milestone: clean welcome/File Recent, independent editor
environment, normal source-file chooser, versioned document envelope, the new
identity-aware battle export adapter, and accepted-layout picker repair.
The larger programme's map selection/clipboard, multi-layer stamp library,
advanced sculpting, water/bridge authoring, object inspector, full autotiling
and tactical inspection overlays remain later work, not silently completed.

## Available reference materials

- New plan's independent copy: `../references/hex-editor-foundation-workspace.html`.
- Current authoring guide: `../../HEX_TILESET_AUTHORING.md`.
- Starter asset: `assets/worldmap/tilesets/temp2_hex32_starter.png`.
- Catalog: `data/worldmap/tilesets.json`, entry `temp2_hex32_starter`.
- Editable guides: `assets/worldmap/tilesets/templates/hex32_guides.svg`.
- Rebuild/probe: `scripts/worldmap_editor/build_hex_starter.gd` and `probe_hex_starter.gd`.
- Existing source schema: `WorldMapTileData.toDictionary/fromDictionary`.
- Existing game boundary: `WorldMapBattleExport.buildDefinition` and headless `BattleMapFactory`.

The starter PNG SHA-256 at audit was
`FE4149A21B91809209BE21A19346EDEC711FAA3CD66F9B03E1C0A7AE839F4D52`.
Its 32px geometry is intentionally camera-compensated. It contains three solid
fills and twelve manual edge examples; it is not a complete autotile set.

## Planning correction

The first plan overprotected the inherited debug shell and permitted both an
ID-dropdown fallback and a collapsed preview drawer. Those choices left room
for this outcome. The recovery plan makes the *visible complete tilesheet*,
single selection state, neutral blank startup and source-only saving literal
acceptance requirements. Passing selection arithmetic is insufficient when
the sheet cannot be seen or clicked.
