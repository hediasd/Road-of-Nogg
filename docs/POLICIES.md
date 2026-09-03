# Road of Nogg Development Policies

Status: current. Last reconciled: 2026-09-03.

This document explains **why** the project's engineering guardrails are what
they are. [`AGENTS.md`](../AGENTS.md) is the operational contract and the only
place a rule is stated; current commands and troubleshooting live in
[`DEVELOPMENT.md`](./DEVELOPMENT.md).

Nothing here restates a rule from `AGENTS.md`. When a rule and its rationale
disagree, `AGENTS.md` wins and this document is out of date. Add reasoning
here; add rules there.

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

One human owns this repository and several agent sessions work in it
concurrently, in a single working tree. That shape is deliberate, and it splits
"safety" into two problems that people usually solve with the same tool.

**Concurrency is not a merge problem, and a branch cannot solve it.** The same
person drives every session, so no merge here settles a real disagreement. When
sessions each had a branch, the conflicts that appeared were in bookkeeping
files rather than in code — `implementation_plan.md` reached 72 of 120 commits
because every session wrote status notes into it. Worse, a branch is a property
of the working tree, not of a session: with one tree, three concurrent sessions
share one `HEAD` no matter what it points at, so branching buys literally
nothing against the hazard it looks like it should address. What actually
prevents a lost update:

- **Path ownership.** A plan item declares the paths it may write, and two
  items run concurrently only when those sets are disjoint. Disjointness is
  designed into the wave table rather than discovered at merge time.
- **Explicit-path staging.** A shared tree means a shared index, so a commit
  that does not name its paths captures another session's unfinished work.
- **A dirty tree carries no information.** It reflects other sessions, so
  pausing on it or cleaning it is friction with no safety value — which is also
  why whole-tree destructive commands are user-invoked only.
- **Commit shape as the rollback unit.** One item, one commit, disjoint paths,
  a `Plan-Item:` trailer. `git revert` on such a commit is a clean undo that
  later items do not fight.

**Releasability is a separate problem, and that is what branching does solve.**
Under the shared-`main` contract every plan item landed on `main` while still
"implemented; pending end-of-plan validation", so `main` was never a known-good
state mid-cycle, and undoing a cycle meant enumerating its commits by hand. A
cycle branch merged with `--no-ff` fixes both: `main` only ever advances to a
validated cycle, and the merge commit is a single revertable handle for the
whole thing. It is a coarse rollback layer on top of the per-item one, not a
replacement for it.

That branch is scoped to a *cycle*, never to a session, precisely because
sessions cannot be isolated by one. The cost is the window rule: with one tree,
work started during a cycle has nowhere else to go, so unrelated commits ride
along on the branch and one cycle runs at a time. For a solo project that is a
smaller price than either serializing the work or paying a 320 MB `.godot`
reimport for a second checkout.

Beyond that:

- Use a written plan when coordination, rollback risk, or architectural impact
  warrants one. Small and well-bounded changes can proceed directly even when
  they touch several files.
- Keep generated diagnostics out of tracked source. Put reusable utilities in
  `scripts/`.
- For complex UI, create a mockup when visual direction is genuinely undecided
  or the user asks for one. A mockup is not required for every `Control` tree.

## Documentation ownership

[`README.md`](./README.md) is the routing table: it names every document and
what that document owns. It is the only such table — a second copy is a thing
to keep in sync, and the copy that lived here had gone stale.

Every truth has exactly one owner. Update the owning document when that truth
changes and link to it from elsewhere rather than restating it, because a rule
written in two places drifts into two rules. This document's own relationship
to `AGENTS.md` is the example: reasoning here, rules there.

Two consequences worth stating. Execution state does not belong in a document —
a cycle file is frozen once execution starts, so item findings live in commit
messages. And a backlog entry earns its place only when it has a clear outcome
and is not being completed in the current task.

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
Verification is therefore manual, which is what shapes the rules in `AGENTS.md`,
"Running the checks". See [`DEVELOPMENT.md`](./DEVELOPMENT.md) for the
executable workflow and Windows safeguards.

Concurrency makes manual verification stricter rather than looser, and the
reason is that a launch observes the whole working tree rather than one item's
diff. During a wave it renders other sessions' half-finished work alongside the
item under test, so any conclusion is unsound in both directions — a failure
may not be yours, and a pass may depend on something about to change. Hence the
quiet tree: no other session editing while behaviour is being judged, and an
agent that hits a failure outside its own paths reports it and keeps going
instead of repairing work still in flight.

**The quiet tree is the invariant; a validation wave is only one way to buy
one.** Deferring *all* verification to a lone final item conflated the two, and
the conflation cost twice. It swept up checks that never observed the tree at
all — a catalog that must stay consistent, a doc reference that must resolve, a
scene that must still load — and parked them a wave away from the session that
knew why they mattered. And it lengthened the stretch in which every item sits
committed and unverified, because the only verification event was at the end.
Classifying each check as self-contained or deferred fixes both: self-contained
checks are proved in the item that created them, and only the checks that
genuinely need a launch wait. When those remaining checks belong to a last wave
that is already a single session, isolating that session from nobody is pure
dispatch overhead, so validation folds into it; two live sessions, or an
acceptance test that is really a judgement about how something looks, still
earn a wave of their own — the second because an implementing session grading
its own visual work is not an independent look at it.

What remains of the cost is worth naming: items with deferred checks are still
committed unverified, and the validating session inherits defects in code it
may not have written. The cycle branch limits the blast radius — the unverified
stretch never reaches `main` — and an early validation wave after a boundary
item shortens it, at the price of pausing concurrency once.

The same absence of automation is why existing VFX and animations are treated
as read-only while a new one is authored. With no regression suite, a tweak to
a shared helper, timeline, or resource that makes a new effect look right is
undetectable in every other caller until someone happens to look at it — and
manual validation in this project looks at the effect under test, not at the
donor. Duplicating a borrowed implementation into owned code costs a file;
coupling two unrelated effects through a premature abstraction costs a silent
regression nobody is watching for. The caller sweep required of a genuine
shared-contract migration exists for the same reason: it is the substitute for
the test run that does not exist. The operational form of both rules is in
`AGENTS.md`; the VFX-specific ownership and donor-capture detail is in
[`VFX_DESIGN.md`](./VFX_DESIGN.md).
