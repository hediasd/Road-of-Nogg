# Battle AI rework

Opened 2026-09-20; revised before execution on 2026-09-20 after architectural
review and the user's instruction to defer tournament tooling. Build the
deterministic state and AI foundations first. Existing tournament tools are
placeholders, not a migration target or an early acceptance gate. Later items
build experiments and analysis against the settled interfaces. The cycle also
proves a technical whole-side-turn rewind, without authoring its spell, cost,
lore, or changing approved combat rules. Work on the checked-out branch. No
implementation item had a commit when this revision was authored; these item
numbers replace the previous unexecuted ordering. The file freezes when
execution starts. One commit per item; findings and deviations belong in its
commit body, with the last trailer Plan-Item: AIR-<number> or Plan-Item: AIR-V.

## Outcome

- BattleSimulator and BattleState remain canonical. Complete mutable state,
  lossless persistence, rule-relevant memory, and deterministic scheduling form
  one foundation for live battles, policy forecasts, checkpoints, and replay.
- A side policy chooses actor and command from authoritative legal queries.
  Cheap estimates, bounded detailed forecasts, and actual side-turn scheduling
  support coordinated play with measurable computation and explicit limits.
- Hex geometry and danger queries are optimized against measured workloads.
  Sparse versus batched computation is an implementation choice; correctness
  and resource budgets are the acceptance criteria.
- A technical checkpoint restores a side turn and records the branch without
  reviving stale proposals or callbacks. No player-facing rewind is authored.
- After the AI foundations, a resumable process-based experiment runner and
  analysis command compare policies, configurations, cost, and failure reasons.
- docs/AI_ARCHITECTURE.md is the durable AI reference. It distinguishes shipped
  behavior from intended contracts and covers structure, algorithms, extension
  points, determinism, limits, and later experiments. Every item updates its
  sections in the same commit as implementation.

## Present-state facts and corrections

- PartyCommandDeliberation prioritizes ready actors and finishes after the first
  selected actor's deliberation. It does not compare all ready actors' scores.
  CommandDeliberation limits destinations to ten, deduplicates spell centers by
  affected units, sets an empty threat dictionary, and skips the threat phase.
  Removing those restrictions changes behavior; it is not automatic parity.
- The controller currently advances deterministic slices on the presentation
  thread. Headless callers run synchronously. Worker-based interactive planning
  is not the current architecture and is not required by this cycle.
- RandomLegalBrain samples the existing pruned candidates, not the entire legal
  action space. It is useful fuzz coverage, not a strength baseline. Its private
  policy randomness must not advance live BattleState.rng.
- HexGrid already owns axial/offset conversion and stable six-neighbor order.
  Weighted movement, height, occupancy and zone of control use MovementResolver.
  Magic is pre-move; commander defeat can withdraw a party. Preserve these rules.
- Monster serialization stores spell/passive names; restoration recreates
  catalog instances. Arbitrary runtime ability changes are not fully captured.
  RNG state is currently a JSON number, creating a lossless-round-trip risk.
  Existing serialize/deserialize equality does not prove complete state.
- SpellEffectResolver's damage reversal reads prior damage events. History
  cannot simply be removed from forecasts. Separate rules memory, replay
  operations, and diagnostic telemetry without losing that behavior.
- Existing ThreatMap and old timings are not the current CPU path or a trusted
  reference for current pre-move magic. A fresh small-map oracle must use current
  legal operations; historical timings are not an acceptance baseline.
- A previous Godot 4.4 run crashed before its success marker. The stage/cause was
  not established. Diagnose any repeated failure through a narrow current probe.
  Do not require rebuilding old championship tools or fixing their quarantined
  schema assertions before state/AI work. Do not claim checks passed without
  marker, exit status, and the required artifact.
- Other cycles may run concurrently. Check actual ownership before editing.
  A dirty tree is normal. All generated battle artifacts use BattleOutputPaths
  under battle_output/. Do not create a worktree without user authorization.

## Shared contracts and evidence

### Determinism and state

Simulation, algorithms, board data, entities, AI and factories remain headless;
no visual/tree inheritance or presentation dependency enters those directories.
Presentation observes simulation events and never mutates canonical state.

The state inventory must identify every future-affecting field and its owner:
board layers, entities, runtime ability changes, effects and durations, resources,
cooldowns, side/selection/spent/withdrawal state, pending operations, gameplay RNG,
allocation, and rule-relevant memory. Future delayed-effect queues must join this
inventory when introduced. Content definitions are immutable; runtime modifiers
belong in battle state. Policy memory is explicit serializable input/output, or
the policy is stateless. No hidden singleton or catalog mutation is permitted.

Version snapshots, commands, policy configuration, and replay schema. Persist
unrestricted 64-bit values losslessly. Compatibility identifies engine build,
simulation source/build, content, and policy configuration. Old ambiguous data
must be migrated only when lossless or rejected clearly. Do not promise exact
replay across arbitrary engine versions. In-memory and actual disk round trips,
fresh-process continuation, and first-divergence diagnostics are required.

Use stable candidate order, fixed work budgets, and total tie keys. Wall-clock
limits may yield computation or terminate a failed match, but cannot decide
which partial search result wins. Distinguish semantic state fingerprints from
monotonic revision/timeline-generation tokens and diagnostic trace hashes.
Every supported state mutation invalidates dependent queries; restoring an equal
old position must never accept abandoned work from a different generation.

### Forecasts, effects, and decisions

Exact debug reproduction may clone gameplay RNG. Normal policy evaluation must
not inspect upcoming live random outcomes. Use explicit chance branches or
deterministically seeded policy samples with stable sample identities. Never
advance live RNG during planning. Forecast results name uncertainty treatment,
decision horizon, accepted versus resolved outcomes, and work consumed.

Execute through canonical resolvers, including ordered reactions and fizzles.
Define atomic observation/checkpoint boundaries, deterministic trigger order,
and a diagnostic failure for runaway reaction chains; do not silently truncate
gameplay. Do not introduce a general effect language or new gameplay content.
Document the registration obligations for future pending effects and new actions.

Legal enumeration, cheap ranking, detailed simulation, and strategic evaluation
are separate. Simulation support does not imply that the evaluator understands
delayed effects. Conservative pruning cannot discard an action merely because
its benefit is unfamiliar; retain a deterministic exploration allowance or an
explicit capability fallback. Distinct paths/centers remain distinct whenever
their effects differ. Define the finite action abstraction used for sampling.

### Documentation and verification

docs/AI_ARCHITECTURE.md owns AI-specific contracts and diagrams, current module
entry points, algorithm choices and rejected alternatives, complexity drivers,
randomness/information access, cache lifetimes, history ownership, rewind,
extension checklists, capabilities/limits, and experiment semantics.
ARCHITECTURE owns general simulation/presentation boundaries; MODULE_MAP owns
directory routing; DEVELOPMENT owns runnable commands; GAME_DESIGN owns approved
behavior. Link to these owners instead of copying their sections. Every item
updates the AI reference to describe what actually shipped; keep unimplemented
contracts explicitly labeled. No durable document needs cycle item IDs to make
sense. Findings are recorded once in commit bodies; docs describe lasting truth,
not execution progress or benchmark diaries.

Each new probe is registered in scripts/checks/probes/ai_rework.json in its
own commit with a unique success marker. Registration must not duplicate an
existing script. Do not weaken or unquarantine an unrelated failing probe.
Run each item's self-contained checks and focused git diff/whitespace checks.
Record revision and relevant concurrent-tree context. Behavioral/display
observation is deferred only where stated, and consolidated in AIR-V.

Before measurement, preserve a small reproducible fixture corpus and executable
legacy-policy compatibility strategy during the AI extraction. This is limited
local regression scaffolding, not tournament infrastructure. Record source and
configuration identity. Exact refactor parity applies only to the compatibility
strategy; deliberate candidate/ranking changes get new expectations.
Do not imply that this weak legacy policy proves broad AI strength.

The later experiment manifest declares budgets, acceptance thresholds, tuning
and held-out sets before held-out results are read. Core state/AI work does not
wait for tournaments. Local correctness and performance evidence remain required.

## Items

### AIR-1 - Make battle state complete and persistence lossless

**Model:** Opus 5 / GPT Sol

**Model rationale:** State is spread across entities, catalogs, resolvers and
history. Deciding what can affect future resolution, what is immutable, and how
to restore it without changing combat is a cross-layer ownership problem.

**Depends on:** None.

**Touches:**
- src/battle_sim/** (state, serialization, mutation/revision and replay contracts)
- src/entities/Monster.gd, src/entities/Spell.gd, src/entities/PassiveSkill.gd
- src/factories/MonsterFactory.gd, src/factories/SpellFactory.gd, src/factories/PassiveSkillFactory.gd
- src/entity_ai/StateRevision.gd
- scripts/battle/checks/probe_state_contract.gd and .uid (new)
- scripts/battle/fixtures/ai/state_contract.json (new)
- scripts/hex_battle/probe_replay.gd
- scripts/checks/probes/ai_rework.json (new)
- scripts/hex_battle/run_probe.ps1, scripts/checks/run_probe_sweep.ps1 (only if narrow probe diagnosis requires them)
- docs/AI_ARCHITECTURE.md, docs/ARCHITECTURE.md, docs/DEVELOPMENT.md

**End state:** An explicit state inventory is implemented and documented.
Catalog definitions cannot be changed by a live effect or detached copy.
Supported runtime ability/effect changes survive restoration and produce the
same subsequent outcomes. RNG state and unrestricted integer identities survive
disk serialization exactly. Schema/build compatibility errors are explicit.
Cheap mutation revision and timeline identity are distinguished from semantic
fingerprints; supported board/effect changes invalidate stale work.

**Implementation:** Judge immutable definitions plus state-owned modifiers
against existing entity APIs. Repair omissions through one canonical snapshot
contract; avoid independent forecast and rewind serializers. Separate the
conceptual ownership of rules memory, replay ledger and telemetry, preserving
damage reversal. Inventory currently transient resolver data and specify safe
snapshot boundaries. Future fields must declare persistence and invalidation
obligations. Establish a narrow runnable probe and diagnose failures without
rebuilding the placeholder tournament. Explain schema compatibility and mutation
coverage in the commit body; update the AI reference's state/determinism sections.

**Risk:** Comparing two incomplete serializations can falsely pass. Probe
independent runtime changes and future action results, including modified ability
properties/loadouts, cooldowns, effects, terrain, withdrawal, allocation and RNG.
Do not infer cross-platform guarantees from one Windows run.

**Validation:**
- Self-contained: run powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter state_contract and the same command with -Filter replay. The state probe performs lossless disk round trips with large integer cases, fresh-process continuation, mutation invalidation, and independent behavioral assertions.
- Self-contained: check the state inventory against resolver reads, documentation links, focused owned diff, and git diff --check -- <owned paths>.

### AIR-2 - Share isolated forecasts and technical checkpoints

**Model:** Opus 5 / GPT Sol

**Model rationale:** Forecast cost, rule-relevant history, live-state isolation,
random information access and rewind branches meet at one boundary. Choosing a
fork/storage strategy and atomic restore semantics requires architectural judgment.

**Depends on:** AIR-1.

**Touches:**
- src/battle_sim/**
- src/entity_ai/OutcomeEstimator.gd and .uid (new)
- src/entities/Monster.gd, src/entities/Spell.gd, src/entities/PassiveSkill.gd
- src/presentation/BattleRecordAdapter.gd
- scripts/battle/checks/probe_forecast.gd and .uid (new)
- scripts/battle/checks/probe_rewind.gd and .uid (new)
- scripts/battle/fixtures/ai/forecast_cases.json (new)
- scripts/hex_battle/probe_replay.gd
- scripts/checks/probes/ai_rework.json
- docs/AI_ARCHITECTURE.md, docs/ARCHITECTURE.md, docs/DEVELOPMENT.md

**End state:** Detached resolution and side-start checkpoints share the complete
state contract. A typed forecast reports outcome deltas, acceptance/resolution,
horizon, uncertainty mode and cost. Debug-exact and policy-safe chance treatments
are separate. Live state, RNG, catalog objects, allocator, history and events
are unchanged by forecasts. A headless technical restore records an immutable
outer branch operation, increments generation, and replays with first-divergence
fingerprints. This is usable before the new policy or tournament exists.

**Implementation:** Choose clone, structural sharing or copy-on-write from small
and growing-history measurements; do not add reversible per-spell undo handlers.
Separate replay/diagnostic retention from sufficient rules memory. Preserve
damage reversal and bound checkpoint/cache retention explicitly. Define trigger
order and quiescent snapshot points; forbid restoring halfway through an
uncommitted resolver cascade. Reserve state storage for any introduced pending
work and fail diagnostically on runaway reactions. Decide stable chance sample
identities independent of candidate enumeration/completion order. Exact debug
RNG must not leak into ordinary policy forecasts. Document branch identity,
entity ID reuse across branches, and which metadata is deliberately not rewound.
No player-facing rewind cost or memory rule is chosen here.

**Risk:** Shallow copies mutate live abilities; full history copies make each
successive turn slower; exact RNG cloning creates an oracle AI. Restore may erase
the operation that requested it. Exercise all these cases directly.

**Validation:**
- Self-contained: run the probe sweep with -Filter forecast, -Filter rewind and -Filter replay. Cover reactive fizzles, AoE, rules-memory damage reversal, supported entity/board changes, allocation, repeated restore/continue, disk replay, and live-state/event purity.
- Self-contained: changing hidden gameplay RNG while public policy inputs and policy sample seeds stay fixed does not change policy-safe forecasts; debug-exact mode reproduces the chosen stream. Measure fork bytes/time across increasing history lengths and record declared retention/cost limits.
- Self-contained: audit AI reference, owned diff and git diff --check -- <owned paths>.

### AIR-3 - Optimize hex queries against independent correctness evidence

**Model:** Opus 5 / GPT Sol

**Model rationale:** Faster geometric enumeration must preserve supercover ties,
heights, weighted paths and deterministic predecessors. Selecting a cache or
frontier representation requires profiling and geometric reasoning.

**Depends on:** AIR-1.

**Touches:**
- src/algorithms/LineOfSight.gd, src/algorithms/HexReachability.gd, src/algorithms/AStarPathfinder.gd
- scripts/hex_battle/probe_spatial.gd, scripts/hex_battle/probe_grid.gd
- scripts/hex_battle/fixtures/spatial/weighted_graph.json
- scripts/hex_battle/fixtures/spatial/los_golden.json (new)
- scripts/battle/checks/probe_spatial_cost.gd and .uid (new)
- scripts/checks/probes/ai_rework.json
- docs/AI_ARCHITECTURE.md, docs/ARCHITECTURE.md

**End state:** Authoritative hex queries preserve intended rules on hand-derived
edge cases, reversal/translation properties, and weighted traversal fixtures.
Old output is regression evidence, not the sole correctness oracle. Retained
optimizations have measured time/query/memory benefit on representative sizes.
Caches have finite retention and dynamic occupancy/height cannot leak into
static geometry templates.

**Implementation:** Consider displacement-keyed ray templates and a narrower
supercover enumerator; preserve touched cells, tie order, endpoint semantics
and exact blocker checks. Compare current linear frontier scans with heap or
bounded-integer bucket alternatives where applicable. Keep one reachability
search per relevant actor/revision, rather than A* per destination. Expose costs
needed for later approach evaluation; this spatial item does not change policy
ranking. Hex-distance A* heuristics require a valid lower bound;
document a safe fallback for future portals or cheaper traversal. Record
rejected optimizations and algorithm complexity in the AI reference.

**Risk:** Preserving an old bug is not correctness; silently changing disputed
geometry is not an optimization. A rules ambiguity blocks that change pending a
user decision, while unrelated proven optimizations may proceed.

**Validation:**
- Self-contained: run the probe sweep with -Filter spatial and -Filter grid. Capture unchanged output before edits, add independent corner/edge/height/occupancy cases, and check reachability costs and stable paths.
- Self-contained: report workload identity and geometry/frontier/cache costs; audit owned diff, AI algorithm documentation and git diff --check -- <owned paths>.

### AIR-4 - Separate legal candidates, compatibility policy and shared queries

**Model:** Opus 5 / GPT Sol

**Model rationale:** Current classes mix actor priority, pruning, deduplication
and scoring. Extracting legal enumeration without silently redefining the old
policy needs explicit action semantics and ownership of caches and observations.

**Depends on:** AIR-2 and AIR-3.

**Touches:**
- src/entity_ai/** (including any namespaced legacy compatibility strategy)
- src/battle_sim/BattleSimulator.gd, src/battle_sim/BattleCommand.gd
- src/battle_sim/CombatResolver.gd, src/battle_sim/ReachQuery.gd
- scripts/hex_battle/probe_ai.gd
- scripts/battle/checks/probe_fuzz.gd
- scripts/battle/checks/probe_candidates.gd and .uid (new)
- scripts/battle/fixtures/ai/legacy_decisions.json (new)
- scripts/battle/fixtures/ai/candidate_cases.json (new)
- scripts/checks/probes/ai_rework.json
- docs/AI_ARCHITECTURE.md, docs/MODULE_MAP.md, docs/ARCHITECTURE.md

**End state:** One revision-scoped read-only decision context serves all ready
actors. Legal action enumeration, candidate filtering, scoring and policy
selection have distinct interfaces. Candidates carry canonical actor, command,
path/footprint identity and deterministic tie order. All supported legal action
classes are represented, including Wait and empty-cell effects. A namespaced
executable legacy strategy preserves old actor priority, destination cap and
selection behavior on frozen local fixtures; it can later act as a comparison
opponent. The new stream does not promise legacy decision parity.

**Implementation:** Choose typed boundaries with policy observation/information
access explicit; full information is currently allowed except upcoming RNG.
Use authoritative resolvers, not AI copies of legal rules. Define finite action
equivalence: alternate routes and centers may collapse only when their supported
effects are equivalent, with an extension rule for future tile-entered triggers.
Separate complete legal enumeration from bounded policy subsets. Define random
sampling over that abstraction and measure action-class coverage, rather than
claiming all possible paths are uniform. Add policy/configuration identity and
reject unknown IDs; preserve the legacy executable behavior without maintaining
a second simulator. Queries are keyed by semantic inputs and revision/generation;
debug fingerprints verify invalidation instead of serializing all actors per
rendered slice. Update actual entry points and extension obligations in the AI doc.

**Risk:** Stale terrain queries, over-aggressive deduplication and misleading
random coverage can all pass outcome-only tests. Early pruning can remove new
mechanics before forecasting sees them. Keep an explicit unsupported-feature
fallback or deterministic exploration allowance.

**Validation:**
- Self-contained: run the probe sweep with -Filter candidates, -Filter ai and -Filter fuzz. Check completeness against small exhaustive legal fixtures, legacy command parity, stale generation rejection, and live state/RNG/event purity.
- Self-contained: compare uninterrupted and differently sliced decisions, verify unknown-policy rejection, inspect links/owned diff and git diff --check -- <owned paths>.

### AIR-5 - Add bounded danger with honest tactical semantics

**Model:** Opus 5 / GPT Sol

**Model rationale:** Useful danger depends on legal reply timing, occupancy,
area effects and competing enemy actions. Sparse and batched algorithms trade
work differently; both semantics and measured cost require judgment.

**Depends on:** AIR-4.

**Touches:**
- src/entity_ai/**
- src/algorithms/ThreatMap.gd
- src/battle_sim/CombatResolver.gd, src/battle_sim/ReachQuery.gd
- scripts/hex_battle/probe_ai.gd
- scripts/battle/checks/probe_danger.gd and .uid (new)
- scripts/battle/fixtures/ai/danger_cases.json (new)
- scripts/checks/probes/ai_rework.json
- docs/AI_ARCHITECTURE.md, docs/MODULE_MAP.md

**End state:** Commander safety, useful-heal decisions and positional ranking
consume one danger contract. It distinguishes an individual reply, a conservative
bound and a feasible side continuation. Query budgets, approximation status and
cache retention are explicit. Sparse candidate queries or shared batches are
chosen from workload evidence; no absolute full-board prohibition substitutes
for a resource limit.

**Implementation:** Use conservative hex/movement/range/area/height bounds before
exact legality and LoS. Model pre-move magic, remaining actions, projected
occupancy and blockers. Do not sum mutually exclusive best attacks as an exact
prediction. New effect/traversal capabilities without a proven bound use a safe
fallback. Compare the current threat-disabled policy, the cost of old exhaustive
work, and a small exact current-rules oracle separately; none alone establishes
quality and speed. Document the break-even reasoning, treatment of uncertainty,
and known blind spots.

**Risk:** Excess danger stalls play; missed danger produces suicidal movement;
repeated sparse queries can cost more than shared batches. Current disabled
threat may be faster than the new useful calculation, legitimately.

**Validation:**
- Self-contained: run the probe sweep with -Filter danger and -Filter ai. Compare bounded queries to exhaustive current-rules cases, including AoE, pre-move spells, occupancy changes and competing replies.
- Self-contained: measure sparse/dense workloads and memory/cost counters; verify no unsupported mechanic is rejected by an unsound bound; check docs, owned diff and git diff --check -- <owned paths>.

### AIR-6 - Build coordinated side policy with deterministic search

**Model:** Opus 5 / GPT Sol

**Model rationale:** Coordinated action order, setup value, terminal outcomes
and CPU character cannot be reduced to a mechanical weight migration. Search
quality must be judged against actual side scheduling and a fixed work budget.

**Depends on:** AIR-5.

**Touches:**
- src/entity_ai/**
- src/battle_sim/BattleSimulator.gd
- src/systems/hex_battle/HexBattleController.gd
- scripts/hex_battle/probe_ai.gd
- scripts/battle/checks/probe_fuzz.gd
- scripts/battle/checks/probe_side_policy.gd and .uid (new)
- scripts/battle/fixtures/ai/policy_cases.json (new)
- scripts/checks/probes/ai_rework.json
- docs/AI_ARCHITECTURE.md, docs/ARCHITECTURE.md, docs/GAME_DESIGN.md

**End state:** A compositional side policy ranks actors and commands on comparable
utility, with explicit terminal priorities, stable arithmetic/ties, fixed work
budgets and serializable configuration. Search follows the simulator's next
decision, including remaining allied actions; its documented horizon is in
decision steps or completed side turns. Headless and sliced execution agree.
Policy traces expose chosen/alternative actions, score components, pruning,
uncertainty and work. The executable legacy comparison remains available.

**Implementation:** Blocking user decision before authoring new balance-facing
CPU character/difficulty: bring local tactical examples and concrete options for
aggression, support, commander focus and risk preference. This decision does not
wait for tournaments. Choose beam/shortlist search or a simpler bounded method
based on local cases and cost. Do not insert an enemy turn before allies have
finished unless explicitly computing a labeled danger approximation. Preserve
a route to setup/delayed benefits through pruning and evaluation features;
document effects the horizon cannot understand. Evaluate approach through legal
traversal/attack positions when direct hex distance is misleading. Remove the nearest-enemy
fallback only with progress evidence. Keep policy memory explicit or remain
stateless. Each slice needs bounded work; an expensive indivisible forecast can
still stall a frame despite a slice counter. Workers are optional, require
detached inputs, and cannot change results through completion order.
Record algorithm/configuration, local budgets and limitations in the AI reference.

**Risk:** Strong-looking tactics can stall, exploit round caps or sacrifice
support. Legacy parity is not required here. Local fixtures validate behavior
and costs; broad strength remains unproven until later experiments.

**Validation:**
- Self-contained: run the probe sweep with -Filter side_policy, -Filter ai and -Filter fuzz. Cover allied setup/combinations, commander withdrawal, healing, barriers/approach, no-op repetition, horizon boundaries and slice-budget equivalence.
- Self-contained: compare policy decisions with varied hidden gameplay RNG but identical observations/policy samples; inspect deterministic explanation traces and local work/memory limits, docs and git diff --check -- <owned paths>.
- Deferred: user observes representative CPU character and frame pacing in a launched battle; AIR-V records the revision and concurrent context.

### AIR-7 - Build the later resumable experiment runner

**Model:** Opus 5 / GPT Sol

**Model rationale:** Match identity, immutable builds, process supervision,
partial recovery and unbiased failure classification are experiment-system
contracts. The old single-process placeholder is not a reliable specification.

**Depends on:** AIR-6.

**Touches:**
- scripts/battle/run_battle.gd, scripts/battle/run_championship.gd
- scripts/battle/run_policy_tournament.gd and .uid (new)
- scripts/battle/run_policy_tournament.ps1 (new)
- scripts/battle/tournament/** (new runner helpers and generated .uid files)
- scripts/battle/checks/probe_policy_tournament.gd and .uid (new)
- scripts/battle/checks/probe_battle_runner.gd, scripts/battle/checks/probe_round_cap.gd
- scripts/battle/fixtures/ai/tournament_smoke.json (new)
- scripts/checks/probes/ai_rework.json, scripts/checks/probes/battle.json
- src/battle_sim/BattleSimulator.gd
- src/presentation/BattleRecordAdapter.gd, src/presentation/BattleOutputPaths.gd
- docs/AI_ARCHITECTURE.md, docs/DEVELOPMENT.md

**End state:** A documented command runs a fixed manifest on bounded independent
process workers, resumes incomplete work without double counting, and merges
deterministic result rows in canonical match-ID order. Jobs pin actual engine,
simulation build, content, policy/configuration, setup, seeds and side assignment.
Both policies are assigned atomically and unknown names fail. Crashes, hangs,
illegal actions, elimination, draw and round-cap adjudication are distinct.
Timing/environment data stay outside deterministic result bytes. A match can
be reproduced from its identity and retained artifacts.

**Implementation:** Use canonical simulator setup/resolution. Judge reuse or
replacement of placeholder tools; preserve useful invocation compatibility only
where cheap and explicit. Pin an immutable runnable build/content artifact under
battle_output/ through BattleOutputPaths, or use an existing verified artifact;
do not launch a long experiment from concurrently changing source. Record actual
file/build hashes, not only HEAD. No new worktree is implied. Give each process
its own output shard; bound concurrency, logs and diagnostic retention. Recover
partial trailing rows, distinguish attempt ID from match ID, and verify metadata
before resume. Failed attempts remain visible even after retry. Side swaps keep
setup/seed pairs explicit; variation must include scenarios and controlled setups.
Document commands, output schema, retention, watchdog and failure recovery.

**Risk:** A resumed duplicate, silent policy fallback or skipped crash can bias
win rates. Wall-clock watchdog failures must not become game losses. A shared
working tree can change the executable halfway through an experiment.

**Validation:**
- Self-contained: run the probe sweep with -Filter policy_tournament and -Filter battle. Smoke coverage must compare one and multiple workers, repeated fresh-process output, both side assignments, unknown IDs, interrupted/resumed runs, corrupt final lines, duplicate attempts and forced crash/hang classification.
- Self-contained: inspect retained artifact identity and bounded memory/log behavior; old probes are corrected to current rules only where verified and unquarantined only after passing. Audit docs and git diff --check -- <owned paths>.

### AIR-8 - Make outcomes, ablations and costs easy to analyze

**Model:** Opus 5 / GPT Sol

**Model rationale:** Statistical units, opponent diversity, held-out evaluation,
cost/strength tradeoffs and causal attribution determine what the tournament
results actually mean. These choices are not a mechanical report layout.

**Depends on:** AIR-7.

**Touches:**
- scripts/battle/analyze_policy_tournament.gd and .uid (new)
- scripts/battle/analysis/** (new analysis helpers and generated .uid files)
- scripts/battle/tournament/**
- scripts/battle/checks/probe_policy_analysis.gd and .uid (new)
- scripts/battle/fixtures/ai/analysis_cases.json (new)
- scripts/battle/fixtures/ai/evaluation_manifest.json (new)
- scripts/checks/probes/ai_rework.json
- src/entity_ai/** (configuration/trace/ablation seams only; no concealed retuning)
- src/presentation/BattleOutputPaths.gd
- docs/AI_ARCHITECTURE.md, docs/DEVELOPMENT.md

**End state:** One documented analysis command consumes versioned result shards
and produces machine-readable aggregates, CSV and a readable report under
battle_output/. Reports show paired outcomes/uncertainty, per-scenario and
per-side results, opponent matrix, end reasons, infrastructure failures, stalls,
throughput, decision p50/p95, work counts and memory. Representative losses and
decision explanations link to reproducible match/replay artifacts. Reports
identify unsupported conclusions and effective sample units.

**Implementation:** Freeze budgets, strength/non-regression criteria and tuning/
held-out scenario allocation in the manifest before viewing held-out outcomes.
Retain deterministic configuration switches sufficient to ablate geometry cost,
candidate scope, danger and search on a common rules build; validate semantics-
preserving optimizations on fixed decisions. Legacy is one weak comparator, not
the entire league. Paired/cluster-aware intervals must respect setup and side
dependence; repeated identical matches are reproduction checks, not independent
samples. A common seed does not ensure policies consume identical random events.
Separate round-cap tallies and game balance from policy strength; include all
scheduled/failed matches in denominators with explicit estimands. Report quality
versus computation at several fixed work budgets. If held-out results trigger
tuning, declare a new experiment and fresh holdout rather than reusing it as proof.
Document formulas, sample units, limitations and analysis examples.

**Risk:** Attractive pooled win rates conceal regressions, weak-opponent exploits
and tuning leakage. Outcome correlations do not prove a technique caused the
improvement; use ablations and explanation traces together.

**Validation:**
- Self-contained: run the probe sweep with -Filter policy_analysis and -Filter policy_tournament. Hand-computable fixtures cover paired wins/losses/draws, caps, failures, unequal scenario sizes, duplicate data, deterministic resampling and degenerate intervals.
- Self-contained: run the declared evaluation manifest and analyzer; verify replay links, acceptance criteria, ablations and machine-readable/report agreement. Publish results with immutable artifact identity; audit docs and git diff --check -- <owned paths>.

### AIR-9 - Retire abandoned visual playback on restore

**Model:** Opus 5 / GPT Sol

**Model rationale:** Playback, tweens, overlays, input and pending AI can retain
the abandoned timeline. Cancellation and authoritative redraw cross lifetimes,
while existing VFX behavior must remain compatible.

**Depends on:** AIR-2 and AIR-6. Scheduled after the experiment items so they can
be used without waiting for visual rewind acceptance.

**Touches:**
- src/presentation/battle/HexBattlePlayback.gd, src/presentation/battle/HexBattleVisualAdapter.gd
- src/presentation/battle/HexBattleBoardView.gd, src/presentation/battle/HexBattleHud.gd
- src/presentation/battle/HexBattleCursor.gd, src/presentation/VisualActionQueue.gd
- src/systems/hex_battle/HexBattleController.gd
- src/battle_sim/BattleEvents.gd, src/battle_sim/IBattleVisualAdapter.gd
- scripts/hex_battle/probe_replay.gd
- scripts/hex_battle/restoration/probe_session.gd
- scripts/hex_battle/side_turn/probe_ui_guardrails.gd
- scripts/checks/probes/hex_battle.json
- docs/AI_ARCHITECTURE.md, docs/ARCHITECTURE.md, docs/UI_DESIGN.md

**End state:** State replacement retires every old generation's proposal, queued
action, interpolation, callback and input target. The authoritative restored
board is drawn and correct input resumes once. Ordinary existing animation
appearance, timing and lifecycle remain unchanged. A technical harness can
restore during movement/casting without adding a player-facing rewind control.

**Implementation:** Use generation ownership and teardown/rebuild, not inverse
VFX. Enumerate all callers of shared helpers before changing their contract.
Keep changes within the listed lifecycle surface; an unowned VFX dependency
requiring modification needs an explicit handoff, not an opportunistic edit.
Document cancellation, pause/restart and presentation responsibilities.

**Risk:** Late callbacks can advance the restored timeline; broad resets can
damage normal pacing. Preserve normal-play goldens/caller evidence.

**Validation:**
- Self-contained: run the probe sweep with -Filter replay, -Filter session and -Filter ui_guardrails; run the standard non-interactive Godot code check. Audit callback generation ownership, docs and git diff --check -- <owned paths>.
- Deferred: user observes technical restore during movement/casting/pause, resumed input, and normal playback for affected shared callers; AIR-V consolidates the evidence.

### AIR-V - Validate integration and reconcile the durable reference

**Model:** Opus 5 / GPT Sol

**Model rationale:** State isolation, tactical quality, experiments and visual
lifecycle span different boundaries. Interpreting losses and judging integrated
play needs a separate review with the predeclared acceptance criteria.

**Depends on:** AIR-1 through AIR-9.

**Touches:**
- src/battle_sim/**, src/entity_ai/**
- src/algorithms/LineOfSight.gd, src/algorithms/HexReachability.gd, src/algorithms/AStarPathfinder.gd, src/algorithms/ThreatMap.gd
- src/entities/Monster.gd, src/entities/Spell.gd, src/entities/PassiveSkill.gd
- src/factories/MonsterFactory.gd, src/factories/SpellFactory.gd, src/factories/PassiveSkillFactory.gd
- src/presentation/BattleRecordAdapter.gd, src/presentation/BattleOutputPaths.gd, src/presentation/VisualActionQueue.gd
- src/presentation/battle/HexBattlePlayback.gd, src/presentation/battle/HexBattleVisualAdapter.gd
- src/presentation/battle/HexBattleBoardView.gd, src/presentation/battle/HexBattleHud.gd, src/presentation/battle/HexBattleCursor.gd
- src/systems/hex_battle/HexBattleController.gd
- scripts/battle/**
- scripts/hex_battle/probe_ai.gd, scripts/hex_battle/probe_grid.gd, scripts/hex_battle/probe_spatial.gd, scripts/hex_battle/probe_replay.gd
- scripts/hex_battle/fixtures/spatial/weighted_graph.json, scripts/hex_battle/fixtures/spatial/los_golden.json
- scripts/hex_battle/restoration/probe_session.gd, scripts/hex_battle/side_turn/probe_ui_guardrails.gd
- scripts/hex_battle/run_probe.ps1, scripts/checks/run_probe_sweep.ps1
- scripts/checks/probes/ai_rework.json, scripts/checks/probes/battle.json, scripts/checks/probes/hex_battle.json
- docs/AI_ARCHITECTURE.md, docs/ARCHITECTURE.md, docs/MODULE_MAP.md, docs/DEVELOPMENT.md
- docs/GAME_DESIGN.md, docs/UI_DESIGN.md, docs/README.md
- BACKLOG_CRITICAL.md, BACKLOG_LONGTERM.md (append durable out-of-scope work only)
- docs/plans/battle-ai-rework.md (delete on successful closure)

**End state:** All gated probes and the standard Godot code check pass.
Lossless disk replay, forecast purity, branch restore and sliced/uninterrupted
decisions agree. Experiment resume/worker-count changes preserve deterministic
outcomes; sampled matches and every reproducible failure replay. Illegal-command
and invariant failures are zero. Performance and policy results meet the
predeclared manifest gates, with failures/caps and remaining limitations visible.
User observation accepts CPU behavior/pacing and technical restore. The durable
AI reference matches shipped code, links runnable workflows, distinguishes
unsupported capabilities, and contains no required dependency on this cycle file.

**Implementation:** Run the consolidated matrix against identified immutable
artifacts and observe the committed interactive revision with concurrent context
recorded. Fix owned defects and repeat the relevant checks; do not silently tune
held-out results or rewrite acceptance criteria. Audit the reference's module/
interface diagram, state inventory, algorithm/complexity sections, information
contract, extension guide, experiments and capability limits against code.
Move genuinely deferred work to the correct backlog and delete this cycle file
in the closing commit. Broad owned paths permit integration fixes, not new scope.

**Risk:** Local checks can pass while the integrated system drifts. Convergence
reviews and independent end-to-end evidence expose that drift; a failed gate
holds closure. Document unavailable platform/version guarantees honestly.

**Validation:**
- Self-contained: run powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 in full, then ./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --quit-after 5 --rendering-method gl_compatibility --audio-driver Dummy. Repeat the declared experiment with varied worker counts/resume, run analysis, and replay samples/failures.
- Self-contained: check all documentation links and present-tense claims, focused owned diff and git diff --check -- <owned paths>.
- Deferred: user observes representative CPU character/frame pacing, technical rewind during movement/casting/pause, correct input, and normal affected VFX playback; record revision and relevant concurrent changes in one consolidated report.

## Deliberately excluded and capability limits

- No player-facing rewind spell, cost, targeting, usage count or lore. Technical
  restore is proven; gameplay rules for persistent costs/memory require design.
- No new movement types, portals, terrain rules, combat stats or victory rules.
  Future mechanics must declare legal actions, state, triggers and evaluation
  obligations; generic deltas do not automatically produce strategic understanding.
- No learned-policy training, broad MCTS adoption, multiplayer rollback,
  distributed cluster service, or fog-of-war gameplay. Explicit observation and
  experiment seams support later work without claiming those capabilities now.
- No arbitrary cross-version/platform replay promise. Validate each supported
  compatibility set; adopting a fixed RNG/numeric model is a separate decision
  if guarantees beyond the pinned engine/build are required.
- Large battles remain bounded by reachable cells, action branching, history,
  fork cost and memory. Profile sizes and fixed budgets; do not claim unlimited
  scale. Independent process workers are the first parallelism axis.
- Do not rehabilitate the old tournament placeholders before AI foundations.
  Their useful behavior may be reused later; their current schemas/performance
  are not authoritative acceptance gates.
- Do not retune donor VFX or shared resources to make restore look better.

## Waves

All items update the same durable AI reference and several share simulation
paths, so this cycle intentionally uses sequential waves. Other cycles may run
on disjoint owned paths. Suggested tier for every row is Opus 5 / GPT Sol:
each item retains the concrete boundary/algorithm/experiment judgment described
in its Model rationale; no item is a mechanical specification disguised as a brief.

| Wave | Items | Dependency/ownership and validation |
|------|-------|-------------------------------------|
| 1 | AIR-1 | Complete state and local probes; no tournament prerequisite |
| 2 | AIR-2 | Forecast/checkpoint foundation after state; self-contained checks inline |
| 3 | AIR-3 | Hex queries; convergence review after the third implementation item |
| 4 | AIR-4 | Candidate/context extraction and executable legacy strategy |
| 5 | AIR-5 | Danger queries on the new contracts |
| 6 | AIR-6 | Side policy; convergence review after the sixth implementation item |
| 7 | AIR-7 | Later experiment runner after policy foundations |
| 8 | AIR-8 | Analysis and predeclared evaluation; usable before visual rewind |
| 9 | AIR-9 | Presentation restore; experiment tools do not depend on it |
| 10 | AIR-V | Standalone consolidated deferred validation and cycle closure |

Convergence reviews are implicit execution substeps, not new items or mutable
status files. AIR-6's authored CPU behavior decision is explicitly blocking;
ordinary technical implementation choices are not. No implementation session
edits this plan once execution begins.
