# Implementation cycles

One file per active cycle, named `<cycle-slug>.md`. Several may be active at
once. A cycle file is **frozen the moment execution starts** — no executing
session edits it. Everything execution produces lives in commit messages, which
is why two sessions can run at the same time without colliding.

`AGENTS.md` is the contract. This file is the shape.

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

**Adds to final validation:** <One line the validation item consolidates.>
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

The final validation item is always alone in its own wave, because manual
validation observes the whole working tree.

## Executing

The user dispatches a wave by opening one session per item and naming it. Each
session commits once per item, with the finding in the message body and a
`Plan-Item: <ID>` trailer.

Resume a cycle with:

```
git log --grep="Plan-Item: SKIN-" --format="%h %s"
```

An item with a commit is implemented; the cycle is done when the validation
item has one. There is no status table, because a status table is a file two
sessions would have to write to.
