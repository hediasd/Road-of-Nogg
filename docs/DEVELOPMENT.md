# Development and Verification

Status: current for Godot 4.4 on Windows. Last verified: 2026-07-31.

This is the executable workflow reference. Start with a clean understanding of
the working tree, but preserve unrelated user changes.

## No test suite, but one command runs every probe

The previous test suite (unit/integration/scene tiers), the GUT addon, the
`scripts/run_godot_check.ps1` / `scripts/check_docs.ps1` runners, and the git
hooks that invoked them were all removed to be rebuilt fresh. What replaced
none of that is a suite: it is a sweep over the probes the cycles already
wrote.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter worldmap
```

`scripts/checks/run_probe_sweep.ps1` reads every manifest in
`scripts/checks/probes/`, runs each registered probe through
`scripts/hex_battle/run_probe.ps1` one at a time, prints a verdict line per
probe and ends with `PROBE_SWEEP_OK <passed>/<gated>` or
`PROBE_SWEEP_FAILED <n>`. A manifest entry names the probe, the exact marker it
prints on success, its timeout, whether a pass or a failure is expected, and
two flags:

- `"gate": false` — **quarantined**. It still runs and is still reported as
  `QUARANTINED-PASS` or `QUARANTINED-FAIL`, but it cannot fail the sweep. The
  `"note"` says why it was quarantined.
- `"renderer": true` — needs a real window, so the sweep lists it as `SKIP`.
  Run it yourself with a windowed Godot when you touch what it checks.

The sweep refuses to start if a registered script is missing or registered
twice. Run it with `-Filter` on your area when your item changes code a
registered probe loads, and in full in a cycle's last item. An item that adds a
probe registers it in a manifest in the same commit.

Registered probes are the only automated check that exists. Behaviour, feel and
appearance are still verified by launching the game.

`scripts/demo_battle.gd` remains available as a manual, non-automated seeded
console battle. It now runs the same PARTY runtime the playable scene does,
from an authored CPU-vs-CPU scenario. Run it from the repository root through a
waited process and require its explicit `Battle complete` marker; a zero exit
code alone is not sufficient evidence on this Windows host. For anything where
you want to choose the scenario, the seed or the output, use the runners in the
next section instead — they supersede it.

The hex battle cycle also ships bounded headless probes under
`scripts/hex_battle/`, each run through `scripts/hex_battle/run_probe.ps1` and
each requiring its own exact marker line. They are narrow checks of one item's
own logic, not a test suite and not visual acceptance.

Generated art must be imported before anything loads it. Use
`godot --headless --import --path .`; `--headless --editor --quit` does NOT
work, because `--quit` ends the run after one frame while the filesystem scan
is asynchronous, so it aborts partway and writes no `.import` file.

## Simulating battles headlessly, and recording them

The state-contract probe verifies disk persistence of mutable abilities, board
costs, large IDs and RNG state, then continues the restored battle through a
canonical command. Run it twice: the second invocation also reads the first
process's snapshot from battle_output/battles/ai_state_contract.json.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter state_contract
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter forecast
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter rewind
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter replay
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter spatial_cost
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter candidates
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter danger
```

Active hex state and replay snapshots use version 8. Version 7 state can be
loaded with catalog-restored abilities, but old numeric RNG files cannot prove
lossless continuation. Version 7 replay envelopes fail with an explicit
unsupported-version result.

The forecast probe checks isolated canonical resolution, area damage, damage
reversal, reactive fizzle, stable policy samples and history-copy cost. The
forecast probe also compares a random-consuming sample with its prior-process
artifact on a second run. The
rewind probe restores the same side twice, checks allocator/RNG recovery,
round-trips the branch replay through JSON and finds a deliberately tampered
operation by index. These are technical contracts; interactive rewind UI and
player-facing cost have not been implemented.

The spatial cost probe checks that cached ray geometry is pure and bounded, and
that weighted reachability and A* agree with an exhaustive oracle on a board
wider than the correctness fixture's. It prints `AI_SPATIAL_COST` lines with the
workload it measured; those numbers are observations of the host that ran them,
never pass conditions. Line-of-sight rules are asserted by `-Filter spatial`
against hand-derived cases in `scripts/hex_battle/fixtures/spatial/los_golden.json`
and a second corner-walking oracle, not against captured output.

The candidates probe checks the separated decision stream: complete legal
enumeration against an independent cell-by-cell sweep of the resolvers, one
shared context that stops answering when the board moves or the timeline
branches, collapse that merges only indistinguishable candidates, a cap that
cannot starve an action class, unknown policy ids refused, and sampling coverage
by class. It also replays the frozen decisions of the shipped side policy from
`scripts/battle/fixtures/ai/legacy_decisions.json`. **A failure there means CPU
behaviour moved.** If that was deliberate, regenerate the fixture in the same
commit and say why; if it was not, it is the finding.

Two runners under `scripts/battle/`. Both write to `battle_output/` at the
project root by default: single battles under `battle_output/battles/`,
championships under `battle_output/championships/`. See the next section.

One battle, both outputs — the readable log and the machine record:

```powershell
./Godot_v4.4-stable_win64.exe --headless --path . --script scripts/battle/run_battle.gd -- res://data/battle/scenarios/proving_ground_cpu_cpu.json 7
```

Many seeds into one corpus plus a run summary:

```powershell
./Godot_v4.4-stable_win64.exe --headless --path . --script scripts/battle/run_championship.gd -- res://data/battle/scenarios/proving_ground_cpu_cpu.json 1000 8
```

The corpus is **JSONL, one battle per line**, written by `BattleRecordAdapter`.
A single battle is simply a one-line file, so there is one schema rather than
two. Each line carries the identity needed to tie it back to what produced it
(scenario, map id and revision, map source fingerprint, content fingerprint,
seed, engine), the board (every valid cell's terrain and height, plus the
terrain table), the parties as deployed, a `roster` of what each monster is
(level, speed, luck, race, elements, passives with their parameters, and every
spell's range, area, damage, cooldown and effects), which brain drove each
member, every decision, and the outcome. The outcome's `end_reason` is
`elimination` or `round_limit_survivor_count`; the second is a tally at the
round cap, not a result, and a scorer should treat it that way.

**The round cap counts whole rounds** (30 in both runners). The last round
plays to its end, so every party still standing has activated the same number
of times. At the cap the team with more monsters on the board wins; **a tie is
a draw**, recorded as `winner_team` 0 with `draw: true`. Team ids start at 1,
so 0 never names a team; it is also what an elimination with nobody left
returns. Records before version 3 were scored differently: the cap stopped
after the first party of the last round, and a tie went to the first-listed
team. The CPU brains also changed with version 3: a heal counts only when its
target could fall before acting again, and a harmful effect a spell puts on its
caster's own side counts as a cost. Do not pool version 2 records with
version 3 ones.

A decision answers four questions: what the actor saw (`observation`, including
each monster's effects in full, its resonance, and whether it is `withdrawn` —
alive but off the board at (-1, -1) because its commander fell), what it could
legally have done (`legal` — reachable cells with costs, attackable positions,
and the actor's spell menu with cooldowns, indexed the way a command addresses
it; plus `eligible_members` and the round's `party_order`), what it did
(`chosen`, `result`), and what changed (`changed`, and `withdrawals` when the
decision killed a commander). Legal movement and attacks come from
`ReachQuery`, the same query the player's own overlay reads, so the corpus says
exactly what the game offered.

What a record does not carry: the legal *spell target cells* per destination
(derive them from the roster's spell ranges and the board), and the rule tables
the ruleset names, such as race-versus-element damage multipliers. The headless
loop always activates the first eligible member, so member choice in a corpus
is that rule, not a policy's decision.

**A scenario with a player-controlled party is refused**, because a console has
nobody to choose. Use the `_cpu_cpu` scenario of a pair.

**Records are deterministic**: two runs at one seed produce byte-identical
lines, asserted by `scripts/battle/checks/probe_battle_runner.gd`. The
championship *summary* deliberately is not — it carries wall-clock timings.
The summary tallies `winners` by team id, with draws under `"draw"` rather than
as a team `"0"`, and counts `end_reasons` beside it; each battle entry carries
its own `draw` and `end_reason`.

The championship flushes the corpus after every battle, so a run that dies
partway keeps every finished line.

**Seeds barely change a battle today.** The only random draw in the simulation
is the critical-hit roll, and the CPU brains are deterministic, so on a fixed
scenario most seeds replay the same fight. Twenty seeds on `hexmap_cpu_cpu`
gave one winner twenty times and five distinct decision sequences (record
version 2). Five seeds under version 3 gave one winner, one end reason and one
decision sequence; only a critical roll's damage differed. A corpus
that needs varied outcomes needs variety from somewhere else first.

**The variety comes from the brain, not the seed.** `--brain=<BrainName>`
replaces every unit's authored brain for that run, and `--brain-team=<teamID>`
limits the replacement to one side. Both runners take them, and the
championship puts the brain in the output file name so a random corpus and a
policy corpus can never be confused on disk.

```powershell
./Godot_v4.4-stable_win64.exe --headless --path . --script scripts/battle/run_championship.gd -- res://data/battle/scenarios/proving_ground_cpu_cpu.json 1 100 --brain=RandomLegalBrain
```

`RandomLegalBrain` picks uniformly among the legal commands the evaluator
enumerates, with waiting added to the pool, and the side picks which unit acts
at random too. It is a **fuzzer, not an opponent**: it walks the branches a
scored policy never reaches — waiting with an enemy in reach, walking away,
casting from an odd tile — which is where a rules bug hides. A random battle at
one seed still replays byte for byte.

**Its draws come from a generator seeded out of the position** (battle seed,
unit, history length), never from `state.rng`. Deliberation is a pure query and
`StateRevision` counts `rng.state` as state, so drawing from the battle's own
generator made every deliberation stale, the side discarded the proposal, and
the unit waited instead. The first version of this brain played 24,000
consecutive waits and passed a fuzz probe that only checked that battles ended.
Assert the operation mix, not just termination.

Two more things to keep straight. A random run and a policy run diverge from
the first decision, so **their records must never be pooled**; the corpus names
each member's brain, so it always says which it is. And win rates against
random play measure nothing about balance, because a random policy loses to
every real one.

`scripts/battle/checks/probe_fuzz.gd` is the smoke-sized version: random play
across every CPU-vs-CPU scenario, asserting each battle ends by elimination or
at the cap, violates no invariant, replays identically at one seed, and differs
from the policy run. It also drives `undoMovePhase()` directly, which no CPU
path can reach.

Measured numbers worth knowing before planning a large run, on this host:

| Measure | `proving_ground_cpu_cpu` | `hexmap_cpu_cpu` |
|---|---|---|
| Time per battle | ~90 s (before FHB-12) | ~48 s at seed 14 after FHB-12 (was ~82 s just before it; 76–79 s over 5 seeds, v3; 79–135 s over 20 seeds, v2) |
| Record size per battle | — | ~200 KB raw, ~12 KB gzipped (v3, 8 rounds); ~330 KB raw, ~15 KB gzipped (v2) |

The time is CPU deliberation, not the recording or the rules. Profiling one
`hexmap` battle: 92.9 s of 93.2 s went to the brains choosing, 0.2 s to the
recorder, 0.1 s to resolving commands. Inside deliberation the cost is line of
sight, and most of it is the threat map, not `_emitSpell`: in the first 12
decisions at seed 14, 28.1 s of 33.0 s was the threat phase and 4.9 s the
actor's own spells. FHB-12 memoizes LoS for one deliberation, which took those
12 decisions to 19.1 s. What is left is mostly each distinct LoS check's hex
line geometry. A thousand battles is now about half a day of wall clock and
about 15 MB of gzipped corpus.

## Where battle output goes

**Every file a battle writes goes under `battle_output/` at the project root**,
and nowhere else. That covers the human log, the machine record, championship
corpora and summaries, the console demo's log, and anything the playable scene
writes about a battle in future. The folder is gitignored and carries a tracked
`.gdignore`, so Godot does not scan or import what lands there.

| Folder | Written by |
|---|---|
| `battle_output/battles/` | `run_battle.gd`: one record and one log per run |
| `battle_output/championships/` | `run_championship.gd`: one corpus and one summary per run |
| `battle_output/demo/` | `demo_battle.gd` |
| `battle_output/played/` | reserved for the playable scene |

A new writer asks `src/presentation/BattleOutputPaths.gd` for its path instead
of choosing one. An exported build cannot write to `res://`, so there the same
layout lives under `user://battle_output/`. Probe fixtures are not battle
output: they stay in memory or under `user://`.

## Exporting a map's battle products without the editor

`scripts/worldmap_editor/export_battle_products.gd` publishes an authored hex
map's battle products the same way the editor's own Export Battle action does,
without opening the editor:

```powershell
./Godot_v4.4-stable_win64.exe --headless --path . --script scripts/worldmap_editor/export_battle_products.gd -- hexmap
```

The argument is a map id under `data/worldmap/authored/<id>.noggmap.json` — the
versioned envelope format the editor's own Save/Save As write. It reads that
one format only; a pre-migration bare `.json` region such as `proving_ground`
predates the envelope and is out of scope for this script, the same as it is
for the editor's own Open dialog.

It runs `godot --headless --import --path .` itself between baking and
exporting, so the command above really is the whole thing — no separate import
step to remember. That nested pass logs its own `ERROR: Do not use progress
dialog...` lines to stderr; this is the same headless-import noise named above,
not a sign the export failed. Trust the exit code and the final
`HEX_EXPORT_OK <mapID>` line.

**Re-exporting an already-scenario'd map makes those scenarios stale.**
`BattleScenarioFactory` refuses to load a scenario whose recorded map
fingerprint no longer matches — correct behaviour, not a bug — and the command
prints a reminder naming every scenario under `data/battle/scenarios` that
needs its `MAP` block updated to match.

## Validation timing

AGENTS.md governs, and this section is subordinate to it. Plan files are frozen
once a cycle opens, so there is no "Resolution" field to update: an item's
evidence lives in its own commit body, ending with its `Plan-Item:` trailer.

Each item runs its OWN self-contained checks -- the ones its plan entry names --
before committing. What is deferred to the validation item is only what cannot
be established without launching the game: appearance, timing, feel, and
integration across subsystems. Deferring a check the item could have run itself
is not permitted.

The plan's final validation item launches the game once all implementation
items are committed. It exercises the combined affected paths, deduplicates
overlapping checks, fixes any integration defect it finds, and changes covered
items from pending validation to done. A narrow compile/load smoke probe is
allowed earlier only when a later item cannot safely proceed against code that
might not parse; it is not acceptance evidence.

A single-item plan performs its manual validation at the end of that item.

## Windows execution safeguards

These apply whenever you launch the bundled Godot binary or generate edits
through nested Windows tooling:

- Do not treat `$LASTEXITCODE` from a direct interactive launch of the bundled
  Windows Godot binary as completion evidence. The host can return before the
  detached process finishes. Wait for the exact process and require a known
  output/log marker.
- Run from the repository root and pass `--path .`; PowerShell argument handling
  can split absolute paths containing spaces.
- Godot writes logs and caches under AppData. If the sandbox reports AppData
  access failures or an access-violation exit, rerun the same bounded command
  with the required permission before diagnosing project code.
- Treat `--editor --quit` as an import diagnostic, not a runtime smoke test. It
  can hit progress-dialog or message-queue errors during import.
- If the patch helper reports an infrastructure error such as
  `windows sandbox failed: helper_unknown_error`, inspect the target immediately
  and stop retrying the same path. After confirming the file is unchanged, use
  one exact, asserted workspace-scoped replacement and review its focused diff.
- Do not generate a `git diff --no-index` patch against a temp file outside the
  repository on Windows: the diff can contain an absolute drive path that
  `git apply` rejects. Keep any fallback temp next to the target or avoid that
  route.
- Avoid inline source generation across JavaScript, PowerShell, and Python when
  the payload contains escape sequences. Outer layers can consume `\"`,
  `\n`, or `\t` before the inner language sees them. Prefer a short temporary
  helper file, single-quoted diagnostics, and character APIs such as
  `[char]10` / `chr(10)`.
- Force generated text to LF. PowerShell and Python on Windows can translate
  line endings to CRLF, which this repository's `git diff --check` reports as
  trailing whitespace. In Python, open with `newline=chr(10)`; in PowerShell,
  normalize before `WriteAllText`.
- Keep native process windows hidden unless the user needs to interact with
  them. Keep reusable logs in the temp directory rather than tracked source.
- Workspace edit permission does not imply permission for external executables
  or Git index writes; honor the permission boundary shown by the tool.

## Failure-triage order

1. Classify the failure as project code, sandbox/permission, process waiting,
   patch infrastructure, or multi-layer quoting before changing source.
2. Inspect the intended target and `git status`; do not assume a failed helper
   either changed nothing or completed successfully.
3. Change execution strategy once. Repeatedly trying equivalent patch/temp/
   launch variants creates more uncertainty than evidence.
4. After the environment is trustworthy, capture the originating parser/runtime
   error from Godot's output or AppData log and fix that exact defect.
5. Run the relevant validation only at the plan's final validation boundary.

## Implementation-item checkpoint

1. Run the item's own self-contained checks and record their results.
2. Inspect `git status` and the focused diff over the item's owned paths.
3. Run `git diff --check`.
4. Stage only task-owned files and commit the item, with implementation,
   assumptions found false, intentional exclusions, commands and results, and
   any deferred check in the body, ending with `Plan-Item: <id>`.

## Final validation checklist

1. Start from all implementation items committed and a clean working tree.
2. Launch the game through a bounded, waited process.
3. Exercise the union of affected behavior once, using integrated flows where
   possible.
4. Fix and rerun only the failed/relevant combined checks.
5. Run `git diff --check` and commit the validation evidence and fixes.
