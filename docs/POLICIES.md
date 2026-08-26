# Road of Nogg Development Policies

Status: current. Last reconciled: 2026-08-12.

This document explains the project’s engineering guardrails. The concise rules
for agents are in [`AGENTS.md`](../AGENTS.md); current commands
and troubleshooting live in [`DEVELOPMENT.md`](./DEVELOPMENT.md).

## Decision authority

- Ask the user before inventing names, lore, narrative, factions, visual themes,
  or balance values that are not already specified.
- Ask before destructive actions, material scope expansion, or a choice that
  would make two plausible product directions meaningfully different.
- Use repository evidence and reversible implementation judgment for ordinary
  technical details. Ambiguity alone is not a reason to stop.
- The Lorekeeper persona or subagent may edit only lore documents such as
  `docs/LORE.md` and files under `docs/lore/`, never code or non-lore
  documentation, even if requested.

## Runtime boundaries

- `BattleSimulator` is the canonical battle runtime and `BattleState` is the
  authoritative state container.
- Simulation code in `src/battle_sim/`, `src/algorithms/`, `src/board/`,
  `src/entities/`, `src/entity_ai/`, and `src/factories/` stays headless. Godot
  data types are acceptable; visual nodes and presentation dependencies are not.
- Presentation subscribes through `BattleEvents` or implements
  `IBattleVisualAdapter`. It must not directly mutate simulation state.
- State changes flow through the simulator and dedicated resolvers. Base
  reference data is read-only; transient effects belong to battle state.
- Gameplay identity uses deterministic `uniqueID` values rather than engine
  instance IDs.
- Gameplay randomness uses the seeded `RandomNumberGenerator` owned by
  `BattleState`; global `randi()` and `randf()` are prohibited in simulation.
- New content is data consumed by general resolvers. Prefer composition,
  strategies, and tables over content-specific conditionals or inheritance
  introduced only to avoid a small amount of duplication.

## Godot and code quality

- Target Godot 4.4. Prefer explicit types at boundaries and wherever they make
  contracts clearer.
- Use `PascalCase` for classes and enums, `camelCase` for functions and
  variables, and `UPPER_SNAKE_CASE` for constants.
- Fail loudly with `assert()` or `push_error()` when internal state is invalid.
  Expected user input failures should return useful validation results.
- Connections owned by the same scene-tree lifetime may rely on that lifetime.
  Cross-lifetime or repeatedly created connections need one-shot behavior or an
  explicit disconnect path.
- Document non-obvious invariants and reasons. Do not add comments that merely
  restate code.
- Treat long files and deep nesting as review signals. Extract code when doing
  so improves ownership, testing, or readability; numeric thresholds are not
  automatic blockers.

## Workflow and repository safety

This repository has one human owner and several agent sessions working in it
concurrently, on `main`, in a single working tree. That shape is deliberate,
and it changes what "safety" means here.

**Branches were not buying safety; they were buying conflicts.** Because the
same person drives every session, a branch per session produced merges between
sessions that were never in genuine disagreement — most conflicts were in
bookkeeping files rather than in code. Working on `main` removes the merge
entirely. What replaces it:

- **Path ownership.** A plan item declares the paths it may write, and two
  items run concurrently only when those sets are disjoint. Disjointness is
  what prevents a lost update; it is designed into the plan's wave table rather
  than discovered at merge time.
- **Commit shape as the rollback unit.** One item, one commit, disjoint paths,
  tagged with a `Plan-Item:` trailer. `git revert` on such a commit is a clean
  undo that later items do not fight, which is the property a branch was
  supposed to provide.
- **Explicit-path staging.** In a shared tree the index is shared too, so
  `git add -A` and `git commit -a` will capture another session's unfinished
  work. Commits name their paths.
- **A dirty tree carries no information.** It reflects other sessions, so
  pausing on it, reporting it, or cleaning it is friction with no safety value.
  Destructive whole-tree commands (`stash`, `reset --hard`, `clean`, pathspec-
  less `restore`) are correspondingly dangerous and are user-invoked only.

Beyond that:

- Use a written plan when coordination, rollback risk, or architectural impact
  warrants one. Small and well-bounded changes can proceed directly even when
  they touch several files.
- Keep generated diagnostics out of tracked source. Put reusable utilities in
  `scripts/`.
- Keep commits reviewable. Push `main` at wave boundaries so `origin/main`
  stays a usable recovery point.
- For complex UI, create a mockup when visual direction is genuinely undecided
  or the user asks for one. A mockup is not required for every `Control` tree.

## Documentation ownership

- [`README.md`](../README.md): contributor entry point and common checks.
- [`ARCHITECTURE.md`](./ARCHITECTURE.md): current runtime ownership, data flow,
  and the first-playable setup/player-control contract.
- [`GAME_DESIGN.md`](./GAME_DESIGN.md): confirmed player-facing rules.
- [`BACKLOG_CRITICAL.md`](../BACKLOG_CRITICAL.md): urgent gameplay, correctness,
  and readiness work outside current scope.
- [`BACKLOG_LONGTERM.md`](../BACKLOG_LONGTERM.md): deferred design, tooling, and
  maintenance work.
- [`LEARNINGS.md`](./LEARNINGS.md): verified reusable discoveries, not session history.
- [`DEVELOPMENT.md`](./DEVELOPMENT.md): executable commands and environment safeguards.
- [`plans/`](./plans/): one file per active implementation cycle, frozen once
  execution starts and deleted when the cycle closes. Execution state lives in
  commit messages, not here — see `AGENTS.md`, "Recording what an item found".

Update the owning document when its truth changes. Do not repeat entire rules
across several files. Add a backlog item only when it has a clear outcome and
is not being completed in the current task.

## Game-reference research

[`gamerefs/tactical_rpg_turn_systems.md`](../gamerefs/tactical_rpg_turn_systems.md)
owns the reference roster and links to aspect studies. Aspect files should:

- cover only examples relevant to the aspect rather than reproducing the whole
  roster as a checklist;
- distinguish sourced fact, interpretation, and Road of Nogg recommendation;
- cite an external source for specific technical claims;
- end with concrete implementation takeaways or state that no decision exists.

## Risk-based verification

There is no automated test suite or check runner in this repository right now;
the previous suite, GUT, and their runners were removed to be rebuilt fresh.
For a multi-item implementation plan, each implementation item is
**implemented; pending end-of-plan validation**, and the combined affected
behavior is exercised once in the plan's final validation item. A single-item
plan validates at the end of that item. See [`DEVELOPMENT.md`](./DEVELOPMENT.md)
for the executable workflow and Windows safeguards. Do not claim the plan
complete until that final manual validation has run.

Concurrency makes this stricter rather than looser. Manual validation observes
the whole working tree, so a launch during a wave renders other sessions'
half-finished work alongside the item under test, and any conclusion drawn from
it is unsound in both directions — a failure may not be yours, and a pass may
depend on something about to change. Final validation therefore runs alone, in
a quiet tree, after every implementation item is committed. During a wave, an
agent that hits a failure outside its own paths reports it and keeps going; it
does not repair another session's work in progress.

Existing VFX and animations are read-only references while authoring a new one.
Study them freely to preserve the project's visual language, but copy any
borrowed implementation into new, explicitly owned code before changing it.
Do not make a new animation work by modifying, extracting, parameterizing, or
retuning an existing animation's methods, timeline, resources, or shared
helpers. Duplication is preferable to coupling unrelated effects through a
premature abstraction.

Shared presentation code and resources are compatibility surfaces. A new visual
feature must leave every existing caller's appearance, timing, playback, and
lifecycle unchanged. If the shared contract itself genuinely needs revision,
handle that as separately scoped compatibility work, enumerate the complete
caller set, and validate every caller. That caller sweep is a regression gate,
not permission to let feature-specific tuning leak into shared behavior. For
VFX-specific ownership and donor-capture rules, see
[`VFX_DESIGN.md`](./VFX_DESIGN.md).
