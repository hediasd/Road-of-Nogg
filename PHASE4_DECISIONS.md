# Phase 4 & P5-2 — Decision Proposals

Proposals for the items in [`AUDIT_REMEDIATION_PLAN.md`](./AUDIT_REMEDIATION_PLAN.md)
that need a design decision rather than engineering work. **Nothing here is
decided.** Each item states the options, a recommendation, and what it would
cost. Reply with a choice per item (or a different option) and the work
becomes routine.

Data in this document was measured from the current catalog on 2026-07-27, not
recalled.

---

## The three items that are really one decision

**P4-6, P4-9, and P4-10 are all facets of: what happens to the 13 legacy
race-less monsters?**

The roster splits cleanly in two:

| | count | HP range | has race | in default preset |
|---|---|---|---|---|
| **Legacy/test monsters** | 13 (46%) | 1-50 | no | all 8 slots |
| **Authored monsters** | 15 (54%) | 28-60 | yes | none |

Measured consequences of that split:

- **The authored roster is already internally consistent.** Its HP range is
  28-60 (2.1x). Every extreme outlier — `Dump` (HP 1), `Magemornus` (HP 8),
  `Defaultgon` (HP 10) — is a legacy monster. P4-10's "60x HP spread" is
  entirely a legacy artifact, not a design problem in the real roster.
- **The default preset is 8/8 legacy monsters**, so a default battle exercises
  no race, no resistance, and no weakness-driven Resonance decay. This was
  proven when doubling every resistance from ±10% to ±20% left the determinism
  check's outcome byte-identical (`winner=1 events=604`).
- **23 of 25 Level 1 spells are unassigned**, largely because the legacy
  monsters predate that vocabulary and the authored ones only partly use it.

### Options

**A — Retire the legacy roster from play (recommended).** Keep the entries
(tests reference `Defaultgon`, `Dump`, `Gigasaurus`, `Envoy of Lightning`,
etc.), but mark them non-selectable and rebuild `DEFAULT_TEAM_1/2` from the
authored 15. P4-6 and P4-10 dissolve; P4-9's unused-spell warnings become a
real authoring backlog against a coherent roster.

- Cost: one flag on the reference schema, a selectable-roster filter, new
  preset rosters, updating any test that assumes the current preset.
- Risk: several tests spawn legacy monsters by name and would keep working
  (they bypass the preset), but `test_playable_battle_core.gd` asserts 8
  deployed monsters per preset and would need its expectations re-checked.

**B — Promote the legacy roster.** Give all 13 races, families, and stats on
the authored curve. Preserves the default preset as-is.

- Cost: 13 × (race + family + stat pass) — real balance work, and it doubles
  the roster you must maintain forever.

**C — Split presets.** Keep legacy monsters selectable but add a "Showcase"
preset built from authored monsters, and make it the default.

- Cost: lowest. But it leaves the two-tier roster permanently, which is the
  underlying problem.

**Recommendation: A.** It converts three open items into one cleanup and stops
the roster from having two incompatible halves. If you want the legacy names
kept playable for nostalgia/testing, C is the cheap compromise.

**Question for you:** is `Kickatoo`'s `MOVE = 8` intentional? It's the only
authored-roster outlier (next highest is 5, and `Brickamount` is 1). It reads
like it could be a typo for 5, but "high-mobility" is plausibly the intent.

---

## P4-5 — Rebalance the race matchup table

Measured across the 14 races with resistances (net = weak-to minus resists):

| element | resisted by | weak to it | net |
|---|---|---|---|
| thunder | 0 | 6 | **+6** |
| fire | 2 | 5 | +3 |
| light | 2 | 5 | +3 |
| water | 3 | 5 | +2 |
| ice | 1 | 1 | 0 |
| steel | 3 | 2 | −1 |
| earth | 4 | 2 | −2 |
| wood | 3 | 1 | −2 |
| darkness | 5 | 1 | −4 |
| wind | 5 | 0 | **−5** |

Thunder is resisted by nobody and strong against 6 of 14 races. Wind is
resisted by 5 and strong against none — and `Blue Crowned Pidgeon` is
mono-Wind. Ice is the only balanced element.

### Options

**A — Targeted patch.** Swap ~8 individual entries to pull every element into
roughly −2..+2. Minimal churn, no structural guarantee against future drift.

**B — Principled cycle (recommended).** Order the 10 elements in a fixed ring
and define each race's matchups by position, so every element is resisted by
exactly N races and strong against exactly N. Self-documenting, and new races
slot in without re-auditing the whole table.

- Cost: rewrites all 14 races' `RESISTANCES` at once, but it's mechanical
  once the ring order is chosen. Determinism numbers will shift (expected).
- Needs from you: the ring order, i.e. the thematic "beats" relationships.
  A conventional one — fire → wood → earth → thunder → water → fire, with
  light ↔ darkness paired and steel/ice/wind slotted — is a starting point,
  but this is a creative call.

**Note:** ±20% is now the multiplier (changed this session). At typical damage
values that's ±1-2 per hit; the mechanically larger consequence of a weakness
hit is stripping a Resonance charge. Worth keeping in mind when judging whether
the table's *shape* matters more than its magnitude.

---

## P4-3 — Author the Level 2-4 spell pool

The single biggest gap: **every tiered spell in the catalog is Level 1**, so
Resonance can never exceed one charge, and the +20%/+30% tiers plus Level 4
ascension are unreachable in play (all implemented and unit-tested, just
unreachable).

Current Level 1 pool, by element:

| element | L1 spells |
|---|---|
| light | Elucidate, Prayer, Prelude, Shine (4) |
| wind | Breeze, Flow, Follow Up, Stroll (4) |
| fire | Enrage, Lantern, Predict (3) |
| ice | Chill, Dutiful, Triage (3) |
| water | Dissolve, Moderation, Ponder (3) |
| darkness | Anticipate, Plot (2) |
| earth | Pillar, Stand (2) |
| wood | Barricade, Gather (2) |
| steel | Iterate (1) |
| thunder | Cheers (1) |

### Options

**A — Pilot one element end to end (recommended).** Author L2/L3/L4 for a
single element, assign a complete vertical set to one monster, and verify the
whole Resonance ladder in real play before scaling. Three spells, not thirty.

- Suggested pilot: **light** — 4 existing L1 spells to build from, and
  `Warden of the Dunes` is mono-light with three light spells already, so it
  can carry the first complete set without touching any other monster.
- Once validated, the remaining 9 elements are repeatable authoring work
  (Sonnet-tier, given a decided template).

**B — Author all 10 elements (30 spells) in one pass.** Complete, but commits
to a tier design that hasn't been validated in play even once.

**Recommendation: A.** But first, the thing that actually blocks authoring:

**Needs from you — the tier design contract.** What distinguishes a Level 2
from a Level 3 from a Level 4? Without this, any spells I author are invented
balance. Some axes to pick from: raw power, range, AOE size/shape, cooldown,
status strength, self-cost, targeting restrictions. The existing L1 convention
is already fixed by the validator (self-target, range 0), so tiers 2-4 need
their own equivalent rule.

---

## P4-4 — `LUCK` and growth values

These are two separate decisions bundled into one item, and they are **not
equally ready**.

### LUCK (ready to decide)

No monster defines `LUCK`, so criticals never fire.
`tests/integration/test_roster_luck_is_dormant.gd` actively fails the build if
any monster has non-zero Luck — a deliberate guard that must be deleted in the
same change that introduces Luck.

- Options: (a) flat low Luck roster-wide; (b) Luck as an archetype signature —
  assassins/glass cannons high (`Night Hunter Panther`, `Paper Cat`,
  `Samarkand Stalker`), bruisers 0; (c) keep dormant.
- **Recommendation: (b)**, capped well under the 15% ceiling — it makes Luck a
  characterisation tool rather than universal variance, and preserves
  determinism-friendly low-variance play for most units.
- Needs from you: the per-archetype values.

### Growth (blocked on a prerequisite — recommend deferring)

Every `*_GROWTH` is 0, **and no production code ever spawns a monster above
level 1** — `BattleSetupFactory` calls `spawnMonster(name, team, pos)` with the
default `level = 1`. So growth values are doubly inert: even non-zero growth
would change nothing until something varies level.

- **Recommendation: defer growth entirely** until there's a reason for level to
  vary (campaign progression, a level control in setup, or an ascension
  system). Assigning growth numbers now would be unverifiable and untestable.
- If you want it now, the prerequisite is a decision about *where* level comes
  from — that's a bigger product question than a balance table.

---

## P4-7 — Petrify is an outlier

`Closing of the Third Sanctuary`: radius 3, range 5, **no cooldown**, no
resistance roll, and petrify makes `executeCommand` skip the victim's entire
turn for 2 turns. Repeatable every turn, on up to a quarter of the board.

### Options

**A — Add a cooldown (recommended, cheapest).** `COOLDOWN = 4-6` makes it a
tempo tool rather than a lock. One data field; the mechanic already works.

**B — Reduce radius** 3 → 1-2. Keeps it spammable but local.

**C — Add a resistance roll.** Most faithful to genre, but there is no
save/resist mechanic anywhere in the codebase — this is a new system, not a
tuning change, and would need a design pass of its own.

**D — Combination of A and B.**

**Recommendation: D (cooldown 5, radius 2)**, or A alone if you want the
minimal intervention. Avoid C for now unless you want to design a save system.

---

## P4-8 — `guard`/`focus` durations are fiction

Authored as `DURATION = 4`, but both are consumed by the first damage event —
verified by `tests/integration/test_level_one_spells.gd`, which asserts the
effect is gone after one hit.

### Options

**A — Change the data to `DURATION = 1` (recommended).** The one-shot behavior
is clearly the intent (it's what the tests lock in, and what makes `focus`
tactically interesting); the data is simply lying. Affects 9 spell entries.

**B — Stop consuming them**, making the 4-turn duration real. Turns a
precision tool into a broadly strong buff — a real balance change, not a
cleanup.

**Recommendation: A.** It's a documentation fix disguised as a data change, and
it makes the catalog honest without touching behavior. Note that P2-2's
`StatusEffectReferences` also lists `guard`/`focus` at `DURATION 4` as their
catalog default — that entry should change in the same pass.

---

## P4-2 — Resonance and criticals have no UI

Nothing in `src/presentation/` references resonance or criticals. Players
cannot see charge state, and crit/weakness hits look identical to normal ones.
`resonance_changed` now reaches adapters (P2-1) and the console adapter logs
it, so the data is available — only the 3D presentation is missing.

### Options

**A — Defer until P4-3 lands (recommended).** Today charge can only ever be 0
or 1, so any UI would display a binary state that the player has almost no
agency over. Building it now means designing against a mechanic that isn't
yet real, then redesigning when tiers 2-3 arrive.

**B — Build it now, minimally.** Extend the existing `StatusEffectIcons` badge
row with a small charge indicator. Cheapest path, consistent with existing
presentation, and would at least surface the mechanic.

**C — Dedicated element-coloured charge bar** beneath the HP bar, plus crit/
weakness damage-number styling.

**Recommendation: A, then C when P4-3 is done.** Sequencing this after the
spell pool avoids building UI twice. If you'd rather have visibility sooner,
B is a reasonable stopgap that C can replace.

---

## P5-2 — Split the two oversized presentation files

`src/systems/BattlePresentationController.gd` (876 lines) and
`src/presentation/GodotVisualAdapter.gd` (783). Not urgent — the plan itself
says "do it the next time either file needs a substantial feature."

Suggested seams, both along boundaries the code already has:

- **Controller** → extract the player-turn state machine
  (`UNIT_SELECTED → MOVE_PREVIEW → ACTION_MENU → TARGETING → CONFIRM`, per
  `ARCHITECTURE.md`) into its own class. It is a self-contained state machine
  that currently shares a file with scene lifecycle, input routing, pacing,
  and adapter wiring.
- **Adapter** → extract the visual-action queue (the FIFO, its tweens, and the
  watchdog recovery) from the event-handling surface. `LEARNINGS.md` already
  treats the queue as its own conceptual unit with its own invariants.

**Recommendation: do this immediately before P4-2's UI work**, not on its own.
P4-2 will add resonance/crit rendering to exactly these two files, so splitting
first avoids growing them further and gives the new UI a clean home. Doing it
standalone is churn with no user-visible payoff.

**Risk:** this is the highest-risk item in the document — cross-layer, touches
the scene runtime, and the `scene` test tier that would catch regressions is
currently unreliable (see below). Resolving the scene-tier tooling issue first
would make this materially safer.

---

## Suggested order

1. **P4-8** and **P4-7** — smallest, self-contained, no dependencies.
2. **The legacy-roster decision** (P4-6 + P4-9 + P4-10 together).
3. **P4-5** — race table, ideally after the roster decision so it's balanced
   against the roster that will actually ship.
4. **P4-3 pilot** — needs the tier design contract from you first.
5. **P4-4 (Luck only)** — defer growth.
6. **Scene-tier tooling fix** (below), then **P5-2**, then **P4-2**.

---

## The standing non-plan item — scene-tier output capture

`tests/scene/test_capsule_features.gd` loses its success marker on this Windows
host even when every assertion passes, and because the tier shares one Godot
process, it takes the other three scene tests' output down with it. This makes
`scripts/hooks/pre-push` fail on every run regardless of real results. Full
detail in [`BACKLOG_LONGTERM.md`](./BACKLOG_LONGTERM.md).

**This splits into two very different tasks, and only one is worth doing.**

### Containment — recommended, Sonnet 5

Run `test_capsule_features.gd` in its own Godot process so it cannot corrupt
other tests' output. Concretely: teach `tests/run_tests.gd` an "isolate" list
(or a per-file tier), and have `pre-push` invoke the isolated test as a
separate `run_godot_check.ps1` call whose marker is checked independently.

- Restores `pre-push` as a trustworthy gate — the actual goal.
- Well-specified, mechanical, testable. **Sonnet 5.**
- Should be done **before P5-2**, which needs the scene tier to be trustworthy.

### Root-causing — recommended: don't, for now

The remaining hypotheses are inside Godot's own logging/shutdown on this
Windows build. I already ruled out the tractable one (a timing race — an
explicit multi-frame yield plus `OS.delay_msec(1500)` before `quit()` changed
nothing). What's left is engine-internals work with an uncertain payoff, on a
bug that containment fully neutralises.

- If you ever do want it chased: **Opus 5**, with `--verbose`, and the honest
  expected outcome is an upstream Godot report rather than a local fix.
- It also shares a signature with the existing `LEARNINGS.md` GUT access
  violation on the same host — worth mentioning together in any upstream
  report, since a common cause is plausible.
