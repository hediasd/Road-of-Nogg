# Project Instructions — Road of Nogg

These instructions govern work in this repository. `docs/POLICIES.md` explains
the rationale; this file is the concise operational contract.

## Architecture

- Keep `src/battle_sim/`, `src/algorithms/`, `src/board/`, `src/entities/`,
  `src/entity_ai/`, and `src/factories/` headless. They may use Godot data
  types, but must not inherit visual/tree nodes or depend on presentation code.
- `BattleSimulator` and `BattleState` are the canonical runtime and state.
- Presentation observes simulation through `BattleEvents` or
  `IBattleVisualAdapter`; it never mutates battle state directly.
- Use deterministic `uniqueID` values, never `get_instance_id()`, for gameplay
  identity. Route gameplay randomness through `BattleState.rng`.
- Express content as data handled by general resolvers. Prefer composition and
  small strategies over content-specific branches or unnecessary inheritance.
- Target Godot 4.4 and use typed GDScript where it improves correctness.

## Working safely

- Inspect `git status` before substantial work. Preserve changes you do not own;
  never clean, overwrite, commit, or stash them without authorization.
- Use a written plan when risk or scope benefits from one, especially for
  cross-layer changes. A file count alone does not require a plan.
- Ask before making creative or lore decisions and before materially expanding
  scope. Resolve ordinary technical details from repository evidence.
- Fail loudly on critical state desynchronization. Review large or deeply
  nested code for extraction, but do not stop solely at a numeric threshold.
- Keep commits focused. Stage only files that belong to the current task.

## Documentation routing

- Start at `docs/README.md`.
- Consult `docs/POLICIES.md` before architectural or workflow changes.
- Consult `docs/ARCHITECTURE.md` before changing runtime ownership or data flow.
- Consult `docs/GAME_DESIGN.md` before changing confirmed gameplay rules.
- Consult `docs/LEARNINGS.md` when its “When to consult” table matches the task.
  Add only durable, verified findings with a clear reuse trigger.
- Add backlog items only when they are actionable, durable, and out of current
  scope. Do not use the backlog as a stream of incidental ideas.
- Keep game references maintainable: the master index owns the roster; aspect
  files cover relevant examples and cite external technical claims.

## Verification

There is no automated test suite or check runner in this repository right now;
the previous suite and its runners were removed to be rebuilt fresh. Verify
changes by launching the game manually and exercising the affected behavior —
see the Windows safeguards in `docs/DEVELOPMENT.md`. Do not claim completion
without having actually exercised the affected behavior.
