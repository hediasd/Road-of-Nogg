# Shallow folder layout correction

Opened 2026-09-24 after FLAT-2's first real import and full probe sweep exposed two defects in the frozen migration contract. This cycle repairs those defects without reopening the folder-layout decision, restoring any removed hierarchy, changing gameplay, or touching retained art content. The original `shallow-folder-layout.md` remains frozen.

## Outcome

The flat cube-placeholder collection has an accurate independence probe and documentation; a migration replay from the FLAT-1 revision produces the same Godot-stable import sidecar as the live tree; the manifest verifies after a real import; and the empty legacy `src/` and `scripts/` directory trees are gone after deleting the proven orphan UID sidecar.

## Present-state facts an executing agent must not "fix"

- All seven cube-placeholder substrate scripts and all four families deliberately share `effects/cube_placeholders/`; recreating `shared/`, `travel/`, `impact/`, `control/`, or `restore/` would undo the requested flattening.
- The Nogg Herald PNG and its `.import` sidecar are retained art. Godot's generated cache basename follows the flattened source filename; correcting the contract must not alter the PNG or its import UID.
- The terrain probe already reaches a missing generated-scene condition in the pre-migration revision. Generated scenes are ignored local products and are outside this correction.
- The pre-migration fuzz probe passes close to its 300-second limit. A migrated timeout needs a targeted rerun, but this item must not tune battle behavior or the fuzz workload.

## Items

### FLAT-C1 — Reconcile the flat layout with its verification contract

**Model:** Opus 5 / GPT Sol

**Model rationale:** The code edit is small, but it must preserve the semantic boundary of the old shared-substrate probe after removing its directory, distinguish generated import behavior from authored art, and keep a replayable migration contract consistent with the already-applied tree. That boundary judgment and recovery risk require the architectural tier.

**Depends on:** FLAT-2 commit `32a2232`.

**Touches:**

- `checks/vfx/probe_cube_substrate.gd`
- `docs/effects/cube-placeholder-foundation.md`
- `docs/effects/cube-placeholder-travel.md`
- `docs/effects/cube-placeholder-impact.md`
- `docs/effects/cube-placeholder-control.md`
- `docs/effects/cube-placeholder-restore.md`
- `tools/folder_layout_manifest.json`
- `scripts/hex_battle/side_turn/capture_damage_number.gd.uid`

**End state:** The substrate probe checks exactly the seven flattened substrate scripts and passes. Every cube-placeholder page names `effects/cube_placeholders/` as the code location. The manifest transforms the FLAT-1 inputs into these corrected files and expects the Nogg Herald `.import` bytes produced by Godot. `Verify` passes both before and after a real import. The orphan UID and all now-empty legacy `src/` and `scripts/` directories are absent. No retained art payload changes.

**Implementation:** Keep the collection flat while preserving what the old `shared/` directory encoded: only the seven substrate scripts are subject to the independence scan. Decide the clearest durable representation of that inventory in the probe and explain the choice in the commit body. Correct the manifest as a replay contract, not merely as a checksum of the live tree: its ordered replacements must produce the corrected probe, documentation, and import sidecar from the FLAT-1 baseline. Delete the old UID only after proving its script is absent and its UID is unreferenced. Do not edit the original plan, the migration PowerShell, baseline inventory, any cube effect implementation, any art payload, or either unrelated failing probe.

**Risk:** A live-tree-only checksum edit could make `Verify` pass while `Apply` remains wrong; an over-broad independence scan could constrain family implementations the old contract did not cover; and an unsafe cleanup could remove concurrent work under a legacy directory. Catch these with a disposable replay, exact file inventory, and a fresh filesystem check immediately before deletion.

**Validation:**

- Self-contained: replay the revised manifest from commit `5ae534d` in a disposable archive and require `Apply` plus `Verify` to pass; run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/folder_layout.ps1 -Mode Verify`; run a real headless import followed by `Verify`; run `powershell -NoProfile -ExecutionPolicy Bypass -File checks/run_probe.ps1 -Script res://checks/vfx/probe_cube_substrate.gd -Marker CUBE_VFX_SUBSTRATE_OK -TimeoutSeconds 180`; rerun `probe_fuzz.gd` at its registered 300-second budget; run the full probe sweep and attribute only failures outside this item's paths; confirm all 254 art hashes and the six recorded duplicate groups; run `git diff --check` on the owned paths.

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | FLAT-C1 | single correction item; validation inline, no deferred checks |

## Deliberately excluded

Generated terrain scenes and their source authoring flow, fuzz workload or battle-performance changes, visual/playtest acceptance owned by FLAT-V, any hierarchy restoration, art deduplication, and all frozen-plan or square-battle-package edits.
