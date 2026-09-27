# Seat bias investigation

2026-09-27. Diagnose the recorded 36/36 team-one wins without changing production
rules, policies, maps, or catalogs. Generated observations belong under
`battle_output/`; the completed investigation's durable findings belong in its
commit body. This cycle owns only new paths and closes in the investigation commit.

## Outcome

Reproduce the declared evaluation, distinguish roster/position from acting order,
trace decisive actions, and recommend the smallest evidence-supported next step.
Diagnostic scenario transformations are experiments, not approved balance values.

## Items

### SEAT-1 — Isolate the causes of the evaluation's team-one dominance

**Model:** Opus 5 / GPT Sol

**Model rationale:** Separating interacting roster, geometry, scheduling, and policy
effects requires causal experimental design and reading canonical combat traces.

**Depends on:** None.

**Touches:**
- `tools/investigate_seat_bias.gd` and its `.uid` if generated.
- `docs/plans/seat-bias-investigation.md` (closure deletion only).
- `battle_output/tournaments/seat_diagnosis*` (ignored generated evidence).

**End state:** Reproducible diagnostic runs, explicit failure handling, measured
conclusions and limitations, and recommendations that preserve user authority
over gameplay changes.

**Implementation:** Reuse canonical scenario loading and simulation. Choose
controls that distinguish initiative, geography, roster, and policy. Log initial
state and decisive events; record source identity and do not tune a strength claim
on the old holdout. Explain experimental judgment in the commit body. No runtime,
catalog, existing scenario, shared runner, or active plan changes are authorized.

**Risk:** Confounding deterministic identity with turn order; treating seeds as
independent maps; mistaking an infrastructure failure or capped run for a loss.

**Validation:**
- Self-contained: reproduce the original manifest and use diagnostic controls
  with invariants enabled; repeat representative runs for deterministic equality;
  run the full probe sweep and the prescribed headless load check, attribute
  failures outside owned paths; inspect explicit-path diff and whitespace.

## Deliberately excluded

No balance edits, new production scenarios, policy tuning, or interactive windows.
No AI-strength claim from investigation data. No shared backlog/document edits.

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | SEAT-1 | Single session, new diagnostic tool only |
| — | validation: inline, no deferred checks | Headless experiment evidence |
