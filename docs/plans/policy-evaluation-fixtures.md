# Policy evaluation fixtures

2026-09-27. Turn the seat-bias diagnosis into a runnable exploratory evaluation.
Repair the evaluator contracts needed to trust its rows, author mirrored existing
kits across the three current maps, and run a declared paired experiment. This
cycle does not tune policies or combat balance. Source findings and deviations
belong in item commits; the cycle file freezes once execution starts.

## Outcome

- A tournament runs complete side turns through the last allowed round, records
  every result under an identity that covers actual source data, and launches
  reliably on this Windows host.
- Existing A and B kits can face identical kits on both sides on each of the
  three maps. The authoring is explicit, validated, and leaves playable source
  scenarios and the approved turn-order rule unchanged.
- A new manifest declares its cases, seeds, thresholds, and exploratory status
  before the run. The resulting report identifies decisive and seat-split
  positions by fixture, preserves capped/failure outcomes, and makes no policy
  strength claim from a viewed development set.

## Present-state facts

- The old 36/36 Team 1 result is reproducible; the claim that first action alone
  causes it is false. The original roster wins from the second seat on the larger
  maps. The technical map has roster, geography, policy and initiative effects.
- The old holdout has been inspected. Mirrored A on the technical map favored
  legacy in three exploratory pairs; mirrored A on Proving Ground favored
  tactical in three. Mirrored B and the Hexmap mirrors split by seat in that
  screen. Those numbers are screening evidence, not new acceptance criteria.
- The prior AI cycle's validation commit exists, but its cycle file remains open
  after a full-sweep failure outside AI ownership. Do not edit that frozen file.
- A current full sweep has a gated board-terrain failure because generated scenes
  are missing. Attribute this separately from evaluator checks and do not repair
  those paths in this cycle.

## Items

### PEF-1 — Make evaluator rows trustworthy

**Model:** Opus 5 / GPT Sol.

**Model rationale:** Completion at a round boundary, build identity, resumption,
and Windows process supervision interact; selecting the smallest reliable fix
requires contract judgment across the runner and its probe.

**Depends on:** None.

**Touches:**
- `tools/BuildIdentity.gd`
- `tools/run_policy_tournament.gd`
- `tools/run_policy_tournament.ps1`
- `checks/battle/probe_policy_tournament.gd`
- `battle_output/tournaments/pef_runner_*` (ignored evidence)

**End state:** Data/scenario/map/catalog edits change the content build hash;
the last round includes both surviving side turns; a bounded hidden launcher
produces and merges a complete smoke run on Windows. Prior resumption and
failure reporting remain intact.

**Implementation:** Fix the two evaluator gaps found in the diagnosis. Preserve
the established match and attempt identities, deterministic row bytes, canonical
simulator commands, and the one-process-per-worker recovery model. The exact
process wrapper and regression evidence are this item's decisions; explain them
in the commit body. Do not change policies, runtime combat, scenarios, or
presentation.

**Risk:** A cap fix can silently change result classification or clip the next
round; a data hash can drift on irrelevant files or miss scenario mutations; a
new launcher can deadlock on redirected output.

**Validation:**
- Self-contained: `powershell -NoProfile -ExecutionPolicy Bypass -File checks/run_probe_sweep.ps1 -Filter policy_tournament`; run the smoke manifest with one worker and with three workers/resume, checking markers and deterministic result bytes; run a one-round manifest and prove both side turns completed; check a controlled content-hash change; inspect focused diff and `git diff --check`.

### PEF-2 — Author and check mirrored fixtures

**Model:** Opus 5 / GPT Sol.

**Model rationale:** Symmetry must preserve party commanders, unit identity,
deployment legality and map conditions while exposing both informative and
seat-dominated cases; fixture selection is experimental judgment.

**Depends on:** PEF-1.

**Touches:**
- `data/scenarios/eval_mirror_*.json` (new)
- `checks/fixtures/evaluation_mirrors_v2.json` (new)
- `checks/battle/probe_evaluation_fixtures.gd` and `.uid` (new)
- `checks/manifests/ai_rework.json`
- `battle_output/tournaments/pef_fixtures_*` (ignored evidence)

**End state:** Six explicit, loadable A/A and B/B fixtures across technical,
Proving Ground and Hexmap; both policy assignments at each seed are declared
before results; self-contained checks prove symmetry, legal deployment,
commander slots, and unchanged map identity.

**Implementation:** Mirror only existing authored monsters and levels into the
opposite team, preserving each side's original cells and deterministic member
IDs. Keep previously screened fixtures as development data, including cases
that favor a seat. Select a useful seed spread and declare infrastructure,
cap and minimum-decisions criteria before running. No new monster content or
balance values. Record the fixture design judgment in the commit body.

**Risk:** A superficially symmetric roster can still have asymmetric cells,
terrain, or identity tie-breaks. Do not call a copied roster a fair map without
self-play evidence.

**Validation:**
- Self-contained: run the new registered probe via `powershell -NoProfile -ExecutionPolicy Bypass -File checks/run_probe_sweep.ps1 -Filter evaluation_fixtures`; require all six scenario loads and manifest pair count; inspect explicit diff and `git diff --check`.

### PEF-3 — Run and interpret the declared evaluation

**Model:** Opus 5 / GPT Sol.

**Model rationale:** A mixed decisive/seat-split result needs interpretation
that respects the effective map count, repeated seeds, and the spent holdout;
the conclusion can diverge from a naive pooled win rate.

**Depends on:** PEF-2.

**Touches:**
- `docs/AI_ARCHITECTURE.md`
- `docs/DEVELOPMENT.md`
- `BACKLOG.md` (whole-file ownership at this final wave)
- `docs/plans/policy-evaluation-fixtures.md` (closure deletion only)
- `battle_output/tournaments/pef_v2` (ignored evidence)

**End state:** A complete run and analysis at pinned source hashes, with
per-fixture seat and policy comparisons, honest effective sample interpretation,
current documentation, and a closed cycle. A failing probe outside owned paths
is attributed rather than altered. No assertion that one policy is stronger
without a genuinely fresh holdout.

**Implementation:** Run one integrated set through the repaired launcher and
analyzer. State which fixtures produce decisive pairs, which remain seat-led,
and what that means for future evaluations. Correct the old causal statement
in the durable AI reference, refresh the stale backlog entry, and document the
reproducible command. Keep the generated result only under BattleOutputPaths.

**Risk:** Treating six seeds on one authored map as six independent maps;
mistaking an exploratory interval for out-of-sample strength; suppressing
round caps or unrelated sweep failures.

**Validation:**
- Self-contained: require tournament and analysis success markers, complete
  manifest identity, invariant/illegal-command counts, by-scenario results,
  and source-hash agreement; run full `checks/run_probe_sweep.ps1` and the
  prescribed headless Godot load check, attributing failures by owned path;
  inspect focused diff and `git diff --check`.

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | PEF-1 | Evaluator foundation |
| 2 | PEF-2 | Depends on trustworthy runner |
| 3 | PEF-3 | Run and documentation after fixture commit |
| — | validation: inline, no deferred checks | Headless evidence only |

## Deliberately excluded

No combat or spell balance changes, turn-order rule changes, policy tuning,
new map art, interactive windows, or strength claim from the old holdout.
