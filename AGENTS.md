# Agent Working Policy — Road of Nogg

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
- Treat shared presentation textures, materials, factories, and theme tokens as
  compatibility surfaces. Spell- or screen-specific tuning must use an owned
  variant rather than redefining a neutral/shared primitive in place. If a
  shared surface intentionally changes, enumerate every caller and include all
  of them in the final validation scope.

## Documentation routing

- Start at `docs/README.md`.
- Consult `docs/POLICIES.md` before architectural or workflow changes.
- Consult `docs/ARCHITECTURE.md` before changing runtime ownership or data flow.
- Consult `docs/GAME_DESIGN.md` before changing confirmed gameplay rules.
- Consult `docs/LEARNINGS.md` when its "When to consult" table matches the task.
  Add only durable, verified findings with a clear reuse trigger.
- Keep game references maintainable: the master index owns the roster; aspect
  files cover relevant examples and cite external technical claims.

## Progress updates

- While work is ongoing, keep the user informed with a concise progress update
  at least every 15 seconds. Configure long-running commands to yield within
  that interval when possible; otherwise update at the first tool boundary.
- Skip redundant updates when the work completes within 15 seconds.

## Implementation plans

- Every plan item must carry an explicit model assignment, drawn from exactly
  two tiers: **Sonnet 5 / GPT Terra** for single-file mechanical work and for
  multi-file work with a stated end state; **Opus 5 / GPT Sol** for
  architectural boundaries, extraction, and balance or design decisions.
  Assign per item, never per phase. Do not route work below the Sonnet 5 /
  GPT Terra tier — smaller models are not used on this project.
- Claude-family models, including Sonnet and Opus, may not design, generate,
  author, or materially edit visual effects unless the user explicitly approves
  Claude for that specific work and the plan item records that approval. This
  includes shaders, particles, effect scenes or scripts, and visual tuning.
  Assign VFX creation to GPT by default; Claude may inspect, diagnose, review,
  or validate it without changing it.
- Every implementation item names its risk and the behavior its change adds to
  final validation coverage. A multi-item plan ends with one validation item
  that depends on every implementation item, has its own model assignment, and
  consolidates the full manual gameplay and integration checks.
- Mark items that require a user decision as blocking, and say so plainly rather
  than proceeding on an assumption.
- Where a fix legitimately changes a passing check's reported numbers, say so in
  the item, so an executing agent does not try to restore the old values.
- Plans are delegation contracts executed by other models. One item per session,
  starting from a clean `git status`.

## Plan file lifecycle

`implementation_plan.md` holds **one plan at a time** — the cycle currently
being executed, and nothing else.

- After final validation passes, move genuinely open items to the appropriate
  backlog and name them to the user, then clear the entire plan in the same
  session. Do not retain completed items or append a new cycle; committed plans
  remain recoverable with `git show <ref>:implementation_plan.md`.
- A fresh plan opens with a dated one-paragraph preamble recording what the
  previous contents were and what happened to the still-open items, so the
  reset is auditable from the file alone.

### Nothing persistent may cite a plan item

Because `implementation_plan.md` is transitory, no persistent file — including
documentation, backlogs, source comments, or commit messages — may name a plan
item or link to the plan for required detail. Describe the work itself instead.
Plan items may cite persistent files. Before clearing a cycle, grep for its item
identifiers and rewrite any external reference as a durable description.

## Executing a plan item

- **Note the model fit before starting.** Compare the item's **Model** field to
  the model actually running. If the running model is more capable than the
  item needs, say so in one line — this is a cost signal for the user to act on
  if they choose, not a gate — and continue. A model-family restriction is a
  gate: reassign the item or obtain the required approval before editing.
- Commit at every item boundary. Item state belongs in the plan's Resolution
  notes and in `git log`, not in conversation history; a fresh session must be
  able to continue from those two sources alone.
- An implementation item's Resolution is **implemented; pending end-of-plan
  validation**. Only the final validation item changes covered items to done and
  claims the plan complete.
- Do not launch the game, replay the full demo, or repeat manual acceptance flows
  after each implementation item. A narrow compile/load probe is allowed only
  when later items cannot safely build on potentially unusable code; record it
  as an intermediate smoke check, not acceptance evidence.
- Cheap local integrity checks remain appropriate at an item boundary: inspect
  the focused diff, run `git diff --check`, and confirm only task-owned files
  are staged.
- Read narrowly. Locate with a content search, then read a bounded range. Read a
  file end to end only when editing throughout it.

## Running the checks

There is no automated test suite, check runner, or git hooks. Verify changes by
launching the game manually and exercising the affected behavior; follow the
Windows safeguards in `docs/DEVELOPMENT.md`.

- For a multi-item plan, perform full validation once in the final validation
  item, after every implementation item is committed. Exercise the union of the
  plan's affected behaviors and reuse one integrated flow where it covers
  several items.
- If final validation finds a defect, fix it in that validation session, rerun
  the relevant consolidated checks, and record the fix and evidence in the
  plan. Do not reopen every prior item merely to repeat the same validation.
- A single-item plan validates at the end of that item because there is no
  repeated per-item validation to avoid.
- VFX work that changes a shared primitive or factory must render every effect
  returned by a caller search, not only the commissioned effect. Compare stored
  goldens where they exist; a target-effect capture alone cannot complete the
  validation.

## Backlog maintenance

- Use `BACKLOG_CRITICAL.md` for incomplete work that materially affects current
  gameplay, correctness, or user-facing readiness and should be fixed promptly.
- Use `BACKLOG_LONGTERM.md` for deferred design, tooling, and maintenance work.
- Add a backlog item only when it is actionable, durable, and out of current
  scope. Do not use the backlog as a stream of incidental ideas.
- During implementation, reconcile relevant backlog entries: add newly
  discovered unresolved work, remove completed entries, and move work whose
  urgency changes.
- Do not leave duplicated, stale, or already-completed backlog entries.
