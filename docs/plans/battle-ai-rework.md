# Battle AI rework

Opened 2026-09-20. Rebuild CPU decision-making for the approved hex side-turn
battle, with reproducible headless evidence before policy changes and a rollback
boundary that can support future time-manipulating effects. This cycle changes
AI algorithms, their headless measurement tools, and the minimum generic
simulation/presentation contracts needed to prove a whole-side-turn rewind. It
does not author a rewind spell, set its cost, add lore, or change confirmed
movement, combat, terrain, or side-turn rules. Execute on the checked-out branch;
no plan branch is requested. Items sharing paths are sequential lanes, with one
commit and `Plan-Item: AIR-<n>` trailer per item. The cycle file freezes as soon
as AIR-1 starts; findings and benchmark numbers go in commit bodies and generated
`battle_output/`, not back into this file.

## Outcome

- One side-level CPU policy chooses an eligible actor and a simulator-legal
  command from shared hex movement and combat queries. Role differences are data
  consumed by that policy; unknown policy IDs fail explicitly.
- Threat and useful-heal estimates account for plausible enemy replies without
  building the old full-board threat map for every unit decision. Exact hex
  movement and symmetric supercover line of sight remain authoritative.
- A shortlist can be forecast through an isolated simulation fork. A technical
  whole-side-turn checkpoint can be restored through `BattleSimulator`, replayed
  as a branch operation, and displayed without stale AI work or visual actions.
- One command runs paired, side-swapped policy tournaments over a versioned set
  of scenarios and seeds. Deterministic match records, separate timing summaries,
  invariants, replay checks, and cost counters show whether each technique
  improved play and throughput.

## Present-state facts an executing agent must not "fix"

- `CommandDeliberation._stepSetup()` currently sets an empty `_threat` and goes
  directly to candidates. The costly `ThreatMap` remains available to probes,
  but is not the current CPU decision path. Older `docs/DEVELOPMENT.md` timings
  describe a policy that did compute threat. Do not call them a current baseline.
- `HexGrid` already owns odd-column offset/axial conversion and deterministic
  neighbour order. Hex distance is already the A* lower bound. `HexReachability`
  already handles weighted movement, height, occupancy, and zone-of-control
  through `MovementResolver` callbacks. Re-evaluate measured costs and preserve
  legal paths; a new hex-only pathfinder is not an assumed requirement.
- Magic is pre-move, side turns may select any ready unit, and commander defeat
  can withdraw a party. Candidate generation and forecasts must respect those
  approved rules rather than score commands the simulator will normalize away.
- `RandomLegalBrain` is a coverage fuzzer, not a strength baseline. It seeds a
  private generator from battle position because drawing `BattleState.rng` during
  pure deliberation makes the proposal stale. Records and replay must identify
  policy and engine versions; Godot RNG streams are not promised across engine
  versions.
- `BattleStateSerializer` captures RNG, IDs, effects, positions, and side-turn
  state; `BattleReplayRunner` already replays operations. A rewind must still
  preserve the operation that caused the branch and invalidate abandoned work.
  The existing movement Undo is narrower than this technical rewind.
- The 2026-09-20 attempt to get a fresh headless AI timing crashed in Godot 4.4
  with signal 11 before a probe marker. `scripts/checks/probes/battle.json` also
  has two quarantined probes. AIR-1 is a blocking evidence gate: no later item
  may claim a speed or policy improvement from the old profile or a zero exit
  without the expected marker.
- Several other cycles still have files under `docs/plans/`. Before each item's
  first edit, check whether another running item currently owns any of its
  `Touches` paths. Coordinate that actual overlap; a dirty tree or another open
  cycle alone is no reason to wait. All battle artifacts go to `battle_output/`.

## Items

### AIR-1 — Establish a runnable, reproducible baseline

**Model:** Opus 5 / GPT Sol

**Model rationale:** A headless crash before the marker and two quarantined
battle probes have different possible causes. Distinguishing host startup,
probe drift, and simulation defects requires diagnosis and a judgment about
which existing assertion is authoritative before any benchmark is credible.

**Depends on:** None.

**Touches:**
- `scripts/hex_battle/run_probe.ps1`
- `scripts/checks/run_probe_sweep.ps1`
- `scripts/checks/probes/battle.json`
- `scripts/battle/checks/probe_battle_runner.gd`
- `scripts/battle/checks/probe_round_cap.gd`
- `scripts/battle/run_battle.gd`
- `src/presentation/BattleRecordAdapter.gd`
- `src/battle_sim/BattleSimulator.gd`
- `scripts/hex_battle/fixtures/spatial/los_golden.json` (new)
- `scripts/battle/fixtures/ai/baseline_manifest.json` (new)
- `docs/DEVELOPMENT.md`

**End state:** A headless run requires an explicit success marker, produces two
byte-identical records for one seed in the same process, and reports a current
CPU-vs-CPU timing and policy/result fingerprint for each baseline scenario.
Both battle probes pass and are unquarantined without weakening their
assertions. If a verified blocker outside `Touches` prevents this, AIR-1 remains
incomplete and later waves do not start. The golden fixture
captures current supercover cells and height-aware visibility for bounded
hex cases before AIR-3 changes geometry. No later performance claim uses an
unmarked or crashing process as a measurement.

**Implementation:** Find why the local Godot invocation crashed before output;
compare the probe wrapper with the direct runner and record the exact revision,
engine, scenario, seed, marker, exit status, and unrelated in-flight context.
Repair only within `Touches`. Preserve the real record schema and whole-round
cap rules; a probe expecting retired `party_id` or party activations should be
updated to the confirmed side-turn contract only after the source result is
checked. Generate the LoS oracle from the unchanged algorithm. Decide a small
repeatable baseline matrix and record its identity and timings in this item's
commit body. If the cause requires another path, stop this item at that boundary
and arrange explicit ownership before proceeding; do not broaden the edit.
Explain diagnosis and benchmark conditions in the commit body.

**Risk:** A startup crash could be environmental, and changing a probe to pass
could conceal a runtime bug. Repeat the same-process record check and require
the marker plus zero exit status. No performance work depends on this item until
its evidence gate passes.

**Validation:**
- Self-contained: run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter battle`; run the baseline manifest twice with the Godot 4.4 headless runner, compare record bytes, inspect the owned diff, and run `git diff --check -- <owned paths>`. Unquarantine only a probe that passes.

### AIR-2 — Add paired policy tournaments and compact result analysis

**Model:** Opus 5 / GPT Sol

**Model rationale:** The existing championship varies seeds in one scenario,
while critical hits are nearly the only source of variation. A useful policy
comparison needs two policy identities, both team assignments, controlled setup
variety, a resumable corpus, and statistics whose meaning survives draws and
round-cap tallies. That is an experiment-design and runner-contract decision.

**Depends on:** AIR-1.

**Touches:**
- `scripts/battle/run_battle.gd`
- `scripts/battle/run_championship.gd`
- `scripts/battle/run_policy_tournament.gd` and generated `.uid` (new)
- `scripts/battle/checks/probe_policy_tournament.gd` and generated `.uid` (new)
- `scripts/battle/fixtures/ai/tournament_smoke.json` (new)
- `scripts/checks/probes/battle.json`
- `src/battle_sim/BattleSimulator.gd`
- `src/presentation/BattleRecordAdapter.gd`
- `docs/DEVELOPMENT.md`

**End state:** A manifest fixes scenario and variant IDs, seeds, policy A/B IDs,
engine/ruleset/content identity, and both side assignments. The runner emits
one deterministic compact JSONL row per completed match under
`battle_output/championships/`, flushes each row, and emits a separate timing
summary. It refuses unknown policy names and player-controlled scenarios.
Reports separate elimination, round-cap, draw, side, scenario, illegal-command,
and invariant counts; paired comparisons include uncertainty intervals. A
failure retains the seed and a detailed record/replay reference. Two identical
invocations produce identical deterministic rows.

**Implementation:** Reuse `run_battle`'s setup and event-record path rather than
copying battle rules into the tournament. Give the runner a validated way to
assign both policies to teams before adapters connect; replace the silent
unknown-brain fallback at that boundary. Pair A-vs-B and B-vs-A on every setup
and seed. Keep timing and environment measurements out of deterministic rows.
Use `RandomLegalBrain` only for fuzz coverage, never as the strength opponent.
Record how variants are generated or enumerated so a particular match can be
reconstructed. Choose a compact schema that does not duplicate the full
`BattleRecordAdapter` observation on every summary row, and explain the pairing
and interval calculation in the commit body.

**Risk:** A mislabeled policy, first-side advantage, or differing content can
produce a convincing but false win rate. The smoke probe uses identical policies
on both labels and checks side swapping, manifest identity, byte equality,
failed-policy rejection, and completed-line retention after a forced failure.

**Validation:**
- Self-contained: run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter policy_tournament`; run the smoke manifest twice, compare deterministic JSONL bytes, then inspect the owned diff and run `git diff --check -- <owned paths>`.

### AIR-3 — Re-evaluate exact hex spatial algorithms against cost

**Model:** Opus 5 / GPT Sol

**Model rationale:** Symmetric supercover with height and occupied blockers is a
gameplay contract, while its current disc scan is a plausible cost hotspot.
Choosing ray templates, a narrower enumerator, or a data-structure change
requires measured benefit and proof of exact geometric equivalence. Weighted
reachability and A* must be audited without assuming replacement is needed.

**Depends on:** AIR-1.

**Touches:**
- `src/algorithms/LineOfSight.gd`
- `src/algorithms/HexReachability.gd`
- `src/algorithms/AStarPathfinder.gd`
- `scripts/hex_battle/probe_spatial.gd`
- `scripts/hex_battle/probe_grid.gd`
- `scripts/hex_battle/fixtures/spatial/weighted_graph.json`
- `docs/ARCHITECTURE.md` (hex spatial algorithm section)

**End state:** Supercover cell order and visibility match AIR-1's oracle,
including reversed rays, edge/vertex ties, heights, and occupancy. Reachable
cells, cheapest costs, deterministic predecessors, and A* legality remain
unchanged on weighted/height/zone-of-control fixtures. The commit body records
before/after query count and time; any replacement is retained only when it
improves the measured workload. Hex distance remains admissible for the active
movement contract, with an explicit fallback rule if future traversal can
beat the minimum per-step cost.

**Implementation:** Profile the cost of `_supercoverEntries()` independently
from blocker checks and LoS memo hits. Consider a displacement-keyed geometry
template because axial translation can reuse touched-cell intervals while
blockers remain dynamic; judge memory against saved work. Inspect the current
linear frontier scans in reachability/A* and change them only if the benchmark
justifies it. Preserve `HexGrid` conversion and neighbour ordering. Explain
the chosen algorithm and rejected alternatives in the commit body.

**Risk:** A fast line that misses one touched hex silently changes spells and
AI. Golden comparisons and symmetry properties are gates; a performance win
cannot waive them.

**Validation:**
- Self-contained: run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter spatial` and `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter grid`; compare the immutable AIR-1 LoS oracle, run the focused benchmark, inspect the owned diff, and run `git diff --check -- <owned paths>`.

### AIR-4 — Give the whole side one legal candidate stream and query context

**Model:** Opus 5 / GPT Sol

**Model rationale:** `CommandDeliberation`, `BattleCommandEvaluator`, role brains,
and `PartyCommandDeliberation` currently divide enumeration, scoring, and unit
selection across mutable cursors. The new boundary must retain pure,
worker-safe decisions and command parity while sharing expensive queries
across ready members. This is an ownership and extraction problem.

**Depends on:** AIR-2 and AIR-3.

**Touches:**
- `src/entity_ai/**`
- `src/battle_sim/CombatResolver.gd`
- `src/battle_sim/ReachQuery.gd`
- `src/battle_sim/BattleSimulator.gd`
- `scripts/hex_battle/probe_ai.gd`
- `scripts/battle/checks/probe_fuzz.gd`
- `docs/ARCHITECTURE.md` (AI ownership section)
- `docs/MODULE_MAP.md` (AI dependency section)

**End state:** One side-scoped, immutable-revision decision context exposes a
deterministically ordered stream of simulator-legal `(actor, command, resolved
footprint)` candidates. All ready units share caches for authoritative movement,
LoS, and action queries. Candidate generation models magic before movement,
commander status, and empty-cell effects. The normal policy gives the same
commands as the old evaluator on frozen reference cases before AIR-7 changes
ranking; `RandomLegalBrain` samples the full stream, including Wait, with no
live-state or `BattleState.rng` mutation. A stale context never applies a
proposal, including after a future timeline change.

**Implementation:** Decide typed candidate/context boundaries and cache keys
from the state fields each query reads. A cache lives only for one immutable
state revision; avoid passing a live mutable resolver across a rollback. Use
existing `MovementResolver`, `CombatResolver`, and `ReachQuery` as the rules
sources. Replace affected-target-only spell deduplication with semantic
equivalence or retain distinct centers until the resolver can prove them
equivalent. Preserve synchronous headless and worker-driven interactive
answers. Record the ownership decision and the parity evidence in the commit
body.

**Risk:** A cache scoped too broadly returns a legal action for an older board;
a cache scoped per unit repeats the cost this item is meant to remove. Probe
state purity, revision invalidation, candidate coverage, and worker/synchronous
equality.

**Validation:**
- Self-contained: run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter ai` and `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter fuzz`; compare frozen decisions and state/RNG hashes before and after repeated queries, inspect the owned diff, and run `git diff --check -- <owned paths>`.

### AIR-5 — Forecast a shortlist through isolated simulation

**Model:** Opus 5 / GPT Sol

**Model rationale:** Today's hand-authored damage/utility estimate misses
reactions and future effect kinds. A generic fork of the canonical simulator
could forecast them, but full clones for every candidate would be expensive and
could leak events, RNG draws, or mutable catalog objects into live play. The
session must choose the smallest safe fork and its outcome projection.

**Depends on:** AIR-4.

**Touches:**
- `src/battle_sim/BattleSimulator.gd`
- `src/battle_sim/BattleState.gd`
- `src/battle_sim/BattleStateSerializer.gd`
- `src/battle_sim/BattleEvents.gd`
- `src/battle_sim/BattleCommandResult.gd`
- `src/battle_sim/CombatResolver.gd`
- `src/battle_sim/SpellEffectResolver.gd`
- `src/battle_sim/PassiveSkillResolver.gd`
- `src/battle_sim/BattleForecast.gd` and generated `.uid` (new)
- `src/entity_ai/OutcomeEstimator.gd` and generated `.uid` (new)
- `scripts/battle/checks/probe_forecast.gd` and generated `.uid` (new)
- `scripts/checks/probes/battle.json`
- `docs/ARCHITECTURE.md` (forecast boundary)

**End state:** A candidate shortlist can be executed against a detached state
and produce a typed, AI-readable delta: actor/target survival, HP, effects,
position, board and terrain changes, spawned or removed entities, commander
withdrawal, resource/cooldown and turn state, plus accepted versus resolved
result. The live state, RNG state, history, ID allocator, events,
and presentation remain byte-identical before and after any forecast. New
resolver-handled effects appear in the delta without a new spell-specific AI
branch. The runner records forecast cost and caps the number of detailed forks
per decision.

**Implementation:** Judge snapshot clone, copy-on-write, and resolver dry-run
strategies against the actual candidate size measured in AIR-1/AIR-4. Resolve
the actor command through canonical validation in the fork, with isolated RNG
and event capture. Keep a cheap estimate for initial filtering, then forecast
only a deterministic shortlist. Do not make a forecast look exact if it omits
opponent actions or random branches; name its horizon and RNG treatment in its
result. Explain the fork design and cost in the commit body.

**Risk:** Shallow copies can mutate the live battle; a very accurate but
unbounded fork can make tournaments unusable. Probe reactive fizzles, AoE,
statuses, commander withdrawal, empty-cell effects, RNG restoration, and
forecast budget.

**Validation:**
- Self-contained: run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter forecast` and `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter replay`; compare live-state serialization before/after forecasts, inspect the owned diff, and run `git diff --check -- <owned paths>`.

### AIR-6 — Replace full-map threat work with bounded danger queries

**Model:** Opus 5 / GPT Sol

**Model rationale:** The old exhaustive map is prohibitively expensive and the
current empty map removes threat from play and heal decisions. An on-demand
query must decide which enemy replies are plausible, what danger means under
whole-side turns, and when an exact forecast is worth its cost. That is both
algorithm and tactical semantics, not a simple cache change.

**Depends on:** AIR-5.

**Touches:**
- `src/entity_ai/**`
- `src/algorithms/ThreatMap.gd`
- `src/battle_sim/CombatResolver.gd`
- `scripts/hex_battle/probe_ai.gd`
- `docs/ARCHITECTURE.md` (AI danger section)
- `docs/MODULE_MAP.md` (ThreatMap ownership section)

**End state:** The side planner queries danger only for candidate destinations
and relevant ally cells. Cheap hex distance, movement, range, height, and
castability bounds reject impossible replies before exact LoS and forecast
queries. Results distinguish the strongest single ready enemy reply from a
plausible combined-side estimate; useful-heal gating and commander safety read
the same result. The legacy full-map query remains correct for its explicit
inspection callers or is migrated with those callers in this item. CPU
decisions never invoke a full-board threat build. Query counts, cache hits,
time, and memory are reported against AIR-1's workload.

**Implementation:** Decide conservative bounds from authoritative resolver
queries; do not clone their rules in AI. Use a stable enemy order and scoped
memo. Be explicit about whether a hypothetical destination alters occupancy,
zone of control, or blockers before forecasting a reply. Keep estimates honest
when several enemies cannot all make their theoretical best attack in one side
turn. Explain the danger semantics and any approximation in the commit body.

**Risk:** An overestimate causes stalling; an underestimate causes suicidal
moves or late heals. Compare bounded queries against exhaustive exact answers
on small maps, and measure the large hex map separately.

**Validation:**
- Self-contained: run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter ai` and `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter spatial`; run the paired benchmark matrix with deterministic output, inspect the owned diff, and run `git diff --check -- <owned paths>`.

### AIR-7 — Replace role brains with a side-level policy and short lookahead

**Model:** Opus 5 / GPT Sol

**Model rationale:** Action order, commander targeting, safe approach, support
value, and attack trades are interdependent choices across a whole side. A
policy must make scores comparable across roles and decide how much opponent
response search the measured budget allows. This changes gameplay judgment and
cannot be specified as mechanical weight tuning.

**Depends on:** AIR-6.

**Touches:**
- `src/entity_ai/**`
- `src/battle_sim/BattleSimulator.gd`
- `scripts/hex_battle/probe_ai.gd`
- `scripts/battle/checks/probe_fuzz.gd`
- `scripts/battle/fixtures/ai/policy_cases.json` (new)
- `docs/ARCHITECTURE.md` (AI policy section)
- `docs/GAME_DESIGN.md` (approved AI behavior, if a user decision changes it)

**End state:** A deterministic side policy chooses actor and command in one
comparable ranking. Terminal victory and commander withdrawal are represented
explicitly; ordinary utility uses stable integer or fixed-point arithmetic
and a total tie key. A bounded one-response lookahead is applied only to a
shortlist, with a documented budget. Role variation is compositional data,
not independent subclasses with incomparable score scales. The nearest-enemy
emergency fallback is removed only when fixtures prove progress without it.
Unknown policy IDs fail closed. Policy A/B tournament results, per-scenario
outcomes, uncertainty, cost, and representative losses are in the commit body.

**Implementation:** Blocking user decision before changing balance-facing
behavior: agree on desired CPU character/difficulty and which tradeoffs matter
most (commander focus, survival, aggression, support). Use the AIR-2 tournament
and AIR-6 danger evidence to propose those choices concretely; do not invent
new authored balance values. Decide lexicographic priorities versus calibrated
utility and the shortlist/search budget. Keep command validation and actual
resolution in the simulator. Explain the chosen ranking, rejected approaches,
and losses the new policy still makes in the commit body.

**Risk:** A policy can win aggregate matches while stalling on one map, exploiting
the round cap, or abandoning useful support. Compare paired side-swapped results
by scenario and end reason; require zero illegal commands and replay drift.

**Validation:**
- Self-contained: run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter ai` and `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter fuzz`; run AIR-2's paired policy suite against the frozen baseline and report match outcomes and cost, inspect the owned diff, and run `git diff --check -- <owned paths>`.
- Deferred: observe the CPU's pacing and representative decisions in a launched battle; exact acceptance is consolidated in AIR-V.

### AIR-8 — Restore a whole side turn as a replayable timeline branch

**Model:** Opus 5 / GPT Sol

**Model rationale:** A rollback must restore far more than positions and HP,
while preserving an outer record of the branch that caused the restoration.
RNG, IDs, withdrawal, clocks, pending moves, worker proposals, and replay
identity create a cross-layer state boundary. The correct checkpoint and ledger
ownership require architectural judgment.

**Depends on:** AIR-5 and AIR-7.

**Touches:**
- `src/battle_sim/BattleSimulator.gd`
- `src/battle_sim/BattleState.gd`
- `src/battle_sim/BattleStateSerializer.gd`
- `src/battle_sim/BattleReplayRunner.gd`
- `src/battle_sim/BattleEvents.gd`
- `src/battle_sim/IBattleVisualAdapter.gd`
- `src/battle_sim/BattleCheckpoint.gd` and generated `.uid` (new)
- `src/presentation/BattleRecordAdapter.gd`
- `scripts/hex_battle/probe_replay.gd`
- `scripts/battle/checks/probe_rewind.gd` and generated `.uid` (new)
- `scripts/checks/probes/battle.json`
- `docs/ARCHITECTURE.md` (checkpoint and replay section)

**End state:** A headless technical command checkpoints the start of one side
turn, resolves ordinary actions, restores that checkpoint atomically through
`BattleSimulator`, and records one branch operation in an immutable outer
ledger. State serialization after restore matches the checkpoint for gameplay
fields including RNG and allocation, except for explicitly non-rewindable
timeline metadata. A monotonic generation invalidates caches and in-flight AI
proposals from the abandoned future. Replay executes the branch operation,
matches each post-operation fingerprint, and continues deterministically.
This item does not add a spell or decide who pays for one.

**Implementation:** Decide checkpoint granularity and bounded retention from
AIR-5's clone measurements. Separate rewindable battle state from the outer
operation ledger so the rewind itself survives; specify how history and event
indices are projected for comparison. Restore resolvers and brains through the
canonical simulator path, then publish one state-replaced signal. Prevent an
old worker result from matching a restored revision by accident. Record the
storage, replay, and timeline semantics in the commit body.

**Risk:** A partial restore can pass a simple HP check while leaving spent units,
withdrawn parties, effects, RNG, or ID allocation from the discarded future.
The probe compares full canonical state, then takes another action and replays
the branch twice.

**Validation:**
- Self-contained: run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter rewind` and `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter replay`; compare byte-identical branch replays, inspect the owned diff, and run `git diff --check -- <owned paths>`.

### AIR-9 — Invalidate abandoned visual playback on restore

**Model:** Opus 5 / GPT Sol

**Model rationale:** The visual queue, cursor, overlays, stage, HUD, and CPU
worker can all hold work from a timeline the simulator has abandoned. The
session must choose one restore boundary that clears those lifetimes and
re-announces the authoritative board without altering existing VFX or timing.

**Depends on:** AIR-8.

**Touches:**
- `src/presentation/battle/HexBattlePlayback.gd`
- `src/presentation/battle/HexBattleVisualAdapter.gd`
- `src/presentation/battle/HexBattleBoardView.gd`
- `src/presentation/battle/HexBattleHud.gd`
- `src/presentation/battle/HexBattleCursor.gd`
- `src/presentation/VisualActionQueue.gd`
- `src/systems/hex_battle/HexBattleController.gd`
- `src/battle_sim/BattleEvents.gd`
- `src/battle_sim/IBattleVisualAdapter.gd`
- `scripts/hex_battle/probe_replay.gd`
- `scripts/hex_battle/restoration/probe_session.gd`
- `docs/ARCHITECTURE.md` (presentation restore section)
- `docs/UI_DESIGN.md` (restore presentation behavior)

**End state:** A state-replaced event cancels or retires every queued action,
visual interpolation, overlay, cursor target, and pending CPU proposal from
the abandoned generation, then renders the restored board and opens the
correct side or player input once. No old VFX completion callback can advance
the new timeline. Existing effect appearance, timing, playback, and lifecycle
remain unchanged during ordinary battles. A technical restore harness can
exercise the transition without exposing an unfinished player-facing rewind
control.

**Implementation:** Use generation ownership rather than reversing individual
VFX. Preserve the current visual adapter/event boundary and main-thread
resolution. Inspect every caller of any shared queue or helper before changing
its contract; keep the restore path local where possible. Explain teardown,
rebuild, and callback retirement in the commit body.

**Risk:** A late tween or task callback can apply an abandoned action to the
restored board, or a broad reset can disrupt normal action pacing. Probe
restore during movement, casting, pause, and restart; compare ordinary donor
effect playback under the existing VFX compatibility rule.

**Validation:**
- Self-contained: run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter replay` and `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter session`; run the non-interactive Godot 4.4 code check in `AGENTS.md`, inspect the owned diff, and run `git diff --check -- <owned paths>`.
- Deferred: in a launched technical battle, restore during movement and a cast, then observe that the old visuals stop, the restored board is correct, and input resumes once; AIR-V consolidates this.

### AIR-V — Validate policy, performance, replay, and restore together

**Model:** Opus 5 / GPT Sol

**Model rationale:** Acceptance spans headless algorithm quality, resource
budget, replay continuity, and visual timeline correctness built in different
waves. Interpreting paired losses and judging a restored live battle need a
fresh look at the integrated result; folding this into AIR-9 would let its
implementing session grade its own cross-system behavior.

**Depends on:** AIR-1 through AIR-9.

**Touches:**
- `src/entity_ai/**`
- `src/algorithms/LineOfSight.gd`
- `src/algorithms/HexReachability.gd`
- `src/algorithms/AStarPathfinder.gd`
- `src/algorithms/ThreatMap.gd`
- `src/battle_sim/**`
- `src/presentation/BattleRecordAdapter.gd`
- `src/presentation/VisualActionQueue.gd`
- `src/presentation/battle/HexBattlePlayback.gd`
- `src/presentation/battle/HexBattleVisualAdapter.gd`
- `src/presentation/battle/HexBattleBoardView.gd`
- `src/presentation/battle/HexBattleHud.gd`
- `src/presentation/battle/HexBattleCursor.gd`
- `src/systems/hex_battle/HexBattleController.gd`
- `scripts/battle/**`
- `scripts/hex_battle/probe_ai.gd`
- `scripts/hex_battle/probe_grid.gd`
- `scripts/hex_battle/probe_spatial.gd`
- `scripts/hex_battle/probe_replay.gd`
- `scripts/hex_battle/restoration/probe_session.gd`
- `scripts/checks/probes/battle.json`
- `scripts/checks/probes/hex_battle.json`
- `docs/ARCHITECTURE.md`
- `docs/MODULE_MAP.md`
- `docs/DEVELOPMENT.md`
- `docs/GAME_DESIGN.md`
- `docs/UI_DESIGN.md`
- `BACKLOG_CRITICAL.md` (append durable open defects only)
- `BACKLOG_LONGTERM.md` (append durable deferred design work only)
- `docs/plans/battle-ai-rework.md` (delete on successful closure)

**End state:** The full gated probe sweep and Godot code check pass. Same-seed
records match byte for byte across repeated same-process and fresh-process
runs; worker and synchronous policy choices match; every sampled tournament
match replays; and invariant/illegal-command counts are zero. The side-swapped
tournament reports paired results and intervals by scenario, side, and end
reason, plus battle throughput, p50/p95 decision time, LoS calls, cache hit
rates, and peak memory against AIR-1. The policy has no unresolved repeatable
stall and meets the resource envelope chosen from AIR-1 measurements and
recorded in AIR-7's commit. A live technical rewind leaves the board, input,
and visual queue coherent. The cycle file is deleted in this item's commit.

**Implementation:** Run one consolidated correctness and performance matrix
at the committed revision, naming unrelated in-flight changes that might
affect observation. Analyze losses and round-cap results rather than reporting
only a pooled win rate. Fix defects in this item's claimed paths and rerun the
relevant consolidated checks. Do not change balance values merely to make a
win-rate number attractive. Obtain the user's interactive judgment for the
restore and representative CPU behavior. Record test identity, metrics,
limitations, and any unresolved design question in this commit body; append
only durable out-of-scope work to the appropriate backlog, then delete this
frozen cycle file.

**Risk:** Aggregates can hide first-side advantage, one-map stalls, or a
throughput regression. The scenario/side breakdown and resource counters are
part of acceptance. A failing gate holds closure.

**Validation:**
- Self-contained: run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1` and `./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --quit-after 5 --rendering-method gl_compatibility --audio-driver Dummy`; run the paired tournament manifest twice and compare deterministic rows, replay the saved sample and every failure, inspect the owned diff, and run `git diff --check -- <owned paths>`.
- Deferred: user observes representative CPU play and a technical rewind during movement and casting in the interactive hex battle; accept only after old visuals are gone and restored state/input agree.

## Waves

| Wave | Items | Why disjoint or one lane |
|------|-------|--------------------------|
| 1 | AIR-1 | Blocking evidence gate before comparisons or geometry changes |
| 2 | AIR-2, AIR-3 | Tournament runner/simulator/DEVELOPMENT vs. spatial algorithms/probes/ARCHITECTURE; no shared path |
| 3 | AIR-4 + AIR-5 | One sequential lane, one commit per item; both own AI queries and combat contracts |
| 4 | AIR-6 + AIR-7 | One sequential lane, one commit per item; danger feeds the policy and both own `src/entity_ai/**` |
| 5 | AIR-8 + AIR-9 | One sequential lane, one commit per item; restore event contract precedes visual invalidation |
| 6 | AIR-V | Standalone integrated validation and user observation across multiple waves; closes the cycle |

AIR-1 is blocking if the headless marker cannot be made reliable inside its
owned paths. AIR-7 is blocking on the stated user decision about CPU behavior;
its executing session brings tournament evidence and concrete options before
asking. AIR-V is blocking on a failing check or unaccepted interactive restore.

## Deliberately excluded

- A player-facing rewind spell, charge/cost, targeting rule, and its lore. The
  technical checkpoint proves architectural capacity; the effect's gameplay
  contract needs its own approved design and data item.
- New movement types, portals, terrain costs, spell content, stat balance, or
  victory rules. These may later use the new query and forecast boundaries.
- Training a learned model or adopting broad Monte Carlo tree search before
  the measured shortlist and one-response policy establish a useful baseline.
- Retuning existing VFX or shared presentation resources to demonstrate
  rollback. AIR-9 only retires abandoned actions and redraws authoritative
  state.
