# Shallow folder layout

2026-09-24. Reorganize Road of Nogg around directly accessible working areas,
normally `root/folder/file`, with `root/folder/collection/file` only where a
real collection or resource contract warrants it. The user explicitly requires
retaining all art collections. This cycle changes locations and their consumers,
not game design, appearance, content selection, or runtime ownership. Execute
on the currently checked-out branch; no branch or worktree is requested.

## Outcome

- Maintained code no longer sits behind the `src/presentation/...` or
  `src/systems/...` wrappers. Small one-script subfolders disappear.
- Maintained files have at most two directory components, except individually
  documented compatibility exceptions. Root files such as `project.godot`,
  `AGENTS.md`, `BACKLOG.md`, and `README.md` remain at root.
- Every existing art asset, collection, duplicate, prototype, font, model,
  shader, texture, reference image, design sketch, generator and measurement
  artifact survives. Moving a file does not authorize deleting or deduplicating it.
- Resource loads, scene entry points, catalog discovery, document loading,
  export filters, check manifests, and documented commands resolve correctly.
- Logical headless and presentation boundaries remain enforceable after paths
  change. Gameplay identities, seeded outcomes and content stay unchanged.
- The module map is the maintained navigation guide. A compact relocation
  manifest lets sessions translate historical paths without retaining wrapper
  directories or modifying other frozen plans.

## Present-state facts an executing agent must not "fix"

The read-only audit at `cafdc64` counted 1,224 tracked files in 123 directories,
with a maximum of five directory components. Excluding `.uid` and `.import`
sidecars left 705 files; 47 directories held only one or two directly contained
non-sidecar files. Refresh these observations at execution; they are not targets.

- `src/entity_ai/SimpleBrain.gd.uid` and
  `src/presentation/StatusEffectBillboard.gd.uid` had no matching scripts.
  These are the only tracked deletion candidates authorized by this plan,
  conditional on rechecking that their scripts are still absent.
- `export_templates/`, `feature_profiles/`, `script_templates/`, and
  `text_editor_themes/` were empty. Remove only while still empty, non-recursively.
- Suspected unused code and old scenes remain. Lack of a textual caller is not
  proof of disuse. In particular retain `BattleSetupPresets`, `BattleVisualEffects`,
  `DeepCard`, `PortraitRenderer`, `map01.tscn`, and `Monster.tscn`.
- SHA-256 matched six pairs of asset files. Preserve BOTH files of every pair,
  including the two aura panels and two generated map images. Distinct consumers
  and output owners may legitimately use identical content.
- `references/square-battle/` is an intentionally frozen runnable package.
  Leave its archive, manifest, README and internal historical paths byte-identical.
- `.godot/`, `.git/`, IDE/agent directories, `battle_output/`, `builds/`, and
  `debug/` are not cleanup targets. Do not sweep local caches, screenshots,
  generated outputs or untracked art. The four empty root directories above
  are the only untracked deletion allowance.
- Existing quarantines remain quarantined with the same reasons. Renderer
  entries skipped by the sweep are not visual passes.
- Frozen plans contain old paths. Preserve their text and reference artifacts;
  do not rewrite them, relocate their linked assets, or close unrelated cycles.
- `docs/plans/README.md` contains older quiet-tree examples. Current `AGENTS.md`
  governs: inspect and attribute concurrent edits; do not demand a clean tree.

## Target working areas

These are the approved destination areas for the mapping item. Its judgment is
which individual presentation helpers belong together and which genuine resource
bundles need an exception, not whether to invent a new subsystem architecture.

| Destination | Contents / allowed collection level |
|---|---|
| `simulation/` | Existing battle simulator, board and spatial algorithm files, flat |
| `ai/` | Existing entity AI, including the named legacy baseline, flat |
| `content/` | Existing entities and factories, flat |
| `battle/` | Battle scene orchestration, cameras, meshes, adapters, rendering and output helpers, flat |
| `ui/` | Battle UI, shared HUD/theme widgets and UI helpers, flat |
| `effects/` | Effects, playback and VFX helpers; `cube_placeholders/` may hold the complete cube collection with no family subdivisions |
| `worldmap/` | World-map presentation, flat |
| `map_editor/` | World-map editor, document, export, foundation and workspace scripts, flat |
| `scenes/` | Eight maintained scenes directly inside; `generated/` reserved for generated scenes |
| `data/` | Main catalogs directly inside; `maps/`, `scenarios/`, `worldmap/`, `authored/`, `tilesets/` as flat collections |
| `assets/` | `fonts/`, `models/`, `textures/`, `shaders/`, `ui/`, `worldmap/`; flatten each, subject to justified inseparable resource bundles |
| `tools/` | Manual runners, generators, captures and analysis helpers; flat unless a substantial named collection earns level two |
| `checks/` | Sweep and process runner directly inside; `battle/`, `worldmap/`, `vfx/`, `fixtures/`, `manifests/` as flat collections |
| `docs/` | Main docs directly inside; existing `effects/`, `lore/`, `plans/`, `sketches/`; frozen plan support trees are temporary depth exceptions |
| `references/` | Research from `gamerefs/` directly inside; frozen `square-battle/` package unchanged |

Use existing filenames unless flattening creates a collision. Resolve collisions
with descriptive collection prefixes, not numbered copies; preserve paired
sidecar naming. Keep artist-authored identifiers and display names unchanged.
Do not scatter a single model's companion material/texture resources to satisfy
a cosmetic depth count. A named, evidenced resource-bundle exception is preferable
to breaking or re-exporting retained art. Engine/agent-owned layouts are exempt.

## Execution and ownership

Only this new cycle file is owned while authoring this plan. The three execution
items below run sequentially, each in its assigned session. No automatic agent
delegation is requested. Check and state the actual model against the item's tier
before execution; a mismatch is a cost signal, not a gate.

**Blocking coordination requirement for the relocation item:** its moves and
reference updates intersect other active cycles. Before its first write, obtain
explicit ownership hand-offs for overlapping source AND destination paths from
the user or their owning sessions. The mapping item can proceed independently
because it writes only its three new files. Unrelated work can continue at all
times. An existing dirty path must never silently enter the migration commit.

The complete migration write boundary, referenced below as **M**, is:

- `src/**`, `simulation/**`, `ai/**`, `content/**`, `battle/**`, `ui/**`,
  `effects/**`, `worldmap/**`, `map_editor/**`.
- `assets/**`, `scenes/**`, `data/**`, `scripts/**`, `tools/**`, `checks/**`,
  `gamerefs/**`.
- `references/*.md` only; `references/square-battle/**` is excluded.
- `docs/*.md`, `docs/effects/**`, `docs/lore/**`, `docs/sketches/**`;
  `docs/plans/**` is excluded except the final deletion of this cycle file.
- `AGENTS.md`, `README.md`, `BACKLOG.md`, `.gitignore`, `project.godot`,
  `export_presets.cfg`.
- Non-recursive removal of the four empty directories named above.

M is an upper bound, not permission to rewrite every file it contains. The
committed manifest must enumerate exact old/new paths and exact in-place edits.
Ownership transfer covers those exact paths. No blanket staging or glob-based
commit is permitted: stage new destinations explicitly and commit the exact
source, destination and in-place-edit list, including deleted sources. Generated
import metadata at mapped destinations belongs to the same explicit list.

Do not rewrite `BACKLOG.md` beyond mapped path/link substitutions. Update policy
path lists without weakening their rules. Frozen-plan historical paths remain
resolvable by consulting the manifest; that lookup does NOT transfer another
session's ownership. A future dispatch against an old Touches list must explicitly
coordinate its translated paths.

## Items

### FLAT-1 — Resolve the move contract and prove the migration machinery

**Model:** Opus 5 / GPT Sol.

**Model rationale:** Classifying shared presentation helpers, preserving binary
resource bundles and saved-document references, and separating live path uses
from historical evidence require architectural and compatibility judgment. A
mechanical search-and-replace specification does not yet exist.

**Depends on:** None.

**Touches:**
- `tools/folder_layout.ps1` (new).
- `tools/folder_layout_manifest.json` (new).
- `tools/folder_layout_baseline.json` (new).

**End state:** A complete, committed, executable move specification exists for
the current tracked tree, within M. It has collision-free destinations, exact
reference patches, collection/depth exceptions, the two conditional metadata
deletions, and an independently checkable retention baseline. No existing project
file has moved or changed. The next item has no unresolved classification or
path-rewrite decisions. Record decisions and rejected alternatives in the commit.

**Implementation brief:** Preserve the target navigation shape while keeping
runtime boundaries, resource identities, authoring round trips and asset payloads
intact. Inspect actual callers, catalog discovery, relative imports, path-building
code, directory-depth assumptions, binary resource dependencies, export filters,
the square-reference reconstruction utility and the check runner. Global class
names are not substitutes for fixing literal `preload` paths.

Decide the exact mapping and patches, not new gameplay or visual behavior. Resolve
each root-level presentation helper and every basename collision. For binary
art/resources prefer relocating intact dependency bundles over reserialization.
Retain separate files even when hashes match. Existing model-relative URIs must
continue to resolve. Do not rename shader uniforms, class names or authored IDs.

Path-bearing saved maps, scenarios, resource fingerprints and historical runner
commands need explicit treatment. Exercise pre-move authored documents and data
fixtures against the proposed layout; do not silently invalidate external saved
documents or rewrite `user://` saves. A justified retained-path bundle exception
is allowed. If preserving a contract requires new runtime behavior rather than
path substitutions, identify the exact missing scope and stop dependent work for
a revised plan; do not hide that redesign inside a Terra patch.

Deliver a small migration utility with this fixed invocation contract:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/folder_layout.ps1 -Mode SelfTest
powershell -NoProfile -ExecutionPolicy Bypass -File tools/folder_layout.ps1 -Mode ValidatePlan
powershell -NoProfile -ExecutionPolicy Bypass -File tools/folder_layout.ps1 -Mode Apply
powershell -NoProfile -ExecutionPolicy Bypass -File tools/folder_layout.ps1 -Mode Verify
```

`ValidatePlan` is read-only. `Apply` performs only the exact committed map and
patches; it must reject changed input hashes, missing files, destination collisions,
case-only rename hazards and out-of-bound paths before changing anything. Handle
Windows case-insensitive comparisons explicitly. It never commits, stages, pushes,
cleans caches, recursively deletes, or edits frozen plans. Verify absolute move
targets remain within the repository. Provide resumable reporting after a partial
failure without overwriting newly changed files. Do not auto-revert other work.

The baseline records one entry per retained pre-migration file, preserving
multiplicity, UID values and asset hashes. Exclude the three migration-tool files
from their own input hashes to avoid a self-referential baseline; verify their
committed revision separately. Binary art is byte-identical. Text assets may change only
enumerated resource-path spans; verify their remaining payload is unchanged.
The utility must detect dropped files, dangling sidecars, unmapped changes and
unexpected rewritten content. Resource checks include literal paths, known dynamic
path constructors, import settings, scene dependencies, export include/exclude
rules, and probe registration parity. Account for binary resource dependencies;
text scanning alone is not complete evidence. Historical paths in frozen packages
and plans are explicitly excluded from stale-live-path failures.

Define `checks/run_probe_sweep.ps1`, `checks/run_probe.ps1` and
`checks/manifests/` as the final runner locations. `probe_ui_guardrails.gd` maps
to `checks/battle/probe_ui_guardrails.gd`. Classify other probes by their actual
area, not solely their old parent; all current manifest entries survive with
unchanged markers, timeouts, expect/gate/renderer values and quarantine reasons.
The checker is a PowerShell migration utility, not a new Godot probe.

Include exact documentation/policy patches in the manifest, including the
`docs/MODULE_MAP.md` layer map and `docs/DEVELOPMENT.md` commands. The existing
module map remains the navigation owner; do not add a competing routing document.
Keep the machine-readable translation manifest after closure for older plans.

**Risk:** A plausible flat tree can break binary assets, derived paths, user
documents or exclusions while passing a filename scan. A long-lived manifest can
also go stale while another session edits; fail closed on changed inputs and
refresh the specification in the mapping item's owned files before dispatch.

**Validation:**
- Self-contained: Run `SelfTest` and `ValidatePlan` above. SelfTest must include
  collision, UID-pair, changed-input, binary-retention, duplicate-retention,
  out-of-root and frozen-file rejection cases in disposable temporary fixtures.
  Prove every planned mutation lies in M, all target exceptions have reasons,
  all asset instances survive, and no existing repository file was changed.
  Run `git diff --check -- tools/folder_layout.ps1 tools/folder_layout_manifest.json tools/folder_layout_baseline.json`.
  Record inventory, anticipated depth/folder counts, exclusions, compatibility
  decisions and results in the commit body. No deferred check for this item.

### FLAT-2 — Apply the committed shallow layout without changing content

**Model:** Sonnet 5 / GPT Terra.

**Model rationale:** The preceding commit supplies exact destinations, patches,
exceptions and an executable verifier. This is a large but fully specified
mechanical migration; it leaves no architectural or art-selection choices open.

**Depends on:** FLAT-1 and explicit ownership hand-offs for overlapping paths.

**Touches:** M, restricted to the exact paths in the committed manifest. Read
the three mapping-tool files but do not change their behavior or specifications.
The four empty root directory removals are conditional and non-recursive.

**End state:** Every manifest move and patch is applied; `Verify` passes; source
wrappers are absent where empty; permitted historical/resource exceptions remain.
All art instances, old scenes and suspected dead code remain. The only removed
tracked content is the two still-orphaned UID sidecars. New paths, the main scene,
export rules, catalog discovery and developer commands work together in one commit.

**Implementation specification:**
1. State the tier check and confirm exact-path ownership. Record HEAD and the
   focused before-diff. Do not fold another session's existing edits into this commit.
   Before moving visual resources, inventory stored comparison evidence. If it
   does not cover the required callers, obtain user-owned pre-move observations
   or captures first; do not move first and discover the baseline is missing later.
2. Run `ValidatePlan` using the exact command above. If it fails, make no edits:
   return its concrete discrepancy to the mapping owner; Terra must not improvise
   new mappings, patch ranges or exceptions.
3. Run `Apply`, then `Verify`. Preserve every `.gd.uid` value and all import
   settings except specified source/dependency path changes. Do not deduplicate,
   re-export art, retune a visual, extract helpers, rename symbols, or modernize code.
4. Import mapped resources headlessly using the command below. Inspect generated
   metadata against the mapping before explicitly staging it; never stage caches.
5. Run the listed self-contained checks. On a migration defect, return the exact
   failure to the mapping owner rather than broadening scope. Commit completed
   work or a precise WIP if interrupted; never leave owned edits uncommitted.

```powershell
./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --import --rendering-method gl_compatibility --audio-driver Dummy
./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --quit-after 5 --rendering-method gl_compatibility --audio-driver Dummy
powershell -NoProfile -ExecutionPolicy Bypass -File tools/folder_layout.ps1 -Mode Verify
powershell -NoProfile -ExecutionPolicy Bypass -File checks/run_probe_sweep.ps1
git diff --check
```

**Risk:** Godot's class/import cache can conceal bad paths; changed folder depth
can invalidate runner root calculations. A partial move can leave the shared tree
unusable. Use the preflight and one migration commit rather than leaving half of
the caller graph pointed at nonexistent paths. Report failures outside the claimed
paths without repairing them. Do not broaden the commit to absorb concurrent work.

**Validation:**
- Self-contained: Run all commands above; inspect Godot logs for parse/load errors
  rather than trusting exit code alone. The full sweep is required because every
  probe's path or loaded code can move. `Verify` must prove file/art multiplicity,
  content/UID parity, import settings, registered-check parity, no live dangling
  references, and the promised depth with enumerated exceptions. Compare the exact
  owned diff to the manifest before explicit-path staging and committing. Record
  all results and legitimate path/hash changes in the commit body.
- Deferred: At the committed migration revision, validate battle setup/playback,
  HUD, every affected existing effect/resource caller, world-map/editor loading,
  pre-move document open/save-copy/export, retained art loads and exported-game
  behavior; record unrelated in-flight context in one consolidated line.

### FLAT-V — Independently validate and close the reorganization

**Model:** Opus 5 / GPT Sol.

**Model rationale:** Acceptance spans runtime, editor, binary assets and all
existing visual callers. It needs independent interpretation of preservation
evidence and observed appearance, not just successful rename-script execution.

**Depends on:** FLAT-2.

**Touches:** M for migration-defect fixes only; `docs/plans/shallow-folder-layout.md`
for deletion at successful closure. No deletion of retained content or other
frozen plans. Mapping-tool corrections are allowed only for demonstrated defects,
with the original baseline retained as evidence rather than rewritten to pass.

**End state:** The promised shallow navigation is usable; preserved art and
existing game/editor behavior are verified; the cycle file is deleted in this
item's commit. Failure or missing required observations does not count as closure.

**Implementation brief:** Independently compare the committed manifest, changes
and retained-file baseline. Look especially for a resource kept on disk but no
longer discoverable, a silently enlarged export, duplicate art collapsed into one
file, or a logical boundary obscured by the new root folders. Record the judgment
and evidence in the commit body. Fix only migration defects, not pre-existing game
issues or unrelated session changes; rerun affected checks after a fix.

The user owns interactive Godot playtesting under `AGENTS.md`. Prepare exact
scenes and observation steps and use user-provided results for interactive checks;
do not start, close or automate an interactive Godot window. Headless imports and
checks are allowed. Obtain comparison evidence from existing goldens or pre-move
captures where available; if a necessary visual baseline is missing, report the
gap and request that observation rather than treating a file hash as visual proof.

Exercise: main battle entry/setup and a representative turn; HUD/status/aiming;
VFX debug playback for affected effects and every existing caller of relocated
shared resources; world-map and editor debug scenes; old and current authored
documents opened and saved to disposable copies; generated scene export and a
Windows export using the existing preset. Do not overwrite user-authored maps.
Compare appearance, timing, playback and lifecycle to the pre-move evidence.
Preserve all payloads and verify model/font bundles also load at their new paths.

Run the complete sweep in this last item even if the migration item passed it.
Renderer skips remain outstanding until observed through the user-owned flow.
Use the final equivalent of the UI guardrail probe through the sweep; ensure
its entry is present and passes. Do not un-quarantine anything to change counts.

At closure leave the relocation manifest and maintenance utility available,
remove only this cycle file, and report before/after directories and depth,
retained-file/art counts, exceptions, verification and anything still actionable.
No backlog entry is required merely because unused-code candidates were excluded.
Push only under the repository's passed-check/scene-load rules; report a hold if
required validation is incomplete. Do not execute unrelated branch housekeeping.

**Risk:** A clean compile and unchanged bitmap hashes do not prove visual parity
or that exported builds include dynamically loaded content. Missing user-owned
observations must remain explicitly pending rather than being converted to passes.

**Validation:**
- Self-contained: Run `SelfTest`, `Verify`, the documented headless load command,
  `powershell -NoProfile -ExecutionPolicy Bypass -File checks/run_probe_sweep.ps1`,
  and `git diff --check`; inspect export contents against the intended resources
  and exclusions. Record check parity, asset/UID preservation, load evidence,
  folder counts, exception rationale and any defect fixes in the commit body.
- Deferred: Consolidate all migration observations above against the FLAT-2
  revision (plus any validation fixes), identifying the observer, comparison
  evidence and unrelated in-flight context; only an observed pass clears closure.

## Deliberately excluded

- Art deletion, deduplication, pruning old collections, changing lore or names,
  font replacement, atlas regeneration, effect tuning, and shared-resource redesign.
- Deleting suspected dead code or old scenes; that is a separate evidence-backed task.
- Cache/output retention cleanup, arbitrary empty-directory sweeps and new worktrees.
- Rewriting other frozen plans, merging unrelated cycles, or cleaning their branches.
- Adding symlink/junction wrapper trees that preserve the unwanted navigation depth.
- Broad architecture refactors masked as relocation. Logical ownership must survive
  even where two small headless directories become one physical directory.

## Waves

| Wave | Items | Why sequential / validation form |
|---|---|---|
| 1 | FLAT-1 — Opus 5 / GPT Sol | Produces the exact specification in three new paths; can coexist with other cycles |
| 2 | FLAT-2 — Sonnet 5 / GPT Terra | Apply the committed specification only after overlapping-path ownership hand-offs; no concurrent item in this cycle |
| 3 | FLAT-V — Opus 5 / GPT Sol | Standalone validation: crosses subsystems and requires independent visual judgment; close in this item's commit |

Two implementation items: no scheduled convergence review is required. The
mapping must be verified before relocation; the standalone validation is the
only deferred-validation item. Never edit this cycle file during execution.
