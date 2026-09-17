# Agent test gates

2026-09-17. This cycle closes four gaps between how agents check Road of Nogg
and how turn-based tactics games are usually tested by machines. The probes
exist but nothing runs them together, so an old probe can break unnoticed. The
simulator never checks its own state, so a thousand simulated battles prove
only that nothing crashed. Every CPU brain is deterministic, so a championship
replays nearly the same fight. And the worldmap docs cite about thirty probes
as their proof, but those probes live in `debug/`, which `.gitignore` excludes,
and a third of them cannot fail. This cycle is not a return of the removed
GUT suite, not CI or git hooks, and not balance work.

## Outcome

- One command, `scripts/checks/run_probe_sweep.ps1`, runs every registered
  probe and ends with `PROBE_SWEEP_OK` or `PROBE_SWEEP_FAILED <n>`. Probes that
  fail today are quarantined in their manifest with a reason, not hidden.
- The battle simulator can check its invariants after every resolved step. The
  headless runners turn that check on, and a probe proves it catches a
  corrupted state.
- A random-legal brain can drive any team in `run_battle.gd` and
  `run_championship.gd`, and a fuzz probe runs it across the CPU-vs-CPU
  scenarios.
- Every worldmap probe that a design doc cites as proof is tracked in Git and
  can fail, or the doc stops claiming it is checked.

## Present-state facts an executing agent must not "fix"

- **`/debug/` is gitignored** (`.gitignore` line 24). Moving a file out of it
  shows up as a new file only; there is no `git mv` and nothing to delete in
  Git.
- **Some registered probes may fail at your revision.** ATG-1 and ATG-6
  quarantine them with a reason. They do not repair probes or product code.
  Another session's in-flight edits can be the cause; record that and move on.
- **`scripts/hex_battle/probe_runner_failure.gd` is meant to fail.** It is the
  runner's negative control and is registered with `"expect": "fail"`.
- **Marker names in old plan files have drifted from the probes.**
  `hex-battle-playability-restoration.md` names `HPR_INSPECTION_OK`; the probe
  prints `HXB_INSPECT_OK`. The probe's own `print` is the truth.
- **`run_probe.ps1` requires a marker.** A zero exit code alone is not
  evidence on this Windows host (`docs/DEVELOPMENT.md`).
- **Seeds barely change a battle today** (`docs/DEVELOPMENT.md`). Under the
  random-legal brain they will change a lot. That is the point, not a
  regression.
- **The championship summary is non-deterministic by design** (wall-clock
  timings). Only the JSONL corpus is byte-identical, and
  `probe_battle_runner.gd` must keep passing unchanged.

## Items

### ATG-1 — Register every tracked probe and add one sweep command

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** The manifest schema, the runner's parameters and output
lines, the quarantine rule and the exact doc wording are all fixed below. The
work is a file walk, copying markers verbatim, and a PowerShell loop that
mirrors an existing script. Nothing in it is a design call.

**Depends on:** none.

**Touches:**
- `scripts/checks/run_probe_sweep.ps1` (new)
- `scripts/checks/probes/hex_battle.json` (new)
- `scripts/checks/probes/battle.json` (new)
- `scripts/checks/probes/worldmap_editor.json` (new)
- `AGENTS.md`, section "Running the checks" only
- `docs/DEVELOPMENT.md`, section "No automated test suite right now" only
- `docs/POLICIES.md`, section "Risk-based verification", first paragraph only
- `BACKLOG_CRITICAL.md` (append one entry)

**End state:**
- Each manifest is a JSON object `{"probes": [...]}`. Each entry has exactly
  these keys:
  `{"script": "res://…/probe_x.gd", "marker": "LITERAL_MARKER", "timeout": 120, "expect": "pass", "gate": true, "renderer": false, "note": ""}`.
  - `expect` is `"pass"` or `"fail"`.
  - `gate: false` means quarantined, and `note` then gives the reason.
  - `renderer: true` means the sweep skips the entry.
- `hex_battle.json` lists every `probe_*.gd` under `scripts/hex_battle/`,
  including `side_turn/` and `restoration/`. `battle.json` lists
  `scripts/battle/checks/probe_*.gd`. `worldmap_editor.json` lists every
  `probe_*.gd` under `scripts/worldmap_editor/`, **excluding**
  `scripts/worldmap_editor/checks/editor/` (ATG-4 creates and registers it).
  List only files that exist at your base revision.
- `probe_runner_failure.gd` is registered with marker `HXB_RUNNER_FAILURE` and
  `"expect": "fail"`.
- `run_probe_sweep.ps1` takes `[string]$Filter = ''` (substring matched against
  `script`) and `[string]$ManifestDirectory = 'scripts/checks/probes'`. It
  reads every `*.json` in that directory and fails before running anything if a
  `script` file is missing or the same `script` appears twice. It then runs the
  entries one at a time, in manifest order, through
  `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/hex_battle/run_probe.ps1 -Script <script> -Marker <marker> -TimeoutSeconds <timeout>`.
- It prints one line per entry:
  `PASS|FAIL|QUARANTINED-PASS|QUARANTINED-FAIL|SKIP <script> <seconds>s`.
  An `expect: "fail"` entry counts as PASS when `run_probe.ps1` exits 1.
- Its last line is `PROBE_SWEEP_OK <passed>/<gated>` with exit 0 when every
  `gate: true` entry met its `expect`. Otherwise the last line is
  `PROBE_SWEEP_FAILED <n>` with exit 1. Quarantined and skipped entries never
  change the exit code.

**Implementation:**
- Mirror `scripts/hex_battle/run_probe.ps1` for the `[CmdletBinding()]` param
  block, `$ErrorActionPreference = 'Stop'` and the try/catch shape. Do not
  modify `run_probe.ps1`.
- **Marker:** copy it literally from the probe's own success `print(...)`.
  Never take it from a plan or doc. A probe with no success print is not
  registered; name it in the commit body.
- **Timeout:** start at 120. If a probe times out, set 300 and run it once
  more. If it times out again, set `gate: false` with
  `note: "timed out at 300s"`.
- **Quarantine:** run the full sweep once. Any gated probe that does not meet
  its `expect` gets `gate: false`, and its `note` is the first line of that
  run's stderr log (`run_probe.ps1` prints the log path). Record
  `git status --short` before and after the sweep. If a failing probe's
  imports overlap paths another session has modified, add
  `"; in-flight: <paths>"` to the note.
- **Probes that write into the repo:** compare the before and after
  `git status --short`. A tracked or new file outside `battle_output/` and
  `debug/` that the sweep created means that probe gets `gate: false` with
  `note: "writes <path>"`. Restore only that path with
  `git restore --source=HEAD -- <path>`, or delete the new file.
- **Backlog:** append one entry to `BACKLOG_CRITICAL.md` titled
  `Quarantined probes (ATG-1)`, listing each quarantined script and its note.
  Skip the entry if nothing was quarantined.
- **Docs, exact wording.** In `AGENTS.md` "Running the checks", replace the
  sentence `There is no automated test suite, check runner, or git hooks.` with:
  `There is no test suite or git hooks. scripts/checks/run_probe_sweep.ps1 runs every probe registered under scripts/checks/probes/. Run it with -Filter on your area when your item changes code a registered probe loads, and in full in a cycle's last item. An item that adds a probe registers it in a manifest in the same commit.`
  Make the matching one-paragraph change in `docs/DEVELOPMENT.md` "No
  automated test suite right now", with the command written out, and in the
  first paragraph of `docs/POLICIES.md` "Risk-based verification". Nothing else
  in those files.
- **Do not:** fix a failing probe, edit any probe script, register anything
  under `debug/`, or parallelise the sweep.

**Risk:** a probe that silently depends on another session's half-finished work
gets quarantined for the wrong reason. The in-flight note and ATG-6's re-run
cover it.

**Validation:**
- Self-contained: run
  `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1`
  and paste its final line plus the QUARANTINED lines into the commit body.
  Run it again with `-Filter probe_runner_` and confirm `PROBE_SWEEP_OK 2/2`.
  Temporarily point a scratch copy of one manifest at a missing script (in
  the scratchpad, via `-ManifestDirectory`) and confirm the sweep refuses to
  start. Run `git diff --check`.

### ATG-2 — Check battle invariants after every resolved step

**Model:** Opus 5 / GPT Sol

**Model rationale:** This adds a new seam to the one canonical simulator. The
session has to decide where the check hooks in, what counts as a step, how a
violation surfaces in the interactive game versus a thousand-battle
championship, and which rules are true invariants rather than current
behaviour. Getting that wrong either misses real bugs or breaks the
determinism contract.

**Depends on:** none.

**Touches:**
- `src/battle_sim/BattleInvariants.gd` (new)
- `src/battle_sim/BattleSimulator.gd`
- `scripts/battle/run_battle.gd`
- `scripts/battle/run_championship.gd`
- `scripts/battle/checks/probe_invariants.gd` (new)
- `scripts/checks/probes/invariants.json` (new, ATG-1 schema)
- `docs/ARCHITECTURE.md` (one new section)

**End state:** the headless runners check a stated set of battle invariants
after every resolved simulator step. A violation cannot pass silently in a
single battle or in a championship. `probe_invariants.gd` passes on the
authored scenarios and fails, with its negative control, on a deliberately
corrupted state. `probe_battle_runner.gd` still passes unchanged.

**Brief:**
- **Problem.** Championships and probes today fail only on crashes, script
  errors or wrong markers. A move onto an occupied hex, a clock that ticks
  twice, or a spent unit acting again produces a perfectly valid-looking
  record. The genre's standard answer is an invariant pass after every action.
  It turns every simulated battle, including ATG-3's random ones, into a test.
- **Where the rules live.** `docs/GAME_DESIGN.md` "Sides, rounds, and unit
  actions" and "Defeat, withdrawal, and battle outcome" are the contract. The
  candidates include:
  - one unit per cell
  - HP within 0..max
  - dead or withdrawn units off the board or at (-1, -1), as the design states
  - spent units neither move nor act
  - magic is never resolved after a move
  - status durations and cooldowns advance exactly once per unit resolution
  - victory is checked before another unit is selected
  - the active side is the lowest surviving team ID not yet taken this round

  Choosing the final list is the session's call. A rule the code does not
  actually hold is a finding to report, not something to weaken until it
  passes.
- **Existing context.** `src/entity_ai/StateRevision.gd` already talks about
  invariants and a ledger. Read it before inventing a parallel concept.
  `BattleSimulator.gd` exposes the step boundaries: `executeMovePhase`,
  `undoMovePhase`, `executeActionPhase`, `finishTurn`, `endSideTurn`,
  `executeCommand` and `startNextSideTurn`.
- **Invariants that must survive:**
  - Records stay byte-identical: no new record fields, no version bump.
  - The check emits no `BattleEvents` and mutates no state.
  - `src/battle_sim` stays headless.
  - The side-turn rules in `docs/HEX_BATTLE.md` are unchanged.
- **Tension.** A thorough check per step may cost real throughput on a
  1000-battle championship. The interactive game may or may not want it on.
  Measure championship time on 100 seeds of `proving_ground_cpu_cpu.json`
  before and after, and record both. Decide whether the check is always on,
  on in the headless runners only, or behind a flag, and say why.
- **Failure behaviour is the session's call.** A championship may stop the
  run, or end that battle and mark it. It must not keep producing records
  from a broken state without a trace.
- **The probe must be able to fail.** `docs/WORLDMAP_DESIGN.md` §11 records
  three probes that passed while measuring nothing. Include a negative
  control that corrupts a state and asserts that each invariant family
  reports it. The success marker is `BATTLE_INVARIANTS_OK`.
- **Do not** fix a rule bug the check uncovers. Name it in the commit body,
  with the scenario, seed and step, so Henri can route it.

**Risk:** hooking the wrong boundary checks mid-resolution states and reports
false violations. Throughput loss can make championships impractical.

**Validation:**
- Self-contained: run `probe_invariants.gd` and `probe_battle_runner.gd` through
  `run_probe.ps1` with their markers. Run `probe_round_cap.gd`,
  `probe_playthrough.gd` and `probe_replay.gd` too, because they share the
  simulator. Run the non-interactive Godot check from `AGENTS.md`. Put the
  before/after championship timings, the final invariant list and the
  failure-behaviour decision, with its reasoning, in the commit body.

### ATG-3 — Add a random-legal brain for fuzzing, selectable per run

**Model:** Opus 5 / GPT Sol

**Model rationale:** The brain has to plug into the deliberation seam without
breaking determinism. It has to cover the whole side-turn legal surface, not
just attack-or-move. The run-time override also has to be designed so random
corpora can never be mistaken for policy corpora. Those are interface and
data-contract decisions, not a fill-in.

**Depends on:** ATG-1 (owns `docs/DEVELOPMENT.md` in wave 1) and ATG-2 (shares
the simulator and runners; its invariants are what the fuzz run checks).

**Touches:**
- `src/entity_ai/RandomLegalBrain.gd` (new)
- `src/battle_sim/BattleSimulator.gd` (`_resolveBrainClass` and brain wiring only)
- `scripts/battle/run_battle.gd`
- `scripts/battle/run_championship.gd`
- `scripts/battle/checks/probe_fuzz.gd` (new)
- `scripts/checks/probes/fuzz.json` (new, ATG-1 schema)
- `docs/DEVELOPMENT.md`, section "Simulating battles headlessly, and recording them" only

**End state:** `run_battle.gd` and `run_championship.gd` can put chosen teams
under a random-legal brain. Two runs at one seed still produce byte-identical
corpora. `probe_fuzz.gd` (marker `BATTLE_FUZZ_OK`) plays many random battles
across every `*_cpu_cpu.json` scenario and requires that:
- every battle ends by elimination or at the round cap
- invariants are never violated
- there are no script errors
- one repeated seed reproduces byte for byte

**Brief:**
- **Problem.** `docs/DEVELOPMENT.md` records that twenty seeds gave five decision
  sequences and five seeds gave one. The only randomness is the crit roll and
  every brain is deterministic. Championships therefore explore almost nothing,
  and the side-turn edge cases are barely exercised: undo, waits, End turn with
  ready units, a commander falling mid-turn. Random legal play is the genre's
  cheapest fuzzer.
- **Existing seams.** `EntityBrain.beginDeliberation` returns a
  `CommandDeliberation`, and `PartyCommandDeliberation` drives a side.
  `BattleSimulator._rebuildRuntimeDependencies` already accepts a
  `brainClasses` dictionary keyed by monster ID, and snapshots serialize it.
  The corpus already records which brain drove each member. Prefer those over
  a scenario format change.
- **Invariants:**
  - All randomness comes from the simulator's seeded RNG, never global
    `randi`.
  - Only commands the simulator and `ReachQuery` accept are chosen.
  - Default-brain corpora are unchanged, so `probe_battle_runner.gd` passes
    as-is.
  - A corpus line makes it obvious that a random brain played.
- **Decisions that are the session's:**
  - the command-line shape of the override (per team, per scenario)
  - whether the brain weights operations to reach rare paths (undo, End
    turn) or samples uniformly
  - whether an epsilon-greedy variant earns its place now
  - how many battles fit the probe's timeout

  Explain each in the commit body.
- **Out of scope.** Drawing balance conclusions from random corpora. Random
  play measures robustness, not balance; balance stays Henri's call.

**Risk:** a random brain that picks only from a subset of legal operations
looks like coverage without being it. Count operation kinds per corpus and
report them. Unseeded randomness would break the byte-identical guarantee.

**Validation:**
- Self-contained: run `probe_fuzz.gd`, `probe_invariants.gd`,
  `probe_battle_runner.gd` and `probe_ai.gd` through `run_probe.ps1`. Run one
  100-seed random championship on `proving_ground_cpu_cpu.json`. Record its
  winners, end reasons, distinct decision sequences and operation-kind counts
  in the commit body. Run the non-interactive Godot check.

### ATG-4 — Move the twenty failable, doc-cited worldmap probes into Git

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** The file list, destinations, marker format and path
rewrite rule are all fixed below. The work is moving files, adding one
success print per file, and replacing path strings. No probe logic or
threshold changes.

**Depends on:** none (the manifest schema is ATG-1's, spelled out there).

**Touches:**
- `debug/worldmap/` — the twenty `.gd` files below, their `.gd.uid` files, and
  `debug/worldmap/validation/**` files those twenty read
- `scripts/worldmap/checks/**` (new)
- `scripts/worldmap_editor/checks/editor/**` (new)
- `scripts/checks/probes/worldmap.json` (new)
- `docs/WORLDMAP_DESIGN.md` and `docs/WORLDMAP_EDITOR.md`, path mentions of the
  twenty probes only

**End state:**
- These thirteen move from `debug/worldmap/` to
  `scripts/worldmap_editor/checks/editor/`, each `.gd` together with its
  `.gd.uid`: `probe_bake_parity`, `probe_brushes`, `probe_edit_history`,
  `probe_editor_input_dispatch`, `probe_editor_tools`, `probe_height_field`,
  `probe_hex_grid_overlay`, `probe_object_layer`, `probe_scene_export`,
  `probe_subtriangles`, `probe_tile_format`, `probe_tileset_ids`,
  `probe_water_layer`.
- These seven move to `scripts/worldmap/checks/`: `probe_cloud_art`,
  `probe_cloud_field`, `probe_cloud_on_props`, `probe_clouds`,
  `probe_editor_camera`, `probe_tile_law`, `probe_validation`.
- No moved file contains `res://debug`.
- Each moved probe prints `WORLD MAP <NAME> OK` on its success path only.
  `<NAME>` is the file name without `probe_`, upper-cased, with `_` as
  spaces, e.g. `WORLD MAP BAKE PARITY OK`. The style mirrors
  `scripts/worldmap_editor/checks/tilesets/probe_tileset_configs.gd`.
- All twenty are registered in `scripts/checks/probes/worldmap.json` using
  ATG-1's schema.
- Neither doc names `debug/worldmap/` for any of the twenty.

**Implementation:**
- **Moving:** move the files (they are untracked, so this is a plain move). Do
  not change any check, threshold or measured value.
- **Success print:** add the print immediately before the probe's success
  exit, guarded by the same failure condition its `quit(...)` already uses. For
  example, `quit(1 if _failures > 0 else 0)` becomes
  `if _failures == 0: print("WORLD MAP … OK")` followed by the unchanged
  `quit`.
- **`res://debug/worldmap/validation/…` paths:** if the probe writes the file
  before any read of it, the path becomes
  `user://probe_scratch/worldmap/<same file name>`. Make the directory with
  `DirAccess.make_dir_recursive_absolute`. If the probe only reads it, copy the
  file into a `fixtures/` folder beside the moved probe and point the path
  there. `probe_validation.gd` references the directory itself; apply the same
  rule to each file it reads or writes.
- **Registering:** run each probe once through `run_probe.ps1` with
  `-TimeoutSeconds 120`.
  - Passes: `gate: true`.
  - Fails, and it is one of `probe_clouds`, `probe_tileset_ids`,
    `probe_cloud_on_props` or `probe_validation` (they read viewport
    textures): `renderer: true`, with the first stderr line as `note`.
  - Any other failure: `gate: false`, with the first stderr line as `note`.
- **Docs:** replace only the `debug/worldmap/` path of the twenty in the two
  docs. §11's opening sentence and table belong to ATG-5; leave them alone
  apart from path strings for the seven.
- **Do not** touch the ten other cited probes (`probe_allpresets`,
  `probe_lamps`, `probe_prop_fog`, `probe_prop_layer`, `probe_props`,
  `probe_segmentation_limits`, `probe_shadow_look`, `probe_shadows`,
  `probe_sun`, `probe_tree_key`). Do not touch any other `debug/` file, or
  `scripts/checks/probes/` files other than `worldmap.json`.

**Risk:** a probe that silently relied on a debug-only asset now fails. The
first-run registration surfaces it as a quarantine with its stderr line.

**Validation:**
- Self-contained: grep that no file under `scripts/worldmap/checks/` or
  `scripts/worldmap_editor/checks/editor/` contains `res://debug`. Grep that
  neither doc mentions `debug/worldmap/probe_` for the twenty. Put each probe's
  registration result in the commit body. Run `git diff --check`.

### ATG-5 — Make the ten un-failable worldmap probes fail, or retract their claims

**Model:** Opus 5 / GPT Sol

**Model rationale:** Every probe needs a judgement. Is the claim it backs still
true? Can it be measured? What threshold, taken from the doc rather than
today's output, makes a real failure visible? The alternative is to downgrade
the doc's wording, which is an editorial call on a design document.

**Depends on:** ATG-4 (shares `docs/WORLDMAP_DESIGN.md` and `scripts/worldmap/checks/`).

**Touches:**
- `debug/worldmap/` — `probe_allpresets`, `probe_lamps`, `probe_prop_fog`,
  `probe_prop_layer`, `probe_props`, `probe_segmentation_limits`,
  `probe_shadow_look`, `probe_shadows`, `probe_sun`, `probe_tree_key`
  (`.gd` and `.gd.uid`)
- `scripts/worldmap/checks/` — those ten file names and `fixtures/` entries
  they add
- `scripts/checks/probes/worldmap_design.json` (new)
- `docs/WORLDMAP_DESIGN.md` §9–§11

**End state:** each of the ten either lives tracked in `scripts/worldmap/checks/`,
exits non-zero when its claim is false, prints `WORLD MAP <NAME> OK` on success
and is registered, or stays in `debug/` while §11 stops listing it as a check.
§11's opening sentence is true as written.

**Brief:**
- **Problem.** §11 says every claim in §9 and §10 "is checked by a probe…
  written so it can fail". It also records three probes that passed while
  measuring nothing. Ten of the cited probes end with a bare `quit()` and can
  never fail. The rendering-rig claims they back (sun elevation, shadow feet,
  prop fog, lamp shapes, palette modes) are the kind that drift silently.
- **Constraints.**
  - Thresholds come from the numbers §9–§11 state, not from re-running and
    copying today's output. A probe that cannot fail on a deliberately broken
    input is not done.
  - Do not change rendering, shader or worldmap code to make a check pass. A
    claim that is no longer true is a finding for the commit body and the doc.
  - Renderer-bound probes may run as a scripted, non-interactive window, one
    process per capture (`docs/LEARNINGS.md`, "Capturing a second screenshot
    in one running process returns a stale image"). Register them with
    `renderer: true`.
  - Follow ATG-4's conventions for markers, `user://probe_scratch/` scratch
    output and fixtures.
- **The session's call, per probe:** convert, or retract the claim. Put the
  reasoning in the commit body.

**Risk:** a threshold tuned to current output turns the probe into a snapshot
that fails on any legitimate art change. Stating the doc's number next to each
threshold keeps it honest.

**Validation:**
- Self-contained: run each converted probe through `run_probe.ps1`, and show
  each failing once on a broken input (describe how in the commit body). Grep
  that §11 lists no `debug/` probe as a check.

### ATG-6 — Run the full sweep and release quarantines that now pass

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** This is one command and one fixed rule applied per
manifest entry. No judgement is needed, and every result goes verbatim into
the commit body.

**Depends on:** ATG-1, ATG-2, ATG-3, ATG-4, ATG-5.

**Touches:**
- `scripts/checks/probes/*.json` (the `gate` and `note` fields only)
- `BACKLOG_CRITICAL.md` (the `Quarantined probes (ATG-1)` entry only)

**End state:** a full sweep at this revision has been run. Every entry with
`gate: false` that meets its `expect` in that sweep is set to `gate: true` with
`note: ""`. The backlog entry lists exactly the probes still quarantined, or is
removed if none are.

**Implementation:** run
`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1`,
flip the entries marked `QUARANTINED-PASS`, and run it again. Do not set any
passing gated probe to quarantined, do not edit probes or product code, and do
not change `timeout`, `marker` or `renderer`.

**Risk:** none beyond a flaky probe flipping twice. Report any probe whose
result differs between the two runs.

**Validation:**
- Self-contained: paste both sweeps' final lines and every QUARANTINED line
  into the commit body.

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | ATG-1, ATG-2, ATG-4 | sweep, manifests and verification docs vs. simulator, battle runners and ARCHITECTURE.md vs. worldmap probes and worldmap docs; each writes its own manifest file |
| 2 | ATG-3, ATG-5 | simulator, runners and DEVELOPMENT.md vs. the other ten worldmap probes and WORLDMAP_DESIGN.md |
| 3 | ATG-6 | alone; reads every manifest after all probes exist |
| — | validation: inline, no deferred checks | every check is a headless or scripted probe run recorded in its item's commit |

## Deliberately excluded

- Rebuilding a GUT or GdUnit4 suite, CI, or git hooks. The sweep is the gate
  for now.
- Balance conclusions from random-brain corpora, or a mixed-brain balance
  report. That is a design cycle of its own.
- Visual goldens for the battle HUD. `probe_ui_guardrails.gd` and the VFX
  golden rules already cover what is checked today.
- Anything about the square battle.
- The roughly thirty-five `debug/` scripts no doc cites (proofs, shots,
  prototypes). They are scratch by design.
- Running probes in parallel.
