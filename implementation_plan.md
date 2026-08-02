# Implementation Plan

Opened 2026-08-01 after the window-scaling and docked-status cycle completed,
passed final validation, and was cleared in commit `14798f4`. That plan had no
unstarted or abandoned items, so nothing needed relocation to a backlog. This
file now holds one cycle: repository structure and typed-boundary maintenance,
STRUCT-1 through STRUCT-VALIDATE.

The worktree was clean when this plan was opened. Execute one item per session,
in file order, starting from clean `git status` and committing at each item
boundary. Implementation items stop after focused diff review,
`git diff --check`, backlog maintenance, and their commit. Only
STRUCT-VALIDATE performs full import, replay, runtime, and manual gameplay
validation.

## Scope and settled decisions

This cycle implements five outcomes:

1. Root `AGENTS.md` becomes the sole agent instruction source.
2. A compact module map makes ownership and dependency discovery cheap.
3. The setup lifecycle and player-presentation port become typed. This is a
   bounded migration, not a ban on `Dictionary`: JSON catalogs, serialization,
   event history, and genuinely variable resolver payloads remain dictionaries.
4. The verified-dead legacy runtime and prototypes are removed. Git history is
   their archive.
5. Tracked root/configuration hygiene is repaired. Ignored local files—the
   bundled Godot executable, Blender backups, temporary scenes, builds, and
   `debug/`—remain untouched because normal Git/`rg` discovery already excludes
   them and the executable supports the documented Windows workflow.

No item needs a product or balance decision. A newly discovered live dependency
on a scheduled deletion is blocking: record it and ask whether to migrate or
retain it.

## Conventions

Every item has an explicit minimum **Model**, **Risk**, and behavior it **Adds
to validation coverage**. The executing session must verify its running model
before starting. Every item reviews `BACKLOG_CRITICAL.md`,
`BACKLOG_LONGTERM.md`, and `docs/BACKLOG.md` for stale, completed, or newly
discovered work. Implementation Resolutions become **implemented; pending
end-of-plan validation**; only STRUCT-VALIDATE marks them done.

---

## STRUCT-1 — Establish one instruction authority

**Model:** Sonnet 5 / GPT Terra

**Depends on:** none.

**Risk:** Medium. A stale or missing instruction route can make later agents use
the wrong architecture, validation, or plan-lifecycle rules.

**Adds to validation coverage:** One authoritative instruction file, no
`.agents/AGENTS.md` reference, and no durable document depending on
`implementation_plan.md`.

**End state:** Root `AGENTS.md` is the only operational contract.

### Work

1. Compare both instruction files once more and preserve every applicable rule
   in root `AGENTS.md`; do not retain obsolete duplication.
2. Delete `.agents/AGENTS.md` and the directory if it becomes empty.
3. Point `docs/README.md` and `docs/POLICIES.md` to `../AGENTS.md`.
4. Rewrite the opening of `docs/UI_DESIGN.md` to state durable UI status and
   backlog destinations directly, removing its transient-plan link.
5. Sweep tracked files for alternative instruction files, the old path, and
   persistent plan links. Only root `AGENTS.md` may mention
   `implementation_plan.md` for lifecycle rules.
6. Review all backlogs; add an item only for a verified unresolved tooling
   dependency.

**Files:** `AGENTS.md`, `.agents/AGENTS.md`, `docs/README.md`,
`docs/POLICIES.md`, `docs/UI_DESIGN.md`; backlogs only if necessary.

**Resolution:** Pending.

---

## STRUCT-2 — Add the module and dependency map

**Model:** Opus 5 / GPT Sol

**Depends on:** STRUCT-1.

**Risk:** Medium. An inaccurate or duplicative map increases search cost and can
legitimize accidental dependencies.

**Adds to validation coverage:** Every production area and canonical entry
point is reachable from the docs index, and documented dependency arrows match
source imports after legacy removal.

**End state:** `docs/MODULE_MAP.md` is the short routing guide;
`docs/ARCHITECTURE.md` remains the detailed behavioral source of truth.

### Work

1. Create `docs/MODULE_MAP.md` with one compact row for `data/`, `scenes/`,
   `scripts/`, and each production `src/` directory: responsibility, public
   entry points, allowed dependencies, forbidden dependencies, and owning doc.
2. Include one small dependency diagram: authored data/setup feed the headless
   simulation; systems orchestrate; presentation observes through
   events/adapters.
3. Add a “where to make a change” table for catalog content, combat rules, AI,
   replay/serialization, battle UI, visual effects, setup, scene lifecycle, and
   tooling.
4. Link the map from `docs/README.md` and the layer-boundary section of
   `docs/ARCHITECTURE.md`; remove only genuinely duplicated prose.
5. Audit imports with focused `rg`. Record a descriptive `docs/BACKLOG.md`
   entry for any real out-of-scope violation rather than falsifying the map.

**Files:** new `docs/MODULE_MAP.md`, `docs/README.md`,
`docs/ARCHITECTURE.md`; `docs/BACKLOG.md` only if needed.

**Resolution:** Pending.

---

## STRUCT-3 — Type the setup lifecycle boundary

**Model:** Opus 5 / GPT Sol

**Depends on:** STRUCT-2.

**Risk:** High. Setup construction feeds live play and replay; mistakes can
reject valid rosters, accept invalid maps, or break compatibility.

**Adds to validation coverage:** Valid/invalid configurations cross a typed
validation/factory boundary, both play modes construct normally, and serialized
setup reconstructs without replay-semantic changes.

**End state:** Runtime setup exchanges `BattleSetupConfig`, a typed validation
result, `BattleSimulator`, and `IBattleVisualAdapter`; dictionaries remain at
catalog and `serialize()`/`fromDictionary()` edges.

### Work

1. Add `BattleSetupValidationResult` under `src/battle_sim/` with typed
   `success` and `errors`, plus only the helpers setup needs.
2. Return it from `BattleSetupConfig.validate()`, preserving every check and
   message. Type `fromDictionary(data: Dictionary) -> BattleSetupConfig` and
   preserve old-snapshot defaults.
3. Type
   `BattleSetupFactory.createSimulator(config: BattleSetupConfig, adapterFactory:
   Callable = Callable()) -> BattleSimulator`. Assert a callable result is an
   `IBattleVisualAdapter` before attaching it.
4. Type setup locals and signatures in `BattleReplayRunner` and
   `BattlePresentationController`, including `current_config`,
   `_read_setup_config()`, `_start_battle()`, and adapter-factory return.
5. Update architecture/module docs with the typed flow and deliberate
   dictionary serialization edge.
6. Run a narrow class-registration parse/load probe only if later items cannot
   compile without it; it is not acceptance evidence.
7. Review backlogs. Do not create a vague “type every dictionary” task.

**Files:** new `src/battle_sim/BattleSetupValidationResult.gd` plus UID,
`BattleSetupConfig.gd`, `BattleSetupFactory.gd`, `BattleReplayRunner.gd`,
`src/systems/BattlePresentationController.gd`, `docs/ARCHITECTURE.md`,
`docs/MODULE_MAP.md`; backlogs only if needed.

**Behavior intentionally unchanged:** modes, seed defaults, team size,
map/deployment checks, serialized keys, and replay-version support.

**Resolution:** Pending.

---

## STRUCT-4 — Type the player-turn presentation port

**Model:** Opus 5 / GPT Sol

**Depends on:** STRUCT-3.

**Risk:** High. This boundary controls queue waiting, menu reopening, cursor
ownership, and overlays.

**Adds to validation coverage:** Move-first, act-first, undo, targeting, and pass
use a typed visual port and still wait for drain without stale overlays.

**End state:** `PlayerTurnController` has no untyped adapter or separate
callable/signal surrogates. `GodotVisualAdapter` implements a narrow interactive
contract layered on `IBattleVisualAdapter`; `ConsoleVisualAdapter` remains
non-interactive.

### Work

1. Add `src/presentation/IPlayerTurnVisualAdapter.gd`, extending
   `IBattleVisualAdapter`. It owns `animation_queue_drained` and declares only
   busy state, player/target cursor, target status, movement options, target
   options, release, and overlay clearing.
2. Make `GodotVisualAdapter` extend it and inherit rather than redeclare the
   drain signal.
3. Type `PlayerTurnController._adapter` and its constructor parameter. Remove
   separate `isAnimating` callable and drained-signal parameters; use the port
   directly.
4. Update `BattlePresentationController` construction/lifecycle wiring while
   preserving disposal and disconnection.
5. Document general versus interactive adapters in architecture/module docs.
6. Use only a narrow registration probe if required; defer full flows.
7. Review backlog wording made stale by the typed port.

**Files:** new `src/presentation/IPlayerTurnVisualAdapter.gd` plus UID,
`GodotVisualAdapter.gd`, `PlayerTurnController.gd`,
`BattlePresentationController.gd`, architecture/module docs; backlogs if
needed.

**Behavior intentionally unchanged:** phases, queue pacing, animation order,
cursor/overlay visuals, and battle-event signatures.

**Resolution:** Pending.

---

## STRUCT-5 — Remove legacy runtime and prototypes

**Model:** Opus 5 / GPT Sol

**Depends on:** STRUCT-4.

**Risk:** High. Deletion is Git-recoverable but a missed resource path or UID can
break import or scene loading.

**Adds to validation coverage:** One live battle runtime imports and launches,
no tracked file references removed resources, and the seeded console demo stays
available.

**End state:** `Battle25D.tscn` and the headless simulation are the only battle
implementation; Git history is the old path's archive.

### Work

1. Audit the complete reference closure with `git grep`/`rg`. Any newly found
   live dependency is blocking.
2. Delete `scenes/main.tscn`; `src/systems/BattleMaster.gd`,
   `BattleSample.gd`, `GameBoardVisual.gd`, `Input.gd`, `MainCamera.gd`,
   `Spin.gd`, `SpinOnDemand.gd`; `src/systems/legacy/`; and
   `src/presentation/legacy/`, including tracked UID sidecars.
3. Delete `scenes/prototypes/`, including `BattleSimPrototype` and both inert
   Retro3D shells. Keep `scripts/demo_battle.gd`.
4. Remove rollback/legacy routes from `README.md`, `docs/ARCHITECTURE.md`, and
   `docs/MODULE_MAP.md`.
5. Remove the completed prototype-shell decision from `docs/BACKLOG.md`; sweep
   both other backlogs for stale references.
6. Sweep all tracked source, scenes, config, and docs for every removed path and
   class before staging.

**Files removed:** the exact closure above and its tracked UID sidecars.

**Files updated:** `README.md`, architecture/module docs,
`docs/BACKLOG.md`; other backlogs only if stale.

**Resolution:** Pending.

---

## STRUCT-6 — Repair tracked root/configuration hygiene

**Model:** Sonnet 5 / GPT Terra

**Depends on:** STRUCT-5.

**Risk:** Medium. Bad resource cleanup can break import/export; careless
line-ending normalization can churn the repository.

**Adds to validation coverage:** The icon resolves, orphan root images are not
tracked, tracked root files are intentional, and future authored text stays LF
without mass renormalization.

**End state:** No known broken tracked resource path or orphan root asset.
Ignored local executables, diagnostics, backups, and temporary files remain
preserved and excluded.

### Work

1. Point `project.godot` at
   `res://assets/textures/icon.png`.
2. Recheck tracked references to `pawn.jpg` and `turbosquid.jpg`; if still
   orphaned, delete both and their root `.import` sidecars. Record that Git
   history can recover them.
3. Add focused `.gitattributes`: LF for authored Godot/config/JSON/Markdown/
   shader text and binary treatment for common asset formats. Do not run
   repository-wide renormalization or accept unrelated churn.
4. Review existing ignores for caches, engine executable, Blender backups,
   temporary scenes, builds, and debug output; edit only for a verified gap.
5. Do not move/delete ignored local files. Confirm the Godot executable path in
   `docs/DEVELOPMENT.md` still matches final commands.
6. Review all backlogs; local housekeeping is not durable product work.

**Files:** `project.godot`, new `.gitattributes`; conditional deletion of
`pawn.jpg`, `pawn.jpg.import`, `turbosquid.jpg`,
`turbosquid.jpg.import`; other hygiene/docs/backlog files only if needed.

**Resolution:** Pending.

---

## STRUCT-VALIDATE — Consolidated validation

**Model:** Opus 5 / GPT Sol

**Depends on:** all implementation items.

**Risk:** High. This is the sole proof that the combined documentation, typing,
deletion, and configuration changes still make a playable project.

**Adds to validation coverage:** Instruction discovery, dependency hygiene,
Godot import, setup validation/construction, deterministic replay, CPU play,
interactive player phases, visual queue coordination, new-battle lifecycle, and
resource/icon resolution.

### Preconditions

1. All implementation items are committed and `git status --short` is clean.
2. Verify the assigned model before work.
3. Read every Resolution and build one combined flow.

### Static checks

1. Confirm root `AGENTS.md` is the only tracked instruction file, Markdown
   links resolve, and persistent files have no plan link or STRUCT identifier.
2. Compare the module map with tracked directories, public entry points, and
   dependency searches; confirm no forbidden simulation-to-presentation import.
3. Find zero references to removed paths/classes and confirm
   `scripts/demo_battle.gd` remains.
4. Resolve application `res://` paths, especially the icon, and confirm the
   four orphan image files are untracked.
5. Inspect typed setup/player-port call sites; leave documented serialization,
   catalog, history, and variable-shape dictionaries intact.

### Executable and manual checks

1. Run the bounded Godot 4.4 headless `--editor --quit` import/parse probe from
   the repository root with `--path .`, `gl_compatibility`, and dummy audio.
2. Run `scripts/demo_battle.gd` through a waited headless process and require
   its explicit `Battle complete!` marker.
3. Exercise fixed-seed setup serialize/reconstruct/replay; compare resulting
   deterministic state/history.
4. Launch `Battle25D.tscn` in a real window. Cover CPU vs CPU start,
   pause/resume, playback, and return to setup/new battle.
5. In Player vs CPU, cover both phase orders, undo, basic and spell targeting,
   pass, drain-before-menu behavior, and cursor/overlay cleanup.
6. Confirm logs have no missing icon or removed-resource warning.

### Completion and plan lifecycle

1. Fix defects in this session and rerun only relevant consolidated checks and
   the affected integrated flow.
2. Reconcile all three backlogs.
3. Run `git diff --check`, inspect/stage only validation-owned changes, and
   commit fixes/evidence.
4. Mark covered Resolutions done, then sweep tracked files for STRUCT identifiers
   and rewrite any outside this file as durable descriptions.
5. Move any genuinely open item to the correct backlog and name it to the user.
6. Clear all contents of `implementation_plan.md` in this session and commit
   that deletion. Recover the plan with
   `git show <validation-ref>:implementation_plan.md`.

**Resolution:** Pending.
