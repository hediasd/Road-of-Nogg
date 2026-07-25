# Battle Runtime Stabilization and Migration Plan

Status: approved on 2026-07-24.

Architectural decision: `BattleSimulator` is the canonical battle runtime. The
older `BattleMaster` stack remains available only as a temporary rollback path
until the migration is verified.

## Delivery phases

### 0. Clean baseline

- Preserve the existing GUT installation, local test runners, and ambiguous
  reference images in a recovery commit.
- Ignore generated diagnostics and test reports.
- Require a clean working tree before implementation starts.

Exit: all pre-existing work is committed and recoverable.

### 1. Godot crash isolation

- Reproduce the Godot 4.4 native crash without disturbing the active editor.
- Compare project, headless, GUT, renderer, cache, and minimal-project cases.
- Use a shadow project for destructive-cache and startup diagnostics.
- Record the cause or reliable workaround in `docs/LEARNINGS.md`.

Exit: a repeatable noninteractive Godot command starts and exits without an
application-error dialog.

### 2. Automated test consolidation

- Repair GUT lifecycle and process exit-code propagation.
- Resolve the `moveMonster()` / `moveMonsterTo()` contract mismatch.
- Cover seeded determinism, movement and occupancy, line of sight, elemental
  damage, turn/status progression, battle termination, and serialization.
- Keep reports outside tracked source state.

Exit: the test command is windowless, terminates reliably, reports zero
failures, and returns nonzero when a test fails.

### 3. Canonical runtime boundary

- Document the responsibilities and migration boundary of the old and new
  battle stacks.
- Inventory legacy behavior still missing from `BattleSimulator`.
- Mark the legacy runtime explicitly; do not delete it until migration parity is
  verified.

Exit: one authoritative state and turn loop exists, and no scene is ambiguously
connected to both runtimes.

### 4. Default-scene integration

- Add a presentation controller under `src/systems/`.
- Construct and configure `BattleSimulator` from the presentation layer.
- Route visuals through `BattleEvents` and `IBattleVisualAdapter`.
- Retain the old scene as a temporary rollback entry point.

Exit: the default launch path uses `BattleSimulator`, presentation code never
mutates simulation state directly, and identical seeds produce identical
results across adapters.

### 5. Architectural boundary restoration

- Move camera, Godot adapter, and visual test/prototype classes out of
  `src/battle_sim/`.
- Audit pure-logic folders for engine-node inheritance, visual dependencies,
  instance IDs, global RNG calls, and resolver-bypassing state mutation.
- Update paths and architecture documentation.

Exit: simulation folders contain only headless data and logic.

### 6. Oversized-script refactoring

- Refactor in this order: `CombatResolver.gd`, `EntityBrain.gd`,
  `GodotVisualAdapter.gd`, `ConsoleVisualAdapter.gd`, and
  `GodotVisualTest.gd`.
- Preserve public contracts and verify between extractions.
- Keep gameplay content data-driven.

Exit: core scripts satisfy the 300-line scout rule or have an explicit,
documented exception.

### 7. Determinism and replay hardening

- Route every random decision through `BattleState.rng`.
- Define, store, and serialize battle seeds and deterministic `uniqueID`
  allocation.
- Verify that identical seeds and inputs produce identical event histories.
- Decouple diagnostic file output from turn execution.

Exit: a saved battle contains everything needed to continue or replay it.

### 8. Documentation and repository cleanup

- Reconcile architecture, project structure, class names, test instructions,
  Godot versions, and Markdown encoding.
- Decide how the bundled Godot executable is distributed.
- Ensure launch and test runs leave `git status` clean.

Exit: a new contributor can identify the main scene, simulation entry point,
and verification command from the README.

## Commit sequence

1. Baseline and ignore rules.
2. Crash diagnosis and workaround.
3. Test harness repairs.
4. Canonical-runtime architecture decision.
5. Main-scene integration.
6. Visual-file relocation.
7. Resolver and AI refactors.
8. Determinism and replay coverage.
9. Documentation cleanup.
