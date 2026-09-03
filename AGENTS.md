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
contributors, so no merge here ever resolves a real disagreement; the only real
hazard is concurrent sessions overwriting each other, and most rules below
exist to stop that. Branching serves a different purpose — keeping `main`
releasable and making a cycle undoable in one move — and buys nothing against
the overwrite hazard.

- **A branch does not isolate sessions.** There is one working tree, so every
  session shares its `HEAD`. Putting the tree on a branch changes nothing about
  two sessions overwriting each other; only path ownership and explicit-path
  staging do that. What a branch buys is a `main` that never holds a
  half-finished cycle, and a one-command undo for a whole cycle.
- **Regular work — anything not driven by a plan — commits directly to
  `main`.** No branch, no ask.
- **An implementation cycle runs on its own branch**, `plan/<cycle-slug>`,
  created when the cycle opens and merged back with `--no-ff` when its
  validation passes. See "Plan lifecycle".
- **The window rule: while a cycle branch is checked out, everything committed
  in this tree goes on it** — plan items and unrelated work alike. Do not check
  out `main` to slip a quick fix in beside a running cycle; the checkout would
  change files under sessions that are mid-edit. The merge may therefore carry
  work that was not in the plan, which is accepted.
- **Never switch branches while another session may be running.** Creating,
  merging, and deleting a branch happen only at cycle boundaries, in a quiet
  tree, and the user says when the tree is quiet.
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
- A separate worktree is for exactly one case: work that may need to be
  abandoned wholesale and cannot wait for the current cycle. Say so and get the
  user's go-ahead before creating one — a checkout pays a full `.godot`
  reimport.
- **Never leave a branch behind.** Any session that creates, merges, or deletes
  a branch runs the audit in "Branch hygiene" afterwards and reports the
  result.

## Branch hygiene

Report unmerged work rather than letting it accumulate. Run this whenever you
create, merge, or delete a branch, when a cycle opens or closes, and whenever
the user asks about branch state:

```
git branch --no-merged main
git branch -r --no-merged main
git worktree list
```

- Name every branch the first two commands print, with its unmerged commit
  count, and say what it is. Silence is not a report: when both are empty, say
  so in one line.
- A merged branch left lying around is debris. Sweep every branch that is fully
  merged into `main` at each cycle boundary, not only the one the cycle used --
  the user gave standing authorization for this on 2026-08-29 after seven
  merged branches had accumulated. `git branch -d` is the safe sweep: it
  refuses anything unmerged. It also refuses a branch that is merged to `HEAD`
  but ahead of its own `origin/` tracking ref; that one needs `-D`, and only
  after `git rev-list --count main..<branch>` confirms zero.
- Deleting a branch on `origin` is a push, so it stays outward-facing: offer it,
  do not do it unasked. Local deletion is recoverable from the reflog.
- A worktree other than the primary one is a session running elsewhere or
  abandoned debris. Report it, check whether its `HEAD` is contained in `main`,
  and never remove it unprompted.

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

- Say what you are about to do before a long or blocking operation, and report
  what it produced at the next tool boundary.
- Do not narrate short steps or repeat what the tool output already shows.
  Filler updates cost tokens and tell the user nothing.

## Implementation plans

A plan lives in `docs/plans/<cycle-slug>.md`. **One cycle is active at a
time**, because the one working tree carries one branch and the window rule
puts everything committed during that window on it. A second cycle waits for
the first to merge. `docs/plans/README.md` carries the item and wave template.

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

  **Check the assignment before executing an item, and state the result — but
  do not stop.** Compare the item's Model field to the model actually running.
  If they differ, say so in one line and execute the item anyway; if several
  consecutive items share a tier, say so and suggest batching them under one
  correctly-sized session. This is a cost signal for the user to act on, not a
  gate. Routing that is authored and never checked is documentation, not
  delegation; routing that blocks costs a round trip the user never wanted.

  **Name the tier in conversation, not only in the plan file.** Any time you
  say what the next item, wave or lane is — a status recap, a suggestion at the
  end of a turn — give its suggested tier alongside it. The user dispatches
  from that sentence. For a folded validation, route the lane to the higher of
  the two tiers it covers.
- **Depends on** — the items whose commits must exist first.
- **Touches** — every path or glob the item may write, documentation included.
  This list is the item's exclusive claim while it runs, so it must be
  complete. An item that cannot state its full write set is not ready to
  dispatch.
- **End state**, **Implementation**, and **Risk**.
- **Validation** — classify every check the end state needs, as one or both of:
  - **Self-contained:** decidable from the item's own paths without observing
    the running game — data and catalog consistency, doc cross-references, a
    narrow load or parse probe of scenes the item owns, grep audits. The item
    runs these itself and records the result in its own commit body. Never
    defer a self-contained check.
  - **Deferred:** needs the game launched and its behaviour or appearance
    looked at, so it needs a quiet tree. One consolidated line.

  An item with no Deferred line is fully verified when it commits.

**Deferred checks, not item count, decide the plan's validation shape.** A
cycle whose items are all self-contained has no validation item at all. A cycle
with deferred checks has exactly one, depending on every item that feeds it,
with its own model assignment — and "Where validation runs" below settles
whether it needs a wave to itself.

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

### Where validation runs

The invariant is a **quiet tree** — no other session editing — because a launch
observes the whole tree rather than one item's diff. A wave of its own is one
way to get a quiet tree, not the requirement itself. The plan author picks one
of three forms and names it in the wave table:

- **Inline** — no validation item exists, because no item had a deferred
  check; each item proved its own checks when it committed. Write
  `validation: inline, no deferred checks` where the final wave would be.
- **Folded** — the validation item is the tail of the final wave's single
  session, taken as a lane: implement, commit, then validate in the now-quiet
  tree and commit the validation item separately. Legal only when all three
  hold: the final wave runs **one** session, that session already owns the code
  the deferred checks look at, and acceptance is observable pass/fail rather
  than a fresh-eyes judgement of look, feel or design. This is the form to
  reach for — it drops a dispatch round trip and a re-read of the same context.
- **Standalone** — the validation item runs alone in the last wave. Use it
  whenever folding is not legal, which it is not when the final wave has two or
  more sessions, when acceptance is a judgement about appearance or design that
  the implementing session cannot fairly make about its own work, or when the
  deferred checks span subsystems built in different waves. If in doubt, this
  is the safe choice — an unnecessary standalone wave costs a round trip, a
  wrongly folded one costs a validation nobody independently made.

A validation wave need not be last. When a boundary item is what every later
wave builds on, the plan may place an **early validation wave** right after it —
alone, quiet tree, its own item and commit — so the rest of the cycle stops
inheriting an unverified foundation. Checks it clears do not repeat later.

## Recording what an item found

**One commit per item, and its message body is the durable record.** Write the
finding once, there. Do not also write it into the cycle file, a resolution
note, or a status table — the plan is frozen and there is nothing else to
update.

- The body states what was implemented, what the plan assumed that turned out
  to be false, what was deliberately not done and why, and any evidence.
- The last trailer line is `Plan-Item: <ITEM-ID>`.
- An item carrying a deferred check is **implemented; pending validation**
  until the validation item's commit exists. An item whose Validation is
  entirely self-contained is verified as of its own commit — say that, not the
  pending phrase.

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

Rollback has two levels: the commit and the cycle.

- Undo one item: `git revert <sha>`. Because items own disjoint paths,
  reverting an earlier item does not conflict with later ones.
- Undo a wave: revert its commits newest-first.
- Undo a merged cycle: `git revert -m 1 <merge sha>`. This is what the `--no-ff`
  merge is for. Read the merge's diff first — under the window rule it may
  carry work that was never part of the plan.
- Abandon a cycle before it merges: `main` never saw it, so leave the branch
  unmerged and tell the user. Delete it only when they say so.
- A cycle's item footprint is `git log --grep="Plan-Item: <PREFIX>"`.
- Push the active branch to `origin` at every wave boundary, and push `main`
  after each merge. The pushed branch is the durable recovery point if the
  local tree becomes unrecoverable.
- If `git revert` refuses or conflicts because another session holds
  uncommitted edits in the same paths, stop and tell the user. Do not force it.

## Plan lifecycle

Opening a cycle, in a quiet tree, with the user's go-ahead:

```
git switch -c plan/<cycle-slug>
```

Then add the cycle file under `docs/plans/`, beginning with a dated
one-paragraph preamble stating what the cycle is for. From here the window rule
applies: everything this tree commits lands on the branch.

Closing is not a separate errand. **The turn that finishes the cycle's last
item also merges it and cleans up** — do not end a turn reporting "branch
unmerged, pending merge" as though that were a resting state. An open design
question the cycle surfaced does not hold the merge: record it in the backlog
and the relevant design note, merge, and raise it with the user afterwards.
Only a *failing* validation holds a merge.

Closing a cycle, after the cycle's validation passes and no session is
editing:

- Move genuinely open items to the appropriate backlog, name them to the user,
  and delete the cycle file in the same commit.
- **Promote any sketch worth keeping into `docs/sketches/`.** Design and motion
  sketches are otherwise written to a scratch directory and lost. The bar is
  high on purpose and is stated in `docs/sketches/README.md`: keep the artifact
  that settles a judgement call, not the proof output that a commit body
  already records.
- Merge and clean up:

  ```
  git switch main
  git merge --no-ff plan/<cycle-slug> -m "merge: <what the cycle delivered>"
  git push origin main
  git branch -d plan/<cycle-slug>
  git push origin --delete plan/<cycle-slug>
  ```

- Run the "Branch hygiene" audit and report it.

The cycle file stays recoverable with `git show <ref>:<path>`. Do not append a
new cycle to a finished file, and do not retain completed items in it.

A cycle that was already in flight when this contract landed stays on `main`;
do not retroactively move it to a branch.

## Running the checks

There is no automated test suite, check runner, or git hooks. Verify changes by
launching the game manually and exercising the affected behavior; follow the
Windows safeguards in `docs/DEVELOPMENT.md`.

**The tree you launch contains every concurrent session's in-flight edits.**
That has consequences:

- **Launching is gated on a quiet tree, not on a wave boundary.** Do not
  launch the game while another session may be editing, and a wave of two or
  more sessions is never quiet. A narrow compile/load probe is allowed even
  then when later items cannot safely build on potentially unusable code;
  record it as an intermediate smoke check, not acceptance evidence.
- If a probe fails in a path you do not own, report it in one line and continue
  your own item. Do not fix it — it is another session's work mid-flight.
- A self-contained check runs inside the item that owns it, and its result
  goes in that item's commit body. Do not push it into the validation item:
  deferring checks that never needed a quiet tree is what used to make
  validation an extra wave.
- Deferred checks run in the validation item, in the form the wave table names
  — inline, folded or standalone — after every item feeding it is committed and
  no other session is editing. Exercise the union of those checks and reuse one
  integrated flow where it covers several items.
- If validation finds a defect, fix it in that session, rerun the
  relevant consolidated checks, and record both in that item's commit. Do not
  reopen every prior item to repeat the same validation.
- A single-item plan validates at the end of that item — the degenerate case
  of the folded form.

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
