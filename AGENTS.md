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

- Every plan item must carry an explicit model assignment: Haiku 4.5 for
  single-file, fully-specified, mechanical work; Sonnet 5 for multi-file work
  with a stated end state; Opus 5 for architectural boundaries, extraction, and
  balance or design decisions. Assign per item, never per phase.
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

Tests are a gate, not a feedback loop. A full tier costs a Godot boot plus its
whole output, and re-running an unchanged tier proves nothing.

- **Once per item, not once per edit.** Batch related edits, then verify.
- **Match the tier to the change.** `unit` while iterating on simulation logic;
  `integration` when catalog or resolver behavior changed; `scene` only for
  presentation work.
- **Full sweep only at an item boundary**, immediately before committing.
- Trust the hooks: `pre-commit` already runs `unit` and `pre-push` runs every
  tier, so a manual pre-commit sweep is usually redundant.
- Do not re-run a tier to confirm a result already reported in this session.

## Backlog maintenance

- Use `BACKLOG_CRITICAL.md` for incomplete work that materially affects current
  gameplay, correctness, or user-facing readiness and should be fixed promptly.
- Use `BACKLOG_LONGTERM.md` for deferred design, tooling, and maintenance work.
- During every implementation task, update the relevant backlog files: add newly
  discovered unresolved work, remove completed entries, and move entries between
  the files when their urgency changes.
- Do not leave duplicated, stale, or already-completed backlog entries.