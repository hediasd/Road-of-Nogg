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
- Every item names its own verification command and its risk.
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
- Read narrowly. Locate with a content search, then read a bounded range. Read a
  file end to end only when editing throughout it.

## Running the checks

There is no automated test suite or git hooks in this repository right now;
the previous suite and hooks were removed to be rebuilt fresh.

- Verify by launching the game manually and exercising the affected behavior,
  once per item boundary rather than once per edit.
- Do not claim an item complete without having actually exercised the affected
  behavior in this session.

## Backlog maintenance

- Use `BACKLOG_CRITICAL.md` for incomplete work that materially affects current
  gameplay, correctness, or user-facing readiness and should be fixed promptly.
- Use `BACKLOG_LONGTERM.md` for deferred design, tooling, and maintenance work.
- During every implementation task, update the relevant backlog files: add newly
  discovered unresolved work, remove completed entries, and move entries between
  the files when their urgency changes.
- Do not leave duplicated, stale, or already-completed backlog entries.