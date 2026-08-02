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
  at least every 15 seconds.
- Configure long-running commands to yield within 15 seconds whenever the tool
  supports bounded output.
- If a command cannot yield while running, send the update at the first
  available tool boundary.
- Do not send redundant progress messages when the requested work completes
  within 15 seconds.

## Implementation plans

- Every plan item must carry an explicit model assignment, drawn from exactly
  two tiers: **Sonnet 5 / GPT Terra** for single-file mechanical work and for
  multi-file work with a stated end state; **Opus 5 / GPT Sol** for
  architectural boundaries, extraction, and balance or design decisions.
  Assign per item, never per phase. Do not route work below the Sonnet 5 /
  GPT Terra tier — smaller models are not used on this project.
- Every implementation item names its risk and the behavior its change adds to
  the plan's final validation coverage. Consolidate and deduplicate the actual
  validation commands in the final validation item instead of rerunning them
  after every implementation item.
- Every multi-item implementation plan ends with an explicit validation item
  that depends on all implementation items. Assign that item its own model
  according to scope. It is the only item that performs the plan's full manual
  gameplay and integration validation.
- Mark items that require a user decision as blocking, and say so plainly rather
  than proceeding on an assumption.
- Where a fix legitimately changes a passing check's reported numbers, say so in
  the item, so an executing agent does not try to restore the old values.
- Plans are delegation contracts executed by other models. One item per session,
  starting from a clean `git status`.

## Plan file lifecycle

`implementation_plan.md` holds **one plan at a time** — the cycle currently
being executed, and nothing else.

- When a plan's final validation item passes and the plan is complete, delete
  the file's entire contents in the same session. Do not append the next plan
  underneath the finished one, and do not keep resolution logs, decision
  records, or completed items "for reference". `git log` and `git show` are the
  history; the plan file is the working contract.
- Before deleting, move any item that is still genuinely open — never started,
  or started and abandoned — into `BACKLOG_CRITICAL.md` or
  `BACKLOG_LONGTERM.md` per the backlog rules below. Name those items
  explicitly to the user rather than relocating them silently, so a deliberate
  drop is distinguishable from an oversight.
- Deleting the file is safe precisely because it is committed: recover any
  prior contents with `git show <ref>:implementation_plan.md`. Say so when
  reporting the deletion.
- A fresh plan opens with a dated one-paragraph preamble recording what the
  previous contents were and what happened to the still-open items, so the
  reset is auditable from the file alone.
- Never let the file accumulate more than one cycle. A plan file carrying
  finished work makes the next executing agent read hundreds of lines of
  settled history to find its one item, which is exactly the cost this rule
  exists to remove.

### Nothing persistent may cite a plan item

`implementation_plan.md` is transitory. Its short-lived item labels live and
die with a single cycle, so a
reference to one from a file that outlives the cycle is a dangling pointer the
moment the plan is reset.

- **No file outside `implementation_plan.md` may name a plan item.** That
  covers `docs/`, `BACKLOG_CRITICAL.md`, `BACKLOG_LONGTERM.md`, `README`s,
  source comments, and commit messages. Nothing is exempt, including a plan
  item that is currently open.
- Describe the work instead of citing it. "Corrected once the body font size
  was settled" is durable; "Tracked in the current plan" becomes a
  statement of what is actually missing. The description survives the reset;
  the identifier does not.
- Do not link to `implementation_plan.md` as a destination for detail either.
  A persistent doc may note that open build work is tracked there and that the
  file is reset per cycle, but must not depend on its contents to be
  understood.
- Plan items may freely cite persistent files — `docs/UI_DESIGN.md` §8,
  `BACKLOG_CRITICAL.md`, source paths. The dependency runs one way only, from
  the transitory file to the durable ones.
- When closing out a cycle, grep for the cycle's identifiers across the repo
  before deleting the plan, and rewrite any hit as a description.

## Executing a plan item

- **Check the model before starting.** Compare the item's **Model** field to the
  model actually running. If the running model is more capable than the item
  needs, say so and stop rather than executing it — routing that is only ever
  written and never checked at execution time costs real money for no benefit.
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

There is no automated test suite, check runner, or git hooks in this
repository right now; the previous suite and its runners were removed to be
rebuilt fresh. Verify changes by launching the game manually and exercising
the affected behavior — see the Windows safeguards in `docs/DEVELOPMENT.md`.
Do not claim completion without having actually exercised the affected
behavior.

- For a multi-item plan, perform full validation once in the final validation
  item, after every implementation item is committed. Exercise the union of the
  plan's affected behaviors and reuse one integrated flow where it covers
  several items.
- If final validation finds a defect, fix it in that validation session, rerun
  the relevant consolidated checks, and record the fix and evidence in the
  plan. Do not reopen every prior item merely to repeat the same validation.
- Do not claim the plan complete until the final validation item has actually
  launched the game and exercised the affected behavior.
- A single-item plan validates at the end of that item because there is no
  repeated per-item validation to avoid.

## Backlog maintenance

- Use `BACKLOG_CRITICAL.md` for incomplete work that materially affects current
  gameplay, correctness, or user-facing readiness and should be fixed promptly.
- Use `BACKLOG_LONGTERM.md` for deferred design, tooling, and maintenance work.
- Add a backlog item only when it is actionable, durable, and out of current
  scope. Do not use the backlog as a stream of incidental ideas.
- During every implementation task, update the relevant backlog files: add newly
  discovered unresolved work, remove completed entries, and move entries between
  the files when their urgency changes.
- Do not leave duplicated, stale, or already-completed backlog entries.
