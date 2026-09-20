# Nogg AI architecture

Status: current behavior was checked against source on 2026-09-20. The rework
contracts below are intended architecture, not a claim that the implementation
already exists. Implementation changes must update this document in the same
commit and remove obsolete current-behavior descriptions.

This is the durable reference for Nogg's AI structure, algorithms, determinism,
extension points and experiment semantics. It is not an execution log.
[Runtime architecture](./ARCHITECTURE.md) owns the general simulation and
presentation boundaries; [module map](./MODULE_MAP.md) owns directory routing;
[game design](./GAME_DESIGN.md) owns approved gameplay; [development](./DEVELOPMENT.md)
owns runnable commands. [Implementation cycles](./plans/) hold temporary
sequencing; this reference remains useful after those cycle files are removed.

## Current implementation

### Entry points and ownership

| Concern | Current owner and behavior |
|---------|----------------------------|
| Authoritative state and resolution | [BattleState](../src/battle_sim/BattleState.gd) and [BattleSimulator](../src/battle_sim/BattleSimulator.gd); AI submits commands rather than resolving its own rules |
| Actor choice | [PartyCommandDeliberation](../src/entity_ai/PartyCommandDeliberation.gd) sorts ready units by role/urgency and stable ID, then finishes after the first selected unit's deliberation |
| Candidate construction | [CommandDeliberation](../src/entity_ai/CommandDeliberation.gd) limits destinations to ten and enumerates spells from the origin because magic is pre-move |
| Evaluation | [BattleCommandEvaluator](../src/entity_ai/BattleCommandEvaluator.gd) scores candidates; brain subclasses supply role differences |
| Geometry and movement | [HexGrid](../src/board/HexGrid.gd), [HexReachability](../src/algorithms/HexReachability.gd), [AStarPathfinder](../src/algorithms/AStarPathfinder.gd), [LineOfSight](../src/algorithms/LineOfSight.gd), and canonical resolver callbacks |
| Interactive scheduling | [HexBattleController](../src/systems/hex_battle/HexBattleController.gd) advances four deterministic inner slices per rendered frame, then applies a completed proposal on the main thread |
| Headless scheduling | [run_battle](../scripts/battle/run_battle.gd) completes the same planner synchronously |
| Stale proposal detection | [StateRevision](../src/entity_ai/StateRevision.gd) builds a token from actors and selected battle fields; it is not yet the complete cheap revision/generation contract described below |
| Persistence and replay | [BattleStateSerializer](../src/battle_sim/BattleStateSerializer.gd) and [BattleReplayRunner](../src/battle_sim/BattleReplayRunner.gd); current coverage has the limitations below |
| Existing match tools | [run_championship](../scripts/battle/run_championship.gd) and [BattleRecordAdapter](../src/presentation/BattleRecordAdapter.gd); placeholders for the later experiment system |

Current decision flow:

~~~mermaid
flowchart LR
    S[Canonical battle state] --> P[Rank ready actors]
    P --> U[Deliberate first selected actor]
    U --> Q[Movement and combat queries]
    Q --> E[Score pruned candidates]
    E --> C[Actor and command proposal]
    C --> V[Simulator validates and resolves]
    V --> S
    V --> B[Events and presentation]
~~~

Interactive planning currently uses slices on the presentation thread, not a
WorkerThreadPool task. A slice count alone does not bound the cost of one slice.
Frame pacing and whole-decision latency are separate measurements. Keep command
application ordered through the simulator and never mutate state from playback.

### Current restrictions that matter

- ThreatMap still exists, but CommandDeliberation initializes an empty threat
  dictionary and skips its threat phase. Historical full-map timings do not
  describe the current policy.
- All-ready-actor comparison would change behavior. Current actor selection is
  a priority heuristic, not a global comparison of candidate scores.
- Destination pruning and affected-unit-only spell deduplication restrict the
  action space. Empty-cell/terrain effects can require distinct centers even
  when they currently affect the same units.
- RandomLegalBrain samples the existing restricted candidates. It is fuzz
  coverage, not proof of complete action coverage or an AI strength baseline.
- Serializer restoration reconstructs catalog monsters and abilities. Names do
  not capture arbitrary runtime ability-property or loadout changes.
- RNG state is a JSON number. Lossless integer persistence must be established
  before relying on disk snapshots for exact continuation.
- Full history participates in serialization. Some history is gameplay data:
  SpellEffectResolver's damage reversal reads damage since a prior turn.
- Existing championship output is not a resumable, supervised, parallel
  experiment system. Its repair is not a prerequisite for AI restructuring.

## Intended structure

The following sections specify the rework's contracts. Until implemented and
verified, they describe targets. Concrete exported symbols, schemas, algorithm
choices, limits and runnable examples must replace open design choices as they
ship. Do not describe a proposed interface as an available API.

~~~mermaid
flowchart TD
    ST[Complete simulation state and immutable content] --> DC[Read-only decision context]
    DC --> LA[Authoritative legal candidates]
    LA --> CF[Cheap bounded ranking and exploration]
    CF --> FS[Shortlist forecasts and side-aware search]
    FS --> EV[Comparable strategic evaluation]
    EV --> PR[Proposal with revision and generation]
    PR --> SIM[Canonical simulator resolution]
    SIM --> ST
    ST --> CP[Checkpoints and semantic fingerprints]
    CP --> BR[Restore and branch ledger]
    BR --> ST
    SIM --> VIS[Events and generation-owned presentation]
    EX[Later experiment runner] --> DC
    EX --> SIM
    EX --> AN[Results, traces and analysis]
~~~

### State, definitions and history

Immutable definitions describe authored content. Mutable battle state owns
everything that can affect a future legal action or result: entity properties,
runtime ability modifications, resources, cooldowns, board layers, effects,
durations, side/selection/spent/withdrawal state, allocation, gameplay RNG,
pending operations and sufficient rules memory. Future delayed effects must
declare their pending state and deterministic processing order.

A state inventory identifies every field's owner, persistence, invalidation and
restore obligation. Policy memory is explicit serializable input/output or the
policy is stateless. Shared catalog mutation, hidden singletons and runtime
object identity must not influence gameplay.

History has three responsibilities:

| Responsibility | Required behavior |
|----------------|-------------------|
| Rules memory | Retain every past fact that supported mechanics need; forecast and restore preserve its meaning |
| Replay ledger | Retain commands and timeline branch operations outside the rewindable state |
| Diagnostic telemetry | Store explanations and cost measurements without changing gameplay or being copied into every forecast |

Do not delete old events merely to reduce cloning cost if a rule still reads
them. Choose sufficient summaries, indexed immutable segments or bounded
retention only after proving the supported rules retain their information.
Measure fork cost as battle history grows.

### Legal actions and observations

The decision context is read-only and revision-scoped. Movement, targeting,
height, occupancy, zone of control, pre-move magic and command acceptance come
from canonical resolvers. Enumeration is separate from policy pruning.

Candidates expose actor, command, path/footprint identity and stable order.
Define the finite action abstraction explicitly. Routes to one destination or
spell centers with identical current occupants are equivalent only when their
supported effects are equivalent. Tile-entered effects can invalidate a
destination-only abstraction.

Policy observation access is explicit. Current gameplay has full battle
information, but ordinary policy evaluation must not inspect upcoming live RNG
outcomes. Fog of war would require filtered observations and belief handling;
that capability is not provided by naming an observation interface.

Preserve a namespaced executable compatibility strategy for local regression
and later comparisons. It retains the old actor/destination/deduplication choices.
The unrestricted candidate interface does not promise old policy decisions.
Random fuzzing names its sampling distribution and reports action-class coverage.

### Hex queries and cache lifetime

Hex topology is already supported. Optimize the actual query workload rather
than replacing algorithms because the board is hexagonal.

- Use weighted reachability to obtain movement costs and paths for an actor.
  Repeated A* for every reachable destination duplicates work.
- Evaluate linear frontier scans, heaps or bounded-cost buckets using measured
  reachable-set sizes and legal movement costs.
- A* uses an admissible lower bound. Portals or cheaper traversal require
  revisiting that bound; a safe fallback is required.
- Consider caching supercover geometry by axial displacement. Dynamic blockers,
  heights and occupancy are separate inputs, not permanent geometry.
- Check edge/vertex ties, reversed rays, translated cases and independent
  hand-derived examples. Old algorithm output is a regression reference.
- Approach utility should account for reachable attack positions when direct
  hex distance points toward an inaccessible target.

Record chosen algorithms, complexity drivers, measured workloads and memory
retention limits when implemented. Do not cache all board-cell pairs without a
demonstrated need. Query keys include all relevant semantic inputs; revision and
timeline generation protect against stale results. Diagnostic full-state hashes
verify the mutation contract rather than becoming a per-frame hot-path tax.

### Forecasting and information access

Forecasts use detached canonical state and resolvers. Their result identifies
acceptance versus resolution, material deltas, horizon, uncertainty treatment,
and work consumed. Reactive fizzles are accepted commands that later fail to
resolve, not illegal proposals.

There are two distinct uses:

- Exact debugging/reproduction can restore the recorded gameplay RNG.
- Policy evaluation uses explicit chance branches or stable independently
  seeded samples. It never consumes or peeks ahead in the live gameplay stream.

Sample identities must not depend on candidate enumeration order or worker
completion order. Changing hidden gameplay RNG while holding observations and
policy samples fixed must not change ordinary policy evaluations.

Choose cloning or structural sharing from measured cost and ownership safety.
All mutable entity/ability state must be isolated; shared immutable definitions
may be reused. Bound detailed forecast counts and storage. Increasing battle
history must not silently turn each forecast into a copy of diagnostic logs.

### Danger and coordinated search

Danger distinguishes a single reply, a conservative bound and a feasible side
continuation. Summed mutually exclusive attacks are not an exact prediction.
Projected occupancy, AoE, range, height and pre-move spell timing matter.

Sparse queries are useful when few cells matter. Shared batches can be cheaper
when many candidates ask overlapping questions. Choose based on measured work,
with explicit limits and conservative fallback for unsupported mechanics.

Search follows the simulator's actual next decision. Remaining allied actions
come before the enemy's next side turn. A bounded beam or shortlist can examine
promising allied sequences and selected replies; an immediate hypothetical
enemy attack is labeled a danger estimate rather than scheduled continuation.
Define horizon in decision steps or completed side turns.

Comparable utility separates terminal outcomes from ordinary value. Role
differences are data/strategies under the same units and tie rules. Tactical
budgets are fixed work counts; wall time can yield computation, but cannot
select a different partial answer on a faster machine. Long individual slices
still require attention for interactive responsiveness.

Cheap pruning must allow unfamiliar or delayed benefits to reach evaluation
through conservative handling or a deterministic exploration allowance.
Generic outcome deltas do not automatically teach the policy to value traps,
terrain, summons, combos or time manipulation. Document evaluator features and
horizon blind spots. Authored difficulty/personality remains a game-design choice.

### Determinism, persistence and rewind

Guarantees apply to a declared engine/build/content/configuration compatibility
set. Version state, commands, policy configuration and replay data. Persist
unrestricted integers losslessly; reject or explicitly migrate incompatible
records. Godot JSON number conversion creates a precision risk for unrestricted
integer state. [Godot JSON documentation](https://docs.godotengine.org/en/4.4/classes/class_json.html)

Godot's RNG implementation is not an across-version contract. Engine upgrades
need explicit compatibility validation; do not promise arbitrary-version replay.
[Godot RNG documentation](https://docs.godotengine.org/en/4.4/classes/class_randomnumbergenerator.html)

Stable iteration, total tie keys, fixed work budgets and deterministic reduction
order apply to the policy as well as simulation. Disk round trips, fresh
processes, and differently sliced decisions must agree. Test continued behavior
after restoration: matching incomplete snapshots is insufficient.

Checkpoint at a defined atomic boundary, with pending state included or a
quiescence requirement enforced. The branch operation survives in an outer
ledger. Restored gameplay RNG/allocation return to the checkpoint; monotonic
generation retires abandoned proposals, caches, callbacks and visual actions.
Distinguish logical state identity from branch/trace identity, including entity
ID reuse on divergent branches.

Technical restore redraws authoritative state; it does not reverse each VFX.
Normal playback compatibility must survive. A player-facing rewind additionally
needs design decisions about cost, usage limits and what information persists
outside the restored state.

### Effect and action extension checklist

For each new mechanic, document:

1. The general resolver/data vocabulary and canonical legal action representation.
2. Mutable state, pending work, serialization, restore and revision invalidation.
3. Trigger phase/order, acceptance versus resolution, and reaction-loop handling.
4. Geometry/danger assumptions it changes and safe query fallback.
5. Path/center equivalence, pruning representation and evaluation/horizon support.
6. Replay identity, explanatory events, and presentation generation ownership.
7. Focused examples proving live, forecast, restore and replay continuation agree.

This is an obligation at the existing boundaries, not a requirement to create a
universal effect language. Unknown strategic value must be visible rather than
silently treated as no effect. Runaway reaction chains fail diagnostically;
silently dropping effects to meet a search budget changes the rules.

## Later experiments and analysis

Tournament tooling follows the AI foundations. Early work uses narrow local
fixtures and counters; it does not repair or depend on the placeholder runner.

The target experiment system provides:

- Immutable runnable engine/build/content identity; a moving shared checkout
  and a commit hash alone are insufficient.
- A fixed manifest of setups, seeds, policy/configuration identities, side
  swaps, budgets and match IDs. Separate attempts from logical matches.
- Bounded independent process workers, per-worker shards, canonical merging,
  partial-write recovery, resume and deduplication.
- Separate elimination, draw, round-cap adjudication, illegal action,
  invariant failure, process crash and watchdog timeout outcomes.
- Compact streamed deterministic rows; timings/environment and optional detailed
  traces have separate retention. All artifacts use BattleOutputPaths.
- A documented analysis command producing machine-readable summaries, CSV and
  readable comparisons with replay/explanation links.

The evaluation manifest declares tuning/held-out allocation, budgets and
acceptance criteria before held-out results are read. Compare several opponents
and configurations; legacy is a weak reference, not the definition of strength.
Paired/cluster-aware uncertainty respects shared setups and side swaps. Repeated
identical deterministic matches add reproducibility evidence, not independent
samples. Equal seeds do not imply equal random-event consumption by two policies.

Use ablations to separate geometry cost, candidate scope, danger and search.
Explain selected actions, runner-up alternatives, score components, pruning
and consumed work. Report quality versus cost, scenario/side breakdowns,
failure denominators, stalls, and cap outcomes. Balance conclusions depend on
policy competence and scenario coverage. Retuning after viewing held-out results
requires a new experiment and fresh holdout.

Actual commands live in DEVELOPMENT once implemented. Current placeholder
commands must not be presented as providing these guarantees.

## Capabilities and limits

| Capability | Intended support or limitation |
|------------|--------------------------------|
| Deterministic headless matches and failure replay | Core target, within declared compatibility boundaries |
| Large resumable tournament batches | Later process-worker runner; bounded memory and failure recovery required |
| Policy explanation and ablations | Explicit trace/configuration and analysis features |
| Technical whole-side-turn rewind | Shared snapshots plus replay branches and presentation invalidation |
| New effects and action classes | Local extension obligations; strategic understanding may need new evaluation features |
| Very large battles | Limited by reachable cells, action branching, forecast/history cost and memory; no unlimited-scale promise |
| Hidden information | Requires observation filtering and information-state search beyond this rework |
| Learned policies/self-play training | Possible consumers of stable interfaces; no training pipeline is included |
| Multiplayer rollback/distributed scheduling | Separate contracts and infrastructure |
| Arbitrary cross-version/platform replay | Not promised; support must be explicitly validated |

## Documentation maintenance

Update this reference with actual symbols, schemas, chosen algorithms, limits,
and examples whenever those contracts change. Keep current behavior separate
from intended work, and remove superseded descriptions. Permanent documentation
must not depend on implementation-cycle item IDs or generated benchmark files
remaining on one machine. Commit bodies hold one-time decisions/evidence;
this document holds the resulting durable architectural truth.
