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

## How this repository is worked

One person owns this repository, and several agent sessions — Claude Code and
others — edit the same working tree at the same time. There are no external
contributors and no merges to defend against. Every rule below exists to stop
concurrent sessions from overwriting each other, which is the only real hazard.

- **Work directly on `main`, in the one working tree. Do not create a branch,
  and do not ask to.** This overrides the general habit of branching before
  committing. Safety comes from commit shape and path ownership, not from
  branches — see "Rolling back".
- **A dirty `git status` is the normal state.** Other sessions have work in
  flight. It is never a reason to pause, ask, clean, or delay your own commit.
  Do not report on it, do not tidy it, do not wait for it.
- **You own only the paths your item's `Touches` list names.** Everything else
  in the tree belongs to a session you cannot see. Read anything; write only
  what you own.
- **Stage by explicit path, every time.** New files first, then commit the same
  list — a pathspec commit cannot pick up an untracked file on its own:

  ```
  git add <new path> <new path>
  git commit -m "…" -- <every path this item owns>
  ```

  `git add -A`, `git add .`, `git add -u`, `git commit -a`, and committing
  whatever happens to be in the index are forbidden here — each one silently
  commits another session's half-finished work under your message. The pathspec
  on `commit` is what keeps a pre-staged index belonging to someone else out of
  your commit.
- **These destroy concurrent work and are forbidden unless the user names them
  in the current request:** `git stash`, `git reset --hard`, `git clean`,
  `git checkout -- .`, and any `git restore`/`git checkout` without a pathspec.
  To undo your own edit, name your own paths:
  `git restore --source=HEAD -- <your path>`.
- **Only one session may launch the game at a time**, and the tree it launches
  carries every other session's in-flight edits. See "Running the checks".
- A branch and a worktree are for exactly one case: work that may need to be
  abandoned wholesale. Say so and get the user's go-ahead before creating one.

## Working safely

- Use a written plan when risk or scope benefits from one, especially for
  cross-layer changes. A file count alone does not require a plan.
- Ask before making creative or lore decisions and before materially expanding
  scope. Resolve ordinary technical details from repository evidence.
- Fail loudly on critical state desynchronization. Review large or deeply
  nested code for extraction, but do not stop solely at a numeric threshold.
- Treat every existing VFX and animation, plus shared presentation textures,
  materials, factories, helper methods, timelines, and theme tokens, as a
  compatibility surface. New work may inspect an existing effect and may copy
  a structural sibling, but it must edit only the new effect's owned copy. Do
  not retune, generalize, extract, parameterize, or otherwise change donor or
  shared behavior to make the new animation work. A shared-contract migration
  is separate, explicitly scoped work: enumerate every caller and prove that
  their appearance, timing, playback, and lifecycle remain unchanged.

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

A plan lives in `docs/plans/<cycle-slug>.md`. Several cycles may be active at
once — they are independent, and a session touches exactly one.
`docs/plans/README.md` carries the item and wave template.

There is no `implementation_plan.md` at the repository root. It held one cycle
at a time under the previous contract and was removed when the Second Window
Skin cycle closed; do not recreate it.

**A cycle file is frozen the moment execution starts.** No executing session
edits it, ever. Everything execution produces lives in commits. This is what
makes several sessions safe at once: there is no shared mutable file for them
to collide in.

Each item carries:

- **Model** and **Model rationale**, drawn from exactly two tiers: **Sonnet 5 /
  GPT Terra** for single-file mechanical work and for multi-file work with a
  stated end state; **Opus 5 / GPT Sol** for architectural boundaries,
  extraction, and balance or design decisions. The rationale must connect
  concrete properties of that item — scope, ambiguity, boundary impact,
  judgment, risk — to the selected tier; restating the label is insufficient.
  Assign per item, never per phase. Never route below Sonnet 5 / GPT Terra.
- **Depends on** — the items whose commits must exist first.
- **Touches** — every path or glob the item may write, documentation included.
  This list is the item's exclusive claim while it runs, so it must be
  complete. An item that cannot state its full write set is not ready to
  dispatch.
- **End state**, **Implementation**, **Risk**, and **Adds to final validation**.

A multi-item plan ends with one validation item that depends on every
implementation item, has its own model assignment, and consolidates the full
manual gameplay and integration checks.

Mark items that require a user decision as blocking, and say so plainly rather
than proceeding on an assumption. Where a fix legitimately changes a passing
check's reported numbers, say so in the item, so an executing agent does not
try to restore the old values.

## Waves — running several items at once

A cycle file ends with a wave table. Each wave names the items that may run
simultaneously, in separate sessions.

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | SKIN-1 | — |
| 2 | SKIN-4, SKIN-5 | catalog vs. builder; no shared path |

A wave is legal only when every item's dependencies are already committed and
the items' **Touches** lists are pairwise disjoint. Authoring the wave table is
the plan author's job, and it is the point where conflicts are designed out.

- The user dispatches a wave by opening one session per item and naming it.
- Before your first edit, confirm your item's work fits inside its Touches
  list. If it cannot be done without writing a path another item in the same
  wave claims, **stop and say so** — the wave is mis-authored, which is a
  one-line fix at plan level, not something to work around.
- One session may take a **lane**: several items that are dependency-consecutive
  and share a Touches list. Prefer this to splitting related work across
  sessions — it removes a conflict surface and re-reads the context once. Still
  one commit per item.
- The final validation item is always alone in its own wave.

## Recording what an item found

**One commit per item, and its message body is the durable record.** Write the
finding once, there. Do not also write it into the cycle file, a resolution
note, or a status table — the plan is frozen and there is nothing else to
update.

- The body states what was implemented, what the plan assumed that turned out
  to be false, what was deliberately not done and why, and any evidence.
- The last trailer line is `Plan-Item: <ITEM-ID>`.
- An implementation item's status is **implemented; pending end-of-plan
  validation** until the validation item's commit exists.

A fresh session resumes a cycle from the cycle file plus:

```
git log --grep="Plan-Item: <CYCLE-PREFIX>" --format="%h %s"
git log --grep="Plan-Item: SKIN-4" -1
```

Nothing outside `docs/plans/` may cite an item identifier for required detail —
not documentation, backlogs, or source comments — because cycle files are
deleted when the cycle closes. Describe the work itself instead. The
`Plan-Item:` commit trailer is the one exception: it is a grouping key, and the
commit's subject and body must still stand alone without it.

## Rolling back

Safety on `main` comes from commit shape, not from branches.

- Undo one item: `git revert <sha>`. Because items own disjoint paths,
  reverting an earlier item does not conflict with later ones.
- Undo a wave: revert its commits newest-first.
- A cycle's full footprint is `git log --grep="Plan-Item: <PREFIX>"`; diff its
  first commit's parent against `HEAD` to see everything it changed.
- Push `main` to `origin` at every wave boundary. `origin/main` is the durable
  recovery point if the local tree becomes unrecoverable.
- If `git revert` refuses or conflicts because another session holds
  uncommitted edits in the same paths, stop and tell the user. Do not force it.
- Work that may need abandoning wholesale is the one case for a branch and
  worktree — propose it before starting, not after.

## Plan lifecycle

- Opening a cycle: a new file in `docs/plans/`, beginning with a dated
  one-paragraph preamble stating what the cycle is for.
- Closing a cycle: after final validation passes, move genuinely open items to
  the appropriate backlog, name them to the user, and delete the cycle file in
  the same commit. It stays recoverable with `git show <ref>:<path>`.
- Do not append a new cycle to a finished file, and do not retain completed
  items in it.

## Running the checks

There is no automated test suite, check runner, or git hooks. Verify changes by
launching the game manually and exercising the affected behavior; follow the
Windows safeguards in `docs/DEVELOPMENT.md`.

**The tree you launch contains every concurrent session's in-flight edits.**
That has consequences:

- Do not launch the game during a wave. A narrow compile/load probe is allowed
  when later items cannot safely build on potentially unusable code; record it
  as an intermediate smoke check, not acceptance evidence.
- If a probe fails in a path you do not own, report it in one line and continue
  your own item. Do not fix it — it is another session's work mid-flight.
- Full validation runs in the final validation item, alone, after every
  implementation item in the cycle is committed and no other session is
  editing. Exercise the union of the plan's affected behaviors and reuse one
  integrated flow where it covers several items.
- If final validation finds a defect, fix it in that session, rerun the
  relevant consolidated checks, and record both in that item's commit. Do not
  reopen every prior item to repeat the same validation.
- A single-item plan validates at the end of that item.

At an item boundary, cheap local integrity checks stay appropriate: inspect
your own focused diff with `git diff HEAD -- <your paths>`, run
`git diff --check`, and confirm the paths you are about to name are the paths
your item owns.

New VFX or animation work must render the donor and every existing caller of
any dependency it reuses. Compare stored goldens where they exist. Any change
to an existing effect's appearance, timing, playback, or lifecycle fails the
item; move the tuning into the new effect's owned code or resources. A caller
sweep is a regression gate, not permission to edit shared behavior.

Read narrowly throughout. Locate with a content search, then read a bounded
range. Read a file end to end only when editing throughout it.

## Backlog maintenance

- Use `BACKLOG_CRITICAL.md` for incomplete work that materially affects current
  gameplay, correctness, or user-facing readiness and should be fixed promptly.
- Use `BACKLOG_LONGTERM.md` for deferred design, tooling, and maintenance work.
- Add a backlog item only when it is actionable, durable, and out of current
  scope. Do not use the backlog as a stream of incidental ideas.
- During implementation, **append only**, and commit the backlog file by
  explicit path immediately. Rewriting, reordering, or pruning a backlog is a
  whole-file edit: do it only when your item's Touches list claims that file,
  or at a wave boundary when nothing else is running.
- Do not leave duplicated, stale, or already-completed backlog entries.
