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
- **Regular and planned work both commit directly to the currently checked-out
  branch, normally `main`.** Several plans may execute at once. A plan branch
  is an opt-in, user-requested recovery boundary; never create, switch, merge,
  or delete one merely because a plan exists.
- **Concurrent execution is the default.** Do not wait for a quiet tree, a
  clean status, another plan, or another model session before starting your
  owned item. Coordinate through complete, disjoint `Touches` lists and
  explicit hand-offs for genuine overlapping ownership.
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
- **Commit working code the moment an item works, and never end a session with
  uncommitted edits in your owned paths.** If the item is not finished, commit
  what exists anyway as `wip: <item>` and say what is missing in the body. The
  working tree is not storage: on 2026-09-16 the hex battle's camera panning,
  stage and board work turned up in a forgotten stash. It had never been
  committed, the branch had been merged without it, and `main` looked like it
  had regressed. The user gave standing authorization on 2026-09-16 for sessions
  to commit whenever an item's code is developed.
- **Launching and probes may run while other sessions edit.** Treat their
  result as evidence for the exact revision and owned paths exercised; record
  unrelated in-flight changes that can affect the result, but do not wait for
  them or repair their paths.
- A separate worktree is optional, never a substitute for path ownership. Ask
  before creating one because it changes checkout and import state.
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
git stash list
```

- A stash is unmerged work too, and the easiest kind to lose. Report every
  entry with the branch it names. Never merge or delete a branch while a stash
  names it: restore that stash onto the branch and commit it first, or ask the
  user.

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
- A worktree other than the primary one is a session running elsewhere or
  abandoned debris. Report it, check whether its `HEAD` is contained in `main`,
  and never remove it unprompted.

### Housekeeping strategy

The goal is one long-lived branch, `main`, with `origin/main` matching it. The
user gave standing authorization on 2026-09-16 for everything below: merging,
deleting merged branches locally and on `origin`, and pushing. It does not cover
force pushes, rewriting history, or anything the checks have not cleared.

1. **Merge when possible.** When a branch's work is finished, merge it into
   `main` in the same session. Don't leave it for later. Before merging,
   dry-run it with `git merge-tree --write-tree main <branch>`:
   - **No conflicts:** merge it, run the checks for the paths it touched, and
     sweep the branch.
   - **Conflicts in paths you understand:** resolve them. Say in the merge
     commit body which side won and why.
   - **Conflicts you can't settle from the code and the plans:** stop and ask.
     Don't guess.
2. **Check that a branch is really stale before calling it stale.** A branch
   that is well behind `main` with no commits in over a week is a candidate.
   Before touching it, check whether its changes already exist on `main`:
   compare the files it changed against `main`, not only the commit count.
   - **Already on `main`:** it is debris. Delete it.
   - **Not on `main`:** it is lost work, not debris. If it still fits the
     current code, restore it and commit it. If it is truly obsolete (built on
     files `main` has since deleted, say), tag it `archive/<name>`, push the
     tag, then delete the branch. Name what it held in the report either way.
3. **Never leave work where only a branch or a stash holds it.** Anything worth
   keeping ends up as a commit on `main` or as an `archive/` tag on `origin`.
4. **Push when confident.** Push `main` after a commit or merge whose checks
   passed and whose scenes load. Also push branch deletions and archive tags
   as soon as they happen. Do not push when:
   - a check failed or was skipped,
   - the commit might contain another session's half-finished work,
   - you resolved a conflict you are unsure of.
   In those cases, say why you held back. Never `--force`.
5. **Finish every housekeeping pass with the audit above.** Report what was
   merged, deleted, archived and pushed. End with one line: either "only
   `main`, in sync with `origin`" or what is still left and why.

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

A plan lives in `docs/plans/<cycle-slug>.md`. **Any number of cycles may be
active at once.** Their items may run in parallel when their `Touches` lists
are disjoint; overlapping paths require an explicit sequential lane or a
user-coordinated ownership transfer. `docs/plans/README.md` carries the item
and wave template.

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

  **Name the tier in conversation, not only in the plan file — with its
  rationale.** Any time you say what the next item, wave or lane is — a status
  recap, a suggestion at the end of a turn — give its suggested tier alongside
  it, plus one short clause on why that tier fits this work. The user
  dispatches from that sentence, and a bare label gives him nothing to disagree
  with when the routing is wrong. For a folded validation, route the lane to
  the higher of the two tiers it covers.
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
    looked at. Record the revision and unrelated in-flight changes that could
    affect the observation. One consolidated line.

  An item with no Deferred line is fully verified when it commits.

**Deferred checks, not item count, decide the plan's validation shape.** A
cycle whose items are all self-contained has no validation item at all. A cycle
with deferred checks has exactly one, depending on every item that feeds it,
with its own model assignment — and "Where validation runs" below settles
whether it needs a wave to itself.

### Convergence reviews during execution

Count implementation items in planned wave order, excluding any validation
item. A cycle with 5–8 implementation items has one implicit convergence review
after `floor(item count / 2)` items (after item 3 in a 7-item cycle). A cycle
with 9 or more has one after every third implementation item, except the last;
a 9-item cycle reviews after items 3 and 6. Shorter cycles need no scheduled
review. Author new wave tables so a wave ends at each review point. For an
already frozen cycle whose waves cross a review point, review at the first
completed wave boundary after it instead of editing the cycle file.

In a wave, the session that commits its last item performs the review before
the next wave begins. In a single-session cycle, review immediately after the
checkpoint item's commit. Stop and compare the committed work and check
evidence so far with the cycle's outcome, item end states, constraints,
dependencies, and deliberate exclusions. Use a small focused probe when it
helps expose drift; this review does not repeat every item's checks or replace
deferred validation.
Report whether the work is converging and what course correction is needed.
Correct drift within the remaining items' owned paths and intended outcome,
recording the reason in the relevant item's commit. If recovery needs paths
outside their `Touches` lists or changes the promised outcome, stop dependent
work and coordinate a revised plan with the user. The review is an implicit
execution substep, not an item, commit, approval gate, or edit to the frozen
cycle file.

**Write each item for the tier that will run it.** The Model field is not only
a cost decision — it decides how the item body must be written, and an item
written for the wrong tier fails even when the routing is right.

- **Sonnet 5 / GPT Terra items are specifications.** Exact paths, symbol names,
  signatures, constants and their values; an end state phrased so it can be
  checked literally; the verification command written out rather than
  described. Point at an existing file to mirror instead of explaining the
  pattern in prose. State the boundary explicitly — what the item must *not*
  touch or "improve" — because this tier's failure mode is drifting into
  adjacent work that belongs to another item's Touches list. Leave no open
  question and no "decide whether".
- **Opus 5 / GPT Sol items are briefs.** State the problem, the constraints and
  the tension, not the solution: prescribing an implementation wastes the tier
  being paid for. Give the context that is not recoverable from the code — why
  the current shape exists, what was already tried and rejected — name the
  invariants that must survive, and say plainly which decision is the session's
  to make. Ask for the judgement and its reasoning in the commit body, so the
  next cycle inherits it.
- The two forms are also a check on the routing itself. If a Sonnet item cannot
  be written without leaving something open, it is an Opus item. If an Opus
  item reads as a step-by-step recipe, the judgement has already been made and
  it is a Sonnet item.

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

Validation is scoped to the item revision and its owned paths. A launch can
observe concurrent edits, so the validating session records that context and
does not attribute failures outside its ownership. The plan author picks one
of three forms and names it in the wave table:

- **Inline** — no validation item exists, because no item had a deferred
  check; each item proved its own checks when it committed. Write
  `validation: inline, no deferred checks` where the final wave would be.
- **Folded** — the validation item is the tail of the final wave's single
  session, taken as a lane: implement, commit, then validate against that
  revision and commit the validation item separately. Legal only when all three
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
wave builds on, the plan may place an **early validation wave** right after it,
with its own item and commit, so the rest of the cycle stops inheriting an
unverified foundation. Checks it clears do not repeat later.

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

Rollback is normally item-scoped; an optional user-requested plan branch may
also provide a cycle-level merge commit.

- Undo one item: `git revert <sha>`. Because items own disjoint paths,
  reverting an earlier item does not conflict with later ones.
- Undo a wave: revert its commits newest-first.
- Undo a user-requested merged cycle: `git revert -m 1 <merge sha>`. Read the
  merge's diff first. Plans executed on `main` are reverted item-by-item.
- A cycle's item footprint is `git log --grep="Plan-Item: <PREFIX>"`.
- Push a user-requested active branch at wave boundaries; otherwise push the
  current shared branch at ordinary integration points.
- If `git revert` refuses or conflicts because another session holds
  uncommitted edits in the same paths, stop and tell the user. Do not force it.

## Plan lifecycle

Opening a cycle does not change branches. Add the cycle file under
`docs/plans/` with a dated one-paragraph preamble, then execute its disjoint
items alongside other active plans. A cycle file freezes when execution starts.

Closing is not a separate errand. **The turn that finishes the cycle's last
item closes its documentation and reports the result.** An open design question
does not block closure: record it in the backlog and relevant design note.
Only a *failing* validation holds closure.

Closing a cycle after its validation passes:

- Move genuinely open items to the appropriate backlog, name them to the user,
  and delete the cycle file in the same commit.
- **Promote any sketch worth keeping into `docs/sketches/`.** Design and motion
  sketches are otherwise written to a scratch directory and lost. The bar is
  high on purpose and is stated in `docs/sketches/README.md`: keep the artifact
  that settles a judgement call, not the proof output that a commit body
  already records.
- If the user explicitly requested a plan branch, merge and clean it up under
  the branch rules; otherwise no merge is needed. Run the branch hygiene audit
  only after an actual branch action or when asked about branch state.

The cycle file stays recoverable in Git history. Do not append a new cycle to a
finished file, and do not retain completed items in it.

## Running the checks

There is no test suite or git hooks. `scripts/checks/run_probe_sweep.ps1` runs
every probe registered under `scripts/checks/probes/`. Run it with `-Filter` on
your area when your item changes code a registered probe loads, and in full in
a cycle's last item. An item that adds a probe registers it in a manifest in
the same commit. Behaviour and appearance still need the game launched
manually; follow the Windows safeguards in `docs/DEVELOPMENT.md`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter side_turn
```

A probe that fails today is **quarantined** in its manifest (`"gate": false`
with the reason in `"note"`), so it still runs and is still reported but cannot
fail the sweep. Quarantine is a record of a known failure, not a repair: do not
un-quarantine a probe without making it pass.

- For a non-interactive Godot code check on this Windows host, run
  `./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --quit-after 5 --rendering-method gl_compatibility --audio-driver Dummy`.
  Do not start, close, or automate an interactive Godot window for that check;
  the user owns interactive playtesting.
- Any change to battle HUD or side-turn UI must pass
  `scripts/hex_battle/side_turn/probe_ui_guardrails.gd` (screen margin, content
  inset, unclipped text, game fonts; see `docs/UI_DESIGN.md` §10c). Extend its
  states when adding a new window rather than exempting the window.

**The tree you launch can contain concurrent sessions' in-flight edits.** That
requires careful attribution, not serialization:

- Launching is allowed at any time. Before launch, record the commit/revision
  and inspect the focused owned diff; treat unrelated changes as environment
  context. A narrow compile/load probe remains useful when later items depend
  on a potentially unusable boundary.
- If a probe fails in a path you do not own, report it in one line and continue
  your own item. Do not fix it — it is another session's work mid-flight.
- A self-contained check runs inside the item that owns it, and its result
  goes in that item's commit body. Do not push it into the validation item:
  deferring checks that never needed a quiet tree is what used to make
  validation an extra wave.
- Deferred checks run in the validation item, in the form the wave table names,
  after every item feeding it is committed. Exercise the union of those checks,
  reuse one integrated flow where it covers several items, and record
  concurrent-tree context.
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
