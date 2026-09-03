# Implementation cycles

One file per cycle, named `<cycle-slug>.md`. **One cycle is active at a time**:
it runs on a `plan/<cycle-slug>` branch, and the repository has one working
tree, so a second cycle waits for the first to merge.

A cycle file is **frozen the moment execution starts** — no executing session
edits it. Everything execution produces lives in commit messages, which is why
two sessions can run at the same time without colliding.

`AGENTS.md` is the contract, including the branch lifecycle and the window
rule. This file is the shape.

## Cycle file skeleton

```markdown
# <Cycle name>

<Dated one-paragraph preamble: what this cycle is for, and what it is not.>

## Outcome
<What is true when the cycle closes.>

## Present-state facts an executing agent must not "fix"
<Behaviour that looks wrong and is not, with the reason. Numbers that will
legitimately change, so nobody restores the old ones.>

## Items
### <ID>-1 — <imperative title>
...

## Waves
...

## Deliberately excluded
<What was considered and left out, so it is not re-proposed.>
```

## Item skeleton

```markdown
### SKIN-4 — Put Nogg Herald under the whole battle UI

**Model:** Opus 5 / GPT Sol

**Model rationale:** <Concrete properties of this item — scope, ambiguity,
boundary impact, judgment, risk — connected to the tier. Restating the label
is not a rationale.>

**Depends on:** SKIN-2.

**Touches:**
- `src/presentation/theme/NoggTheme.gd`
- `src/presentation/theme/WindowSkinCatalog.gd`
- `docs/UI_DESIGN.md` §4

**End state:** <Observable, checkable.>

**Implementation:** <What is not obvious from the end state.>

**Risk:** <What this could break, and how to notice.>

**Validation:**
- Self-contained: <checks this item runs and records itself — data, docs, a
  load probe of scenes it owns. Omit the line if there are none.>
- Deferred: <one line needing the game launched in a quiet tree, for the
  validation item to consolidate. Omit the line if there are none — an item
  with no deferred check is verified when it commits.>
```

**Touches** is the item's exclusive claim while it runs, and it is what makes
concurrency safe. Include documentation. Be complete: an item that cannot state
its full write set is not ready to dispatch. When two items genuinely need the
same file, either give one item both edits or put them in different waves —
never let them overlap.

## Wave table

Ends the cycle file. Each wave lists the items that may run simultaneously in
separate sessions.

```markdown
## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | SKIN-1 | — |
| 2 | SKIN-2 | boundary item; everything after depends on it |
| 3 | SKIN-4, SKIN-5, SKIN-7 | theme tokens vs. chrome resources vs. rail/badges |
| 4 | SKIN-9 | validation, alone, quiet tree |
```

A wave is legal only when every item's dependencies are already committed and
the items' Touches lists are pairwise disjoint. Authoring this table is where
conflicts are designed out — it is the plan author's job, not the executor's.

### Naming the validation form

`AGENTS.md`, "Where validation runs", owns the rule. The table has to say which
of the three forms applies, because it changes how the last wave is dispatched:

```markdown
| 4 | SKIN-9 | validation, alone, quiet tree |          <- standalone
| 4 | SKIN-7 + SKIN-9 | one session; validation folded |  <- folded
| — | validation: inline, no deferred checks |            <- inline
```

Folding is legal only when the last wave is a single session that already owns
what the deferred checks look at, and acceptance is pass/fail rather than a
judgement about how something looks. Two or more sessions in the last wave, or
a design judgement in the acceptance, forces standalone. An **early validation
wave** — alone, mid-cycle, right after a boundary item — is allowed and stops
later waves building on something unverified.

## Executing

The cycle opens with `git switch -c plan/<cycle-slug>` in a quiet tree, and the
window rule applies from that point: everything this tree commits lands on the
branch until the cycle merges.

The user dispatches a wave by opening one session per item and naming it. Each
session commits once per item, with the finding in the message body and a
`Plan-Item: <ID>` trailer. Every session in a wave shares the branch — the
branch is not what keeps them apart, the Touches lists are.

Resume a cycle with:

```
git log --grep="Plan-Item: SKIN-" --format="%h %s"
```

An item with a commit is implemented; the cycle is done when the validation
item has one, after which it merges to `main` with `--no-ff` and the branch is
deleted. There is no status table, because a status table is a file two
sessions would have to write to.

## Single-session cycles

Not every cycle needs waves. A cycle whose items cannot state complete Touches
lists — because a blocking decision makes a later item's write set unknowable —
runs one item at a time in one session. Say so in the preamble, in place of the
wave table, so nobody tries to dispatch it concurrently. It still gets a
branch and a commit per item, and its validation is folded into the last
item's session by construction — there is never a second session to isolate it
from.
