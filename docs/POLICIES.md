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

- Inspect the working tree before substantial work and preserve changes not
  created by the current task.
- Use a written plan when coordination, rollback risk, or architectural impact
  warrants one. Small and well-bounded changes can proceed directly even when
  they touch several files.
- Keep generated diagnostics out of tracked source. Put reusable utilities in
  `scripts/`.
- Keep commits reviewable and stage only task-owned files. Pushing is a user or
  release decision, not a mandatory prerequisite for local work.
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
For a multi-item implementation plan, record each implementation item as
**implemented; pending end-of-plan validation** and exercise the combined
affected behavior once in the plan's final validation item. A single-item plan
validates at the end of that item. See [`DEVELOPMENT.md`](./DEVELOPMENT.md) for
the executable workflow and Windows safeguards. Do not claim the plan complete
until that final manual validation has run.

Shared presentation resources are compatibility surfaces: their verification
scope is the complete caller set, not the feature that motivated the edit.
Prefer an owned variant for local visual tuning. For VFX-specific ownership and
donor-capture rules, see [`VFX_DESIGN.md`](./VFX_DESIGN.md).
