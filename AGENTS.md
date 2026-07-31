# Agent Working Policy

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

There is no automated test suite or git hooks in this repository right now;
the previous suite and hooks were removed to be rebuilt fresh.

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
- During every implementation task, update the relevant backlog files: add newly
  discovered unresolved work, remove completed entries, and move entries between
  the files when their urgency changes.
- Do not leave duplicated, stale, or already-completed backlog entries.
