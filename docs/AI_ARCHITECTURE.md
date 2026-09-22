# Nogg AI architecture

Status: checked against source on 2026-09-20. The state and persistence
foundation described as current below is implemented. Later rework contracts
remain intended architecture. Implementation changes must update this document
in the same commit and remove obsolete current-behavior descriptions.

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
| Side policy | [TacticalSidePolicy](../src/entity_ai/TacticalSidePolicy.gd) ranks every ready actor's commands over one decision step; [CommandUtility](../src/entity_ai/CommandUtility.gd) scores in hit points; [EngagementBand](../src/entity_ai/EngagementBand.gd) says where each unit wants to stand |
| Danger | [DangerQuery](../src/entity_ai/DangerQuery.gd) answers a single reply, a conservative bound and a feasible continuation as three labelled things; [DangerAssessment](../src/entity_ai/DangerAssessment.gd) carries the label, contributors, cost and named blind spots |
| Decision context and candidates | [DecisionContext](../src/entity_ai/DecisionContext.gd) shares revision-scoped queries; [LegalActionEnumerator](../src/entity_ai/LegalActionEnumerator.gd) produces complete legal [ActionCandidate](../src/entity_ai/ActionCandidate.gd) sets; [CandidateFilter](../src/entity_ai/CandidateFilter.gd) narrows them; [PolicyCatalog](../src/entity_ai/PolicyCatalog.gd) names who chose |
| Geometry and movement | [HexGrid](../src/board/HexGrid.gd), [HexReachability](../src/algorithms/HexReachability.gd) over cost buckets, [AStarPathfinder](../src/algorithms/AStarPathfinder.gd) over a binary heap, [LineOfSight](../src/algorithms/LineOfSight.gd) over translated ray templates, and canonical resolver callbacks |
| Interactive scheduling | [HexBattleController](../src/systems/hex_battle/HexBattleController.gd) advances four deterministic inner slices per rendered frame, then applies a completed proposal on the main thread |
| Headless scheduling | [run_battle](../scripts/battle/run_battle.gd) completes the same planner synchronously |
| Stale proposal detection | [StateRevision](../src/entity_ai/StateRevision.gd) includes actor state, a mutation revision and timeline generation; full actor serialization is still paid on capture |
| Persistence and replay | [BattleStateSerializer](../src/battle_sim/BattleStateSerializer.gd) restores runtime abilities, movement costs and lossless large integers in state version 8; [BattleReplayRunner](../src/battle_sim/BattleReplayRunner.gd) consumes the version 8 replay envelope |
| Detached forecast | [BattleForecast](../src/battle_sim/BattleForecast.gd) resolves one command on a cloned canonical state; [OutcomeEstimator](../src/entity_ai/OutcomeEstimator.gd) combines explicit policy samples as integer counts and sums |
| Technical side rewind | BattleSimulator retains one side-start checkpoint, restores only at quiescent boundaries, increments timeline generation, and keeps branch operations in an outer ledger |
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
- State version 8 restores spell and passive instance properties and complete
  loadouts. Older state version 7 remains readable with catalog reconstruction;
  its numeric RNG field cannot prove lossless disk continuation.
- RNG state is decimal text. Integers beyond JSON's exact range use a reserved
  tagged decimal string in state and replay envelopes. Decode at read boundaries.
- Current state mutation methods advance a revision; simulator restore advances
  generation even for an equal position. Direct writes to public matrices,
  entities or nested dictionaries bypass the cheap revision. Proposal capture
  still reads actor fields; future caches must use state methods or a semantic
  validation at application.
- Full history participates in replay snapshots and the one retained side-start
  checkpoint. Forecast forks copy the suffix beginning at the earliest actor
  last-turn index. SpellEffectResolver's damage reversal reads that suffix.
- Existing championship output is not a resumable, supervised, parallel
  experiment system. Its repair is not a prerequisite for AI restructuring.

## Intended structure

The following sections specify the remaining rework contracts. Until implemented
and verified, they describe targets. Concrete exported symbols, schemas, algorithm
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

Version 8 currently stores these future-affecting fields:

| Owner | Persisted state |
|-------|-----------------|
| BattleState | Board occupancy, height, terrain and movement cost; map/scenario identity; rosters/parties; side order, selection, spent/pending/withdrawn state; clocks and outcome |
| BattleState | Effects, complete event history, turn-start indices, battle seed, decimal RNG state and next monster ID |
| Monster | Identity, position, stats, elements, lineage, cooldowns, resonance, complete spell instances and passives |
| BattleSimulator | Setup identity and replay operation envelope; resolver and brain wiring are rebuilt after restore |

Mutation revision and timeline generation are scheduling identity outside the
gameplay snapshot. State APIs for terrain, height, movement cost, effects,
abilities, allocation and occupancy advance the revision; state events do too.
Direct field writes need markMutation until those paths are encapsulated. The
full actor token catches direct actor edits, but a direct board write bypasses
the cheap token. Future cache users must respect this boundary.

Catalog references are treated as immutable. Monster construction copies the
elements list; spell/passive instances own their mutable properties; and
setMonsterAbilities copies an incoming loadout. The content fingerprint uses
authored map and party data plus sorted complete catalogs. A runtime ability
edit does not change that identity. It does not hash simulation source code;
later experiments must identify the executable build separately.

The state-contract probe writes a version 8 snapshot under battle_output/.
On its next run it reads the prior process's file. It checks large integers,
runtime abilities, board/effect state and a continued command. JSON turns
ordinary numbers into floats on parse, so the probe compares equivalent
numeric values rather than claiming byte-identical in-memory dictionaries.
Run the focused sweep twice for the fresh-process check. State version 7 uses
catalog reconstruction; version 7 replay envelopes are unsupported.

### Current forecast, checkpoint and branch contract

`BattleForecast.evaluate(simulator, actorID, command, mode, sampleID)` copies
`BattleStateSerializer.serializeForForecast`, reconstructs independent state and
resolvers, selects the actor on the fork when needed, then calls the canonical
`executeCommand`. `BattleForecastResult` reports `accepted` and `resolved`
separately, the one-command horizon, an ordered list of changed serialized
paths, new state events, and copied bytes/history counts plus diagnostic times.
An accepted command whose caster dies to an `ON_TARGETED` passive is unresolved.
The generic path delta exposes state changes from new effect types without an
effect-specific forecast handler; an evaluator still needs to value them.

`debug_exact` clones the current gameplay RNG for reproduction. `policy_sample`
does not read its state: the serializer substitutes zero before cloning and a
new stream is seeded from battle seed, round, side-turn count, active side,
actor ID, explicit sample ID, and content fingerprint. The caller owns stable
sample IDs, independent of candidate enumeration and worker completion order.
Do not pass debug-exact results to policy aggregation. `OutcomeEstimator` checks
for unique policy sample IDs and reports integer acceptance/resolution counts,
HP delta sums and terminal counts. Its summaries are not yet a tactical policy.
The forecast probe persists a random-consuming policy sample under
`battle_output/battles/ai_forecast_sample.json` and compares the next process's
result and serialized bytes with it; diagnostic timings are excluded.

Forecast history starts at the earliest `last_turn_start_index` among **all**
monsters, including defeated ones. Indices are shifted into the fork and
`historyBaseIndex` preserves the logical event count for seeded uniform choices.
This is sufficient for the current damage-reversal rule, which reads damage
events by actor since that index. A future effect that reads older history must
extend the rules-memory contract before using compact forecasts. The technical
probe copied zero historical events and serialized 17,720 bytes at both 120
and 960 diagnostic events after all turn indices advanced (sampled on this
Windows Godot 4.4 host; 2,844 and 3,247 microseconds respectively). Full
snapshots at those lengths were 28,378 and 102,298 bytes. These
timings are observations, not deterministic policy inputs or a performance gate.
Before every monster has a turn index, the conservative default copies from
event zero.

`BattleSimulator` captures one complete state snapshot after `side_turn_start`
has settled; the next side replaces it. `restoreSideTurn()` rejects a missing or
expired checkpoint and calls during movement, action resolution, unit-selection
callbacks or end-of-turn passive cascades. It validates content and semantic
fingerprints before replacing state, then rebuilds resolvers/brains and advances
`timelineGeneration`. The old gameplay RNG and allocator return to their
checkpoint values. Entity IDs can therefore recur on divergent branches; use
branch identity plus generation when naming a trace entity. Repeated restores
from the same side checkpoint are technically supported. There is no player
cost, usage limit or interactive presentation contract yet.

The append-only `operationLedger` is outside rewindable `BattleState`. It holds
normal accepted operations with post-operation semantic fingerprints and a
`side_turn_rewind` entry with checkpoint fingerprint, branch ID and abandoned
operation count. Version 8 replay executes branches in order, checks each
post-operation fingerprint, and reports the first divergent operation index.
The fingerprint covers future-affecting state, including damage facts selected
by turn-start pointers, but omits diagnostic history, the numeric pointers and
reconstructed brain objects; operation results and the ledger cover event order.
Exact integral JSON numbers are normalized within
their safe range for semantic comparisons, while unrestricted integers retain
their tagged decimal representation. A direct restored battle keeps the
checkpoint and ledger in the replay envelope.

The checkpoint retains **one full history copy**, so its capture cost and size
still grow with battle age, though forecast copies do not once turn indices
advance. A future persistent event store could remove that remaining growth;
this implementation does not claim constant-memory rewind. Current resolver
cascades are synchronous and have no serialized in-progress queue. Any future
delayed work must add pending state and a declared deterministic processing
order before it may cross this checkpoint boundary.

Reaction order is fixed and finite. `ON_TARGETED` retaliation fires before the
attack or spell's own damage, once per affected unit in enumeration order; a
caster killed there leaves the command accepted and unresolved with reason
`caster_died_to_passive`. Every kill source reaches the single
`PassiveSkillResolver.handleDefeat` path, whose `_resolvingDeaths` set refuses
to re-enter a monster that is already resolving, so an `ON_DEATH` area chain
visits each entity at most once and terminates instead of looping. That guard
bounds today's cascade; it is not a general reaction budget, and it is
transient resolver wiring rebuilt with the resolvers rather than serialized
state. Restore cannot observe it mid-chain, because every path that populates
it runs inside `_resolutionDepth`. A future trigger that can re-enter the same
entity, or queue work past the end of its own resolution, owes this contract a
declared deterministic processing order and a diagnostic failure on exceeding
it; truncating a cascade silently is not an acceptable fallback.

The remaining contract extends this foundation. Immutable definitions describe
authored content. Mutable battle state owns
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

#### Current candidate implementation

[DecisionContext](../src/entity_ai/DecisionContext.gd) is the one read-only view
a decision works from. It computes an actor's reachable set once and shares it
across every ready actor, holds the memoizing resolver for exactly its own
lifetime, and refuses to answer once it is no longer current. Its key is the
cheap pair of timeline generation and mutation revision; it also watches whether
the simulator's state **object** was replaced, because `restoreSideTurn()` swaps
in a restored state rather than editing the old one, and a context holding only
the old object would keep answering confidently about an abandoned branch.
`debugFingerprint()` is the expensive full-actor token, used by the probe to
show that the cheap key moves whenever the supported mutation API is used. That
equivalence holds only for mutations that go through a `BattleState` method:
writing a `Monster`'s fields directly still bypasses it, and `MapFactory` now
marks one mutation after applying a map, because it writes the terrain and
height layers directly for speed.

[LegalActionEnumerator](../src/entity_ai/LegalActionEnumerator.gd) answers what
is legal and nothing else. It asks the resolvers rather than restating their
rules, and emits four classes: Wait at every reachable destination, an attack per
legal target position, and a spell per castable centre, split by whether the
centre catches any unit. Spells are enumerated at the origin alone because magic
is pre-move -- `BattleSimulator._sideLegalCommand()` turns a move-then-cast into
a move and a Wait, so a cast from a walked-to tile is not a legal action to
begin with. `classCoverage()` counts a candidate set by class, so a sampler that
never casts anything is visible as a gap rather than as a number nobody read.

[ActionCandidate](../src/entity_ai/ActionCandidate.gd) carries the actor, the
canonical command, the destination and the walked path, and two separate keys.
`tie_key` totally orders one actor's candidates so selection among equals is
machine-independent. `equivalence_key` is the finite action abstraction: two
candidates are the same move when the action class, destination, ability and set
of affected units all match. **The route is deliberately excluded, and that is
an obligation, not a simplification.** The first rule that reads the route -- a
tile that triggers on entry, a trail, an opportunity attack -- makes routes
distinguishable, and the key must gain the path in the same change, or the
filter will discard the only route that fires the trigger.

[CandidateFilter](../src/entity_ai/CandidateFilter.gd) is where narrowing
happens, in the open. `collapseEquivalent()` may merge only on
`equivalence_key`. `capWithAllowance()` reserves a per-class allowance before
spending the rest of its budget, so a cap can make a policy look at less but
cannot make a whole class of action invisible -- the failure mode where a new
spell is never chosen because ranking never understood it. `nearestDestinations()`
holds the legacy ten-destination budget as a named filter rather than as
something an enumerator does quietly.

[PolicyCatalog](../src/entity_ai/PolicyCatalog.gd) names the policies a battle
may be played with, with their configuration and a fingerprint over both. An
unknown id is refused rather than defaulted, so a manifest typo fails instead of
running something else under the name that was asked for.
[LegacySidePolicy](../src/entity_ai/legacy/LegacySidePolicy.gd) gives the shipped
stream an identity and freezes its decisions in
`scripts/battle/fixtures/ai/legacy_decisions.json`. It drives the existing
deliberation classes rather than copying them, because a second implementation
of one policy drifts and then neither is the baseline. Its decisions are frozen
across slice sizes as well, since how a decision was spent is not part of it.

**The reworked stream is built beside the shipped one, not over it.** The game
still plays through `PartyCommandDeliberation` and `CommandDeliberation`, which
keep their per-slice full-actor staleness check. Retiring that cost belongs to
the item that replaces the policy; changing it here would alter legacy staleness
behaviour in exactly the edge cases the frozen baseline exists to hold still.
Measured on the technical scenario, the complete legal set the enumerator
produces for one ready side is 38 Wait, 119 attack, 8 unit-affecting spell and
20 empty-centre spell candidates -- the last class being one the shipped
deduplication collapses away entirely.

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

#### Current hex query implementation

[LineOfSight](../src/algorithms/LineOfSight.gd) builds one ray template per
axial displacement and source-column parity, and translates it. Cell centres are
an affine image of axial coordinates, so the touched cells, their entry and exit
parameters, and their order all depend on nothing else -- parity enters only
because the order tie-break reads storage rows, which shift with it. A template
holds geometry alone: heights, blockers and occupancy stay in the caller's
callable and are re-asked on every query. Retention is one bounded table of 4096
templates, dropped whole rather than evicted, since every entry costs the same
to rebuild. `clearRayTemplates()` exists for the cost probe; no gameplay path
needs to invalidate geometry, because geometry never changes.

Building a template is still a scan of the disc of radius distance + 1, clipping
the segment against six edge normals per cell, so a first ray of length *d*
costs *O(d²)* while every later ray of that displacement costs *O(d)*. A
narrower enumerator that walks only cells near the segment was rejected: it
needs a proof that its candidate set is a superset of the touched set, and the
templates already remove the repeated cost that the measured workload pays.

[HexReachability](../src/algorithms/HexReachability.gd) keeps one search per
actor rather than an A* per destination, and spends its frontier through cost
buckets. Every step costs at least one, so a relaxation can only move a cell to
a strictly later bucket, and a bucket is complete before it is opened: sorting
it once on its stable row-and-column key reproduces exactly the order a repeated
cheapest-cell scan produced. Memory is one array slot per point of the movement
budget. [AStarPathfinder](../src/algorithms/AStarPathfinder.gd) uses a binary
heap over the same total key the old scan selected on -- estimate, cost so far,
row, column, insertion sequence -- which a heap may reorder freely because
entries agreeing on all five describe the same cell reached the same way.

`MovementResolver` caches the minimum traversal cost that scales the A*
heuristic, keyed by map and mutation revision, because A* asked for a whole-board
scan on every path query. Understating that minimum is always safe: every
traversal cost is a positive integer, so a bound of one is admissible on any
board. Overstating it is not, so **a future traversal cheaper than the recorded
minimum -- a portal, or a direct board write of the kind the state contract still
permits -- must advance a revision or fall back to one.**

Measured on this Windows Godot 4.4 host, ten runs each, against the previous
implementations. Rays over two full radius-8 discs: 687-743 ms before, 294-363
ms after. One side turn of the technical scenario -- eight units, 67 reachable
destinations, 219 melee and 747 spell target tests -- 481-487 ms before, 137-143
ms after. Weighted reachability: no clear gain on a small frontier, 1.4x to 2.9x
faster as board and movement budget grow. A long A* path: no gain on short
searches where the open set stays tiny, 1.4x to 3.5x faster at 24 and 40 cells
square. These are observations of one host, not acceptance thresholds.

Enumeration **order** is not a property callers may lean on beyond the one
guarantee that it is deterministic. The touched *set* is symmetric under
reversal and invariant under translation; the order is neither, because cells
are ordered by where the segment enters them, which reversal does not mirror,
and ties break on storage rows, which move with source-column parity. The
correctness probe asserts the set properties everywhere and the order only for
parity-preserving translations.

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

#### Current danger implementation

[DangerQuery](../src/entity_ai/DangerQuery.gd) answers three questions and keeps
them apart, because a caller that gets one number cannot tell which risk it is
taking. `reply()` is the most one named enemy could deal at a tile, exact under
current rules for that enemy. `conservativeBound()` adds every enemy's best
reply: **an upper bound, never a prediction**, because two of those enemies may
need the same cell to stand on. `feasibleContinuation()` builds a continuation
the side could really carry out -- one action each, no two enemies on one cell,
and a caster stays put -- which is a **lower** bound, since the assignment is
greedy over the conflict set rather than optimal. So `feasible <= truth <=
bound`, and a consumer picks the side of the truth it wants to be wrong on.
Commander safety and heal worth both ask the bound, because overstating danger
loses a tile and understating it loses a commander.

[DangerAssessment](../src/entity_ai/DangerAssessment.gd) carries the label, the
per-enemy contributors with the cell each would act from, the work spent, a
`truncated` flag, and `approximations` -- the named blind spots, which are part
of the answer rather than a comment: reactions, damage over time, anything past
one enemy round, the greedy assignment, and any ability with no declared reach.

**Pre-move magic is respected, and the influence map it replaces did not respect
it.** `ThreatMap.threatFor()` enumerates each enemy's spells from every cell it
could walk to, but `BattleSimulator._sideLegalCommand()` turns a move-then-cast
into a move and a Wait, so those casts cannot happen. Danger therefore credits a
spell only from where the enemy already stands. On the technical scenario the
probe finds three walked-to cells from which a relocated caster's spell would
have reached its target, and credits none of them.

Cheap geometric rejection runs before any question about legality, line of sight
or height: an enemy whose declared reach cannot span the distance is dropped
untouched. The bound is deliberately generous and **fails towards keeping**, so
an ability that declares no range at all is never pruned and the assessment says
so. A bound that silently prunes a mechanic it does not understand is how a new
spell becomes invisible to danger.

Work is counted per query and a budget yields a truncated answer rather than a
stall. Measured on the technical scenario on this Windows Godot 4.4 host: eight
sparse bounds, one per living unit, cost 154 resolver queries in 22 ms; seven
dense bounds over one actor's whole reachable set cost 146 queries in 12 ms; the
full-board influence map for one side costs 86 ms. Sparse questions win at the
sizes a side policy actually asks, which is why there is no shared batch yet --
not because batching is wrong, but because nothing has yet asked enough
overlapping questions to pay for it. These are observations, not gates.

**The reworked policy is what consumes this.** `CommandDeliberation` sets an
empty threat dictionary and skips its threat phase, so the legacy path still
runs with danger disabled; that is deliberate, because moving it would move the
frozen decisions that exist to hold it still.

#### Current side policy

[TacticalSidePolicy](../src/entity_ai/TacticalSidePolicy.gd) is what plays.
`BattleSimulator.sidePolicyID` selects it and `beginSideDeliberation()` is the
one way a side decision opens, so a run always knows what chose its moves; the
legacy stream stays selectable by id as a comparator, and random legal play
keeps its own path because a fuzzer's whole point is the uniform draw.

Its **horizon is one decision step**. It picks the next command the simulator
will resolve and values a position by what the acting unit could do from there
afterwards. It never schedules an enemy turn: the reply enters only through
`DangerQuery`, labelled as a single-enemy-round approximation. Things the
horizon cannot see are listed in the class, not discovered later -- combinations
needing two allies, effects that pay off after a duration, terrain that matters
in two turns, and any opponent move other than a reply.

[CommandUtility](../src/entity_ai/CommandUtility.gd) scores in one currency,
hit points, with terminal outcomes on their own tiers far above it. It uses the
two danger labels for the two jobs they exist for, and **which one gates
survival was the difference between a game and a staring contest**: vetoing a
destination on the *bound* -- everything the enemy side could throw -- made
units refuse every engagement once wounded, and the technical scenario ran 30
rounds to no result. Vetoing on the *feasible* continuation, and charging the
bound's excess as a separate `exposure` term, gives a decided battle. Only
*added* exposure is charged, so standing in danger is not itself a reason to
act and retreating earns nothing.

[EngagementBand](../src/entity_ai/EngagementBand.gd) is where a unit's preferred
distance comes from, and it is read off the abilities the unit is carrying
rather than typed in per role: melee at one for `atk`, each damaging castable
spell across its own range band, best band wins and ties go to the longer one.
A unit handed a new spell starts wanting a new distance with nobody editing a
table. Two things about it were load-bearing:

- **The value is not clamped at zero.** Clamping made everywhere past a few
  hexes score the same nothing, so a unit that started far from the fight saw a
  flat landscape and had no reason to walk in.
- **Position is weighted at three, not one.** A band's value is what a unit
  earns there every turn while the risk beside it is one turn's worth, so at a
  weight of one a melee unit never closes -- standing next to somebody costs
  more than one swing returns. Measured on the technical scenario: no result in
  30 rounds at one and two, a decided battle at three, the same result one unit
  poorer at five.

Work is bounded in two passes. Everything except danger is scored for every
candidate; only a shortlist of six per actor earns a danger question, which is
cached by tile. **A slice is a unit of work, not a unit of candidate** --
enumerating one actor costs milliseconds while pre-scoring one candidate costs a
fraction of one, so spending a slice on each made a decision take dozens of
frames on the presentation thread. One decision on the technical scenario
enumerates 185 candidates, scores 24, and finishes in 16 slices and about 33 ms
on this host.

`CandidateFilter.dropIdleAttacks()` removes a swing at an empty tile. A basic
attack damages the occupant of its target and nothing else, so aimed at nobody
it is the Wait at that same destination spelled in a way **a player's own
controls cannot express**, and a CPU should not play moves the person across the
board could not. It is an equivalence, not a judgement about usefulness: spells
whose centre catches nobody are deliberately kept, because an effect that reads
the ground is a mechanic this game could gain. If a basic attack ever lands
something without a target, that filter is wrong and must go.

The policy is stateless and draws nothing from the battle's RNG. Candidates
accumulate in a fixed order and rank once on a total key, so slice boundaries
cannot change the answer, and a fresh instance is built after each resolution so
later units see the board the earlier ones changed. `trace()` returns the chosen
action's components, the runners-up, what was enumerated against what was
scored, and the work spent; the probe checks the components sum to the score.

Measured against the shipped policy on the technical cpu-versus-cpu scenario at
two seeds, both sides running the same policy: legacy resolves in 7 rounds and
38 decisions, the reworked policy in 14 rounds and 78 decisions, with a
different side winning. **That is not evidence of strength.** Both finish, which
is the property being checked here; which policy is better is what the later
experiment items are for, and a two-seed self-play fixture cannot answer it.

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
